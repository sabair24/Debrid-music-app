/// Gelijk volume: elk nummer even hard, zonder dat er iets aan het geluid zelf verandert.
///
/// **Waarom dit bestaat.** Saber op 07-10-2026: *"hoe we het volume over alle liedjes gelijk kunnen
/// krijgen, maar dit zonder enige verlies van kwaliteit en ook dat de liedjes zeker niet te still
/// worden."* Gemeten op een steekproef van 149 nummers uit zijn bibliotheek (EBU R128): de luidheid
/// loopt van −23,3 tot −4,7 LUFS, en tussen het 10e en het 90e percentiel zit 8,8 dB. In shuffle en
/// radio springt een moderne master dus 6 tot 9 dB boven een oude of dynamische opname uit.
///
/// **Wat hier wel en niet gebeurt.** Eén VASTE versterking per nummer (of per plaat), toegepast door
/// mpv op dezelfde plek als zijn volume. Geen compressor, geen begrenzer, geen dynamische
/// normalisatie: dynamiek, transiënten en klankkleur blijven precies zoals ze zijn. Dat heeft een
/// prijs, en die staat hier eerlijk: zonder begrenzer kan een zacht nummer alleen omhoog zolang zijn
/// pieken dat toelaten. 82 van de 149 gemeten nummers zitten al boven 0 dBTP. Gelijk komt dus vooral
/// van luide nummers zachter zetten.
///
/// **Deze hele rekensom is zuiver.** Geen schijf, geen netwerk, geen Flutter — de beslissing waar een
/// fout niet omvalt maar stil verkeerd klinkt, hoort in een toets te passen. Zie
/// `test/luidheid_test.dart`. Het plan dat door drie beoordelaars unaniem is goedgekeurd staat in de
/// commitboodschap; de getallen hieronder komen daaruit.
library;

import 'dart:math' as math;

/// De drie standen. Bewaard als tekst, net als elke andere keuze in [AppSettings].
enum Luidheidsstand { uit, normaal, luid }

Luidheidsstand luidheidsstandUit(String? naam) => switch ((naam ?? '').trim()) {
      'uit' => Luidheidsstand.uit,
      'luid' => Luidheidsstand.luid,
      // Onbekend of leeg is de standaard: een instellingenbestand van een andere versie mag nooit
      // stilletjes alles uitzetten.
      _ => Luidheidsstand.normaal,
    };

/// Het doelniveau in LUFS.
///
/// **−14 is het niveau van Spotify (standaard), TIDAL, YouTube en Amazon.** "Niet te stil" betekent
/// hier: even hard als wat je daar gewend bent. In deze bibliotheek valt −14 precies op het 25e
/// percentiel, dus driekwart van de nummers hoeft alleen zachter (dat kan altijd verliesloos) en een
/// kwart zou omhoog moeten (dat kan alleen zover de pieken het toelaten). Gesimuleerd: 85 % binnen
/// 1 dB van het doel, restspreiding 1,9 dB (was 8,8), mediane verandering −3,3 dB.
///
/// **−11 ("Luider") is gemiddeld even hard als vroeger** (mediane verandering 0,0 dB): alleen de
/// uitschieters gaan omlaag. Minder gelijk (60 % binnen 1 dB), want zachte opnames kunnen zonder
/// begrenzer niet mee omhoog.
double doelVoor(Luidheidsstand s) => s == Luidheidsstand.luid ? -11.0 : -14.0;

/// Hoe ver een ophoging mag gaan: de ware piek eindigt op hooguit −1 dBTP. DAC-reconstructie,
/// Bluetooth (SBC/AAC/LDAC) en Android Auto coderen opnieuw; AES TD1004 en EBU R128 s1 noemen −1.
const double kPiekPlafond = -1.0;

/// Elke versterking ≠ 0 eist dat de piek daarna op hooguit −0,5 dBTP staat.
///
/// **Waarom dit er is, ook bij ZACHTER zetten.** mpv tot en met 0.37 — en dat zijn alle drie de
/// gebundelde builds (Windows git 652a1dd, Android 0.35.1, Apple 0.36.0) — knipt bij elke versterking
/// ≠ 1 elk float-monster boven 1,0 hard af (`MUL_GAIN_f … MPCLAMP(…, -1.0, 1.0)`, audio/out/ao.c).
/// Na de herbemonstering naar de mengfrequentie van Windows, of uit een mp3-decoder, ZIJN er monsters
/// boven 1,0: gemeten op een 16/44,1-bron met ware piek +3,6 → +3,1 dBFS na aresample=48000. Met
/// versterking 0 vermenigvuldigt mpv niets en knipt hij niets (ao.c: `if (gi == 256) return;`), en
/// dat is precies vandaag.
const double kKlemMarge = -0.5;

