@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/release_format.dart';

/// Hits MusicBrainz and the Cover Art Archive for real. Excluded from the normal run
/// (`--exclude-tags live`); this is here to check that the two still answer the way the design
/// assumes, not to gate every commit on someone else's uptime.
void main() {
  // flutter_test swaps in an HTTP client that answers 400 to everything.
  setUpAll(() => HttpOverrides.global = null);

  test('one call carries the tracklist, the label and the catalogue number', () async {
    final mb = MusicBrainzService();
    final hits = await mb.searchReleases('Adele', '30', expectedTracks: 12);
    expect(hits, isNotEmpty);

    // CD before digital, which is the whole preference.
    expect(hits.first.major, 'CD', reason: 'a documented CD must lead, not a digital stub');

    final full = await mb.release(hits.first.mbid);
    expect(full, isNotNull);
    expect(full!.tracks, isNotEmpty, reason: 'the tracklist comes with the same request');
    expect(full.tracks.first.ms, isNotNull, reason: 'with millisecond timings');
    expect(full.catno, isNotNull, reason: 'and the catalogue number, without a second call');
    expect(full.releaseGroupId, isNotNull);

    // And every other pressing of the record, also in one call.
    final all = await mb.editionsOf(full.releaseGroupId!);
    expect(all.length, greaterThan(5), reason: 'a release-group browse returns them all at once');
    expect(releaseFormatRank(all.first.major), lessThanOrEqualTo(releaseFormatRank(all.last.major)));
  });

  test('the archive states what each scan is — front, back and the disc', () async {
    final mb = MusicBrainzService();
    // The Japanese CD of 30: twenty-one scans, including the disc itself.
    final images = await mb.art('ce4eb4e1-e490-4808-9cc6-d0c0d8001ff0');
    expect(images, isNotEmpty);
    expect(images.any((i) => i.isFront), isTrue);
    expect(images.any((i) => i.isBack), isTrue);
    expect(images.any((i) => i.isDisc), isTrue,
        reason: 'Medium is the disc — the thing the pixel guess exists to find');
  });

  test('an empty archive is a silence, not a crash', () async {
    // The British CD of 30 has no art at all. Very common, and the reason Discogs stays.
    expect(await MusicBrainzService().art('fd2ee47d-4456-4cb1-a6e2-85d6aeefbc81'), isEmpty);
  });

  test('Thriller leads with a CD even though MusicBrainz lists vinyl first', () async {
    // 104 releases, ranked by MusicBrainz with the 1982 LPs at the top. This is the same trap the
    // Discogs path fell into, and the reason the preference is shared between them.
    final hits = await MusicBrainzService().searchReleases('Michael Jackson', 'Thriller');
    expect(hits, isNotEmpty);
    expect(hits.first.major, 'CD');
  });
}
