/// Foto's uit het leven van een artiest, per periode, uit de Engelse Wikipedia.
///
/// **Waarom dit bestaat.** Saber op 11-10-2026, op de artiestpagina: *"algemeen is er te weinig en
/// niet relevante foto's erbij, zoals geboren of kindertijd, moet je als dat kan baby en of kinder
/// afbeeldingen tonen van die artist"*. Naast "Geboren" stond bij Lionel Richie de hoes van
/// "Tuskegee" (TheAudioDB's portret van hem is die hoes), en naast elk hoofdstuk om de beurt
/// dezelfde drie volwassen foto's.
///
/// **Gemeten vóór er iets gebouwd werd.** De Engelse Wikipedia zet bij elk hoofdstuk de foto's die
/// erbij horen, met een onderschrift en vaak een jaartal (REST `page/media-list`). Michael Jackson:
/// 27 foto's, waarvan in "Early life and the Jackson 5 (1958–1975)" zijn ouderlijk huis en de Jackson
/// 5 in 1972. Lionel Richie: drie, geen enkele uit zijn jeugd. De Nederlandse artikels hebben er
/// bijna geen. Dus: de Engelse foto's, gekoppeld op jaartal en op "jeugd" — en waar er niets past,
/// liever geen beeld dan een verkeerd.
///
/// **Met naam en licentie.** Wikimedia-foto's zijn vrij onder voorwaarden (meestal CC BY-SA): de
/// maker en de licentie horen erbij te staan. Die komen mee uit `imageinfo` en staan onder de foto.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cachesleutel.dart';
import 'json_body.dart';
import 'musicbrainz.dart';
import 'paths.dart';
import 'wikipedia.dart';

/// Een foto uit een Wikipedia-artikel, met waar hij stond en wat erbij stond.
class WikiFoto {
  const WikiFoto({
    required this.bestand,
    required this.url,
    this.onderschrift = '',
    this.sectie = '',
    this.jaar,
    this.vroeg = false,
    this.maker = '',
    this.licentie = '',
  });

  /// `File:The_Jackson_5_1972.JPG`.
  final String bestand;

  /// Een miniatuur van hoogstens 800 pixels breed, door Wikimedia zelf geschaald.
  final String url;
  final String onderschrift;

  /// De kop van het hoofdstuk waar hij in het Engelse artikel stond.
  final String sectie;

  /// Het jaar van de foto: uit het onderschrift, anders het begin van het hoofdstuk. Null = onbekend.
  final int? jaar;

  /// Uit de jeugd: het hoofdstuk heet "Early life" of het onderschrift zegt "childhood".
  final bool vroeg;

  final String maker, licentie;

  /// Wat er onder de foto hoort te staan.
  String get vermelding {
    final delen = [
      if (maker.isNotEmpty) maker,
      if (licentie.isNotEmpty) licentie,
      'Wikimedia Commons',
    ];
    return 'Foto: ${delen.join(' · ')}';
  }

  Map<String, dynamic> toJson() => {
        'bestand': bestand,
        'url': url,
        if (onderschrift.isNotEmpty) 'onderschrift': onderschrift,
        if (sectie.isNotEmpty) 'sectie': sectie,
        if (jaar != null) 'jaar': jaar,
        if (vroeg) 'vroeg': true,
        if (maker.isNotEmpty) 'maker': maker,
        if (licentie.isNotEmpty) 'licentie': licentie,
      };

  static WikiFoto? fromJson(Object? j) {
    if (j is! Map) return null;
    final bestand = j['bestand'], url = j['url'];
    if (bestand is! String || url is! String || url.isEmpty) return null;
    return WikiFoto(
      bestand: bestand,
      url: url,
      onderschrift: (j['onderschrift'] as String?) ?? '',
      sectie: (j['sectie'] as String?) ?? '',
      jaar: (j['jaar'] as num?)?.toInt(),
      vroeg: j['vroeg'] == true,
      maker: (j['maker'] as String?) ?? '',
      licentie: (j['licentie'] as String?) ?? '',
    );
  }
}