/// Vangnet tegen een meetfout. De grootste ophoging die deze bibliotheek nodig heeft is +9,3 dB.
const double kMaxOphoging = 10.0;

/// Stilte of een verborgen nummer: niets opblazen. ffmpeg geeft −70 LUFS bij stilte of invoer korter
/// dan 0,4 s.
const double kStilteGrens = -50.0;

/// Kleiner dan dit is onhoorbaar, en 0 houdt het nummer bit-gelijk aan vandaag.
const double kNulDrempel = 0.05;

/// `Peak: -inf dBFS` (stilte) wordt dit, want JSON kent geen oneindig — en een catalogus met één
/// oneindig getal erin breekt voor álle toestellen (jsonEncode gooit).
const double kPiekOndergrens = -200.0;

/// Wat er van één nummer gemeten is: geïntegreerde luidheid (LUFS) en de hoogste piek (dBTP).
class Luidheidsmeting {
  final double lufs;

  /// max(monsterpiek, ware piek) + 0,05 (ffmpeg drukt af op één decimaal).
  final double piek;

  const Luidheidsmeting({required this.lufs, required this.piek});

  /// Alleen met twee eindige getallen; alles anders is "geen meting" — en geen meting is 0 dB.
  static Luidheidsmeting? fromJson(Object? j) {
    if (j is! Map) return null;
    final i = j['i'], tp = j['tp'];
    if (i is! num || tp is! num) return null;
    final lufs = i.toDouble(), piek = tp.toDouble();
    if (!lufs.isFinite || !piek.isFinite) return null;
    return Luidheidsmeting(lufs: lufs, piek: piek);
  }

  Map<String, dynamic> toJson() => {
        'i': _afgerond(lufs, 1),
        'tp': _afgerond(piek, 2),
      };

  @override
  bool operator ==(Object other) =>
      other is Luidheidsmeting && other.lufs == lufs && other.piek == piek;

  @override
  int get hashCode => Object.hash(lufs, piek);

  @override
  String toString() => 'Luidheidsmeting(${lufs.toStringAsFixed(1)} LUFS, ${piek.toStringAsFixed(2)} dBTP)';
}

double _afgerond(double v, int decimalen) {
  if (!v.isFinite) return kPiekOndergrens;
  final f = math.pow(10, decimalen).toDouble();
  return (v * f).roundToDouble() / f;
}

/// Wat een meting heeft opgeleverd.
sealed class Luidheidsuitslag {
  const Luidheidsuitslag();
}

class Gemeten extends Luidheidsuitslag {
  final Luidheidsmeting meting;
  const Gemeten(this.meting);
}

/// Meer dan twee kanalen. **Er worden geen getallen bewaard of verstuurd**, zodat geen enkel toestel
/// er een versterking op kan zetten: mpv mengt zo'n nummer op een stereo-uitgang terug (Android altijd,
/// ao_opensles.c:113) zonder normalisatie (rematrix_maxval 1000), en dan ligt de echte piek tot ~7,6 dB
/// boven de gemeten piek per kanaal — gemeten met een coherente 5.1-toon: −0,9 → +6,7 dBFS.
class Meerkanaals extends Luidheidsuitslag {
  final int kanalen;
  const Meerkanaals(this.kanalen);
}

class Mislukt extends Luidheidsuitslag {
  final String reden;

  /// Geen oordeel over het BESTAND: ffmpeg startte niet, of het bestand was even vergrendeld. Zo'n
  /// uitslag wordt niet bewaard; de volgende ronde probeert het opnieuw. Bewaard "kon niet meten"
  /// komt pas terug als het bestand zelf verandert.
  final bool tijdelijk;
  const Mislukt(this.reden, {this.tijdelijk = false});
}

/// Wat er in de stderr van `ffmpeg -af ebur128=peak=sample+true` staat.
typedef Ebur128Uitvoer = ({double? lufs, double? monsterpiek, double? warePiek, int? kanalen, int? frequentie});

final _invoerBegin = RegExp(r'^Input #0', multiLine: true);
final _uitvoerBegin = RegExp(r'^Output #0', multiLine: true);
final _hz = RegExp(r'\b(\d{4,7}) Hz\b');
final _audiostroom = RegExp(r'^\s*Stream #0:\d+[^:]*: Audio: (.*)$', multiLine: true);

