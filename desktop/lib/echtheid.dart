/// Is dit bestand écht wat het beweert te zijn?
///
/// Saber: "hoe weet ik dat een FLAC echt een FLAC is en niet een mp3 die naar FLAC is omgezet? Hoe weet
/// ik dat ik echt lossless of hi-res binnenhaal?" Tot nu toe wist de app dat niet: [isHiRes] gelooft de
/// FLAC-kop, of bij een zoekresultaat wat een wildvreemde peer meldt, onvoorwaardelijk — en geeft daar
/// een gouden badge voor.
///
/// DRIE PROEVEN, en het scheiden ervan is de belangrijkste keuze in dit bestand:
///
///   A  bitdiepte     zijn de onderste acht bits ooit gebruikt?    tegenspraak
///   B  bovenband     staat er iets boven 22,05 kHz?               zo goed als tegenspraak
///   C  bandbreedte   staat er een muur in het spectrum?           statistisch
///
/// A en B beantwoorden "is dit hi-res", C beantwoordt "is dit een transcode". **Alleen C kan vals alarm
/// geven.** Door ze uit elkaar te houden zit het hele risico in één van de drie, en blijven de andere
/// twee hard.
///
/// A BEWIJST ALLEEN HET NEGATIEVE. Zijn de onderste acht bits in een half miljoen samples nooit gebruikt,
/// dan is de inhoud met zekerheid niet meer dan zestien bit. Zijn ze wél gebruikt, dan bewijst dat
/// niets — een omzetting van 16 naar 24 mét dither vult ze ook. De uitslag heet daarom
/// [Bitdiepte.spreektNietTegen] en nooit "echt 24 bits".
///
/// WAAROM B ERBIJ MOET, terwijl de vraag er niet naar vroeg: een 16/44,1 die met een resampler naar
/// 24/96 is getild heeft wél volle onderste bits — interpolatie vult ze. Proef A mist hem dus volledig.
/// Maar boven 22,05 kHz is hij absoluut leeg, terwijl een echte 96 kHz-opname daar altijd iets heeft:
/// microfoonruis, omzetterruis. Zonder B ontsnapt precies de meest voorkomende soort nep-hi-res.
///
/// Puur en zonder `dart:io`, zodat alles hieronder met verzonnen spectra te toetsen is. Het draaien van
/// ffmpeg staat in `echtheid_meter.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';
import 'quality.dart';

// ── De drempels ────────────────────────────────────────────────────────────
// De drempels van de spectrale proeven staan bij [oordeelVol], met de ijking waarop ze rusten. Hier
// alleen de twee die voor beide gelden.

/// Onder deze frequentie doen we geen uitspraak.
///
/// Daaronder leven 78-toerenplaten, cassettetransfers, AM-opnames en gerestaureerde mono's. De kans op
/// vals alarm is daar hoog en het belang laag.
const double laagsteAfkapHz = 14000;

/// Hoeveel samples er minstens niet-nul moeten zijn voor de bitdiepteproef.
const int minNietNulSamples = 200000;

// ── De uitslagen ───────────────────────────────────────────────────────────

enum Bitdiepte { spreektNietTegen, opgeblazen, onbekend }

enum Bovenband { vol, leeg, onbekend }

/// [vermoedelijk]: een muur tussen [zekerAfkapTot] en [vermoedelijkAfkapTot] — past bij mp3 320 of
/// Opus, maar ook bij een 20 kHz-filter in de master. Geen bewijs, dus geen [Echtheidsoordeel.isNep].
enum Bandbreedte { doorlopend, afgekapt, vermoedelijk, onbekend }

/// De controlesom van een FLAC: de MD5 van alle samples, door de encoder in de kop gezet (RFC 9639).
/// [fout]: de samples zijn niet wat de encoder schreef — bewezen beschadigd.
enum Integriteit { klopt, fout, geenControlesom, onbekend }

/// De vorm van de opgeslagen meting. Een oordeel uit de oude meting (drie grepen van vier seconden,
/// één kanaal) gaf ~180 verkeerde antwoorden op Sabers bibliotheek en wordt bij het laden weggegooid,
/// zodat het opnieuw gemeten wordt — zie [Echtheidsoordeel.fromJson].
const int echtheidsVersie = 2;

