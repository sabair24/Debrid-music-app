/// Downloads chosen while the PC was off.
///
/// The trick that keeps this small: a queue item carries **exactly the body the PC's own route
/// takes**. So the worker does not interpret anything — it replays the request that would have
/// been made had the PC been awake, into the same `DownloadManager` that serves every other
/// download. No second download path, and nothing to keep in step.
///
/// What you are queueing is a *request*, not a file. Searching happens on the PC, because that is
/// where the TorBox key and the single Soulseek login live — so with the PC off you can only queue
/// something you already picked while it was on, or something the library itself told you was
/// missing.
library;

import 'dart:math';

/// Which route the payload belongs to. The string is stored, so these names are part of the wire
/// format: renaming one strands whatever is already queued.
class QueueKind {
  static const torrent = 'torrent'; // POST /api/online/download
  static const soulseek = 'soulseek'; // POST /api/soulseek/download
  static const soulseekAlbum = 'soulseekAlbum'; // POST /api/soulseek/download-album
}

class QueueStatus {
  static const queued = 'queued';
  static const claimed = 'claimed';
  static const running = 'running';
  static const done = 'done';
  static const failed = 'failed';
}

class QueueItem {
  QueueItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.payload,
    this.status = QueueStatus.queued,
    this.claimedBy,
    this.leaseUntil,
    this.progress = 0,
    this.detail,
    this.requestedBy = '',
    this.requestedAt,
    this.attempts = 0,
  });

  final String id;
  final String kind;

  /// What to show in a list — the PC is not the only thing that reads this.
  final String title;

  /// The request body, verbatim.
  final Map<String, dynamic> payload;

  String status;
  String? claimedBy;
  DateTime? leaseUntil;
  double progress;
  String? detail;
  final String requestedBy;
  final DateTime? requestedAt;
  int attempts;

  bool get isFinished => status == QueueStatus.done || status == QueueStatus.failed;

  /// Free for the taking: nobody has it, or whoever had it stopped saying so. A PC unplugged
  /// mid-download would otherwise hold the item for ever.
  bool claimableAt(DateTime now) {
    if (status == QueueStatus.queued) return true;
    if (status == QueueStatus.claimed || status == QueueStatus.running) {
      final until = leaseUntil;
      return until == null || now.isAfter(until);
    }
    return false;
  }

  Map<String, dynamic> toFields() => {
        'kind': kind,
        'title': title,
        'payload': payload,
        'status': status,
        'claimedBy': claimedBy,
        'leaseUntil': leaseUntil,
        'progress': progress,
        'detail': detail,
        'requestedBy': requestedBy,
        'requestedAt': requestedAt,
        'attempts': attempts,
      };

  static QueueItem? fromFields(String id, Map<String, dynamic> f) {
    final kind = (f['kind'] ?? '').toString();
    if (kind.isEmpty) return null;
    return QueueItem(
      id: id,
      kind: kind,
      title: (f['title'] ?? '').toString(),
      payload: (f['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      status: (f['status'] ?? QueueStatus.queued).toString(),
      claimedBy: f['claimedBy'] as String?,
      leaseUntil: f['leaseUntil'] is DateTime ? f['leaseUntil'] as DateTime : null,
      progress: (f['progress'] as num?)?.toDouble() ?? 0,
      detail: f['detail'] as String?,
      requestedBy: (f['requestedBy'] ?? '').toString(),
      requestedAt: f['requestedAt'] is DateTime ? f['requestedAt'] as DateTime : null,
      attempts: (f['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Where the queue lives. An interface so the claiming and throttling rules can be tested without
/// a Firebase project — without this seam none of the logic below would be exercised at all.
abstract interface class QueueBackend {
  Future<List<QueueItem>> list();
  Future<QueueItem?> get(String id);
  Future<void> put(QueueItem item);
  Future<void> patch(String id, Map<String, dynamic> fields);
  Future<void> remove(String id);
}

String newQueueId() {
  final rnd = Random.secure();
  final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final tail = List.generate(6, (_) => rnd.nextInt(36).toRadixString(36)).join();
  // Time-ordered, so a listing comes back roughly in the order things were asked for.
  return '$now-$tail';
}

/// How long a PC may hold an item before another may take it. Long enough that a slow Soulseek
/// peer does not lose the claim mid-transfer, short enough that a crash is picked up in minutes.
const Duration kQueueLease = Duration(minutes: 5);

/// Progress is written back at most this often, and only when it actually moved. DownloadManager
/// notifies several times a second; mirroring that would turn a free tier into a bill.
const Duration kProgressInterval = Duration(seconds: 5);
const double kProgressStep = 0.02;
