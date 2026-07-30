import 'package:http/http.dart' as http;
import 'json_body.dart';

import 'organize.dart' show artistKey;

/// Which of Deezer's artist hits is the artist actually meant.
///
/// Deezer's artist search is not ranked by popularity, and the difference is not subtle: searching
/// "Adele" puts "Adele & The Chandeliers" (41 fans) first and the real Adele (15,429,227) fifth;
/// "Michael Jackson" leads with an 86-fan account. Taking row one — which is what asking for
/// limit=1 did — built the entire radio around a namesake with no catalogue, so /radio answered
/// "no data" and the Radio button came back empty.
///
/// The rule: the name has to be the name that was asked for, and among those, the one people
/// actually listen to. Fan count is the only popularity signal Deezer gives without a key, and it
/// separates fifteen million from forty-one without ambiguity. An exact name always outranks fans,
/// so "Enrique Iglesias & Ana Mena" can never win the query "Enrique Iglesias" — a collaboration
/// is a different act, however popular.
///
/// Names are compared through [artistKey], so "Beyonce" finds "Beyoncé".
int? pickArtist(List<dynamic> hits, String wanted) {
  final want = artistKey(wanted);
  final rows = [for (final h in hits) if (h is Map && h['id'] != null) h];
  if (rows.isEmpty) return null;
  rows.sort((a, b) {
    final ea = artistKey('${a['name'] ?? ''}') == want;
    final eb = artistKey('${b['name'] ?? ''}') == want;
    if (ea != eb) return ea ? -1 : 1;
    final fa = (a['nb_fan'] as num?)?.toInt() ?? 0;
    final fb = (b['nb_fan'] as num?)?.toInt() ?? 0;
    return fb.compareTo(fa);
  });
  return (rows.first['id'] as num?)?.toInt();
}

/// A recommended track (metadata only) — resolved to a playable source on demand.
class RecTrack {
  final String artist;
  final String title;
  final String? cover;

  /// Which record it is on, and Deezer's id for it. Empty and 0 when the source did not say.
  ///
  /// Both were always in the answer — the cover above is that same album's — and throwing them away
  /// is why a tile under "Aanbevolen voor jou" could only start playing. Every other row on that
  /// screen opens the album; this one now can too.
  final String album;
  final int albumId;
  const RecTrack(this.artist, this.title, this.cover, {this.album = '', this.albumId = 0});

  /// True when there is a record to open rather than only a song to play.
  bool get hasAlbum => albumId > 0 && album.trim().isNotEmpty && artist.trim().isNotEmpty;
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
      final j = jsonBody(r);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _artistId(String name) async {
    final j = await _get('$_base/search/artist?q=${Uri.encodeComponent(name)}&limit=10');
    return pickArtist((j?['data'] as List?) ?? const [], name);
  }

  List<RecTrack> _tracks(Map<String, dynamic>? j) {
    final data = (j?['data'] as List?) ?? const [];
    return data
        .map((t) => RecTrack(
              ((t['artist']?['name']) ?? '') as String,
              (t['title'] ?? '') as String,
              (t['album']?['cover_medium']) as String?,
              album: ((t['album']?['title']) ?? '') as String,
              albumId: ((t['album']?['id']) as num?)?.toInt() ?? 0,
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
