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

/// An album search hit — carries the artist name so browse can open its tracklist.
class CatalogAlbumHit {
  final CatalogAlbum album;
  final String artist;
  const CatalogAlbumHit(this.album, this.artist);
}

/// A track search hit — tapped to open torrent/Soulseek sources directly.
class CatalogTrackHit {
  final String title;
  final String artist;
  final String? cover;
  const CatalogTrackHit(this.title, this.artist, this.cover);
  String get query => artist.isEmpty ? title : '$artist $title';
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

  /// Top albums right now (Deezer global chart) — for the home screen.
  Future<List<CatalogAlbumHit>> chartAlbums() async {
    final j = await _get('$_base/chart/0/albums?limit=25');
    final data = (j?['data'] as List?) ?? const [];
    return data
        .map((a) => CatalogAlbumHit(_album(a), (a['artist']?['name'] ?? '') as String))
        .where((h) => h.album.title.isNotEmpty)
        .toList();
  }

  /// Newest albums from the artists the user already listens to (Deezer's global "editorial
  /// releases" endpoint is deprecated / empty). This is more personal anyway — "new from your
  /// artists". Runs the per-artist lookups concurrently and returns newest-release-first.
  Future<List<CatalogAlbumHit>> latestFromArtists(List<String> names) async {
    final picks = names.take(6).toList();
    final results = await Future.wait(picks.map((name) async {
      try {
        final aj = await _get('$_base/search/artist?q=${Uri.encodeComponent(name)}&limit=1');
        final ad = (aj?['data'] as List?) ?? const [];
        if (ad.isEmpty) return <CatalogAlbumHit>[];
        final albums = await artistAlbums(ad.first['id'] as int); // newest-first, deduped
        return albums.where((a) => !a.isSingle).take(2).map((a) => CatalogAlbumHit(a, name)).toList();
      } catch (_) {
        return <CatalogAlbumHit>[];
      }
    }));
    final out = <CatalogAlbumHit>[];
    final seen = <String>{};
    for (final list in results) {
      for (final h in list) {
        if (h.album.title.isNotEmpty && seen.add(h.album.title.toLowerCase())) out.add(h);
      }
    }
    out.sort((a, b) => (b.album.releaseDate ?? '').compareTo(a.album.releaseDate ?? ''));
    return out;
  }

  /// Top tracks right now (Deezer global chart) — for the home screen.
  Future<List<CatalogTrackHit>> chartTracks() async {
    final j = await _get('$_base/chart/0/tracks?limit=25');
    final data = (j?['data'] as List?) ?? const [];
    final seen = <String>{};
    return data
        .map((t) => CatalogTrackHit(
              (t['title'] ?? '') as String,
              (t['artist']?['name'] ?? '') as String,
              (t['album']?['cover_medium'] ?? t['album']?['cover']) as String?,
            ))
        .where((h) => h.title.isNotEmpty && seen.add('${h.artist.toLowerCase()}|${h.title.toLowerCase()}'))
        .toList();
  }

  /// Artists matching [q]. An EXACT name match outranks everything, and among equals the one with
  /// the most listeners wins — searching "Michael Jackson" otherwise returns a namesake with a
  /// single release ahead of the real one, and every page that follows is then about the wrong
  /// person.
  Future<List<CatalogArtist>> searchArtists(String q) async {
    final j = await _get('$_base/search/artist?q=${Uri.encodeComponent(q)}&limit=25');
    final data = (j?['data'] as List?) ?? const [];
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final wanted = norm(q);
    final scored = data
        .where((a) => ((a['name'] ?? '') as String).isNotEmpty)
        .map((a) => (
              artist: CatalogArtist(
                a['id'] as int,
                (a['name'] ?? '') as String,
                (a['picture_big'] ?? a['picture_medium']) as String?,
                (a['nb_album'] ?? 0) as int,
              ),
              fans: (a['nb_fan'] as num?)?.toInt() ?? 0,
            ))
        .toList();
    scored.sort((a, b) {
      final ea = norm(a.artist.name) == wanted, eb = norm(b.artist.name) == wanted;
      if (ea != eb) return ea ? -1 : 1;
      return b.fans.compareTo(a.fans);
    });
    return scored.map((e) => e.artist).toList();
  }

  /// Artists this one sits next to — the starting point for "more like this".
  Future<List<CatalogArtist>> relatedArtists(int artistId) async {
    final j = await _get('$_base/artist/$artistId/related?limit=20');
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

  /// Browse: albums matching a query (each keeps its artist for the tracklist page).
  Future<List<CatalogAlbumHit>> searchAlbums(String q) async {
    final j = await _get('$_base/search/album?q=${Uri.encodeComponent(q)}&limit=20');
    final data = (j?['data'] as List?) ?? const [];
    return data
        .map((a) => CatalogAlbumHit(_album(a), (a['artist']?['name'] ?? '') as String))
        .where((h) => h.album.title.isNotEmpty)
        .toList();
  }

  /// Browse: individual tracks matching a query (→ sources on tap).
  Future<List<CatalogTrackHit>> searchTracks(String q) async {
    final j = await _get('$_base/search?q=${Uri.encodeComponent(q)}&limit=25');
    final data = (j?['data'] as List?) ?? const [];
    final seen = <String>{};
    return data
        .map((t) => CatalogTrackHit(
              (t['title'] ?? '') as String,
              (t['artist']?['name'] ?? '') as String,
              (t['album']?['cover_medium'] ?? t['album']?['cover']) as String?,
            ))
        .where((h) => h.title.isNotEmpty && seen.add('${h.artist.toLowerCase()}|${h.title.toLowerCase()}'))
        .toList();
  }

  /// Everyone credited on a track, main artist first.
  ///
  /// Needed because a rip's tags often name only the main artist: the file for Lady Gaga's
  /// "Telephone" is tagged just "Lady Gaga" / "Telephone" with Beyoncé nowhere in it. Deezer's
  /// search result doesn't carry contributors either, so this costs a second call for the track
  /// itself. Cached per track — it never changes.
  final Map<String, List<String>> _contributorCache = {};

  Future<List<String>> trackContributors(String artist, String title) async {
    final key = '${artist.toLowerCase()}|${title.toLowerCase()}';
    final hit = _contributorCache[key];
    if (hit != null) return hit;

    String loose(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final wantedTitle = loose(title);
    final wantedArtist = loose(artist);

    final j = await _get('$_base/search?q=${Uri.encodeComponent('$artist $title')}&limit=8');
    final data = (j?['data'] as List?) ?? const [];
    int? id;
    for (final t in data) {
      final tt = loose((t['title'] ?? '') as String);
      final ta = loose((t['artist']?['name'] ?? '') as String);
      // The catalogue's title may carry the credit our file lacks, so match on "starts with".
      final titleOk = tt == wantedTitle || tt.startsWith(wantedTitle) || wantedTitle.startsWith(tt);
      if (titleOk && (ta == wantedArtist || ta.startsWith(wantedArtist) || wantedArtist.startsWith(ta))) {
        id = t['id'] as int?;
        break;
      }
    }
    if (id == null) return _contributorCache[key] = const [];

    final t = await _get('$_base/track/$id');
    final names = ((t?['contributors'] as List?) ?? const [])
        .map((c) => ((c as Map)['name'] ?? '') as String)
        .where((n) => n.trim().isNotEmpty)
        .toList();
    return _contributorCache[key] = names;
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