/// Leest de samenvatting van ebur128, en het aantal kanalen en de bemonsteringsfrequentie van de eerste
/// geluidsstroom.
///
/// Drie vormen van de streamregel, alle drie gezien op Sabers pc:
///
///     Stream #0:0: Audio: flac, 44100 Hz, stereo, s16
///     Stream #0:0: Audio: ape (APE  / 0x20455041), 192000 Hz, stereo, s32p (24 bit)
///     Stream #0:0[0x1](und): Audio: aac (LC) (mp4a / 0x6134706D), 44100 Hz, stereo, fltp, 256 kb/s
///
/// Alleen de regel onder `Input #0`: een M4A met hoes heeft ook een `Video: mjpeg`-stroom, en het
/// uitvoerblok herhaalt de indeling.
Ebur128Uitvoer leesEbur128(String stderr) {
  int? kanalen, frequentie;
  final invoer = _invoerBegin.firstMatch(stderr);
  if (invoer != null) {
    final eind = _uitvoerBegin.firstMatch(stderr.substring(invoer.start));
    final blok = eind == null
        ? stderr.substring(invoer.start)
        : stderr.substring(invoer.start, invoer.start + eind.start);
    final m = _audiostroom.firstMatch(blok);
    if (m != null) {
      kanalen = kanalenUitStroom(m.group(1)!);
      frequentie = int.tryParse(_hz.firstMatch(m.group(1)!)?.group(1) ?? '');
    }
  }

  final samenvatting = stderr.lastIndexOf('Summary:');
  if (samenvatting < 0) {
    return (lufs: null, monsterpiek: null, warePiek: null, kanalen: kanalen, frequentie: frequentie);
  }
  final staart = stderr.substring(samenvatting);
  final lufs = _getal(RegExp(r'\bI:\s+(\S+)\s+LUFS').firstMatch(staart)?.group(1));
  double? piekNa(String kop) {
    final k = staart.indexOf(kop);
    if (k < 0) return null;
    return _getal(RegExp(r'Peak:\s+(\S+)\s+dBFS').firstMatch(staart.substring(k))?.group(1));
  }

  return (
    lufs: lufs,
    monsterpiek: piekNa('Sample peak:'),
    warePiek: piekNa('True peak:'),
    kanalen: kanalen,
    frequentie: frequentie,
  );
}

double? _getal(String? s) {
  if (s == null) return null;
  final t = s.trim().toLowerCase();
  if (t == '-inf') return double.negativeInfinity;
  if (t == 'inf' || t == '+inf' || t == 'nan' || t == '-nan') return double.nan;
  return double.tryParse(t);
}

const Map<String, int> _indelingen = {
  'mono': 1,
  'stereo': 2,
  '2.1': 3,
  '3.0': 3,
  '3.0(back)': 3,
  'quad': 4,
  'quad(side)': 4,
  '4.0': 4,
  '5.0': 5,
  '5.0(side)': 5,
  '5.1': 6,
  '5.1(side)': 6,
  '6.0': 6,
  '6.1': 7,
  '7.0': 7,
  '7.1': 8,
  '7.1(wide)': 8,
  '7.1(wide-side)': 8,
};

/// Het aantal kanalen uit het deel ná `Audio:` van een streamregel. Een onbekende indeling telt als
/// meer dan twee — dat is de veilige kant: zo'n nummer speelt zoals vroeger.
int kanalenUitStroom(String audio) {
  final delen = audio.split(',').map((d) => d.trim()).toList();
  final hz = delen.indexWhere((d) => d.endsWith(' Hz'));
  if (hz < 0 || hz + 1 >= delen.length) return 99;
  final indeling = delen[hz + 1].toLowerCase();
  final n = RegExp(r'^(\d+) channels?').firstMatch(indeling);
  if (n != null) return int.parse(n.group(1)!);
  return _indelingen[indeling] ?? 99;
}

