/// De biografie van een artiest, uit Wikipedia.
///
/// **Waarom hier een tweede bron bij komt.** De app leest biografieën van TheAudioDB, en die zijn
/// kort. GEMETEN op 10-09-2026 voor Michael Jackson: de Nederlandse Wikipedia heeft **27.847**
/// tekens, TheAudioDB **2.357** — en die 2.357 blijken een oudere KOPIE van precies datzelfde
/// artikel. Waar Wikipedia inmiddels "tussen 400 en 500 miljoen" zegt, staat er bij TheAudioDB nog
/// "tussen 300 en 400 miljoen". Het is dus niet twee bronnen naast elkaar maar dezelfde tekst,
/// afgeknipt en verouderd.
///
/// TheAudioDB blijft de terugval: niet elke act heeft een artikel.
///
/// # De weg naar het juiste artikel
///
/// Naam → MBID → Wikidata → sitelink → titel. Niet zoeken op naam: dat levert naamgenoten, dezelfde
/// val als bij `resolveArtist` ("Backstreet" mag geen "Backstreet Girls" worden). MusicBrainz heeft
/// géén relatie van het soort `wikipedia` maar wél een van het soort `wikidata` — gemeten op
/// dezelfde dag — en Wikidata geeft in één verzoek de titel in elke taal.
///
/// Lukt die weg niet, dan is er een zoekval-terug die alléén een treffer aanneemt waarvan de titel
/// na [normKey] gelijk is aan de naam. Anders: een misteken schrijven en TheAudioDB laten staan.
///
/// # Bronvermelding
///
/// De tekst is CC BY-SA. [WikiArtikel.url] hoort ONVOORWAARDELIJK onder de tekst te staan, met de
/// titel als link — niet verborgen bij ingeklapt, niet weggelaten op een televisie, niet
/// overgeslagen bij een kort artikel. Anders verspreidt de app andermans tekst zonder vermelding.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cachesleutel.dart';
import 'json_body.dart';
import 'musicbrainz.dart';
import 'organize.dart' show normKey;
import 'paths.dart';

/// Eén sectie uit een artikel: een kop, zijn niveau, en de tekst eronder.
class WikiAfdeling {
  final int niveau;
  final String kop, tekst;
  const WikiAfdeling({required this.niveau, required this.kop, required this.tekst});

  Map<String, dynamic> toJson() => {'n': niveau, 'k': kop, 't': tekst};

  static WikiAfdeling? fromJson(Object? j) {
    if (j is! Map) return null;
    final kop = (j['k'] as String?)?.trim() ?? '';
    final tekst = (j['t'] as String?)?.trim() ?? '';
    if (kop.isEmpty || tekst.isEmpty) return null;
    return WikiAfdeling(niveau: (j['n'] as num?)?.toInt() ?? 2, kop: kop, tekst: tekst);
  }
}

/// Wat er van één Wikipedia-pagina bewaard wordt.
class WikiArtikel {
  final String taal, titel, intro;
  final List<WikiAfdeling> afdelingen;

  /// Het hoofdbeeld van de pagina, als er een is.
  ///
  /// **Let op: dit is lang niet altijd een foto.** GEMETEN over vier artiesten uit deze
  /// bibliotheek: Adele 1725×2096 (foto) · Michael Jackson 2291×3046 (foto) · Stromae 470×574
  /// (foto, kleiner dan TheAudioDB's fanart) · The Police 459×225 (`The_Police-logo.png`) · Daft
  /// Punk 381×260 (`Daft_Punk_logo.svg`). **Twee van de vier zijn een woordmerk.** Wie dit als
  /// achtergrond wil gebruiken heeft dus een logowacht nodig, niet alleen een vormtoets — een logo
  /// van 459×225 heeft verhouding 2,04 en haalt elke "is dit liggend"-poort.
  final String? beeldUrl;
  final int beeldBreedte, beeldHoogte;

  /// Wanneer dit opgehaald is, zodat een oude kopie meteen getoond kan worden terwijl er een verse
  /// achter binnenkomt.
  final int haaldMs;

  const WikiArtikel({
    required this.taal,
    required this.titel,
    required this.intro,
    this.afdelingen = const [],
    this.beeldUrl,
    this.beeldBreedte = 0,
    this.beeldHoogte = 0,
    this.haaldMs = 0,
  });

