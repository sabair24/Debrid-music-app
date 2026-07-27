import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'discogs.dart';
import 'models.dart';
import 'settings.dart';
import 'paths.dart';

/// A wide backdrop and the act's official wordmark — what turns an artist page into a banner.
class ArtistArt {
  final String? logo, backdrop, thumb;
  final Uint8List? logoBytes, backdropBytes, thumbBytes;
  const ArtistArt({
    this.logo,
    this.backdrop,
    this.thumb,
    this.logoBytes,
    this.backdropBytes,
    this.thumbBytes,
  });

  bool get isEmpty => logo == null && backdrop == null && thumb == null;

  /// Bumped whenever a new field is added, so entries cached by an older build are refetched
  /// instead of answering forever with a null they never had a chance to fill. Adding `thumb`
  /// without this meant every artist you'd already opened kept showing the old fallback.
  static const schema = 2;

  Map<String, dynamic> toJson() => {'v': schema, 'logo': logo, 'backdrop': backdrop, 'thumb': thumb};

  /// Null for an entry written by an older build — the caller refetches.
  static ArtistArt? fromJson(Map<String, dynamic> j) {
    if ((j['v'] as int?) != schema) return null;
    return ArtistArt(
      logo: j['logo'] as String?,
      backdrop: j['backdrop'] as String?,
      thumb: j['thumb'] as String?,
    );
  }
}

/// What a release IS — the text and facts that make an album page read like a film page
/// instead of a bare track list.
class AlbumInfo {
  final String? description, review, genre, style, label;
  final int? year;
  final double? score;
  const AlbumInfo({this.description, this.review, this.year, this.genre, this.style, this.label, this.score});

  bool get isEmpty =>
      (description == null || description!.isEmpty) &&
      (review == null || review!.isEmpty) &&
      year == null &&
      genre == null &&
      label == null;

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
      };

  factory AlbumInfo.fromJson(Map<String, dynamic> j) => AlbumInfo(
        description: j['description'] as String?,
        review: j['review'] as String?,
        year: j['year'] as int?,
        genre: j['genre'] as String?,
        style: j['style'] as String?,
        label: j['label'] as String?,
        score: (j['score'] as num?)?.toDouble(),
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

  // Stable FNV-1a hash (Dart's String.hashCode is randomized per run, so it can't
  // be used for a persistent on-disk cache key).
  static String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  String keyFor(Album a) => _fnv('${a.artist.toLowerCase()}|${a.title.toLowerCase()}');
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
    final from = _fnv('${oldArtist.toLowerCase()}|${oldTitle.toLowerCase()}');
    final to = _fnv('${newArtist.toLowerCase()}|${newTitle.toLowerCase()}');
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
  File _artistFile(String name) => File('${artistDir.path}${Platform.pathSeparator}${_fnv(name.toLowerCase())}.jpg');
  File _bioFile(String name) => File('${bioDir.path}${Platform.pathSeparator}${_fnv(name.toLowerCase())}.txt');

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
      final data = (jsonDecode(r.body)['data'] as List?) ?? const [];
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
  Future<ArtistArt?> artistArt(String name) async {
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
      try {
        final r = await http.get(
          Uri.parse('https://theaudiodb.com/api/v1/json/2/search.php?s=${Uri.encodeComponent(name)}'),
          headers: {'User-Agent': _ua},
        ).timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) return null;
        final list = (jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true))['artists'] as List?) ?? const [];
        if (list.isEmpty) return null;
        final a = list.first as Map<String, dynamic>;
        String? s(String k) {
          final v = (a[k] as String?)?.trim();
          return (v == null || v.isEmpty) ? null : v;
        }

        art = ArtistArt(
          logo: s('strArtistLogo'),
          // Fanart is the wide, cinematic one; the wide thumb is the next best framing.
          backdrop: s('strArtistFanart') ?? s('strArtistWideThumb') ?? s('strArtistBanner'),
          // A proper portrait. A wide backdrop cropped into a banner is a horizontal slice, and
          // where the face lands in it is luck — this is what guarantees you actually see them.
          thumb: s('strArtistThumb') ?? s('strArtistCutout'),
        );
        if (art.isEmpty) return null;
        await _artistArtDir.create(recursive: true);
        await meta.writeAsString(jsonEncode(art.toJson()));
      } catch (_) {
        return null;
      }
    }
    // Keep the bytes locally too: these render on every visit and shouldn't refetch each time.
    final logo = await _cachedArt(name, 'logo', art.logo);
    final backdrop = await _cachedArt(name, 'backdrop', art.backdrop);
    final thumb = await _cachedArt(name, 'thumb', art.thumb);
    return ArtistArt(
      logo: art.logo,
      backdrop: art.backdrop,
      thumb: art.thumb,
      logoBytes: logo,
      backdropBytes: backdrop,
      thumbBytes: thumb,
    );
  }

  Directory get _artistArtDir => Directory(_dir('artistart'));
  File _artistArtFile(String name) =>
      File('${_artistArtDir.path}${Platform.pathSeparator}${_fnv(name.toLowerCase())}.json');

  Future<Uint8List?> _cachedArt(String name, String kind, String? url) async {
    if (url == null) return null;
    final f = File('${_artistArtDir.path}${Platform.pathSeparator}${_fnv(name.toLowerCase())}_$kind.img');
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
      final r = await http.get(
        Uri.parse('https://theaudiodb.com/api/v1/json/2/searchalbum.php'
            '?s=${Uri.encodeComponent(artist)}&a=${Uri.encodeComponent(album)}'),
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
  File _albumInfoFile(String artist, String album) => File('${_albumInfoDir.path}${Platform.pathSeparator}'
      '${_fnv('${artist.toLowerCase()}|${album.toLowerCase()}')}.json');

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
      final r = await http.get(
        Uri.parse('https://theaudiodb.com/api/v1/json/2/search.php?s=${Uri.encodeComponent(name)}'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final artists = (jsonDecode(r.body)['artists'] as List?) ?? const [];
      if (artists.isEmpty) return null;
      final a = artists.first as Map<String, dynamic>;
      final bio = ((a['strBiographyNL'] ?? a['strBiographyEN']) as String?)?.trim();
      if (bio == null || bio.isEmpty) return null;
      await bioDir.create(recursive: true);
      await _bioFile(name).writeAsString(bio);
      return bio;
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
      final data = (jsonDecode(r.body)['data'] as List?) ?? const [];
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

  Future<Uint8List?> _musicbrainzCover(String artist, String album) async {
    try {
      var q = 'release:"$album"';
      if (artist.isNotEmpty) q += ' AND artist:"$artist"';
      final r = await http.get(
        Uri.parse('https://musicbrainz.org/ws/2/release/?query=${Uri.encodeComponent(q)}&fmt=json&limit=3'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final releases = (jsonDecode(r.body)['releases'] as List?) ?? const [];
      for (final rel in releases.take(3)) {
        final id = rel['id'] as String?;
        if (id == null) continue;
        final b = await _download('https://coverartarchive.org/release/$id/front-500');
        if (b != null) return b;
      }
    } catch (_) {}
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
