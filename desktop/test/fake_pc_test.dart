/// NOT a test — a stand-in PC, for looking at the Mac/iPad client by hand.
///
/// Run it, then start the app; it serves a small library of real FLACs on a fixed port with a
/// fixed token. Skipped unless FAKE_PC=1, so it never runs in CI.
///
///   FAKE_PC=1 flutter test test/fake_pc_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

void main() {
  test('serve a fake library', () async {
    final source = Platform.environment['FAKE_PC_FLAC'] ?? '';
    final root = Directory.systemTemp.createTempSync('fake_pc_');
    final albumDir = Directory('${root.path}/Portishead/Dummy')..createSync(recursive: true);

    final titles = ['Mysterons', 'Sour Times', 'Strangers', 'It Could Be Sweet'];
    final library = LibraryStore()
      ..rootPath = root.path
      ..configDirOverride = root.path;

    for (var i = 0; i < titles.length; i++) {
      final f = File('${albumDir.path}/${i + 1} ${titles[i]}.flac');
      f.writeAsBytesSync(File(source).readAsBytesSync());
      library.tracks.add(Track(
        path: f.path,
        title: titles[i],
        artist: 'Portishead',
        album: 'Dummy',
        trackNo: i + 1,
        trackTotal: titles.length,
        duration: const Duration(seconds: 8),
        isFlac: true,
        sizeBytes: f.lengthSync(),
        sampleRate: i.isEven ? 44100 : 96000,
        bitsPerSample: i.isEven ? 16 : 24,
        year: 1994,
        genre: 'Trip Hop',
        addedMs: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    library.tracks.add(Track(
      path: '${root.path}/los.flac',
      title: 'Teardrop',
      artist: 'Massive Attack',
      album: '',
      isFlac: true,
      duration: const Duration(seconds: 8),
    ));
    File('${root.path}/los.flac').writeAsBytesSync(File(source).readAsBytesSync());
    library.rebuildAlbums();

    final server = LanServer(
      library: library,
      token: 'nep-pc-sleutel',
      state: LanStateStore(File('${root.path}/state.json')),
      pairing: PairingStore(),
      port: 47830,
      version: 'fake',
    );
    expect(await server.start(), isNull);
    // ignore: avoid_print
    print('FAKE PC op http://127.0.0.1:${server.boundPort} — token nep-pc-sleutel');
    await Future<void>.delayed(const Duration(minutes: 25));
    await server.dispose();
    root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 30)), skip: Platform.environment['FAKE_PC'] != '1');
}
