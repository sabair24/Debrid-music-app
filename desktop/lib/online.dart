import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'organize.dart';
import 'quality.dart';
import 'rutracker.dart';
import 'search.dart';
import 'settings.dart';
import 'soulseek.dart';
import 'torbox.dart';

/// TorBox search + resolve + download, ported from the server's OnlineService.
class OnlineService {
  final AppSettings settings;
  final TorBox torbox;
  final RuTrackerService rutracker;
  final SearchAggregator aggregator;
  OnlineService(this.settings)
      : torbox = TorBox(() => settings.torboxToken),
        rutracker = RuTrackerService(settings),
        aggregator = SearchAggregator([
          ApibaySource(),
          BitSearchSource(),
          KnabenSource(),
          RuTrackerSource(RuTrackerService(settings)),
        ]);

  bool get torboxReady => torbox.hasKey;

  Future<List<SearchResult>> search(String query, {void Function(List<SearchResult>)? onPartial}) async {
    // Stream raw hits as each source finishes (fast perceived results); the ⚡Instant
    // cache marks are applied on the final pass below.
    final results = await aggregator.search(query, onPartial: onPartial);
    if (!torbox.hasKey) return results;
    // Mark instantly-cached results (top 40, batches of 20).
    final top = results.take(40).map((r) => r.hash.toLowerCase()).toList();
    final cached = <String>{};
    for (var i = 0; i < top.length; i += 20) {
      cached.addAll(await torbox.checkCached(top.sublist(i, (i + 20).clamp(0, top.length))));
    }
    for (final r in results) {
      r.cached = cached.contains(r.hash.toLowerCase());
    }
    results.sort((a, b) {
      if (a.cached != b.cached) return a.cached ? -1 : 1;
      return b.seeders.compareTo(a.seeders);
    });
    return results;
  }

  Future<(int?, String)> _addOrFind(SearchResult r) async {
    final (success, id, hash0, detail) = await torbox.addMagnet(r.magnet);
    final hash = (hash0 != null && hash0.isNotEmpty) ? hash0 : r.hash;
    if (hash.isEmpty) throw 'Torrent heeft geen infohash';
    if (success) return (id, hash);
    if (detail.toLowerCase().contains('already')) {
      final item = (await torbox.listTorrents())
          .cast<TbTorrent?>()
          .firstWhere((t) => t?.hash?.toLowerCase() == hash.toLowerCase(), orElse: () => null);
      return (item?.id, hash);
    }
    throw detail.isNotEmpty ? detail : 'Kon torrent niet toevoegen';
  }