final _jaartal = RegExp(r'\b(1[89]\d\d|20\d\d)\b');
final _vroegWoord = RegExp(r'early life|childhood|as a child|youth|jeugd|kindertijd|vroege jaren|jonge jaren',
    caseSensitive: false);

/// Is dit een foto van een mens of een plek, en geen handtekening, logo of kaart?
bool bruikbareFoto(String bestand) {
  final b = bestand.toLowerCase();
  if (b.endsWith('.svg') || b.endsWith('.ogg') || b.endsWith('.webm') || b.endsWith('.ogv')) {
    return false;
  }
  return !RegExp(r'signature|handtekening|logo|wordmark|map\b|kaart').hasMatch(b);
}

/// Het jaar van een foto: het eerste jaartal in het onderschrift, anders het eerste in de kop van
/// het hoofdstuk ("Early life and the Jackson 5 (1958–1975)" → 1958).
int? jaarVanFoto(String onderschrift, String sectie) {
  final uitOnderschrift = _jaartal.firstMatch(onderschrift);
  if (uitOnderschrift != null) return int.parse(uitOnderschrift.group(1)!);
  final uitSectie = _jaartal.firstMatch(sectie);
  return uitSectie == null ? null : int.parse(uitSectie.group(1)!);
}

/// Komt deze foto uit de jeugd?
bool vroegeFoto(String onderschrift, String sectie) =>
    _vroegWoord.hasMatch(sectie) || _vroegWoord.hasMatch(onderschrift);

/// Over welke jaren een hoofdstuk van de biografie gaat, uit zijn kop.
///
/// "1949–1968: Jeugd" → 1949–1968; "Jaren 90: comeback" → 1990–1999; "Sinds 2000" → 2000 en later;
/// "1982–1987: De eerste drie soloalbums" → 1982–1987. Geen jaartal = null (bijvoorbeeld
/// "Persoonlijk": dat gaat over geen bepaalde periode).
({int van, int tot})? periodeVanKop(String kop) {
  final k = kop.toLowerCase();
  final bereik = RegExp(r'\b(1[89]\d\d|20\d\d)\s*[–—-]\s*(1[89]\d\d|20\d\d)\b').firstMatch(k);
  if (bereik != null) {
    return (van: int.parse(bereik.group(1)!), tot: int.parse(bereik.group(2)!));
  }
  final jaren = RegExp(r"\bjaren\s+'?(\d0)\b|\b(\d0)'?s\b").firstMatch(k);
  if (jaren != null) {
    final tiental = int.parse(jaren.group(1) ?? jaren.group(2)!);
    final eeuw = tiental >= 30 ? 1900 : 2000;
    return (van: eeuw + tiental, tot: eeuw + tiental + 9);
  }
  final sinds = RegExp(r'\b(sinds|since|vanaf)\s+(1[89]\d\d|20\d\d)\b').firstMatch(k);
  if (sinds != null) return (van: int.parse(sinds.group(2)!), tot: 2100);
  final een = _jaartal.firstMatch(k);
  if (een != null) {
    final j = int.parse(een.group(1)!);
    return (van: j, tot: j);
  }
  return null;
}

/// Gaat dit hoofdstuk over de jeugd?
bool kopOverJeugd(String kop) => _vroegWoord.hasMatch(kop);

/// Hoofdstukken zonder jaartal, op hun woord gekoppeld aan het Engelse hoofdstuk waar de foto stond.
/// "Overlijden" bij Michael Jackson heeft geen jaartal in de kop, maar het Engelse "Death" wel foto's.
const _kopNaarSectie = <String, List<String>>{
  'overlijden': ['death', 'memorial'],
  'dood': ['death'],
  'persoonlijk': ['personal life'],
  'privéleven': ['personal life'],
  'prive': ['personal life'],
  'huwelijk': ['personal life', 'marriage'],
  'nalatenschap': ['legacy'],
  'invloed': ['influence', 'legacy'],
  'erfenis': ['legacy'],
};

