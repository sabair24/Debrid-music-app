/// Music kept on the device.
///
/// Against a fake server over a real socket, because the parts worth testing are the ones that
/// only go wrong halfway: a download that is interrupted, a file that disappeared from under the
/// index, a cancel while bytes are still arriving. A copy that plays a truncated file is worse
/// than no copy at all — it sounds like the track is broken.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/offline.dart';
import 'package:debridmusic/paths.dart';

/// A stand-in for the PC's /stream route. Serves [bytes], and can be told to hang up halfway.
class FakeServer {
  FakeServer(this.bytes);
  final List<int> bytes;
  HttpServer? _server;

  /// Close the connection after this many bytes instead of finishing.
  int? cutAfter;

  /// How long to wait between chunks, so a test can cancel mid-flight.
  Duration chunkDelay = Duration.zero;

  int requests = 0;

  Future<Uri> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen((req) async {
      requests++;
      final cut = cutAfter;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType('audio', 'flac');
      // Promised in full even when the connection is about to drop — that is what a real server
      // does, and it is the only thing that makes a truncated download detectable.
      req.response.contentLength = bytes.length;
      var sent = 0;
      for (var i = 0; i < bytes.length; i += 64) {
        final end = (i + 64).clamp(0, bytes.length);
        if (cut != null && sent >= cut) break;
        req.response.add(bytes.sublist(i, end));
        sent += end - i;
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      }
      if (cut != null) {
        // What a dropped connection looks like: bytes, then nothing.
        await req.response.close().catchError((_) {});
        return;
      }
      await req.response.close();
    });
    return Uri.parse('http://${s.address.address}:${s.port}/stream/x.flac');
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  late Directory scratch;
  late OfflineStore store;
  late FakeServer server;
  late Uri url;

  // Big enough that it arrives in many chunks, which is what the throttling and the cancel path
  // are about.
  final payload = List<int>.generate(20000, (i) => i % 256);

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_offline_');
    setAppDirForTest(scratch.path);
    store = OfflineStore();
    await store.load();
    server = FakeServer(payload);
    url = await server.start();
  });

  tearDown(() async {
    await server.stop();
    store.dispose();
    // Windows keeps a handle for a moment after the last close, so a straight delete failed with
    // "the process cannot access the file" — but only when the suite ran under load, which is the
    // worst kind of red: one that never reproduces on its own. Retry briefly, then let it go; a
    // leftover temp folder is not worth failing a test that has already made its point.
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        scratch.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  const path = r'D:\Flac music 2024\Adele\30\01 Strangers By Nature.flac';

  Future<bool> download() => store.download(
        libraryPath: path,
        url: url.toString(),
        title: 'Strangers By Nature',
        artist: 'Adele',
        album: '30',
      );

  group('a copy on this device', () {
    test('the bytes arrive whole and the player is pointed at them', () async {
      expect(await download(), isTrue);

      final local = store.localFor(path);
      expect(local, isNotNull);
      expect(File(local!).readAsBytesSync(), payload,
          reason: 'een halve kopie klinkt als een kapot nummer, niet als een fout');
      expect(store.bytes, payload.length);
      expect(store.has(path), isTrue);
    });

    test('the file keeps the extension, because that is how a player knows the format', () async {
      await download();
      // libmpv and AVFoundation both decide from the extension before reading a byte.
      expect(store.localFor(path), endsWith('.flac'));
    });

    test('it survives a restart', () async {
      await download();

      final second = OfflineStore();
      await second.load();
      expect(second.localFor(path), isNotNull);
      expect(second.bytes, payload.length);
      second.dispose();
    });

    test('the same track is not fetched twice', () async {
      await download();
      await download();
      expect(server.requests, 1);
    });
  });

  group('half a copy is no copy', () {
    test('a dropped connection leaves nothing behind', () async {
      server.cutAfter = 5000;
      await download();

      // Not merely absent from the index: no stray part-file either, or the next attempt would
      // find a name it thinks it already has.
      expect(store.has(path), isFalse);
      expect(store.localFor(path), isNull);
      final files = Directory('${scratch.path}/offline').listSync();
      expect(files, isEmpty, reason: 'een .part van een mislukte poging hoort opgeruimd te zijn');
    });

    test('a file that vanished stops being offered', () async {
      await download();
      final local = store.localFor(path)!;
      // Android reclaims an app's files under storage pressure without telling anybody.
      File(local).deleteSync();

      expect(store.localFor(path), isNull,
          reason: 'anders krijgt libmpv een pad naar niets en weigert het nummer zonder uitleg');
      expect(store.has(path), isFalse);
    });

    test('cancelling mid-download leaves nothing behind', () async {
      server.chunkDelay = const Duration(milliseconds: 2);
      final running = download();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      store.cancel(path);

      expect(await running, isFalse);
      expect(store.has(path), isFalse);
      expect(Directory('${scratch.path}/offline').listSync(), isEmpty);
    });
  });

  group('removing a copy is not deleting the track', () {
    test('remove takes the bytes and leaves the index consistent', () async {
      await download();
      final local = store.localFor(path)!;

      await store.remove(path);

      expect(File(local).existsSync(), isFalse);
      expect(store.has(path), isFalse);
      expect(store.bytes, 0);

      // And it can be fetched again — removing a copy says nothing about the PC's file.
      expect(await download(), isTrue);
      expect(store.localFor(path), isNotNull);
    });

    test('clear empties the folder', () async {
      await download();
      await store.clear();
      expect(store.tracks, isEmpty);
      expect(Directory('${scratch.path}/offline').listSync(), isEmpty);
    });
  });

  group('what the screen is told', () {
    test('progress moves, and not on every chunk', () async {
      server.chunkDelay = const Duration(milliseconds: 1);
      var notifications = 0;
      store.addListener(() => notifications++);

      await download();

      // 20000 bytes in 64-byte chunks is 313 of them. Reporting each would rebuild the downloads
      // screen 313 times for one track.
      expect(notifications, lessThan(70),
          reason: 'de voortgang mag alleen melden als de balk zichtbaar beweegt');
      expect(notifications, greaterThan(2), reason: 'maar hij moet wel bewegen');
    });

    test('a track being fetched is busy, and afterwards it is not', () async {
      server.chunkDelay = const Duration(milliseconds: 2);
      final running = download();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.isBusy(path), isTrue);

      await running;
      expect(store.isBusy(path), isFalse);
      expect(store.has(path), isTrue);
    });
  });
}
