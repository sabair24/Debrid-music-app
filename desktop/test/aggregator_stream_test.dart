import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/search.dart';
import 'package:debridmusic/torbox.dart';

class _Fake implements SearchSource {
  @override
  final String id;
  final List<SearchResult> results;
  final Duration delay;
  _Fake(this.id, this.results, this.delay);
  @override
  Future<List<SearchResult>> search(String q) async {
    await Future.delayed(delay);
    return results;
  }
}

SearchResult _r(String name, String hash, int seeders) =>
    SearchResult(name: name, hash: hash, magnet: 'magnet:?xt=urn:btih:$hash', seeders: seeders);

void main() {
  test('aggregator streams per source, dedups, sorts by seeders', () async {
    final fast = _Fake('fast', [_r('A FLAC', 'a' * 40, 10)], const Duration(milliseconds: 10));
    final slow = _Fake('slow', [_r('B FLAC', 'b' * 40, 30), _r('dup', 'a' * 40, 99)],
        const Duration(milliseconds: 120));
    final agg = SearchAggregator([fast, slow]);

    final partialSizes = <int>[];
    final r = await agg.search('q', onPartial: (p) => partialSizes.add(p.length));

    print('partials=$partialSizes final=${r.map((e) => "${e.name}:${e.seeders}").toList()}');
    expect(partialSizes.length, 2); // one emit per source as it completes
    expect(partialSizes.first, 1); // fast source alone first
    expect(r.length, 2); // deduped (a*40 kept once)
    expect(r.first.hash, 'a' * 40); // dedup kept the higher-seeder copy (99) → sorts first
    expect(r.first.seeders, 99);
    expect(r.last.hash, 'b' * 40);
  });

  test('a slow/throwing source does not sink the fast ones', () async {
    final fast = _Fake('fast', [_r('A FLAC', 'a' * 40, 10)], const Duration(milliseconds: 5));
    final bad = _Fake('bad', const [], const Duration(milliseconds: 5));
    final agg = SearchAggregator([fast, bad]);
    final r = await agg.search('q');
    expect(r.length, 1);
  });
}
