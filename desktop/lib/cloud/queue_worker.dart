/// The PC working through what was chosen while it was off.
///
/// Deliberately thin. It claims an item, hands the payload to the same `LanServer` methods a live
/// request would have reached, and reports back. Everything about *how* a download runs — the peer
/// race, the fallbacks, the filing — belongs to `DownloadManager` and is not repeated here.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../lan/server.dart';
import '../online.dart';
import 'queue.dart';

class QueueWorker {
  QueueWorker({
    required this.backend,
    required this.server,
    required this.downloads,
    required this.workerId,
    this.now = DateTime.now,
  });

  final QueueBackend backend;
  final LanServer server;
  final DownloadManager downloads;

  /// Which PC this is. Written into the claim so a second machine can see the item is taken.
  final String workerId;

  /// Injectable so the lease and throttle rules can be tested without waiting minutes.
  final DateTime Function() now;

  Timer? _poll;

  /// Last progress written per item, so the throttle has something to compare against.
  final Map<String, ({DateTime at, double progress, String status})> _lastReport = {};

  /// Items this worker is running, by queue id.
  final Set<String> _running = {};

  /// Items whose job has actually been observed at least once.
  final Set<String> _seen = {};

  void start({Duration every = const Duration(seconds: 20)}) {
    _poll?.cancel();
    unawaited(tick());
    _poll = Timer.periodic(every, (_) => unawaited(tick()));
  }

  void stop() {
    _poll?.cancel();
    _poll = null;
  }

  /// One pass: pick up anything free, then report on anything running.
  Future<void> tick() async {
    try {
      final items = await backend.list();
      for (final item in items) {
        if (_running.contains(item.id)) continue;
        if (item.isFinished) continue;
        if (!item.claimableAt(now())) continue;
        await _claimAndRun(item);
      }
      await _reportRunning(items);
    } catch (e) {
      // A queue that cannot be reached is not a PC that cannot serve music. Say it once.
      debugPrint('Queue tick failed: $e');
    }
  }

  Future<void> _claimAndRun(QueueItem item) async {
    // Claim by writing, then read back. Firestore's REST API has no transaction in this client, so
    // the check is optimistic: two PCs may both write, but only the one whose id survives the read
    // proceeds. Losing the race costs a wasted write, not a duplicate download.
    final claimedAt = now();
    await backend.patch(item.id, {
      'status': QueueStatus.claimed,
      'claimedBy': workerId,
      'leaseUntil': claimedAt.add(kQueueLease),
      'attempts': item.attempts + 1,
    });

    final confirmed = await backend.get(item.id);
    if (confirmed == null || confirmed.claimedBy != workerId) {
      // Somebody else got there. Theirs to finish.
      return;
    }

    _running.add(item.id);
    try {
      final started = await _replay(item);
      if (!started) {
        await backend.patch(item.id, {
          'status': QueueStatus.failed,
          'detail': 'De pc kon hier niets bruikbaars in vinden.',
          'claimedBy': null,
        });
        _running.remove(item.id);
        return;
      }
      await backend.patch(item.id, {
        'status': QueueStatus.running,
        'leaseUntil': now().add(kQueueLease),
      });
    } catch (e) {
      await backend.patch(item.id, {
        'status': QueueStatus.failed,
        'detail': '$e',
        'claimedBy': null,
      });
      _running.remove(item.id);
    }
  }

  /// Hand the payload to the very code a live request would have reached.
  ///
  /// The Soulseek key is replaced by the queue id, and that is load-bearing: it is how the running
  /// [DownloadJob] is found again to report progress against the right row. Duplicate protection
  /// does not suffer, because the stronger check is on `trackKey` — artist, title and duration
  /// from the authority — which this does not touch.
  Future<bool> _replay(QueueItem item) async {
    switch (item.kind) {
      case QueueKind.torrent:
        server.startTorrentDownload(item.payload);
        return true;
      case QueueKind.soulseek:
        return server.startSoulseekDownload({...item.payload, 'key': item.id});
      case QueueKind.soulseekAlbum:
        // An album fans out into one job per track, so there is no single job to key. Progress is
        // reported from the album's own tracks instead — see [_jobsFor].
        final started = await server.startSoulseekAlbumDownload(item.payload);
        return started > 0;
      default:
        throw 'Onbekend soort download: ${item.kind}';
    }
  }

  /// Mirror what the local job is doing back onto the queue item — throttled, because
  /// DownloadManager notifies several times a second and Firestore charges per write.
  Future<void> _reportRunning(List<QueueItem> items) async {
    for (final id in _running.toList()) {
      final item = items.firstWhere((i) => i.id == id, orElse: () => _missing);
      if (identical(item, _missing)) {
        _running.remove(id);
        continue;
      }
      final job = downloads.jobByKey(id);
      if (job == null) {
        // Absent for two different reasons, and telling them apart matters. Before we have ever
        // seen it, the download simply has not appeared yet — calling that "done" would mark
        // everything complete the instant it was claimed. After we have seen it, the job finished
        // and was tidied off the list, and the album is in the library.
        if (!_seen.contains(id)) continue;
        await backend.patch(id, {'status': QueueStatus.done, 'progress': 1.0, 'claimedBy': null});
        _running.remove(id);
        _seen.remove(id);
        _lastReport.remove(id);
        continue;
      }
      _seen.add(id);

      final status = job.busy
          ? QueueStatus.running
          : (job.playable ? QueueStatus.done : QueueStatus.failed);
      if (!_shouldReport(id, job.progress, status)) continue;

      await backend.patch(id, {
        'status': status,
        'progress': job.progress,
        'detail': job.detail,
        // Renew while it is still going; a five-minute lease must not expire under a long transfer.
        'leaseUntil': status == QueueStatus.running ? now().add(kQueueLease) : null,
        if (status != QueueStatus.running) 'claimedBy': null,
      });
      _lastReport[id] = (at: now(), progress: job.progress, status: status);
      if (status != QueueStatus.running) {
        _running.remove(id);
        _seen.remove(id);
        _lastReport.remove(id);
      }
    }
  }

  bool _shouldReport(String id, double progress, String status) {
    final last = _lastReport[id];
    if (last == null) return true;
    // A finished or failed job is always worth a write, however little the number moved.
    if (last.status != status) return true;
    if (now().difference(last.at) < kProgressInterval) return false;
    return (progress - last.progress).abs() >= kProgressStep;
  }

  static final QueueItem _missing =
      QueueItem(id: '', kind: '', title: '', payload: const {});
}
