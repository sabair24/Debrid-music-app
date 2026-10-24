/// Eén discografie uit drie catalogi, samengevoegd tot één regel per plaat.
///
/// Deezer alleen was te mager: regionale uitgaves, EP's en compilaties ontbreken er stelselmatig.
/// MusicBrainz kent die wel maar heeft geen hoezen, en Discogs kent er zoveel dat je door de
/// persingen de plaat niet meer ziet. Elk van de drie is in zijn eentje het verkeerde antwoord.
///
/// Dit bestand is een BLAD: geen http, geen Flutter, geen bestanden. Alleen `catalog.dart` voor
/// [CatalogRef] en `organize.dart` voor [normKey]. Zo staat het samenvoegen los van het ophalen en is
/// het te testen zonder een netwerk na te bootsen — de vorm die de rest van dit project ook aanhoudt.
///
/// Apart bestand en niet in `catalog.dart`, om dezelfde reden waarom `editions.dart` apart staat:
/// `discogs.dart` importeert `catalog.dart` al, dus de afhankelijkheid kan maar één kant op.
library;

import 'catalog.dart';
import 'organize.dart' show normKey;

/// Welke catalogus deze plaat kent. Het merkje op de regel.
///
/// Bewust niet [EditionSource] uit editions.dart hergebruikt: die zegt "welke catalogus beschreef deze
/// PERSING" en kent er twee. Twee tegengestelde betekenissen onder één naam is precies hoe je later
/// niet meer weet wat een veld doet.
enum DiscoSource { deezer, musicbrainz, discogs }

/// Wat voor uitgave dit is.
///
/// Elke bron spelt dit anders — Deezer `album|single|ep|compile` als vrije tekst, MusicBrainz een
/// `primaryType` plus losse `secondaryTypes`, Discogs verstopt het in het formaat. Eén veld met drie
/// spellingen is de reden dat sorteren op type nu niet kan; vandaar één eigen begrip met drie
/// omzetters ernaartoe.
/// De vier laatste kwamen erbij toen bleek dat MusicBrainz ze al aanleverde en de app ze weggooide:
/// `secondaryTypes` werd alleen op "Compilation" gelezen, dus een concertplaat, een remixplaat en een
/// interviewschijf stonden allemaal tussen de studioalbums. Gemeten over de 333 release-groups van
/// Michael Jackson: Live 32, Remix 59, Soundtrack 7, Demo 5, Mixtape/Street 3, Interview 3,
/// Spokenword 1, Audiobook 1, DJ-mix 1.
///
/// [demo] en [gesproken] krijgen geen blok op de pagina (zie [verborgenSoorten]) maar zijn wél eigen
/// soorten en géén [other]. Dat verschil is niet cosmetisch: `other` betekent bij het samenvoegen
/// "ik heb geen mening", en dan zou een interviewschijf die Discogs als "LP, Album" kent zó terug
/// tussen de albums staan.
enum RecordKind {
  album,
  albumVersie,
  live,
  ep,
  single,
  remix,
  compilation,
  demo,
  gesproken,
  video,
  uitzending,
  other
}

/// Draagt deze titel een uitgave-staart — "(Deluxe Edition)", "[2021 Remaster]"?
///
/// Zo'n uitgave is geen andere PERSING maar een ander product: er staan nummers op die op het gewone
/// album niet staan. Vandaar een eigen blok, en vandaar dat [discoKey] hem NIET wegstrijkt: dan zou
/// hij samenvallen met het hoofdalbum en was er niets meer te tonen.
bool heeftEditieStaart(String title) => _editieStaart(title) != null;

/// De titel zonder zijn uitgave-staart, of null als er geen staart is.
String? _editieStaart(String title) {
  var t = title.trim();
  var gevonden = false;
  for (var i = 0; i < 3; i++) {
    // Tussen haakjes, of na een streepje: Deezer schrijft dezelfde staart ook als
    // "Aux Armes Et Caetera-Version Internationale" en "Histoire De Melody Nelson - 40ème
    // Anniversaire". Zonder die tweede vorm stonden die heruitgaven met hun eigen jaar (2003, 2011)
    // tussen de studioalbums van Serge Gainsbourg (gezien op 11-10-2026).
    final haakje = _staart.firstMatch(t);
    final m = haakje ?? _streepStaart.firstMatch(t);
    if (m == null) break;
    final binnen = normKey(m.group(0)!).split(' ').where((w) => w.isNotEmpty);
    if (binnen.isEmpty) break;
    if (!binnen.every((w) => _uitgaveWoorden.contains(w) || _getalWoord.hasMatch(w))) break;
    // Een kaal getal na een streepje ("Hits - 2") is geen uitspraak; dat beslist de jubileumregel in
    // [vouwHeruitgaves], die het jaarverschil narekent.
    if (haakje == null && binnen.every(_getalWoord.hasMatch)) break;
    final kaal = t.substring(0, m.start).trim();
    if (kaal.isEmpty) break;
    t = kaal;
    gevonden = true;
  }
  return gevonden ? t : null;
}

/// Een staart na een streepje: "Titel - 40ème Anniversaire", "Titel-Version Internationale".
final _streepStaart = RegExp(r'\s*[-–—]\s*[^-–—()\[\]{}]+$');

/// Deezers `record_type`.
RecordKind kindFromDeezer(String recordType) => switch (recordType.trim().toLowerCase()) {
      'album' => RecordKind.album,
      'ep' => RecordKind.ep,
      'single' => RecordKind.single,
      'compile' || 'compilation' => RecordKind.compilation,
      _ => RecordKind.other,
    };

/// MusicBrainz' `primaryType` plus zijn `secondaryTypes`.
///
/// De tweede lijst gaat vóór, en dat is geen detail: een verzamelaar staat daar als
/// `primaryType: Album` met `secondaryTypes: [Compilation]`. Alleen naar het eerste veld kijken zet
/// elke verzamelbox tussen de studioalbums.
///
/// Dat gold tot 06-09-2026 alléén voor "Compilation", en daar kwam de klacht vandaan: "HIStory Manila
/// 1996", "Bad Live In Yokohama" en "Heal the World Tour 92" stonden tussen de studioplaten. Alle
/// andere tweede etiketten vielen door naar `primaryType: Album`. Nu leest deze functie ze allemaal.
///
/// Op exacte woorden en niet op deelreeksen, want MusicBrainz spelt ze zelf ook exact —
/// "Mixtape/Street", "DJ-mix". Een `contains` zou "Live" ook in "Olive" vinden.
///
/// **Soundtrack blijft bewust een album.** Een soundtrack die de artiest zélf maakte is een plaat, en
/// hem degraderen is de kant op die dit hele werk moest vermijden. De soundtracks die wél
/// samengeraapt werk van anderen zijn, dragen bij MusicBrainz óók "Compilation" — en die wint hier
/// als eerste.
RecordKind kindFromMb(String primaryType, List<String> secondaryTypes) {
  final tweede = secondaryTypes.map((s) => s.trim().toLowerCase()).toSet();
  if (tweede.contains('compilation')) return RecordKind.compilation;
  if (tweede.contains('live')) return RecordKind.live;
  if (tweede.contains('remix') || tweede.contains('dj-mix')) return RecordKind.remix;
  if (tweede.contains('demo') || tweede.contains('mixtape/street')) return RecordKind.demo;
  if (tweede.contains('interview') ||
      tweede.contains('spokenword') ||
      tweede.contains('audiobook') ||
      tweede.contains('audio drama')) {
    return RecordKind.gesproken;
  }
  return switch (primaryType.trim().toLowerCase()) {
    'album' => RecordKind.album,
    'ep' => RecordKind.ep,
    'single' => RecordKind.single,
    // MusicBrainz' eigen woord voor een uitgave die gemaakt is om uitgezonden te worden. Viel
    // hiervoor door naar `other` — dat wérkte, maar per ongeluk: `other` betekent bij het
    // samenvoegen "ik heb geen mening", dus een radioplaat die Discogs ook als "LP, Album" kent
    // stond zó terug tussen de albums.
    'broadcast' => RecordKind.uitzending,
    _ => RecordKind.other,
  };
}

/// Discogs' `format`, dat een opsomming is: "LP, Album, Reissue" of "CD, Single".
/// Discogs' `format`, dat een opsomming is: "LP, Album, Reissue" of "File, FLAC, Single".
///
/// Ruim genomen, want gemeten viel een VIJFDE van Sia's discografie in "overig" — 51 van 238 — en dat
/// waren geen rariteiten maar gewone singles mét hoes: Thunderclouds, Helium, Never Give Up. Discogs
/// schrijft daar "File, MP3, Single" of "Maxi-Single" of "Single, Promo", en op exacte woorden matchen
/// mist dat allemaal. Een vijfde van de lijst verkeerd indelen maakt sorteren op type waardeloos.
RecordKind kindFromDiscogs(String format) {
  if (alleenVideo(format)) return RecordKind.video;
  if (isTranscriptie(format)) return RecordKind.uitzending;
  final f = format.toLowerCase();
  // "Comp" is Discogs' AFKORTING van Compilation, en op `/artists/{id}/releases` de enige spelling.
  // GEMETEN over 12093 regels uit die endpoint: `Compilation` voluit komt er NUL keer voor en `Comp`
  // 1711 keer. Deze functie zocht alleen het hele woord, dus die regel heeft daar nooit één keer
  // geraakt en zeventienhonderd verzamelaars stonden tussen de albums. De zoek-endpoint schrijft het
  // wél voluit — vandaar dat het niemand opviel.
  //
  // Op velden en niet op deelreeksen: "comp" zit ook in "compact".
  final velden = f.split(RegExp(r'[,+]')).map((s) => s.trim());
  if (velden.any((s) => s == 'comp' || s == 'compilation')) return RecordKind.compilation;
  // Op deelreeksen en niet op hele woorden: "maxi-single" en "single" moeten allebei tellen. Wel EP
  // eerst, want "EP" komt ook naast "Single" voor en is dan het specifiekere antwoord.
  if (RegExp(r'\bep\b').hasMatch(f)) return RecordKind.ep;
  if (f.contains('single')) return RecordKind.single;
  if (f.contains('album') || RegExp(r'\blp\b').hasMatch(f)) return RecordKind.album;
  return RecordKind.other;
}