/// De Engelse woorden waar een hoofdstuk met deze kop op gekoppeld wordt. Leeg = geen.
List<String> sectiewoordenVanKop(String kop) {
  final k = kop.toLowerCase();
  return [
    for (final e in _kopNaarSectie.entries)
      if (k.contains(e.key)) ...e.value,
  ];
}

/// De foto die bij een periode hoort, of null als er geen past.
///
/// Bij [vroeg] eerst een foto uit de jeugd — en daarvan eerst die het dichtst bij [geboren] ligt:
/// de Jackson 5 in 1972 gaat voor zijn geboortehuis gefotografeerd in 2014. Dan een met een jaartal
/// binnen [periode], dan een uit een Engels hoofdstuk met een van [sectiewoorden]. Een foto zonder
/// jaartal en zonder passend hoofdstuk past nergens: een willekeurige foto naast een hoofdstuk is
/// precies wat er gemeld werd. [alGebruikt]: wat een vorig hoofdstuk al kreeg, zodat niet elk
/// hoofdstuk dezelfde foto toont.
WikiFoto? fotoVoorPeriode(
  List<WikiFoto> fotos, {
  ({int van, int tot})? periode,
  bool vroeg = false,
  int? geboren,
  List<String> sectiewoorden = const [],
  Set<String> alGebruikt = const {},
}) {
  final vrij = [for (final f in fotos) if (!alGebruikt.contains(f.bestand)) f];
  if (vroeg) {
    final jeugd = [for (final f in vrij) if (f.vroeg) f];
    if (jeugd.isNotEmpty) {
      if (geboren != null) {
        int afstand(WikiFoto f) => f.jaar == null ? 1000 : (f.jaar! - geboren).abs();
        jeugd.sort((a, b) => afstand(a).compareTo(afstand(b)));
      }
      return jeugd.first;
    }
  }
  if (periode != null) {
    for (final f in vrij) {
      final j = f.jaar;
      if (j != null && j >= periode.van && j <= periode.tot) return f;
    }
  }
  if (sectiewoorden.isNotEmpty) {
    for (final f in vrij) {
      final s = f.sectie.toLowerCase();
      if (sectiewoorden.any(s.contains)) return f;
    }
  }
  return null;
}

/// Een foto per hoofdstuk, op volgorde, zonder dubbelen. Null waar er niets past.
List<WikiFoto?> fotosPerHoofdstuk(List<WikiFoto> fotos, List<String> koppen, {int? geboren}) {
  final gebruikt = <String>{};
  return [
    for (final kop in koppen)
      () {
        final f = fotoVoorPeriode(fotos,
            periode: periodeVanKop(kop),
            vroeg: kopOverJeugd(kop),
            geboren: geboren,
            sectiewoorden: sectiewoordenVanKop(kop),
            alGebruikt: gebruikt);
        if (f != null) gebruikt.add(f.bestand);
        return f;
      }(),
  ];
}

/// De jeugdfoto bij het geboortejaar: een foto uit de jeugd (de dichtstbij de geboorte eerst), of een
/// met een jaartal binnen vijftien jaar na de geboorte. Null als er geen is — dan staat er bij
/// "Geboren" liever niets dan een volwassen foto of een hoes.
WikiFoto? geboortefoto(List<WikiFoto> fotos, {int? geboren}) {
  final vroeg = fotoVoorPeriode(fotos, vroeg: true, geboren: geboren);
  if (vroeg != null) return vroeg;
  if (geboren == null) return null;
  return fotoVoorPeriode(fotos, periode: (van: geboren, tot: geboren + 15));
}

/// Een grote foto van Wikimedia Commons voor "Foto kiezen", met zijn echte maat.
///
/// **Waarom (Saber, 19-10-2026).** De foto's in de kop van een gsm waren vaak niet scherp: van de 29
/// gekozen gsm-foto's werden er 28 meer dan 2,5 keer opgerekt, want Discogs levert 200 tot 600 pixels
/// en TheAudioDB 1280×720. Saber koos er "Wikipedia-foto's bij": Commons heeft vaak 2000 tot 4000
/// pixels. [WikiFoto] vraagt een miniatuur van 800 voor naast een hoofdstuk; deze is zo groot als de
/// kop hem kan gebruiken ([WikiFotoService.kPortretBreedte]).
class WikiPortret {
  const WikiPortret({
    required this.bestand,
    required this.url,
    required this.voorbeeld,
    required this.breedte,
    required this.hoogte,
    this.maker = '',
    this.licentie = '',
  });

