@Tags(['live'])
library;

// What the pressing gallery actually costs, against the real servers. Excluded from the normal run.
//
// Measured on this album on 26 July 2026, before the fixes below:
//   • opening the gallery cold      16–31 s, a spinner for all of it
//   • one MusicBrainz `?query=`     44 ms, 12.1 s, 15.9 s, 17.9 s over four tries
//   • one Cover Art Archive lookup  1.0–2.0 s, and the lane held each one end to end
//   • the same group via the pin    48–232 ms
//
// Céline Dion – Sans attendre: one release group, eight pressings, five with scans.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/musicbrainz.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);
  setUp(MusicBrainzService.resetLanes);

  test('eight scan lookups overlap instead of queueing', () async {
    // The pinned French CD's group holds them all, and a browse names them in one request.
    final mb = MusicBrainzService();
    final pinned = await mb.release('bcd34d7e-2ffa-48d0-bd4b-19d278ca0a0c');
    expect(pinned, isNotNull, reason: 'no network, or MusicBrainz moved the release');
    final group = pinned!.releaseGroupId;
    expect(group, isNotNull, reason: 'a lookup asks for release-groups, so this is free');

    final editions = await mb.editionsOf(group!);
    expect(editions.length, greaterThanOrEqualTo(6));

    final sw = Stopwatch()..start();
    final scans = await Future.wait([for (final e in editions) mb.art(e.mbid)]);
    sw.stop();

    // Serialised — a lookup takes 1–2 s and the lane used to hold each one — eight of these cost
    // thirteen seconds or more. Paced, the starts are 250 ms apart and the round trips overlap:
    // 7 x 250 ms + one round trip, comfortably under four seconds even on a slow day.
    expect(sw.elapsedMilliseconds, lessThan(8000),
        reason: 'the lane is queueing whole round trips again — ${sw.elapsedMilliseconds}ms for '
            '${editions.length} lookups');
    expect(scans.where((s) => s.isNotEmpty).length, greaterThanOrEqualTo(3),
        reason: 'several of these pressings do have scans; nothing was actually asked otherwise');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a pinned pressing skips the slow search entirely', () async {
    // The search is the single slowest thing in opening this dialog and its answer is already known
    // when a pin exists: a pressing belongs to exactly one release group, and the lookup said which.
    final mb = MusicBrainzService();
    final sw = Stopwatch()..start();
    final r = await mb.release('bcd34d7e-2ffa-48d0-bd4b-19d278ca0a0c');
    sw.stop();
    expect(r?.releaseGroupId, isNotNull);
    expect(sw.elapsedMilliseconds, lessThan(4000),
        reason: 'a lookup is not a search; if this is slow the endpoint changed');
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('the gallery shows rows before the scans arrive, and never takes one away', () async {
    final counts = <int>[];
    final firstPartial = Stopwatch()..start();
    var firstPartialMs = -1;

    final out = await MusicBrainzService().editionChoices('Céline Dion', 'Sans attendre',
        pinnedMbid: 'bcd34d7e-2ffa-48d0-bd4b-19d278ca0a0c', onPartial: (rows) {
      if (firstPartialMs < 0) firstPartialMs = firstPartial.elapsedMilliseconds;
      counts.add(rows.length);
    });

    expect(counts, isNotEmpty, reason: 'nothing was published while it worked');
    expect(counts.first, greaterThan(0), reason: 'the pressings are named before anything is fetched');
    // The user-visible win: something on screen in a second or two instead of half a minute.
    expect(firstPartialMs, lessThan(6000),
        reason: 'the first rows took ${firstPartialMs}ms to appear');
    for (var i = 1; i < counts.length; i++) {
      expect(counts[i], greaterThanOrEqualTo(counts[i - 1]),
          reason: 'a row vanished between updates ($counts) — worse than one arriving late');
    }
    expect(out.length, greaterThanOrEqualTo(counts.last));
    expect(out.first.mbid, 'bcd34d7e-2ffa-48d0-bd4b-19d278ca0a0c',
        reason: "the pressing the user pinned leads the list");
    expect(out.where((c) => c.front != null).length, greaterThanOrEqualTo(3),
        reason: 'the scans still land, they just no longer gate the list');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
