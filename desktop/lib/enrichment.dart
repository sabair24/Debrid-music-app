import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'cachesleutel.dart';
import 'json_body.dart';
import 'deezerbaan.dart';
import 'isrc.dart' show isrcJaar;
import 'discogs.dart';
import 'models.dart';
import 'musicbrainz.dart';
import 'organize.dart' show normKey, artistKey;
import 'settings.dart';
import 'paths.dart';

/// A wide backdrop and the act's official wordmark — what turns an artist page into a banner.
class ArtistArt {
  final String? logo, backdrop, thumb, cutout, clearart;
  final Uint8List? logoBytes, backdropBytes, thumbBytes, cutoutBytes, clearartBytes;
  const ArtistArt({
    this.logo,
    this.backdrop,
    this.thumb,
    this.cutout,
    this.clearart,
    this.logoBytes,
    this.backdropBytes,
    this.thumbBytes,
    this.cutoutBytes,
    this.clearartBytes,
  });

  bool get isEmpty => logo == null && backdrop == null && thumb == null;

  /// De artiest, vrijstaand uitgeknipt op een doorzichtige achtergrond — als die er is.
  ///
  /// **Waarom dit een eigen veld is en geen terugval meer.** `strArtistCutout` stond hier alleen
  /// achteraan bij [thumb], als noodgreep wanneer er geen portret was. Daarmee is hij vrijwel
  /// onbereikbaar: bijna elke artiest hééft een portret, dus de cutout werd nooit gekozen. En juist
  /// hij is het interessante beeld — een figuur zónder kader kun je over een titel heen zetten, en
  /// dat kan een rechthoekige foto niet.
  ///
  /// Gemeten op 06-09-2026 over dertien artiesten uit deze bibliotheek: **tien hebben een cutout**
  /// en elf een clearart. Het is dus geen zeldzaamheid maar de regel — met een terugval voor de
  /// rest. Zie `ArtistHero` voor de ladder cutout → clearart → portret → alleen letters.
  ///
  /// [clearart] is dezelfde gedachte in liggend formaat (1000×562, doorzichtig).
  bool get heeftVrijstaand => cutout != null || clearart != null;

  /// Bumped whenever a new field is added, so entries cached by an older build are refetched
  /// instead of answering forever with a null they never had a chance to fill. Adding `thumb`
  /// without this meant every artist you'd already opened kept showing the old fallback.
  static const schema = 3;

  Map<String, dynamic> toJson() => {
        'v': schema,
        'logo': logo,
        'backdrop': backdrop,
        'thumb': thumb,
        'cutout': cutout,
        'clearart': clearart,
      };

  /// Null for an entry written by an older build — the caller refetches.
  static ArtistArt? fromJson(Map<String, dynamic> j) {
    if ((j['v'] as int?) != schema) return null;
    return ArtistArt(
      logo: j['logo'] as String?,
      backdrop: j['backdrop'] as String?,
      thumb: j['thumb'] as String?,
      cutout: j['cutout'] as String?,
      clearart: j['clearart'] as String?,
    );
  }
}

/// Wie een artiest IS in feiten: geboren, opgericht, land, label.
///
/// **Dit stond al in de respons en werd weggegooid.** [CoverEnricher.fetchArtistBio] en
/// [CoverEnricher._zoekArtiestBeeld] halen allebei dezelfde URL op — `search.php?s=<naam>` — en
/// nemen er elk één ding uit: de eerste de biografie, de tweede de beelden. Alles daarnaast viel
/// op de grond: `strBorn`, `intBornYear`, `intDiedYear`, `intFormedYear`, `strDisbanded`,
/// `strCountry`, `strLabel`, `intMembers`. Dat zijn precies de feiten die boven een biografie
/// horen te staan, en ze kosten nul extra verzoeken.
///
/// Een eigen buurcache en NIET een veld erbij op [ArtistArt]: dat is een beeldrecord, en een veld
/// toevoegen dwingt daar de keuze af tussen een schemabump (herophalen voor 268 artiesten) en
/// voor altijd `null` antwoorden op elke regel die een oudere bouw schreef. Ook niet bij de
/// biografie: `bios/<fnv>.txt` is platte tekst, en daar JSON van maken breekt elk bestaand bestand
/// en [CoverEnricher.cachedBio].
class ArtiestFeiten {
  /// `strBorn` zoals hij binnenkomt — vaak "29 August 1958, Gary, Indiana". Ruw bewaard: het is
  /// vrije tekst in wisselende vorm, en er zelf een datum uit peuteren is raden.
  final String? geboren;
  final int? geborenJaar, gestorvenJaar, opgerichtJaar;
  final String? ontbonden, land, label;
  final int? aantalLeden;

  const ArtiestFeiten({
    this.geboren,
    this.geborenJaar,
    this.gestorvenJaar,
    this.opgerichtJaar,
    this.ontbonden,
    this.land,
    this.label,
    this.aantalLeden,
  });

  static const schema = 1;

  bool get isEmpty =>
      geboren == null &&
      geborenJaar == null &&
      gestorvenJaar == null &&
      opgerichtJaar == null &&
      (ontbonden == null || ontbonden!.isEmpty) &&
      (land == null || land!.isEmpty) &&
      (label == null || label!.isEmpty);

  /// Of dit één iemand is in plaats van een groep.
  ///
  /// TheAudioDB vult `intMembers` met 1 voor een solo-artiest. Dat is precies genoeg om te weten
  /// welk jaartal het BEGIN van een loopbaan is: bij een groep de oprichting, bij een persoon de
  /// geboorte. Weet de bron het niet, dan is een geboortejaar het veiligste antwoord — dat klopt
  /// voor een persoon en is voor een groep meestal simpelweg afwezig.
  bool get isPersoon => (aantalLeden ?? 1) <= 1;

  /// "1958 – 2009", "sinds 1993", "1993 – 2011" — of null als er niets te zeggen valt.
  ///
  /// Bij een GROEP telt het jaar van oprichting; bij een PERSOON het geboortejaar. Andersom stond
  /// er bij Michael Jackson "1964 – 2009" — het jaar dat The Jackson 5 begon, onder een label dat
  /// over hem gaat.
  String? get actief {
    final van = isPersoon ? (geborenJaar ?? opgerichtJaar) : (opgerichtJaar ?? geborenJaar);
    if (van == null) return null;
    final tot = gestorvenJaar ?? _jaarUit(ontbonden);
    return tot == null ? 'sinds $van' : '$van – $tot';
  }

  /// Alleen een schoon viertal telt. `strDisbanded` is vrije tekst en staat regelmatig vol met
  /// "still active" of een hele zin; daar een jaartal uit vissen zou een gok zijn die er als een
  /// feit uitziet.
  ///
  /// Openbaar omdat `jaarlint.dart` hem ook nodig heeft. Eén idee over wanneer "ontbonden" een
  /// jaartal is — anders kan het lint een streepje zetten waar de feitenstrook er geen ziet.
  static int? jaarUit(String? tekst) => _jaarUit(tekst);

  /// Een jaartal, of null. TheAudioDB stuurt "0" als het jaar niet bekend is, en dat stond er dan
  /// letterlijk: "OPGERICHT 0" en "ACTIEF sinds 0" bij 2 Fabiola (gsm, 18-10-2026). Ook uit een
  /// bewaard bestand van vóór deze regel.
  static int? _echtJaar(int? j) => j == null || j < 1000 ? null : j;

  static int? _jaarUit(String? tekst) {
    if (tekst == null) return null;
    final m = RegExp(r'^\s*(\d{4})\s*$').firstMatch(tekst);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Map<String, dynamic> toJson() => {
        'v': schema,
        if (geboren != null) 'geboren': geboren,
        if (geborenJaar != null) 'gj': geborenJaar,
        if (gestorvenJaar != null) 'sj': gestorvenJaar,
        if (opgerichtJaar != null) 'oj': opgerichtJaar,
        if (ontbonden != null) 'ontbonden': ontbonden,
        if (land != null) 'land': land,
        if (label != null) 'label': label,
        if (aantalLeden != null) 'leden': aantalLeden,
      };

  /// Null bij een ander schema — dan haalt de aanroeper hem opnieuw op.
  static ArtiestFeiten? fromJson(Map<String, dynamic> j) {
    if ((j['v'] as num?)?.toInt() != schema) return null;
    return ArtiestFeiten(
      geboren: j['geboren'] as String?,
      geborenJaar: _echtJaar((j['gj'] as num?)?.toInt()),
      gestorvenJaar: _echtJaar((j['sj'] as num?)?.toInt()),
      opgerichtJaar: _echtJaar((j['oj'] as num?)?.toInt()),
      ontbonden: j['ontbonden'] as String?,
      land: j['land'] as String?,
      label: j['label'] as String?,
      aantalLeden: (j['leden'] as num?)?.toInt(),
    );
  }

  /// Uit één rij van TheAudioDB's `search.php`.
  ///
  /// De jaartallen komen als TEKST binnen ("1958"), niet als getal — vandaar `int.tryParse` en
  /// niet een cast. En de `'null'`-wacht, want deze bron stuurt die vier letters echt.
  static ArtiestFeiten uitAudioDb(Map<String, dynamic> a) {
    String? s(String k) {
      final v = (a[k] as String?)?.trim();
      return (v == null || v.isEmpty || v.toLowerCase() == 'null') ? null : v;
    }

    int? n(String k) => int.tryParse(s(k) ?? '');

    return ArtiestFeiten(
      geboren: s('strBornLocation') == null
          ? s('strBorn')
          : [s('strBorn'), s('strBornLocation')].whereType<String>().join(' · '),
      geborenJaar: _echtJaar(n('intBornYear')),
      gestorvenJaar: _echtJaar(n('intDiedYear')),
      opgerichtJaar: _echtJaar(n('intFormedYear')),
      ontbonden: s('strDisbanded'),
      land: s('strCountry'),
      label: s('strLabel'),
      aantalLeden: n('intMembers'),
    );
  }
}

/// What a release IS — the text and facts that make an album page read like a film page
/// instead of a bare track list.
class AlbumInfo {
  final String? description, review, genre, style, label;
  final int? year;
  final double? score;

  /// Where TheAudioDB keeps this record's back cover and its disc, if it has them.
  ///
  /// Read from the same response the description comes out of — which this app has been fetching on
  /// every album page open and throwing these two fields away. Worth having for one reason above all:
  /// they cost nothing. The Cover Art Archive has no scans for most pressings, and the fallback after
  /// it is Discogs, whose sixty requests a minute are the scarcest thing in the app; measured on the
  /// real library, one album's artwork could sit there for over two minutes waiting for its turn.
  /// TheAudioDB is keyless and unmetered, and for ANTI it has both.
  final String? backUrl, discUrl;

  /// De voorkant bij TheAudioDB (`strAlbumThumb`, 700×700): de tweede keus na Deezer's 1200 — Saber,
  /// 20-10-2026: "front is meestal de digitale versie het beste 1200x1200 of bij the audiodb 700x700".
  final String? frontUrl;

  const AlbumInfo({
    this.description,
    this.review,
    this.year,
    this.genre,
    this.style,
    this.label,
    this.score,
    this.backUrl,
    this.discUrl,
    this.frontUrl,
  });

  bool get isEmpty =>
      (description == null || description!.isEmpty) &&
      (review == null || review!.isEmpty) &&
      year == null &&
      genre == null &&
      label == null &&
      backUrl == null &&
      discUrl == null &&
      frontUrl == null;

  /// The blurb to show: the encyclopedic description first, a review only if that's all there is.
  String? get text => (description != null && description!.isNotEmpty) ? description : review;

  Map<String, dynamic> toJson() => {
        'description': description,
        'review': review,
        'year': year,
        'genre': genre,
        'style': style,
        'label': label,
        'score': score,
        if (backUrl != null) 'backUrl': backUrl,
        if (discUrl != null) 'discUrl': discUrl,
        if (frontUrl != null) 'frontUrl': frontUrl,
      };

