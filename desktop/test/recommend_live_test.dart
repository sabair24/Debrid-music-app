@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/recommend.dart';

/// Radio, against the real Deezer.
///
/// These used to live untagged in recommend_test.dart and so ran in every suite, which is why a
/// broken Radio button read as "one flaky test we've always had". They are tagged now — run them
/// with --run-skipped — and they assert what a radio actually needs, not merely that a list came
/// back non-empty. That weakness is what hid the bug: `artistRadio('Michael Jackson')` was passing
/// while resolving an 86-fan namesake and returning a single track.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('artist radio is a radio, not one track by a namesake', () async {
    final r = await RecommendService().artistRadio('Michael Jackson');
    expect(r.length, greaterThan(5),
        reason: 'kreeg ${r.length} nummers — dat is een naamgenoot, geen radio');
    expect(r.first.title, isNotEmpty);
    expect(r.first.artist, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('mixRadio blends related artists, and finds the real Adele', () async {
    final r = await RecommendService().mixRadio('Adele');
    final artists = r.map((t) => t.artist.toLowerCase()).toSet();
    expect(r.length, greaterThan(15));
    expect(artists.length, greaterThan(1), reason: 'alleen de zaadartiest is geen mix');
    // The seed's own catalogue has to be in there: that is what lets Smart Shuffle lead with
    // tracks already owned. It was missing entirely while the wrong Adele was being resolved.
    expect(artists.any((a) => a.contains('adele')), isTrue,
        reason: 'geen enkel nummer van Adele zelf: ${artists.take(5).toList()}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
