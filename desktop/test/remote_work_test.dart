/// Searching and downloading from a device that does neither itself.
///
/// Over a real socket against a real [LanServer], because the whole point is that a Mac or an
/// iPad reaches the PC's TorBox key and Soulseek login without ever holding them. The services on
/// the PC are stubbed — this is about the wire and the plumbing, not about TorBox.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/remote_services.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/torbox.dart';

/// Stands in for the PC's TorBox side. Records what it was asked for, so the test can check that
/// the query actually crossed the network rather than being answered locally.
class FakeOnline extends OnlineService {
  FakeOnline(super.settings);

  final List<String> queries = [];
  List<SearchResult> answer = [];
  Object? failWith;

  @override
  Future<List<SearchResult>> search(String query,
      {void Function(List<SearchResult>)? onPartial}) async {
    queries.add(query);
    if (failWith != null) throw failWith!;
    return answer;
  }
}

class FakeSoulseek extends SoulseekService {
  FakeSoulseek(super.settings);

  final List<String> queries = [];
  List<SoulseekFile> answer = [];
  bool up = true;

  @override
  bool get available => up;

  @override
  Future<List<SoulseekFile>> search(String query,
      {void Function(List<SoulseekFile>)? onPartial,
      void Function(String)? gebruikteVraag}) async {
    queries.add(query);
    return answer;
  }
}

/// Stands in for the PC's downloader. Never touches the network or the disk.
class FakeDownloads extends DownloadManager {
  FakeDownloads(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged);

  final List<SearchResult> enqueued = [];
  final List<List<SoulseekFile>> slskEnqueued = [];
  final List<DownloadJob> cancelled = [];
  bool cleared = false;

  @override
  void enqueue(SearchResult result, {int? fileId, TbTorrent? klaar}) {
    enqueued.add(result);
    jobs.insert(0, DownloadJob(result.name, key: 'k${jobs.length}')..status = 'downloading');
    notifyListeners();
  }

  @override
  Future<bool> enqueueSoulseekBest(List<SoulseekFile> candidates,
      {String? key, TrackTags? authority, SoulseekFile? exact, bool wachtOpAfloop = true}) async {
    slskEnqueued.add(candidates);
    jobs.insert(0, DownloadJob(candidates.first.filename, key: key)..status = 'queued');
    notifyListeners();
    return true;
  }

  @override
  void cancelJob(DownloadJob job) => cancelled.add(job);

  @override
  void clearFinished() => cleared = true;
}

SearchResult _hit(String name, {String hash = 'abc', bool cached = true}) =>
    SearchResult(name: name, magnet: 'magnet:?xt=urn:btih:$hash', hash: hash, size: 123, seeders: 9, cached: cached);

SoulseekFile _peer(String file) =>
    SoulseekFile(username: 'iemand', filename: file, size: 4096, bitrate: 1000, freeSlots: true);

