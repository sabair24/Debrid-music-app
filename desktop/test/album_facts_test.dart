/// Remembering what a record IS, instead of asking again.
///
/// The album page used to work out its pressing and tracklist on every single open — six
/// MusicBrainz requests at 1.1 s apart — and throw the result away when the page closed. Every
/// device did it separately, and a refusal was never remembered at all, so one outage meant paying
/// the full chain forever after.
///
/// Two things are tested here: that the answer survives the things that used to lose it (a rename,
/// a restart, a folder copied to another machine), and that the disk cost stays where it was
/// promised — one file at startup, never twelve thousand.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

Track _t(String path) => Track(path: path, title: 'x', artist: 'Portishead', album: 'Dummy');

AlbumFacts _facts(String uid, String hash, {int? failedMs, List<ChoiceTrack>? list}) => AlbumFacts(
      uid: uid,
      trackSetHash: hash,
      updatedMs: 1730000000000,
      source: 'MusicBrainz',
      mbid: 'e5f6-abc',
      tracklist: list ??
          const [
            ChoiceTrack('1', 'Mysterons', 306),
            ChoiceTrack('2', 'Sour Times', 254),
          ],
      bonus: const [BonusTrack(ChoiceTrack('13', 'Sheared Times', 240), 'CD · JP · 1994')],
      year: 1994,
      failedMs: failedMs,
    );