  factory AlbumInfo.fromJson(Map<String, dynamic> j) => AlbumInfo(
        description: j['description'] as String?,
        review: j['review'] as String?,
        year: j['year'] as int?,
        genre: j['genre'] as String?,
        style: j['style'] as String?,
        label: j['label'] as String?,
        score: (j['score'] as num?)?.toDouble(),
        backUrl: j['backUrl'] as String?,
        discUrl: j['discUrl'] as String?,
        frontUrl: j['frontUrl'] as String?,
      );
}

/// Waar TheAudioDB antwoordt.
///
/// **De sleutel "2" is dood.** Gemeten op 26-09-2026: `/json/2/search.php?s=coldplay` gaf
/// `{"Message":"Not found"}`, voor élke artiest, en `theaudiodb.com` zonder www stuurde eerst een 301.
/// Met de huidige gratis sleutel "123" op www kwam Coldplay gewoon terug, en 2 Fabiola als "Euro
/// Dance". Alles wat de app hier ophaalde — artiestbeelden, biografieën, albumhoezen achterop — deed
/// het dus stil niet meer: een lege lijst en een "Not found" zien er in de code hetzelfde uit.
const kAudioDbBasis = 'https://www.theaudiodb.com/api/v1/json/123';

/// Het Deezer-album dat werkelijk [album] van [artiest] is, uit een zoekuitslag — of null.
///
/// **Nooit blind het eerste resultaat.** Gemeten op 21-10-2026: "Roya Turn Me On" geeft bij Deezer als
/// eerste "Rojas On The Beat — On Me", en de oude zoektocht nam dat als hoes. Sinds de digitale voorkant
/// boven de hoes in de bestanden gaat (Saber, 21-10-2026: "digitaal wint altijd") mag een gok op naam er
/// niet meer tussen komen.
///
/// De artiest moet kloppen — of de artiest in het bestand begint met die van Deezer ("Lady Gaga & Bruno
/// Mars" bij Deezers "Lady Gaga"). De titel eerst precies, dan zonder de editie-aanduiding
/// ([DiscogsService.plainTitle]: "(Deluxe)", "Remastered"). Bij een verzamelaar ("Various Artists")
/// telt alleen de precieze titel.
Map<String, dynamic>? kiesDigitaalAlbum(List<dynamic> data, String artiest, String album, {bool generiek = false}) {
  final wilTitel = normKey(album);
  if (wilTitel.isEmpty) return null;
  final wilKaal = normKey(DiscogsService.plainTitle(album));
  final wilArtiest = artistKey(artiest);
  bool zelfdeArtiest(String naam) {
    final k = artistKey(naam);
    return k.isNotEmpty && (k == wilArtiest || wilArtiest.startsWith('$k '));
  }

  Map<String, dynamic>? kaal;
  for (final d in data) {
    if (d is! Map<String, dynamic>) continue;
    final titel = '${d['title'] ?? ''}';
    final art = d['artist'];
    final naam = '${art is Map ? art['name'] ?? '' : ''}';
    if (!generiek && !zelfdeArtiest(naam)) continue;
    if (normKey(titel) == wilTitel) return d;
    if (!generiek && kaal == null && wilKaal.isNotEmpty && normKey(DiscogsService.plainTitle(titel)) == wilKaal) {
      kaal = d;
    }
  }
  return kaal;
}

/// Ziet deze albumtitel eruit als een verzamelaar — "Foute Cd 11 Cd2", "NOW 121", "Bravo Hits 00's",
/// "Sublime Top 1000"? Alleen gevraagd nadat het album zelf nergens te vinden was.
bool lijktVerzamelaar(String album) => RegExp(
        r'\b(cd ?\d+|vol(ume)?\.? ?\d+|hits|top ?\d+|now|foute|compilation|collection|verzamel\w*|best of|the best)\b',
        caseSensitive: false)
    .hasMatch(album);

/// Zonder gastrol: "(feat. …)", "[with …]".
String zonderGastTitel(String t) => t
    .replaceAll(RegExp(r'\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s[^\)\]]*[\)\]]', caseSensitive: false), '')
    .trim();

bool _zelfdeArtiestAls(String naam, String artiest) {
  final k = artistKey(naam), wil = artistKey(artiest);
  return k.isNotEmpty && (k == wil || wil.startsWith('$k '));
}

/// De Deezer-albums waarop [titel] van [artiest] staat, uit een zoekuitslag op nummers — hoogstens [max],
/// in de volgorde van Deezer. Geen remix of karaokeversie: de titel moet precies kloppen (of zonder gastrol),
/// en de artiest ook ("The Karaoke Channel — Dur Dur D'être Bébé (Originally Performed by Jordy)" niet).
List<int> albumsVanNummer(List<dynamic> data, String artiest, String titel, {int max = 5}) {
  final wil = normKey(titel), wilKaal = normKey(zonderGastTitel(titel));
  final uit = <int>[];
  for (final d in data) {
    if (d is! Map) continue;
    final art = d['artist'];
    if (!_zelfdeArtiestAls('${art is Map ? art['name'] ?? '' : ''}', artiest)) continue;
    final t = '${d['title'] ?? ''}';
    if (normKey(t) != wil && normKey(zonderGastTitel(t)) != wilKaal) continue;
    final alb = d['album'];
    final id = alb is Map ? (alb['id'] as num?)?.toInt() : null;
    if (id != null && !uit.contains(id)) uit.add(id);
    if (uit.length >= max) break;
  }
  return uit;
}

/// De ORIGINELE uitgave uit Deezer-albums ([albums], zoals `/album/{id}` ze geeft): geen verzamelaar
/// (`record_type` "compile"), van de artiest zelf, en de vroegste. Of null.
Map<String, dynamic>? kiesOrigineleUitgave(List<Map<String, dynamic>> albums, String artiest) {
  Map<String, dynamic>? beste;
  var besteDatum = '';
  for (final a in albums) {
    if ('${a['record_type'] ?? ''}' == 'compile') continue;
    final art = a['artist'];
    if (!_zelfdeArtiestAls('${art is Map ? art['name'] ?? '' : ''}', artiest)) continue;
    final datum = '${a['release_date'] ?? '9999'}';
    if (beste == null || datum.compareTo(besteDatum) < 0) {
      beste = a;
      besteDatum = datum;
    }
  }
  return beste;
}

/// Het Deezer-nummer van [titel] van [artiest] op het album [album], uit een zoekuitslag op nummers — of
/// null. Dezelfde zeef als [albumsVanNummer], plus de albumtitel.
int? nummerOpAlbum(List<dynamic> data, String artiest, String titel, String album) {
  final wil = normKey(titel), wilKaal = normKey(zonderGastTitel(titel)), wilAlbum = normKey(album);
  for (final d in data) {
    if (d is! Map) continue;
    final art = d['artist'];
    if (!_zelfdeArtiestAls('${art is Map ? art['name'] ?? '' : ''}', artiest)) continue;
    final t = '${d['title'] ?? ''}';
    if (normKey(t) != wil && normKey(zonderGastTitel(t)) != wilKaal) continue;
    final alb = d['album'];
    if (alb is! Map || normKey('${alb['title'] ?? ''}') != wilAlbum) continue;
    final id = (d['id'] as num?)?.toInt();
    if (id != null) return id;
  }
  return null;
}

/// De plek van een nummer op een uitgave, zoals Deezer het van `/track/{id}` geeft: het jaar van het
/// album, het nummer en de schijf (0: onbekend). Zie [deezerPlekOpAlbum].
({int? jaar, int nummer, int schijf}) plekUitDeezerNummer(Map<String, dynamic> t) {
  final alb = t['album'];
  final datum = '${(alb is Map ? alb['release_date'] : null) ?? t['release_date'] ?? ''}';
  final jaar = datum.length >= 4 ? int.tryParse(datum.substring(0, 4)) : null;
  return (
    jaar: jaar == null || jaar < 1900 ? null : jaar,
    nummer: (t['track_position'] as num?)?.toInt() ?? 0,
    schijf: (t['disk_number'] as num?)?.toInt() ?? 0,
  );
}

/// Waar [titel] van [artiest] op de uitgave [album] staat, volgens Deezer — of null.
///
/// Voor ▶, dat het bestand met het album tagt waarop je het nummer zag (`DownloadManager.gezagVoorHaal`):
/// de nummering en het jaar in een verzamelrip horen bij een ándere uitgave. Gemeten op 21-10-2026: Jordy —
/// Dur Dur D'être Bébé uit de Foute CD van Q-music stond na ▶ als nummer 11 van 2012 op Pochette Surprise;
/// Deezer zegt nummer 1, schijf 1, 1992.
Future<({int? jaar, int nummer, int schijf})?> deezerPlekOpAlbum(String artiest, String titel, String album) async {
  final j = await DeezerBaan.haal(
      'https://api.deezer.com/search?q=${Uri.encodeComponent('$artiest $titel')}&limit=15');
  final id = nummerOpAlbum((j?['data'] as List?) ?? const [], artiest, titel, album);
  if (id == null) return null;
  final t = await DeezerBaan.haal('https://api.deezer.com/track/$id');
  return t == null ? null : plekUitDeezerNummer(t);
}

/// De oorspronkelijke uitgave van [titel] door [artiest] in wat MusicBrainz' opnamezoeker gaf: het studioalbum, en
/// pas als dat er niet is de single of ep — nooit een verzamelaar, een live-plaat, een dj-mix of een promo. Null als
/// geen enkele opname dit nummer is.
///
/// **Waarom (Saber, 23-10-2026).** Wat de radio en ▶ binnenhalen, landde in `Singles/` zonder albumtag, want Deezer
/// noemt bij een radionummer vaak een verzamelaar. Gevraagd of de app het album dan zelf mag invullen: *"Ja"*. Gemeten
/// op 23-10-2026: "Hate Me" van Ellie Goulding & Juice WRLD staat in MusicBrainz op de single (2019), op Brightest
/// Blue (2020) en op vier verzamelaars, waaronder EG.0 — het antwoord is Brightest Blue.
///
/// Een opname telt als hetzelfde nummer bij dezelfde artiest (de eerste genoemde), dezelfde titel (ook zonder gast),
/// en — als beide het weten — hoogstens 8 s verschil in lengte: een albumversie van 5:36 is niet de single van 4:17.
({String album, int? jaar})? origineleUitgaveUit(List<MbRecording> opnames,
    {required String artiest, required String titel, int? seconden}) {
  final wil = normKey(titel), wilKaal = normKey(zonderGastTitel(titel));
  final remix = RegExp(r'\b(re)?mix\b', caseSensitive: false).hasMatch(titel);
  ({MbRecordingRelease rel, String datum})? beste;
  // Een album van de artiest zelf (ook een eigen soundtrack, zoals Purple Rain), dan een album van iemand anders, dan
  // pas een single of ep. Gemeten op 23-10-2026: Live And Let Die kwam zonder deze volgorde op de soundtrack van een
  // film uit 2003, terwijl Red Rose Speedway en Band on the Run erbij stonden.
  int rang(MbRecordingRelease r) {
    if (r.primaryType != 'Album') return 2;
    return r.artiest.isEmpty || _zelfdeArtiestLos(r.artiest, artiest) ? 0 : 1;
  }

  for (final o in opnames) {
    if (!_zelfdeArtiestAls(o.artist, artiest)) continue;
    if (normKey(o.title) != wil && normKey(zonderGastTitel(o.title)) != wilKaal) continue;
    if (seconden != null && seconden > 0 && o.seconds > 0 && (o.seconds - seconden).abs() > 8) continue;
    for (final r in o.releases) {
      if (r.status.isNotEmpty && r.status != 'Official') continue;
      if (!const {'Album', 'Single', 'EP'}.contains(r.primaryType)) continue;
      // Een verzamelaar die MusicBrainz niet zo noemt ("SWF 3 Club Collection Oldies", 23-10-2026).
      if (r.artiest.toLowerCase().contains('various artists')) continue;
      // Een soundtrack mag (daar staat een nummer soms eerst op), een remixplaat alleen voor een remix.
      if (r.secondaryTypes.any((s) => s != 'Soundtrack' && !(s == 'Remix' && remix))) continue;
      final datum = r.date.isNotEmpty ? r.date : o.firstReleaseDate;
      final b = beste;
      // Bij gelijke rang het origineel vóór een deluxe of remaster ([isEditie]), dan de vroegste.
      int ed(MbRecordingRelease x) => isEditie(x.title) ? 1 : 0;
      final beter = b == null ||
          rang(r) < rang(b.rel) ||
          (rang(r) == rang(b.rel) && ed(r) < ed(b.rel)) ||
          (rang(r) == rang(b.rel) &&
              ed(r) == ed(b.rel) &&
              datum.isNotEmpty &&
              (b.datum.isEmpty || datum.compareTo(b.datum) < 0));
      if (beter) beste = (rel: r, datum: datum);
    }
  }
  final b = beste;
  if (b == null) return null;
  // Het jaar van de plaat zelf: de vroegste persing met die naam en soort die een datum draagt. Pas zonder zo'n persing
  // de eerste datum van de opname — die van Hate Me is de single (2019), niet Brightest Blue (2020).
  var datum = '';
  for (final o in opnames) {
    for (final r in o.releases) {
      if (r.date.isEmpty || r.primaryType != b.rel.primaryType || normKey(r.title) != normKey(b.rel.title)) continue;
      if (datum.isEmpty || r.date.compareTo(datum) < 0) datum = r.date;
    }
  }
  if (datum.isEmpty) datum = b.datum;
  final jaar = datum.length >= 4 ? int.tryParse(datum.substring(0, 4)) : null;
  return (album: b.rel.title, jaar: jaar == null || jaar < 1900 ? null : jaar);
}

/// Dezelfde artiest, of de een een uitgebreidere naam van de ander: "Paul McCartney & Wings" bij Paul McCartney.
bool _zelfdeArtiestLos(String a, String b) {
  final ka = artistKey(a), kb = artistKey(b);
  return ka.isNotEmpty && kb.isNotEmpty && (ka == kb || ka.startsWith('$kb ') || kb.startsWith('$ka '));
}

/// Zonder wat er over de uitvoering achter staat: "Loneliness (Radio Cut)" is "Loneliness".
String _zonderUitvoering(String t) {
  var x = t.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '');
  final streep = x.indexOf(' - ');
  if (streep > 0) x = x.substring(0, streep);
  return x.trim();
}

/// Is [album] gewoon de single van [titel] — de plaat die naar het nummer heet ("Summer Of '69" bij Summer Of '69)?
///
/// **Waarom (radiotest van 23-10-2026).** Deezer noemt bij een radionummer vaak de single als album. Van de dertien
/// nummers die de radio die ochtend haalde, kregen er zeven zo een single als album — en een single krijgt geen
/// tracklijst en dus geen cd-afbeelding. Saber: *"ook vooral de cd afbeeldingen"*. Dan zoekt de radio toch het
/// studioalbum op ([origineleUitgaveVan]); is er geen, dan blijft de single.
bool albumIsDeSingle(String album, String titel) {
  final a = normKey(album);
  if (a.isEmpty) return false;
  final t = normKey(_zonderUitvoering(titel));
  return a == normKey(titel) || a == t || normKey(_zonderUitvoering(album)) == t;
}