/// Draagt dit formaat ALLEEN beeld — een dvd, een blu-ray, een vhs?
///
/// Saber vroeg film- en dvd-uitgaves uit de discografie te houden, "wel als er officieel een live
/// album music is". Dat tweede deel is precies waarom hier op de DRAGER gekeken wordt en niet op de
/// titel: een concertregistratie bestaat vaak als dvd én als plaat, en dan hoort de plaat te blijven.
///
/// GEMETEN op de 200 Discogs-regels van Michael Jackson: twintig noemen een videodrager, en twee
/// daarvan zijn hybride — `CD, Comp, RE + DVD-V, Comp, RE, NTSC` is een cd-verzamelaar met een dvd
/// erbij. Vandaar de eis dat er GEEN audiodrager in mag staan; anders gooit deze regel gewone platen
/// weg omdat er een schijfje bij zat.
///
/// Per veld en niet met `contains`, om twee vallen:
///   * "VCD" bevat "CD" — op deelreeksen zou een video-cd voor een gewone cd doorgaan;
///   * "DVD-A" is dvd-AUDIO en "Blu-ray Audio" ook. Die staan bewust niet in de videolijst.
///
/// Discogs schrijft het formaat als `CD, Album, RE + DVD-V, NTSC`: komma's tussen de kenmerken, een
/// plus tussen de dragers, en een aantal ervoor (`3xDVD`, `2xDVD-V`).
bool alleenVideo(String format) {
  final velden = format
      .toLowerCase()
      .split(RegExp(r'[,+]'))
      .map((s) => s.trim().replaceFirst(RegExp(r'^\d+\s*x\s*'), ''))
      .where((s) => s.isNotEmpty);
  var beeld = false;
  for (final v in velden) {
    if (_audioDrager.hasMatch(v)) return false;
    if (_videoDrager.hasMatch(v)) beeld = true;
  }
  return beeld;
}

/// Is dit een RADIOPLAAT — een persing die alleen bestond om uitgezonden te worden?
///
/// Saber wees ze aan op de pagina van The Police: twintig van de drieëndertig "albums" waren
/// BBC Rock Hour, Innerview, Off The Record Specials, Legends Of Rock, The Robert Klein Radio Show.
/// Allemaal met een etiketscan als hoes, want een verkoophoes hebben ze nooit gehad.
///
/// Discogs zegt het zelf, in één woord: `Transcription`. GEMETEN over de hele cache — 12093
/// Discogs-regels, 182 met dat kenmerk, en zonder uitzondering radio ("Superstar Concert Series",
/// "Brand New Day World Premiere Broadcast"). `kindFromDiscogs` zag alleen de "LP" ernaast en maakte
/// er een album van.
///
/// **`Promo` telt hier NIET mee**, en dat is een meting en geen voorzichtigheid: 1593 regels dragen
/// Promo zonder Transcription, en dat zijn grotendeels gewone promopersingen van echte singles —
/// "Breathe", "We've Got Tonight". Die weggooien zou het middel erger maken dan de kwaal.
bool isTranscriptie(String format) => format
    .toLowerCase()
    .split(RegExp(r'[,+]'))
    .map((s) => s.trim())
    .any((s) => s == 'transcription');

final _videoDrager = RegExp(r'^(dvd|dvd-?v|dvd-?video|dvdr|blu-?ray|blu-?ray-?r|bd|bdr|vhs|'
    r's-?vhs|betamax|betacam|video ?2000|laserdisc|ld|vcd|s-?vcd|cvd|umd|mini-?dv|vhd|ced|'
    r'u-?matic|video ?8|hi-?8|film|hd ?dvd)$');

final _audioDrager = RegExp(r'^(cd|cdr|cd-?r|hdcd|sacd|dvd-?a|dvd-?audio|blu-?ray audio|dualdisc|'
    r'lp|vinyl|shellac|acetate|flexi-?disc|lathe cut|cass|cassette|microcassette|8-?track|'
    r'reel-?to-?reel|minidisc|md|file|mp3|flac|wav|aac|wma|alac|aiff|dat|dcc|elcaset|'
    r'memory stick|sd card|usb|\d+")$');

/// Woorden die alleen iets zeggen over de UITGAVE en niets over de plaat.
///
/// "30" en "30 (Deluxe Edition)" zijn één plaat; "30" en "30 ans de succès" zijn er twee. Het
/// verschil is dat de eerste staart uitsluitend uit deze woorden bestaat.
const _uitgaveWoorden = {
  'deluxe', 'edition', 'editie', 'expanded', 'remaster', 'remastered', 'reissue', 'anniversary',
  'special', 'limited', 'bonus', 'tracks', 'track', 'version', 'versie', 'the', 'of', 'disc',
  'cd', 'lp', 'vinyl', 'digital', 'explicit', 'clean', 'jubileum',
  // 'super' erbij voor "Thriller 25 Super Deluxe Edition": zonder dat woord faalt de eis dat ÉLK
  // staartwoord uit deze lijst komt, en blijft die uitgave tussen de studioalbums staan.
  'super',
  // Frans, voor de heruitgaven van Gainsbourg: "Version Internationale", "40ème Anniversaire",
  // "Mix 2023", "Édition Collector", "Remasterisé" (na normKey zonder accenten).
  'internationale', 'international', 'anniversaire', 'mix', 'collector', 'remasterise',
  'remasterisee', 'integrale',
};

final _staart = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]\s*$');

/// Een jaartal of een rangtelwoord: "2021", "25th", "10e".
///
/// Als één woord, want [normKey] plakt cijfer en achtervoegsel aan elkaar. Ze los in de woordenlijst
/// zetten helpt dus niet — "25th" is nooit "25" plus "th".
final _getalWoord = RegExp(r'^\d+(st|nd|rd|th|e|de|ste|eme|ieme)?$');

/// De sleutel waarop twee regels dezelfde plaat zijn.
///
/// Twee lagen. Eerst [normKey] (organize.dart), want dat is de sleutel waarmee de BIBLIOTHEEK
/// vergelijkt — accenten gevouwen, krul- en rechte apostrof gelijk, leestekens weg. Gebruik je hier
/// iets anders, dan is "heb ik dit al" een andere vraag dan "is dit dezelfde plaat", en dat is precies
/// de bestaande scheefheid: `catalog.dart` dedupliceert op `toLowerCase()` terwijl de bezitscontrole
/// `normKey` gebruikt, waardoor "Backstreet's Back" met een krulapostrof twee regels oplevert die
/// allebei als "heb ik" worden afgevinkt.
///
/// De uitgave-staart blijft er nadrukkelijk IN staan.
///
/// Eerst haalde deze functie hem weg, zodat "30 (Deluxe Edition)" samenviel met "30". Dat is voor
/// PERSINGEN het goede antwoord — dezelfde plaat op vinyl, cd en per land hoort één regel te zijn —
/// maar een deluxe is geen persing: daar staan nummers op die op het gewone album niet staan. Met de
/// staart eruit verdwijnt die uitgave gewoon uit beeld, en dan is er niets meer te kiezen.
///
/// Dus blijft hij staan, en [heeftEditieStaart] gebruikt hem om zo'n uitgave in zijn eigen blok te
/// zetten. Twee zichtbare regels in twee blokken, in plaats van één regel en een stilzwijgend verlies.
///
/// Bewust NIET slimmer dan dit. Geen fuzzy titelafstand, geen jaarnabijheid. Een valse samenvoeging
/// VERBERGT een plaat en dat merk je nooit; een dubbele regel zie je meteen. Van die twee fouten is de
/// zichtbare de goede.
String discoKey(String title) => normKey(title);

/// Eén plaat, zoals hij op de artiestpagina staat.
class DiscoRelease {
  /// De titel zoals je hem leest. Vergelijken gebeurt op [key], nooit hierop.
  final String title;

  /// 'YYYY' of 'YYYY-MM-DD', als tekst — net als [CatalogAlbum.releaseDate]. Beide vormen sorteren
  /// als tekst correct ten opzichte van elkaar, en een echte datum invoeren zou de helft van de
  /// bronnen dwingen iets te verzinnen wat ze niet weten.
  final String? firstDate;

  final RecordKind kind;

  /// Null tot een bron er een levert. MusicBrainz heeft er nooit een op dit niveau.
  final String? cover;

  /// 0 = onbekend. Alleen Deezer weet dit; MusicBrainz en Discogs niet op dit niveau.
  final int trackCount;

  /// Welke catalogi deze plaat kennen — het merkje op de regel.
  final Set<DiscoSource> sources;

  /// Per bron de eigen verwijzing. Drie stuks, want ze zijn niet uit elkaar af te leiden.
  final Map<DiscoSource, CatalogRef> refs;

  const DiscoRelease({
    required this.title,
    required this.kind,
    this.firstDate,
    this.cover,
    this.trackCount = 0,
    this.sources = const {},
    this.refs = const {},
  });

  String get key => discoKey(title);

  /// Het soort zoals het in BLOKKEN komt te staan.
  ///
  /// Een album met een uitgave-staart is geen gewoon album: het is een deluxe, een remaster, een
  /// jubileumuitgave. Die horen bij elkaar en niet tussen de studioalbums, want anders staat één plaat
  /// er vier keer met bijna dezelfde naam en zie je niet meer welke de gewone is.
  RecordKind get blok =>
      kind == RecordKind.album && heeftEditieStaart(title) ? RecordKind.albumVersie : kind;

  int? get year {
    final d = firstDate;
    if (d == null || d.length < 4) return null;
    return int.tryParse(d.substring(0, 4));
  }

  /// Waarmee deze regel geopend wordt, in vaste voorkeursvolgorde.
  ///
  /// Deezer eerst, en dat is geen willekeur: alleen die tak haalt een tracklijst in één verzoek. De
  /// MusicBrainz-groep kost een browse plus een release-opzoeking op een baan van 1100 ms, en Discogs
  /// kost versions plus release op een baan van zestig per minuut. Wie het snelste antwoord heeft,
  /// mag de klik hebben.
  CatalogRef? get openRef =>
      refs[DiscoSource.deezer] ?? refs[DiscoSource.musicbrainz] ?? refs[DiscoSource.discogs];

