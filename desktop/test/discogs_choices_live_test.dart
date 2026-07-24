@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/settings.dart';

/// Enrique Iglesias — Escape, the album Discogs lists seventy-five pressings of.
///
/// The picker used to show two dozen of them and take half a minute doing it, because it fetched
/// every release in full before showing anything. These pin the shape that fixed it: the list lands
/// off one request per master, carrying enough to be worth reading, and a pressing's scans are
/// fetched only when something asks for that one — the picker does so as a row scrolls into view.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  Future<AppSettings> loadSettings() async {
    final s = AppSettings();
    await s.load();
    return s;
  }

  test('the whole versions list arrives fast, and no scan is fetched up front', () async {
    final settings = await loadSettings();
    if (settings.discogsToken.trim().isEmpty) {
      markTestSkipped('no Discogs token configured');
      return;
    }

    final clock = Stopwatch()..start();
    int? firstRowsMs;
    var firstBatch = 0;

    final svc = DiscogsService(settings);
    final all = await svc.releaseChoices(
      'Enrique',
      'Escape',
      onPartial: (rows) {
        firstRowsMs ??= clock.elapsedMilliseconds;
        if (firstBatch == 0) firstBatch = rows.length;
      },
    );
    final listMs = clock.elapsedMilliseconds;

    // The listing is one request per master, so the rows have to be there almost immediately —
    // not after a per-release lookup apiece.
    expect(firstRowsMs, isNotNull);
    expect(firstRowsMs!, lessThan(12000),
        reason: 'rows appeared after ${firstRowsMs}ms; they used to take ~26s');
    expect(firstBatch, greaterThan(30),
        reason: 'only $firstBatch pressings in the first batch — Discogs lists 75');

    // The whole call is now the listing and nothing else. Enriching forty pressings here, one
    // request apiece on a 60-a-minute lane, is exactly what this stopped doing.
    expect(listMs, lessThan(15000),
        reason: 'releaseChoices took ${listMs}ms — it should not be fetching scans at all');

    // Every row is worth reading straight away: format and a sleeve, from the listing alone.
    expect(all.take(20).where((c) => c.front != null).length, greaterThan(10));
    expect(all.every((c) => c.source == EditionSource.discogs), isTrue);

    // A pressing not yet looked up must not pretend to know it has no back.
    for (final c in all.where((c) => !c.detailed)) {
      expect(c.hasBack, isFalse);
      expect(c.hasDisc, isFalse);
    }

    // And asking for ONE fills that one in — what the picker does per visible row.
    final one = await svc.detailOf(all.first);
    expect(one, isNotNull);
    expect(one!.detailed, isTrue);
    // ignore: avoid_print
    print('lijst na ${listMs}ms: $firstBatch pressingen, ${all.length} totaal; '
        'één detail erbij: back=${one.hasBack} disc=${one.hasDisc}');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a cassette is never offered', () async {
    final settings = await loadSettings();
    if (settings.discogsToken.trim().isEmpty) {
      markTestSkipped('no Discogs token configured');
      return;
    }
    final all = await DiscogsService(settings).releaseChoices('Enrique', 'Escape');
    expect(all.any((c) => c.format.toLowerCase().contains('cassette')), isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
