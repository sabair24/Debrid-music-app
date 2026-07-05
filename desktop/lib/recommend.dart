import 'dart:convert';
import 'package:http/http.dart' as http;

/// A recommended track (metadata only) — resolved to a playable source on demand.
class RecTrack {
  final String artist;
  final String title;
  final String? cover;
  const RecTrack(this.artist, this.title, this.cover);
  String get query => artist.isEmpty ? title : '$artist $title';
}

/// Recommendation engine (Deezer, keyless): artist radio + related artists,
/// for Radio / Smart Shuffle / discovery.
class RecommendService {
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

  Future<int?> _artistId(String name) async {
    final j = await _get('$_base/search/artist?q=${Uri.encodeComponent(name)}&limit=1');
    final data = (j?['data'] as List?) ?? const [];
    return data.isEmpty ? null : (data.first['id'] as int?);
  }

  List<RecTrack> _tracks(Map<String, dynamic>? j) {
    final data = (j?['data'] as List?) ?? const [];
    return data
        .map((t) => RecTrack(
              ((t['artist']?['name']) ?? '') as String,
              (t['title'] ?? '') as String,
              (t['album']?['cover_medium']) as String?,
            ))
        .where((r) => r.title.isNotEmpty)
        .toList();
  }

  /// Radio (~25 tracks) around an artist — the seed artist mixed with similar ones.
  Future<List<RecTrack>> artistRadio(String artist) async {
    final id = await _artistId(artist);
    if (id == null) return [];
    return _tracks(await _get('$_base/artist/$id/radio'));
  }

  /// Deduped radio built from the seed artist's own top tracks + a "similar" flow
  /// + a few related artists' top tracks. Including the seed's own catalogue is what
  /// lets Smart Shuffle lead with tracks the listener already owns (instant playback);
  /// the similar/related tracks are the discovery layer.
  Future<List<RecTrack>> mixRadio(String artist) async {
    final id = await _artistId(artist);
    if (id == null) return artistRadio(artist);
    final out = <RecTrack>[];
    final seen = <String>{};
    void add(Iterable<RecTrack> ts) {
      for (final t in ts) {
        if (seen.add('${t.artist.toLowerCase()}|${t.title.toLowerCase()}')) out.add(t);
      }
    }

    // Seed's own top tracks + seed "radio" (similar) + related-artist list, concurrently
    // (reusing the one artist id). Deezer's /radio is a similar-artist flow that omits the
    // seed, so /top is needed for the seed's own songs to appear in the queue at all.
    final topF = _get('$_base/artist/$id/top?limit=15');
    final radioF = _get('$_base/artist/$id/radio');
    final relF = _get('$_base/artist/$id/related?limit=4');
    add(_tracks(await topF));
    add(_tracks(await radioF));
    final rel = ((await relF)?['data'] as List?) ?? const [];
    final tops = await Future.wait(rel.take(4).map((a) => _get('$_base/artist/${a['id']}/top?limit=5')));
    for (final t in tops) {
      add(_tracks(t));
    }
    out.shuffle();
    return out;
  }

  /// Discovery feed: top tracks from artists related to the given library seeds.
  Future<List<RecTrack>> discover(List<String> seeds) async {
    final out = <RecTrack>[];
    final seen = <String>{};
    void add(Iterable<RecTrack> ts) {
      for (final t in ts) {
        if (seen.add('${t.artist.toLowerCase()}|${t.title.toLowerCase()}')) out.add(t);
      }
    }

    for (final s in seeds.take(4)) {
      final id = await _artistId(s);
      if (id == null) continue;
      final rel = ((await _get('$_base/artist/$id/related?limit=4'))?['data'] as List?) ?? const [];
      final tops = await Future.wait(rel.take(4).map((a) => _get('$_base/artist/${a['id']}/top?limit=6')));
      for (final t in tops) {
        add(_tracks(t));
      }
    }
    out.shuffle();
    return out;
  }
}
