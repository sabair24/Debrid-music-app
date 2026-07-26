/// The hand-made metadata, and what may be allowed to forget it.
///
/// `corrections.json` is the one file in this app that cannot be regenerated. Covers can be
/// fetched again, tracklists can be looked up again, the whole library can be rescanned — but what
/// the user typed exists nowhere else. It used to be pruned on load, by asking the filesystem
/// whether each path still existed and writing the survivors back. With the music drive not
/// mounted every path fails that question at the same moment, and the file is replaced by an empty
/// one before anything is on screen.
///
/// So these tests are mostly about what must NOT happen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/paths.dart';

void main() {
  late Directory scratch;
  late Directory music;
  late String cfg;
  late File corrections;

  /// A path under a root that is not there — what every entry looks like when a disk is unplugged.
  const gonePath = r'D:\Flac music 2024\Adele\30\01 Strangers By Nature.flac';
  const gonePath2 = r'D:\Flac music 2024\Adele\30\02 Easy On Me.flac';

  LibraryStore store() => LibraryStore()
    ..configDirOverride = cfg
    ..rootPath = music.path;

  Future<void> writeCorrections(Map<String, Map<String, String>> m) async {
    await Directory(cfg).create(recursive: true);
    await corrections.writeAsString(jsonEncode(m));
  }

  Map<String, dynamic> readCorrections() =>
      jsonDecode(corrections.readAsStringSync()) as Map<String, dynamic>;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_corr_');
    setAppDirForTest(scratch.path);
    cfg = '${scratch.path}${Platform.pathSeparator}_cfg';
    music = Directory('${scratch.path}${Platform.pathSeparator}music')..createSync();
    corrections = File('$cfg${Platform.pathSeparator}corrections.json');
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Put a real, tagged FLAC in the library so a scan has something to find.
  String plantTrack([String name = '01 Strangers By Nature.flac']) {
    final dest = File('${music.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(File('test/fixtures/tone.flac').readAsBytesSync());
    return dest.path;
  }

  group('a drive that is not there', () {
    test('loading keeps every correction and writes nothing back', () async {
      await writeCorrections({
        gonePath: {'artist': 'Adele', 'album': '30'},
        gonePath2: {'artist': 'Adele', 'album': '30', 'title': 'Easy on Me'},
      });
      final before = corrections.readAsStringSync();

      final lib = store();
      await lib.loadCorrections();

      expect(lib.correctionForTest(gonePath), {'artist': 'Adele', 'album': '30'},
          reason: 'de schijf is niet weg, hij is niet aangekoppeld');
      expect(lib.correctionForTest(gonePath2)?['title'], 'Easy on Me');
      expect(corrections.readAsStringSync(), before,
          reason: 'laden mag nooit schrijven — dat is precies hoe het bestand leeg raakte');
    });

    test('a scan that finds no music forgets nothing', () async {
      await writeCorrections({
        gonePath: {'artist': 'Adele', 'album': '30'},
      });

      final lib = store();
      await lib.loadCorrections();
      await lib.scan(); // empty root: the disk is not mounted

      expect(lib.tracks, isEmpty);
      expect(lib.correctionForTest(gonePath), isNotNull,
          reason: 'een lege bibliotheek is geen bewijs dat de muziek weg is');
      expect(readCorrections().keys, contains(gonePath));
    });

    test('and it survives a restart, which is when the damage used to show', () async {
      await writeCorrections({gonePath: {'artist': 'Adele', 'album': '30'}});

      for (var boot = 0; boot < 3; boot++) {
        final lib = store();
        await lib.loadCorrections();
        await lib.scan();
      }

      final fresh = store();
      await fresh.loadCorrections();
      expect(fresh.correctionForTest(gonePath)?['artist'], 'Adele');
    });
  });

  group('a file that really is gone', () {
    test('is marked rather than dropped, once music has actually been seen', () async {
      final live = plantTrack();
      await writeCorrections({
        gonePath: {'artist': 'Adele', 'album': '30'},
        live: {'artist': 'Adele'},
      });

      final lib = store();
      await lib.loadCorrections();
      await lib.scan();

      expect(lib.tracks, isNotEmpty, reason: 'deze scan moet wél muziek vinden');
      expect(lib.correctionForTest(gonePath)?['artist'], 'Adele',
          reason: 'de correctie blijft — hij krijgt alleen een datum mee');
      expect(lib.correctionForTest(gonePath)?['_gone'], isNotNull);
      expect(lib.correctionForTest(live)?['_gone'], isNull,
          reason: 'dit bestand is er gewoon');
    });

    test('is forgotten after the grace period, not before', () async {
      plantTrack();
      final old = DateTime.now().subtract(const Duration(days: 91)).millisecondsSinceEpoch;
      final recent = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      await writeCorrections({
        gonePath: {'artist': 'Adele', '_gone': '$old'},
        gonePath2: {'artist': 'Adele', '_gone': '$recent'},
      });

      final lib = store();
      await lib.loadCorrections();
      await lib.scan();

      expect(lib.correctionForTest(gonePath), isNull, reason: 'drie maanden weg is weg');
      expect(lib.correctionForTest(gonePath2)?['artist'], 'Adele', reason: 'een maand is niet weg');
      expect(readCorrections().keys, isNot(contains(gonePath)));
    });

    test('a file that comes back loses its mark', () async {
      final live = plantTrack();
      final marked = DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch;
      await writeCorrections({
        live: {'artist': 'Adele', '_gone': '$marked'},
      });

      final lib = store();
      await lib.loadCorrections();
      await lib.scan();

      expect(lib.correctionForTest(live)?['_gone'], isNull,
          reason: 'anders telt de klok door terwijl het bestand er weer is');
      expect(lib.correctionForTest(live)?['artist'], 'Adele');
    });

    test('the mark never reaches the track itself', () async {
      final live = plantTrack();
      await writeCorrections({
        live: {'artist': 'Adele', 'album': '30', 'title': 'Strangers by Nature'},
      });

      final lib = store();
      await lib.loadCorrections();
      await lib.scan();

      final t = lib.tracks.firstWhere((t) => t.path == live);
      expect(t.artist, 'Adele');
      expect(t.album, '30');
      expect(t.title, 'Strangers by Nature');
    });
  });

  group('removed from library only', () {
    test('hiding a track does not start the clock on what you typed about it', () async {
      final live = plantTrack();
      await writeCorrections({live: {'artist': 'Adele'}});

      final lib = store();
      await lib.loadCorrections();
      await lib.scan();
      await lib.removeTracks([live], fromDisk: false);
      await lib.scan();

      expect(lib.tracks.any((t) => t.path == live), isFalse, reason: 'wel verborgen');
      expect(lib.correctionForTest(live)?['_gone'], isNull,
          reason: '"verwijder uit bibliotheek" mag niet stiekem "vergeet mijn correctie" worden');
    });
  });
}
