import 'dart:convert';
import 'package:http/http.dart' as http;

import 'settings.dart';

/// One candidate release/track from a metadata provider — used by the manual
/// "correct metadata" editor to fix a wrong cover/artist/title.
class MetaResult {
  final String title; // track title (single) or album title
  final String artist;
  final String album;
  final String? coverUrl;
  const MetaResult({required this.title, required this.artist, required this.album, this.coverUrl});
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
        out.add(MetaResult(
          title: album,
          artist: artist,
          album: album,
          coverUrl: (cover != null && cover.isNotEmpty && !cover.contains('spacer')) ? cover : null,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<MetaResult>> _musicbrainz(String query) async {
    try {
      final r = await http.get(
        Uri.parse('https://musicbrainz.org/ws/2/release/?query=${Uri.encodeComponent(query)}&fmt=json&limit=12'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return [];
      final releases = (jsonDecode(r.body)['releases'] as List?) ?? const [];
      final out = <MetaResult>[];
      for (final e in releases) {
        final id = e['id'] as String?;
        final title = (e['title'] ?? '') as String;
        final credit = (e['artist-credit'] as List?) ?? const [];
        final artist = credit.isNotEmpty
            ? ((credit.first['name'] ?? credit.first['artist']?['name'] ?? '') as String)
            : '';
        out.add(MetaResult(
          title: title,
          artist: artist,
          album: title,
          coverUrl: id != null ? 'https://coverartarchive.org/release/$id/front-500' : null,
        ));
      }
      return out.where((m) => m.title.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }
}
