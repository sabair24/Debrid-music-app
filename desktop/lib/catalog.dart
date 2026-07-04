import 'dart:convert';
import 'package:http/http.dart' as http;

/// Deezer catalog (keyless) — powers the Stremio-style browse:
/// search artist → their albums → an album's tracks. Sources (torrents/Soulseek)
/// are then searched per track/album via the existing OnlineService/SoulseekService.
class CatalogArtist {
  final int id;
  final String name;
  final String? picture;
  final int albumCount;
  const CatalogArtist(this.id, this.name, this.picture, this.albumCount);
}

class CatalogAlbum {
  final int id;
  final String title;
  final String? cover;
  final String? releaseDate;
  final int trackCount;
  final String recordType; // album | single | ep | compile
  const CatalogAlbum(this.id, this.title, this.cover, this.releaseDate, this.trackCount, this.recordType);

  String? get year => (releaseDate != null && releaseDate!.length >= 4) ? releaseDate!.substring(0, 4) : null;
  bool get isSingle => recordType == 'single';
}

class CatalogTrack {
  final int id;
  final String title;
  final String artist;
  final int durationSec;
  final int position;
  const CatalogTrack(this.id, this.title, this.artist, this.durationSec, this.position);

  String get durationLabel {
    final m = durationSec ~/ 60, s = durationSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class CatalogService {
  static const _base = 'https://api.deezer.com';

  Future<Map<String, dynamic>?> _get(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<CatalogArtist>> searchArtists(String q) async {
    final j = await _get('$_base/search/artist?q=${Uri.encodeComponent(q)}&limit=25');
    final data = (j?['data'] as List?) ?? const [];
    return data
        .map((a) => CatalogArtist(
              a['id'] as int,
              (a['name'] ?? '') as String,
              (a['picture_big'] ?? a['picture_medium']) as String?,
              (a['nb_album'] ?? 0) as int,
            ))
        .where((a) => a.name.isNotEmpty)
        .toList();
  }

  Future<List<CatalogAlbum>> artistAlbums(int artistId) async {
    final j = await _get('$_base/artist/$artistId/albums?limit=100');
    final data = (j?['data'] as List?) ?? const [];
    final albums = data.map(_album).toList();
    // De-dupe by title (Deezer lists many re-releases), keep the newest, sort newest-first.
    final byTitle = <String, CatalogAlbum>{};
    for (final a in albums) {
      final k = a.title.toLowerCase();
      final cur = byTitle[k];
      if (cur == null || (a.releaseDate ?? '').compareTo(cur.releaseDate ?? '') > 0) byTitle[k] = a;
    }
    final out = byTitle.values.toList()
      ..sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
    return out;
  }

  /// The album (with cover) + its ordered tracklist.
  Future<(CatalogAlbum?, List<CatalogTrack>)> albumTracks(int albumId) async {
    final j = await _get('$_base/album/$albumId');
    if (j == null) return (null, const <CatalogTrack>[]);
    final album = _album(j);
    final artistName = (j['artist']?['name'] ?? '') as String;
    final td = ((j['tracks']?['data']) as List?) ?? const [];
    final tracks = td
        .map((t) => CatalogTrack(
              t['id'] as int,
              (t['title'] ?? '') as String,
              ((t['artist']?['name']) ?? artistName) as String,
              (t['duration'] ?? 0) as int,
              (t['track_position'] ?? 0) as int,
            ))
        .toList();
    return (album, tracks);
  }

  CatalogAlbum _album(dynamic a) => CatalogAlbum(
        a['id'] as int,
        (a['title'] ?? '') as String,
        (a['cover_big'] ?? a['cover_medium'] ?? a['cover']) as String?,
        a['release_date'] as String?,
        (a['nb_tracks'] ?? 0) as int,
        (a['record_type'] ?? 'album') as String,
      );
}
