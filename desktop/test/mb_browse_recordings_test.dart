/// Six requests per album, down to two.
///
/// The browse that lists a record's pressings asked for `media+labels+artist-credits`, which gives
/// `track-count` but no `tracks` — so every shortlisted pressing then needed its own lookup, four
/// more requests at 1.1 s apart. Asking for `recordings` as well returns all of them in the one
/// answer, and it is still faster than a single one of the lookups it replaces.
///
/// The danger is the server's silent cap: at roughly 500 tracks it truncates and keeps reporting
/// the true `release-count`. Measured on Thriller — 41 of 85. The shortlist ranks over ALL
/// pressings, so a truncated roster could quietly pick a different pressing than before. That is
/// what most of this file is about.
///
/// No sockets: `_get` reads its disk cache before it ever reaches HTTP, so seeding that cache with
/// crafted answers drives the whole thing offline. A request that is NOT seeded would try the
/// network and leave a miss marker behind — which is how "no second request was made" is asserted.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';

void main() {
  late Directory scratch;
  late MusicBrainzService mb;
  const rg = 'f32fab67-77dd-3937-addc-9062e28e4c37';

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_mbbrowse_');
    setAppDirForTest(scratch.path);
    Directory('${scratch.path}${Platform.pathSeparator}musicbrainz').createSync();
    mb = MusicBrainzService();
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  File cacheFile(String url) => File('${scratch.path}${Platform.pathSeparator}musicbrainz'
      '${Platform.pathSeparator}${sha1.convert(utf8.encode(url))}.json');

  /// One pressing, with or without its tracklist.
  Map<String, dynamic> release(String id, {required int tracks, bool withTracks = false}) => {
        'id': id,
        'title': 'Thriller',
        'status': 'Official',
        'country': 'US',
        'date': '1982-11-30',
        'label-info': [
          {'label': {'name': 'Epic'}, 'catalog-number': 'EK $id'}
        ],
        'media': [
          {
            'format': 'CD',
            'position': 1,
            'track-count': tracks,
            if (withTracks)
              'tracks': [
                for (var i = 1; i <= tracks; i++)
                  {'number': '$i', 'title': 'nummer $i van $id', 'length': 200000},
              ],
          }
        ],
      };

  void seed(String url, {required List<Map<String, dynamic>> releases, required int total}) =>
      cacheFile(url).writeAsStringSync(
          jsonEncode({'releases': releases, 'release-count': total, 'release-offset': 0}));

  String richUrl({int max = 100}) => mb.editionsUrl(rg, max: max, tracklists: true);
  String plainUrl({int max = 100}) => mb.editionsUrl(rg, max: max);

  group('a complete answer', () {
    test('needs no second request', () async {
      seed(richUrl(),
          releases: [
            for (var i = 1; i <= 3; i++) release('r$i', tracks: 9, withTracks: true),
          ],
          total: 3);

      final out = await mb.editionsOf(rg, tracklists: true);

      expect(out, hasLength(3));
      expect(out.every((r) => r.tracks.isNotEmpty), isTrue);
      // The plain URL was never asked for. Had it been, the miss would be cached right here.
      expect(cacheFile(plainUrl()).existsSync(), isFalse,
          reason: 'twee verzoeken, niet zes — en de tweede is er niet');
    });

    test('carries the tracks through unchanged', () async {
      seed(richUrl(), releases: [release('r1', tracks: 9, withTracks: true)], total: 1);
      final out = await mb.editionsOf(rg, tracklists: true);
      expect(out.single.tracks.map((t) => t.title).take(2), ['nummer 1 van r1', 'nummer 2 van r1']);
      expect(out.single.tracks.first.disc, 1);
      expect(out.single.trackCount, 9);
    });
  });

  group('an answer the server cut short', () {
    test('still ranks over every pressing, not only the ones it sent', () async {
      // What Thriller does: 41 of 85 come back, release-count still says 85.
      seed(richUrl(),
          releases: [for (var i = 1; i <= 2; i++) release('r$i', tracks: 9, withTracks: true)],
          total: 5);
      seed(plainUrl(), releases: [for (var i = 1; i <= 5; i++) release('r$i', tracks: 9)], total: 5);

      final out = await mb.editionsOf(rg, tracklists: true);

      expect(out, hasLength(5),
          reason: 'anders kiest de shortlist uit 41 van de 85 en kan hij een andere persing pakken');
      expect(out.map((r) => r.mbid).toSet(), {'r1', 'r2', 'r3', 'r4', 'r5'});
    });

    test('keeps the tracklists it did pay for', () async {
      seed(richUrl(),
          releases: [for (var i = 1; i <= 2; i++) release('r$i', tracks: 9, withTracks: true)],
          total: 5);
      seed(plainUrl(), releases: [for (var i = 1; i <= 5; i++) release('r$i', tracks: 9)], total: 5);

      final out = await mb.editionsOf(rg, tracklists: true);
      final byId = {for (final r in out) r.mbid: r};

      expect(byId['r1']!.tracks, isNotEmpty);
      expect(byId['r2']!.tracks, isNotEmpty);
      // The rest stay empty, so tracklistOf looks them up one at a time — as it always did.
      expect(byId['r5']!.tracks, isEmpty);
    });

    test('more pressings than the limit counts as cut short', () async {
      seed(richUrl(max: 2),
          releases: [release('r1', tracks: 9, withTracks: true)], total: 150);
      seed(plainUrl(max: 2),
          releases: [for (var i = 1; i <= 2; i++) release('r$i', tracks: 9)], total: 150);

      expect(await mb.editionsOf(rg, max: 2, tracklists: true), hasLength(2));
    });

    test('as many back as there are is NOT cut short', () async {
      seed(richUrl(),
          releases: [for (var i = 1; i <= 5; i++) release('r$i', tracks: 9, withTracks: true)],
          total: 5);

      expect(await mb.editionsOf(rg, tracklists: true), hasLength(5));
      expect(cacheFile(plainUrl()).existsSync(), isFalse);
    });
  });

  group('when the big request fails', () {
    test('the roster still arrives, and the old chain takes over', () async {
      // A 526 kB body is likelier to hit the 12 s timeout than a 132 kB one, so this path is not
      // hypothetical. It must land on today's behaviour, not on nothing.
      cacheFile(richUrl()).writeAsStringSync(jsonEncode({'_miss': 1}));
      seed(plainUrl(), releases: [for (var i = 1; i <= 4; i++) release('r$i', tracks: 9)], total: 4);

      final out = await mb.editionsOf(rg, tracklists: true);

      expect(out, hasLength(4));
      expect(out.every((r) => r.tracks.isEmpty), isTrue,
          reason: 'geen tracklijsten, dus tracklistOf haalt ze op — precies zoals vroeger');
    });
  });

  group('the pressing gallery', () {
    test('still asks the small question', () async {
      seed(plainUrl(), releases: [for (var i = 1; i <= 3; i++) release('r$i', tracks: 9)], total: 3);

      final out = await mb.editionsOf(rg);

      expect(out, hasLength(3));
      expect(cacheFile(richUrl()).existsSync(), isFalse,
          reason: 'de galerij wil geen tracklijsten — die zou 8x zoveel bytes kosten voor niets');
    });
  });

  group('the cache key', () {
    test('the plain URL is byte-for-byte what it always was', () {
      // The disk cache is keyed on sha1 of the whole URL. Reordering the query string would throw
      // away every cached browse on every machine, silently, for no gain.
      expect(mb.editionsUrl(rg),
          'https://musicbrainz.org/ws/2/release?release-group=$rg'
          '&fmt=json&inc=media+labels+artist-credits&limit=100');
    });

    test('and the rich one differs only by the extra inc', () {
      expect(mb.editionsUrl(rg, tracklists: true),
          mb.editionsUrl(rg).replaceFirst('artist-credits', 'artist-credits+recordings'));
    });
  });
}