  /// Terug naar de vorm die de albumpagina begrijpt. Die verandert niet mee.
  CatalogAlbum toCatalogAlbum() {
    final r = openRef;
    return CatalogAlbum(
      r != null && r.source == CatalogSource.deezer ? r.intId : 0,
      title,
      cover,
      firstDate,
      trackCount,
      switch (kind) {
        // Een albumversie is voor de albumpagina gewoon een album; het onderscheid dient alleen om
        // hem in de discografie in zijn eigen blok te zetten. Datzelfde geldt voor live, remix, demo
        // en gesproken: de albumpagina leest hier alleen 'single' uit (catalog.dart), dus verder
        // onderscheid zou daar niets doen behalve een tweede vocabulaire introduceren.
        RecordKind.album ||
        RecordKind.albumVersie ||
        RecordKind.live ||
        RecordKind.remix ||
        RecordKind.demo ||
        RecordKind.gesproken ||
        RecordKind.video ||
        RecordKind.uitzending =>
          'album',
        RecordKind.ep => 'ep',
        RecordKind.single => 'single',
        RecordKind.compilation => 'compile',
        RecordKind.other => 'album',
      },
      origin: r,
    );
  }

  /// Twee regels over dezelfde plaat tot één.
  ///
  /// Per veld wint de RIJKSTE waarde, niet de laatste: een hoes die er is verslaat null, een bekende
  /// tracktelling verslaat nul, en de VROEGSTE datum wint — Deezer levert bij een heruitgave de
  /// heruitgavedatum, en dan hoort de plaat nog steeds op zijn eigen jaar te staan.
  ///
  /// Daardoor is samenvoegen commutatief: het maakt niet uit in welke volgorde de bronnen binnenkomen.
  /// Dat is geen nettigheid maar de hele reden dat de lijst progressief mag aanvullen zonder onder je
  /// handen te veranderen.
  DiscoRelease mergedWith(DiscoRelease other) {
    String? vroegste(String? a, String? b) {
      if (a == null || a.isEmpty) return b;
      if (b == null || b.isEmpty) return a;
      return a.compareTo(b) <= 0 ? a : b;
    }

    return DiscoRelease(
      // De langste titel houdt de meeste informatie vast ("30" tegen "30 (Deluxe Edition)"), en bij
      // gelijke lengte beslist de tekst zelf zodat het antwoord niet van de volgorde afhangt.
      title: title.length == other.title.length
          ? (title.compareTo(other.title) <= 0 ? title : other.title)
          : (title.length > other.title.length ? title : other.title),
      // Een echt type verslaat `other`; weten twee bronnen het allebei, dan wint de laagste rang —
      // album boven overig, zodat één bron die "overig" zegt een album niet degradeert.
      //
      // Behalve voor een VERZAMELAAR, en dat is geen uitzondering maar het herstel van een fout.
      // [kindRank] is een LEESVOLGORDE — waar een blok op de pagina staat — en werd hier gebruikt
      // alsof het een betrouwbaarheidsvolgorde was. Album staat op 0 en compilation op 4, dus won
      // album altijd. Dat is precies waar [kindFromMb] tegen bestaat ("Alleen naar het eerste veld
      // kijken zet elke verzamelbox tussen de studioalbums"), één laag hoger teruggekomen.
      //
      // De asymmetrie is inhoudelijk: "Compilation" in MusicBrainz' tweede lijst en Deezers
      // `compile` zijn een UITSPRAAK dat dit een verzamelaar is. "Album" in een Discogs-formaat is
      // dat niet — dat staat op elke lp, ook op die van een verzamelbox. Een uitspraak verslaat een
      // afwezigheid, in beide volgordes.
      //
      // Lag er al, maar was onbereikbaar zolang Discogs-masters altijd `other` droegen; sinds die
      // hun formaat uit de zoeksweep krijgen, doen ze mee en trokken ze verzamelaars naar Albums.
      //
      // Sinds er live, remix, demo en gesproken bij zijn is dat geen uitzondering meer maar de
      // regel: zie [_uitspraakRang]. Vier keer dezelfde uitzondering opschrijven is vier keer de
      // kans hem verkeerd op te schrijven.
      kind: _sterksteUitspraak(kind, other.kind),
      firstDate: vroegste(firstDate, other.firstDate),
      cover: (cover != null && cover!.isNotEmpty) ? cover : other.cover,
      trackCount: trackCount > 0 ? trackCount : other.trackCount,
      sources: {...sources, ...other.sources},
      refs: {...other.refs, ...refs},
    );
  }
}

/// De volgorde waarin een discografie gelezen wordt: eerst de platen, dan de varianten, dan het klein
/// werk, en de verzamelaars achteraan.
///
/// Uitdrukkelijk NIET te gebruiken om te bepalen welke bron gelijk heeft — daarvoor is
/// [_uitspraakRang]. Dat verschil is hier één keer duur betaald: album staat op 0, en daardoor won
/// "album" bij het samenvoegen van élke andere uitspraak.
int kindRank(RecordKind k) => switch (k) {
      RecordKind.album => 0,
      RecordKind.albumVersie => 1,
      RecordKind.live => 2,
      RecordKind.ep => 3,
      RecordKind.single => 4,
      RecordKind.remix => 5,
      RecordKind.compilation => 6,
      RecordKind.demo => 7,
      RecordKind.gesproken => 8,
      RecordKind.uitzending => 9,
      RecordKind.video => 10,
      RecordKind.other => 11,
    };

/// Hoe HARD een bron dit zegt. Laag = een uitspraak, hoog = een vorm of een schouderophalen.
///
/// Geen [kindRank]. Die is een LEESVOLGORDE — waar een blok op de pagina staat. "Live" in
/// MusicBrainz' tweede lijst is een uitspraak dát dit een concertplaat is; "Album" in een
/// Discogs-formaat is dat niet, want dat staat op elke lp, ook op die van een livealbum. Een
/// uitspraak verslaat een vorm, en een vorm verslaat een afwezigheid — in beide volgordes, want
/// anders hangt de uitkomst af van welke bron toevallig het eerst binnenkwam.
int _uitspraakRang(RecordKind k) => switch (k) {
      RecordKind.compilation => 0,
      RecordKind.live => 1,
      RecordKind.remix => 2,
      RecordKind.demo => 3,
      RecordKind.gesproken => 4,
      RecordKind.album || RecordKind.albumVersie || RecordKind.ep || RecordKind.single => 5,
      // Video staat ONDER elke geluidsuitspraak, en dat is de halve wens: "wel als er officieel een
      // live album music is". Een concertregistratie die Discogs als dvd kent en MusicBrainz als
      // livealbum is een livealbum — er bestaat een plaat van. Kent alleen Discogs hem, en alleen
      // als dvd, dan is het beeld en verdwijnt hij.
      //
      // Een radioplaat staat op dezelfde trap, en om dezelfde reden. GEMETEN: van de 182
      // transcriptieregels in de cache dragen er vier een titel die óók zonder dat kenmerk bestaat
      // — "Elegantly Wasted" van INXS is een echt album waarvan ook een radiopersing bestaat.
      // Stond `uitzending` bóven album, dan zou die persing de plaat verbergen. Andersom niet: een
      // regel die alleen Discogs kent en alleen als transcriptie verdwijnt gewoon.
      RecordKind.uitzending || RecordKind.video => 6,
      RecordKind.other => 7,
    };

/// Welk van twee soorten overleeft als twee bronnen het niet eens zijn. Symmetrisch, en dat is de eis.
RecordKind _sterksteUitspraak(RecordKind a, RecordKind b) {
  if (a == b) return a;
  if (a == RecordKind.other) return b;
  if (b == RecordKind.other) return a;
  final ra = _uitspraakRang(a), rb = _uitspraakRang(b);
  if (ra != rb) return ra < rb ? a : b;
  // Even hard gezegd: dan beslist de leesvolgorde, zoals hij dat altijd deed — album boven single.
  return _minKind(a, b);
}

/// De kop boven elk blok. Ook de blokken die niet getoond worden hebben er een: de regel onder de
/// sectiekop somt met deze woorden op wát er weggelaten is.
String blokTitel(RecordKind k) => switch (k) {
      RecordKind.album => 'Albums',
      RecordKind.albumVersie => 'Andere uitgaves',
      RecordKind.live => 'Live',
      RecordKind.ep => "EP's",
      RecordKind.single => 'Singles',
      RecordKind.remix => 'Remixen',
      RecordKind.compilation => 'Verzamelaars',
      RecordKind.demo => "Demo's",
      RecordKind.gesproken => 'Gesproken',
      RecordKind.uitzending => 'Radio',
      RecordKind.video => 'Video',
      RecordKind.other => 'Overig',
    };

/// De discografie in blokken, elk blok op zijn eigen sortering, en lege blokken vallen weg.
List<({RecordKind soort, List<DiscoRelease> rijen})> inBlokken(
    List<DiscoRelease> alles, DiscoSort op, Set<String> bezit) {
  final per = <RecordKind, List<DiscoRelease>>{};
  for (final r in alles) {
    per.putIfAbsent(r.blok, () => []).add(r);
  }
  final soorten = per.keys.toList()..sort((a, b) => kindRank(a).compareTo(kindRank(b)));
  return [
    for (final s in soorten)
      if (per[s]!.isNotEmpty) (soort: s, rijen: sortDiscography(per[s]!, op, bezit)),
  ];
}

RecordKind _minKind(RecordKind a, RecordKind b) => kindRank(a) <= kindRank(b) ? a : b;