class Echtheidsoordeel {
  final Bitdiepte bits;
  final int? gebruikteBits;
  final Bovenband boven;
  final Bandbreedte band;
  final double? afkapHz, wandDb;
  final int vensters;
  final Integriteit integriteit;

  /// 24,5-40 kHz ten opzichte van de muziek (dB), alleen boven 48 kHz.
  final double? ultraDb;

  /// Waarmee een ANDERE kopie van dezelfde opname bewees dat deze afgekapt is ([bewezenDoor]): "je cd loopt door tot
  /// 21,3 kHz", "precies 1024 monsters achter je cd". Null als alleen deze meting sprak.
  final String? bewijs;

  const Echtheidsoordeel({
    required this.bits,
    required this.boven,
    required this.band,
    this.gebruikteBits,
    this.afkapHz,
    this.wandDb,
    this.vensters = 0,
    this.integriteit = Integriteit.onbekend,
    this.ultraDb,
    this.bewijs,
  });

  /// Dit oordeel, maar afgekapt — bewezen door een andere kopie van dezelfde opname ([bewijs]).
  ///
  /// **Waarom (Saber, 27-10-2026: "Amai, weer een foute meting, zorg er eens voor dat dit goed werkt, daarnet ook al bij
  /// Céline Dion").** Destin had een muur op 17,15 kHz van 22,7 dB — te ondiep om op zichzelf afgekapt te heten — en zijn
  /// "studio" van Nothing Compares 2 U een muur op 20,35 kHz, "vermoedelijk". In beide gevallen liep zijn eigen cd van
  /// dezelfde opname verder door (21,25 en 20,95 kHz): dan zat die muur niet in de master. Dat bewijs hoort bij het
  /// oordeel zelf, zodat de hele app het ziet — de badge, de keuring, de jacht, "studio downloaden".
  Echtheidsoordeel bewezenDoor(String bewijs) => Echtheidsoordeel(
        bits: bits,
        boven: boven,
        band: Bandbreedte.afgekapt,
        gebruikteBits: gebruikteBits,
        afkapHz: afkapHz,
        wandDb: wandDb,
        vensters: vensters,
        integriteit: integriteit,
        ultraDb: ultraDb,
        bewijs: bewijs,
      );

  /// Alleen wat BEWEZEN is telt. `onbekend` is nadrukkelijk geen "nep" — zie [isOnbekend].
  bool get isNep =>
      bits == Bitdiepte.opgeblazen || boven == Bovenband.leeg || band == Bandbreedte.afgekapt;

  /// Bewezen beschadigd: de controlesom klopt niet.
  bool get isKapot => integriteit == Integriteit.fout;

  /// Een muur rond 20 kHz: waarschijnlijk lossy, niet bewezen.
  bool get isVermoedelijk => band == Bandbreedte.vermoedelijk;

  /// Er viel niets te zeggen. Een volwaardig antwoord, geen stille `false`.
  bool get isOnbekend =>
      !isNep &&
      bits == Bitdiepte.onbekend &&
      boven == Bovenband.onbekend &&
      band == Bandbreedte.onbekend;

  Map<String, dynamic> toJson() => {
        'v': echtheidsVersie,
        'bits': bits.name,
        'boven': boven.name,
        'band': band.name,
        if (gebruikteBits != null) 'gebruikteBits': gebruikteBits,
        if (afkapHz != null) 'afkapHz': afkapHz,
        if (wandDb != null) 'wandDb': wandDb,
        'vensters': vensters,
        'integriteit': integriteit.name,
        if (ultraDb != null) 'ultraDb': ultraDb,
        if (bewijs != null) 'bewijs': bewijs,
      };