/// De Deezer-single die naar [titel] heet en waarop precies dit nummer staat — de terugval van [origineleUitgaveVan]
/// voor dance, waar MusicBrainz vaak alleen verzamelaars kent. Gemeten op 23-10-2026: van Tomcraft — Loneliness kent
/// MusicBrainz alleen Viva Hits 19, Electro Tech en Best of House; Deezer heeft "Loneliness (Radio Cut)" op de single
/// "Loneliness". Een album met een andere naam ("Café Del Mar: The Best of the Remixes") telt hier niet: dat is geen
/// single, en of het de oorspronkelijke plaat is, valt aan de naam niet te zien.
String? deezerSingleUit(List<dynamic> data, String artiest, String titel, {int? seconden}) {
  final wil = normKey(titel), wilKaal = normKey(zonderGastTitel(titel)), naam = normKey(_zonderUitvoering(titel));
  if (naam.isEmpty) return null;
  for (final d in data) {
    if (d is! Map) continue;
    final art = d['artist'];
    if (!_zelfdeArtiestAls('${art is Map ? art['name'] ?? '' : ''}', artiest)) continue;
    final t = '${d['title'] ?? ''}';
    if (normKey(t) != wil && normKey(zonderGastTitel(t)) != wilKaal) continue;
    final duur = (d['duration'] as num?)?.toInt() ?? 0;
    if (seconden != null && seconden > 0 && duur > 0 && (duur - seconden).abs() > 8) continue;
    final alb = d['album'];
    final a = alb is Map ? '${alb['title'] ?? ''}' : '';
    if (a.isEmpty || normKey(a) != naam || lijktVerzamelaar(a)) continue;
    return a;
  }
  return null;
}

/// [album] zonder wat er over de editie achter staat: "Private Dancer (30th Anniversary Edition)" is "Private Dancer",
/// "Rumours (2004 Remaster)" is "Rumours", "Woodface - Remastered" is "Woodface". Zie [studioalbumUitGroepen].
String zonderEditie(String album) => album.replaceAll(_editieDeel, '').replaceAll(_editieStaart, '').trim();
// Nooit een deel waarin "live" (of een andere uitvoering) staat: "Luka (Live 1986 Broadcast Remastered)" is niet Luka.
final _editieDeel = RegExp(
    r'\s*[\(\[](?![^\)\]]*\b(live|broadcast|unplugged|demo|remix|mix|acoustic|instrumental|karaoke)\b)'
    r'[^\)\]]*\b(deluxe|remaster(ed)?|expanded|anniversary|edition|reissue|bonus|special|collector|legacy|super)\b'
    r'[^\)\]]*[\)\]]',
    caseSensitive: false);
final _editieStaart = RegExp(
    r'\s+-\s+(?![^-]*\b(live|broadcast|unplugged|demo|remix|mix|acoustic|instrumental|karaoke)\b)'
    r'[^-]*\b(remaster(ed)?|deluxe|edition|anniversary|expanded|single|ep)\b[^-]*$',
    caseSensitive: false);

/// [o], of null als hij van na [nietNa] is — zie [oorsprongJaar]. Zonder jaar telt hij.
({String album, int? jaar})? nietTeLaat(({String album, int? jaar}) o, int? nietNa) =>
    nietNa != null && (o.jaar ?? 0) > nietNa ? null : o;

/// Een live-opname, in de titel of op het album (zoals `_liveOpname` in recommend.dart).
final _live = RegExp(r'\b(live|broadcasts?|unplugged|in concert)\b', caseSensitive: false);

/// Wanneer dit nummer er al was: het vroegste jaar van de opnames die het zijn (MusicBrainz: hun eerste datum) en van de
/// ISRC-codes van de Deezer-nummers die het zijn, nooit live. Geen van beide is het origineel zelf — de zoekvraag geeft
/// heruitgaven, een ISRC is soms die van het digitaliseren — maar het nummer bestond toen in elk geval al. Voor
/// [studioalbumUitGroepen] (`nietNa`). Null: onbekend.
int? oorsprongJaar(List<MbRecording> opnames, List<dynamic> deezer, {required String artiest, required String titel}) {
  final wil = _titelvormen(titel);
  int? min;
  void zie(int? j) {
    if (j != null && j > 1900 && (min == null || j < min!)) min = j;
  }

  for (final o in opnames) {
    // Live: MusicBrainz noemt een live-opname gewoon "Don't Get Me Wrong" en zet "live" bij de plaat.
    final live = o.releases.isNotEmpty && o.releases.every((r) => r.secondaryTypes.contains('Live'));
    if (!_zelfdeArtiestAls(o.artist, artiest) || live || !_ditNummer(o.title, wil, 0, null)) continue;
    final d = o.firstReleaseDate;
    if (d.length >= 4) zie(int.tryParse(d.substring(0, 4)));
  }
  for (final d in deezer) {
    if (d is! Map) continue;
    final art = d['artist'];
    if (!_zelfdeArtiestAls('${art is Map ? art['name'] ?? '' : ''}', artiest)) continue;
    final t = '${d['title'] ?? ''}', alb = d['album'];
    if (_live.hasMatch(t) || _live.hasMatch(alb is Map ? '${alb['title'] ?? ''}' : '')) continue;
    if (!_ditNummer(t, wil, 0, null)) continue;
    zie(isrcJaar(d['isrc'] as String?));
  }
  return min;
}

/// Een album waarop dit nummer staat, als kandidaat voor [studioalbumUitGroepen]: zijn [titel], en het id van zijn
/// plaat ([groep], van MusicBrainz) als dat bekend is — Deezer kent alleen de titel.
typedef Albumkandidaat = ({String titel, String groep});

/// Het oudste studioalbum van de artiest waar dit nummer op staat. [kandidaten]: de albums waarop MusicBrainz en Deezer
/// het nummer kennen; [groepen]: de studioalbums van de artiest ([MusicBrainzService.studioalbumsVan]), met de datum
/// van hun eerste uitgave. Alleen een studioalbum telt (soort Album, zonder bijsoort: geen verzamelaar, live-plaat of
/// soundtrack). Null: geen kandidaat is zo'n album — dan [origineleUitgaveUit], zoals voorheen.
///
/// - Een kandidaat met het id van zijn plaat telt op dat id. Zonder id (Deezer) op de titel, zonder editie
///   ([zonderEditie]), maar niet als twee studioalbums zo heten: Duran Duran heeft er twee met die naam (1981 en 1993),
///   en Ordinary World staat op die van 1993.
/// - Een editie telt als de plaat zelf, ook een deluxe: de deluxe van Break Every Rule draagt What's Love Got to Do with
///   It, maar Private Dancer is ouder en wint. Een regel "deluxe pas als tweede keus" duwde Nothing Compares 2 U van I
///   Do Not Want What I Haven't Got (Deluxe Version, 1990) naar How About I Be Me (2012) (23-10-2026).
///
/// **Waarom (radio vanaf Luka, 23-10-2026).** Van 48 opgehaalde nummers kregen er 28 geen album en 3 een verkeerd:
/// de zoekvraag op opnames geeft bij MusicBrainz vooral heruitgaven. Linger kwam op Bury the Hatchet (1999), What's
/// Love Got to Do with It op Break Every Rule (Deluxe Edition), Luka op de heropname van 2010; Weather With You, One Of
/// Us en Solsbury Hill op niets. Het jaar van de plaat zelf staat alleen bij de releasegroep.
///
/// [nietNa]: een plaat van ná dat jaar telt niet. Het nummer bestond toen al lang ([oorsprongJaar]), en dan is die plaat
/// een latere uitgave met het als bonus: Don't Get Me Wrong (1986) stond bij Deezer alleen nog op Alone (Special
/// Edition, 2016) en op verzamelaars, niet op Get Close (23-10-2026).
({String album, int? jaar})? studioalbumUitGroepen(Iterable<Albumkandidaat> kandidaten, List<MbReleaseGroup> groepen,
    {int? nietNa}) {
  String kaal(String s) => normKey(s).replaceAll(RegExp(r'[^a-z0-9]'), '');
  final opId = <String, ({String titel, String datum})>{};
  final opTitel = <String, List<({String titel, String datum})>>{};
  for (final g in groepen) {
    final d = g.firstDate ?? '';
    final k = kaal(g.title);
    if (g.primaryType != 'Album' || g.secondaryTypes.isNotEmpty || d.length < 4 || k.isEmpty) continue;
    if (nietNa != null && (int.tryParse(d.substring(0, 4)) ?? 0) > nietNa) continue;
    final plaat = (titel: g.title, datum: d);
    if (g.mbid.isNotEmpty) opId[g.mbid] = plaat;
    (opTitel[k] ??= []).add(plaat);
  }
  ({String titel, String datum})? vind(Albumkandidaat c) {
    if (c.groep.isNotEmpty) return opId[c.groep];
    final lijst = opTitel[kaal(zonderEditie(c.titel))] ?? opTitel[kaal(c.titel)];
    return lijst != null && lijst.length == 1 ? lijst.single : null;
  }

  // Het vroegste jaar; in hetzelfde jaar de plaat die MusicBrainz én Deezer noemen, dan de preciezere datum. Bij
  // Carnival won "Garden Lillies" (alleen "1995", alleen MusicBrainz) zo niet meer van Tigerlily (16-06-1995).
  ({String titel, String datum})? oudste(Iterable<Albumkandidaat> cs) {
    final bronnen = <({String titel, String datum}), Set<bool>>{};
    for (final c in cs) {
      final g = vind(c);
      if (g != null) (bronnen[g] ??= {}).add(c.groep.isNotEmpty);
    }
    int vergelijk(({String titel, String datum}) a, ({String titel, String datum}) b) {
      final j = a.datum.substring(0, 4).compareTo(b.datum.substring(0, 4));
      if (j != 0) return j;
      final n = bronnen[b]!.length.compareTo(bronnen[a]!.length);
      if (n != 0) return n;
      final p = b.datum.length.compareTo(a.datum.length);
      return p != 0 ? p : a.datum.compareTo(b.datum);
    }

    return bronnen.keys.isEmpty ? null : bronnen.keys.reduce((a, b) => vergelijk(a, b) <= 0 ? a : b);
  }

  final b = oudste(kandidaten);
  return b == null ? null : (album: b.titel, jaar: int.tryParse(b.datum.substring(0, 4)));
}

/// De vormen waarin een titel hetzelfde nummer noemt: zoals hij is, zonder gast, en zonder editie ([zonderEditie]). Bij
/// Deezer heet het origineel van Nothing Compares 2 U "Nothing Compares 2 U (2009 Remaster)", en de radio zocht zelf
/// "Blue Hotel (Remastered)" (23-10-2026). Een live-versie blijft een andere titel.
Set<String> _titelvormen(String titel) {
  final kaal = zonderEditie(titel);
  return {normKey(titel), normKey(zonderGastTitel(titel)), normKey(kaal), normKey(zonderGastTitel(kaal))}
    ..remove('');
}

/// Is [titel] (van een opname of een Deezer-nummer) dit nummer ([wil]: de [_titelvormen] van het gezochte), en past de
/// lengte ([duur] tegen [seconden], hoogstens [speling] s verschil; null: de lengte telt niet)?
bool _ditNummer(String titel, Set<String> wil, int duur, int? seconden, {int? speling}) =>
    _titelvormen(titel).any(wil.contains) &&
    !(speling != null && seconden != null && seconden > 0 && duur > 0 && (duur - seconden).abs() > speling);

/// De albums (officieel, soort Album) waarop [opnames] dit nummer van [artiest] dragen — kandidaten voor
/// [studioalbumUitGroepen].
List<Albumkandidaat> albumsMetNummerUitOpnames(List<MbRecording> opnames,
    {required String artiest, required String titel, int? seconden}) {
  final wil = _titelvormen(titel);
  return [
    for (final o in opnames)
      // ±8 s, zoals [origineleUitgaveUit]: de lengte van een opname is exact, en een heropname is een andere opname —
      // Solsbury Hill op New Blood (2011) duurt 12 s langer dan het origineel van 1977.
      if (_zelfdeArtiestAls(o.artist, artiest) && _ditNummer(o.title, wil, o.seconds, seconden, speling: 8))
        for (final r in o.releases)
          if (r.primaryType == 'Album' && (r.status.isEmpty || r.status == 'Official')) (titel: r.title, groep: r.groep),
  ];
}

/// De albums waarop Deezer dit nummer van [artiest] kent, uit een zoekuitslag op nummers ([data]) — kandidaten voor
/// [studioalbumUitGroepen]. Deezer kent Linger op "Everybody Else Is Doing It, So Why Can't We?", waar MusicBrainz'
/// zoekvraag alleen latere opnames gaf.
///
/// Zonder lengte: de titel moet al precies kloppen, en de radio kent vaak de lengte van een andere versie. If It Makes
/// You Happy staat met 5:24 op Sheryl Crow, de radio had de radio-edit van 4:24; One Of Us staat met 321 s op Relish,
/// de radio verwachtte 300 (23-10-2026).
List<Albumkandidaat> deezerAlbumsMetNummer(List<dynamic> data, String artiest, String titel, {int? seconden}) {
  final wil = _titelvormen(titel);
  final uit = <Albumkandidaat>[];
  for (final d in data) {
    if (d is! Map) continue;
    final art = d['artist'];
    if (!_zelfdeArtiestAls('${art is Map ? art['name'] ?? '' : ''}', artiest)) continue;
    if (!_ditNummer('${d['title'] ?? ''}', wil, (d['duration'] as num?)?.toInt() ?? 0, seconden)) continue;
    final alb = d['album'];
    final a = alb is Map ? '${alb['title'] ?? ''}' : '';
    if (a.isNotEmpty) uit.add((titel: a, groep: ''));
  }
  return uit;
}