  /// `File:Michael Jackson 1983 (3x4 cropped) (contrast).jpg`.
  final String bestand;

  /// Hoogstens [WikiFotoService.kPortretBreedte] breed, door Wikimedia zelf geschaald.
  final String url;

  /// Een kleine versie voor de tegel in de kiezer ([kVoorbeeldBreedte] breed), zodat het venster niet
  /// tientallen megabytes binnenhaalt.
  final String voorbeeld;

  /// De maat van [url] — wat de kop werkelijk krijgt, niet die van het origineel.
  final int breedte, hoogte;
  final String maker, licentie;

  /// Wat er onder de foto hoort te staan (zie [WikiFoto.vermelding]).
  String get vermelding {
    final delen = [
      if (maker.isNotEmpty) maker,
      if (licentie.isNotEmpty) licentie,
      'Wikimedia Commons',
    ];
    return 'Foto: ${delen.join(' · ')}';
  }

  Map<String, dynamic> toJson() => {
        'bestand': bestand,
        'url': url,
        'voorbeeld': voorbeeld,
        'breedte': breedte,
        'hoogte': hoogte,
        if (maker.isNotEmpty) 'maker': maker,
        if (licentie.isNotEmpty) 'licentie': licentie,
      };

  static WikiPortret? fromJson(Object? j) {
    if (j is! Map) return null;
    final bestand = j['bestand'], url = j['url'], b = j['breedte'], h = j['hoogte'];
    if (bestand is! String || url is! String || url.isEmpty || b is! num || h is! num) return null;
    return WikiPortret(
      bestand: bestand,
      url: url,
      voorbeeld: (j['voorbeeld'] as String?) ?? url,
      breedte: b.toInt(),
      hoogte: h.toInt(),
      maker: (j['maker'] as String?) ?? '',
      licentie: (j['licentie'] as String?) ?? '',
    );
  }
}

/// Hoe breed het voorbeeld in een tegel van de kiezer is. Niet zomaar een getal: Wikimedia geeft alleen
/// miniaturen op vaste breedtes (gemeten 19-10-2026: 250, 330, 500, 960, 1280 en 1920 wel, 400 niet —
/// "400 Bad Request", en dan bleef de tegel op de gsm leeg).
const kVoorbeeldBreedte = 500;

/// Geen foto van de artiest zelf: een kaartje, een affiche, een hoes, een ster op de Walk of Fame.
/// Een Commons-categorie verzamelt alles over iemand; bij Michael Jackson stonden een concertkaartje
/// en een collage tussen de eerste vijf.
bool geenPortret(String bestand) => RegExp(
        r'ticket|poster|affiche|cover|album|single|collage|walk of fame|\bstar\b|grave|graf|statue|beeld van|'
        r'mural|wax|museum|stamp|postzegel|autograph|screenshot|flag|vlag|plaque|gedenkplaat|building|house',
        caseSensitive: false)
    .hasMatch(bestand);