void main() {
  late Directory scratch;
  late FakeOnline online;
  late FakeSoulseek soulseek;
  late FakeDownloads downloads;
  late LanServer server;
  late RemoteEndpoint endpoint;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_work_');
    setAppDirForTest(scratch.path);
    final settings = AppSettings();
    final library = LibraryStore()
      ..rootPath = scratch.path
      ..configDirOverride = scratch.path;
    online = FakeOnline(settings);
    soulseek = FakeSoulseek(settings);
    downloads = FakeDownloads(online, soulseek, scratch.path, () async {});

    server = LanServer(
      library: library,
      token: 'sleutel',
      state: LanStateStore(File('${scratch.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      online: online,
      soulseek: soulseek,
      downloads: downloads,
    );
    expect(await server.start(), isNull);
    endpoint = RemoteEndpoint(
      baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'),
      token: 'sleutel',
    );
  });

  tearDown(() async {
    await server.dispose();
    scratch.deleteSync(recursive: true);
  });

  RemoteOnlineService remoteOnline() => RemoteOnlineService(AppSettings(), () => endpoint);
  RemoteSoulseekService remoteSoulseek() => RemoteSoulseekService(AppSettings(), () => endpoint);
  RemoteDownloadManager remoteDownloads() => RemoteDownloadManager(
      online, soulseek, scratch.path, () async {}, () => endpoint);

  group('searching on the PC', () {
    test('the query goes to the PC and the results come back whole', () async {
      online.answer = [_hit('Portishead - Dummy [FLAC]'), _hit('Portishead - Dummy [MP3]', hash: 'def')];
      final service = remoteOnline();

      final got = await service.search('portishead dummy');

      expect(online.queries, ['portishead dummy'], reason: 'de pc hoort de zoekopdracht te doen');
      expect(got.map((r) => r.name), [
        'Portishead - Dummy [FLAC]',
        'Portishead - Dummy [MP3]',
      ]);
      // The magnet and the cached flag are what a download needs; losing either silently turns a
      // one-click instant download into a torrent that never starts.
      expect(got.first.magnet, contains('urn:btih:abc'));
      expect(got.first.cached, isTrue);
      expect(got.first.seeders, 9);
      service.dispose();
    });

    test('the screens still get their partial callback', () async {
      online.answer = [_hit('iets')];
      final service = remoteOnline();
      var calls = 0;
      final got = await service.search('iets', onPartial: (partial) {
        calls++;
        expect(partial.length, 1);
      });
      expect(calls, 1, reason: 'de lijst moet gevuld worden, ook zonder stroom van tussenresultaten');
      expect(got.length, 1);
      service.dispose();
    });

    test('a failure on the PC arrives as a sentence, not a status code', () async {
      online.failWith = 'TorBox antwoordde niet';
      final service = remoteOnline();
      await expectLater(
        service.search('iets'),
        throwsA(isA<RemoteException>().having((e) => e.message, 'message', contains('TorBox'))),
      );
      service.dispose();
    });

    test('Soulseek is searched on the PC too', () async {
      soulseek.answer = [_peer(r'muziek\Portishead\01.flac')];
      final service = remoteSoulseek();
      final got = await service.search('portishead');
      expect(soulseek.queries, ['portishead']);
      expect(got.single.filename, r'muziek\Portishead\01.flac');
      expect(got.single.bitrate, 1000);
      service.dispose();
    });

    test('a PC without a Soulseek login says so', () async {
      soulseek.up = false;
      final service = remoteSoulseek();
      await expectLater(
        service.search('iets'),
        throwsA(isA<RemoteException>().having((e) => e.message, 'message', contains('Soulseek'))),
      );
      service.dispose();
    });
  });

  group('downloading, on the PC', () {
    test('a download started here runs there', () async {
      final manager = remoteDownloads();
      manager.enqueue(_hit('Portishead - Dummy [FLAC]'), fileId: 7);

      // enqueue returns immediately by design — the work is the PC's, and holding the request open
      // for a download would time out long before it finished.
      await _until(() => downloads.enqueued.isNotEmpty);
      expect(downloads.enqueued.single.name, 'Portishead - Dummy [FLAC]');
      expect(downloads.enqueued.single.hash, 'abc');

      await _until(() => manager.jobs.isNotEmpty);
      expect(manager.jobs.single.name, 'Portishead - Dummy [FLAC]');
      expect(manager.jobs.single.status, 'downloading');
      manager.dispose();
    });

    test('progress on the PC shows up here', () async {
      final manager = remoteDownloads();
      downloads.enqueue(_hit('Iets'));
      await manager.refresh();
      expect(manager.jobs.single.progress, 0);

      downloads.jobs.first
        ..progress = 0.42
        ..status = 'downloading'
        ..detail = 'poging 2/5 · peer';
      await manager.refresh();

      final job = manager.jobs.single;
      expect(job.progress, closeTo(0.42, 0.001));
      expect(job.detail, 'poging 2/5 · peer');
      manager.dispose();
    });

    test('a Soulseek download is handed over with its candidates', () async {
      final manager = remoteDownloads();
      final started = await manager.enqueueSoulseekBest(
        [_peer(r'a\1.flac'), _peer(r'b\1.flac')],
        key: 'portishead|mysterons',
      );
      expect(started, isTrue);
      expect(downloads.slskEnqueued.single.map((f) => f.filename), [r'a\1.flac', r'b\1.flac']);
      // The quality fields decide which peer the race prefers — they have to survive the trip.
      expect(downloads.slskEnqueued.single.first.bitrate, 1000);
      expect(downloads.slskEnqueued.single.first.freeSlots, isTrue);
      manager.dispose();
    });

    test('stopping and clearing reach the PC', () async {
      final manager = remoteDownloads();
      downloads.enqueue(_hit('Iets'));
      await manager.refresh();

      manager.cancelJob(manager.jobs.single);
      await _until(() => downloads.cancelled.isNotEmpty);
      expect(downloads.cancelled.single.name, 'Iets');

      manager.clearFinished();
      await _until(() => downloads.cleared);
      manager.dispose();
    });

    test('the list only wakes the UI when something moved', () async {
      final manager = remoteDownloads();
      downloads.enqueue(_hit('Iets'));
      await manager.refresh();

      var rebuilds = 0;
      manager.addListener(() => rebuilds++);
      await manager.refresh();
      await manager.refresh();
      expect(rebuilds, 0, reason: 'twee keer hetzelfde antwoord mag het scherm niet verversen');

      downloads.jobs.first.progress = 0.5;
      await manager.refresh();
      expect(rebuilds, 1);
      manager.dispose();
    });

    test('a PC that has gone away leaves the list alone and says why', () async {
      final manager = remoteDownloads();
      downloads.enqueue(_hit('Iets'));
      await manager.refresh();
      expect(manager.jobs.length, 1);

      await server.dispose();
      await manager.refresh();

      expect(manager.jobs.length, 1, reason: 'wat er stond blijft staan');
      expect(manager.lastError, isNotNull);
      manager.dispose();
    });
  });

  group('what a client cannot do', () {
    test('playing an online result straight through is refused, with a way forward', () async {
      final service = remoteOnline();
      expect(
        () => service.resolveStreamUrl(_hit('iets')),
        throwsA(isA<RemoteWorkException>().having((e) => e.message, 'message', contains('Download'))),
      );
      service.dispose();
    });

    test('radio skips an online track rather than failing the queue', () async {
      // Returning null is what the radio queue treats as "not found" — the local tracks in the
      // queue keep playing, which is the whole point.
      expect(await remoteOnline().resolveRadio('Portishead', 'Mysterons'), isNull);
    });

    test('nothing paired yet is a sentence, not a crash', () async {
      final service = RemoteOnlineService(AppSettings(), () => null);
      await expectLater(service.search('iets'), throwsA(isA<RemoteWorkException>()));
      service.dispose();
    });
  });

  group('a PC that cannot do the work', () {
    test('says so instead of pretending', () async {
      final bare = LanServer(
        library: LibraryStore()..configDirOverride = scratch.path,
        token: 'sleutel',
        state: LanStateStore(File('${scratch.path}/state2.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await bare.start(), isNull);
      final service = RemoteOnlineService(
        AppSettings(),
        () => RemoteEndpoint(
            baseUrl: Uri.parse('http://127.0.0.1:${bare.boundPort}'), token: 'sleutel'),
      );
      await expectLater(
        service.search('iets'),
        throwsA(isA<RemoteException>().having((e) => e.message, 'message', contains('niet online zoeken'))),
      );
      service.dispose();
      await bare.dispose();
    });
  });
}

/// The client fires and forgets on purpose, so the test waits for the effect rather than assuming
/// it has already happened.
Future<void> _until(bool Function() done, {Duration limit = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('wachtte tevergeefs op het effect');
}
