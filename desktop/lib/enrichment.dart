import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'cachesleutel.dart';
import 'json_body.dart';
import 'discogs.dart';
import 'models.dart';
import 'musicbrainz.dart';
import 'organize.dart' show normKey;
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

  /// "1958 – 2009", "sinds 1993", "1993 – 2011" — of null als er niets te zeggen valt.
  ///
  /// Het jaar van oprichting gaat voor het geboortejaar: bij een BAND is dat het jaar dat telt, en
  /// bij een persoon staat er geen oprichtingsjaar.
  String? get actief {
    final van = opgerichtJaar ?? geborenJaar;
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
      geborenJaar: (j['gj'] as num?)?.toInt(),
      gestorvenJaar: (j['sj'] as num?)?.toInt(),
      opgerichtJaar: (j['oj'] as num?)?.toInt(),
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
      geborenJaar: n('intBornYear'),
      gestorvenJaar: n('intDiedYear'),
      opgerichtJaar: n('intFormedYear'),
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
  });

  bool get isEmpty =>
      (description == null || description!.isEmpty) &&
      (review == null || review!.isEmpty) &&
      year == null &&
      genre == null &&
      label == null &&
      backUrl == null &&
      discUrl == null;

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
      );
}

/// Fetches missing album covers from Deezer → Discogs → MusicBrainz/CoverArtArchive
/// and caches them on disk. Ported from the server's enrichment logic.
class CoverEnricher {
  final AppSettings settings;
  CoverEnricher(this.settings);

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