/// Van ruwe ffmpeg-uitvoer naar een uitslag.
///
/// [kanalenUitKop] (uit de FLAC-STREAMINFO) gaat vóór de streamregel. Geen leesbare luidheid of geen
/// piek is Mislukt; een stille meting (−70 LUFS) is gewoon een meting.
Luidheidsuitslag uitslagUit(Ebur128Uitvoer u, {int? kanalenUitKop}) {
  final kanalen = kanalenUitKop ?? u.kanalen ?? 99;
  if (kanalen > 2) return Meerkanaals(kanalen);
  final lufs = u.lufs;
  if (lufs == null || !lufs.isFinite) return const Mislukt('geen luidheid in de uitvoer van ffmpeg');
  final pieken = [u.monsterpiek, u.warePiek].whereType<double>().where((p) => !p.isNaN).toList();
  if (pieken.isEmpty) return const Mislukt('geen piek in de uitvoer van ffmpeg');
  var piek = pieken.reduce(math.max);
  if (piek == double.negativeInfinity) piek = kPiekOndergrens;
  if (!piek.isFinite) return const Mislukt('geen geldige piek in de uitvoer van ffmpeg');
  return Gemeten(Luidheidsmeting(lufs: _afgerond(lufs, 1), piek: piek + 0.05));
}

/// Waarom een nummer de versterking heeft die het heeft. Het merk op Nu speelt en het blad leven
/// hiervan; elke bron heeft een eigen tekst.
enum Bijstelbron {
  /// Stand Uit.
  uit,

  /// Gemeten en al op het doel (minder dan [kNulDrempel] ernaast).
  opDoel,

  /// Per nummer bijgesteld.
  nummer,

  /// De plaat als geheel bijgesteld.
  album,

  /// Zacht opgenomen, maar de pieken laten geen ophoging toe.
  geenRuimte,

  /// De klem liet het nummer ongemoeid (een kleine verlaging zou pieken boven 0 dB laten afknippen).
  klemNul,

  /// De klem verlaagde het nummer verder dan het doel vroeg, zodat er niets afknipt.
  klemExtra,

  /// Stilte of een verborgen nummer.
  stilte,

  /// Meer dan twee kanalen; speelt zoals vroeger.
  meerkanaals,

  /// Nog niet gemeten.
  ongemeten,

  /// Een adres van buiten de bibliotheek (online radio); wordt nooit gemeten.
  online,

  /// De meting kon niet; speelt zoals vroeger.
  mislukt,

  /// De pc heeft zijn eerste ronde nog niet af; tot dan klinkt alles zoals vroeger.
  pcNietKlaar,

  /// Op een toestel: de pc stuurt geen metingen mee — een oudere versie. "pc meet nog" zou hier een
  /// belofte zijn die nooit uitkomt.
  pcOud,

  /// ffmpeg ontbreekt op de pc; er wordt niets gemeten.
  pcZonderFfmpeg,

  /// Een speaker (Sonos/UPnP) speelt; die krijgt het origineel.
  speaker,

  /// Gecast naar de Shield; die rekent zelf, met de stand van de pc (niet die van dit toestel).
  shield,

  /// mpv nam de waarde niet aan.
  mpvWeigert,

  /// De speler herkende het geladen adres niet; uit voorzorg 0 dB.
  onbekendAdres,
}

/// De versterking voor één nummer, met waarom.
class Bijstelling {
  final double db;
  final Bijstelbron bron;
  final double doel;
  final Luidheidsmeting? meting;

  /// Speelt als deel van een plaat (het merk zegt dan "Album").
  final bool alsAlbum;

  /// De versterking van de plaat als geheel, als [alsAlbum].
  final double? albumDb;

  /// De meting van de plaat als geheel, als [alsAlbum] (voor het blad).
  final Luidheidsmeting? albumMeting;

  /// Ongemeten, maar er was op dit pad eerder een meting: "net bewerkt — wordt zo opnieuw gemeten".
  final bool netBewerkt;

  /// Uitgerekend met de opgave van de zender (op de Shield): de stand komt dan van de pc, en de
  /// keuzes op dit toestel veranderen er niets aan.
  final bool vanZender;

  /// Per nummer, omdat de plaat een verzamelalbum is (terwijl "Albums als geheel" aan staat).
  final bool verzamelaar;

  const Bijstelling(this.db, this.bron,
      {this.doel = -14,
      this.meting,
      this.alsAlbum = false,
      this.albumDb,
      this.albumMeting,
      this.netBewerkt = false,
      this.vanZender = false,
      this.verzamelaar = false});

  static const nul = Bijstelling(0, Bijstelbron.uit);

  Bijstelling metBron(Bijstelbron b, {double? db}) => Bijstelling(db ?? this.db, b,
      doel: doel,
      meting: meting,
      alsAlbum: alsAlbum,
      albumDb: albumDb,
      albumMeting: albumMeting,
      netBewerkt: netBewerkt,
      vanZender: vanZender,
      verzamelaar: verzamelaar);

