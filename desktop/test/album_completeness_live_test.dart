@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/musicbrainz.dart';

/// Does the album page actually learn what a record holds, when the library holds almost none of it?
///
/// This is the whole premise of the missing-tracks list, and the one part of it that depends on a
/// remote answer. The page asks WITHOUT expectedTracks on purpose — the library's own count is the
/// wrong question here, because owning one track of sixteen is exactly the case being solved. What
/// these pin is that dropping that filter doesn't cost us the right release.
Future<List<dynamic>> _official(MusicBrainzService mb, String artist, String album) async {
  final hits = await mb.searchReleases(artist, DiscogsService.plainTitle(album));
  if (hits.isEmpty) return const [];
  final full = await mb.release(hits.first.mbid);
  return full == null ? const [] : await mb.tracklistOf(full);
}

Track _t(String title, int seconds, String album) => Track(
      path: r'D:\Flac music 2024\Albums\x\' '$album\\01 - $title.flac',
      title: title,
      artist: 'x',
      album: album,
      duration: Duration(seconds: seconds),
    );

void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('one track of RENAISSANCE still resolves the whole record', () async {
    final mb = MusicBrainzService();
    final official = (await _official(mb, 'Beyoncé', 'RENAISSANCE')).cast<dynamic>();
    expect(official.length, greaterThanOrEqualTo(14),
        reason: 'got ${official.length} tracks — a single or an EP was picked over the album');

    final c = matchAlbumTracks(
        official.cast(), [_t('CUFF IT', 225, 'RENAISSANCE')], 'Beyoncé', source: 'MusicBrainz');
    expect(c.have, 1, reason: 'the one track on disk must be recognised, not reported as missing');
    expect(c.missing.length, greaterThanOrEqualTo(13));
    expect(c.slots.any((s) => s.track != null && s.number == 4), isTrue,
        reason: 'CUFF IT is track 4 on the record');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test("the eleven tracks of Backstreet's Back resolve to an eleven-track pressing", () async {
    // The record has ten pressings, 11 to 16 tracks, including a Malaysian double CD. Choosing the
    // first one big enough picked that double CD and reported five gaps — a Christmas song among
    // them — for a record the user holds complete. Containment, not size, is the question.
    final mb = MusicBrainzService();
    final groups = await mb.searchReleaseGroups("Backstreet's Back", artist: 'Backstreet Boys');
    final g = groups.where((x) => !x.isCompilation).firstOrNull ?? groups.first;
    final all = await mb.editionsOf(g.mbid);
    expect(all.length, greaterThan(3), reason: 'de release-group hoort alle persingen te geven');

    // The eleven album tracks as they sit on disk, in the library's own spelling.
    const titles = [
      "Everybody (Backstreet's Back)", 'As Long as You Love Me', 'All I Have to Give',
      "That's the Way I Like It", '10.000 Promises', 'Like a Child',
      "Hey Mr. DJ (Keep Playin' This Song)", 'Set Adrift on Memory Bliss',
      "That's What She Said", 'If You Want to Be a Good Girl (Get Yourself a Bad Boy)',
      "If I Don't Have You",
    ];
    // No durations: a real library has the pressing's own timings, and inventing one figure for
    // every track would make the ±12s rule reject titles that do match. This test is about which
    // pressing the titles pick.
    final mine = [
      for (final t in titles)
        Track(
            path: r"D:\Flac music 2024\Albums\Backstreet Boys\Backstreet's Back\" '$t.flac',
            title: t,
            artist: 'Backstreet Boys',
            album: "Backstreet's Back")
    ];

    final shortlist = shortlistPressings([for (final r in all) r.trackCount], mine.length);
    final lists = <List<ChoiceTrack>>[];
    final scored = <AlbumCompleteness>[];
    for (final i in shortlist) {
      final list = await mb.tracklistOf(all[i]);
      if (list.isEmpty) continue;
      lists.add(list);
      scored.add(matchAlbumTracks(list, mine, 'Backstreet Boys'));
    }
    final pick = pickPressing(scored);
    expect(pick, greaterThanOrEqualTo(0));

    expect(lists[pick], hasLength(11),
        reason: 'koos een ${lists[pick].length}-nummer persing voor een plaat van 11');
    expect(scored[pick].namesEverything, isTrue);
    expect(scored[pick].complete, isTrue, reason: 'deze plaat is compleet — er ontbreekt niets');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('and a record we hold in full reports nothing missing', () async {
    final mb = MusicBrainzService();
    final official = await _official(mb, 'Enrique Iglesias', 'Escape');
    expect(official, isNotEmpty);

    // Feed the official list back in as if every track were on disk: the matcher must recognise
    // its own titles, or every complete album in the library would sprout a download bar.
    final tracks = [
      for (final o in official.cast<dynamic>())
        _t(o.title as String, (o.seconds as int?) ?? 200, 'Escape')
    ];
    final c = matchAlbumTracks(official.cast(), tracks, 'Enrique Iglesias');
    expect(c.complete, isTrue, reason: 'missing: ${c.missing.map((s) => s.title).toList()}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