  /// Fetch + cache an artist photo from Deezer (keyless).
  Future<Uint8List?> fetchArtistImage(String name) async {
    if (_generic.contains(name.trim().toLowerCase())) return null;
    try {
      final r = await http
          .get(Uri.parse('https://api.deezer.com/search/artist?q=${Uri.encodeComponent(name)}&limit=1'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final data = (jsonBody(r)['data'] as List?) ?? const [];
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
    final loopt = _artistArtInFlight[sleutel];
    if (loopt != null) return loopt;
    // Een BLOKlichaam, en dat is geen stijlkwestie. Zie `discogs.dart:838-848`: met een pijl
    // (`() => map.remove(k)`) geeft de opruimer terug wát `remove()` teruggeeft — op een
    // `Map<String, Future<…>>` is dat de verwijderde Future zélf, en `whenComplete` wacht dan op het
    // werk dat het net afrondde. Voor altijd, zonder socket, zonder logregel. Die fout kostte daar
    // zes herschrijvingen; hier staat hij één keer opgeschreven en niet nog eens gemaakt.
    final werk = _artistArtVers(name).whenComplete(() {
      _artistArtInFlight.remove(sleutel);
    });
    _artistArtInFlight[sleutel] = werk;
    return werk;
  }

  /// Wie tegelijk om dezelfde naam vraagt, wacht op hetzelfde antwoord.
  ///
  /// **Vijf aanroepers bij één pagina-opening**: de vervaagde wash achter de pagina, de editoriale
  /// kop, de personenkop, de artiestpagina zelf en de fotokiezer. Zonder deze tabel zijn dat vijf
  /// zoekopdrachten naar dezelfde artiest, tegelijk, op een bron die al terugduwt — en dan is het
  /// niet de traagheid maar de leegte die je ziet. `DiscogsArtwork.releaseArt` heeft deze tabel al;
  /// dit is dezelfde, voor de andere helft van hetzelfde scherm.
  static final _artistArtInFlight = <String, Future<ArtistArt?>>{};

  Future<ArtistArt?> _artistArtVers(String name) async {
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
      Uri.parse('https://theaudiodb.com/api/v1/json/2/search.php?s=${Uri.encodeComponent(q)}'),
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
  Future<AlbumInfo?> albumInfo(String artist, String album, {bool fetch = true}) async {
    final f = _albumInfoFile(artist, album);
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, dynamic>) return AlbumInfo.fromJson(j);
      } catch (_) {/* corrupt cache entry — refetch */}
    }
    if (!fetch) return null;
    if (_generic.contains(artist.trim().toLowerCase()) || album.trim().isEmpty) return null;
    try {
      // Ask for the record, not for the folder name. Measured: "Talk That Talk (Deluxe)" returns no
      // album at all, while the same request without the suffix finds it — TheAudioDB indexes one
      // entry per record, not per edition. plainTitle is the same stripper the Discogs search uses,
      // so both sides ask the same question.
      final ask = DiscogsService.plainTitle(album);
      await _audioDbSlot();
      final r = await http.get(
        Uri.parse('https://theaudiodb.com/api/v1/json/2/searchalbum.php'
            '?s=${Uri.encodeComponent(artist)}&a=${Uri.encodeComponent(ask)}'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      // Decode as UTF-8 ourselves: the endpoint doesn't always say so in its headers, and the
      // descriptions are full of accented names.
      final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      final list = (j['album'] as List?) ?? const [];
      if (list.isEmpty) return null;
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
      );
      if (info.isEmpty) return null;
      await _albumInfoDir.create(recursive: true);
      await f.writeAsString(jsonEncode(info.toJson()));
      return info;
    } catch (_) {
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
  File _albumInfoFile(String artist, String album) => File('${_albumInfoDir.path}${Platform.pathSeparator}'
      '${fnv1a('v2|${artist.toLowerCase()}|${album.toLowerCase()}')}.json');

  Future<String?> cachedBio(String name) async {
    final f = _bioFile(name);
    if (!await f.exists()) return null;
    final s = (await f.readAsString()).trim();
    return s.isEmpty ? null : s;
  }

  /// Artist biography from TheAudioDB (keyless test key). Prefers Dutch, falls back to English.
  Future<String?> fetchArtistBio(String name) async {
    if (_generic.contains(name.trim().toLowerCase())) return null;
    try {
      // Op de rij, om dezelfde reden als in [_zoekArtiestBeeld]: dit is dezelfde URL naar dezelfde
      // host, en `_enrichArtistsFromWeb` roept ze allebei aan voor zes artiesten tegelijk.
      await _audioDbSlot();
      final r = await http.get(
        Uri.parse('https://theaudiodb.com/api/v1/json/2/search.php?s=${Uri.encodeComponent(name)}'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final artists = (jsonBody(r)['artists'] as List?) ?? const [];
      if (artists.isEmpty) return null;
      final a = artists.first as Map<String, dynamic>;
      // De feiten liggen HIER al op tafel, in dezelfde rij. Ze wegschrijven kost geen verzoek en
      // geen wachttijd; ze later apart ophalen zou allebei wél kosten. Buiten de bio-tak, want een
      // artiest zonder biografie heeft vaak wél een geboortejaar en een land.
      await _schrijfFeiten(name, ArtiestFeiten.uitAudioDb(a));
      final bio = ((a['strBiographyNL'] ?? a['strBiographyEN']) as String?)?.trim();
      if (bio == null || bio.isEmpty) return null;
      await bioDir.create(recursive: true);
      await _bioFile(name).writeAsString(bio);
      return bio;
    } catch (_) {
      return null;
    }
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

  /// De feiten van deze artiest, van schijf.
  ///
  /// **Alleen lezen.** Ze worden geschreven als bijwerking van [fetchArtistBio], die bij elke
  /// artiest toch al langskomt via de opstartveeg. Hier zelf gaan ophalen zou een tweede weg naar
  /// dezelfde URL zijn, en dan is er geen plek meer waar één antwoord over dezelfde artiest staat.
  ///
  /// Gevolg dat je moet weten: voor de artiesten waarvan de biografie al vóór vandaag op schijf
  /// stond komen deze feiten pas binnen als die bio een keer ververst wordt. Dat is de prijs van
  /// nul extra verzoeken, en het scherm hoort er tegen te kunnen — zie [ArtiestFeiten.isEmpty].
  Future<ArtiestFeiten?> artistFeiten(String name) async {
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

    final deezer = await _deezerCover(query);
    if (deezer != null) {
      final b = await _download(deezer);
      if (b != null) return b;
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

  Future<String?> _deezerCover(String query) async {
    try {
      final r = await http
          .get(Uri.parse('https://api.deezer.com/search/album?q=${Uri.encodeComponent(query)}&limit=1'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final data = (jsonBody(r)['data'] as List?) ?? const [];
      if (data.isEmpty) return null;
      final a = data.first as Map<String, dynamic>;
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
