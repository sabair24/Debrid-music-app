@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/musicbrainz.dart';

/// Enrique Iglesias — Escape. The album that "never showed versions with the CD", even though
/// MusicBrainz has fourteen pressings of it and one of them carries a scan of the disc itself.
///
/// Two things went wrong and both are pinned here: only the first eight rows ever had their scans
/// looked up (so the rest reported "no cd-scan" without asking), and pressings were dropped for
/// having a different track count than the local copy — which is exactly what a different pressing
/// IS, and it hid the only one whose disc had been scanned.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('every pressing is offered, and the one with the disc scan is among them', () async {
    final mb = MusicBrainzService();
    // "Enrique" is what the library's tags say — Discogs credits this release "Enrique*" — so the
    // search has to cope with the short name, not just "Enrique Iglesias".
    final choices = await mb.editionChoices('Enrique', 'Escape');

    expect(choices.length, greaterThanOrEqualTo(12),
        reason: 'the release group holds 14 pressings; the picker used to show 4');

    // The 16-track European CD, the one whose disc is in the archive.
    final withDisc = choices.where((c) => c.hasDisc).toList();
    expect(withDisc, isNotEmpty, reason: 'at least one pressing has a scan of the CD itself');
    expect(withDisc.any((c) => c.mbid == 'f8920e1b-5552-4301-85ac-cc9b0ab6e454'), isTrue,
        reason: 'and it is the European CD the user linked');

    // Backs are found too, and every row is a real answer rather than an unexamined one.
    expect(choices.where((c) => c.hasBack).length, greaterThanOrEqualTo(1));
    expect(choices.every((c) => c.source == EditionSource.musicbrainz), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a tracklist is fetched on demand, not up front', () async {
    final mb = MusicBrainzService();
    final choices = await mb.editionChoices('Enrique', 'Escape');
    // Nothing carries a tracklist from the picker — that is what kept it fast enough to look up
    // every row's scans.
    expect(choices.every((c) => c.tracklist.isEmpty), isTrue);

    // But asking for one works, which is what "Nummering overnemen" does.
    final full = await mb.release(choices.first.mbid!);
    expect(full, isNotNull);
    expect(await mb.tracklistOf(full!), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
