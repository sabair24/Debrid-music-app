@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/discogs.dart';
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

  test('a record held in full is described by a pressing that can hold it', () async {
    // Ranked first for this album is a ten-track pressing, while the library holds thirteen. Taken
    // at face value it reported nothing missing AND filed three tracks the user owns as not being
    // on the record — the album page showed "2" sitting between 10 and 11, with no 12.
    final mb = MusicBrainzService();
    final hits = await mb.searchReleases('Backstreet Boys', 'Backstreet Boys');
    expect(hits, isNotEmpty);

    final i = pickPressing([for (final h in hits) h.trackCount], 13);
    expect(i, greaterThanOrEqualTo(0));
    expect(hits[i].trackCount, greaterThanOrEqualTo(13),
        reason: 'picked a ${hits[i].trackCount}-track pressing for a 13-track album');

    final full = await mb.release(hits[i].mbid);
    final official = await mb.tracklistOf(full!);
    expect(official.length, greaterThanOrEqualTo(13));
    // And the positions run 1..n, which is what the rows are numbered by.
    expect(official.take(13).map((t) => int.tryParse(t.position)).toList(),
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
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