/// De oorspronkelijke uitgave. Eerst het oudste studioalbum van de artiest waarop MusicBrainz of Deezer het nummer
/// kent ([studioalbumUitGroepen]); kent die geen, dan [origineleUitgaveUit] met de opnames van MusicBrainz, en kent die
/// alleen verzamelaars, dan [deezerSingleUit]. Null bij geen antwoord — dan blijft het nummer zonder album, zoals
/// voorheen. Het jaar van een Deezer-single komt daarna uit [deezerPlekOpAlbum].
Future<({String album, int? jaar})?> origineleUitgaveVan(String artiest, String titel, {int? seconden}) async {
  // Zoeken zonder editie: MusicBrainz kent "Blue Hotel", niet "Blue Hotel (Remastered)" (23-10-2026).
  final zoek = zonderEditie(titel).isEmpty ? titel : zonderEditie(titel);
  // Eerst alleen op albums (de studio-opname staat anders achter tientallen live-opnames), dan gewoon.
  final mbs = MusicBrainzService();
  final albums = await mbs.searchRecordings(zoek, artist: artiest, max: 15, alleenAlbums: true);
  final gewoon = await mbs.searchRecordings(zoek, artist: artiest, max: 15);
  final gezien = <String>{};
  final opnames = [
    for (final r in [...albums, ...gewoon])
      if (gezien.add(r.mbid)) r,
  ];
  final j = await DeezerBaan.haal(
      'https://api.deezer.com/search?q=${Uri.encodeComponent('$artiest $zoek')}&limit=25');
  final data = (j?['data'] as List?) ?? const [];
  // Een plaat die meer dan vier jaar na het ontstaan van het nummer uitkwam, draagt het als bonus of als B-kant — een
  // single kan een jaar of twee vóór zijn album uitkomen, een heruitgave van een latere plaat dertig. Geldt voor elke
  // weg hieronder: Don't Get Me Wrong (1986) kwam via [origineleUitgaveUit] op The Losing, een single uit 2003
  // (23-10-2026). Liever geen album dan een fout.
  final al = oorsprongJaar(opnames, data, artiest: artiest, titel: titel);
  final nietNa = al == null ? null : al + 4;
  // Een remix hoort op zijn remixplaat, niet op een studioalbum — dat regelt [origineleUitgaveUit].
  if (!RegExp(r'\b(re)?mix\b', caseSensitive: false).hasMatch(titel)) {
    // Het id van de artiest staat al in zijn opnames: niet opnieuw raden (naamgenoten — "Oasis" is ook een trance-act).
    final id = [
      for (final o in opnames)
        if (o.artistMbid.isNotEmpty && _zelfdeArtiestAls(o.artist, artiest)) o.artistMbid,
    ].firstOrNull;
    if (id != null) {
      final studio = studioalbumUitGroepen([
        ...albumsMetNummerUitOpnames(opnames, artiest: artiest, titel: titel, seconden: seconden),
        ...deezerAlbumsMetNummer(data, artiest, titel, seconden: seconden),
      ], await mbs.studioalbumsVan(id), nietNa: nietNa);
      if (studio != null) return studio;
    }
  }
  final mb = origineleUitgaveUit(opnames, artiest: artiest, titel: zoek, seconden: seconden);
  if (mb != null) return nietTeLaat(mb, nietNa);
  final single = deezerSingleUit(data, artiest, zoek, seconden: seconden);
  return single == null ? null : (album: single, jaar: null);
}

/// Hoeveel vragen met voorrang er binnen [kAudioDbSalvoVenster] zonder afstand mogen.
///
/// De drie seconden van de gewone rij zijn geijkt op een lange veeg: zesenvijftig albums aan 1,2 s gaven
/// zevenenveertig lege antwoorden. Een paar vragen van één scherm is iets anders — gemeten op 21-10-2026:
/// twaalf vragen binnen twee seconden kregen alle twaalf een volledig antwoord (cd en achterkant).
const kAudioDbSalvo = 6;
const kAudioDbSalvoVenster = Duration(seconds: 20);

/// Hoe lang een vraag met voorrang nog moet wachten. Zolang er in het venster minder dan [kAudioDbSalvo]
/// voorrangsvragen weg zijn: niet. Daarna weer [afstand] na de vorige vraag, maar nooit langer dan die
/// afstand zelf — ook niet als de klok terugsprong. Ruimt [verstuurd] op wat buiten het venster valt.
Duration audioDbVoorrangWacht({
  required List<DateTime> verstuurd,
  required DateTime laatste,
  required DateTime nu,
  required Duration afstand,
}) {
  verstuurd.removeWhere((t) {
    final oud = nu.difference(t);
    return oud.isNegative || oud > kAudioDbSalvoVenster;
  });
  if (verstuurd.length < kAudioDbSalvo) return Duration.zero;
  final sinds = nu.difference(laatste);
  if (sinds.isNegative || sinds >= afstand) return Duration.zero;
  return afstand - sinds;
}

/// Fetches missing album covers from Deezer → Discogs → MusicBrainz/CoverArtArchive
/// and caches them on disk. Ported from the server's enrichment logic.
class CoverEnricher {
  final AppSettings settings;
  /// Het net — of een nagebootst net in een toets.
  ///
  /// Zonder dit is "hij vraagt het NIET nog eens" niet te bewijzen: je kunt alleen zien dat er weer
  /// niets terugkomt, niet dat er geen verzoek uitging. Zie `test/albuminfo_briefje_test.dart`.
  CoverEnricher(this.settings, {this.client});

  final http.Client? client;

  Future<http.Response> _haal(Uri u, {Map<String, String>? headers}) =>
      client == null ? http.get(u, headers: headers) : client!.get(u, headers: headers);