  /// Null voor rommel én voor een oordeel van een oudere meting ([echtheidsVersie]): dat wordt dan
  /// opnieuw gemeten in plaats van verder geloofd.
  static Echtheidsoordeel? fromJson(Map<String, dynamic> j) {
    if ((j['v'] as num?)?.toInt() != echtheidsVersie) return null;
    T? lees<T extends Enum>(List<T> waarden, String sleutel) {
      final s = j[sleutel]?.toString();
      for (final w in waarden) {
        if (w.name == s) return w;
      }
      return null;
    }

    final b = lees(Bitdiepte.values, 'bits');
    final v = lees(Bovenband.values, 'boven');
    final n = lees(Bandbreedte.values, 'band');
    if (b == null || v == null || n == null) return null;
    return Echtheidsoordeel(
      bits: b,
      boven: v,
      band: n,
      gebruikteBits: (j['gebruikteBits'] as num?)?.toInt(),
      afkapHz: (j['afkapHz'] as num?)?.toDouble(),
      wandDb: (j['wandDb'] as num?)?.toDouble(),
      vensters: (j['vensters'] as num?)?.toInt() ?? 0,
      integriteit: lees(Integriteit.values, 'integriteit') ?? Integriteit.onbekend,
      ultraDb: (j['ultraDb'] as num?)?.toDouble(),
      bewijs: j['bewijs'] as String?,
    );
  }
}

// ── Proef A: de bitdiepte ──────────────────────────────────────────────────

/// Hoeveel bits er werkelijk in gebruik zijn, uit samples die als 32-bit links uitgelijnd binnenkomen.
///
/// ffmpeg legt bij `s32le` een 16-bit sample in de bovenste zestien bits en een 24-bit sample in de
/// bovenste vierentwintig. De onderste bits zijn dus precies de vraag. Werkt op tweecomplement zonder
/// omweg: negeren behoudt het aantal nullen achteraan, en samples die nul zijn beïnvloeden een OR niet —
/// digitale stilte vervuilt de meting dus niet.
int gebruikteBitsVan(Int32List samples) {
  var masker = 0;
  for (final s in samples) {
    masker |= s;
  }
  if (masker == 0) return 0;
  var nullenAchteraan = 0;
  while (masker & 1 == 0) {
    masker >>= 1;
    nullenAchteraan++;
  }
  return 32 - nullenAchteraan;
}

// ── De volle meting (20-10-2026) ───────────────────────────────────────────
//
// Saber: "ik wil dit met 100 procent zekerheid weten … eerlijkheid". Dezelfde drie proeven, maar over
// het HELE bestand en beide kanalen (echtheid_meter.dart), en met drempels die geijkt zijn op 110
// nep-bestanden gemaakt van zes echte uit zijn bibliotheek:
//
//   echte originelen                 0 van 6 vals alarm
//   MP3 192, 256, 320                18 van 18        MP3 128 en V2     10 van 12
//   Opus 128 en 256                  9 van 10         44,1 → 96 kHz     11 van 11
//   16 → 24 bit                      6 van 6          via 48 → 96 kHz   0 van 1
//   MP3 V0, Vorbis q6, AAC (ffmpeg)  0 van 30 — geen laagdoorlaat; voor geen enkele spectrummeting
//                                    zichtbaar (LAME-broncode: V0 = 24 kHz, boven Nyquist)
//
// De oude meting (drie grepen van vier seconden, één kanaal, een val van 35 dB, een bovenband 55 dB
// stil) noemde 89 echte hi-res bestanden opgeschaald (A-ha "Take On Me (MTV Unplugged)" heeft inhoud
// tot 34 kHz) en miste 75 duidelijke MP3-muren (Beyoncé "Halo", 17 kHz).

/// Het spectrum zoals de volle meting het verzamelt: banden van [bandHz] breed, het vermogensgemiddelde
/// over de luide vensters ([gemiddeld], dB) en het 95e percentiel per band ([p95], dB). [luid] is het
/// aantal luide vensters, alle kanalen samen.
class Spectrumstaat {
  const Spectrumstaat({
    required this.sampleRate,
    required this.bandHz,
    required this.gemiddeld,
    required this.p95,
    required this.luid,
  });
  final int sampleRate;
  final double bandHz;
  final Float64List gemiddeld, p95;
  final int luid;

  ({int a, int z}) _banden(double van, double tot) => (
        a: math.max(0, (van / bandHz).round()),
        z: math.min(gemiddeld.length, (tot / bandHz).round()),
      );