/// Alle regels van alle bronnen tot één lijst, één regel per plaat.
///
/// Neemt de LIJSTEN, niet een lopende toestand. De artiestpagina houdt de drie bronnen apart en roept
/// dit aan bij het tekenen; dan geeft elke hertekening hetzelfde antwoord, ongeacht wie het eerst
/// binnenkwam. Dat is wat progressief aanvullen veilig maakt — en meteen wat het testbaar maakt.
///
/// **Een single of EP en een album met dezelfde titel zijn twee platen** (Saber, 19-10-2026: "vaak
/// merk ik dat er singles staan bij albums"). Op titel alleen werden het album "Taking Chances" en de
/// single "Taking Chances" één regel. Die stond terecht bij Albums, maar droeg de hoes, de nummers en
/// de Deezer-link van wat het eerst binnenkwam — vaak de single, en dan opende een album op twee
/// nummers. GEMETEN over acht artiesten: 8 van de 167 albumtegels openden op een single of EP
/// ("Taking Chances", "One Heart", "Vuelve", "A Medio Vivir", "Livin' La Vida Loca", "Funhouse",
/// "True Blue", en "Alabina": Discogs' cassette-album uit 1993 plus de single uit 1996). Dus samen
/// op titel ÉN maat: single en EP apart van de rest. Eén uitzondering, zie [_alleenDeezerZegtKlein].
List<DiscoRelease> mergeDiscography(List<List<DiscoRelease>> bronnen) {
  final samen = <String, DiscoRelease>{};
  // Per titel (en maat) de plekken in [samen]: de eerste is de titel zelf, een andere plaat met dezelfde titel krijgt
  // er het jaar achter ("seal#1994") — zie [_anderePlaat]. De rondes hieronder werken op de titel zelf en laten zo'n
  // tweede plaat met rust.
  final varianten = <String, List<String>>{};
  String plekVoor(String g, DiscoRelease r) {
    final lijst = varianten[g] ??= [];
    String? beste;
    int? afstand;
    for (final s in lijst) {
      final e = samen[s]!;
      if (_anderePlaat(e, r)) continue;
      final d = _jaarAfstand(e, r) ?? 0;
      if (afstand == null || d < afstand) {
        beste = s;
        afstand = d;
      }
    }
    if (beste != null) return beste;
    var nieuw = lijst.isEmpty ? g : '$g#${_jaar(r) ?? lijst.length}';
    while (samen.containsKey(nieuw)) {
      nieuw = '$nieuw+';
    }
    lijst.add(nieuw);
    return nieuw;
  }

  for (final lijst in bronnen) {
    final klaar = <({DiscoRelease r, String g})>[];
    for (final r0 in lijst) {
      final k = r0.key;
      if (k.isEmpty) continue;
      // Wat de titel zegt, vóór het samenvoegen: zie [soortMetTitel].
      final soort = soortMetTitel(r0.kind, r0.title);
      final r = soort == r0.kind
          ? r0
          : DiscoRelease(
              title: r0.title,
              kind: soort,
              firstDate: r0.firstDate,
              cover: r0.cover,
              trackCount: r0.trackCount,
              sources: r0.sources,
              refs: r0.refs,
            );
      klaar.add((r: r, g: _isKlein(r.kind) ? '$k$_klein' : k));
    }
    // Wie het eerst bij een regel aansluit, geeft hem zijn hoes en zijn verwijzing ([DiscoRelease.mergedWith]). Daarom
    // per bron eerst wat in jaar en soort het dichtst bij een regel ligt die er al staat, en wat geen jaar draagt het
    // laatst. Seal (24-10-2026): Discogs noemt eerst een dvd uit 2008 en de krantenuitgave van 2007 (The Mail on
    // Sunday), pas daarna de cd's van 1994 en 1991. In aanvoervolgorde kreeg Seal 1991 de hoes en de tracklijst van
    // de krant.
    int rang(({DiscoRelease r, String g}) e) {
      if (_jaar(e.r) == null) return 1 << 30;
      var beste = 1 << 29;
      for (final s in varianten[e.g] ?? const <String>[]) {
        final b = samen[s]!;
        final d = _jaarAfstand(b, e.r);
        if (d == null) continue;
        final soortAnders = b.kind != e.r.kind && b.kind != RecordKind.other && e.r.kind != RecordKind.other;
        if (d * 2 + (soortAnders ? 1 : 0) < beste) beste = d * 2 + (soortAnders ? 1 : 0);
      }
      return beste;
    }

    final volgorde = [for (var i = 0; i < klaar.length; i++) (i: i, rang: rang(klaar[i]))]
      ..sort((a, b) => a.rang != b.rang ? a.rang.compareTo(b.rang) : a.i.compareTo(b.i));
    for (final v in volgorde) {
      final (:r, :g) = klaar[v.i];
      final plek = plekVoor(g, r);
      final bestaand = samen[plek];
      samen[plek] = bestaand == null ? r : bestaand.mergedWith(r);
    }
  }
  // Wat bij een titel als single of EP staat naast een regel van een andere maat. In vaste volgorde,
  // zodat de uitkomst niet van de aanvoer afhangt.
  for (final g in samen.keys.toList()..sort()) {
    if (!g.endsWith(_klein)) continue;
    final klein = samen[g];
    final k = g.substring(0, g.length - _klein.length);
    final groot = samen[k];
    if (klein == null || groot == null) continue;
    // Draagt de titel nog een grote plaat die MusicBrainz kent (zie [_anderePlaat]), dan is [groot] een heruitgave
    // daarvan en niet de single. Eurythmics, "Sweet Dreams (Are Made of This)": Deezer heeft het album vier keer (1987,
    // 1999, 2003, 2018), MusicBrainz het album van 1983 en de single van 1982, en de heruitgave van 2018 belandde zo
    // bij de single. Kent MusicBrainz geen album met die titel, dan blijft het zoals het was: Johnny Hallyday,
    // "Rivière… ouvre ton lit", is bij MusicBrainz alleen een single, en Deezers album (2000, 2020) geeft hem een
    // hoes en nummers.
    if ((varianten[k] ?? const <String>[])
        .any((s) => s != k && (samen[s]?.sources.contains(DiscoSource.musicbrainz) ?? false))) {
      continue;
    }
    // Een regel zonder mening (een Discogs-master zonder formaat) bij een titel die verder alleen als
    // single bekend is: bij die single, zoals hij dat altijd deed.
    if (groot.kind == RecordKind.other || _alleenDeezerZegtKlein(klein, groot)) {
      samen[k] = groot.mergedWith(klein);
      samen.remove(g);
    } else if (_alleenDeezerZegtGroot(klein, groot)) {
      // Omgekeerd: alleen Deezer zegt "album", MusicBrainz zegt EP of single. Dan MusicBrainz' soort.
      final m = klein.mergedWith(groot);
      samen[g] = DiscoRelease(
        title: m.title,
        kind: klein.kind,
        firstDate: m.firstDate,
        cover: m.cover,
        trackCount: m.trackCount,
        sources: m.sources,
        refs: m.refs,
      );
      samen.remove(k);
    }
  }
  // TWEEDE RONDE: een aanduiding die zegt WAT de plaat is, niet welke uitgave.
  //
  // Deezer noemt de soundtrack van Madame Claude "Madame Claude (Bande originale du film)", met als
  // datum zijn digitale heruitgave van 2021; MusicBrainz noemt hem "Madame Claude", 1977. Op sleutel
  // zijn dat twee platen, en dan stond de 2021 tussen de albums (Serge Gainsbourg, 11-10-2026). Zelfde
  // met "BOF Anna" (2006 tegen 1967) en "Enregistrement public au Théâtre Le Palace (Live)" (2020
  // tegen 1980). Alleen samen als de kale titel er ÓÓK staat, en van het passende soort: een
  // live-aanduiding alleen bij een liveplaat, want "Plaat (Live)" naast de studioplaat "Plaat" zijn
  // twee platen. In vaste volgorde, zodat de uitkomst niet van de aanvoer afhangt.
  //
  // Zonder kaal album: twee regels met dezelfde aanduiding en dezelfde kale titel zijn één plaat.
  // Madonna (20-10-2026): Deezer "Who's That Girl Soundtrack", MusicBrainz "Who’s That Girl: Original
  // Motion Picture Soundtrack" — twee keer tussen de albums, en "Who's That Girl" zelf is een single.
  final zonderKaal = <String, String>{};
  for (final k in samen.keys.toList()..sort()) {
    // Een single met een aanduiding hoort evenmin bij een album als een single zonder.
    if (k.endsWith(_klein)) continue;
    final r = samen[k];
    if (r == null) continue;
    final a = _aanduiding(r.title);
    if (a == null) continue;
    final kk = discoKey(a.kaal);
    if (kk == k) continue;
    final basis = samen[kk];
    if (basis == null) {
      final groep = '$kk|${a.live}';
      final eerste = zonderKaal[groep];
      final e = eerste == null ? null : samen[eerste];
      if (e == null || e.kind != r.kind) {
        zonderKaal.putIfAbsent(groep, () => k);
        continue;
      }
      samen[eerste!] = e.mergedWith(r);
      samen.remove(k);
      continue;
    }
    if (basis.kind != (a.live ? RecordKind.live : RecordKind.album)) continue;
    final m = basis.mergedWith(r);
    samen[kk] = DiscoRelease(
      title: basis.title,
      kind: m.kind,
      firstDate: m.firstDate,
      cover: m.cover,
      trackCount: m.trackCount,
      sources: m.sources,
      refs: m.refs,
    );
    samen.remove(k);
  }
  return samen.values.toList();
}

/// Zijn [a] en [b] twee platen, ook al dragen ze dezelfde titel? Ja als één bron ze allebei kent onder een ANDER
/// nummer, en ze minstens twee jaar uit elkaar liggen.
///
/// **Waarom (Saber, 24-10-2026: "hij maakt geen onderscheid tussen album seal 1991 en 1994").** Seal heeft twee
/// albums die "Seal" heten, en MusicBrainz kent er nog een derde: een krantenuitgave uit 2007 (The Mail on Sunday,
/// één uitgave). Deezer heeft er ook twee (86422, 1991-06-11 en 467277, 1994-05-31). Op titel alleen werden ze één
/// regel, met de hoes en de verwijzing van wie het eerst binnenkwam: "Seal · 1991" met de hoes van de krant, en
/// "Geen tracklijst gevonden". Een heruitgave van dezelfde plaat bij een ándere bron (Deezer 2003, MusicBrainz 1980)
/// blijft samengaan: die bron kent hem maar onder één nummer.
bool _anderePlaat(DiscoRelease a, DiscoRelease b) {
  final d = _jaarAfstand(a, b);
  if (d == null || d < 2) return false;
  for (final e in a.refs.entries) {
    final ander = b.refs[e.key];
    if (ander != null && ander.id.isNotEmpty && e.value.id.isNotEmpty && ander.id != e.value.id) return true;
  }
  return false;
}

int? _jaar(DiscoRelease r) {
  final d = r.firstDate ?? '';
  return d.length >= 4 ? int.tryParse(d.substring(0, 4)) : null;
}

int? _jaarAfstand(DiscoRelease a, DiscoRelease b) {
  final x = _jaar(a), y = _jaar(b);
  return x == null || y == null ? null : (x - y).abs();
}

/// Een titel die zegt dat de plaat remixen zijn: "Hollywood (Remixes)", "American Life (The Remixes)",
/// "Remixed & Revisited", "You Can Dance (Single Edits of Album Remixes)", "X-Ray Mixes", "Music Mix 2001".
final _remixTitel = RegExp(r'\bremix(es|ed)?\b|\bremixen\b|\bmix(es)?\b', caseSensitive: false);

