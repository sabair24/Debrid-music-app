/// NOT a test — a stand-in PC, for looking at the Mac/iPad client by hand.
///
/// Run it, then start the app; it serves a small library of real FLACs on a fixed port with a
/// fixed token. Skipped unless FAKE_PC=1, so it never runs in CI.
///
///   FAKE_PC=1 flutter test test/fake_pc_test.dart
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/torbox.dart';
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

    // Canned online results and a download that crawls along, so the searching and downloading
    // screens on a Mac or an iPad can be tried by hand without a TorBox key.
    final settings = AppSettings();
    final online = _FakeOnline(settings);
    final soulseek = _FakeSoulseek(settings);
    final downloads = _FakeDownloads(online, soulseek, root.path, () async {});

    final server = LanServer(
      library: library,
      token: 'nep-pc-sleutel',
      state: LanStateStore(File('${root.path}/state.json')),
      pairing: PairingStore(),
      port: 47830,
      version: 'fake',
      online: online,
      soulseek: soulseek,
      downloads: downloads,
    );
    expect(await server.start(), isNull);
    // ignore: avoid_print
    print('FAKE PC op http://127.0.0.1:${server.boundPort} — token nep-pc-sleutel');
    await Future<void>.delayed(const Duration(minutes: 25));
    await server.dispose();
    root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 30)), skip: Platform.environment['FAKE_PC'] != '1');
}

class _FakeOnline extends OnlineService {
  _FakeOnline(super.settings);
  @override
  Future<List<SearchResult>> search(String query,
      {void Function(List<SearchResult>)? onPartial}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return [
      for (var i = 1; i <= 5; i++)
        SearchResult(
          name: '$query — bron $i [FLAC]',
          magnet: 'magnet:?xt=urn:btih:${'0' * 36}$i',
          hash: '${'0' * 36}$i',
          size: 300000000 + i * 1000000,
          seeders: 40 - i * 3,
          cached: i.isOdd,
          source: i.isOdd ? 'TorBox' : 'RuTracker',
        ),
    ];
  }
}

class _FakeSoulseek extends SoulseekService {
  _FakeSoulseek(super.settings);
  @override
  bool get available => true;
  @override
  Future<List<SoulseekFile>> search(String query,
      {void Function(List<SoulseekFile>)? onPartial}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return [
      for (var i = 1; i <= 4; i++)
        SoulseekFile(
          username: 'peer$i',
          filename: 'muziek\\$query\\0$i.flac',
          size: 30000000,
          bitrate: 1000,
          freeSlots: i.isOdd,
          queueLength: i,
        ),
    ];
  }
}

/// Runs a job that gets slowly further, so a progress bar on another device has something to do.
class _FakeDownloads extends DownloadManager {
  _FakeDownloads(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged);

  @override
  void enqueue(SearchResult result, {int? fileId}) => _run(result.name);

  @override
  Future<bool> enqueueSoulseekBest(List<SoulseekFile> candidates,
      {String? key, TrackTags? authority}) async {
    _run(candidates.first.filename, key: key);
    return true;
  }

  void _run(String name, {String? key}) {
    final job = DownloadJob(name, key: key)
      ..status = 'downloading'
      ..canCancel = true;
    jobs.insert(0, job);
    notifyListeners();
    Timer.periodic(const Duration(milliseconds: 700), (t) {
      if (job.cancelled) {
        job.status = 'failed';
        job.detail = 'gestopt';
        t.cancel();
      } else {
        job.progress += 0.05;
        if (job.progress >= 1) {
          job.progress = 1;
          job.status = 'done';
          t.cancel();
        }
      }
      notifyListeners();
    });
  }

  @override
  void cancelJob(DownloadJob job) {
    job.cancelled = true;
    notifyListeners();
  }
}