  /// Het vermogensgemiddelde over [van, tot) in dB, of null als daar geen band ligt.
  double? db(double van, double tot) {
    final (:a, :z) = _banden(van, tot);
    if (z <= a) return null;
    var som = 0.0;
    for (var k = a; k < z; k++) {
      som += math.pow(10, gemiddeld[k] / 10);
    }
    return dB(som / (z - a));
  }

  /// De luidste band van het 95e percentiel in [van, tot): staat er óóit iets?
  double maxP95(double van, double tot) {
    final (:a, :z) = _banden(van, tot);
    var m = -300.0;
    for (var k = a; k < z; k++) {
      if (p95[k] > m) m = p95[k];
    }
    return m;
  }
}

/// Hoeveel dB de val over een afkap minstens is om een MUUR te heten: gemiddeld over 1 kHz eronder
/// min 1 kHz erboven. De zes echte bronnen haalden hooguit 13, MP3 128-320 en Opus 23 tot 68.
const double volMuurDb = 25;

/// Onder [zekerAfkapTot], waar een studio niet filtert: een val van minstens dit (maar minder dan [volMuurDb]) heet
/// [Bandbreedte.vermoedelijk] — verdacht, met een vraagteken, geen bewijs.
///
/// **Waarom (27-10-2026).** Destin van Céline Dion — een gedecodeerde stream, precies 1024 monsters achter Sabers cd —
/// had een val van 22,7 dB op 17,15 kHz en ging als "doorlopend" door; Saber: *"Amai, weer een foute meting"*. Gemeten
/// over de bibliotheek, de steilste val onder 19,4 kHz van 552 doorlopende bestanden: 506 onder 10 dB, 31 tussen 10 en
/// 15, 6 tussen 15 en 20, en tussen 20 en 25 negen, allemaal op een mp3-grens (15,7 tot 19,3 kHz). Maar daar zit ook
/// Children (Radio Edit) bij, met zijn val op 16,1 kHz in de officiële TIDAL-master, en een steile geleidelijke afloop
/// (18 dB/kHz) geeft ook 21 dB: dus verdacht, niet bewezen. Bewezen wordt het door een andere kopie van dezelfde opname
/// die verder doorloopt (`muurBewezenDoor`, keuring.dart) of door de nultoets.
const double volBijnaMuurDb = 20;

/// Boven de muur gemiddeld minstens zoveel stiller dan de muziek (500-5000 Hz): echt leeg.
const double volErbovenDb = -45;

/// En eronder minstens zoveel meer dan erboven: er wás iets om af te kappen (anders is het dof).
const double volInhoudDb = 15;

/// Een muur onder deze frequentie is het patroon van een MP3/AAC-encoder: LAME 128 = 17,0 kHz, 192 =
/// 18,6, oudere encoders op 128 = 16. Een studio filtert daar niet.
const double zekerAfkapTot = 19400;

/// Tussen [zekerAfkapTot] en hier: mp3 256/320 (19,7/20,5 kHz) en Opus (20 kHz), maar ook een 20 kHz-
/// filter in de master. Waarschijnlijk, niet bewezen — [Bandbreedte.vermoedelijk].
const double vermoedelijkAfkapTot = 20900;

/// Hi-res: 24,5-40 kHz zoveel onder de muziek is vrijwel digitale stilte. Opgeschaald met soxr: tot -122;
/// echte 96 kHz-opnames in de bibliotheek: -40 tot -70.
const double volOpgeschaaldStil = -90;

/// Of een muur tussen 19 en 25 kHz van minstens [volOpgeschaaldWand] dB met erboven minstens
/// [volOpgeschaaldLeeg] stilte: ffmpegs eigen resampler laat tot 25 kHz wat doorlekken (val 15-23 dB).
const double volOpgeschaaldWand = 15;
const double volOpgeschaaldLeeg = -60;

/// Zoveel luide vensters (alle kanalen) minstens voor een uitspraak over de band.
const int volMinLuid = 50;

