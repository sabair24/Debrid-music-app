import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/organize.dart';

/// The file the metadata package refuses, and then never lets go of.
///
/// `readMetadata` opens the file before it decides which parser to use, and closes it only once a
/// parser has finished. When none recognises the bytes it throws with the handle still open. On
/// Windows that handle makes the file — and every folder above it — impossible to rename or
/// delete for the rest of the session: a move fails all its retries, falls back to copy, then
/// fails to delete the original and silently leaves a duplicate behind.
///
/// It cost two green-looking tests to find. These pin the guard that keeps such a file away from
/// the package in the first place, since the handle cannot be closed from outside it.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('dm_handle_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {/* the point of the test is that this works; failures are asserted, not here */}
  });

  File _junk(String name, [int n = 2048]) =>
      File('${dir.path}/$name')..writeAsBytesSync(List<int>.generate(n, (i) => i % 256));

  group('tagParserWouldClaim', () {
    test('says no to bytes no parser knows — and leaves nothing open', () {
      final f = _junk('01.flac');
      expect(tagParserWouldClaim(f), isFalse);
      // The whole point: after asking, the file is still ours to move.
      expect(() => f.deleteSync(), returnsNormally);
    });

    test('says yes to a real FLAC, so nothing readable is turned away', () {
      final real = File('test/fixtures/tone.flac');
      expect(real.existsSync(), isTrue, reason: 'fixture ontbreekt');
      expect(tagParserWouldClaim(real), isTrue);
      // And the package really does read it, so the guard is not merely agreeing with itself.
      expect(readMetadata(real, getImage: false).title, isNotNull);
    });

    test('recognises a container by its magic, not by its extension', () {
      // A FLAC named .mp3 is still a FLAC. Judging by extension would drop it from the library.
      final f = File('${dir.path}/mislabeled.mp3')
        ..writeAsBytesSync(File('test/fixtures/tone.flac').readAsBytesSync());
      expect(tagParserWouldClaim(f), isTrue);
    });

    test('a file too short to hold a header is refused without reading past its end', () {
      expect(tagParserWouldClaim(_junk('tiny.flac', 4)), isFalse);
      expect(tagParserWouldClaim(File('${dir.path}/leeg.flac')..createSync()), isFalse);
    });

    test('a file that is not there is a no, not a crash', () {
      expect(tagParserWouldClaim(File('${dir.path}/bestaat-niet.flac')), isFalse);
    });
  });

  group('the guard, at the call sites', () {
    test('a scan over unreadable files leaves the folder deletable', () async {
      // This is the exact shape that broke the LAN move tests: fixtures named .flac that are not
      // FLAC at all, scanned on the PC side, after which the temp folder could not be removed.
      _junk('01.flac');
      _junk('02.flac', 1024);
      _junk('03.mp3');

      final lib = LibraryStore()..rootPath = dir.path;
      await lib.scan();

      expect(() => dir.deleteSync(recursive: true), returnsNormally,
          reason: 'de scan houdt nog een bestand vast — precies het lek dat dit moest voorkomen');
      dir.createSync(); // tearDown deletes it again
    });

    test('readTags refuses a file rather than locking it in the staging folder', () {
      final f = _junk('download.m4a');
      expect(readTags(f), isNull);
      // A download that cannot be renamed out of staging is a download that never arrives.
      expect(() => f.renameSync('${dir.path}/verplaatst.m4a'), returnsNormally);
    });

    test('and still reads the tags of a file it can read', () {
      final f = File('${dir.path}/tone.flac')
        ..writeAsBytesSync(File('test/fixtures/tone.flac').readAsBytesSync());
      final tags = readTags(f);
      expect(tags, isNotNull);
      expect(tags!.title, isNotEmpty);
    });
  });
}
