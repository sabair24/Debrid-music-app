@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/musicbrainz.dart';

/// Live checks on the three searches. Excluded from the normal run.
///
/// These exist because MusicBrainz search has a specific weakness that is easy to ship by
/// accident: no popularity signal at all. The tests pin down which shapes of query actually work.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('artists are found by name, exactly', () async {
    final hits = await MusicBrainzService().searchArtists('backstreet boys');
    expect(hits, isNotEmpty);
    expect(hits.first.name, 'Backstreet Boys');
    expect(hits.first.line, contains('Group'));
  });

  test('an exact name beats a higher-scoring near-miss', () async {
    // "Backstreet" alone also matches "Backstreet Girls" and several unnamed acts.
    final a = await MusicBrainzService().resolveArtist('Backstreet Boys');
    expect(a, isNotNull);
    expect(a!.name, 'Backstreet Boys');
  });

  test('an album search scoped to its artist finds the right record', () async {
    // Unscoped, "thriller" returns Part Chimp, Swoop and Eddie & the Hot Rods first — MusicBrainz
    // ranks on text alone. Scoping to the artist is what makes the search usable.
    final hits =
        await MusicBrainzService().searchReleaseGroups('Thriller', artist: 'Michael Jackson');
    expect(hits, isNotEmpty);
    expect(hits.first.title, 'Thriller');
    expect(hits.first.artist, 'Michael Jackson');
    expect(hits.first.year, 1982);
  });

  test('a discography comes back complete, albums first', () async {
    final mb = MusicBrainzService();
    final a = await mb.resolveArtist('Backstreet Boys');
    final disco = await mb.discographyOf(a!.mbid);
    expect(disco.length, greaterThan(15), reason: 'MusicBrainz carries the regional oddities too');
    expect(disco.first.primaryType, 'Album', reason: 'albums lead, singles trail');
    expect(disco.map((g) => g.title), contains('Millennium'));
  });

  test('recordings are found when the artist scopes them', () async {
    // Unscoped this returns Mar.Ko and The Baseballs before the Backstreet Boys.
    final hits = await MusicBrainzService()
        .searchRecordings('Quit Playing Games', artist: 'Backstreet Boys');
    expect(hits, isNotEmpty);
    expect(hits.first.artist, 'Backstreet Boys');
    expect(hits.first.seconds, greaterThan(60));
  });

  test('the release the user pointed at carries the official numbering', () async {
    // https://musicbrainz.org/release/d87362b1-15d1-41f4-b0e6-fe316d6bcc59
    final r = await MusicBrainzService().release('d87362b1-15d1-41f4-b0e6-fe316d6bcc59');
    expect(r, isNotNull);
    expect(r!.tracks, hasLength(13));
    expect(r.tracks[0].title, contains('Goin'));
    expect(r.tracks[1].title, 'Anywhere for You', reason: 'track 2, which the local tags call 6');
    expect(r.tracks[2].title, startsWith('Get Down'), reason: 'track 3, which the tags leave blank');
    expect(r.tracks[4].title, startsWith('Quit Playing Games'),
        reason: 'track 5, which the tags call 2');
    // Every number present exactly once — the thing the local files get wrong.
    expect(r.tracks.map((t) => t.position).toList(),
        [for (var i = 1; i <= 13; i++) '$i']);
  });
}
