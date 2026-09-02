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
import 'zuinig.dart';

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

  /// Wanneer er voor het laatst iets in de wachtrij stond. Null zolang dat nog nooit zo was.
  DateTime? _laatsteWerk;

  /// Kijk de wachtrij na — snel zolang er iets gebeurt, trager als het al een tijd stil is.
  ///
  /// **Waarom dat laatste erbij moest.** Dit stond op vast elke twintig seconden, ook als de
  /// wachtrij dagenlang leeg was: 4320 leesbeurten per dag van de accountdatabase, voor een pc die
  /// niets te doen had. Samen met de hartslag was dat genoeg om de gratis daglimiet op te maken, en
  /// dan kom je niet meer binnen — precies wat er op 31-08-2026 gebeurde. Zie `zuinig.dart`.
  ///
  /// De prijs staat er eerlijk bij: na vijf minuten stilte kan het tot een minuut duren voor een
  /// nieuwe opdracht wordt opgepikt. Zodra er íéts in de wachtrij staat gaat het meteen weer snel.
  void start({Duration? every}) {
    _poll?.cancel();
    _vast = every;
    _gestopt = false;
    unawaited(_ronde());
  }

  /// Een klok die zichzelf steeds opnieuw zet, en geen `Timer.periodic`: het ritme wordt NA elke
  /// ronde opnieuw bepaald, want juist die ronde kan werk gevonden hebben.
  Future<void> _ronde() async {
    if (_gestopt) return;
    await tick();
    if (_gestopt) return;
    _poll?.cancel();
    _poll = Timer(_vast ?? wachtrijRitme(_stilte()), () => unawaited(_ronde()));
  }

  /// Een vast ritme uit [start], voor toetsen die niet op de terugval willen wachten.
  Duration? _vast;
  bool _gestopt = false;

  Duration _stilte() =>
      _laatsteWerk == null ? kStilteVoorTraag : now().difference(_laatsteWerk!);

  void stop() {
    _gestopt = true;
    _poll?.cancel();
    _poll = null;
  }

  /// One pass: pick up anything free, then report on anything running.
  Future<void> tick() async {
    try {
      final items = await backend.list();
      // Iets in de rij betekent: blijf snel kijken. Ook een item dat al klaar is telt mee -- er is
      // dan zojuist iets gebeurd, en de kans is groot dat er meer volgt.
      if (items.isNotEmpty) _laatsteWerk = now();
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
