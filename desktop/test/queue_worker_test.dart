/// Downloads chosen while the PC was off.
///
/// Against a fake backend and a fake clock, because the rules worth testing are about time: how
/// long a claim is held, when a lease expires, how often progress may be written. A test that
/// waited five real minutes for a lease is a test nobody runs.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/cloud/queue.dart';
import 'package:debridmusic/cloud/queue_worker.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/torbox.dart';

class FakeQueue implements QueueBackend {
  final Map<String, QueueItem> items = {};
  int writes = 0;

  @override
  Future<List<QueueItem>> list() async =>
      items.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  @override
  Future<QueueItem?> get(String id) async => items[id];

  @override
  Future<void> put(QueueItem item) async {
    writes++;
    items[item.id] = item;
  }

  @override
  Future<void> patch(String id, Map<String, dynamic> fields) async {
    writes++;
    final item = items[id];
    if (item == null) return;
    if (fields.containsKey('status')) item.status = '${fields['status']}';
    if (fields.containsKey('claimedBy')) item.claimedBy = fields['claimedBy'] as String?;
    if (fields.containsKey('leaseUntil')) item.leaseUntil = fields['leaseUntil'] as DateTime?;
    if (fields.containsKey('progress')) item.progress = (fields['progress'] as num).toDouble();
    if (fields.containsKey('detail')) item.detail = fields['detail'] as String?;
    if (fields.containsKey('attempts')) item.attempts = (fields['attempts'] as num).toInt();
  }

  @override
  Future<void> remove(String id) async => items.remove(id);
}

/// Records what it was asked to download, and lets a test drive the job's progress.
class FakeDownloads extends DownloadManager {
  FakeDownloads(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged);

  final List<SearchResult> torrents = [];
  final List<List<SoulseekFile>> slsk = [];
  final List<String?> keys = [];
  final List<TrackTags?> authorities = [];

  @override
  void enqueue(SearchResult result, {int? fileId, TbTorrent? klaar}) {
    torrents.add(result);
    jobs.insert(0, DownloadJob(result.name)..status = 'downloading');
  }

  @override
  Future<bool> enqueueSoulseekBest(List<SoulseekFile> candidates,
      {String? key,
      TrackTags? authority,
      SoulseekFile? exact,
      bool jouwKeuze = false,
      bool wachtOpAfloop = true}) async {
    if (candidates.isEmpty) return false;
    // Mirrors the real guard: the same recording, already running, is not started twice.
    final track = authority == null ? '' : '${authority.artist}|${authority.title}';
    if (track.isNotEmpty && jobs.any((j) => j.busy && j.trackKey == track)) return false;
    slsk.add(candidates);
    keys.add(key);
    authorities.add(authority);
    jobs.insert(0, DownloadJob(candidates.first.filename, key: key)
      ..status = 'downloading'
      ..trackKey = track.isEmpty ? null : track);
    return true;
  }
}

SoulseekFile _peer(String file) =>
    SoulseekFile(username: 'iemand', filename: file, size: 4096, bitrate: 1000);