/// De steilste val in [van, tot]: het gemiddelde over 1 kHz eronder min 1 kHz erboven, met 150 Hz marge.
({double hz, double db})? steilsteVal(Spectrumstaat s, double van, double tot) {
  final nyq = s.sampleRate / 2;
  ({double hz, double db})? beste;
  for (var f = van; f <= tot; f += s.bandHz) {
    final onder = s.db(f - 1000, f - 150);
    final boven = s.db(f + 150, math.min(f + 1000, nyq - 100));
    if (onder == null || boven == null) continue;
    final val = onder - boven;
    if (beste == null || val > beste.db) beste = (hz: f, db: val);
  }
  return beste;
}

/// Het oordeel van de volle meting: de drie proeven uit de kop van dit bestand, met
/// [Bandbreedte.vermoedelijk] erbij en de controlesom ([integriteit]).
Echtheidsoordeel oordeelVol({
  required Spectrumstaat s,
  required int kopSampleRate,
  required int kopBits,
  required int gebruikteBits,
  required int nietNulSamples,
  Integriteit integriteit = Integriteit.onbekend,
}) {
  final sr = s.sampleRate;
  final nyq = sr / 2;
  final muziek = s.db(500, 5000);
  // Geen muziek (stilte, of geen enkel luid venster): dan valt er niets te zeggen.
  if (sr < 44100 || muziek == null || muziek < -250 || s.gemiddeld.isEmpty) {
    return Echtheidsoordeel(
        bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.onbekend, integriteit: integriteit);
  }

  // ── A: over ALLE samples, dus rekenkundig zeker ──
  var bits = Bitdiepte.onbekend;
  if (nietNulSamples >= minNietNulSamples && kopBits > 16) {
    bits = gebruikteBits <= 16 ? Bitdiepte.opgeblazen : Bitdiepte.spreektNietTegen;
  }

  // ── B: is er iets boven 24,5 kHz? Alleen als het bestand meer dan 48 kHz beweert. ──
  var boven = Bovenband.onbekend;
  double? ultra;
  if (kopSampleRate > 48000 && sr > 48000) {
    final u = s.db(24500, math.min(nyq - 1000, 40000));
    if (u != null) {
      ultra = u - muziek;
      final wand = steilsteVal(s, 19000, 25000);
      final leeg = ultra <= volOpgeschaaldStil ||
          (wand != null && wand.db >= volOpgeschaaldWand && ultra <= volOpgeschaaldLeeg);
      boven = leeg ? Bovenband.leeg : Bovenband.vol;
    }
  }

  // ── C: staat er een muur tussen 14 en 20,9 kHz? ──
  var band = Bandbreedte.onbekend;
  double? afkapHz, wandDb;
  if (s.luid >= volMinLuid) {
    band = Bandbreedte.doorlopend;
    final w = steilsteVal(s, 11000, math.min(21500, nyq - 600));
    if (w != null) {
      afkapHz = w.hz;
      wandDb = w.db;
      final erboven = (s.db(w.hz + 150, nyq - 200) ?? muziek) - muziek;
      final eronder = (s.db(w.hz - 3000, w.hz - 500) ?? muziek) - muziek;
      final leegErboven = erboven <= volErbovenDb && (eronder - erboven) >= volInhoudDb;
      final muur = w.db >= volMuurDb && leegErboven;
      if (muur && w.hz >= laagsteAfkapHz && w.hz < zekerAfkapTot) {
        band = Bandbreedte.afgekapt;
      } else if (muur && w.hz >= zekerAfkapTot && w.hz <= vermoedelijkAfkapTot) {
        band = Bandbreedte.vermoedelijk;
      } else if (leegErboven && w.db >= volBijnaMuurDb && w.hz >= laagsteAfkapHz && w.hz < zekerAfkapTot) {
        band = Bandbreedte.vermoedelijk;
      }
    }
  }

  return Echtheidsoordeel(
    bits: bits,
    gebruikteBits: nietNulSamples >= minNietNulSamples ? gebruikteBits : null,
    boven: boven,
    band: band,
    afkapHz: afkapHz,
    wandDb: wandDb,
    vensters: s.luid,
    integriteit: integriteit,
    ultraDb: ultra,
  );
}