  static const _ua = 'DebridMusic/0.1 ( https://github.com/sabair24/Debrid-music-app )';
  static final _albumJunk = RegExp(
    r'\((?:[A-Za-z]{1,4}[\s-]?\d{2,6}|maxi[-\s]?cd|maxi|single|radio(?:\s+mix)?|extended(?:\s+\w+)?|original(?:\s+mix)?|\d{4}|[\w\s]*remix|edit|vinyl|promo|re-?issue)\)|\[[^\]]*\]',
    caseSensitive: false,
  );
  static final _featRe = RegExp(r'\s+(feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false);
  static const _generic = {'various', 'various artists', 'va', 'onbekende artiest', 'unknown artist', 'unknown', ''};

  static String _dir(String name) {
    return '$appDir${Platform.pathSeparator}$name';
  }

  Directory get cacheDir => Directory(_dir('covers'));
  Directory get artistDir => Directory(_dir('artists'));
  Directory get bioDir => Directory(_dir('bios'));
  Directory get fixDir => Directory(_dir('fixcovers'));

  /// The sleeve OF a pressing that was actually identified — kept apart from [cacheDir] because it
  /// ranks differently: an enriched cover is a guess by name and loses to whatever the files carry,
  /// while this one belongs to a named release and beats it.
  ///
  /// That distinction only mattered within a session until now. D'Eux, downloaded off Soulseek,
  /// carries "The Essential Céline Dion" as its embedded art — someone's rip of the compilation. The
  /// album page fetched the right sleeve and handed it to the library, so the grid corrected itself
  /// the moment you opened the record; nothing was written down, so the next start went back to the
  /// wrong one. The fix looked like it worked every time you checked it.
  Directory get resolvedDir => Directory(_dir('resolved'));

  /// De digitale voorkanten ([digitaleVoorkant]) — apart van [cacheDir] (een gok op naam voor wie geen
  /// hoes heeft) en van [resolvedDir] (wat de bibliotheek overnam).
  Directory get digitaalDir => Directory(_dir('digitaal'));

  /// Wat er al eens gelezen of gevonden is — en dan HETZELFDE object terug, zoals `DiscogsService._gelezen`:
  /// een `Image.memory` herkent een beeld aan zijn bytes-object, en een nieuw object laat Nu speelt bij
  /// elke nummerwissel even flitsen (Saber, 10-10-2026). Begrensd: de opwarmer loopt de hele bibliotheek af.
  static final _digitaalGelezen = <String, ({Uint8List bytes, String bron})>{};
  static const _digitaalGelezenMax = 24;
  static final _digitaalOnderweg = <String, Future<({Uint8List bytes, String bron})?>>{};

  /// Zo lang telt "niets gevonden": een nieuwe single staat er soms pas na een paar dagen.
  static const _digitaalMisDuur = Duration(days: 3);

  /// De digitale voorkant van een album: Deezer op 1200×1200 als artiest én titel kloppen
  /// ([kiesDigitaalAlbum]), anders TheAudioDB (`strAlbumThumb`, ~700×700). Saber, 21-10-2026: "digitaal
  /// wint altijd" en "Deezer 1200 eerst". `bron` is `dz:<album-id>` of `tadb` — zie [isDigitaleHerkomst].
  ///
  /// Op schijf bewaard ([digitaalDir]), één zoektocht per album tegelijk. [netwerk] uit: alleen wat er al
  /// ligt — voor wie meteen iets wil tekenen.
  ///
  /// [titels]: de nummers van dit album (Nu speelt: het spelende eerst). Is het album nergens te vinden en
  /// lijkt het een verzamelrip — één of twee nummers van deze artiest, of een titel als "Foute Cd 11 Cd2" —
  /// dan de hoes van de originele uitgave van het NUMMER (Saber, 21-10-2026, over Jordy — Dur Dur D'être
  /// Bébé uit de Foute CD van Q-music: "het moet echt de originele hoes zijn").
  Future<({Uint8List bytes, String bron})?> digitaleVoorkant(String artistRaw, String albumRaw,
      {bool voorrang = false, bool netwerk = true, List<String> titels = const []}) async {
    final artist = _cleanArtist(artistRaw), album = _cleanAlbum(albumRaw);
    if (album.isEmpty) return null;
    final sleutel = fnv1a('${artist.toLowerCase()}|${album.toLowerCase()}');
    final al = _digitaalGelezen[sleutel];
    if (al != null) return al;
    final sep = Platform.pathSeparator;
    final img = File('${digitaalDir.path}$sep$sleutel.jpg'), van = File('${digitaalDir.path}$sep$sleutel.from');
    try {
      if (await img.exists() && await van.exists()) {
        final b = await img.readAsBytes();
        final f = (await van.readAsString()).trim();
        if (b.length > 1500 && f.isNotEmpty) return _onthoudDigitaal(sleutel, (bytes: b, bron: f));
      }
    } catch (_) {/* niets te lezen: dan zoeken */}
    if (!netwerk) return null;
    final generiek = _generic.contains(artist.toLowerCase());
    final perNummer = !generiek &&
        titels.any((t) => t.trim().isNotEmpty) &&
        (titels.length <= 2 || lijktVerzamelaar(album));
    final lopend = '$sleutel|${perNummer ? 'nummer' : 'album'}';
    return _digitaalOnderweg[lopend] ??=
        _zoekDigitaal(sleutel, artist, album, voorrang, img, van, perNummer ? titels : const []).whenComplete(() {
      _digitaalOnderweg.remove(lopend);
    });
  }

  /// De hoes van de originele uitgave van een van [titels] — zie [albumsVanNummer] en [kiesOrigineleUitgave].
  /// Gemeten op 21-10-2026: "Jordy Dur Dur D'être Bébé" geeft bij Deezer "Pochette Surprise" (album, 1992) en
  /// twee karaokeversies.
  Future<({Uint8List bytes, String bron})?> _origineleVoorkant(String artist, List<String> titels) async {
    for (final titel in titels.where((t) => t.trim().isNotEmpty).take(3)) {
      try {
        final j = await DeezerBaan.haal(
            'https://api.deezer.com/search?q=${Uri.encodeComponent('$artist $titel')}&limit=15');
        final ids = albumsVanNummer((j?['data'] as List?) ?? const [], artist, titel);
        final albums = <Map<String, dynamic>>[];
        for (final id in ids) {
          final a = await DeezerBaan.haal('https://api.deezer.com/album/$id');
          if (a != null) albums.add(a);
        }
        final o = kiesOrigineleUitgave(albums, artist);
        final url = o == null ? null : (o['cover_xl'] ?? o['cover_big']) as String?;
        if (o == null || url == null || url.isEmpty) continue;
        final groot = deezerHoes1200(url);
        final b = (groot == url ? null : await _download(groot)) ?? await _download(url);
        if (b != null) return (bytes: b, bron: 'dz:${o['id']}');
      } catch (_) {/* het volgende nummer */}
    }
    return null;
  }

  ({Uint8List bytes, String bron}) _onthoudDigitaal(String sleutel, ({Uint8List bytes, String bron}) d) {
    _digitaalGelezen.remove(sleutel);
    _digitaalGelezen[sleutel] = d;
    while (_digitaalGelezen.length > _digitaalGelezenMax) {
      _digitaalGelezen.remove(_digitaalGelezen.keys.first);
    }
    return d;
  }

  Future<({Uint8List bytes, String bron})?> _zoekDigitaal(String sleutel, String artist, String album,
      bool voorrang, File img, File van, List<String> perNummer) async {
    final mis = File('${digitaalDir.path}${Platform.pathSeparator}$sleutel.none');
    try {
      // Een "niets gevonden" telt alleen als hij ook per nummer gezocht had, wanneer dat nu kan.
      if (await mis.exists() &&
          DateTime.now().difference(await mis.lastModified()) <= _digitaalMisDuur &&
          (perNummer.isEmpty || (await mis.readAsString()).trim() == 'nummer')) {
        return null;
      }
    } catch (_) {}
    final generiek = _generic.contains(artist.toLowerCase());
    ({Uint8List bytes, String bron})? gevonden;
    var deezerAntwoordde = false;
    try {
      final j = await DeezerBaan.haal('https://api.deezer.com/search/album'
          '?q=${Uri.encodeComponent(generiek ? album : '$artist $album')}&limit=10');
      deezerAntwoordde = j != null;
      final d = kiesDigitaalAlbum((j?['data'] as List?) ?? const [], artist, album, generiek: generiek);
      final url = d == null ? null : (d['cover_xl'] ?? d['cover_big']) as String?;
      if (d != null && url != null && url.isNotEmpty) {
        final groot = deezerHoes1200(url);
        final b = (groot == url ? null : await _download(groot)) ?? await _download(url);
        if (b != null) gevonden = (bytes: b, bron: 'dz:${d['id']}');
      }
    } catch (_) {/* Deezer weigerde of zweeg: TheAudioDB mag het nog zeggen */}
    if (gevonden == null && !generiek) {
      final u = (await albumInfo(artist, album, voorrang: voorrang))?.frontUrl;
      if (u != null) {
        final b = await _download(u);
        if (b != null) gevonden = (bytes: b, bron: 'tadb');
      }
    }
    // Het album nergens, en het is een verzamelrip: de originele uitgave van het nummer.
    if (gevonden == null && perNummer.isNotEmpty) gevonden = await _origineleVoorkant(artist, perNummer);
    try {
      await digitaalDir.create(recursive: true);
      if (gevonden != null) {
        await img.writeAsBytes(gevonden.bytes);
        await van.writeAsString(gevonden.bron);
        if (await mis.exists()) await mis.delete();
      } else if (deezerAntwoordde) {
        // Alleen als Deezer echt antwoordde: een weigering is geen "bestaat niet".
        await mis.writeAsString(perNummer.isEmpty ? 'album' : 'nummer');
      }
    } catch (_) {/* niet bewaard kost alleen een tweede zoektocht */}
    return gevonden == null ? null : _onthoudDigitaal(sleutel, gevonden);
  }

  /// Een kort merkteken voor precies déze hoes.
  ///
  /// **Waarom dit bestaat.** De cachesleutel van een hoes is `fnv(artiest|titel)` — die verandert
  /// niet als je een ándere hoes voor hetzelfde album kiest. Een telefoon die de verkeerde hoes ooit
  /// heeft opgehaald houdt hem dus voor altijd: het bestand ligt er, de naam klopt, en niemand kan
  /// zien dat de inhoud achterhaald is. Gemeld op 13-08-2026 en precies zo gemeten: op de pc de
  /// juiste Whitney-hoes, op de telefoon het logo van een verzamelaar, en na élke herstart weer.
  ///
  /// Over ÁLLE bytes, en niet over een greep hier en daar. De eerste versie nam er 64 verspreid over
  /// het bestand, "want een hoes is honderden kilobytes". De toets `een hoes van dezelfde lengte
  /// maar andere inhoud ook` viel daar meteen over: één gewijzigde byte op plek 4000 zat net tussen
  /// twee grepen in, en dan zou een toestel een nieuwe hoes voor de oude houden. Precies de fout die
  /// dit merk moet vóórkomen.
  ///
  /// De kosten vallen mee: FNV over een paar honderd kilobyte is een kwestie van microseconden, en
  /// dit gebeurt alleen bij het bouwen van een catalogusmomentopname — niet per verzoek.
  static String hoesMerk(List<int>? bytes) {
    if (bytes == null || bytes.length < 100) return '';
    // Eerst de lengte als tekst, dan de bytes zelf — twee stukken achter elkaar in dezelfde hash.
    return fnv1aBytes(bytes, fnv1aVan(bytes.length.toString())).toRadixString(16);
  }

  String keyFor(Album a) => fnv1a('${a.artist.toLowerCase()}|${a.title.toLowerCase()}');

  /// Het merkteken van de hoes die op de telefoon in [cacheDir] ligt.
  File _merkFile(Album a) => File('${cacheDir.path}${Platform.pathSeparator}${keyFor(a)}.merk');

  /// Welke hoes hier bewaard is, volgens de pc. Leeg als we het niet weten.
  Future<String> bewaardMerk(Album a) async {
    try {
      final f = _merkFile(a);
      return await f.exists() ? (await f.readAsString()).trim() : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> schrijfMerk(Album a, String merk) async {
    try {
      await cacheDir.create(recursive: true);
      await _merkFile(a).writeAsString(merk, flush: true);
    } catch (_) {
      // Zonder merkteken valt de cache terug op het oude gedrag: hij blijft staan. Nooit een reden
      // om het binnenhalen van een hoes te laten mislukken.
    }
  }
  File _cacheFile(Album a) => File('${cacheDir.path}${Platform.pathSeparator}${keyFor(a)}.jpg');
  File _fixFile(Album a) => File('${fixDir.path}${Platform.pathSeparator}${keyFor(a)}.jpg');

  /// A user-corrected cover (manual editor), if one was saved for this album.
  Future<Uint8List?> fixedCover(Album a) async {
    final f = _fixFile(a);
    if (!await f.exists()) return null;
    final b = await f.readAsBytes();
    return b.length > 100 ? b : null;
  }

  File _resolvedFile(Album a) => File('${resolvedDir.path}${Platform.pathSeparator}${keyFor(a)}.jpg');
  File _resolvedFromFile(Album a) =>
      File('${resolvedDir.path}${Platform.pathSeparator}${keyFor(a)}.from');

  /// The saved sleeve of an identified pressing, with the marker saying WHICH pressing
  /// (`rel:12345`, `mb:<uuid>`).
  ///
  /// The marker is required, not optional: bytes without it cannot be told apart from a by-name
  /// guess, and a guess must not outrank the art in the files.
  Future<(Uint8List, String)?> resolvedCover(Album a) async {
    try {
      final img = _resolvedFile(a), from = _resolvedFromFile(a);
      if (!await img.exists() || !await from.exists()) return null;
      final marker = (await from.readAsString()).trim();
      if (marker.isEmpty) return null;
      final b = await img.readAsBytes();
      return b.length > 100 ? (b, marker) : null;
    } catch (_) {
      return null;
    }
  }

  /// Write down a sleeve that was traced to a specific pressing, so the next start knows it too.
  Future<void> saveResolvedCover(Album a, Uint8List bytes, String from) async {
    if (bytes.length <= 100 || from.trim().isEmpty) return;
    try {
      await resolvedDir.create(recursive: true);
      await _resolvedFile(a).writeAsBytes(bytes);
      await _resolvedFromFile(a).writeAsString(from.trim());
    } catch (_) {/* the cover is on the album in memory; this only costs the next start */}
  }

  /// Persist a user-picked cover for [a] (survives rescans; top display priority).
  Future<void> saveFixedCover(Album a, Uint8List bytes) async {
    await fixDir.create(recursive: true);
    await _fixFile(a).writeAsBytes(bytes);
  }

  /// Carry a hand-picked cover — and a traced one — to the album's new name.
  ///
  /// [keyFor] is the artist and the title, so correcting either moves the filename this was saved
  /// under. Within the session nothing showed, because the cover is carried across a regroup by
  /// track path — but at the next start the lookup went to the new name, found nothing, and the
  /// cover the user chose by hand was gone. Nobody would connect that to a rename days earlier.
  Future<void> reKeyFixedCover(
      String oldArtist, String oldTitle, String newArtist, String newTitle) async {
    final from = fnv1a('${oldArtist.toLowerCase()}|${oldTitle.toLowerCase()}');
    final to = fnv1a('${newArtist.toLowerCase()}|${newTitle.toLowerCase()}');
    if (from == to) return;
    // Both caches are keyed the same way, so both go stale on the same rename.
    for (final (dir, ext) in [(fixDir, 'jpg'), (resolvedDir, 'jpg'), (resolvedDir, 'from')]) {
      try {
        final src = File('${dir.path}${Platform.pathSeparator}$from.$ext');
        if (!await src.exists()) continue;
        await src.rename('${dir.path}${Platform.pathSeparator}$to.$ext');
      } catch (_) {/* the cover is still on the album in memory; this is only the next start */}
    }
  }

  /// Download raw image bytes for a chosen cover URL (with the right User-Agent).
  Future<Uint8List?> downloadImage(String url) => _download(url);
  File _artistFile(String name) => File('${artistDir.path}${Platform.pathSeparator}${fnv1a(name.toLowerCase())}.jpg');
  File _bioFile(String name) => File('${bioDir.path}${Platform.pathSeparator}${fnv1a(name.toLowerCase())}.txt');

  /// Put bytes in the cover cache that did not come from the web enricher — on a Mac or an iPad
  /// the covers arrive from the paired PC, and caching them there means the second start shows the
  /// grid instantly instead of refetching every one over wifi.
  Future<void> putCached(Album a, Uint8List bytes) async {
    if (bytes.length <= 100) return;
    try {
      await cacheDir.create(recursive: true);
      await _cacheFile(a).writeAsBytes(bytes);
    } catch (_) {
      // A full disk must not cost you the cover you are looking at.
    }
  }

  Future<Uint8List?> cached(Album a) async {
    final f = _cacheFile(a);
    if (!await f.exists()) return null;
    final b = await f.readAsBytes();
    return b.length > 100 ? b : null; // skip empty/corrupt cache files
  }

  Future<Uint8List?> cachedArtist(String name) async {
    final f = _artistFile(name);
    if (!await f.exists()) return null;
    final b = await f.readAsBytes();
    return b.length > 100 ? b : null;
  }

  /// Deezer builds a picture URL from the MD5 of the image, so an artist with no photo gets the
  /// MD5 of nothing — and serves a grey silhouette rather than a 404. Taking it at face value put
  /// that silhouette in the hero AND blurred it across the whole banner; no picture looks better.
  static const _noPhoto = 'd41d8cd98f00b204e9800998ecf8427e';

  /// Het adres van Deezers artiestfoto (1000×1000, anders 500×500), zonder hem op te halen. Voor
  /// "Foto kiezen": dezelfde foto die de pagina als terugval toont, nu ook als keuze met zijn maat.
  Future<({String url, int maat})?> deezerFotoAdres(String name) async {
    if (_generic.contains(name.trim().toLowerCase())) return null;
    try {
      final j = await DeezerBaan.haal(
          'https://api.deezer.com/search/artist?q=${Uri.encodeComponent(name)}&limit=1');
      final data = (j?['data'] as List?) ?? const [];
      if (data.isEmpty) return null;
      final xl = data.first['picture_xl'] as String?;
      final url = xl ?? data.first['picture_big'] as String?;
      if (url == null || url.isEmpty || url.contains(_noPhoto)) return null;
      return (url: url, maat: xl != null ? 1000 : 500);
    } catch (_) {
      return null;
    }
  }

  /// Fetch + cache an artist photo from Deezer (keyless).
  Future<Uint8List?> fetchArtistImage(String name) async {
    if (_generic.contains(name.trim().toLowerCase())) return null;
    try {
      // Via de gedeelde rijbaan: hierbuiten telde dit niet mee in het budget van vijftig per vijf
      // seconden dat de radio ook gebruikt — zie `deezerbaan.dart`.
      final j = await DeezerBaan.haal(
          'https://api.deezer.com/search/artist?q=${Uri.encodeComponent(name)}&limit=1');
      final data = (j?['data'] as List?) ?? const [];
      if (data.isEmpty) return null;
      final url = (data.first['picture_xl'] ?? data.first['picture_big']) as String?;
      if (url == null || url.isEmpty || url.contains(_noPhoto)) return null;
      final b = await _download(url);
      if (b != null) {
        await artistDir.create(recursive: true);
        await _artistFile(name).writeAsBytes(b);
      }
      return b;
    } catch (_) {
      return null;
    }
  }

  /// The artwork set behind an artist page: a wide cinematic backdrop and the act's own
  /// wordmark. The logo is the reason this exists — you can't render a name in an artist's
  /// official typography from a font (nobody ships those), but the wordmark itself is a real
  /// image and that IS the official lettering.
  Future<ArtistArt?> artistArt(String name) {
    final sleutel = name.toLowerCase();
    final al = _artiestUitGeheugen(sleutel);
    if (al != null) return Future.value(al);
    final loopt = _artistArtInFlight[sleutel];
    if (loopt != null) return loopt;
    // Een BLOKlichaam, en dat is geen stijlkwestie. Zie `discogs.dart:838-848`: met een pijl
    // (`() => map.remove(k)`) geeft de opruimer terug wát `remove()` teruggeeft — op een
    // `Map<String, Future<…>>` is dat de verwijderde Future zélf, en `whenComplete` wacht dan op het
    // werk dat het net afrondde. Voor altijd, zonder socket, zonder logregel. Die fout kostte daar
    // zes herschrijvingen; hier staat hij één keer opgeschreven en niet nog eens gemaakt.
    final werk = _artistArtVers(name).then((art) {
      if (art != null) _artiestOnthoud(sleutel, art);
      return art;
    }).whenComplete(() {
      _artistArtInFlight.remove(sleutel);
    });
    _artistArtInFlight[sleutel] = werk;
    return werk;
  }

  /// Wat er al eens gelezen is, per artiest — en dan HETZELFDE object terug.
  ///
  /// Saber op 10-10-2026, na de hoezen: *"is dit ook zo voor de naam van de artist via the audio
  /// DB ?"* Ja: [_artistArtVers] las het JSON-bestand en vijf beelden opnieuw van schijf bij elke
  /// vraag, en een `Image.memory` herkent een beeld aan zijn bytes-OBJECT — dus het logo boven de
  /// hoes op Nu speelt werd bij elke andere artiest opnieuw gedecodeerd, na eerst de naam als tekst
  /// (zie `ArtiestKop`). Dezelfde reparatie als `DiscogsArtwork._readArt`. Tweeëndertig artiesten;
  /// een logo is klein.
  static final Map<String, ArtistArt> _artiestGelezen = <String, ArtistArt>{};
  static const int kArtiestGelezenMax = 32;

  static ArtistArt? _artiestUitGeheugen(String sleutel) {
    final a = _artiestGelezen.remove(sleutel);
    if (a != null) _artiestGelezen[sleutel] = a; // weer achteraan: het laatst gebruikt
    return a;
  }

  static void _artiestOnthoud(String sleutel, ArtistArt art) {
    _artiestGelezen.remove(sleutel);
    _artiestGelezen[sleutel] = art;
    while (_artiestGelezen.length > kArtiestGelezenMax) {
      _artiestGelezen.remove(_artiestGelezen.keys.first);
    }
  }

  /// Het logo en de foto's van deze artiest als ze al in het geheugen liggen — meteen, zonder
  /// schijf of net. Voor het eerste beeld na een artiestwissel; zie `ArtiestKop`.
  ArtistArt? artistArtInGeheugen(String name) => _artiestUitGeheugen(name.toLowerCase());

  /// Alles vergeten. Voor toetsen.
  static void vergeetArtiestGelezenVoorToets() => _artiestGelezen.clear();

  /// Wie tegelijk om dezelfde naam vraagt, wacht op hetzelfde antwoord.
  ///
  /// **Vijf aanroepers bij één pagina-opening**: de vervaagde wash achter de pagina, de editoriale
  /// kop, de personenkop, de artiestpagina zelf en de fotokiezer. Zonder deze tabel zijn dat vijf
  /// zoekopdrachten naar dezelfde artiest, tegelijk, op een bron die al terugduwt — en dan is het
  /// niet de traagheid maar de leegte die je ziet. `DiscogsArtwork.releaseArt` heeft deze tabel al;
  /// dit is dezelfde, voor de andere helft van hetzelfde scherm.
  static final _artistArtInFlight = <String, Future<ArtistArt?>>{};

  Future<ArtistArt?> _artistArtVers(String name) async {
    final art = await _artiestMeta(name);
    if (art == null) return null;
    // Keep the bytes locally too: these render on every visit and shouldn't refetch each time.
    final logo = await _cachedArt(name, 'logo', art.logo);
    final backdrop = await _cachedArt(name, 'backdrop', art.backdrop);
    final thumb = await _cachedArt(name, 'thumb', art.thumb);
    final cutout = await _cachedArt(name, 'cutout', art.cutout);
    final clearart = await _cachedArt(name, 'clearart', art.clearart);
    return ArtistArt(
      logo: art.logo,
      backdrop: art.backdrop,
      thumb: art.thumb,
      cutout: art.cutout,
      clearart: art.clearart,
      logoBytes: logo,
      backdropBytes: backdrop,
      thumbBytes: thumb,
      cutoutBytes: cutout,
      clearartBytes: clearart,
    );
  }

  /// Alleen het portret van een artiest (TheAudioDB `strArtistThumb`, 700×700): voor het
  /// artiestenraster en "Klinkt als" (Saber, 17-10-2026: "met effectief de artiest in, niet de album
  /// hoes"). Dezelfde zoektocht en dezelfde map op schijf als [artistArt], maar zonder de vier andere
  /// beelden: voor een raster van tweehonderdzeventig artiesten zou dat op een Shield honderden
  /// megabytes aan achtergronden en logo's zijn die niemand daar ziet.
  Future<Uint8List?> artistThumb(String name) async {
    final sleutel = name.toLowerCase();
    final al = _artiestUitGeheugen(sleutel)?.thumbBytes ?? artistThumbInGeheugen(name);
    if (al != null) return al;
    final art = await _artiestMeta(name);
    if (art == null) return null;
    final b = await _cachedArt(name, 'thumb', art.thumb);
    if (b != null) {
      // HETZELFDE object bij de volgende vraag: een `Image.memory` herkent een beeld aan zijn
      // bytes-object, en zo hoeft heen en weer scrollen in het raster niets opnieuw te decoderen.
      _portretGelezen.remove(sleutel);
      _portretGelezen[sleutel] = b;
      while (_portretGelezen.length > kPortretGelezenMax) {
        _portretGelezen.remove(_portretGelezen.keys.first);
      }
    }
    return b;
  }

  /// Het portret als het al in het geheugen ligt — meteen, voor het eerste beeld van een tegel.
  Uint8List? artistThumbInGeheugen(String name) {
    final sleutel = name.toLowerCase();
    final b = _portretGelezen.remove(sleutel);
    if (b != null) _portretGelezen[sleutel] = b; // weer achteraan: het laatst gebruikt
    return b ?? _artiestUitGeheugen(sleutel)?.thumbBytes;
  }

  /// Zo'n honderd portretten van 700×700 als jpg: een paar MB, genoeg voor een paar schermen raster.
  static final Map<String, Uint8List> _portretGelezen = <String, Uint8List>{};
  static const int kPortretGelezenMax = 120;

  /// Wie tegelijk naar dezelfde artiest zoekt (raster en pagina), wacht op hetzelfde antwoord. Zie
  /// [_artistArtInFlight], en de waarschuwing daar over de pijlvorm in `whenComplete`.
  static final _metaInFlight = <String, Future<ArtistArt?>>{};

  /// Wat TheAudioDB van deze artiest heeft (alleen de adressen): van schijf, of één zoekopdracht.
  Future<ArtistArt?> _artiestMeta(String name) {
    final sleutel = name.toLowerCase();
    final loopt = _metaInFlight[sleutel];
    if (loopt != null) return loopt;
    final werk = _artiestMetaVers(name).whenComplete(() {
      _metaInFlight.remove(sleutel);
    });
    _metaInFlight[sleutel] = werk;
    return werk;
  }

  Future<ArtistArt?> _artiestMetaVers(String name) async {
    final meta = _artistArtFile(name);
    ArtistArt? art;
    if (await meta.exists()) {
      try {
        final j = jsonDecode(await meta.readAsString());
        if (j is Map<String, dynamic>) art = ArtistArt.fromJson(j);
      } catch (_) {/* corrupt entry — refetch */}
    }
    if (art == null) {
      if (_generic.contains(name.trim().toLowerCase())) return null;
      if (await _artiestBeeldGezochtEnLeeg(name)) return null;
      try {
        // **Een tweede poging met de accenten eraf, en die is niet theoretisch.** TheAudioDB's
        // zoekfunctie vindt `Beyoncé` niet en `Beyonce` wel; hetzelfde voor Céline Dion. Gemeten op
        // 06-09-2026: van de 268 artiestnamen in deze bibliotheek dragen er dertien een niet-ASCII
        // teken — Beyoncé, Céline Dion, Édith Piaf, Tiësto, Alizée, Hélène Ségara, Emeli Sandé,
        // Chimène Badi, Gérard Lenorman, Âme, en `Lil’ Kim` met een krulapostrof. Die kregen dus
        // nooit een foto, een logo of een backdrop.
        //
        // Wrang genoeg maakte een eerdere reparatie dit erger: sinds `canonicalName` een accent
        // laat winnen van het aantal, toont de app juist de spelling die deze bron niet kent.
        //
        // Via [normKey] en niet met een eigen zeef: die vouwt accenten al plat, haalt de apostrof
        // weg en normaliseert de spaties — precies wat hier nodig is, en het is één begrip van
        // "dezelfde naam" in plaats van twee.
        art = await _zoekArtiestBeeld(name);
        final plat = normKey(name);
        if (art == null && plat.isNotEmpty && plat != name.toLowerCase()) {
          art = await _zoekArtiestBeeld(plat);
        }
        if (art == null) {
          await _onthoudGeenArtiestBeeld(name);
          return null;
        }
        await _artistArtDir.create(recursive: true);
        await meta.writeAsString(jsonEncode(art.toJson()));
        // Wie zojuist gevonden is hoort niet meer op de niet-vragen-lijst te staan.
        final leeg = _artistArtMissFile(name);
        if (await leeg.exists()) await leeg.delete().catchError((_) => leeg);
      } catch (_) {
        return null;
      }
    }
    return art;
  }

  /// Eén zoekopdracht bij TheAudioDB. Null als er niets is — dan probeert de aanroeper het nog
  /// eens met een platgeslagen naam; zie [artistArt].
  Future<ArtistArt?> _zoekArtiestBeeld(String q) async {
    // OP DE RIJ, net als [albumInfo]. Dit was de enige TheAudioDB-aanroeper zónder wachtrij, terwijl
    // `_enrichArtistsFromWeb` er zes tegelijk afvuurt op precies deze host. De meting bij
    // [_audioDbGap] gaat over albums, maar er is geen reden waarom het artiesteneindpunt zich anders
    // gedraagt — en het gevolg is hier erger: een geweigerd antwoord is niet een trage pagina maar
    // een lege.
    await _audioDbSlot();
    final r = await http.get(
      Uri.parse('$kAudioDbBasis/search.php?s=${Uri.encodeComponent(q)}'),
      headers: {'User-Agent': _ua},
    ).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final list =
        (jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true))['artists'] as List?) ?? const [];
    if (list.isEmpty) return null;
    final a = list.first as Map<String, dynamic>;
    String? s(String k) {
      final v = (a[k] as String?)?.trim();
      // `null` als TEKST van vier letters, en dat stuurt deze bron echt — [albumInfo]'s versie van
      // deze functie wacht er al op en die hier niet. Zonder de wacht wordt "null" een URL, gaat de
      // app hem ophalen, krijgt niets terug, en bewaart dat als de achtergrond van de artiest.
      return (v == null || v.isEmpty || v.toLowerCase() == 'null') ? null : v;
    }

    final art = ArtistArt(
      logo: s('strArtistLogo'),
      // Fanart is the wide, cinematic one; the wide thumb is the next best framing.
      backdrop: s('strArtistFanart') ?? s('strArtistWideThumb') ?? s('strArtistBanner'),
      // A proper portrait. A wide backdrop cropped into a banner is a horizontal slice, and
      // where the face lands in it is luck — this is what guarantees you actually see them.
      //
      // De cutout staat hier NIET meer als terugval: hij heeft zijn eigen veld gekregen, want als
      // noodgreep werd hij nooit gekozen. Zie [ArtistArt.heeftVrijstaand].
      thumb: s('strArtistThumb'),
      cutout: s('strArtistCutout'),
      clearart: s('strArtistClearart'),
    );
    return art.isEmpty ? null : art;
  }

  /// De NOMINALE maat die bij een TheAudioDB-beeldsoort hoort.
  ///
  /// **Waarom nominaal en niet gemeten.** TheAudioDB publiceert geen afmetingen, en ze uitlezen zou
  /// betekenen dat je elke foto eerst binnenhaalt voor je weet in welk vak van de kiezer hij hoort.
  /// Tegels zouden dan tussen de vakken springen naarmate ze laden — een venster dat onder je hand
  /// verspringt is erger dan een tegel die er een paar procent naast zit.
  ///
  /// **En het lost een echte fout op.** De kiezer bouwde deze regels als `DiscogsImage(url, url, 0,
  /// 0, false)`, met breedte en hoogte op NUL. `isWide` deelt dan door nul en zegt nee, dus ook een
  /// fanart van 1280×720 werd als staand ingedeeld — precies het beeld dat er als achtergrond hoort
  /// te staan.
  ///
  /// Deze getallen leven alleen in de lijst van dat venster en worden nergens bewaard. Dat is wat
  /// "nominaal" hier eerlijk maakt in plaats van een verzonnen meting: het enige wat ze hoeven te
  /// kloppen is de VORM.
  ///
  /// `backdrop` is er drie in één — `strArtistFanart` (1280×720), `strArtistWideThumb` (1000×562) en
  /// `strArtistBanner` (1000×185) delen dat veld via een `??`-ketting. Alle drie zijn ze liggend, en
  /// meer dan dat hoeft dit getal niet te weten.
  static ({int breedte, int hoogte}) audioDbNominaal(String soort) => switch (soort) {
        'backdrop' => (breedte: 1280, hoogte: 720),
        'clearart' => (breedte: 1000, hoogte: 562),
        'logo' => (breedte: 400, hoogte: 155),
        'thumb' || 'cutout' => (breedte: 1000, hoogte: 1000),
        _ => (breedte: 0, hoogte: 0),
      };

  Directory get _artistArtDir => Directory(_dir('artistart'));
  File _artistArtFile(String name) =>
      File('${_artistArtDir.path}${Platform.pathSeparator}${fnv1a(name.toLowerCase())}.json');

  /// Het briefje "hier hebben we gekeken en niets gevonden".
  ///
  /// **Zonder dit werd een onbekende artiest voor eeuwig opnieuw bevraagd.** Twee mislukte pogingen
  /// (de naam, en de naam met de accenten eraf) schreven niets, dus bij élke pagina-opening gingen er
  /// weer twee verzoeken uit naar een bron die deze act niet kent — en straks doet de voorkiezende
  /// veeg dat er nog eens overheen, voor alle 268 namen, bij elke start.
  ///
  /// Dezelfde vorm en dezelfde [_rememberMiss] van veertien dagen als de hoezenkant
  /// ([searchedAndEmpty]), en om dezelfde reden veertien en niet voorgoed: catalogi krijgen er
  /// beelden bij.
  File _artistArtMissFile(String name) =>
      File('${_artistArtDir.path}${Platform.pathSeparator}${fnv1a(name.toLowerCase())}.none');

  Future<bool> _artiestBeeldGezochtEnLeeg(String name) async {
    try {
      final f = _artistArtMissFile(name);
      if (!await f.exists()) return false;
      if (DateTime.now().difference(await f.lastModified()) <= _rememberMiss) return true;
      await f.delete().catchError((_) => f);
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onthoudGeenArtiestBeeld(String name) async {
    try {
      await _artistArtDir.create(recursive: true);
      await _artistArtMissFile(name).writeAsString('');
    } catch (_) {/* een briefje dat we niet konden schrijven kost één herhaalde zoektocht */}
  }

  Future<Uint8List?> _cachedArt(String name, String kind, String? url) async {
    if (url == null) return null;
    final f = File('${_artistArtDir.path}${Platform.pathSeparator}${fnv1a(name.toLowerCase())}_$kind.img');
    if (await f.exists()) {
      final b = await f.readAsBytes();
      if (b.length > 100) return b;
    }
    final bytes = await _download(url);
    if (bytes == null || bytes.length < 100) return null;
    await _artistArtDir.create(recursive: true);
    await f.writeAsBytes(bytes);
    return bytes;
  }

  /// One TheAudioDB request at a time, spaced out. The same treatment MusicBrainz and Discogs already
  /// get, and it turns out to be just as necessary here.
  ///
  /// Measured on the real library: the background sweep asked for roughly seventy albums in four
  /// minutes and only twenty-two came back with anything. A manual call to the identical URL for one
  /// of the failures — Rihanna / ANTI — returns both the back cover and the disc. So the misses were
  /// the free endpoint pushing back, not data it does not have, and the two scans this whole thread is
  /// about were among the casualties.
  ///
  /// Static, so every CoverEnricher in the process queues behind one line. Spaces the SENDS rather
  /// than holding whole round trips — the lesson the MusicBrainz lane already carries.
  static Future<void> _audioDbTurn = Future<void>.value();
  static DateTime _audioDbLast = DateTime.fromMillisecondsSinceEpoch(0);
  /// Three seconds, and the number came from measuring rather than guessing.
  ///
  /// At 1.2s a sweep of fifty-six records got forty-seven empty answers. Five of those were then asked
  /// for by hand, one at a time: Unapologetic and Loud both came back with a back cover AND a disc, so
  /// the endpoint had the data and was refusing the pace. (The other three genuinely are not in
  /// TheAudioDB — a different problem, and not this one.)
  ///
  /// This runs in the background with all the time in the world; fifty-six records at three seconds is
  /// under three minutes of pacing. Being refused is what costs the user something.
  static const _audioDbGap = Duration(seconds: 3);

  /// Een vraag uit een venster (zie `audiodb.dart`) ging net de deur uit, buiten deze rij om. De
  /// achtergrond houdt daarna weer [_audioDbGap] afstand, zodat de twee samen niet te snel gaan.
  static void meldAudioDbVraag() => _audioDbLast = DateTime.now();

  /// Het GENRE van een artiest volgens TheAudioDB ("Euro Dance", "Pop", "R&B"), of null.
  ///
  /// Voor de radio — zie `radiostijl.dart`. Op dezelfde rij als alles hier, want het is dezelfde
  /// host met dezelfde grens. Een fout gooit door: "geen antwoord" is niet hetzelfde als "geen genre",
  /// en alleen dat laatste mag onthouden worden.
  static Future<String?> audioDbGenre(String artiest) async {
    await _audioDbSlot();
    final r = await http.get(
      Uri.parse('$kAudioDbBasis/search.php?s=${Uri.encodeComponent(artiest)}'),
      headers: {'User-Agent': _ua},
    ).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw HttpException('TheAudioDB gaf ${r.statusCode}');
    final lijst = (jsonBody(r)['artists'] as List?) ?? const [];
    if (lijst.isEmpty) return null;
    final g = ((lijst.first as Map<String, dynamic>)['strGenre'] as String?)?.trim();
    return g == null || g.isEmpty || g.toLowerCase() == 'null' ? null : g;
  }

  /// Een vraag die iemand nu op het scherm wacht (de artiestpagina, Nu speelt): niet achter de hele rij
  /// van de achtergrond. Op de pc stond de bio van een geopende artiest anders minuten achter de
  /// opstartveeg van de hele bibliotheek (18-10-2026: "Over 2 Fabiola" kwam er op de pc niet, op de gsm
  /// meteen).
  ///
  /// En ook niet meer [_audioDbGap] na de vorige vraag, zolang het een kleine reeks blijft — zie
  /// [audioDbVoorrangWacht]. Gemeten op 21-10-2026 op de gsm (▶ KATSEYE — Gabriela): de cd-vraag van Nu
  /// speelt stond twee keer precies 3,1 s te wachten op een vraag die net de deur uit was.
  static Future<void> _audioDbVoorrang() async {
    final wacht = audioDbVoorrangWacht(
        verstuurd: _voorrangVerstuurd, laatste: _audioDbLast, nu: DateTime.now(), afstand: _audioDbGap);
    if (wacht > Duration.zero) await Future<void>.delayed(wacht);
    _audioDbLast = DateTime.now();
    _voorrangVerstuurd.add(_audioDbLast);
  }

  /// Wanneer de vragen met voorrang de deur uit gingen, voor [audioDbVoorrangWacht].
  static final _voorrangVerstuurd = <DateTime>[];

  static Future<void> _audioDbSlot() {
    final slot = _audioDbTurn.then((_) async {
      final since = DateTime.now().difference(_audioDbLast);
      if (since < _audioDbGap) await Future<void>.delayed(_audioDbGap - since);
      _audioDbLast = DateTime.now();
    });
    // The chain must survive a failed turn, or one thrown error deadlocks the lane for the session.
    _audioDbTurn = slot.catchError((_) {});
    return slot;
  }

  /// The sleeve notes for a release: what it is, when, on what label, how it was received —
  /// the album equivalent of a film's synopsis panel.
  ///
  /// [voorrang]: iemand wacht er nu op een scherm op (Nu speelt, de albumpagina) — zie [_audioDbVoorrang].
  Future<AlbumInfo?> albumInfo(String artist, String album, {bool fetch = true, bool voorrang = false}) async {
    final f = _albumInfoFile(artist, album);
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, dynamic>) return AlbumInfo.fromJson(j);
      } catch (_) {/* corrupt cache entry — refetch */}
    }
    if (!fetch) return null;
    // Recent al gezocht en niets gevonden? Dan niet opnieuw staan wachten — zie
    // [albumInfoGezochtEnLeeg]. Dit is het wachten dat op 12-09-2026 zesennegentig keer in één veeg
    // langskwam als "theaudiodb: GEEN ANTWOORD".
    if (await albumInfoGezochtEnLeeg(artist, album)) return null;
    if (_generic.contains(artist.trim().toLowerCase()) || album.trim().isEmpty) return null;
    try {
      // Ask for the record, not for the folder name. Measured: "Talk That Talk (Deluxe)" returns no
      // album at all, while the same request without the suffix finds it — TheAudioDB indexes one
      // entry per record, not per edition. plainTitle is the same stripper the Discogs search uses,
      // so both sides ask the same question.
      final ask = DiscogsService.plainTitle(album);
      await (voorrang ? _audioDbVoorrang() : _audioDbSlot());
      final r = await _haal(
        Uri.parse('$kAudioDbBasis/searchalbum.php'
            '?s=${Uri.encodeComponent(artist)}&a=${Uri.encodeComponent(ask)}'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) {
        await onthoudGeenAlbumInfo(artist, album, stil: true);
        return null;
      }
      // Decode as UTF-8 ourselves: the endpoint doesn't always say so in its headers, and the
      // descriptions are full of accented names.
      final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      final list = (j['album'] as List?) ?? const [];
      if (list.isEmpty) {
        await onthoudGeenAlbumInfo(artist, album);
        return null;
      }
      final a = list.first as Map<String, dynamic>;

      String? s(String k) {
        final v = (a[k] as String?)?.trim();
        return (v == null || v.isEmpty || v.toLowerCase() == 'null') ? null : v;
      }

      final info = AlbumInfo(
        // Dutch when it exists (as the artist bios do), else the English default field.
        description: s('strDescriptionNL') ?? s('strDescription'),
        review: s('strReview'),
        year: int.tryParse(s('intYearReleased') ?? ''),
        genre: s('strGenre'),
        style: s('strStyle'),
        label: s('strLabel'),
        score: double.tryParse(s('intScore') ?? ''),
        // Free, and already in this response. Verified live on Rihanna/ANTI: strAlbumBack and
        // strAlbumCDart both filled. The app has been downloading this JSON on every album page open
        // and dropping these two on the floor, then paying the Discogs budget for the same two scans.
        backUrl: s('strAlbumBack'),
        discUrl: s('strAlbumCDart'),
        frontUrl: s('strAlbumThumb'),
      );
      if (info.isEmpty) {
        await onthoudGeenAlbumInfo(artist, album);
        return null;
      }
      await _albumInfoDir.create(recursive: true);
      await f.writeAsString(jsonEncode(info.toJson()));
      // Wél iets gevonden: het briefje mag weg, anders blijft een oude "niets" nog dagen hangen.
      final leeg = _albumInfoMissFile(artist, album);
      if (await leeg.exists()) await leeg.delete().catchError((_) => leeg);
      return info;
    } catch (_) {
      // Een tijdslimiet of een kapotte verbinding is GEEN antwoord over deze plaat: kort briefje.
      await onthoudGeenAlbumInfo(artist, album, stil: true);
      return null;
    }
  }

  Directory get _albumInfoDir => Directory(_dir('albuminfo'));

  /// The `v2` is a schema marker, and it is load-bearing.
  ///
  /// Nothing in this cache expires. Every entry written before [AlbumInfo.backUrl] and
  /// [AlbumInfo.discUrl] existed came back from disk with both fields null, and the code above then
  /// never asked TheAudioDB again — so the back cover and the disc it does have stayed invisible
  /// forever. Traced on the real library: ANTI warmed with `theaudiodb: achter=false cd=false` while
  /// a live call to the same endpoint returns strAlbumBack AND strAlbumCDart for it.
  ///
  /// Same lesson as the artwork key's version, learned twice in one morning: adding a field to a
  /// cached record does nothing until the old records are re-derived.
  ///
  /// `v3` sinds 20-10-2026: [AlbumInfo.frontUrl] erbij — zelfde les, derde keer.
  File _albumInfoFile(String artist, String album) => File('${_albumInfoDir.path}${Platform.pathSeparator}'
      '${fnv1a('v3|${artist.toLowerCase()}|${album.toLowerCase()}')}.json');

  /// Het briefje "hier gekeken en niets gevonden", voor de albuminfo van TheAudioDB.
  ///
  /// **Waarom dit er moest komen.** Gemeten op 12-09-2026 in `warm.log`: in één veeg over de
  /// bibliotheek stond er zesennegentig keer "theaudiodb: GEEN ANTWOORD". Alleen een GEVONDEN
  /// antwoord werd bewaard, dus elke volgende verversing wachtte opnieuw op dezelfde bron — met een
  /// tijdslimiet van acht seconden en een pauze van drie ertussen. Dat is waar het wachten zat, niet
  /// bij het uitzoeken van de plaat zelf: dat duurde mediaan 84 ms.
  ///
  /// Twee soorten briefjes, want ze zeggen niet hetzelfde. "Die catalogus kent deze plaat niet"
  /// houdt [_rememberMiss] — veertien dagen, net als bij de artiestbeelden, en om dezelfde reden
  /// niet voorgoed: catalogi krijgen er platen bij. "De bron bleef stil" (een tijdslimiet of een
  /// foutcode) zegt niets OVER de plaat, en telt daarom maar een dag.
  File _albumInfoMissFile(String artist, String album) =>
      File('${_albumInfoFile(artist, album).path}.none');

  static const _stilKort = Duration(days: 1);

  /// Waar zolang een recente zoektocht naar deze plaat niets opleverde.
  Future<bool> albumInfoGezochtEnLeeg(String artist, String album) async {
    try {
      final f = _albumInfoMissFile(artist, album);
      if (!await f.exists()) return false;
      final stil = (await f.readAsString()).trim() == 'stil';
      final bewaar = stil ? _stilKort : _rememberMiss;
      if (DateTime.now().difference(await f.lastModified()) <= bewaar) return true;
      await f.delete().catchError((_) => f);
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Schrijf het briefje. [stil] voor "de bron gaf geen antwoord", anders "die kent deze plaat niet".
  Future<void> onthoudGeenAlbumInfo(String artist, String album, {bool stil = false}) async {
    try {
      await _albumInfoDir.create(recursive: true);
      await _albumInfoMissFile(artist, album).writeAsString(stil ? 'stil' : '');
    } catch (_) {/* een briefje dat we niet konden schrijven kost één herhaalde zoektocht */}
  }

  Future<String?> cachedBio(String name) async {
    // Een bestand dat niet te lezen is (op Windows even op slot) is geen bio, en mag de rest van de
    // pagina niet tegenhouden: zonder dit stopte het hele laden van "Over …" bij die ene fout.
    try {
      final f = _bioFile(name);
      if (!await f.exists()) return null;
      final s = (await f.readAsString()).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// "TheAudioDB kent deze artiest niet, of heeft geen bio": zo lang niet opnieuw vragen.
  static const _bioMisDuur = Duration(days: 14);
  File _bioMisFile(String name) =>
      File('${bioDir.path}${Platform.pathSeparator}${fnv1a(name.toLowerCase())}.geen');

  /// Artist biography from TheAudioDB (keyless test key). Prefers Dutch, falls back to English.
  ///
  /// [voorrang] voor wie er nu op wacht (de artiestpagina), zie [_audioDbVoorrang].
  ///
  /// **Een "niets" wordt onthouden** ([_bioMisDuur]). Dat stond nergens, en dus vroeg de opstartveeg
  /// op de pc bij elke start opnieuw naar elke artiest die TheAudioDB niet kent — drie seconden per
  /// stuk, op de rij waar ook de artiestpagina op wacht.
  Future<String?> fetchArtistBio(String name, {bool voorrang = false}) async {
    if (_generic.contains(name.trim().toLowerCase())) return null;
    try {
      final mis = _bioMisFile(name);
      if (await mis.exists() &&
          DateTime.now().difference(await mis.lastModified()) < _bioMisDuur) {
        return null;
      }
    } catch (_) {/* geen briefje te lezen: gewoon vragen */}
    try {
      // Op de rij, om dezelfde reden als in [_zoekArtiestBeeld]: dit is dezelfde URL naar dezelfde
      // host, en `_enrichArtistsFromWeb` roept ze allebei aan voor zes artiesten tegelijk.
      await (voorrang ? _audioDbVoorrang() : _audioDbSlot());
      final r = await http.get(
        Uri.parse('$kAudioDbBasis/search.php?s=${Uri.encodeComponent(name)}'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final artists = (jsonBody(r)['artists'] as List?) ?? const [];
      if (artists.isEmpty) {
        await _onthoudGeenBio(name);
        return null;
      }
      final a = artists.first as Map<String, dynamic>;
      // De feiten liggen HIER al op tafel, in dezelfde rij. Ze wegschrijven kost geen verzoek en
      // geen wachttijd; ze later apart ophalen zou allebei wél kosten. Buiten de bio-tak, want een
      // artiest zonder biografie heeft vaak wél een geboortejaar en een land.
      await _schrijfFeiten(name, ArtiestFeiten.uitAudioDb(a));
      final bio = ((a['strBiographyNL'] ?? a['strBiographyEN']) as String?)?.trim();
      if (bio == null || bio.isEmpty) {
        await _onthoudGeenBio(name);
        return null;
      }
      await bioDir.create(recursive: true);
      await _bioFile(name).writeAsString(bio);
      return bio;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onthoudGeenBio(String name) async {
    try {
      await bioDir.create(recursive: true);
      await _bioMisFile(name).writeAsString('');
    } catch (_) {/* niet te onthouden: dan wordt het later nog eens gevraagd */}
  }

  // ── Feiten ────────────────────────────────────────────────────────────────

  Directory get _feitenDir => Directory(_dir('artistfeiten'));
  File _feitenFile(String name) =>
      File('${_feitenDir.path}${Platform.pathSeparator}${fnv1a(name.toLowerCase())}.json');

  Future<void> _schrijfFeiten(String name, ArtiestFeiten f) async {
    if (f.isEmpty) return;
    try {
      await _feitenDir.create(recursive: true);
      await _feitenFile(name).writeAsString(jsonEncode(f.toJson()));
    } catch (_) {/* een cache die niet geschreven kan worden kost één herhaald verzoek */}
  }

  /// De feiten van deze artiest.
  ///
  /// Ze worden geschreven als bijwerking van [fetchArtistBio], uit dezelfde respons — dus voor elke
  /// artiest die vanaf nu opgehaald wordt kost dit niets.
  ///
  /// **Maar staan ze er niet, dan wordt de bio wél opgehaald, en dat is met opzet.** De eerste
  /// versie las alleen van schijf, met de gedachte "de opstartveeg komt toch langs". GEMETEN op het
  /// scherm op 10-09-2026: bij Michael Jackson bleef de feitenstrook leeg en had het jaarlint geen
  /// geboorte- en sterfjaar. De reden is `_loadBio`, dat `cachedBio` eerst probeert en alleen
  /// ophaalt als die leeg is — en voor de 29 artiesten wier biografie al op schijf stond gebeurde
  /// dat nooit. Die feiten zouden dus voor altijd wegblijven, zonder één melding.
  ///
  /// [fetch] op false is er voor wie alleen wil kijken wat er ligt.
  Future<ArtiestFeiten?> artistFeiten(String name, {bool fetch = true, bool voorrang = false}) async {
    final gelezen = await _leesFeiten(name);
    if (gelezen != null || !fetch) return gelezen;
    // De bio ophalen schrijft de feiten mee. Eén weg naar die URL, en dus geen tweede plek waar
    // een ander antwoord over dezelfde artiest vandaan kan komen.
    await fetchArtistBio(name, voorrang: voorrang);
    return _leesFeiten(name);
  }

  Future<ArtiestFeiten?> _leesFeiten(String name) async {
    try {
      final f = _feitenFile(name);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map<String, dynamic>) return null;
      final feiten = ArtiestFeiten.fromJson(j);
      return (feiten == null || feiten.isEmpty) ? null : feiten;
    } catch (_) {
      return null;
    }
  }

  /// Fetch + cache a cover for [a]; returns the bytes (or null if nothing found).
  /// How long a fruitless search is taken at its word before it is worth asking again.
  ///
  /// Some records genuinely have no cover anywhere — a Soulseek rip of a bootleg, a live set nobody
  /// catalogued. Without a marker, those were searched again on EVERY start: Deezer, then Discogs,
  /// then the Cover Art Archive, one after another, for each of them, forever. Measured here: 23 of
  /// 136 albums found nothing, so that is 23 albums times three services of pure waiting, every
  /// single time the app opened.
  ///
  /// Two weeks rather than forever, because catalogues do gain artwork.
  static const _rememberMiss = Duration(days: 14);

  File _missFile(Album a) => File('${cacheDir.path}${Platform.pathSeparator}${keyFor(a)}.none');

  /// Has this album been searched recently and come up empty?
  Future<bool> searchedAndEmpty(Album a) async {
    try {
      final f = _missFile(a);
      if (!await f.exists()) return false;
      if (DateTime.now().difference(await f.lastModified()) <= _rememberMiss) return true;
      await f.delete().catchError((_) => f);
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> fetchAndCache(Album a) async {
    final bytes = await _find(a.artist, a.title);
    try {
      await cacheDir.create(recursive: true);
      if (bytes != null) {
        await _cacheFile(a).writeAsBytes(bytes);
        // A record that has just been found must not stay on the do-not-ask list.
        final miss = _missFile(a);
        if (await miss.exists()) await miss.delete().catchError((_) => miss);
      } else {
        // Nothing found. Write that down, or the next start repeats the whole chain.
        await _missFile(a).writeAsString('');
      }
    } catch (_) {/* a note we could not write only costs one repeated search */}
    return bytes;
  }

  Future<Uint8List?> _find(String artistRaw, String albumRaw) async {
    final album = _cleanAlbum(albumRaw);
    if (album.isEmpty || album.toLowerCase() == 'flac music 2024') return null;
    final artist = _cleanArtist(artistRaw);
    final generic = _generic.contains(artist.trim().toLowerCase());
    final query = generic ? album : '$artist $album';

    final deezer = await _deezerCover(query, artist: artist, album: album, generiek: generic);
    if (deezer != null) {
      // Op 1200, en de 1000 van `cover_xl` als die maat er niet is — zie [deezerHoes1200].
      final groot = deezerHoes1200(deezer);
      final b = (groot == deezer ? null : await _download(groot)) ?? await _download(deezer);
      if (b != null) return b;
    }
    // TheAudioDB's 700 voor wat Deezer niet heeft — vóór Discogs (~600) en het archief.
    if (!generic) {
      final u = (await albumInfo(artist, album))?.frontUrl;
      if (u != null) {
        final b = await _download(u);
        if (b != null) return b;
      }
    }
    if (settings.discogsToken.isNotEmpty) {
      final dc = await _discogsCover(artist, album, generic);
      if (dc != null) {
        final b = await _download(dc);
        if (b != null) return b;
      }
    }
    return await _musicbrainzCover(generic ? '' : artist, album);
  }

  Future<String?> _deezerCover(String query,
      {required String artist, required String album, required bool generiek}) async {
    try {
      // Via de gedeelde rijbaan, zoals [fetchArtistImage]: het verrijken vraagt zes hoezen tegelijk.
      // Tien treffers en de juiste eruit ([kiesDigitaalAlbum]) — niet blind de eerste.
      final j = await DeezerBaan.haal(
          'https://api.deezer.com/search/album?q=${Uri.encodeComponent(query)}&limit=10');
      final a = kiesDigitaalAlbum((j?['data'] as List?) ?? const [], artist, album, generiek: generiek);
      if (a == null) return null;
      final url = (a['cover_xl'] ?? a['cover_big']) as String?;
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _discogsCover(String artist, String album, bool generic) async {
    // Through DiscogsService, which owns the token's budget and the disk cache. This used to call
    // api.discogs.com with a bare http.get: invisible to that budget, and nothing remembered between
    // starts. Harmless while covers were fetched one at a time; a burst now that six are enriched at
    // once, and the token pays for it.
    try {
      return await DiscogsService(settings).coverFromSearch(artist, album, generic: generic);
    } catch (_) {
      return null;
    }
  }

  /// De hoes uit het Cover Art Archive, via de dienst en niet eromheen.
  ///
  /// **Twee fouten zaten hier in één functie, en ze versterkten elkaar.**
  ///
  /// De eerste: dit was de enige plek in de app die `musicbrainz.org/ws/2` met een kale `http.get`
  /// aanriep, buiten [MusicBrainzService] om. Die dienst houdt een wachtrij van 1,1 seconde bij
  /// omdat MusicBrainz één verzoek per seconde vraagt en daarboven 503 antwoordt — en die wachtrij
  /// is `static` juist omdat het budget van de SERVER is, niet van een object. Deze aanroep stond
  /// buiten die rij, en verrijken doet zes albums tegelijk. Zes verzoeken per tel op een dienst die
  /// er één wil: de eerste kwam door, de rest kreeg 503.
  ///
  /// De tweede: `catch (_) {}` eronder. Een 503 werd dus niet eens een 503 — hij werd niets. Geen
  /// hoes, geen melding, geen spoor. Dat is precies de klacht "soms zie ik de juiste afbeelding
  /// niet": hij is er wel, er is alleen te snel om gevraagd.
  ///
  /// En passant vervalt `front-500`. [MbImage.full] is de 1200 van het archief, met het origineel
  /// als terugval — de maat die de keuzelijst al jaren gebruikt en waarvan de reden bij [MbImage]
  /// nagemeten staat. 500 was zichtbaar zacht zodra een hoes een scherm vult.
  Future<Uint8List?> _musicbrainzCover(String artist, String album) async {
    try {
      final mb = MusicBrainzService();
      // Drie persingen, want de eerste heeft lang niet altijd scans. Meer is zonde: elk kost een
      // beurt op de wachtrij van één per seconde.
      final hits = await mb.searchReleases(artist, album, max: 3);
      for (final r in hits.take(3)) {
        if (r.mbid.isEmpty) continue;
        // Het archief zegt zelf wat elke scan is. Alleen de VOORKANT mag hier landen: zonder die
        // controle werd de eerste de beste scan de hoes, en dat is net zo goed het boekje of de
        // achterkant.
        final images = await mb.art(r.mbid);
        for (final i in images) {
          if (!i.isFront) continue;
          final b = await _download(i.full);
          if (b != null) return b;
        }
      }
    } catch (_) {/* een hoes is een verrijking; hij mag ontbreken, niets mag erop stuklopen */}
    return null;
  }

  Future<Uint8List?> _download(String url) async {
    try {
      final r = await http.get(Uri.parse(url), headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200 && r.bodyBytes.length > 1500 && _isImage(r.bodyBytes)) {
        return r.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  bool _isImage(Uint8List b) {
    if (b.length < 12) return false;
    final jpg = b[0] == 0xFF && b[1] == 0xD8;
    final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final gif = b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46;
    final webp = b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45;
    return jpg || png || gif || webp;
  }

  String _cleanAlbum(String s) =>
      s.replaceAll(_albumJunk, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim().replaceAll(RegExp(r'^[\s\-_.]+|[\s\-_.]+$'), '');
  String _cleanArtist(String s) => s.replaceAll(_featRe, '').trim();
}
