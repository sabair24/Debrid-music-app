import 'dart:convert';
import 'package:http/http.dart' as http;
import 'json_body.dart';
import 'rutracker.dart';
import 'torbox.dart';

String _magnetFor(String hash, String name) =>
    'magnet:?xt=urn:btih:${hash.toLowerCase()}&dn=${Uri.encodeComponent(name)}';

abstract class SearchSource {
  String get id;
  Future<List<SearchResult>> search(String query);
}

/// Pirate Bay via apibay.org (keyless).
class ApibaySource implements SearchSource {
  @override
  String get id => 'apibay';
  @override
  Future<List<SearchResult>> search(String query) async {
    try {
      final r = await http.get(Uri.parse('https://apibay.org/q.php?q=${Uri.encodeComponent(query)}&cat=100'));
      if (r.statusCode != 200) return [];
      final arr = (jsonBody(r) as List?) ?? const [];
      final out = <SearchResult>[];
      for (final e in arr) {
        final m = e as Map<String, dynamic>;
        final hash = (m['info_hash'] as String?)?.toLowerCase();
        final name = (m['name'] ?? '') as String;
        final cat = int.tryParse('${m['category'] ?? ''}') ?? 0;
        if (hash == null || hash == '0' * 40 || name == 'No results returned') continue;
        if (cat < 100 || cat > 199) continue;
        out.add(SearchResult(
          name: name,
          size: int.tryParse('${m['size'] ?? 0}') ?? 0,
          seeders: int.tryParse('${m['seeders'] ?? 0}') ?? 0,
          leechers: int.tryParse('${m['leechers'] ?? 0}') ?? 0,
          hash: hash,
          magnet: _magnetFor(hash, name),
          source: 'Pirate Bay',
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}

/// BitSearch (keyless JSON).
class BitSearchSource implements SearchSource {
  @override
  String get id => 'bitsearch';
  @override
  Future<List<SearchResult>> search(String query) async {
    try {
      final r = await http.get(Uri.parse('https://bitsearch.eu/api/v1/search?q=${Uri.encodeComponent(query)}&category=audio&sort=seeders&p=1'));
      if (r.statusCode != 200) return [];
      final j = jsonBody(r) as Map<String, dynamic>;
      if (j['success'] != true) return [];
      final results = (j['results'] as List?) ?? const [];
      return results
          .map((e) => e as Map<String, dynamic>)
          .where((m) => (m['infohash'] as String?)?.isNotEmpty ?? false)
          .map((m) {
        final hash = (m['infohash'] as String).toLowerCase();
        final name = (m['title'] ?? '') as String;
        return SearchResult(
          name: name,
          size: (m['size'] ?? 0) as int,
          seeders: (m['seeders'] ?? 0) as int,
          leechers: (m['leechers'] ?? 0) as int,
          hash: hash,
          magnet: _magnetFor(hash, name),
          source: 'BitSearch',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

/// Knaben (keyless JSON POST).
class KnabenSource implements SearchSource {
  @override
  String get id => 'knaben';
  static final _infohash = RegExp(r'^([0-9a-fA-F]{40}|[A-Za-z2-7]{32})$');
  @override
  Future<List<SearchResult>> search(String query) async {
    try {
      final body = jsonEncode({
        'query': query, 'search_type': '100%', 'search_field': 'title',
        'order_by': 'seeders', 'order_direction': 'desc', 'size': 50,
        'hide_unsafe': true, 'hide_xxx': true,
      });
      final r = await http.post(Uri.parse('https://api.knaben.org/v1'),
          headers: {'Content-Type': 'application/json'}, body: body);
      if (r.statusCode != 200) return [];
      final hits = (jsonBody(r)['hits'] as List?) ?? const [];
      final out = <SearchResult>[];
      for (final e in hits) {
        final m = e as Map<String, dynamic>;
        final hash = m['hash'] as String?;
        if (hash == null || !_infohash.hasMatch(hash)) continue;
        final name = (m['title'] ?? '') as String;
        final magnet = (m['magnetUrl'] as String?);
        out.add(SearchResult(
          name: name,
          size: (m['bytes'] ?? 0) as int,
          seeders: (m['seeders'] ?? 0) as int,
          leechers: (m['peers'] ?? 0) as int,
          hash: hash.toLowerCase(),
          magnet: (magnet != null && magnet.isNotEmpty) ? magnet : _magnetFor(hash, name),
          source: 'Knaben',
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}

/// RuTracker (login + scrape) — only contributes when the user is logged in.
class RuTrackerSource implements SearchSource {
  final RuTrackerService service;
  RuTrackerSource(this.service);
  @override
  String get id => 'rutracker';
  @override
  Future<List<SearchResult>> search(String query) => service.search(query);
}

/// Runs sources in parallel, dedupes by hash, drops junk, sorts by seeders.
class SearchAggregator {
  final List<SearchSource> sources;
  SearchAggregator(this.sources);

  static final _adult = RegExp(
      r'(\bxxx\b|\.xxx\.|\bporn|brazzers|wowgirls|analvids|nubile|onlyfans|hardcore|\bmilf\b|playboy|penthouse|\bsex\.)',
      caseSensitive: false);
  static final _video = RegExp(
      r'(\b(480p|576p|720p|1080p|1080i|2160p|x264|x265|h\.?264|h\.?265|hevc|xvid|divx|blu-?ray|web-?dl|webrip|hdrip|hdtv|dvdrip|remux|uhd)\b|\bmusic\s*video\b|\bfilm\b|\.(mp4|mkv|avi|m4v|wmv|mov)\b)',
      caseSensitive: false);

  /// [onPartial] fires each time a source finishes, so fast indexers (apibay/BitSearch)
  /// show immediately instead of waiting for the slowest (RuTracker's topic lookups).
  Future<List<SearchResult>> search(String query, {void Function(List<SearchResult>)? onPartial}) async {
    final byHash = <String, SearchResult>{};
    List<SearchResult> snapshot() =>
        byHash.values.toList()..sort((a, b) => b.seeders.compareTo(a.seeders));

    await Future.wait(sources.map((s) async {
      try {
        final list = await s.search(query).timeout(const Duration(seconds: 12));
        for (final r in list.where((r) => r.hash.isNotEmpty && !_isJunk(r.name))) {
          final k = r.hash.toLowerCase();
          final cur = byHash[k];
          if (cur == null || r.seeders > cur.seeders) byHash[k] = r;
        }
        if (onPartial != null) onPartial(snapshot());
      } catch (_) {}
    }));
    return snapshot();
  }

  bool _isJunk(String name) => _adult.hasMatch(name) || _video.hasMatch(name);
}