/// Waarom, in dezelfde volgorde als [oordeelVol] beslist — zodat het scherm nooit iets anders zegt dan de
/// meting. Zelfde afspraak als `whyBetter` in organize.dart.
/// Waarom dit bestand op de Kwaliteit-lijst staat: de afkap, altijd.
///
/// [waarom] noemt de EERSTE grond die het vindt, en dat is de goede volgorde voor een merkje bij een
/// nummer: "je 24 bits zijn er 16" is een hardere uitspraak dan een muur in het spectrum. Maar op een
/// lijst die alléén afgekapte bestanden toont las dat verkeerd — er stond "opgeschaald, geen echte
/// hi-res" naast een chipje met 17,2 kHz erin, en dan lijkt de rij over iets anders te gaan dan
/// waarom hij daar staat. Gezien op Stromae en Christina Aguilera, allebei tegelijk opgeblazen én
/// afgekapt.
///
/// De tweede bevinding gaat niet verloren, hij komt erachter. Beide zijn waar.
String waaromAfkap(Echtheidsoordeel o) {
  final hz = o.afkapHz;
  if (o.band != Bandbreedte.afgekapt || hz == null) return waarom(o);
  final zin = afkapZin(hz);
  if (o.bits == Bitdiepte.opgeblazen) {
    return '$zin · en het zegt meer dan ${o.gebruikteBits} bits';
  }
  if (o.boven == Bovenband.leeg) return '$zin · en het is bovendien opgeschaald';
  return zin;
}

/// Waar een afkap op deze hoogte vandaan pleegt te komen, of null als hij nergens naar wijst.
///
/// De getallen zijn de standaardinstellingen van de encoders zelf. Ze staan hier omdat "17,2 kHz"
/// een meting is en "dit was een mp3 van 128" een verklaring — en het verschil tussen die twee hoort
/// zichtbaar te blijven. Een marge van 400 Hz, want encoders schuiven hun filter een beetje met de
/// bemonstering en de versie mee.
/// De meting eerst, de verklaring erachter.
///
/// Vroeger stond hier onvoorwaardelijk "dit kwam uit een mp3". Sinds de muurzoeker tot 21 kHz kijkt
/// is dat te stellig: daar zit ook de bovengrens van een oude, smal gemasterde cd. De AFKAP is een
/// meting en blijft dus vooropstaan; wat hem waarschijnlijk veroorzaakte staat erachter, en alleen
/// als de hoogte ergens naar wijst.
String afkapZin(double hz) {
  // Met een komma, zoals overal in de app ("15,9 kHz"); hier stond "15.9" (18-10-2026).
  final k = (hz / 1000).toStringAsFixed(1).replaceAll('.', ',');
  final bron = vermoedelijkeBron(hz);
  return bron == null
      ? 'afgekapt op $k kHz — smaller dan lossless hoort te zijn'
      : 'afgekapt op $k kHz — dat is waar $bron kapt';
}

/// Gemeten op de ijkset (20-10-2026): de muurzoeker vindt de val zo'n 300 Hz onder wat de encoder
/// instelt (LAME-broncode: 128 = 17,0, 160 = 17,5, 192 = 18,6, V2 = 18,5, 256 = 19,7, 320 = 20,5 kHz;
/// Opus: 20 kHz; oudere encoders op 128: 16 kHz). Mp3 V0 staat er bewust niet in: die heeft op 44,1
/// kHz geen laagdoorlaat, en hier stond hij bij 19,5 kHz.
String? vermoedelijkeBron(double hz) {
  const bekend = <(double, String)>[
    (15900, 'een oude mp3 van 128'),
    (16800, 'mp3 128'),
    (17300, 'mp3 160'),
    (18700, 'mp3 192 of V2'),
    (19450, 'mp3 256'),
    (20200, 'mp3 320 of Opus'),
  ];
  for (final (f, naam) in bekend) {
    if ((hz - f).abs() <= 250) return naam;
  }
  return null;
}