/// Het soort, met wat de titel erover zegt.
///
/// **Waarom (Saber, 20-10-2026: "dit staat ook vaak tussen albums ?? remixen enzo").** Deezer noemt bij
/// Madonna veertien remixuitgaven "album" — "Hollywood (Remixes)", "Celebration (Remixes)", "Hung Up
/// (Remixes)", "American Life (The Remixes)" — en wat alleen Deezer kent, stond daardoor tussen de
/// studioalbums. Een album, ep of regel zonder mening met "remix" in de titel is een remixuitgave. Een
/// SINGLE niet: een remixsingle hoort bij de singles, en zo valt hij ook niet los van de single die
/// MusicBrainz onder dezelfde naam kent ([mergeDiscography] houdt single en groot werk apart).
///
/// En om dezelfde reden live en verzamelaars: Kylie's "Live In New York" en "Kylie Hits", Michael
/// Jacksons "Greatest Hits Live" en "Anthology: The Best Of Michael Jackson" stonden tussen de
/// studioalbums omdat alleen Deezer ze kende, en Deezer kent geen live en noemt een verzamelaar soms
/// "album". Alleen voor een album of een regel zonder mening: een single blijft een single.
RecordKind soortMetTitel(RecordKind kind, String titel) {
  final groot = kind == RecordKind.album || kind == RecordKind.other;
  if ((groot || kind == RecordKind.ep) && _remixTitel.hasMatch(titel)) return RecordKind.remix;
  if (!groot) return kind;
  final t = titel.trim();
  if (_liveTitel.hasMatch(t)) return RecordKind.live;
  if (_verzamelTitel.hasMatch(t)) return RecordKind.compilation;
  return kind;
}

/// "Live In New York", "Live At Wembley", "Live 2010 (…)", "Greatest Hits Live", "Plaat (Live)",
/// "Live - London Festival EP". Niet "Live Your Life" of "Live to Tell": live moet aan een plek, een
/// jaartal, het eind van de titel of een staart hangen.
///
/// Ook Frans, want Céline Dion: "Le spectacle Live à Montréal", "Une Seule Fois / Live 2013".
final _liveTitel = RegExp(
    r'\blive (in|at|from|on)\b|\blive (à|au|aux)\s|\blive \d{4}\b|^live\s*[-–(:]|\blive$|\(live\b[^)]*\)',
    caseSensitive: false);

/// "Greatest Hits", "The Best Of …", "Kylie Hits", "The Collection", "Anthology", "The Essential …",
/// "50 Number Ones", "Number 1's". Op hele woorden: "Golden" is een studioalbum van Kylie.
final _verzamelTitel = RegExp(
    r"\b(greatest hits|best of|hits|the collection|collection|anthology|the essential|essentials|number ones|#1'?s|number 1'?s)\b",
    caseSensitive: false);

/// Wat een versie van een nummer verraadt: "(Shep's Deep Makeover Mix)", "(Album Edit)", "(David's Love
/// Dub)", "(Shep's Classic 12")", "(Shep's Deepstrumental)", "(Backing Track)". Niet "Remaster": dat is
/// dezelfde opname.
final _versieWoord = RegExp(
    r'\b(mix|remix|dub|edit|version|versie|instrumental|acapella|a cappella|club|radio|extended|deepstrumental|'
    r'backing track|karaoke)\b|\d+"|\d+ inch',
    caseSensitive: false);

/// Eén staart achteraan de titel: "(…)", "[…]" of " - …".
final _titelStaart = RegExp(r'\s*[(\[]([^()\[\]]*)[)\]]\s*$|\s+-\s+([^-]+)$');

/// De titel zonder al zijn staarten, en wat er in die staarten stond. "Holiday (7" Version) (2022
/// Remaster)" → ("Holiday", ["2022 Remaster", "7" Version"]).
({String kaal, List<String> staarten}) _ontleed(String titel) {
  var t = titel;
  final staarten = <String>[];
  for (var i = 0; i < 4; i++) {
    final m = _titelStaart.firstMatch(t);
    if (m == null || m.start == 0) break;
    staarten.add(m.group(1) ?? m.group(2) ?? '');
    t = t.substring(0, m.start);
  }
  return (kaal: t, staarten: staarten);
}

/// Heeft deze titel een staart die een versie aanduidt?
bool _isVersie(String titel) => _ontleed(titel).staarten.any(_versieWoord.hasMatch);

/// Is dit een maxisingle die Deezer "album" noemt: het titelnummer in meerdere versies, met hooguit
/// een paar B-kanten? Dan hoort hij bij de singles.
///
/// Gemeten (20-10-2026). Madonna, 2022: "Deeper and Deeper" is twaalf keer "Deeper and Deeper (… Mix)",
/// "(… Dub)", "(Album Edit)"; "Rain" is drie keer "Rain (… Edit)" met "Waiting (Remix)", "Up Down Suite"
/// en "Fever (Edit Two)". Kylie, 2009: "Hand on Your Heart" is zes keer "Hand on Your Heart" ZONDER
/// versienaam en twee keer "Just Wanna Love You" — dus een titel die meer dan eens voorkomt telt ook
/// als versie. Geen titel die "remix" zegt, en de singles van toen heten bij MusicBrainz anders
/// ("Deeper and Deeper EP"), dus alleen de nummers verraden het.
///
/// De regel: het titelnummer staat er minstens twee keer op, minstens drie vijfde van de nummers is
/// een versie, en het zijn er hooguit vijftien — een deluxe-album met remixen erachter blijft zo een
/// album, en een album met een "Reprise" van het titelnummer ook.
bool isMaxisingle(String albumTitel, List<String> titels) {
  if (titels.length < 2 || titels.length > 15) return false;
  final titel = _zelfdeNummer(albumTitel);
  if (titel.isEmpty) return false;
  final kalen = [for (final t in titels) _zelfdeNummer(t)];
  final hoeVaak = <String, int>{};
  for (final k in kalen) {
    hoeVaak[k] = (hoeVaak[k] ?? 0) + 1;
  }
  final vanTitel = kalen.where((k) => k == titel).length;
  var versies = 0;
  for (var i = 0; i < titels.length; i++) {
    if (_isVersie(titels[i]) || (hoeVaak[kalen[i]] ?? 0) >= 2) versies++;
  }
  return vanTitel >= 2 && versies * 5 >= titels.length * 3;
}

/// Een titel om nummers op te vergelijken: zonder staart, zonder lidwoord vooraan en zonder spaties.
/// Kylie, "The Loco-Motion (Australian Version)" (2009): de nummers heten daar "Locomotion" en
/// "Locomotion (Chugga-Motion Mix)" — zonder lidwoord en zonder streepje.
String _zelfdeNummer(String titel) =>
    normKey(_ontleed(titel).kaal).replaceFirst(_lidwoordVooraan, '').replaceAll(' ', '');
final _lidwoordVooraan = RegExp(r'^(the|a|an|de|het|le|la|les) ');

/// Is dit een remixalbum dat Deezer "album" noemt: veel nummers, bijna allemaal een versie?
///
/// Madonna, "Finally Enough Love: 50 Number Ones" (2022): vijftig keer "… (7" Version)", "(You Can Dance
/// Remix Edit)", "(Video Version)". Minstens acht nummers en minstens vier vijfde een versie — een
/// deluxe-uitgave met een tweede schijf remixen haalt dat niet.
bool isRemixAlbum(List<String> titels) {
  if (titels.length < 8) return false;
  final versies = titels.where(_isVersie).length;
  return versies * 5 >= titels.length * 4;
}

/// Hoeveel albums MusicBrainz minstens moet kennen voor hij alleen beslist ([volgensMusicBrainz]).
const int kMbGenoeg = 3;

/// Hoe lang een plaat die alleen Deezer kent nog "nieuw" is: MusicBrainz heeft hem dan misschien nog niet.
const Duration kNieuwVenster = Duration(days: 183);

