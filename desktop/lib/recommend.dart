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
    return data.isEmpty ? null : data.first['id'] as int;
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

  /// Deduped radio built from an artist + a few related artists' top tracks,
  /// for more variety in a longer queue.
  Future<List<RecTrack>> mixRadio(String artist) async {
    final out = <RecTrack>[];
    final seen = <String>{};
    void add(Iterable<RecTrack> ts) {
      for (final t in ts) {
        if (seen.add('${t.artist.toLowerCase()}|${t.title.toLowerCase()}')) out.add(t);
      }
    }

    add(await artistRadio(artist));
    final id = await _artistId(artist);
    if (id != null) {
      final rel = (await _get('$_base/artist/$id/related?limit=4'))?['data'] as List? ?? const [];
      for (final a in rel.take(4)) {
        final aid = a['id'];
        add(_tracks(await _get('$_base/artist/$aid/top?limit=5')));
      }
    }
    out.shuffle();
    return out;
  }
}
