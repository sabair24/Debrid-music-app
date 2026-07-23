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
/// off one request per master, and the scans fill in behind it.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  Future<AppSettings> loadSettings() async {
    final s = AppSettings();
    await s.load();
    return s;
  }

  test('the whole versions list arrives fast, then the scans fill in', () async {
    final settings = await loadSettings();
    if (settings.discogsToken.trim().isEmpty) {
      markTestSkipped('no Discogs token configured');
      return;
    }

    final clock = Stopwatch()..start();
    int? firstRowsMs;
    var firstBatch = 0;
    var updates = 0;

    final all = await DiscogsService(settings).releaseChoices(
      'Enrique',
      'Escape',
      enrich: 6, // keep the test short; the shape is what matters, not the depth
      onPartial: (rows) {
        updates++;
        firstRowsMs ??= clock.elapsedMilliseconds;
        if (firstBatch == 0) firstBatch = rows.length;
      },
    );

    // The listing is one request per master, so the rows have to be there almost immediately —
    // not after a per-release lookup apiece.
    expect(firstRowsMs, isNotNull);
    expect(firstRowsMs!, lessThan(12000),
        reason: 'rows appeared after ${firstRowsMs}ms; they used to take ~26s');
    expect(firstBatch, greaterThan(30),
        reason: 'only $firstBatch pressings in the first batch — Discogs lists 75');

    // And they keep arriving with their scans filled in.
    expect(updates, greaterThan(1), reason: 'the scans should stream in, not land all at once');
    expect(all.where((c) => c.detailed).length, greaterThanOrEqualTo(1));

    // Every row is worth reading straight away: format and a sleeve, from the listing alone.
    expect(all.take(20).where((c) => c.front != null).length, greaterThan(10));
    expect(all.every((c) => c.source == EditionSource.discogs), isTrue);

    // A pressing not yet looked up must not pretend to know it has no back.
    for (final c in all.where((c) => !c.detailed)) {
      expect(c.hasBack, isFalse);
      expect(c.hasDisc, isFalse);
    }
    // ignore: avoid_print
    print('eerste rijen na ${firstRowsMs}ms: $firstBatch pressingen, ${all.length} totaal, '
        '${all.where((c) => c.detailed).length} met scans, ${updates} updates');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a cassette is never offered', () async {
    final settings = await loadSettings();
    if (settings.discogsToken.trim().isEmpty) {
      markTestSkipped('no Discogs token configured');
      return;
    }
    final all = await DiscogsService(settings)
        .releaseChoices('Enrique', 'Escape', enrich: 0);
    expect(all.any((c) => c.format.toLowerCase().contains('cassette')), isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
