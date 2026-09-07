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
enum RecordKind { album, albumVersie, live, ep, single, remix, compilation, demo, gesproken, other }

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
    final m = _staart.firstMatch(t);
    if (m == null) break;
    final binnen = normKey(m.group(0)!).split(' ').where((w) => w.isNotEmpty);
    if (binnen.isEmpty) break;
    if (!binnen.every((w) => _uitgaveWoorden.contains(w) || _getalWoord.hasMatch(w))) break;
    t = t.substring(0, m.start).trim();
    gevonden = true;
  }
  return gevonden ? t : null;
}

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
  final f = format.toLowerCase();
  if (f.contains('compilation')) return RecordKind.compilation;
  // Op deelreeksen en niet op hele woorden: "maxi-single" en "single" moeten allebei tellen. Wel EP
  // eerst, want "EP" komt ook naast "Single" voor en is dan het specifiekere antwoord.
  if (RegExp(r'\bep\b').hasMatch(f)) return RecordKind.ep;
  if (f.contains('single')) return RecordKind.single;
  if (f.contains('album') || RegExp(r'\blp\b').hasMatch(f)) return RecordKind.album;
  return RecordKind.other;
}

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
};

final _staart = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]\s*$');

/// Een jaartal of een rangtelwoord: "2021", "25th", "10e".
///
/// Als één woord, want [normKey] plakt cijfer en achtervoegsel aan elkaar. Ze los in de woordenlijst
/// zetten helpt dus niet — "25th" is nooit "25" plus "th".
final _getalWoord = RegExp(r'^\d+(st|nd|rd|th|e|de|ste)?$');

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
        RecordKind.gesproken =>
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
      RecordKind.other => 9,
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
      RecordKind.other => 6,
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
List<DiscoRelease> mergeDiscography(List<List<DiscoRelease>> bronnen) {
  final samen = <String, DiscoRelease>{};
  for (final lijst in bronnen) {
    for (final r in lijst) {
      final k = r.key;
      if (k.isEmpty) continue;
      final bestaand = samen[k];
      samen[k] = bestaand == null ? r : bestaand.mergedWith(r);
    }
  }
  return samen.values.toList();
}

/// Vult ontbrekende hoezen aan uit een losse tabel, zonder ooit een regel toe te voegen.
///
/// Saber wees het aan op de pagina van Céline Dion: een blok "Verzamelaars" waarin de meeste tegels
/// een grijze schijf zijn. GEMETEN: van haar 274 regels missen er 55 een hoes, en 54 daarvan kent
/// alléén MusicBrainz — dat levert op releasegroep-niveau nooit een hoes, en de Cover Art Archive
/// evenmin (0 van 25 getoetst).
///
/// Aanvullen en niet vervangen: een hoes die er al is blijft staan, ongeacht wat de tabel zegt. Zo
/// kan deze stap een goede hoes nooit door een mindere vervangen, en is hij idempotent.
///
/// De sleutel is [discoKey], dezelfde waarop [mergeDiscography] beslist of twee regels dezelfde plaat
/// zijn. Bewust geen losser criterium: een hoes die bij de verkeerde plaat staat ziet er precies zo
/// uit als een hoes die klopt, en dat is een fout die je nooit meer opmerkt.
List<DiscoRelease> vulHoezenAan(List<DiscoRelease> rijen, Map<String, String> hoesPerSleutel) {
  if (hoesPerSleutel.isEmpty) return rijen;
  return [
    for (final r in rijen)
      if (r.cover != null && r.cover!.isNotEmpty) r
      else if (hoesPerSleutel[r.key] case final h? when h.isNotEmpty)
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
const verborgenSoorten = {RecordKind.other, RecordKind.demo, RecordKind.gesproken};

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