  Future<TbTorrent> _pollReady(int? id, String hash,
      {bool patient = false, void Function(double progress, String status)? onProgress}) async {
    var delayMs = 2000;
    var noProgress = 0;
    var readyNoAudio = 0;
    // Big, low-seed torrents (a whole discography) take TorBox a long time to fetch from
    // few peers — be patient and, crucially, report progress so it's not a mystery spinner.
    final maxAttempts = patient ? 120 : 30;
    final stallTimeout = patient ? 90000 : 25000;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final list = await torbox.listTorrents();
      final item = list.cast<TbTorrent?>().firstWhere(
          (t) => (id != null && t?.id == id) || (t?.hash?.toLowerCase() == hash.toLowerCase()),
          orElse: () => null);
      onProgress?.call(item?.progress ?? 0, item?.status ?? 'toevoegen');
      if (item == null) {
        noProgress += delayMs;
      } else if (item.isFailed) {
        throw 'Bron mislukt: ${item.status}';
      } else if (item.isReady && item.audio.isNotEmpty) {
        return item;
      } else if (item.isReady) {
        readyNoAudio += delayMs;
        if (readyNoAudio >= 18000) throw 'Geen afspeelbare audio in deze bron';
      } else {
        if (item.progress <= 0) {
          noProgress += delayMs;
        } else {
          noProgress = 0;
        }
      }
      if (noProgress >= stallTimeout) throw 'Bron loopt vast — geen voortgang';
      await Future.delayed(Duration(milliseconds: delayMs));
      if (attempt >= 1) delayMs = (delayMs * 1.5).round().clamp(0, 10000);
    }
    throw 'Time-out bij voorbereiden van deze bron';
  }

  TbFile? _bestAudio(TbTorrent t) {
    final audio = t.audio;
    if (audio.isEmpty) return null;
    audio.sort((a, b) {
      final fa = a.isFlac ? 1 : 0, fb = b.isFlac ? 1 : 0;
      if (fa != fb) return fb - fa;
      return b.size.compareTo(a.size);
    });
    return audio.first;
  }

  List<TbFile> _sortedAudio(TbTorrent t) {
    final audio = t.audio;
    audio.sort((a, b) {
      final fa = a.isFlac ? 1 : 0, fb = b.isFlac ? 1 : 0;
      if (fa != fb) return fb - fa;
      return a.name.compareTo(b.name);
    });
    return audio;
  }

  /// Resolve the single best track of a result to a playable URL.
  Future<String> resolveStreamUrl(SearchResult r) async {
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached);
    final best = _bestAudio(item);
    if (best == null) throw 'Geen audio in deze torrent';
    final url = await torbox.requestDownload(item.id, best.id);
    if (url == null) throw 'Lege download-URL';
    return url;
  }

  /// Resolve a recommended track (artist + title) to a playable URL, picking the file
  /// that actually matches [title] (so an album torrent doesn't play the wrong song).
  /// [instantOnly] true (Radio) = cached TorBox sources only, for speed; false (an
  /// explicit play) also tries un-cached sources (slower). Returns null if nothing matches.
  Future<String?> resolveRadio(String artist, String title, {bool instantOnly = true}) async {
    if (!torbox.hasKey) return null;
    final results = await search('$artist $title');
    if (results.isEmpty) return null;
    int score(SearchResult r) {
      final n = r.name.toLowerCase();
      var s = 0;
      if (_titleMatch(r.name, title)) s += 60;
      if (RegExp('flac', caseSensitive: false).hasMatch(n)) s += 10;
      if (r.size < 120 * 1000 * 1000) s += 20; // small => likely a single track, not an album
      return s + (r.seeders > 0 ? 3 : 0);
    }

    final top = (results.toList()..sort((a, b) => score(b) - score(a))).take(10).toList();
    // Directly cache-check these candidates — search() only flags the top 40 overall.
    Set<String> cachedSet = {};
    try {
      cachedSet = await torbox.checkCached(top.map((r) => r.hash.toLowerCase()).toList());
    } catch (_) {}
    bool isCached(SearchResult r) => r.cached || cachedSet.contains(r.hash.toLowerCase());
    final cached = top.where(isCached).toList();
    // Cached first; for an explicit play, fall back to un-cached (slower) sources too.
    final candidates = instantOnly ? cached : [...cached, ...top.where((r) => !isCached(r))];
    for (final r in candidates.take(instantOnly ? 3 : 4)) {
      try {
        final (item, files) = await resolveForDownload(r, null); // patient poll when not cached
        TbFile? pick;
        for (final f in files) {
          if (_titleMatch(f.name, title)) {
            pick = f;
            break;
          }
        }
        pick ??= files.length == 1 ? files.first : null; // single-track torrent
        if (pick == null) continue; // multi-track, no title match => avoid the wrong song
        final url = await torbox.requestDownload(item.id, pick.id);
        if (url != null) return url;
      } catch (_) {}
    }
    return null;
  }

  bool _titleMatch(String name, String title) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final t = n(title);
    return t.length >= 3 && n(name).contains(t);
  }

  /// (torrent, audio files) for the track picker.
  Future<(TbTorrent, List<TbFile>)> tracklist(SearchResult r,
      {void Function(double, String)? onProgress}) async {
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached, onProgress: onProgress);
    final files = _sortedAudio(item);
    if (files.isEmpty) throw 'Geen audio in deze torrent';
    return (item, files);
  }

  Future<String> resolveTrackUrl(int torrentId, int fileId) async {
    final url = await torbox.requestDownload(torrentId, fileId);
    if (url == null) throw 'Lege download-URL';
    return url;
  }

  /// Resolve the torrent + the files to download (all audio, or one file).
  Future<(TbTorrent, List<TbFile>)> resolveForDownload(SearchResult r, int? fileId,
      {void Function(double, String)? onProgress}) async {
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached, onProgress: onProgress);
    final files = fileId != null ? item.files.where((f) => f.id == fileId).toList() : _sortedAudio(item);
    if (files.isEmpty) throw 'Geen audio gevonden';
    return (item, files);
  }
}