/// Een verdachte muur: wat hij kan zijn, zonder te beweren wat hij is. Rond 20 kHz een mp3 320 of een filter in de
/// master; daaronder een val die te zacht is om zeker te zijn ([volBijnaMuurDb]).
String vermoedelijkZin(double hz, {double? db}) {
  final k = (hz / 1000).toStringAsFixed(1).replaceAll('.', ',');
  if (hz < zekerAfkapTot) {
    final d = db == null ? '' : ' van ${db.round()} dB';
    final bron = vermoedelijkeBron(hz);
    return 'val$d op $k kHz — past bij ${bron ?? 'een mp3'}, maar is te zacht om zeker te zijn';
  }
  return 'muur op $k kHz — past bij mp3 320 of Opus, maar ook bij een 20 kHz-filter in de master; niet zeker';
}

/// Wat er WERKELIJK in zit, in de notatie waarin de kop het beweert.
///
/// **Waarom dit er is.** De badge toonde `FLAC · 24/192` — wat het bestand BEWEERT — met daarnaast
/// een bolletje dat zei dat dat niet klopte. Wat het dan wél was stond nergens, en dat is precies wat
/// je wilt weten. Nu vervangt dit de getallen door de gemeten waarheid.
///
/// Null als er niets tegengesproken is; dan klopt de kop en hoeft er niets te veranderen.
///
/// De volgorde is die van het HARDSTE gemeten feit. Een muur in het spectrum bindt sterker dan een
/// bemonstering: een bestand dat op 17,2 kHz ophoudt draagt geen 44,1 kHz aan inhoud, hoe de kop het
/// ook noemt. Daarom staat de bandbreedte vooraan en niet de bits.
String? echteResolutie(Echtheidsoordeel o, {required int kopSampleRate, required int kopBits}) {
  final hz = o.afkapHz;
  // De ZIN blijft zeggen waar de muur zit, ook al rekent [echteWaarden] hem om naar een
  // bemonstering: "tot 14,0 kHz" vertelt je iets, "16/28" niets.
  if (o.band == Bandbreedte.afgekapt && hz != null) {
    return 'tot ${(hz / 1000).toStringAsFixed(1).replaceAll('.', ',')} kHz';
  }
  final w = echteWaarden(o, kopSampleRate: kopSampleRate, kopBits: kopBits);
  // Vermoedelijk: met een vraagteken, want het kan ook de master zijn. Pas als niets harders iets zegt.
  if (o.band == Bandbreedte.vermoedelijk && hz != null && w.rate == kopSampleRate && w.bits == kopBits) {
    return 'tot ${(hz / 1000).toStringAsFixed(1).replaceAll('.', ',')} kHz?';
  }
  if (w.rate == kopSampleRate && w.bits == kopBits) return null;
  // Dezelfde notatie als de badge ernaast, uit dezelfde functie. Een eigen kopie zou hier `16/44,1`
  // kunnen gaan schrijven terwijl de badge `16/44` zegt, en dan lezen ze als twee verschillende
  // soorten getallen over hetzelfde bestand.
  return depthRateLabel(sampleRate: w.rate, bitsPerSample: w.bits);
}

/// Wat er WERKELIJK in zit, als getallen in plaats van als zin.
typedef EchteResolutie = ({int bits, int rate, bool uitLossy});

