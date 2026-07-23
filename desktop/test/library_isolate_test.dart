import 'dart:async';
import 'dart:io';

import 'package:debridmusic/library.dart';
import 'package:flutter_test/flutter_test.dart';

/// A regression test for a scan that silently found nothing.
///
/// `LibraryStore.scan()` hands the work to another isolate. When the closure doing that was
/// created inside the method, it carried the enclosing context — `this`, and the async method's
/// own completer — along with it. As soon as a widget attached a listener to the store that
/// context became unsendable, `Isolate.run` threw, the catch swallowed it, and the app started
/// with an empty library while the music sat untouched on disk. Nothing in the UI said so.
///
/// The app ALWAYS has listeners attached by the time it scans, so this is the real case; a scan
/// with none, which is what a naive test does, passes either way and proves nothing.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('debridmusic_scan_');
    final album = Directory('${root.path}/Portishead/Dummy')..createSync(recursive: true);
    _writeFlac(File('${album.path}/01 Mysterons.flac'),
        title: 'Mysterons', artist: 'Portishead', album: 'Dummy', trackNo: 1);
    _writeFlac(File('${album.path}/02 Sour Times.flac'),
        title: 'Sour Times', artist: 'Portishead', album: 'Dummy', trackNo: 2);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('a scan still finds the music once listeners are attached', () async {
    final library = LibraryStore()..rootPath = root.path;
    // The shape of a widget's rebuild callback: a closure over something unsendable.
    final completer = Completer<void>();
    library.addListener(() {
      if (completer.isCompleted) return;
    });

    await library.scan();

    expect(library.tracks, hasLength(2), reason: 'the scan came back empty with a listener attached');
    expect(library.albums, hasLength(1));
    expect(library.albums.single.title, 'Dummy');
  });

  test('and reads the format details the cast path depends on', () async {
    final library = LibraryStore()..rootPath = root.path;
    library.addListener(() {});
    await library.scan();

    final track = library.tracks.first;
    // Without a sample rate there is no way to know a track is beyond what Sonos accepts, and
    // it would be sent anyway — where it is silently skipped rather than refused.
    expect(track.sampleRate, 44100);
    expect(track.bitsPerSample, 16);
  });
}

/// A minimal but genuine FLAC: a real STREAMINFO block and a real Vorbis comment, so the app's
/// own reader parses it the way it parses the library.
void _writeFlac(
  File file, {
  required String title,
  required String artist,
  required String album,
  required int trackNo,
  int sampleRate = 44100,
  int bitsPerSample = 16,
  int seconds = 180,
}) {
  final streamInfo = List<int>.filled(34, 0);
  // Bytes 10-17 pack: 20 bits sample rate, 3 bits (channels-1), 5 bits (bits-per-sample-1),
  // then 36 bits of total sample count.
  final packed = (BigInt.from(sampleRate) << 44) |
      (BigInt.from(1) << 41) |
      (BigInt.from(bitsPerSample - 1) << 36) |
      BigInt.from(sampleRate * seconds);
  for (var i = 0; i < 8; i++) {
    streamInfo[10 + i] = ((packed >> ((7 - i) * 8)) & BigInt.from(0xFF)).toInt();
  }

  final comment = <int>[];
  void u32(int v) => comment.addAll([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  const vendor = 'test';
  u32(vendor.length);
  comment.addAll(vendor.codeUnits);
  final fields = [
    'TITLE=$title',
    'ARTIST=$artist',
    'ALBUM=$album',
    'TRACKNUMBER=$trackNo',
    'TRACKTOTAL=2',
    'DATE=1994',
  ];
  u32(fields.length);
  for (final f in fields) {
    u32(f.length);
    comment.addAll(f.codeUnits);
  }

  final out = <int>[...'fLaC'.codeUnits];
  out
    ..addAll([0, 0, 0, streamInfo.length]) // STREAMINFO, not the last block
    ..addAll(streamInfo)
    ..addAll([0x80 | 4, (comment.length >> 16) & 0xFF, (comment.length >> 8) & 0xFF, comment.length & 0xFF])
    ..addAll(comment)
    ..addAll(List<int>.filled(2048, 0)); // stand-in for the audio frames
  file.writeAsBytesSync(out);
}