/// Soulseek search (with the first-character "*" quirk) + credentials gate.
class SoulseekService {
  final AppSettings settings;
  final SoulseekClient client = SoulseekClient();
  SoulseekService(this.settings);

  bool get available => settings.soulseekUser.isNotEmpty && settings.soulseekPass.isNotEmpty;

  /// True while the client is backing off after a refused login (account rate-limited/blocked).
  /// While this holds, NOTHING touches Soulseek — so normal browsing can't keep feeding the block.
  bool get blocked => client.blocked;
  Duration? get blockedFor => client.blockedFor;

  // ── The one logged-in connection ──────────────────────────────────────────
  // Soulseek allows a single login per account and blocks on a burst of them, so EVERYTHING that
  // talks to the server — searching, downloading, the status check — shares this one session.
  // Searching used to open its own connection and log in per query (twice, with the broad-query
  // retry), which is what kept getting the account blocked.
  SlskSession? _session;
  Timer? _idle;
  int _users = 0;

  Future<T> withSession<T>(Future<T> Function(SlskSession) body) async {
    _users++;
    _idle?.cancel();
    try {
      client.listenPort = settings.soulseekPort; // so firewalled peers can reach us
      final s = _session ??= client.newSession(settings.soulseekUser, settings.soulseekPass);
      return await body(s);
    } finally {
      _users--;
      if (_users == 0) _scheduleClose();
    }
  }

  /// Let go of the connection when nothing needs it, so the native client can log in again.
  void _scheduleClose() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 120), () {
      if (_users > 0) return;
      _session?.close();
      _session = null;
    });
  }

  /// Shutdown only. Guarded on [_users]: closing a session that a search or a queued download is
  /// still holding would leave that operation with an orphaned session which logs itself back in —
  /// two live logins for an account that allows one.
  void disposeSession() {
    if (_users > 0) return;
    _idle?.cancel();
    _session?.close();
    _session = null;
  }

  /// Confirm the Soulseek login works (used by the connection-status check).
  /// Goes through the shared session — it never costs a login of its own.
  Future<bool> verify() async {
    if (!available) return false;
    return withSession((s) => s.alive());
  }

  /// [onPartial] streams merged results as they arrive.
  ///
  /// Soulseek requires EVERY term to appear in a peer's path, so a long "Artist Title" query can
  /// come back completely empty while the artist alone has plenty (measured: "jaafar jackson got
  /// me singing" → 0 hits even after 30s, "jaafar jackson" → hits within 2s). So when a multi-word
  /// query finds nothing, retry once with just the first two words (usually the artist) rather
  /// than telling the user there are no sources. Both attempts run on the shared connection, so
  /// the retry costs nothing beyond the query itself.
  Future<List<SoulseekFile>> search(String query, {void Function(List<SoulseekFile>)? onPartial}) async {
    // An empty result because we couldn't log in is NOT "no sources" — retrying a broader query
    // would just burn another login and still show the user the wrong answer.
    final blocked = client.whyNotLogin;
    if (blocked != null) throw blocked;
    final first = await _searchOnce(query, onPartial);
    if (first.isNotEmpty) return first;
    if (client.whyNotLogin != null) throw client.whyNotLogin!;
    final words = query.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 3) return first;
    final broader = words.take(2).join(' ');
    return _searchOnce(broader, onPartial);
  }

  Future<List<SoulseekFile>> _searchOnce(String query, void Function(List<SoulseekFile>)? onPartial) async {
    if (!available) return [];
    final q = query.trim();
    if (q.isEmpty) return [];
    // Soulseek quirk: the first character is often dropped — also try a "*"-prefixed variant.
    final variants = <String>{q};
    if (q.length > 2) variants.add('*${q.substring(1)}');
    try {
      return await withSession((s) => s.search(variants.toList(), onPartial: onPartial));
    } catch (_) {
      return [];
    }
  }
}