/// De grote foto's uit één `imageinfo`-antwoord van Commons, in de volgorde van [volgorde]. Alleen
/// foto's (jpeg, png, webp) waarvan de korte kant minstens [kleinsteKant] pixels is: kleiner levert
/// in de kop niets op dat Discogs niet al heeft.
List<WikiPortret> portrettenUitInfo(Map<String, dynamic>? info, List<String> volgorde, {int kleinsteKant = 500}) {
  final perBestand = <String, Map>{};
  for (final p in (((info?['query'] as Map?)?['pages'] as List?) ?? const [])) {
    if (p is! Map) continue;
    final ii = (p['imageinfo'] as List?)?.firstOrNull;
    if (ii is Map) perBestand['${p['title']}'.replaceAll('_', ' ')] = ii;
  }
  String tekst(Object? v) => '${(v is Map ? v['value'] : null) ?? ''}'.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  final uit = <WikiPortret>[];
  for (final bestand in volgorde) {
    final ii = perBestand[bestand.replaceAll('_', ' ')];
    if (ii == null) continue;
    final mime = '${ii['mime'] ?? ''}';
    if (!(mime == 'image/jpeg' || mime == 'image/png' || mime == 'image/webp')) continue;
    final url = (ii['thumburl'] ?? ii['url']) as String?;
    final b = ((ii['thumbwidth'] ?? ii['width']) as num?)?.toInt() ?? 0;
    final h = ((ii['thumbheight'] ?? ii['height']) as num?)?.toInt() ?? 0;
    if (url == null || url.isEmpty || b <= 0 || h <= 0) continue;
    if ((b < h ? b : h) < kleinsteKant) continue;
    // De miniatuur van Wikimedia heeft de breedte in het pad ("…/1920px-Naam.jpg"); voor de tegel
    // dezelfde op [kVoorbeeldBreedte]. Een origineel dat smaller is dan 1920 heeft geen miniatuur: dan dat.
    final voorbeeld = url.replaceFirst(RegExp(r'/\d+px-'), '/${kVoorbeeldBreedte}px-');
    uit.add(WikiPortret(
      bestand: bestand,
      url: url,
      voorbeeld: voorbeeld,
      breedte: b,
      hoogte: h,
      maker: tekst((ii['extmetadata'] as Map?)?['Artist']),
      licentie: tekst((ii['extmetadata'] as Map?)?['LicenseShortName']),
    ));
  }
  return uit;
}

/// Haalt en bewaart de foto's van een artiest.
class WikiFotoService {
  WikiFotoService({WikipediaService? wikipedia}) : _wikipedia = wikipedia ?? WikipediaService();
  final WikipediaService _wikipedia;

  static const _ua = 'DebridMusic/1.0 ( https://github.com/sabair24/Debrid-music-app )';
  static const _lane = 'wikimedia';
  static const _gap = Duration(seconds: 1);
  static const _versGenoeg = Duration(days: 30);

  Directory get _dir => Directory('$appDir${Platform.pathSeparator}wikifotos');
  File _lijstFile(String q) => File('${_dir.path}${Platform.pathSeparator}${fnv1a('f1|$q')}.json');
  File _beeldFile(String url) => File('${_dir.path}${Platform.pathSeparator}${fnv1a('b1|$url')}.img');

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

  /// De foto's van deze artiest, oudste eerst zoals ze in het artikel staan. Leeg als er geen zijn of
  /// als de biografie nog nooit opgehaald is (dan is er geen Wikidata-nummer).
  Future<List<WikiFoto>> fotos(String naam) async {
    final q = await _wikipedia.wikidataVoor(naam);
    if (q == null) return const [];
    return fotosVoor(q);
  }