  /// De pagina zelf, voor de bronvermelding.
  String get url =>
      'https://$taal.wikipedia.org/wiki/${Uri.encodeComponent(titel.replaceAll(' ', '_'))}';

  /// Het merk staat ZOWEL in de bestandsnaam als hierin.
  ///
  /// `AlbumInfo` leerde de eerste les (een veld toevoegen aan een cache zonder de naam te wijzigen
  /// doet voor bestaande regels niets) en `ArtistArt` de tweede (een `v`-veld dat bij mismatch null
  /// teruggeeft). Een gloednieuw bestand mag ze gratis allebei hebben.
  static const schema = 1;

  bool get isEmpty => intro.trim().isEmpty && afdelingen.isEmpty;

  Map<String, dynamic> toJson() => {
        'v': schema,
        'taal': taal,
        'titel': titel,
        'intro': intro,
        'afdelingen': [for (final a in afdelingen) a.toJson()],
        if (beeldUrl != null) 'beeld': beeldUrl,
        if (beeldBreedte > 0) 'bb': beeldBreedte,
        if (beeldHoogte > 0) 'bh': beeldHoogte,
        'haald': haaldMs,
      };

  /// Null bij een ander schema — dan haalt de aanroeper hem opnieuw op.
  static WikiArtikel? fromJson(Map<String, dynamic> j) {
    if ((j['v'] as num?)?.toInt() != schema) return null;
    final taal = (j['taal'] as String?)?.trim() ?? '';
    final titel = (j['titel'] as String?)?.trim() ?? '';
    if (taal.isEmpty || titel.isEmpty) return null;
    return WikiArtikel(
      taal: taal,
      titel: titel,
      intro: (j['intro'] as String?) ?? '',
      afdelingen: [
        for (final a in (j['afdelingen'] as List?) ?? const [])
          if (WikiAfdeling.fromJson(a) case final w?) w,
      ],
      beeldUrl: j['beeld'] as String?,
      beeldBreedte: (j['bb'] as num?)?.toInt() ?? 0,
      beeldHoogte: (j['bh'] as num?)?.toInt() ?? 0,
      haaldMs: (j['haald'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Koppen die niets zeggen zodra de tabel eronder wegvalt.
///
/// `explaintext` rendert tabellen en lijsten met verwijzingen als NIETS, dus deze komen terug als
/// een kop boven een leegte. Een kopje dat opengeklapt niets toont is erger dan geen kopje.
const _staartKoppen = <String>[
  'zie ook',
  'externe links',
  'externe link',
  'literatuur',
  'bronnen noten en of referenties',
  'referenties',
  'noten',
  'voetnoten',
  'bibliografie',
  'see also',
  'external links',
  'references',
  'notes',
  'further reading',
  'bibliography',
  'citations',
];

/// Knipt een `explaintext`-uittreksel in een inleiding en losse secties.
///
/// **`exsectionformat=wiki` en niet `raw`.** GEMETEN op 10-09-2026: `raw` levert zijn
/// scheidingstekens als **U+FFFD** (`EF BF BD`) — het vervangingsteken, oftewel precies het teken
/// dat al "deze tekst is stuk" betekent. In een repo die `mojibake.dart` heeft omdat dat teken ook
/// om ándere redenen opduikt, is dat het slechtst denkbare scheidingsteken. `wiki` geeft schoon
/// `== Kop ==`.
///
/// **De terugverwijzing `\1` alléén is niet genoeg**, en dat bleek pas uit de toets. Met
/// `(.+?)` mag de luie groep het overtollige teken gewoon opslokken: in `== Scheef ===` wordt de kop
/// dan "Scheef =" en matcht `\1` de laatste twee. Vandaar `(.*?[^=\s])` — de kop mag niet op een `=`
/// eindigen, en dan is er geen manier meer om de tekens ongelijk te krijgen.
///
/// Puur en op topniveau, zodat `test/wikipedia_afdelingen_test.dart` er geen netwerk voor nodig
/// heeft.
({String intro, List<WikiAfdeling> afdelingen}) ontleedAfdelingen(String uittreksel) {
  final kopjes = RegExp(r'^(={2,6})[ \t]*(.*?[^=\s])[ \t]*\1[ \t]*$', multiLine: true);
  final treffers = kopjes.allMatches(uittreksel).toList();
  if (treffers.isEmpty) {
    return (intro: uittreksel.trim(), afdelingen: const <WikiAfdeling>[]);
  }

  final intro = uittreksel.substring(0, treffers.first.start).trim();
  final uit = <WikiAfdeling>[];
  for (var i = 0; i < treffers.length; i++) {
    final t = treffers[i];
    final eind = i + 1 < treffers.length ? treffers[i + 1].start : uittreksel.length;
    final kop = (t.group(2) ?? '').trim();
    final tekst = uittreksel.substring(t.end, eind).trim();
    // Leeg? Weglaten. Zie [_staartKoppen] — dit vangt er meer dan alleen de staart, want ook
    // "Discografie" en "Prijzen" zijn bij deze artiesten enkel een tabel.
    if (kop.isEmpty || tekst.isEmpty) continue;
    if (_staartKoppen.contains(normKey(kop))) continue;
    uit.add(WikiAfdeling(niveau: (t.group(1) ?? '==').length, kop: kop, tekst: tekst));
  }
  return (intro: intro, afdelingen: uit);
}

/// Haalt en bewaart artikelen. Eén per artiest, met een misteken als er geen is.
class WikipediaService {
  /// Wikimedia vraagt om een agent die zichzelf noemt en zegt hoe je de schrijver bereikt.
  ///
  /// De derde kopie van deze tekst (`enrichment.dart` en `musicbrainz.dart` hebben er elk een).
  /// Samenvoegen is een aparte, mechanische opruiming en hoort niet in deze verbouwing thuis.
  static const _ua = 'DebridMusic/1.0 ( https://github.com/sabair24/Debrid-music-app )';

  /// Eén verzoek per seconde, via de lane die MusicBrainz al heeft.
  ///
  /// Die is statisch, generiek over een naam, `@visibleForTesting`, en hij overleeft een klok die
  /// terugloopt — dat laatste doet `CoverEnricher._audioDbSlot` niet. Een vierde eigen wachtrij
  /// bouwen zou de vierde plek zijn waar iemand die val opnieuw kan zetten.
  static const _lane = 'wikimedia';
  static const _gap = Duration(seconds: 1);

  /// Hoe lang een artikel vers genoeg is. Erna wordt de oude kopie nog wél meteen getoond en
  /// ververst hij erachter — naar het model van de artiestpagina, die ook eerst tekent en dan
  /// overschrijft.
  static const _versGenoeg = Duration(days: 30);

  /// "Deze act heeft geen artikel" mag lang blijven staan; "het lukte even niet" niet.
  static const _misGevonden = Duration(days: 7);
  static const _misHaperend = Duration(hours: 1);

  Directory get _dir => Directory('$appDir${Platform.pathSeparator}wikipedia');

  File _naamFile(String naam) =>
      File('${_dir.path}${Platform.pathSeparator}${fnv1a('a1|${naam.toLowerCase()}')}.json');
  File _artikelFile(String taal, String titel) =>
      File('${_dir.path}${Platform.pathSeparator}${fnv1a('t1|$taal|$titel')}.json');

  // ── Mistekens ─────────────────────────────────────────────────────────────
  // Dezelfde vorm als `musicbrainz.dart`: een gewoon JSON-bestand met alleen `_miss`, herkenbaar
  // aan zijn grootte. Zo hoeft er geen tweede soort bestand te bestaan naast de echte antwoorden.

  Map<String, dynamic> _misteken({required bool nietGevonden}) =>
      {'_miss': DateTime.now().millisecondsSinceEpoch, if (nietGevonden) '_notfound': true};

  bool _isMis(Map<String, dynamic> j) => j['_miss'] is num && j.length <= 2;

  /// Geldt dit misteken nog? Zo ja: niet opnieuw vragen.
  bool _misGeldt(Map<String, dynamic> j) {
    final toen = DateTime.fromMillisecondsSinceEpoch((j['_miss'] as num).toInt());
    final duur = j['_notfound'] == true ? _misGevonden : _misHaperend;
    return DateTime.now().difference(toen) <= duur;
  }

  Future<Map<String, dynamic>?> _lees(File f) async {
    try {
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _schrijf(File f, Map<String, dynamic> j) async {
    try {
      await _dir.create(recursive: true);
      await f.writeAsString(jsonEncode(j));
    } catch (_) {/* een cache die niet geschreven kan worden kost één herhaald verzoek */}
  }

  Future<Map<String, dynamic>?> _haal(Uri url) async {
    try {
      await MusicBrainzService.laneSlot(_lane, _gap);
      final r = await http
          .get(url, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonBody(r);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  // ── Naam naar titel ───────────────────────────────────────────────────────

  /// Welke pagina bij deze artiest hoort, en in welke taal.
  ///
  /// Apart bewaard van het artikel zelf: dit kost twee verzoeken en verandert vrijwel nooit,
  /// terwijl het artikel wél ververst wordt.
  Future<({String taal, String titel})?> titelVoor(String naam, {String? mbid}) async {
    final f = _naamFile(naam);
    final bewaard = await _lees(f);
    if (bewaard != null) {
      if (_isMis(bewaard)) {
        if (_misGeldt(bewaard)) return null;
      } else {
        final taal = (bewaard['taal'] as String?) ?? '';
        final titel = (bewaard['titel'] as String?) ?? '';
        if (taal.isNotEmpty && titel.isNotEmpty) return (taal: taal, titel: titel);
      }
    }

    final gevonden = await _zoekTitel(naam, mbid: mbid);
    if (gevonden == null) {
      await _schrijf(f, _misteken(nietGevonden: true));
      return null;
    }
    await _schrijf(f, {'taal': gevonden.taal, 'titel': gevonden.titel, 'q': gevonden.q});
    return (taal: gevonden.taal, titel: gevonden.titel);
  }

  Future<({String taal, String titel, String? q})?> _zoekTitel(String naam, {String? mbid}) async {
    // 1. Over Wikidata, als MusicBrainz de artiest kent. Dit is de weg zonder gokwerk.
    var q = mbid == null ? null : await MusicBrainzService().wikidataId(mbid);
    q ??= await _wikidataViaNaam(naam);
    if (q != null) {
      final sitelink = await _sitelink(q);
      if (sitelink != null) return (taal: sitelink.taal, titel: sitelink.titel, q: q);
    }
    // 2. Zoeken op naam, en ALLEEN een titel aannemen die na normKey gelijk is. Zonder die tucht
    //    wordt "Air" het scheikundige artikel en "Bush" een president.
    for (final taal in ['nl', 'en']) {
      final j = await _haal(Uri.parse('https://$taal.wikipedia.org/w/api.php'
          '?action=query&list=search&srsearch=${Uri.encodeQueryComponent(naam)}'
          '&srlimit=3&format=json&formatversion=2'));
      final rijen = ((j?['query'] as Map?)?['search'] as List?) ?? const [];
      for (final rij in rijen) {
        final titel = ((rij as Map?)?['title'] as String?)?.trim() ?? '';
        if (titel.isNotEmpty && normKey(titel) == normKey(naam)) {
          return (taal: taal, titel: titel, q: null);
        }
      }
    }
    return null;
  }

  /// Wikidata's eigen zoekfunctie, als er geen MBID is.
  Future<String?> _wikidataViaNaam(String naam) async {
    final j = await _haal(Uri.parse('https://www.wikidata.org/w/api.php'
        '?action=wbsearchentities&search=${Uri.encodeQueryComponent(naam)}'
        '&language=nl&uselang=nl&type=item&limit=3&format=json'));
    for (final rij in (j?['search'] as List?) ?? const []) {
      if (rij is! Map) continue;
      final label = (rij['label'] as String?)?.trim() ?? '';
      final id = rij['id'] as String?;
      if (id != null && normKey(label) == normKey(naam)) return id;
    }
    return null;
  }

  /// De artikeltitel bij een Wikidata-nummer, Nederlands vóór Engels.
  Future<({String taal, String titel})?> _sitelink(String q) async {
    final j = await _haal(Uri.parse('https://www.wikidata.org/w/api.php'
        '?action=wbgetentities&ids=$q&props=sitelinks&sitefilter=nlwiki%7Cenwiki&format=json'));
    final links = (((j?['entities'] as Map?)?[q] as Map?)?['sitelinks'] as Map?) ?? const {};
    for (final (sleutel, taal) in [('nlwiki', 'nl'), ('enwiki', 'en')]) {
      final titel = ((links[sleutel] as Map?)?['title'] as String?)?.trim() ?? '';
      if (titel.isNotEmpty) return (taal: taal, titel: titel);
    }
    return null;
  }

  // ── Het artikel ───────────────────────────────────────────────────────────

  /// De biografie van deze artiest, of null als Wikipedia hem niet heeft.
  ///
  /// [fetch] op false leest alleen van schijf en doet géén enkel verzoek — dezelfde stand die
  /// `CoverEnricher.albumInfo` heeft, zodat een scherm meteen kan tekenen met wat er al ligt.
  Future<WikiArtikel?> artikel(String naam, {String? mbid, bool fetch = true}) async {
    final waar = await (fetch
        ? titelVoor(naam, mbid: mbid)
        : _lees(_naamFile(naam)).then((j) {
            if (j == null || _isMis(j)) return null;
            final taal = (j['taal'] as String?) ?? '';
            final titel = (j['titel'] as String?) ?? '';
            return taal.isEmpty || titel.isEmpty ? null : (taal: taal, titel: titel);
          }));
    if (waar == null) return null;

    final f = _artikelFile(waar.taal, waar.titel);
    final bewaard = await _lees(f);
    WikiArtikel? oud;
    if (bewaard != null && !_isMis(bewaard)) oud = WikiArtikel.fromJson(bewaard);
    if (!fetch) return oud;

    final vers = oud != null &&
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(oud.haaldMs))
                .compareTo(_versGenoeg) <=
            0;
    if (vers) return oud;

    final nieuw = await _haalArtikel(waar.taal, waar.titel);
    if (nieuw == null) return oud; // niets nieuws? dan blijft de oude kopie staan
    await _schrijf(f, nieuw.toJson());
    return nieuw;
  }

  Future<WikiArtikel?> _haalArtikel(String taal, String titel) async {
    // Eén verzoek voor alle drie: de tekst, het hoofdbeeld en het Wikidata-nummer.
    final j = await _haal(Uri.parse('https://$taal.wikipedia.org/w/api.php'
        '?action=query&prop=extracts%7Cpageimages%7Cpageprops'
        '&explaintext=1&exsectionformat=wiki'
        '&piprop=original%7Cthumbnail&pithumbsize=2560'
        '&titles=${Uri.encodeQueryComponent(titel)}&format=json&formatversion=2'));
    final paginas = ((j?['query'] as Map?)?['pages'] as List?) ?? const [];
    if (paginas.isEmpty) return null;
    final p = paginas.first as Map<String, dynamic>;
    final uittreksel = (p['extract'] as String?)?.trim() ?? '';
    if (uittreksel.isEmpty) return null;

    final stukken = ontleedAfdelingen(uittreksel);
    // De MINIATUUR bewaren en niet het origineel: Wikimedia schaalt server-side naar
    // `pithumbsize`, dus het bestand komt al op het plafond binnen zonder dat wij één pixel
    // decoderen. De opgegeven maat van het ORIGINEEL blijft wel staan, want daarop wordt gescoord.
    final mini = p['thumbnail'] as Map?;
    final orig = p['original'] as Map?;
    return WikiArtikel(
      taal: taal,
      titel: (p['title'] as String?)?.trim() ?? titel,
      intro: stukken.intro,
      afdelingen: stukken.afdelingen,
      beeldUrl: _zonderVolgsleutels((mini?['source'] ?? orig?['source']) as String?),
      beeldBreedte: (orig?['width'] as num?)?.toInt() ?? 0,
      beeldHoogte: (orig?['height'] as num?)?.toInt() ?? 0,
      haaldMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Wikimedia plakt sinds kort `?utm_source=…&utm_campaign=api` achter beeld-urls.
  ///
  /// Die staart hoort niet bij de identiteit van het bestand en hij verandert. Bewaar je hem mee,
  /// dan is dezelfde foto morgen een andere sleutel, en dan haalt de app hem opnieuw op en zet hij
  /// een tweede kopie op schijf.
  static String? _zonderVolgsleutels(String? url) {
    if (url == null || url.isEmpty) return null;
    final i = url.indexOf('?');
    return i < 0 ? url : url.substring(0, i);
  }
}