class DownloadJob {
  final String name;
  final String? key; // stable id so a specific tile/track row can show THIS job's progress inline
  double progress;
  String status; // queued | waiting | downloading | done | failed | preparing
  String? detail; // failure reason, or "poging 2/5 · peer" while falling back
  int queuePlace = 0; // position in the uploader's queue while status == 'waiting' (0 = unknown)
  bool get busy => status == 'queued' || status == 'waiting' || status == 'downloading' || status == 'preparing';
  DownloadJob(this.name, {this.key, this.status = 'downloading'}) : progress = 0;
}

/// Streams TorBox + Soulseek downloads into the music library (with progress), then rescans.
class DownloadManager extends ChangeNotifier {
  final OnlineService online;
  final SoulseekService soulseek;
  final String musicRoot;
  final Future<void> Function() onLibraryChanged;
  DownloadManager(this.online, this.soulseek, this.musicRoot, this.onLibraryChanged);

  final List<DownloadJob> jobs = [];

  // ── Shared Soulseek download session ──────────────────────────────────────
  // Soulseek allows ONE login per username and blocks on a burst of logins — but a file TRANSFER
  // is a separate peer socket and costs no login. So (like the native client) all downloads share
  // ONE logged-in session and run in PARALLEL on it, up to [_slskMaxParallel] at a time; the rest
  // queue. The session auto-closes ~2 min after the last download, freeing Soulseek's single
  // connection so the native client can be used again.
  static const _slskMaxParallel = 6;
  int _slskActive = 0; // downloads holding a PARALLEL SLOT (a queued one gives its slot back)
  final List<Completer<void>> _slskWaiting = [];

  /// Live count of Soulseek downloads running / waiting (for the UI).
  int get slskActive => _slskActive;
  int get slskQueued => _slskWaiting.length;

  /// [body] gets a `releaseSlot` callback: a download that ends up waiting in an uploader's queue
  /// holds its peer connection (losing it would cost our queue position) but must NOT keep
  /// occupying one of the parallel slots — otherwise one busy uploader stalls everything else.
  Future<T> _withSlsk<T>(Future<T> Function(SlskSession, void Function()) body) async {
    if (_slskActive >= _slskMaxParallel) {
      final wait = Completer<void>();
      _slskWaiting.add(wait);
      await wait.future;
    }
    _slskActive++;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      _slskActive--;
      if (_slskWaiting.isNotEmpty) _slskWaiting.removeAt(0).complete(); // let the next one start
    }