  @override
  String toString() =>
      'Bijstelling(${db.toStringAsFixed(2)} dB, ${bron.name}${alsAlbum ? ', album ${albumDb?.toStringAsFixed(2)}' : ''})';
}

/// De keuze bij een verlaging die de klem raakt: 0 (ongemoeid, bit-gelijk aan vandaag) of zo ver
/// omlaag dat de piek op [kKlemMarge] eindigt — welke van de twee het dichtst bij [gewenst] ligt.
/// Bij gelijke afstand 0: dan wordt het nooit te stil.
({double db, Bijstelbron bron}) _klem(double gewenst, double piek, Bijstelbron gewoon) {
  if (piek + gewenst <= kKlemMarge + 1e-9) return (db: gewenst, bron: gewoon);
  final dieper = kKlemMarge - piek;
  if ((dieper - gewenst).abs() < (0 - gewenst).abs() && dieper.abs() >= kNulDrempel) {
    return (db: dieper, bron: Bijstelbron.klemExtra);
  }
  return (db: 0, bron: Bijstelbron.klemNul);
}

/// De versterking voor één nummer op eigen kracht.
///
/// Invariant (eigenschapstoets): de uitkomst is 0, of piek + uitkomst ≤ −0,5; en een ophoging
/// eindigt op ≤ −1,0 dBTP.
({double db, Bijstelbron bron}) versterking(Luidheidsmeting m, double doel) {
  if (m.lufs <= kStilteGrens) return (db: 0, bron: Bijstelbron.stilte);
  final nodig = doel - m.lufs;
  if (nodig.abs() < kNulDrempel) return (db: 0, bron: Bijstelbron.opDoel);
  if (nodig < 0) return _klem(nodig, m.piek, Bijstelbron.nummer);
  final ruimte = kPiekPlafond - m.piek;
  if (ruimte < kNulDrempel) return (db: 0, bron: Bijstelbron.geenRuimte);
  final g = math.min(nodig, math.min(ruimte, kMaxOphoging));
  return (db: g, bron: Bijstelbron.nummer);
}

/// Eén nummer als bouwsteen voor [albumMeting].
typedef Albumdeel = ({Luidheidsmeting? meting, bool definitief, Duration? duur});

/// De luidheid van een plaat, afgeleid uit die van zijn nummers.
///
/// Vermogensgemiddelde naar duur: I = 10·log10(Σ dᵢ·10^(Iᵢ/10) / Σ dᵢ). Nagemeten op Khaled
/// (11 nummers): afgeleid −13,61 LUFS, het hele album aan één stuk door ffmpeg −13,60. De piek is de
/// hoogste piek van alle gemeten nummers, ook de stille.
///
/// Null zolang er een nummer is dat nog gemeten moet worden: dan geldt per nummer tot de plaat af
/// is. Mislukte en meerkanaalsnummers zijn [Albumdeel.definitief] en tellen niet mee.
Luidheidsmeting? albumMeting(Iterable<Albumdeel> delen) {
  final lijst = delen.toList();
  if (lijst.isEmpty) return null;
  if (lijst.any((d) => d.meting == null && !d.definitief)) return null;
  final gemeten = [for (final d in lijst) if (d.meting != null) d];
  if (gemeten.isEmpty) return null;
  final bekend = [for (final d in gemeten) if (d.duur != null && d.duur! > Duration.zero) d.duur!];
  final gemiddeld = bekend.isEmpty
      ? 1.0
      : bekend.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / bekend.length;
  var energie = 0.0, totaal = 0.0;
  for (final d in gemeten) {
    if (d.meting!.lufs <= kStilteGrens) continue;
    final w = (d.duur != null && d.duur! > Duration.zero) ? d.duur!.inMilliseconds.toDouble() : gemiddeld;
    energie += w * math.pow(10, d.meting!.lufs / 10);
    totaal += w;
  }
  if (totaal <= 0 || energie <= 0) return null;
  final piek = gemeten.map((d) => d.meting!.piek).reduce(math.max);
  return Luidheidsmeting(lufs: 10 * math.log(energie / totaal) / math.ln10, piek: piek);
}