  /// [fotos] voor een Wikidata-nummer (`Q2831`). Bewaard voor dertig dagen.
  Future<List<WikiFoto>> fotosVoor(String q) async {
    final f = _lijstFile(q);
    try {
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map && j['haaldMs'] is num) {
          final oud = [
            for (final x in (j['fotos'] as List? ?? const [])) ?WikiFoto.fromJson(x),
          ];
          final leeftijd = DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch((j['haaldMs'] as num).toInt()));
          if (leeftijd < _versGenoeg) return oud;
        }
      }
    } catch (_) {/* een kapotte lijst wordt opnieuw opgehaald */}

    final vers = await _haalFotos(q);
    if (vers == null) return const [];
    try {
      await _dir.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'haaldMs': DateTime.now().millisecondsSinceEpoch,
        'fotos': [for (final x in vers) x.toJson()],
      }));
    } catch (_) {/* een cache die niet geschreven kan worden kost één herhaald verzoek */}
    return vers;
  }

  Future<List<WikiFoto>?> _haalFotos(String q) async {
    final ent = await _haal(Uri.parse('https://www.wikidata.org/w/api.php'
        '?action=wbgetentities&ids=$q&props=sitelinks&sitefilter=enwiki&format=json'));
    final titel = ((((ent?['entities'] as Map?)?[q] as Map?)?['sitelinks'] as Map?)?['enwiki']
            as Map?)?['title'] as String?;
    if (titel == null || titel.trim().isEmpty) return const [];
    final pad = Uri.encodeComponent(titel.replaceAll(' ', '_'));
    final media = await _haal(Uri.parse('https://en.wikipedia.org/api/rest_v1/page/media-list/$pad'));
    if (media == null) return null;
    final secties = await _haal(Uri.parse('https://en.wikipedia.org/w/api.php'
        '?action=parse&page=$pad&prop=sections&format=json&redirects=1'));
    final kopVan = <int, String>{};
    for (final s in (((secties?['parse'] as Map?)?['sections'] as List?) ?? const [])) {
      if (s is! Map) continue;
      final i = int.tryParse('${s['index']}');
      if (i != null) kopVan[i] = '${s['line'] ?? ''}'.replaceAll(RegExp(r'<[^>]+>'), '');
    }
    final kandidaten = <({String bestand, String onderschrift, String sectie})>[
      for (final i in ((media['items'] as List?) ?? const []))
        if (i is Map && i['type'] == 'image' && i['title'] is String && bruikbareFoto(i['title'] as String))
          (
            bestand: i['title'] as String,
            onderschrift: (((i['caption'] as Map?)?['text'] as String?) ?? '').trim(),
            sectie: kopVan[(i['section_id'] as num?)?.toInt() ?? 0] ?? '',
          ),
    ];
    if (kandidaten.isEmpty) return const [];
    // De miniatuur, de maker en de licentie, voor hoogstens vijftig bestanden in één verzoek.
    final info = await _haal(Uri.parse('https://en.wikipedia.org/w/api.php'
        '?action=query&prop=imageinfo&iiprop=url%7Cextmetadata&iiurlwidth=800'
        '&iiextmetadatafilter=Artist%7CLicenseShortName&format=json&formatversion=2'
        '&titles=${Uri.encodeQueryComponent(kandidaten.take(50).map((k) => k.bestand).join('|'))}'));
    final perBestand = <String, Map>{};
    for (final p in (((info?['query'] as Map?)?['pages'] as List?) ?? const [])) {
      if (p is! Map) continue;
      final ii = (p['imageinfo'] as List?)?.firstOrNull;
      if (ii is Map) perBestand['${p['title']}'] = ii;
    }
    String tekst(Object? v) =>
        '${(v is Map ? v['value'] : null) ?? ''}'.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return [
      for (final k in kandidaten.take(50))
        if (perBestand[k.bestand.replaceAll('_', ' ')] ?? perBestand[k.bestand] case final ii?)
          if ((ii['thumburl'] ?? ii['url']) is String)
            WikiFoto(
              bestand: k.bestand,
              url: (ii['thumburl'] ?? ii['url']) as String,
              onderschrift: k.onderschrift,
              sectie: k.sectie,
              jaar: jaarVanFoto(k.onderschrift, k.sectie),
              vroeg: vroegeFoto(k.onderschrift, k.sectie),
              maker: tekst((ii['extmetadata'] as Map?)?['Artist']),
              licentie: tekst((ii['extmetadata'] as Map?)?['LicenseShortName']),
            ),
    ];
  }

