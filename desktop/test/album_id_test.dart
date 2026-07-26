/// An album keeping its name when you change its name.
///
/// Everything the app remembers ABOUT a record is filed under `artist|title` — merged pressings,
/// hand-assigned scans, styles, cached covers. Correcting the artist is the most ordinary edit
/// there is, and it moved every one of those keys at once. Nobody deleted any of it; the key walked
/// out from under it, and the loss only shows up days later.
///
/// Two halves here: the uid, which is anchored on track paths and therefore does not move at all,
/// and carrying the name-keyed maps across a rename for the things that cannot use it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/album_id.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

Track _t(String path, {String artist = 'Portishead', String album = 'Dummy', int no = 1}) =>
    Track(path: path, title: 'nr $no', artist: artist, album: album, trackNo: no);

Album _album(List<Track> ts, {String artist = 'Portishead', String title = 'Dummy'}) =>
    Album(title, artist, ts);

void main() {
  late Directory scratch;
  late AlbumUids uids;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_uid_');
    setAppDirForTest(scratch.path);
    uids = AlbumUids(dir: () => scratch.path);
  });

  tearDown(() {
    uids.dispose();
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  final tracks = [for (var i = 1; i <= 6; i++) _t('/m/$i.flac', no: i)];

  group('the uid holds still', () {
    test('a rename does not move it — the paths did not move', () {
      final before = _album(tracks);
      uids.reconcile([before]);
      final uid = uids.uidOf(before);
      expect(uid, isNotEmpty);

      // Exactly what applyCorrection produces: new Track objects, same paths.
      final renamed = _album(
        [for (final t in tracks) _t(t.path, artist: 'Portishead & Beth Gibbons', no: t.trackNo)],
        artist: 'Portishead & Beth Gibbons',
      );
      uids.reconcile([renamed]);

      expect(uids.uidOf(renamed), uid);
    });

    test('a second pass over an unchanged library changes nothing', () {
      final a = _album(tracks);
      expect(uids.reconcile([a]), isTrue, reason: 'de eerste keer wordt er gemunt');
      expect(uids.reconcile([a]), isFalse, reason: 'daarna mag het geen schijf meer kosten');
    });

    test('it survives a restart', () async {
      final a = _album(tracks);
      uids.reconcile([a]);
      final uid = uids.uidOf(a);
      await uids.flush();

      final again = AlbumUids(dir: () => scratch.path);
      await again.load();
      expect(again.uidOf(a), uid);
      again.dispose();
    });
  });

  group('splitting and merging', () {
    test('the side with most of the tracks keeps the uid, the other mints', () {
      final whole = _album(tracks);
      uids.reconcile([whole]);
      final uid = uids.uidOf(whole);

      // An edition split: four tracks stay, two become their own pressing.
      final big = _album(tracks.take(4).toList());
      final small = _album(tracks.skip(4).toList());
      uids.reconcile([big, small]);

      expect(uids.uidOf(big), uid, reason: 'de grootste helft is nog steeds dezelfde plaat');
      expect(uids.uidOf(small), isNotEmpty);
      expect(uids.uidOf(small), isNot(uid));
    });

    test('merging two pressings keeps the bigger one', () {
      final big = _album(tracks.take(4).toList());
      final small = _album(tracks.skip(4).toList());
      uids.reconcile([big, small]);
      final bigUid = uids.uidOf(big);
      final smallUid = uids.uidOf(small);
      expect(bigUid, isNot(smallUid));

      uids.reconcile([_album(tracks)]);
      expect(uids.uidOf(_album(tracks)), bigUid);
    });

    test('order does not decide it — the same two groups give the same answer twice', () {
      final big = _album(tracks.take(4).toList());
      final small = _album(tracks.skip(4).toList());
      uids.reconcile([big, small]);
      final first = (uids.uidOf(big), uids.uidOf(small));

      // Same albums, presented the other way round. Identity must not depend on iteration order.
      uids.reconcile([small, big]);
      expect((uids.uidOf(big), uids.uidOf(small)), first);
    });

    test('a track leaving does not rename the record', () {
      final a = _album(tracks);
      uids.reconcile([a]);
      final uid = uids.uidOf(a);

      final fewer = _album(tracks.take(5).toList());
      uids.reconcile([fewer]);
      expect(uids.uidOf(fewer), uid);
    });
  });

  group('files that move', () {
    test('a move the app performed carries the uid along', () {
      final a = _album(tracks);
      uids.reconcile([a]);
      final uid = uids.uidOf(a);

      uids.reKey('/m/1.flac', '/tidy/Albums/Portishead/Dummy/01.flac');
      expect(uids.uidOfPath('/tidy/Albums/Portishead/Dummy/01.flac'), uid);
      expect(uids.uidOfPath('/m/1.flac'), isNull);
    });
  });

  group('forgetting', () {
    test('an empty library forgets nothing — the disk may simply be absent', () {
      final a = _album(tracks);
      uids.reconcile([a]);
      final before = uids.count;

      uids.prune({});
      expect(uids.count, before, reason: 'dezelfde val als bij corrections.json');
    });

    test('a scan that saw the music does forget what it did not see', () {
      final a = _album(tracks);
      uids.reconcile([a]);

      uids.prune({'/m/1.flac', '/m/2.flac'});
      expect(uids.count, 2);
      expect(uids.uidOfPath('/m/6.flac'), isNull);
    });
  });

  /// The other half: what cannot be keyed on the uid, because two split pressings deliberately
  /// share it. Those keys are carried to the new name instead.
  group('what is filed under the album name', () {
    late LibraryStore lib;
    late AppSettings settings;

    setUp(() async {
      settings = AppSettings();
      lib = LibraryStore()..configDirOverride = scratch.path;
      lib.tracks.addAll(tracks);
      lib.rebuildAlbums();
    });

    test('hand-assigned scans, styles and a merge follow the rename', () async {
      await lib.setAlbumArtRole('Portishead', 'Dummy', 'back', 'http://x/back.jpg');
      await lib.rememberStyles('Portishead', 'Dummy', ['Trip Hop']);
      await lib.mergeEditions(lib.albums.first);

      await lib.applyCorrection(lib.albums.single, settings, artist: 'Portishead & Beth Gibbons');

      expect(lib.albumArtRoles('Portishead & Beth Gibbons', 'Dummy'),
          {'back': 'http://x/back.jpg'},
          reason: 'anders zijn de scans die je zelf toewees weg na een naamscorrectie');
      expect(lib.stylesOf(lib.albums.single), ['Trip Hop']);
      expect(lib.isMerged(lib.albums.single), isTrue,
          reason: 'anders biedt de app aan om een plaat samen te voegen die dat al is');
      expect(lib.albumArtRoles('Portishead', 'Dummy'), isEmpty);
    });

    test('and so does the cover the user picked by hand', () async {
      final mine = Uint8List.fromList(List<int>.filled(2000, 9));
      await lib.applyCorrection(lib.albums.single, settings, coverBytes: mine);

      await lib.applyCorrection(lib.albums.single, settings, artist: 'Portishead & Beth Gibbons');

      // Within the session the bytes ride along on the Album; the loss only showed at the next
      // start, when the lookup went to the new name and found nothing.
      final fresh = LibraryStore()..configDirOverride = scratch.path;
      fresh.tracks.addAll([
        for (final t in tracks) _t(t.path, artist: 'Portishead & Beth Gibbons', no: t.trackNo)
      ]);
      fresh.rebuildAlbums();
      await fresh.enrich(settings);
      expect(fresh.albums.single.cover, mine);
    });

    test('the uid comes along on a plain rebuild', () {
      final uid = lib.uidOf(lib.albums.single);
      expect(uid, isNotEmpty);
      lib.rebuildAlbums();
      expect(lib.uidOf(lib.albums.single), uid);
    });
  });
}