/// Dezelfde waarheid als [echteResolutie], maar te vergelijken.
///
/// **Waarom dit erbij moest.** De meting bestond alleen als zin ("24/44.1") en als ja/nee
/// ([Echtheidsoordeel.isNep]). Daardoor kon niets in de app vragen wélke van twee bestanden er écht
/// beter is — `firstIsBetter` kende maar "betrapt: ja/nee" en viel daaronder terug op de grootte,
/// en juist een opgeblazen bestand is GROTER.
///
/// De volgorde is die van het hardste gemeten feit, gelijk aan [echteResolutie]: een muur bindt
/// sterker dan een bemonstering.
///
/// **Een afgekapte kopie verliest per constructie van een echte cd, zonder drempel.** De muurzoeker
/// noemt alleen een muur onder [zekerAfkapTot] = 19400 afgekapt, dus twee keer de afkap is hoogstens 38800 — al
/// minder dan 44100. En de bits worden op zestien geklemd: een uit mp3 omgezet bestand dat 24 bits
/// beweert zou anders `42000 × 24` scoren en een echte cd verslaan. Die klem is verdedigbaar op de
/// eigen voorwaarden van dit bestand — [Bitdiepte.spreektNietTegen] bewijst nadrukkelijk nooit dat
/// er 24 echte bits in zitten.
///
/// **Let op wat dit NIET zegt.** Zonder oordeel komt de kop onveranderd terug: dit is geen bewijs
/// dat een bestand echt is, alleen dat niets het tegensprak.
EchteResolutie echteWaarden(Echtheidsoordeel? o,
    {required int kopSampleRate, required int kopBits}) {
  // Een kop van nul is geen kop. GEZIEN op Sabers bibliotheek: er staat een bestand met
  // `bitsPerSample: 0` in het tagbestand, en dat gaf capaciteit NUL — waarmee het bovenaan de lijst
  // van te vervangen bestanden belandde. Nul is niet "het slechtste", het is "onbekend", en de
  // gewone aannames horen hier hetzelfde te zijn als overal elders in de app.
  final bits = kopBits > 0 ? kopBits : 16;
  final rate = kopSampleRate > 0 ? kopSampleRate : 44100;
  if (o == null) return (bits: bits, rate: rate, uitLossy: false);
  final gemeten = o.bits == Bitdiepte.opgeblazen ? (o.gebruikteBits ?? 16) : bits;
  final hz = o.afkapHz;
  if (o.band == Bandbreedte.afgekapt && hz != null) {
    return (bits: math.min(gemeten, 16), rate: (2 * hz).round(), uitLossy: true);
  }
  // Niets boven 22 kHz betekent dat de inhoud niet meer draagt dan wat 44,1 kHz kan bevatten, hoe
  // hoog de kop ook staat. Dat is de gewone vorm van opgeschaalde hi-res.
  return (bits: gemeten, rate: o.boven == Bovenband.leeg ? 44100 : rate, uitLossy: false);
}

/// De gemeten waarheid op dezelfde schaal als [capaciteitOpEenSchaal], zodat twee bestanden te
/// wegen zijn. Een echte cd is 705; alles wat uit een mp3 komt blijft daaronder.
int echteCapaciteit(Echtheidsoordeel? o, {required int kopSampleRate, required int kopBits}) {
  final w = echteWaarden(o, kopSampleRate: kopSampleRate, kopBits: kopBits);
  return capaciteitOpEenSchaal(
      sampleRate: w.rate, bitDepth: w.bits, kbps: 0, lossless: true);
}

String waarom(Echtheidsoordeel o) {
  if (o.isKapot) {
    return 'beschadigd: de controlesom klopt niet — de samples zijn niet wat de encoder schreef';
  }
  if (o.bits == Bitdiepte.opgeblazen) {
    return 'zegt meer dan 16 bits, maar gebruikt er ${o.gebruikteBits} — opgeblazen';
  }
  if (o.boven == Bovenband.leeg) {
    return 'boven 24,5 kHz vrijwel leeg — opgeschaald uit 44,1 of 48 kHz, geen echte hi-res';
  }
  if (o.band == Bandbreedte.afgekapt) {
    final b = o.bewijs;
    if (b != null) {
      final hz = o.afkapHz;
      return hz == null
          ? 'omgezet uit een lossy bestand — $b'
          : 'muur op ${(hz / 1000).toStringAsFixed(1).replaceAll('.', ',')} kHz, en $b: omgezet uit een lossy bestand';
    }
    return afkapZin(o.afkapHz!);
  }
  if (o.band == Bandbreedte.vermoedelijk && o.afkapHz != null) {
    return vermoedelijkZin(o.afkapHz!, db: o.wandDb);
  }
  if (o.isOnbekend) return 'niet te beoordelen';
  final stukken = <String>[];
  if (o.bits == Bitdiepte.spreektNietTegen) stukken.add('${o.gebruikteBits} bits in gebruik');
  if (o.boven == Bovenband.vol) stukken.add('inhoud boven 22 kHz');
  if (o.band == Bandbreedte.doorlopend) stukken.add('geen afkap gevonden');
  return stukken.isEmpty ? 'niet te beoordelen' : stukken.join(' · ');
}