/// Hoe breed een foto voor de kop gevraagd wordt: zo breed decodeert de kop hem hoogstens
  /// (`decodeerBreedte` in ui/kopfoto.dart). Groter kost alleen geheugen.
  static const kPortretBreedte = 1920;

  /// `p2` sinds de voorbeelden op 500 staan: een lijst van `p1` draagt nog adressen van 400 die Wikimedia
  /// weigert ([kVoorbeeldBreedte]).
  File _portretFile(String q) => File('${_dir.path}${Platform.pathSeparator}${fnv1a('p2|$q')}.json');

  /// Grote foto's van deze artiest voor "Foto kiezen": de hoofdfoto van Wikidata, de foto's uit het
  /// Engelse artikel en die uit zijn Commons-categorie, met hun echte maat. Leeg als Wikipedia hem
  /// niet kent. Zoekt het Wikidata-nummer zelf als de biografie nog nooit opgehaald is.
  Future<List<WikiPortret>> portretten(String naam) async {
    var q = await _wikipedia.wikidataVoor(naam);
    if (q == null) {
      await _wikipedia.titelVoor(naam);
      q = await _wikipedia.wikidataVoor(naam);
    }
    if (q == null) return const [];
    return portrettenVoor(q);
  }

  /// [portretten] voor een Wikidata-nummer. Bewaard voor dertig dagen.
  Future<List<WikiPortret>> portrettenVoor(String q) async {
    final f = _portretFile(q);
    try {
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map && j['haaldMs'] is num) {
          final leeftijd = DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch((j['haaldMs'] as num).toInt()));
          if (leeftijd < _versGenoeg) {
            return [for (final x in (j['portretten'] as List? ?? const [])) ?WikiPortret.fromJson(x)];
          }
        }
      }
    } catch (_) {/* een kapotte lijst wordt opnieuw opgehaald */}

    final ent = await _haal(Uri.parse('https://www.wikidata.org/w/api.php'
        '?action=wbgetentities&ids=$q&props=claims&format=json'));
    if (ent == null) return const [];
    final claims = ((((ent['entities'] as Map?)?[q] as Map?)?['claims']) as Map?) ?? const {};
    List<String> waarden(String p) => [
          for (final c in (claims[p] as List?) ?? const [])
            if (((c as Map?)?['mainsnak'] as Map?)?['datavalue']?['value'] case final String v) v,
        ];
    final namen = <String>[
      for (final v in waarden('P18')) 'File:$v',
      // De foto's die Wikipedia zelf bij de artiest zette (al bewaard door [fotosVoor]).
      for (final w in await fotosVoor(q)) w.bestand,
    ];
    final categorie = waarden('P373').firstOrNull;
    if (categorie != null) {
      final leden = await _haal(Uri.parse('https://commons.wikimedia.org/w/api.php'
          '?action=query&list=categorymembers&cmtype=file&cmlimit=30&format=json'
          '&cmtitle=${Uri.encodeQueryComponent('Category:$categorie')}'));
      for (final m in (((leden?['query'] as Map?)?['categorymembers'] as List?) ?? const [])) {
        final t = (m as Map?)?['title'];
        if (t is String) namen.add(t);
      }
    }
    final gezien = <String>{};
    final volgorde = [
      for (final n in namen)
        if (bruikbareFoto(n) && !geenPortret(n) && gezien.add(n.replaceAll('_', ' '))) n,
    ].take(40).toList();
    if (volgorde.isEmpty) return const [];
    final info = await _haal(Uri.parse('https://commons.wikimedia.org/w/api.php'
        '?action=query&prop=imageinfo&iiprop=url%7Csize%7Cmime%7Cextmetadata&iiurlwidth=$kPortretBreedte'
        '&iiextmetadatafilter=Artist%7CLicenseShortName&format=json&formatversion=2'
        '&titles=${Uri.encodeQueryComponent(volgorde.join('|'))}'));
    if (info == null) return const [];
    final uit = portrettenUitInfo(info, volgorde);
    try {
      await _dir.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'haaldMs': DateTime.now().millisecondsSinceEpoch,
        'portretten': [for (final x in uit) x.toJson()],
      }));
    } catch (_) {/* een cache die niet geschreven kan worden kost één herhaald verzoek */}
    return uit;
  }

  /// De bytes van een foto, van schijf of van Wikimedia. Null als het niet lukt.
  Future<Uint8List?> bytes(WikiFoto foto) async {
    final f = _beeldFile(foto.url);
    try {
      if (await f.exists()) return await f.readAsBytes();
      final r = await http
          .get(Uri.parse(foto.url), headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200 || r.bodyBytes.length < 200) return null;
      await _dir.create(recursive: true);
      await f.writeAsBytes(r.bodyBytes);
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