/// De discografie zoals MusicBrainz hem kent: welke platen er zijn, van welke soort, en wanneer.
///
/// **Waarom (Saber, 20-10-2026: "gebruik dan 1 pad, MusicBrainz, wat het beste en precies is").** Drie
/// bronnen samenvoegen en elke fout met een eigen regel dichten bleef lekken: Deezer noemt elke
/// verzamelaar, remix-ep en heruitgave "album" ("Alabina, l'essentiel", zeven keer "Anthologie" bij
/// Johnny Hallyday, "Last Train To Mashville Vol.2" drie keer bij Alabama 3), en Discogs zette 37
/// concertdownloads van Metallica bij de albums. MusicBrainz heeft per plaat één releasegroep, met een
/// soort die mensen nakijken (album, verzamelaar, live, remix, soundtrack); edities zijn daar uitgaven
/// bínnen de groep.
///
/// Dus: elke releasegroep van [mb] precies één keer, met de soort, de titel en de datum van MusicBrainz.
/// Wat Deezer en Discogs over dezelfde plaat weten (hoes, nummers, de link om af te spelen) komt uit de
/// samengevoegde regel in [samen] met dezelfde MusicBrainz-verwijzing. Van wat MusicBrainz niet kent,
/// blijft alleen:
/// - een editie van een MusicBrainz-album ("Rebel Heart (Deluxe)"), voor de nummers die er alleen op
///   staan — hij komt onder de uitgaven ([DiscoRelease.blok], [vouwHeruitgaves]);
/// - een plaat van de laatste [kNieuwVenster] die geen versie is van iets wat MusicBrainz al heeft:
///   die kent MusicBrainz misschien nog niet.
///
/// Kent MusicBrainz de artiest niet, of minder dan [kMbGenoeg] albums (of antwoordde hij niet), dan
/// blijft [samen] zoals hij is: dan is er geen beter pad. Alleen de heruitgaven die alleen Deezer kent, gaan
/// eruit ([zonderDeezerDubbels]).
///
/// [artiest]: Deezer zet de naam soms vóór of achter de titel ("Alabina, l'essentiel", "Les amours perdues -
/// Serge Gainsbourg"). Een MusicBrainz-regel zonder Deezer-link krijgt die van zo'n regel ("L'Essentiel"),
/// anders was hij niet af te spelen; de Deezer-regel staat dan niet nog eens apart.
List<DiscoRelease> volgensMusicBrainz(List<DiscoRelease> samen, List<DiscoRelease> mb,
    {String artiest = '', DateTime? nu}) {
  final mbAlbums = {
    for (final m in mb)
      if (soortMetTitel(m.kind, m.title) == RecordKind.album) m.key,
  };
  if (mbAlbums.length < kMbGenoeg) return zonderDeezerDubbels(samen);
  final mbSleutels = {for (final m in mb) m.key};
  final perMbId = <String, DiscoRelease>{
    for (final r in samen)
      if (r.refs[DiscoSource.musicbrainz] case final ref?) ref.id: r,
  };
  // Deezer-regels die MusicBrainz niet kent, op hun sleutel zonder de artiestnaam.
  final ak = discoKey(artiest);
  String? zonderArtiest(String k) {
    if (ak.isEmpty) return null;
    final rest = k.startsWith('$ak ')
        ? k.substring(ak.length + 1)
        : k.endsWith(' $ak')
            ? k.substring(0, k.length - ak.length - 1)
            : null;
    return rest == null || rest.trim().isEmpty ? null : rest.trim();
  }
  // Op hun eigen sleutel én zonder de artiestnaam; per maat, want een single hoort niet bij een album.
  // Per sleutel ALLE losse Deezer-regels: twee platen kunnen dezelfde titel dragen (Seal, 1991 en 1994 — zie
  // [_anderePlaat]); welke bij een MusicBrainz-plaat hoort, beslist het jaar ([dichtstBij]).
  final losDeezer = <String, List<DiscoRelease>>{};
  String maat(RecordKind k) => _isKlein(k) ? _klein : '';
  for (final r in samen) {
    if (r.refs.containsKey(DiscoSource.musicbrainz) || !r.refs.containsKey(DiscoSource.deezer)) continue;
    (losDeezer[r.key + maat(r.kind)] ??= []).add(r);
    if (zonderArtiest(r.key) case final k?) (losDeezer[k + maat(r.kind)] ??= []).add(r);
  }
  final gekoppeld = Set<DiscoRelease>.identity();
  DiscoRelease? dichtstBij(List<DiscoRelease>? lijst, DiscoRelease m) {
    DiscoRelease? beste;
    int? afstand;
    for (final d in lijst ?? const <DiscoRelease>[]) {
      if (gekoppeld.contains(d) || _anderePlaat(d, m)) continue;
      final a = _jaarAfstand(d, m) ?? 0;
      if (afstand == null || a < afstand) {
        beste = d;
        afstand = a;
      }
    }
    return beste;
  }
  final g = (nu ?? DateTime.now()).subtract(kNieuwVenster);
  String twee(int n) => n.toString().padLeft(2, '0');
  final grens = '${g.year}-${twee(g.month)}-${twee(g.day)}';
  final gezien = <String>{};
  final uit = <DiscoRelease>[];
  for (final m in mb) {
    final ref = m.refs[DiscoSource.musicbrainz];
    if (ref == null || !gezien.add(ref.id)) continue;
    var s = perMbId[ref.id];
    if (s == null || !s.refs.containsKey(DiscoSource.deezer)) {
      final km = zonderArtiest(m.key);
      final d = dichtstBij(losDeezer[m.key + maat(m.kind)], m) ?? (km == null ? null : dichtstBij(losDeezer[km + maat(m.kind)], m));
      if (d != null && gekoppeld.add(d)) s = s == null ? d : s.mergedWith(d);
    }
    uit.add(DiscoRelease(
      title: m.title,
      kind: soortMetTitel(m.kind, m.title),
      firstDate: m.firstDate ?? s?.firstDate,
      cover: s?.cover,
      trackCount: s?.trackCount ?? 0,
      sources: {...m.sources, ...?s?.sources},
      refs: {...?s?.refs, ...m.refs},
    ));
  }
  return [
    ...uit,
    for (final r in samen)
      if (!r.refs.containsKey(DiscoSource.musicbrainz) &&
          !gekoppeld.contains(r) &&
          _blijftNaastMb(r, mbAlbums, mbSleutels, grens))
        r,
  ];
}

/// Zonder MusicBrainz als scheidsrechter: één regel per titel en maat voor wat alleen Deezer kent.
///
/// Deezer houdt sinds 24-10-2026 twee uitgaven met dezelfde titel die twee jaar of meer uiteen liggen allebei
/// (Seal 1991 en 1994, zie `CatalogService.ontdubbelArtiestAlbums`), en dan beslist MusicBrainz welke bij welke plaat
/// hoort. Zonder MusicBrainz is dat meestal een heruitgave (Toto 1978 en 2006). Een regel die alleen Deezer kent valt
/// dan weg naast een regel met dezelfde titel die een andere bron ook kent; kent alleen Deezer ze allemaal, dan blijft
/// de nieuwste, zoals vóór 24-10-2026.
List<DiscoRelease> zonderDeezerDubbels(List<DiscoRelease> rijen) {
  String plaat(DiscoRelease r) => r.key + (_isKlein(r.kind) ? _klein : '');
  bool alleenDeezer(DiscoRelease r) => r.sources.length == 1 && r.sources.contains(DiscoSource.deezer);
  final per = <String, List<DiscoRelease>>{};
  for (final r in rijen) {
    (per[plaat(r)] ??= []).add(r);
  }
  final weg = Set<DiscoRelease>.identity();
  for (final groep in per.values) {
    if (groep.length < 2) continue;
    final deezer = groep.where(alleenDeezer).toList();
    if (deezer.isEmpty) continue;
    if (deezer.length < groep.length) {
      weg.addAll(deezer);
    } else {
      deezer.sort((a, b) => (b.firstDate ?? '').compareTo(a.firstDate ?? ''));
      weg.addAll(deezer.skip(1));
    }
  }
  return weg.isEmpty ? rijen : [for (final r in rijen) if (!weg.contains(r)) r];
}

/// Een regel die MusicBrainz niet kent: blijft hij staan? Zie [volgensMusicBrainz].
bool _blijftNaastMb(DiscoRelease r, Set<String> mbAlbums, Set<String> mbSleutels, String grens) {
  if (r.kind == RecordKind.album) {
    final kaal = _editieStaart(r.title) ?? _losseUitgave(r.title);
    if (kaal != null && mbAlbums.contains(discoKey(kaal))) return true;
  }
  if ((r.firstDate ?? '').compareTo(grens) < 0) return false;
  // Nieuw, maar een versie van iets wat MusicBrainz al heeft ("Insolitudes (Johnny 73)", 2026): weg.
  return !mbSleutels.contains(r.key) && !mbSleutels.contains(discoKey(_ontleed(r.title).kaal));
}

/// [r] met wat het nakijken van zijn nummers zei (zie `DiscographyService.nakijken`): een maxisingle
/// ([isMaxisingle]) naar de singles, een remixalbum ([isRemixAlbum]) naar de remixen. Anders ongewijzigd.
DiscoRelease metNagekekenSoort(DiscoRelease r, {required Set<int> singles, required Set<int> remixen}) {
  final id = r.refs[DiscoSource.deezer]?.intId;
  if (id == null) return r;
  final soort = singles.contains(id)
      ? RecordKind.single
      : remixen.contains(id)
          ? RecordKind.remix
          : r.kind;
  if (soort == r.kind) return r;
  return DiscoRelease(
    title: r.title,
    kind: soort,
    firstDate: r.firstDate,
    cover: r.cover,
    trackCount: r.trackCount,
    sources: r.sources,
    refs: r.refs,
  );
}

/// Achter de sleutel van een single of EP in [mergeDiscography]: zo staan ze los van een album met
/// dezelfde titel. Een teken dat in geen [discoKey] kan voorkomen.
const _klein = '\u0000klein';

bool _isKlein(RecordKind k) => k == RecordKind.single || k == RecordKind.ep;

/// Is "single" hier alleen Deezers etiket op dezelfde plaat die een andere bron een album noemt?
///
/// Dan blijft het één plaat. Deezer noemt Janet Jacksons "Unbreakable" (19 nummers, 71 minuten) een
/// single, en MusicBrainz en Discogs noemen het een album: uit elkaar gehouden kwam er een tegel bij
/// Albums zonder Deezer-link en een "single" van 71 minuten bij Singles. Alleen als geen andere bron
/// van een single of EP spreekt, én Deezer zelf niet ook een album met die titel heeft — want dan zijn
/// het voor Deezer zelf al twee platen ("Taking Chances": album en single, twee nummers).
bool _alleenDeezerZegtKlein(DiscoRelease klein, DiscoRelease groot) =>
    klein.sources.length == 1 &&
    klein.sources.contains(DiscoSource.deezer) &&
    !groot.sources.contains(DiscoSource.deezer);

/// Het omgekeerde: alleen Deezer noemt het een album, en MusicBrainz kent een EP of single met die naam.
///
/// Madonna's "Bedtime Stories – The Untold Chapter" (2025): Deezer "album", MusicBrainz EP. Dan geldt
/// MusicBrainz, waar mensen het soort per releasegroep vastleggen; Deezer krijgt het etiket van de
/// platenmaatschappij, en die noemt bij Madonna veertien remix-ep's een album (20-10-2026). Alleen met
/// MusicBrainz als getuige: een single die alleen Discogs kent zegt niet genoeg over een album dat
/// MusicBrainz niet kent.
bool _alleenDeezerZegtGroot(DiscoRelease klein, DiscoRelease groot) =>
    groot.sources.length == 1 &&
    groot.sources.contains(DiscoSource.deezer) &&
    groot.kind == RecordKind.album &&
    klein.sources.contains(DiscoSource.musicbrainz);

/// De titel zonder een aanduiding van wat de plaat IS — soundtrack, live, of een tweede naam als
/// "(N°3)" — of null. Geen uitgave-staart: die maakt een ander product, zie [heeftEditieStaart].
({String kaal, bool live})? _aanduiding(String title) {
  final t = title.trim();
  final bof = RegExp(r'^B\.?O\.?F\.?\s+', caseSensitive: false).firstMatch(t);
  if (bof != null) {
    final kaal = t.substring(bof.end).trim();
    return kaal.isEmpty ? null : (kaal: kaal, live: false);
  }
  final m = _staart.firstMatch(t);
  if (m != null) {
    final kaal = t.substring(0, m.start).trim();
    final binnen = normKey(m.group(0)!);
    if (kaal.isNotEmpty) {
      if (_soundtrackAanduiding.hasMatch(binnen) || _tweedeNaam.hasMatch(binnen)) {
        return (kaal: kaal, live: false);
      }
      if (_liveAanduiding.hasMatch(binnen)) return (kaal: kaal, live: true);
    }
  }
  // Of als laatste woorden, zonder haakjes: "Who's That Girl Soundtrack" (Deezer) en "Who’s That Girl:
  // Original Motion Picture Soundtrack" (MusicBrainz; de dubbele punt valt weg in de sleutel).
  final los = _losseSoundtrack.firstMatch(t);
  if (los != null) {
    final kaal = t.substring(0, los.start).trim();
    if (kaal.isNotEmpty) return (kaal: kaal, live: false);
  }
  return null;
}