void main() {
  late Directory scratch;
  late AlbumFactsStore store;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_facts_');
    setAppDirForTest(scratch.path);
    store = AlbumFactsStore(dir: () => scratch.path);
  });

  tearDown(() {
    store.dispose();
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the answer survives', () {
    test('a restart', () async {
      store.put(_facts('uid1', 'h1'));
      await store.flush();

      final again = AlbumFactsStore(dir: () => scratch.path);
      await again.load();
      final f = again.get('uid1')!;
      expect(f.tracklist.map((t) => t.title), ['Mysterons', 'Sour Times']);
      expect(f.bonus.single.edition, 'CD · JP · 1994');
      expect(f.year, 1994);
      expect(f.mbid, 'e5f6-abc');
      again.dispose();
    });

    test('a rename — the uid does not move, so neither do the facts', () {
      store.put(_facts('uid1', 'h1'));
      // Renaming changes artist and title and nothing else. The key here is neither.
      expect(store.get('uid1')?.staleFor('h1'), isFalse);
    });

    test('but not a track being added — that is a different record', () {
      store.put(_facts('uid1', 'h1'));
      expect(store.get('uid1')!.staleFor('h2'), isTrue);
    });

    test('and not a schema bump — a wrong tracklist is worse than none', () async {
      final raw = _facts('uid1', 'h1').toJson()..['schema'] = kAlbumFactsSchema - 1;
      await File('${scratch.path}${Platform.pathSeparator}album_facts.json').writeAsString(
          jsonEncode({'facts': {'uid1': raw}, 'folders': const {}}));

      await store.load();
      expect(store.get('uid1'), isNull);
    });
  });

  group('remembering a refusal', () {
    test('an empty answer is kept, so the six requests are not paid again', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      store.put(AlbumFacts(uid: 'uid1', trackSetHash: 'h1', failedMs: now, updatedMs: now));

      final f = store.get('uid1')!;
      expect(f.isEmpty, isTrue);
      expect(f.retryDue(now), isFalse, reason: 'niet meteen opnieuw');
      expect(f.retryDue(now + const Duration(hours: 23).inMilliseconds), isFalse);
    });

    test('but it is tried again a day later', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      store.put(AlbumFacts(uid: 'uid1', trackSetHash: 'h1', failedMs: now, updatedMs: now));
      expect(store.get('uid1')!.retryDue(now + const Duration(hours: 25).inMilliseconds), isTrue);
    });

    test('a record that DID resolve is never on a retry timer', () {
      store.put(_facts('uid1', 'h1'));
      expect(store.get('uid1')!.retryDue(DateTime.now().millisecondsSinceEpoch), isFalse);
    });
  });

  group('one file at startup', () {
    test('five hundred albums are one read, not five hundred', () async {
      for (var i = 0; i < 500; i++) {
        store.put(_facts('uid$i', 'h$i'));
      }
      await store.flush();

      final files = scratch.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(files.single.path, endsWith('album_facts.json'));

      final again = AlbumFactsStore(dir: () => scratch.path);
      await again.load();
      expect(again.count, 500);
      again.dispose();
    });

    test('an unreadable index starts empty rather than throwing', () async {
      await File('${scratch.path}${Platform.pathSeparator}album_facts.json')
          .writeAsString('{niet eens json');
      await store.load();
      expect(store.count, 0);
    });
  });

  group('the sidecar next to the music', () {
    late Directory album;

    setUp(() {
      album = Directory('${scratch.path}${Platform.pathSeparator}Albums'
          '${Platform.pathSeparator}Portishead${Platform.pathSeparator}Dummy')
        ..createSync(recursive: true);
    });

    test('is written where the music is', () async {
      store.put(_facts('uid1', 'h1'), folder: album.path);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final side = File('${album.path}${Platform.pathSeparator}$kSidecarName');
      expect(side.existsSync(), isTrue);
      expect(jsonDecode(side.readAsStringSync())['mbid'], 'e5f6-abc');
    });

    test('is read for an album the index has never heard of', () async {
      store.put(_facts('uid1', 'h1'), folder: album.path);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // A reinstall, or this folder copied onto another machine: same music, empty index, and the
      // library will have minted its own uid for it.
      final elsewhere = AlbumFactsStore(dir: () => '${scratch.path}${Platform.pathSeparator}other');
      final found = await elsewhere.adoptSidecar('a-different-uid', album.path, 'h1');

      expect(found, isNotNull);
      expect(found!.tracklist.map((t) => t.title), ['Mysterons', 'Sour Times']);
      expect(found.uid, 'a-different-uid', reason: 'de uid van DEZE bibliotheek, niet die van gindse');
      elsewhere.dispose();
    });

    test('is ignored when the index already knows the album', () async {
      store.put(_facts('uid1', 'h1'), folder: album.path);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(await store.adoptSidecar('uid1', album.path, 'h1'), isNull,
          reason: 'staat het in de index, dan wint de index — geen klokken vergelijken');
    });

    test('is ignored when the album has changed since it was written', () async {
      store.put(_facts('uid1', 'h1'), folder: album.path);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final elsewhere = AlbumFactsStore(dir: () => '${scratch.path}${Platform.pathSeparator}other2');
      expect(await elsewhere.adoptSidecar('uid9', album.path, 'h-changed'), isNull);
      elsewhere.dispose();
    });

    test('a folder that cannot be written to is not an error', () async {
      final readonly = Directory('${scratch.path}${Platform.pathSeparator}ro')
        ..createSync();
      await Process.run('chmod', ['0555', readonly.path]);
      try {
        store.put(_facts('uid1', 'h1'), folder: readonly.path);
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(store.get('uid1'), isNotNull, reason: 'de index heeft alles nog');
        expect(store.sidecarsWritable, isFalse, reason: 'en probeert het niet nog 12.000 keer');
      } finally {
        await Process.run('chmod', ['0755', readonly.path]);
      }
    });
  });

  group('which folder a sidecar belongs in', () {
    Album al(List<String> paths) =>
        Album('Dummy', 'Portishead', [for (final p in paths) _t(p)]);

    test('the tidy tree is simply the album folder', () {
      final a = al([r'D:\M\Albums\Portishead\Dummy\01.flac', r'D:\M\Albums\Portishead\Dummy\02.flac']);
      expect(albumFolderOf(a, albumsPerDirOf([a])), r'D:\M\Albums\Portishead\Dummy');
    });

    test('a stray track elsewhere does not stop it', () {
      final a = al([
        for (var i = 1; i <= 9; i++) r'D:\M\Albums\Portishead\Dummy\0$i.flac'.replaceAll(r'$i', '$i'),
        r'D:\M\Elders\bonus.flac',
      ]);
      expect(albumFolderOf(a, albumsPerDirOf([a])), r'D:\M\Albums\Portishead\Dummy');
    });

    test('tracks scattered over folders get no sidecar', () {
      final a = al([r'D:\A\1.flac', r'D:\B\2.flac', r'D:\C\3.flac', r'D:\D\4.flac']);
      expect(albumFolderOf(a, albumsPerDirOf([a])), isNull);
    });

    test('a flat dump gets no sidecar — the albums would overwrite each other', () {
      final a = al([r'D:\Muziek\a1.flac', r'D:\Muziek\a2.flac']);
      final b = Album('Third', 'Portishead', [_t(r'D:\Muziek\b1.flac')]);
      final perDir = albumsPerDirOf([a, b]);

      expect(albumFolderOf(a, perDir), isNull);
      expect(albumFolderOf(b, perDir), isNull);
    });
  });

  /// The decision itself: ask, or answer from memory. This is what the album page runs before it
  /// paints, and every "true" here is six MusicBrainz requests at 1.1 s apart.
  group('when to go and ask', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final known = _facts('uid1', 'h1');

    test('a second visit asks nothing', () {
      expect(needsResolve(known, trackSetHash: 'h1', nowMs: now), isFalse);
    });

    test('a first visit asks', () {
      expect(needsResolve(null, trackSetHash: 'h1', nowMs: now), isTrue);
    });

    test('a rename asks nothing — no file moved', () {
      // A rename produces a new Album object with a new title and the same files. The hash is over
      // the files, so it is unchanged, and this is the case that used to cost six requests.
      expect(needsResolve(known, trackSetHash: 'h1', nowMs: now), isFalse);
    });

    test('a track added asks again', () {
      expect(needsResolve(known, trackSetHash: 'h2', nowMs: now), isTrue);
    });

    test('picking a different pressing asks again, though no file changed', () {
      expect(needsResolve(known, trackSetHash: 'h1', nowMs: now, pinnedMbid: 'another-mbid'),
          isTrue);
      expect(needsResolve(known, trackSetHash: 'h1', nowMs: now, pinnedMbid: 'e5f6-abc'), isFalse,
          reason: 'de persing die er al beschreven staat is geen reden om opnieuw te zoeken');
    });

    test('a Discogs pin behaves the same way', () {
      expect(needsResolve(known, trackSetHash: 'h1', nowMs: now, pinned: 12345), isTrue);
    });

    test('the refresh button asks whatever we know', () {
      expect(needsResolve(known, trackSetHash: 'h1', nowMs: now, force: true), isTrue);
    });

    test('a remembered failure waits a day, then asks', () {
      final failed = AlbumFacts(uid: 'uid1', trackSetHash: 'h1', failedMs: now);
      expect(needsResolve(failed, trackSetHash: 'h1', nowMs: now + 60000), isFalse,
          reason: 'één storing mag niet elke opening zes verzoeken kosten');
      expect(
          needsResolve(failed,
              trackSetHash: 'h1', nowMs: now + const Duration(hours: 25).inMilliseconds),
          isTrue);
    });
  });

  group('what counts as the same record', () {
    test('moving the folder does not change the hash', () {
      final before = [_t(r'D:\M\Dummy\01.flac'), _t(r'D:\M\Dummy\02.flac')];
      final after = [_t(r'E:\Muziek\Albums\Portishead\Dummy\01.flac'),
                     _t(r'E:\Muziek\Albums\Portishead\Dummy\02.flac')];
      expect(trackSetHashOf(after), trackSetHashOf(before),
          reason: 'een map verhuizen maakt er geen andere plaat van');
    });

    test('adding a track does', () {
      final before = [_t('/m/01.flac'), _t('/m/02.flac')];
      expect(trackSetHashOf([...before, _t('/m/03.flac')]), isNot(trackSetHashOf(before)));
    });

    test('the order the files are listed in does not', () {
      final a = [_t('/m/01.flac'), _t('/m/02.flac'), _t('/m/03.flac')];
      expect(trackSetHashOf(a.reversed), trackSetHashOf(a));
    });

    test('two files whose names run together are not one file', () {
      expect(trackSetHashOf([_t('/m/ab.flac'), _t('/m/c.flac')]),
          isNot(trackSetHashOf([_t('/m/a.flac'), _t('/m/bc.flac')])));
    });
  });
}
