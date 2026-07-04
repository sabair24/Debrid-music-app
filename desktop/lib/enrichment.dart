import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'settings.dart';

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
    final base = Platform.environment['APPDATA'] ?? Directory.current.path;
    final sep = Platform.pathSeparator;
    return '$base${sep}DebridMusic$sep$name';
  }

  Directory get cacheDir => Directory(_dir('covers'));
  Directory get artistDir => Directory(_dir('artists'));
  Directory get bioDir => Directory(_dir('bios'));

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
  File _artistFile(String name) => File('${artistDir.path}${Platform.pathSeparator}${_fnv(name.toLowerCase())}.jpg');
  File _bioFile(String name) => File('${bioDir.path}${Platform.pathSeparator}${_fnv(name.toLowerCase())}.txt');

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
      if (url == null || url.isEmpty) return null;
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
  Future<Uint8List?> fetchAndCache(Album a) async {
    final bytes = await _find(a.artist, a.title);
    if (bytes != null) {
      await cacheDir.create(recursive: true);
      await _cacheFile(a).writeAsBytes(bytes);
    }
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
    Future<String?> search(String url) async {
      try {
        final r = await http.get(Uri.parse(url), headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) return null;
        final results = (jsonDecode(r.body)['results'] as List?) ?? const [];
        for (final it in results) {
          final ci = (it['cover_image'] ?? it['thumb']) as String?;
          if (ci != null && ci.isNotEmpty && !ci.contains('spacer')) return ci;
        }
      } catch (_) {}
      return null;
    }

    final tok = Uri.encodeComponent(settings.discogsToken);
    final strict = StringBuffer('https://api.discogs.com/database/search?type=release&token=$tok&release_title=${Uri.encodeComponent(album)}');
    if (!generic && artist.isNotEmpty) strict.write('&artist=${Uri.encodeComponent(artist)}');
    final s = await search(strict.toString());
    if (s != null) return s;
    final q = generic ? album : '$artist $album';
    return search('https://api.discogs.com/database/search?type=release&token=$tok&q=${Uri.encodeComponent(q)}');
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