final _losseSoundtrack = RegExp(r'\s+(original\s+)?(motion\s+picture\s+)?soundtrack$', caseSensitive: false);

/// "Bande originale du film", "… de la série TV", "… de la comédie musicale", "… du film de Claude
/// Berri" — Discogs en Deezer zetten er van alles achter; het blijft dezelfde soundtrack.
final _soundtrackAanduiding = RegExp(r'^(bande originale( d[eu]( la| l)? .+)?|musique( originale)? du film( .+)?|'
    r'(original )?(motion picture )?(sound ?track|score)( .+)?|ost|music from the motion picture( .+)?)$');
final _liveAanduiding = RegExp(r'^live( \d{4})?$');
final _tweedeNaam = RegExp(r'^n \d+$');

/// Vult ontbrekende hoezen aan uit een losse tabel, zonder ooit een regel toe te voegen.
///
/// Saber wees het aan op de pagina van Céline Dion: een blok "Verzamelaars" waarin de meeste tegels
/// een grijze schijf zijn. GEMETEN: van haar 274 regels missen er 55 een hoes, en 54 daarvan kent
/// alléén MusicBrainz — dat levert op releasegroep-niveau nooit een hoes, en de Cover Art Archive
/// evenmin (0 van 25 getoetst).
///
/// **Dat laatste hangt van de artiest af.** Bij Oasis (25-09-2026) hadden 32 van 39 live-opnames
/// zonder hoes er in het Cover Art Archive wél een, per releasegroep. Daarom vraagt de artiestpagina
/// het sindsdien per regel na — zie `MusicBrainzService.groepHoes` en [groepenZonderHoes] — en komt
/// het resultaat via deze zelfde functie binnen.
///
/// Aanvullen en niet vervangen: een hoes die er al is blijft staan, ongeacht wat de tabel zegt. Zo
/// kan deze stap een goede hoes nooit door een mindere vervangen, en is hij idempotent.
///
/// De sleutel is [discoKey], dezelfde waarop [mergeDiscography] beslist of twee regels dezelfde plaat
/// zijn. Bewust geen losser criterium: een hoes die bij de verkeerde plaat staat ziet er precies zo
/// uit als een hoes die klopt, en dat is een fout die je nooit meer opmerkt.
///
/// **Per plaat, niet per titel** (Seal, 24-10-2026): eerst op [plaatHoesSleutel] (de MusicBrainz-groep), en op de titel
/// alleen als geen andere regel die titel draagt. Anders kregen "Seal" 1991, 1994 en de krantenuitgave van 2007
/// alle drie dezelfde hoes — die van de krant.
List<DiscoRelease> vulHoezenAan(List<DiscoRelease> rijen, Map<String, String> hoesPerSleutel) {
  if (hoesPerSleutel.isEmpty) return rijen;
  final perTitel = <String, int>{};
  for (final r in rijen) {
    perTitel[r.key] = (perTitel[r.key] ?? 0) + 1;
  }
  String? hoesVan(DiscoRelease r) => hoesPerSleutel[plaatHoesSleutel(r)] ?? (perTitel[r.key] == 1 ? hoesPerSleutel[r.key] : null);
  return [
    for (final r in rijen)
      if (r.cover != null && r.cover!.isNotEmpty) r
      else if (hoesVan(r) case final h? when h.isNotEmpty)
        DiscoRelease(
          title: r.title,
          kind: r.kind,
          firstDate: r.firstDate,
          cover: h,
          trackCount: r.trackCount,
          sources: r.sources,
          refs: r.refs,
        )
      else
        r
  ];
}

/// De kale titel van een uitgave waarvan de staart een STERK uitgavewoord draagt, ook als er woorden
/// naast staan die [_uitgaveWoorden] niet kent; anders null.
///
/// Gemeten bij Madonna en Kylie (20-10-2026), allemaal tussen de studioalbums naast hun eigen album:
/// "Erotica (PA Version)", "Hard Candy (iTunes Deluxe Pre-Order)", "Confessions On A Dance Floor (Twenty
/// Years Edition)", "Kylie Christmas (Snow Queen Edition)", en na een dubbele punt "DISCO: Guest List
/// Edition" en "CONFESSIONS II: Afterhours Edition". Die woorden ("pa", "itunes", "snow queen") kan
/// geen lijst bijhouden; het uitgavewoord ernaast zegt genoeg — maar alleen samen met grendel 1 van
/// [vouwHeruitgaves]: het kale album staat er ook. "Tension II" heeft geen staart en blijft een album.
String? _losseUitgave(String title) {
  final t = title.trim();
  final m = _staart.firstMatch(t) ?? _dubbelpuntStaart.firstMatch(t) ?? _streepStaart.firstMatch(t);
  if (m == null) return null;
  final kaal = t.substring(0, m.start).trim();
  if (kaal.isEmpty) return null;
  return normKey(m.group(0)!).split(' ').any(_sterkeUitgaveWoorden.contains) ? kaal : null;
}

/// Een staart na een dubbele punt: "DISCO: Guest List Edition".
final _dubbelpuntStaart = RegExp(r'\s*:\s+[^:()\[\]{}]+$');

/// Woorden die op zichzelf al zeggen dat dit een uitgave is, geen andere plaat. Niet "the", "of",
/// "cd" of een jaartal uit [_uitgaveWoorden]: die zeggen pas iets als ELK woord van de staart meedoet.
const _sterkeUitgaveWoorden = {
  'deluxe', 'edition', 'editie', 'expanded', 'remaster', 'remastered', 'reissue', 'anniversary',
  'version', 'versie', 'jubileum', 'collector', 'remasterise', 'remasterisee',
};

/// Heruitgaves ZONDER haakjes bij hun eigen album vandaan: "Bad 25", "Thriller 40".
///
/// [heeftEditieStaart] ziet alleen een staart tussen haakjes, en Deezer en Discogs zetten die er vaak
/// niet omheen. Zonder deze stap staat "Thriller 40" gewoon tussen de studioalbums, met bijna
/// dezelfde naam als "Thriller" — precies wat [DiscoRelease.blok] moest voorkomen.
///
/// Dit kan niet in de `blok`-getter: die kent alleen zijn eigen regel, en de hele regel hier is dat
/// een uitgave alleen een uitgave is als het KALE album er óók staat.
///
/// Twee grendels, want een valse vouw verbergt een plaat en dat merk je nooit (zie [discoKey]):
///
/// 1. de kale titel moet als eigen regel in dezelfde lijst staan. "Thriller 40" vouwt alleen omdat
///    "Thriller" er ook is; staat die er niet, dan blijft het een album op zichzelf.
/// 2. een staart van louter cijfers moet een JUBILEUM zijn: het getal is minstens tien én het
///    jaarverschil klopt ermee. Thriller 1982 + 40 = 2022 ✓. Chicago 1970 + 17 ≠ 1984, dus
///    "Chicago 17" blijft het studioalbum dat het is — en dát is waarom een kaal getal niet genoeg
///    is. Zelfde soort val als "30" naast "30 ans de succès".
///
/// Staat er een echt uitgavewoord in de staart ("25th Anniversary", "Super Deluxe"), dan is dát al de
/// uitspraak en hoeft grendel 2 niet.
///
/// En een staart MET haakjes of na een dubbele punt die een sterk uitgavewoord draagt naast woorden die
/// [_uitgaveWoorden] niet kent — zie [_losseUitgave]. Ook die alleen onder grendel 1.
///
/// Verandert alleen [DiscoRelease.kind]; gooit nooit een regel weg. Onafhankelijk van de
/// aanvoervolgorde en idempotent — de pagina roept dit bij elke hertekening aan.
List<DiscoRelease> vouwHeruitgaves(List<DiscoRelease> rijen) {
  // Eerst de foto van de kale albums, uit de ONGEWIJZIGDE invoer. Zo kan een uitgave nooit zelf als
  // basis voor een volgende uitgave dienen, en hangt de uitkomst niet van de volgorde af.
  final basis = <String, int?>{};
  for (final r in rijen) {
    if (r.blok == RecordKind.album) basis.putIfAbsent(r.key, () => r.year);
  }

  bool isHeruitgave(DiscoRelease r) {
    if (r.kind != RecordKind.album || heeftEditieStaart(r.title)) return false;
    final los = _losseUitgave(r.title);
    if (los != null && discoKey(los) != r.key && basis.containsKey(discoKey(los))) return true;
    final w = r.key.split(' ').where((x) => x.isNotEmpty).toList();
    for (var n = 1; n <= 4 && n < w.length; n++) {
      final staart = w.sublist(w.length - n);
      if (!staart.every((x) => _uitgaveWoorden.contains(x) || _getalWoord.hasMatch(x))) break;
      final kaal = w.sublist(0, w.length - n).join(' ');
      if (!basis.containsKey(kaal)) continue;
      if (staart.any(_uitgaveWoorden.contains)) return true;
      // Alleen cijfers: dan moet het jaarverschil het jubileum bevestigen.
      if (staart.length != 1) continue;
      final getal = int.tryParse(staart.first);
      final jaarBasis = basis[kaal], jaarDeze = r.year;
      if (getal == null || getal < 10 || jaarBasis == null || jaarDeze == null) continue;
      if ((jaarDeze - jaarBasis - getal).abs() <= 1) return true;
    }
    return false;
  }

  return [
    for (final r in rijen)
      if (isHeruitgave(r))
        DiscoRelease(
          title: r.title,
          kind: RecordKind.albumVersie,
          firstDate: r.firstDate,
          cover: r.cover,
          trackCount: r.trackCount,
          sources: r.sources,
          refs: r.refs,
        )
      else
        r
  ];
}