/// De versterking van een plaat als geheel. GEEN klem op albumniveau: die zou één nummer met hoge
/// pieken de hele plaat laten bepalen (een maximum over 10–15 moderne nummers ligt bijna altijd boven
/// 0 dBTP). De klem komt per nummer, in [perNummerInAlbum].
double albumVersterking(Luidheidsmeting album, double doel) {
  final nodig = doel - album.lufs;
  double g;
  if (nodig < 0) {
    g = nodig;
  } else {
    final ruimte = kPiekPlafond - album.piek;
    g = ruimte <= 0 ? 0 : math.min(nodig, math.min(ruimte, kMaxOphoging));
  }
  return g.abs() < kNulDrempel ? 0 : g;
}

/// De albumversterking voor één nummer van die plaat, geklemd met zijn EIGEN piek.
///
/// Geen eigen meting (mislukt, meerkanaals) → 0. Een ophoging is al begrensd door de plaatpiek, die
/// minstens zo hoog is als die van dit nummer.
({double db, Bijstelbron bron}) perNummerInAlbum(double gAlbum, Luidheidsmeting? eigen) {
  if (eigen == null) return (db: 0, bron: Bijstelbron.mislukt);
  if (gAlbum == 0) return (db: 0, bron: Bijstelbron.album);
  if (gAlbum < 0) return _klem(gAlbum, eigen.piek, Bijstelbron.album);
  return (db: gAlbum, bron: Bijstelbron.album);
}

/// Speelt dit nummer als deel van zijn plaat?
///
/// Binnen een plaat zijn de verschillen de mastering — een stil intro, een ballad — en die horen te
/// blijven; daarom gaat de plaat als geheel omhoog of omlaag. Maar alleen als je echt een plaat
/// luistert: op volgorde, minstens drie nummers achter elkaar (of de hele plaat als die korter is),
/// en geen verzamelalbum — daar komen de nummers uit verschillende jaren en masters, en dan geldt het
/// argument niet.
bool speeltAlsAlbum({
  required bool albumGeheel,
  required bool opVolgorde,
  required bool isSingle,
  required bool isVerzamelaar,
  required int reeks,
  required int plaatLengte,
}) =>
    albumGeheel &&
    opVolgorde &&
    !isSingle &&
    !isVerzamelaar &&
    plaatLengte > 0 &&
    reeks >= math.min(3, plaatLengte);

/// Hoe lang de aaneengesloten reeks is waar plek [index] in zit: opeenvolgende wachtrijplekken
/// waarvan de plek in de plaat ([plekInPlaat], null = niet van deze plaat) telkens met precies 1
/// stijgt. Track heeft geen discveld; de volgorde van `album.tracks` is de plaatvolgorde, en dat
/// werkt ook bij tracknummers 0.
int aaneengeslotenReeks(List<int?> plekInPlaat, int index) {
  if (index < 0 || index >= plekInPlaat.length || plekInPlaat[index] == null) return 0;
  var begin = index, eind = index;
  while (begin > 0 &&
      plekInPlaat[begin - 1] != null &&
      plekInPlaat[begin - 1]! + 1 == plekInPlaat[begin]) {
    begin--;
  }
  while (eind + 1 < plekInPlaat.length &&
      plekInPlaat[eind + 1] != null &&
      plekInPlaat[eind]! + 1 == plekInPlaat[eind + 1]) {
    eind++;
  }
  return eind - begin + 1;
}

/// Eén sleutel voor één adres, aan beide kanten van de speler hetzelfde.
///
/// **Waarom dit nodig is.** De speler legt de versterking vast onder het adres dat hij aan mpv geeft;
/// de on_load-haak leest mpv's `path` terug. Maar media_kit maakt van een Windows-pad eerst
/// `\\?\D:\…` met backslashes (media_native.dart normalizeURI → real.dart `_sanitizeUri` →
/// safe_local_storage `addPrefix`). Zonder deze functie vond de haak op de pc nooit iets, en zei het
/// merk "−3,4 dB" boven een nummer dat op 0 dB speelde.
String adresSleutel(String s, {required bool kleineLetters}) {
  var t = s.trim();
  final lager = t.toLowerCase();
  if (lager.startsWith('http://') || lager.startsWith('https://')) {
    try {
      return Uri.parse(t).toString();
    } on FormatException {
      return t;
    }
  }
  if (t.startsWith(r'\\?\UNC\')) {
    t = '\\\\${t.substring(8)}';
  } else if (t.startsWith(r'\\?\')) {
    t = t.substring(4);
  }
  t = t.replaceAll('\\', '/');
  final unc = t.startsWith('//');
  t = t.replaceAll(RegExp(r'/{2,}'), '/');
  if (unc) t = '/$t';
  return kleineLetters ? t.toLowerCase() : t;
}
