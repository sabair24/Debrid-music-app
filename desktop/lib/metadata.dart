import 'dart:convert';
import 'package:http/http.dart' as http;

import 'musicbrainz.dart';
import 'settings.dart';

/// One candidate release/track from a metadata provider — used by the manual
/// "correct metadata" editor to fix a wrong cover/artist/title.
class MetaResult {
  final String title; // track title (single) or album title
  final String artist;
  final String album;
  final String? coverUrl;

  /// The Discogs release this candidate IS, when it came from Discogs. Picking a release in the
  /// editor used to change only the name and the front cover — the app then went off and chose its
  /// own edition for everything else, so the back cover and the disc never followed.
  final int? releaseId;

  /// The MusicBrainz release this candidate IS, when it came from there. Kept separately from
  /// [releaseId] rather than replacing it: an MBID is a string and a Discogs id is a number, and
  /// pins already written to disk as numbers have to keep working.
  final String? mbid;

  /// What this pressing IS, in one line: "CD · Europe · 19439937972 · 2021". Five results reading
  /// "30 — Adele" and nothing else give you nothing to choose between.
  final String? detail;
  const MetaResult({
    required this.title,
    required this.artist,
    required this.album,
    this.coverUrl,
    this.releaseId,
    this.mbid,
    this.detail,
  });
}

/// Searches Deezer / Discogs / MusicBrainz for correct metadata + cover art.
class MetadataSearch {
  final AppSettings settings;
  MetadataSearch(this.settings);

  static const _ua = 'DebridMusic/0.1 ( https://github.com/sabair24/Debrid-music-app )';

  static const providers = ['Deezer', 'Discogs', 'MusicBrainz'];

  /// [track] true searches individual tracks (for a single), false searches albums.
  Future<List<MetaResult>> search(String provider, String query, {bool track = false}) async {
    if (query.trim().isEmpty) return [];
    switch (provider) {
      case 'Discogs':
        return _discogs(query);
      case 'MusicBrainz':
        return _musicbrainz(query);
      default:
        return _deezer(query, track);
    }
  }

  Future<List<MetaResult>> _deezer(String query, bool track) async {
    final path = track ? 'search' : 'search/album';
    try {
      final r = await http
          .get(Uri.parse('https://api.deezer.com/$path?q=${Uri.encodeComponent(query)}&limit=12'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return [];
      final data = (jsonDecode(r.body)['data'] as List?) ?? const [];
      final out = <MetaResult>[];
      for (final e in data) {
        if (track) {
          final al = e['album'] as Map<String, dynamic>?;
          out.add(MetaResult(
            title: (e['title'] ?? '') as String,
            artist: (e['artist']?['name'] ?? '') as String,
            album: (al?['title'] ?? '') as String,
            coverUrl: (al?['cover_xl'] ?? al?['cover_big']) as String?,
          ));
        } else {
          out.add(MetaResult(
            title: (e['title'] ?? '') as String,
            artist: (e['artist']?['name'] ?? '') as String,
            album: (e['title'] ?? '') as String,
            coverUrl: (e['cover_xl'] ?? e['cover_big']) as String?,
          ));
        }
      }
      return out.where((m) => m.title.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MetaResult>> _discogs(String query) async {
    if (settings.discogsToken.isEmpty) return [];
    try {
      final tok = Uri.encodeComponent(settings.discogsToken);
      final r = await http.get(
        Uri.parse('https://api.discogs.com/database/search?type=release&token=$tok&q=${Uri.encodeComponent(query)}&per_page=12'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return [];
      final results = (jsonDecode(r.body)['results'] as List?) ?? const [];
      final out = <MetaResult>[];
      for (final e in results) {
        final ttl = (e['title'] ?? '') as String; // usually "Artist - Album"
        var artist = '', album = ttl;
        final dash = ttl.indexOf(' - ');
        if (dash > 0) {
          artist = ttl.substring(0, dash).trim();
          album = ttl.substring(dash + 3).trim();
        }
        final cover = (e['cover_image'] ?? e['thumb']) as String?;
        // Format first, because it is the thing worth choosing on: a CD carries a catalogue number
        // and a country, a digital entry usually carries neither.
        final formats = [for (final f in (e['format'] as List? ?? const [])) f.toString()];
        final bits = <String>[
          if (formats.isNotEmpty) formats.first,
          if ((e['country'] as String?)?.isNotEmpty ?? false) e['country'] as String,
          if ((e['catno'] as String?)?.isNotEmpty ?? false) e['catno'] as String,
          if ((e['year'] as String?)?.isNotEmpty ?? false) e['year'] as String,
        ];
        out.add(MetaResult(
          title: album,
          artist: artist,
          album: album,
          coverUrl: (cover != null && cover.isNotEmpty && !cover.contains('spacer')) ? cover : null,
          releaseId: (e['id'] as num?)?.toInt(),
          detail: bits.isEmpty ? null : bits.join(' · '),
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Every pressing MusicBrainz knows, CD first, each saying what it is.
  ///
  /// This used to return bare titles: five rows reading "30 — Adele" with nothing to choose
  /// between, and picking one changed the album's name and nothing else. The pressing is now
  /// described the same way a Discogs row is, and its MBID travels with it so the choice can
  /// actually be pinned.
  Future<List<MetaResult>> _musicbrainz(String query) async {
    try {
      final mb = MusicBrainzService();
      // The query MUST be scoped to an artist. Unscoped, MusicBrainz matches the whole string as
      // one phrase against the release title, so "Daft Punk Discovery" finds two SM64-soundfont
      // parodies and nothing else — it has no popularity signal to rescue a bad match. Split on
      // "Artist - Album" first, then fall back to resolving the leading words as an artist.
      var artist = '', album = query.trim();
      final dash = query.indexOf(' - ');
      if (dash > 0) {
        artist = query.substring(0, dash).trim();
        album = query.substring(dash + 3).trim();
      } else {
        final words = query.trim().split(RegExp(r'\s+'));
        // Try the longest leading run of words that names a real artist, shortest search first.
        for (var take = words.length - 1; take >= 1; take--) {
          final cand = words.take(take).join(' ');
          final a = await mb.resolveArtist(cand);
          if (a != null && a.name.toLowerCase() == cand.toLowerCase()) {
            artist = a.name;
            album = words.skip(take).join(' ');
            break;
          }
        }
      }
      final hits = await mb.searchReleases(artist, album.isEmpty ? query.trim() : album, max: 25);
      return [
        for (final r in hits)
          if (r.title.isNotEmpty)
            MetaResult(
              title: r.title,
              artist: r.artist,
              album: r.title,
              // The archive answers 404 for a pressing with no scans, which the image widget shows
              // as an empty box — honest, and the row is still choosable on its edition line.
              coverUrl: 'https://coverartarchive.org/release/${r.mbid}/front-500',
              mbid: r.mbid,
              detail: r.line.isEmpty ? null : r.line,
            )
      ];
    } catch (_) {
      return [];
    }
  }
}