    try {
      // The session belongs to SoulseekService and is shared with searching, so N parallel
      // downloads plus any search in flight still cost exactly ONE login. withSession also holds
      // the connection open for as long as anyone needs it — including a download parked in an
      // uploader's queue, whose retry would otherwise have to log in again.
      return await soulseek.withSession((s) => body(s, release));
    } finally {
      release();
    }
  }

  @override
  void dispose() {
    soulseek.disposeSession();
    super.dispose();
  }

  /// The most recent job with this key (or null) — lets a tile/track row show its own progress.
  DownloadJob? jobByKey(String key) {
    for (final j in jobs) {
      if (j.key == key) return j;
    }
    return null;
  }

  /// Remove finished (done/failed) jobs from the list; keep anything still in progress.
  void clearFinished() {
    jobs.removeWhere((j) => j.status == 'done' || j.status == 'failed');
    notifyListeners();
  }

  /// Rank peers offering the SAME track by QUALITY first: the user always wants the best copy
  /// available (24-bit hi-res FLAC → CD FLAC → … → MP3 only as an absolute last resort). The
  /// peer-fallback then falls through if the top pick won't actually download, so availability
  /// only breaks ties between EQUAL-quality copies.
  static int _rankSlsk(SoulseekFile a, SoulseekFile b) {
    final qa = _slskScore(a), qb = _slskScore(b);
    if (qa != qb) return qb - qa; // higher quality first
    if (a.freeSlots != b.freeSlots) return a.freeSlots ? -1 : 1;
    if (a.queueLength != b.queueLength) return a.queueLength.compareTo(b.queueLength);
    if (a.speed != b.speed) return b.speed.compareTo(a.speed);
    return b.size.compareTo(a.size);
  }

  /// A comparable quality score: format tier dominates (lossless ≫ lossy), then effective
  /// bitrate distinguishes hi-res (24/192 ≈ 4000k) from CD (16/44 ≈ 900k) within a tier.
  static int _slskScore(SoulseekFile f) {
    final q = qualityFromFile(
      name: f.displayName,
      ext: f.ext,
      isFlac: f.isFlac,
      bitrate: f.bitrate,
      durationSec: f.durationSec,
      size: f.size,
      isVbr: f.isVbr,
    );
    final tier = switch (q.tier) {
      QTier.hires => 3,
      QTier.lossless => 2,
      QTier.lossy => 1,
      QTier.unknown => 0,
    };
    var kbps = f.bitrate ?? 0;
    if (kbps <= 0 && (f.durationSec ?? 0) > 0 && f.size > 0) {
      kbps = (f.size * 8 / f.durationSec! / 1000).round();
    }
    return tier * 1000000 + kbps.clamp(0, 999999);
  }

  Future<void> enqueueSoulseek(SoulseekFile file) => enqueueSoulseekBest([file]);

  /// Download one track, trying its candidate peers best-first until one succeeds.
  /// [candidates] are copies of the SAME track from different peers. [key] lets the UI show
  /// this job's live progress inline on the tile/track row that started it.
  Future<bool> enqueueSoulseekBest(List<SoulseekFile> candidates, {String? key}) async {
    if (!soulseek.available) throw 'Stel je Soulseek-login in (Instellingen).';
    if (candidates.isEmpty) return false;
    // Don't start a duplicate if this exact key is already in progress.
    if (key != null) {
      final existing = jobByKey(key);
      if (existing != null && existing.busy) {
        return false;
      }
    }
    // Starts as 'queued': with parallel downloads a job can sit waiting for a slot, and showing a
    // spinning progress ring for it looked like a stuck download. _soulseekBest flips it to
    // 'downloading' once it actually starts.
    final job = DownloadJob(candidates.first.displayName, key: key, status: 'queued');
    jobs.insert(0, job);
    notifyListeners();
    // Runs on the shared session → reuses the one login (no new login per click).
    return _withSlsk((s, release) => _soulseekBest(candidates, job, s, release));
  }

  /// Fallback loop: try up to 5 peers best-first; the first that delivers wins. All attempts
  /// reuse [session]'s single login — trying another peer costs a new peer connection, NOT a
  /// new server login.
  Future<bool> _soulseekBest(
      List<SoulseekFile> candidates, DownloadJob job, SlskSession session, void Function() releaseSlot) async {
    final ranked = [...candidates]..sort(_rankSlsk);
    final tries = ranked.length < 5 ? ranked.length : 5;

    /// Shared success path: file the track away tidily (Albums/Singles/Compilaties per artist)
    /// before the rescan picks it up, so the library never sees the loose landing-zone copy.
    Future<bool> succeed(SlskDone res) async {
      final staged = File(res.path);
      var how = Placement.stuck;
      try {
        how = (await placeFileDetailed(staged, _downloadsRoot)).how;
        // Non-recursive: only removes the per-peer staging folder once it's actually empty.
        await staged.parent.delete();
      } catch (_) {/* leave it where it landed — the scan still finds it */}
      job.progress = 1;
      job.status = 'done';
      job.queuePlace = 0;
      // Say what actually happened. A plain "Klaar" on a track that turned out to be a duplicate
      // (and was therefore discarded) reads as "added to your library" when nothing was added.
      job.detail = switch (how) {
        Placement.moved => null,
        Placement.duplicate => 'had je al — beste versie behouden',
        Placement.stuck => 'gedownload, maar tags onleesbaar — staat in _inkomend',
      };
      notifyListeners();
      try {
        await onLibraryChanged();
      } catch (_) {/* library rescan hiccup shouldn't un-succeed the download */}
      return true;
    }

    Future<SlskResult> attempt(SoulseekFile f, {required bool wait}) async {
      try {
        return await _rawTransfer(session, f, job, () {
          // Only reached when waiting: hand our parallel slot to the next download so one busy
          // peer can't stall the batch, while we keep our place in this uploader's queue.
          releaseSlot();
        }, waitInQueue: wait);
      } catch (_) {
        return SlskFail('Downloadfout'); // unexpected throw → a failed attempt, keep going
      }
    }

    // Pass 1 — find someone who is FREE RIGHT NOW. A peer that puts us in its queue is dropped
    // immediately rather than waited on: a free peer beats a good place in a busy peer's line.
    final busy = <SoulseekFile>[];
    for (var i = 0; i < tries; i++) {
      final f = ranked[i];
      job.status = 'downloading';
      job.progress = 0;
      job.queuePlace = 0;
      job.detail = tries > 1 ? 'poging ${i + 1}/$tries · ${f.username}' : f.username;
      notifyListeners();
      final res = await attempt(f, wait: false);
      if (res is SlskDone) return succeed(res);
      if (res is SlskQueued) {
        busy.add(f); // worth waiting on later if nobody turns out to be free
        job.detail = '${f.username} is bezet · volgende bron';
      } else {
        job.detail = (res as SlskFail).reason;
      }
      notifyListeners();
    }

    // Pass 2 — nobody was free, so now we do wait, best quality first.
    for (final f in busy) {
      job.status = 'waiting';
      job.progress = 0;
      job.detail = 'wachten op ${f.username}';
      notifyListeners();
      final res = await attempt(f, wait: true);
      if (res is SlskDone) return succeed(res);
      job.detail = res is SlskQueued ? '${f.username} bleef bezet' : (res as SlskFail).reason;
      notifyListeners();
    }

    job.status = 'failed';
    job.queuePlace = 0;
    if (busy.isNotEmpty) job.detail = 'alle uploaders bleven bezet — probeer later opnieuw';
    notifyListeners();
    return false;
  }

  /// Root of the app's own, tidily-organised download tree. Only ever writes inside here — the
  /// user's existing collection elsewhere under musicRoot is never touched or moved.
  String get _downloadsRoot => '$musicRoot${Platform.pathSeparator}DebridMusic Downloads';

  /// A peer that never delivered leaves an empty staging folder behind; drop it so `_inkomend`
  /// doesn't slowly fill with the name of every uploader we ever tried. Non-recursive on purpose:
  /// a folder that still holds a partial file is left alone.
  Future<SlskResult> _cleanStaging(Directory dir, Future<SlskResult> transfer) async {
    final res = await transfer;
    try {
      await dir.delete();
    } catch (_) {/* not empty (or already gone) — leave it */}
    return res;
  }

  /// The raw single-peer transfer over [session] (updates progress only; no status finalization).
  Future<SlskResult> _rawTransfer(
      SlskSession session, SoulseekFile file, DownloadJob job, void Function() onQueued,
      {bool waitInQueue = true}) async {
    // Land in a staging folder; placeFile() moves it into Albums/Singles/Compilaties after.
    // Per-PEER subfolder: candidates for the same track share a display name, so a slow attempt
    // that is still winding down can never write into the file the next attempt just opened.
    final dir = Directory(
        '$_downloadsRoot${Platform.pathSeparator}_inkomend${Platform.pathSeparator}${_sanitize(file.username)}');
    await dir.create(recursive: true);
    final dest = File('${dir.path}${Platform.pathSeparator}${_sanitize(file.displayName)}');
    return _cleanStaging(dir, session.download(file, dest, (rec, tot) {
      if (job.status == 'waiting') {
        job.status = 'downloading'; // bytes are flowing — the wait is over
        job.queuePlace = 0;
        job.detail = file.username;
      }
      if (tot > 0) {
        final p = (rec / tot).clamp(0.0, 1.0);
        if (p - job.progress > 0.02) {
          job.progress = p;
          notifyListeners();
        }
      }
    }, onStatus: (q) {
      job.status = 'waiting';
      job.queuePlace = q.place;
      job.detail = q.place > 0 ? 'wachten op ${file.username} · plaats ${q.place}' : 'wachten op ${file.username}';
      notifyListeners();
      onQueued();
    }, waitInQueue: waitInQueue));
  }

  /// Add a torrent download. Non-blocking: a "preparing" job shows TorBox's fetch progress
  /// immediately (so a big/low-seed torrent isn't a mystery spinner), then per-file jobs
  /// start once TorBox has it ready.
  void enqueue(SearchResult result, {int? fileId}) {
    final prep = DownloadJob(fileId != null ? result.name : 'Voorbereiden: ${result.name}')..status = 'preparing';
    jobs.insert(0, prep);
    notifyListeners();
    unawaited(() async {
      try {
        final (torrent, files) = await online.resolveForDownload(result, fileId, onProgress: (p, s) {
          prep.progress = p;
          notifyListeners();
        });
        jobs.remove(prep);
        final destDir = Directory(
            '$musicRoot${Platform.pathSeparator}DebridMusic Downloads${Platform.pathSeparator}${_sanitize(torrent.name)}');
        await destDir.create(recursive: true);
        for (final f in files) {
          final job = DownloadJob(f.label);
          jobs.insert(0, job);
          notifyListeners();
          unawaited(_download(torrent.id, f, destDir, job));
        }
        notifyListeners();
      } catch (e) {
        prep.status = 'failed';
        notifyListeners();
      }
    }());
  }

  /// Download a whole album (used by "Download album" from Soulseek), ONE TRACK AT A TIME.
  /// Each element of [tracks] is the candidate peers for one track (the same song offered by
  /// several peers) — so a track whose best peer is busy falls back to another peer instead of
  /// failing. Sequential AND single-login: the WHOLE album runs on ONE session (one login), so a
  /// 12-track album costs 1 login, not one per track/peer — the burst that tripped the block.
  Future<int> enqueueSoulseekAlbum(List<List<SoulseekFile>> tracks) async {
    if (!soulseek.available) throw 'Stel je Soulseek-login in (Instellingen).';
    final running = <Future<bool>>[];
    for (final cands in tracks) {
      if (cands.isEmpty) continue;
      final job = DownloadJob(cands.first.displayName, status: 'queued');
      jobs.insert(0, job);
      // Start them ALL now — _withSlsk runs up to _slskMaxParallel at once on the ONE shared
      // login and queues the rest, so a whole album downloads in parallel like the native client.
      running.add(_withSlsk((s, release) => _soulseekBest(cands, job, s, release)).catchError((_) {
        job.status = 'failed';
        notifyListeners();
        return false;
      }));
    }
    notifyListeners();
    final results = await Future.wait(running);
    return results.where((ok) => ok).length;
  }

  Future<void> _download(int torrentId, TbFile f, Directory destDir, DownloadJob job) async {
    try {
      final url = await online.resolveTrackUrl(torrentId, f.id);
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw 'HTTP ${resp.statusCode}';
      final total = resp.contentLength ?? f.size;
      final dest = File('${destDir.path}${Platform.pathSeparator}${_sanitize(f.label)}');
      final sink = dest.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final p = (received / total).clamp(0.0, 1.0);
          if (p - job.progress > 0.02) {
            job.progress = p;
            notifyListeners();
          }
        }
      }
      await sink.close();
      client.close();
      job.progress = 1;
      job.status = 'done';
      notifyListeners();
      await onLibraryChanged();
    } catch (_) {
      job.status = 'failed';
      notifyListeners();
    }
  }

  String _sanitize(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}