void main() {
  late Directory scratch;
  late FakeQueue queue;
  late FakeDownloads downloads;
  late LanServer server;
  late DateTime clock;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_queue_');
    setAppDirForTest(scratch.path);
    clock = DateTime.utc(2026, 7, 25, 12);
    queue = FakeQueue();
    final settings = AppSettings();
    final library = LibraryStore()..configDirOverride = scratch.path;
    downloads = FakeDownloads(
        OnlineService(settings), SoulseekService(settings), scratch.path, () async {});
    server = LanServer(
      library: library,
      token: 't',
      state: LanStateStore(File('${scratch.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      downloads: downloads,
      settings: settings,
    );
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  QueueWorker worker({String id = 'pc-1'}) => QueueWorker(
        backend: queue,
        server: server,
        downloads: downloads,
        workerId: id,
        now: () => clock,
      );

  QueueItem soulseekItem({String id = 'a'}) => QueueItem(
        id: id,
        kind: QueueKind.soulseek,
        title: 'Mysterons',
        payload: {
          'candidates': [_peer(r'muziek\01.flac').toJson()],
          'key': 'portishead|mysterons',
          'authority': const TrackTags(
            title: 'Mysterons',
            artist: 'Portishead',
            album: 'Dummy',
            trackNo: 1,
          ).toJson(),
        },
      );

  group('picking work up', () {
    test('a queued item is claimed and handed to the real downloader', () async {
      await queue.put(soulseekItem());
      await worker().tick();

      // Straight into DownloadManager, with the authority intact — that is what decides the track
      // number and the folder, and losing it files the track under the uploader's own tags.
      expect(downloads.slsk.single.single.filename, r'muziek\01.flac');
      // The key becomes the QUEUE ID, so the running job can be found again to report progress
      // against the right row. The payload's own key is not what identifies it here.
      expect(downloads.keys.single, 'a');
      expect(downloads.authorities.single?.album, 'Dummy');

      final item = queue.items['a']!;
      expect(item.status, QueueStatus.running);
      expect(item.claimedBy, 'pc-1');
      expect(item.leaseUntil, clock.add(kQueueLease));
    });

    test('overriding the key does not cost duplicate protection', () async {
      // The queue id replaces the payload's key, so the guard that matters is the OTHER one:
      // trackKey, built from the authority's artist, title and duration. Two queue items for the
      // same recording must still produce one download.
      await queue.put(soulseekItem(id: 'a'));
      await queue.put(soulseekItem(id: 'b'));
      final w = worker();
      await w.tick();

      expect(downloads.slsk.length, 1,
          reason: 'hetzelfde nummer twee keer in de wachtrij is één download');
      // The second is refused by the downloader, and says so rather than sitting at "queued".
      expect(queue.items['b']!.status, QueueStatus.failed);
    });

    test('a torrent request replays the body the route would have taken', () async {
      await queue.put(QueueItem(
        id: 'b',
        kind: QueueKind.torrent,
        title: 'Portishead - Dummy',
        payload: {
          'name': 'Portishead - Dummy [FLAC]',
          'magnet': 'magnet:?xt=urn:btih:abc',
          'hash': 'abc',
          'cached': true,
          'fileId': 7,
        },
      ));
      await worker().tick();

      expect(downloads.torrents.single.name, 'Portishead - Dummy [FLAC]');
      expect(downloads.torrents.single.hash, 'abc');
      expect(downloads.torrents.single.cached, isTrue);
    });

    test('two PCs racing the same item produce one download', () async {
      await queue.put(soulseekItem());
      // Both see it as free and both write a claim; only the one whose id survives the read runs.
      await Future.wait([worker(id: 'pc-1').tick(), worker(id: 'pc-2').tick()]);
      expect(downloads.slsk.length, 1);
    });

    test('an item nobody can use fails with a reason, rather than being retried for ever', () async {
      await queue.put(QueueItem(
        id: 'c',
        kind: QueueKind.soulseek,
        title: 'Leeg',
        payload: const {'candidates': []},
      ));
      await worker().tick();

      final item = queue.items['c']!;
      expect(item.status, QueueStatus.failed);
      expect(item.detail, contains('niets bruikbaars'));
      expect(item.claimedBy, isNull);
    });

    test('a finished item is left alone', () async {
      await queue.put(soulseekItem()..status = QueueStatus.done);
      await worker().tick();
      expect(downloads.slsk, isEmpty);
    });
  });

  group('leases', () {
    test('an item another PC is holding is left alone', () async {
      await queue.put(soulseekItem()
        ..status = QueueStatus.running
        ..claimedBy = 'pc-2'
        ..leaseUntil = clock.add(const Duration(minutes: 4)));
      await worker().tick();
      expect(downloads.slsk, isEmpty, reason: 'de lease van de ander loopt nog');
    });

    test('an expired lease is reclaimable — a PC unplugged mid-download is not for ever', () async {
      await queue.put(soulseekItem()
        ..status = QueueStatus.running
        ..claimedBy = 'pc-2'
        ..leaseUntil = clock.subtract(const Duration(seconds: 1)));
      await worker().tick();

      expect(downloads.slsk.length, 1);
      expect(queue.items['a']!.claimedBy, 'pc-1');
      expect(queue.items['a']!.attempts, 1);
    });
  });

  group('reporting back', () {
    test('progress reaches the queue, but not on every tick', () async {
      await queue.put(soulseekItem());
      final w = worker();
      await w.tick();
      final afterClaim = queue.writes;

      // Same numbers again: nothing worth a write. This is what keeps a free tier free —
      // DownloadManager notifies several times a second.
      await w.tick();
      await w.tick();
      expect(queue.writes, afterClaim, reason: 'ongewijzigde voortgang mag niets kosten');

      // Moved, but too soon.
      downloads.jobs.first.progress = 0.5;
      await w.tick();
      expect(queue.writes, afterClaim);

      // Moved, and enough time has passed.
      clock = clock.add(kProgressInterval + const Duration(seconds: 1));
      await w.tick();
      expect(queue.writes, greaterThan(afterClaim));
      expect(queue.items['a']!.progress, closeTo(0.5, 0.001));
    });

    test('finishing is written immediately, however little the number moved', () async {
      await queue.put(soulseekItem());
      final w = worker();
      await w.tick();

      downloads.jobs.first
        ..status = 'done'
        ..progress = 1.0;
      // No clock advance: a state change beats the throttle, because "it is finished" is the one
      // update nobody wants to wait five seconds for.
      await w.tick();

      final item = queue.items['a']!;
      expect(item.status, QueueStatus.done);
      expect(item.claimedBy, isNull, reason: 'klaar betekent niet meer vastgehouden');
    });

    test('a failed download says so instead of looking finished', () async {
      await queue.put(soulseekItem());
      final w = worker();
      await w.tick();

      downloads.jobs.first
        ..status = 'failed'
        ..detail = 'geen enkele peer had het';
      await w.tick();

      expect(queue.items['a']!.status, QueueStatus.failed);
      expect(queue.items['a']!.detail, 'geen enkele peer had het');
    });

    test('a job that vanished from the list counts as done', () async {
      await queue.put(soulseekItem());
      final w = worker();
      await w.tick();

      // What a completed download looks like after the list is tidied: the album is in the
      // library, and the job is gone.
      downloads.jobs.clear();
      await w.tick();

      expect(queue.items['a']!.status, QueueStatus.done);
      expect(queue.items['a']!.progress, 1.0);
    });
  });
}