/// Welke soorten geen blok op de pagina krijgen.
///
/// Los en publiek, want de pagina moet kunnen VERTELLEN wat ze weglaat. Een lijst die stilzwijgend
/// tweederde overslaat is geen betere lijst, alleen een kortere.
const verborgenSoorten = {
  RecordKind.other,
  RecordKind.demo,
  RecordKind.gesproken,
  // Dvd's, blu-rays en videobanden: Saber vroeg ze eruit. De live PLATEN blijven staan — dat regelt
  // [_uitspraakRang], waar elke geluidsuitspraak van video wint.
  RecordKind.video,
  // En radioplaten: BBC Rock Hour, Innerview, Off The Record Specials. Zie [isTranscriptie] — bij
  // The Police waren dat twintig van de drieëndertig "albums".
  RecordKind.uitzending,
};

/// Wat er van de discografie op het scherm hoort te staan — en wat er wegviel, en waarom.
typedef DiscoZeef = ({
  /// Wat getoond wordt. Bij `toonAlles` is dit de hele lijst, en zeggen de tellingen wat er
  /// verborgen ZOU zijn.
  List<DiscoRelease> rijen,
  int verborgen,
  int zonderHoes,
  Map<RecordKind, int> perSoort,
});

/// De regels die de pagina niet laat zien, geteld en benoemd.
///
/// GEMETEN op Michael Jackson: van 252 samengevoegde regels blijven er 99 over — 34 vallen af omdat
/// er geen hoes is en 119 omdat ze in "Overig" zaten. Dat is geen opruimen maar een ingreep, en
/// daarom levert deze functie de TELLING mee: de pagina zet eronder wat ze weglaat, met een knop die
/// alles terugzet. Een filter zonder uitweg is een filter dat je niet kunt controleren.
///
/// NA [vulHoezenAan] aanroepen, nooit ervoor. "Bad" (1987) draagt in de samenvoeging geen hoes en
/// krijgt er pas een uit de Discogs-zoeksweep; andersom om gooit dit precies de platen weg die het
/// hardst op de pagina horen.
///
/// [zeefHoezen] uit zetten als die sweep niet gedraaid heeft. Zonder Discogs-token levert hij niets,
/// en dan zou de hoesregel élke plaat wegvegen die alleen MusicBrainz kent — Off The Wall, Dangerous
/// en Invincible staan bij deze artiest nergens anders.
DiscoZeef zeefDiscografie(
  List<DiscoRelease> alles, {
  bool toonAlles = false,
  bool zeefHoezen = true,
}) {
  final houden = <DiscoRelease>[];
  final perSoort = <RecordKind, int>{};
  var zonderHoes = 0;

  for (final r in alles) {
    if (zeefHoezen && (r.cover == null || r.cover!.isEmpty)) {
      zonderHoes++;
      continue;
    }
    final b = r.blok;
    if (verborgenSoorten.contains(b)) {
      perSoort[b] = (perSoort[b] ?? 0) + 1;
      continue;
    }
    houden.add(r);
  }

  return (
    rijen: toonAlles ? alles : houden,
    verborgen: alles.length - houden.length,
    zonderHoes: zonderHoes,
    perSoort: perSoort,
  );
}

/// De discografie zoals hij op het scherm kwam, en vanaf dan zo blijft (Saber, 18-10-2026).
///
/// De bronnen kwamen na elkaar binnen en bij elke bron verschoof de lijst: Deezer eerst, dan
/// MusicBrainz en Discogs, dan de hoezen van het archief (en die lieten regels zonder hoes
/// verdwijnen), dan de gastoptredens (en die haalden regels weg). Saber koos voor "pas tonen als hij
/// compleet is". Hij staat er dus één keer, en tijdens het bezoek komt er alleen nog een hoes bij.
///
/// [samen] is al gevouwen ([vouwHeruitgaves]) en zonder gastoptredens. [zeefHoezen] is de hoesregel
/// zoals die gold toen de lijst verscheen.
typedef VasteDisco = ({List<DiscoRelease> samen, bool zeefHoezen});

VasteDisco bevriesDiscografie(List<DiscoRelease> alles, {required bool zeefHoezen}) =>
    (samen: vouwHeruitgaves(alles), zeefHoezen: zeefHoezen);

/// Wat [vast] laat zien, met de hoezen die er sindsdien bij kwamen.
///
/// **De zeef beslist op de hoezen van het moment waarop de lijst verscheen**, niet op die van nu.
/// Anders komt een regel die wegviel omdat hij geen hoes had, alsnog tevoorschijn zodra het archief
/// er een vindt, en schuift alles eronder op. Een hoes die binnenkomt vult alleen een tegel in.
DiscoZeef toonVast(VasteDisco vast, Map<String, String> hoezen, {bool toonAlles = false}) {
  final z = zeefDiscografie(vast.samen, toonAlles: toonAlles, zeefHoezen: vast.zeefHoezen);
  return (
    rijen: vulHoezenAan(z.rijen, hoezen),
    verborgen: z.verborgen,
    zonderHoes: z.zonderHoes,
    perSoort: z.perSoort,
  );
}

/// Waarop de gebruiker kan sorteren.
///
/// [datumOud] staat vooraan omdat het menu de declaratievolgorde volgt en dit de stand is waarin de
/// pagina opengaat.
enum DiscoSort { datumOud, datum, bezit, type }

extension DiscoSortX on DiscoSort {
  String get label => switch (this) {
        DiscoSort.datumOud => 'Release (oud→nieuw)',
        DiscoSort.datum => 'Release (nieuw→oud)',
        DiscoSort.bezit => 'Wat ik heb',
        DiscoSort.type => 'Titel (A–Z)',
      };
}

/// Gesorteerd, met een TOTALE orde.
///
/// Elke vergelijking eindigt op de sleutel, zodat twee regels met dezelfde datum nooit tussen twee
/// hertekeningen van plek wisselen. Zonder die laatste stap springt de lijst zichtbaar zodra er een
/// bron bij komt.
///
/// [bezit] bevat de [discoKey]s van wat er in de bibliotheek staat. Bewust een argument en geen veld
/// op [DiscoRelease]: bezit is iets van de bibliotheek, niet van de plaat, en zo blijft samenvoegen
/// puur.
List<DiscoRelease> sortDiscography(List<DiscoRelease> in_, DiscoSort op, Set<String> bezit) {
  // Ongedateerd hoort ACHTERAAN, bij beide richtingen. Een kale tekstvergelijking op '' zet ze bij
  // oplopend juist vooraan — dezelfde val waarvoor `_sortAlbums` elders `?? 9999` gebruikt.
  int opDatum(DiscoRelease a, DiscoRelease b, {bool oplopend = false}) {
    final da = a.firstDate ?? '', db = b.firstDate ?? '';
    if (da.isEmpty && db.isEmpty) return 0;
    if (da.isEmpty) return 1;
    if (db.isEmpty) return -1;
    return oplopend ? da.compareTo(db) : db.compareTo(da);
  }

  final uit = [...in_];
  uit.sort((a, b) {
    switch (op) {
      case DiscoSort.datumOud:
        final d = opDatum(a, b, oplopend: true);
        if (d != 0) return d;
      case DiscoSort.datum:
        final d = opDatum(a, b);
        if (d != 0) return d;
      case DiscoSort.bezit:
        final ha = bezit.contains(a.key), hb = bezit.contains(b.key);
        if (ha != hb) return ha ? -1 : 1;
        final d = opDatum(a, b);
        if (d != 0) return d;
      case DiscoSort.type:
        // Het TYPE bepaalt nu het blok, dus binnen een blok is sorteren op type zinloos. Hier is
        // alfabetisch het bruikbare antwoord: een plaat terugvinden waarvan je de naam weet.
        final t = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        if (t != 0) return t;
    }
    return a.key.compareTo(b.key);
  });
  return uit;
}

/// De regels die het Cover Art Archive nog om een hoes mogen vragen, in de volgorde van de pagina.
///
/// Alleen regels ZONDER hoes en MET een MusicBrainz-releasegroep: van een groep kent het archief de
/// voorkant, van een Deezer- of Discogs-nummer niets. Soorten die de pagina toch verbergt (demo's,
/// video, radio — zie [verborgenSoorten]) blijven buiten: dat zijn verzoeken voor tegels die
/// niemand ziet. In de volgorde van de blokken, zodat de albums bovenaan het eerst antwoord krijgen.
List<({String sleutel, String mbid})> groepenZonderHoes(List<DiscoRelease> rijen) {
  final uit = <({String sleutel, String mbid, int rang})>[];
  for (final r in rijen) {
    if (r.cover != null && r.cover!.isNotEmpty) continue;
    if (verborgenSoorten.contains(r.blok)) continue;
    final ref = r.refs[DiscoSource.musicbrainz];
    if (ref == null || ref.source != CatalogSource.musicbrainzGroup || ref.id.isEmpty) continue;
    uit.add((sleutel: plaatHoesSleutel(r), mbid: ref.id, rang: kindRank(r.blok)));
  }
  uit.sort((a, b) => a.rang.compareTo(b.rang));
  return [for (final u in uit) (sleutel: u.sleutel, mbid: u.mbid)];
}

/// Waaronder de hoes van [r] bewaard wordt: zijn MusicBrainz-groep als hij die heeft, anders zijn titel
/// ([DiscoRelease.key]). Twee platen met dezelfde titel (Seal, 1991 en 1994) krijgen zo elk hun eigen hoes.
String plaatHoesSleutel(DiscoRelease r) {
  final mb = r.refs[DiscoSource.musicbrainz];
  return mb != null && mb.id.isNotEmpty ? 'mb:${mb.id}' : r.key;
}

/// Hoeveel tegels er naast elkaar passen, met dezelfde som als het raster zelf.
///
/// `SliverGridDelegateWithMaxCrossAxisExtent` rekent `(breedte / (max + tussenruimte)).ceil()`. Een
/// eigen, andere som zou een ingeklapt blok van "twee rijen" soms anderhalve rij laten tonen.
int kolommenVoor(double breedte, {double max = 180, double tussen = 14}) =>
    breedte <= 0 ? 1 : (breedte / (max + tussen)).ceil().clamp(1, 1 << 16);

/// Hoeveel regels een blok toont: ingeklapt [rijen] rijen, open alles.
///
/// Gevraagd op 25-09-2026 bij Oasis: tweehonderd live-opnames onder elkaar is geen overzicht meer.
/// Een blok dat al in twee rijen past, toont gewoon alles — een knop "toon alle 9" onder negen
/// tegels is een knop voor niets.
int zichtbaarInBlok({required int aantal, required int kolommen, required bool open, int rijen = 2}) {
  if (open) return aantal;
  final max = kolommen * rijen;
  return aantal <= max ? aantal : max;
}
