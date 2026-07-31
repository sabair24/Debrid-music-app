import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'organize.dart';
import 'lossless_want.dart';
import 'quality.dart';
import 'rutracker.dart';
import 'search.dart';
import 'settings.dart';
import 'soulseek.dart';
import 'torbox.dart';
import 'warm_log.dart';
import 'paths.dart';

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

  /// True while nothing may touch Soulseek — so normal browsing can't keep feeding the problem.
  ///
  /// [SoulseekClient.mustNotLogin], not `blocked`: the login budget stops logins just as firmly and
  /// used to do it invisibly, leaving the panel to report "0 bronnen" with no reason given.
  bool get blocked => client.mustNotLogin;
  Duration? get blockedFor => client.blockedFor;

  /// What is actually going on — see [SlskPause]. The screen wrote its own text from one boolean
  /// and called a kick, a silence and a wrong password all "login geweigerd".
  SlskPause get pause => client.pause;
  String get pauseLabel => client.pauseLabel;
  String? get whyNotLogin => client.whyNotLogin;

  /// Drop every wait standing in the way and let one login through.
  ///
  /// The session's own counters go too. Without them the button cleared the client's back-off and
  /// the session refused anyway, so nothing happened and the notice stayed on screen.
  void retryLoginNow() {
    client.allowOneRetry();
    _session?.allowRetry();
  }

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
      // A session holds the username and password it was built with. Correcting them in Settings
      // therefore changed nothing until the old session happened to idle out — so the fix for a
      // wrong password appeared not to work, which is the worst possible moment to be ignored.
      final s0 = _session;
      if (s0 != null && (s0.user != settings.soulseekUser || s0.pass != settings.soulseekPass)) {
        s0.close();
        _session = null;
      }
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
  String status; // queued | waiting | downloading | upgrading | done | failed | preparing
  String? detail; // failure reason, or "poging 2/5 · peer" while falling back
  int queuePlace = 0; // position in the uploader's queue while status == 'waiting' (0 = unknown)

  /// Everything this job currently has in flight — several at once while racing peers. Stopping
  /// the job means stopping all of them.
  final List<SlskCancel> live = [];
  bool cancelled = false;

  /// Only a Soulseek job can actually be stopped mid-flight; a TorBox transfer has no such
  /// handle, and offering a button that silently does nothing is worse than offering none.
  bool canCancel = false;

  /// Identity of the TRACK, not of one peer's copy. Clicking five sources of the same song must
  /// not start five downloads of it.
  String? trackKey;

  /// Every peer copy this job may fall back on — kept so the job can be written down and picked
  /// up again after a restart.
  List<SoulseekFile> candidates = const [];

  /// What this track IS, according to the official release the user was looking at — not according
  /// to whichever peer happened to serve it. Soulseek delivers the audio; this decides the name,
  /// the folder and the tags. Null for a download with no album context (a loose search hit).
  TrackTags? authority;
  bool get busy =>
      status == 'queued' ||
      status == 'waiting' ||
      status == 'downloading' ||
      status == 'preparing' ||
      status == 'upgrading';

  /// The track is on disk and playable — even if something is still running for it.
  bool get playable => status == 'done' || status == 'upgrading';
  DownloadJob(this.name, {this.key, this.status = 'downloading'}) : progress = 0;
}

/// Streams TorBox + Soulseek downloads into the music library (with progress), then rescans.
class DownloadManager extends ChangeNotifier {
  final OnlineService online;
  final SoulseekService soulseek;
  final String musicRoot;
  final Future<void> Function() onLibraryChanged;

  /// Heeft de bibliotheek dit nummer al lossless? Laat een staande wens vervallen.
  ///
  /// Als vraag naar buiten en niet als eigen index: de bibliotheek weet dit al, en een tweede
  /// administratie zou ernaast gaan lopen zodra de gebruiker een map verplaatst.
  bool Function(String artist, String title)? haveLossless;

  /// Waar deze opname al staat, zodat een betere versie er NAARTOE gaat in plaats van ernaast.
  ///
  /// Zonder dit bergt de app een download op volgens diens eigen albumtag, en dan landt een 24/192 van
  /// Thriller in een map "Thriller" naast je "Thriller (MFSL One Step)" — twee albums, en het mindere
  /// bestand blijft staan omdat de vervangingsregel alleen binnen één map kijkt.
  String? Function(String artist, String title)? mapVanBestaande;

  DownloadManager(this.online, this.soulseek, this.musicRoot, this.onLibraryChanged);

  final List<DownloadJob> jobs = [];

  // ── Shared Soulseek download session ──────────────────────────────────────
  // Soulseek allows ONE login per username and blocks on a burst of logins — but a file TRANSFER
  // is a separate peer socket and costs no login. So (like the native client) all downloads share
  // ONE logged-in session and run in PARALLEL on it, up to [_slskMaxParallel] at a time; the rest
  // queue. The session auto-closes ~2 min after the last download, freeing Soulseek's single
  // connection so the native client can be used again.
  static const _slskMaxParallel = 6;

  /// How many peers a sweep walks looking for "someone free right now". Lossless gets a much
  /// deeper sweep: settling for an MP3 while an untried FLAC was sitting at position 7 would
  /// break the one rule that matters here. A short probe timeout keeps that affordable.
  /// Each try is now a DIFFERENT peer (see [_sweepOrder]), so the budget buys real chances rather
  /// than several files from the same collector.
  static const _maxLosslessTries = 20;
  static const _maxLossyTries = 8;

  /// How fast the race opens new peer connections. Not a cap on how many run at once: a peer that
  /// answers "you're in my queue" frees its slot immediately and keeps waiting in the background,
  /// so within half a minute the whole shortlist is engaged. Peer connections, not logins — the
  /// shared session is untouched, so this cannot repeat the login problem.
  static const _probeWidth = 6;

  /// Total time spent chasing a better copy after a playable one already landed.
  static const _upgradeBudget = Duration(minutes: 10);

  /// Wat deze weg besloot, in `downloads.log` naast de andere staatbestanden.
  ///
  /// Gebouwd omdat een vraag niet te beantwoorden was. Een FLAC die via de app niet binnenkwam en via
  /// de native client meteen wel: er zijn vier mechanismen die dat kunnen verklaren -- geen kandidaat
  /// gevonden, tien minuten opwaardeerbudget op, wachten achter een andere opwaardering, of een
  /// herstart die de jacht afkapt -- en van buitenaf zijn ze niet van elkaar te onderscheiden.
  /// pending_downloads.json wordt opgeruimd en warm.log gaat alleen over de metadata-warmer, dus na
  /// een uur is er niets meer om naar te kijken. Precies de les die warm.log zelf al opschreef.
  late final WarmLog _log = WarmLog('$appDir${Platform.pathSeparator}downloads.log');

  /// Upgrades run one at a time and take NO download slot, so they can never delay a track you
  /// have nothing of yet. Queued rather than dropped, so a whole album still gets upgraded.
  final List<Future<void> Function()> _upgradeQueue = [];
  bool _upgradeRunning = false;
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

  /// Stop a download the user no longer wants. Everything in flight for it is torn down; the
  /// partial file is removed by the transfer itself.
  void cancelJob(DownloadJob job) {
    job.cancelled = true;
    for (final c in job.live) {
      c.cancel();
    }
    job.live.clear();
    job.status = 'failed';
    job.detail = 'geannuleerd';
    job.queuePlace = 0;
    notifyListeners();
    // Off the list at once — a download the user stopped must not come back at the next start.
    unawaited(_savePending());
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
    final stereo = switch (q.tier) {
      QTier.hires => 4,
      QTier.lossless => 3,
      QTier.lossy => 1,
      QTier.unknown => 0,
    };
    // A surround rip carries the most bits of all and would win every comparison on bitrate — but
    // it gets downmixed on a stereo system and costs ten times the space (one measured track:
    // 263 MB). It sits below every stereo lossless copy, and still above MP3: it IS lossless.
    final tier = (stereo >= 3 && isMultichannel(f)) ? 2 : stereo;
    return tier * 1000000 + effectiveKbps(f).clamp(0, 999999);
  }

  /// Bitrate as actually delivered — the peer's own figure, else derived from size and duration.
  static int effectiveKbps(SoulseekFile f) {
    final stated = f.bitrate ?? 0;
    if (stated > 0) return stated;
    if ((f.durationSec ?? 0) > 0 && f.size > 0) return (f.size * 8 / f.durationSec! / 1000).round();
    return 0;
  }

  static final _multichannelRe = RegExp(
    r'(\b5[\._ ]1\b|\b7[\._ ]1\b|\b4[\._ ]0\b|surround|multi[\- ]?channel|quadraphonic|\bquad\b|atmos|\bdts\b|\bauro3d\b)',
    caseSensitive: false,
  );

  /// A 5.1/surround rip rather than a stereo master.
  ///
  /// The release name is the reliable signal; the bitrate is the backstop for rips that don't say
  /// so. 6500k is above what stereo 24/192 FLAC reaches (~5000k) and below 5.1 24/96 (~8000k).
  /// Drie wegen, van hard naar zacht — want elke weg alleen laat er doorheen glippen.
  ///
  /// 1. De SOM. Sinds de peer zijn sample rate en bitdiepte meestuurt, is dit te bewijzen: een FLAC is
  ///    nooit groter dan onbewerkt, dus wie boven `sampleRate × bits × 2` uitkomt heeft meer kanalen.
  ///    Zie [meerDanStereo]. Dit vervangt de vaste 6500 hieronder waar het kan, en dat is nodig: die
  ///    grens zit precies in het gebied waar 24/192 stereo leeft (4600–6500), dus hij nam echte
  ///    stereobestanden mee én liet een 5.1 op cd-kwaliteit (~2600) lopen.
  /// 2. De NAAM, voor peers die geen sample rate sturen.
  /// 3. De vaste grens, als vangnet voor diezelfde peers.
  static bool isMultichannel(SoulseekFile f) {
    final kbps = effectiveKbps(f);
    if (f.sampleRate != null && f.bitDepth != null) {
      return meerDanStereo(sampleRate: f.sampleRate, bitDepth: f.bitDepth, kbps: kbps) ||
          _multichannelRe.hasMatch(f.filename);
    }
    return _multichannelRe.hasMatch(f.filename) || kbps > 6500;
  }

  Future<void> enqueueSoulseek(SoulseekFile file) => enqueueSoulseekBest([file]);

  /// Download one track, trying its candidate peers best-first until one succeeds.
  /// [candidates] are copies of the SAME track from different peers. [key] lets the UI show
  /// this job's live progress inline on the tile/track row that started it.
  Future<bool> enqueueSoulseekBest(List<SoulseekFile> candidates,
      {String? key, TrackTags? authority}) async {
    if (!soulseek.available) throw 'Stel je Soulseek-login in (Instellingen).';
    if (candidates.isEmpty) return false;
    // Don't start a duplicate if this exact key is already in progress.
    if (key != null) {
      final existing = jobByKey(key);
      if (existing != null && existing.busy) {
        return false;
      }
    }
    // Nor if the same TRACK is already running from another source. Clicking five copies of one
    // song used to start five downloads of it; whichever finished second was thrown away as a
    // duplicate anyway, and the better copy is already chased automatically once one lands.
    //
    // The key carries the DURATION as well as the name: on name alone, "Intro" from one album
    // blocked "Intro" from another, and refusing a download the user actually wanted is worse
    // than allowing a duplicate.
    final track = _trackIdOf(candidates.first);
    if (track.isNotEmpty && jobs.any((j) => j.busy && j.trackKey == track)) return false;
    // Starts as 'queued': with parallel downloads a job can sit waiting for a slot, and showing a
    // spinning progress ring for it looked like a stuck download. _soulseekBest flips it to
    // 'downloading' once it actually starts.
    final job = DownloadJob(candidates.first.displayName, key: key, status: 'queued')..trackKey = track
      ..canCancel = true
      ..authority = authority
      ..candidates = candidates;
    jobs.insert(0, job);
    notifyListeners();
    // Written down BEFORE it starts: the point is to survive the app not getting a chance to
    // finish — a PC shut down mid-download is exactly the case this is for.
    unawaited(_savePending());
    // Runs on the shared session → reuses the one login (no new login per click).
    final ok = await _withSlsk((s, release) => _soulseekBest(candidates, job, s, release));
    await _pruneStaging();
    unawaited(_savePending());
    return ok;
  }

  // ── Surviving a restart ───────────────────────────────────────────────────
  // A download interrupted by the app closing (or the PC shutting down) used to be simply gone:
  // no record of it anywhere, and a half-written file left behind in staging.

  String get _appDir => appDir;
  File get _pendingFile => File('$_appDir${Platform.pathSeparator}pending_downloads.json');

  Future<void> _savePending() async {
    try {
      final open = jobs.where((j) => j.busy && j.candidates.isNotEmpty).toList();
      if (open.isEmpty) {
        if (await _pendingFile.exists()) await _pendingFile.delete();
        return;
      }
      await Directory(_appDir).create(recursive: true);
      await _pendingFile.writeAsString(jsonEncode([
        for (final j in open)
          {
            'name': j.name,
            'key': j.key,
            'candidates': [for (final c in j.candidates) c.toJson()],
            if (j.authority != null) 'authority': j.authority!.toJson(),
          }
      ]));
    } catch (_) {/* losing the note is not worth failing a download over */}
  }

  /// Pick up where we left off. Called once at startup, after the library is loaded.
  ///
  /// Restarted from scratch rather than continued byte-for-byte: the half-file in staging came
  /// from one particular peer that may well be gone, and the race will find whoever is fastest
  /// right now anyway. Staging is cleared first — nothing in there can be live at startup.
  Future<int> resumePending() async {
    List<dynamic> saved;
    try {
      if (!await _pendingFile.exists()) return 0;
      saved = jsonDecode(await _pendingFile.readAsString()) as List<dynamic>;
    } catch (_) {
      return 0;
    }
    await _clearStaging();
    var n = 0;
    for (final e in saved) {
      if (e is! Map<String, dynamic>) continue;
      final cands = [
        for (final c in (e['candidates'] as List<dynamic>? ?? const []))
          if (c is Map<String, dynamic>) SoulseekFile.fromJson(c),
      ].whereType<SoulseekFile>().toList();
      if (cands.isEmpty) continue;
      n++;
      // Not awaited: they run in parallel under the usual slot cap, and startup mustn't block.
      // A row written before this existed simply has no authority and behaves as it always did.
      final auth = e['authority'];
      unawaited(enqueueSoulseekBest(cands,
              key: e['key'] as String?,
              authority: auth is Map<String, dynamic> ? TrackTags.fromJson(auth) : null)
          .catchError((_) => false));
    }
    return n;
  }

  /// Everything in staging at startup is a leftover from a session that ended mid-transfer.
  Future<void> _clearStaging() async {
    final root = Directory('$_downloadsRoot${Platform.pathSeparator}_inkomend');
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {/* in use, or already gone */}
  }

  /// Fallback loop: try up to 5 peers best-first; the first that delivers wins. All attempts
  /// reuse [session]'s single login — trying another peer costs a new peer connection, NOT a
  /// new server login.
  Future<bool> _soulseekBest(
      List<SoulseekFile> candidates, DownloadJob job, SlskSession session, void Function() releaseSlot) async {
    final ranked = [...candidates]..sort(_rankSlsk);

    /// Shared success path: file the track away tidily (Albums/Singles/Compilaties per artist)
    /// before the rescan picks it up, so the library never sees the loose landing-zone copy.
    Future<bool> succeed(SlskDone res) async {
      final staged = File(res.path);
      var how = Placement.stuck;
      try {
        how = (await placeFileDetailed(staged, _downloadsRoot, tags: job.authority, staatAl: mapVanBestaande)).how;
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

    Future<SlskResult> attempt(SoulseekFile f,
        {required bool wait, SlskCancel? cancel, void Function()? onQueued, bool Function()? claim}) async {
      final t0 = DateTime.now();
      SlskResult uit;
      try {
        uit = await _rawTransfer(session, f, job, () => onQueued?.call(),
            waitInQueue: wait, cancel: cancel, claim: claim);
      } catch (_) {
        uit = SlskFail('Downloadfout'); // unexpected throw → a failed attempt, keep going
      }
      _log.line('   ${f.username}: ${_uitkomst(uit)}  na ${_kort(DateTime.now().difference(t0))}');
      return uit;
    }

    // Three pools, raced in this order. A race is won by whoever SENDS first, not by whoever is
    // best, so quality has to be decided by which pool runs — not by sorting inside one. Racing
    // surround alongside stereo did exactly what it sounds like: a free 5.1 rip beat every stereo
    // peer, landed 103 MB, and the upgrade chase then fetched the 32 MB stereo copy anyway.
    final stereo = ranked.where((f) => isLossless(f) && !isMultichannel(f)).toList();
    final surround = ranked.where((f) => isLossless(f) && isMultichannel(f)).toList();
    // An MP3 stays what it has always been here: an absolute last resort, never a shortcut — so a
    // free MP3 does NOT beat waiting for a FLAC.
    final lossy = ranked.where((f) => !isLossless(f)).toList();

    // De eerste vraag bij "hij kwam niet binnen" is of er überhaupt iets te halen was. Zonder deze
    // regel is "geen kandidaat gevonden" niet te onderscheiden van "wel gevonden, maar afgebroken".
    _log.line('"${job.name}": ${ranked.length} kandidaten '
        '(stereo ${stereo.length}, surround ${surround.length}, lossy ${lossy.length})');
    for (final f in ranked.take(3)) {
      _log.line('   beste: ${f.username}  ${f.displayName}  '
          '${isLossless(f) ? "lossless" : "lossy"}  wachtrij=${f.queueLength} vrij=${f.freeSlots}');
    }

    /// Ask every candidate peer and let the FIRST ONE THAT ACTUALLY SENDS win.
    ///
    /// This is what clicking twenty sources by hand in the native client does. The earlier version
    /// only asked [_probeWidth] at a time and, worse, threw away any peer that answered "you're in
    /// my queue" — those went on a list that was walked one at a time, minutes later. So a peer
    /// that would have come up in ten seconds was dropped, the counter marched to 20/20, and it
    /// looked as though only the last peer ever counted.
    ///
    /// Now a queue answer costs a peer nothing: it keeps waiting in the background while the
    /// window moves on to the next one. Within half a minute every candidate is engaged at once
    /// and whoever comes up first takes it. All of them ride the ONE shared login — twenty peer
    /// sockets, zero extra logins.
    Future<(SlskDone, SoulseekFile)?> race(List<SoulseekFile> pool, String label) async {
      final cap = identical(pool, lossy) ? _maxLossyTries : _maxLosslessTries;
      final order = sweepOrderFor(pool);
      final n = order.length < cap ? order.length : cap;

      SlskDone? winner;
      SoulseekFile? winnerFile;
      SoulseekFile? leader; // the peer currently sending; owns the progress line
      final decided = Completer<void>();
      final runners = <Future<void>>[];
      var asked = 0, queued = 0, cursor = 0;

      void paint() {
        // Never after a stop: cancelJob has already written the final word, and overwriting it
        // left the job looking busy forever.
        if (leader != null || winner != null || job.cancelled) return; // the sending peer owns the line
        job.status = 'waiting';
        job.progress = 0;
        job.queuePlace = 0;
        job.detail = '$label · $asked van $n gevraagd, $queued in de wachtrij';
        notifyListeners();
      }

      Future<void> run(SoulseekFile f, Completer<void> moveOn) async {
        final c = SlskCancel();
        job.live.add(c);
        asked++;
        paint();
        // Counted once. A queued peer re-reports its position every 30 seconds, so counting each
        // report had the line climbing to "137 in de wachtrij" out of twenty peers.
        var inLine = false;
        final res = await attempt(
          f,
          wait: true,
          cancel: c,
          // Queued is no longer a dead end — this peer stays in line while the window moves on.
          onQueued: () {
            if (!inLine) {
              inLine = true;
              queued++;
            }
            if (!moveOn.isCompleted) moveOn.complete();
            paint();
          },
          claim: () {
            if (leader == null) {
              leader = f;
              return true;
            }
            c.cancel(); // someone else is already sending — don't burn bandwidth alongside them
            return false;
          },
        );
        job.live.remove(c);
        if (inLine) queued--; // this peer gave up its place; the line really is shorter
        if (!moveOn.isCompleted) moveOn.complete();
        if (res is SlskDone) {
          if (winner == null) {
            winner = res;
            winnerFile = f;
            // Now everything else is redundant. Anything BETTER than this copy is still on the
            // list the upgrade chase walks afterwards, so quality is parked, not thrown away.
            for (final live in [...job.live]) {
              live.cancel();
            }
            if (!decided.isCompleted) decided.complete();
          } else {
            // Two finished in the same instant. The loser's file is complete but unwanted: bin it,
            // or it sits in staging forever — the library scan skips that folder.
            await _discardStaged(res.path);
          }
          return;
        }
        // The peer that was sending died on us. Release the line so another runner can take over
        // rather than leaving the job frozen on a name that stopped sending.
        if (identical(leader, f)) {
          leader = null;
          paint();
        }
      }

      /// Starts runners; each slot frees the moment its peer is merely queued, so the whole
      /// shortlist ends up engaged instead of four at a time.
      Future<void> feeder() async {
        while (winner == null && !job.cancelled) {
          final i = cursor++;
          if (i >= n) return;
          final moveOn = Completer<void>();
          final r = run(order[i], moveOn);
          runners.add(r);
          await Future.any([r, moveOn.future]);
        }
      }

      paint();
      final feeders = List.generate(_probeWidth, (_) => feeder());
      await Future.wait(feeders);
      // Everyone has been asked and nobody is sending, so this job is now just holding places in
      // other people's queues: hand the parallel slot to the next download. Releasing it on the
      // FIRST queued peer (as the old sequential wait did) meant a twelve-track album could have
      // every track racing twenty peers at once — the cap stopped capping anything.
      if (winner == null) releaseSlot();
      // Now sit on the ones still queued until one comes up.
      if (winner == null && !job.cancelled && runners.isNotEmpty) {
        await Future.any([Future.wait(runners), decided.future]);
      }
      if (winner != null) {
        // Return the winning FILE too: which copy we settled for is what decides whether a better
        // one is still worth chasing.
        return (winner!, winnerFile!);
      }
      return null;
    }

    /// Finish, and if what we settled for is beaten by another candidate, chase that in the
    /// background. Reached from EVERY success path — the copy most worth upgrading is the MP3
    /// we only took because no lossless could be had.
    Future<bool> finish(SlskDone res, SoulseekFile from) async {
      final ok = await succeed(res);
      final better = ranked.where((f) => clearlyBetter(f, from)).toList();
      if (ok && better.isNotEmpty) _queueUpgrade(better, job);
      // FLAC is koning. Landde er lossy, dan blijft de FLAC gewenst -- ook als er vandaag geen enkele
      // lossless bron was, want morgen staat er een andere peer online. Dat is niet theoretisch:
      // gemeten op één nummer waar de enige lossless peer het account geband had, en een dag later
      // leverde een andere hem in twee seconden.
      //
      // Bewust hier en niet bij _queueUpgrade: die vuurt alleen als er NU een betere bron in de lijst
      // staat, en juist het geval zonder kandidaat is het geval dat een staande wens nodig heeft.
      if (ok && !isLossless(from)) await _wantLossless(job, from);
      return ok;
    }

    // ── 1. Stereo lossless: the thing you actually want ──────────────────────
    final first = await race(stereo, 'poging');
    if (first != null) return finish(first.$1, first.$2);

    if (job.cancelled) return false;

    // ── 2. Surround — lossless, but it downmixes on a stereo system and costs ten times the space
    if (surround.isNotEmpty) {
      job.detail = 'alleen surround beschikbaar — 5.1 als tweede keus';
      notifyListeners();
      final second = await race(surround, '5.1-poging');
      if (second != null) return finish(second.$1, second.$2);
      if (job.cancelled) return false;
    }

    // ── 3. Only now, lossy — an MP3 is a last resort, never a shortcut ───────
    if (lossy.isNotEmpty) {
      job.detail = 'geen lossless beschikbaar — MP3 als laatste optie';
      notifyListeners();
      final third = await race(lossy, 'MP3-poging');
      if (third != null) return finish(third.$1, third.$2);
    }

    job.status = 'failed';
    job.queuePlace = 0;
    // Don't rewrite the user's own stop as an uploader failure and invite them to retry.
    if (!job.cancelled) {
      job.detail = 'geen enkele bron leverde — probeer later opnieuw';
    }
    notifyListeners();
    return false;
  }

  /// Identity of a track across peers: the filename without its track number, plus the running
  /// time rounded to five seconds. Two peers' copies of one song agree on both; two different
  /// songs that merely share a title ("Intro") almost never do.
  static String _trackIdOf(SoulseekFile f) {
    final name = trackNameKey(f.displayName);
    if (name.isEmpty) return '';
    final secs = f.durationSec ?? 0;
    return secs > 0 ? '$name|${(secs / 5).round()}' : name;
  }

  /// Drop the empty per-peer folders a race leaves behind. Each attempt tidies up after itself,
  /// but with twenty running at once those deletes collide, and one leftover folder per peer ever
  /// tried adds up. Only empty ones: a folder that still holds a file is somebody's download.
  Future<void> _pruneStaging() async {
    final root = Directory('$_downloadsRoot${Platform.pathSeparator}_inkomend');
    try {
      await for (final e in root.list()) {
        if (e is! Directory) continue;
        try {
          await e.delete(); // non-recursive: throws if anything is in it
        } catch (_) {/* not empty — leave it */}
      }
    } catch (_) {/* no staging folder yet */}
  }

  /// Bin a completed file we turned out not to want, and the staging folder it came in.
  Future<void> _discardStaged(String path) async {
    try {
      final f = File(path);
      await f.delete();
      await f.parent.delete();
    } catch (_) {/* already gone, or the folder still holds something */}
  }

  /// Eén regel per uitkomst, kort genoeg om honderd pogingen naast elkaar te kunnen lezen.
  static String _uitkomst(SlskResult r) => switch (r) {
        SlskDone() => 'GELEVERD',
        SlskQueued(place: final p) => 'in de wachtrij${p > 0 ? " (plaats $p)" : ""}',
        SlskCancelled() => 'gestopt',
        // Geen vangnet-tak: SlskResult is gesloten, dus als er ooit een uitkomst bijkomt hoort de
        // compiler te klagen in plaats van hem stil als "onbekend" weg te schrijven.
        SlskFail(reason: final w) => 'mislukt: $w',
      };

  static String _kort(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes}m${d.inSeconds % 60}s' : '${d.inSeconds}s';

  // ── FLAC is koning: de staande wens ──────────────────────────────────────
  //
  // De eenmalige jacht hierboven blijft staan voor de snelle winst -- als er NU een betere bron is,
  // is tien minuten wachten de beste kans. Wat eronder ligt is het lange spel: een lijst die een
  // herstart overleeft en dagen blijft proberen, omdat peers per dag wisselen.

  late final LosslessWants _wants =
      LosslessWants('$_appDir${Platform.pathSeparator}lossless_wanted.json');
  bool _wantsLoaded = false;
  bool _sweeping = false;

  Future<void> _ensureWants() async {
    if (_wantsLoaded) return;
    _wantsLoaded = true;
    await _wants.load();
  }

  /// Hoeveel nummers wachten er nog op hun FLAC. Voor het scherm en voor het logboek.
  int get losslessWanted => _wants.count;

  /// Zet dit nummer op de lijst. De TAGS beslissen wat er gezocht wordt, niet de bestandsnaam van de
  /// peer: die heet bij de een "215 - sabien tiels - trein.flac" en bij de ander "5-03 Sabien Tiels -
  /// Trein.mp3", en daar valt geen zoekvraag van te maken.
  Future<void> _wantLossless(DownloadJob job, SoulseekFile landed) async {
    final t = job.authority;
    if (t == null || t.artist.trim().isEmpty || t.title.trim().isEmpty) {
      _log.line('"${job.name}": lossy geland, maar zonder artiest+titel valt er niets te wensen');
      return;
    }
    if (haveLossless?.call(t.artist, t.title) ?? false) return; // je hebt hem al, elders
    await _ensureWants();
    final nieuw = _wants.want(LosslessWant(
      artist: t.artist.trim(),
      title: t.title.trim(),
      album: t.album,
      sinceMs: DateTime.now().millisecondsSinceEpoch,
      // Het gezag van DEZE landing gaat mee: de FLAC die de mp3 dagen later vervangt hoort op dezelfde
      // plek en met dezelfde nummering te belanden, ook als de peer een bestand zonder tags stuurt.
      authority: t,
      // En de naam waar peers hun bestand naar noemen, uit de bestandsnaam van deze peer. Op een
      // verzamelaar is dat de enige echte artiestennaam die er te vinden is.
      performer: performerFromFilename(landed.displayName, t.title),
    ));
    if (nieuw) {
      await _wants.save();
      _log.line('"${job.name}": lossy geland — FLAC blijft gewenst '
          '(${_wants.count} op de lijst)');
    }
  }

  /// Loop de wensen af die aan de beurt zijn, met een VERSE zoekopdracht per wens.
  ///
  /// Vers zoeken is het hele punt. De opgeslagen kandidaten van gisteren zijn de peers van gisteren;
  /// resumePending doet het hierom al zo, en dat is precies waarom een hervatte download vandaag een
  /// andere peer vond die in twee seconden leverde waar de enige van gisteren geband bleek.
  Future<int> sweepLosslessWants() async {
    if (_sweeping) return 0;
    _sweeping = true;
    try {
      await _ensureWants();
      final have = haveLossless;
      if (have != null) {
        final weg = _wants.forgetWhatWeHave(have);
        if (weg.isNotEmpty) {
          await _wants.save();
          _log.line('wensen: ${weg.length} vervallen — die FLAC staat al in de bibliotheek');
        }
      }
      final nu = DateTime.now().millisecondsSinceEpoch;
      final rij = _wants.due(nu);
      if (rij.isEmpty) return 0;
      _log.line('wensen: ${rij.length} van ${_wants.count} aan de beurt');
      var gehaald = 0;
      for (final w in rij) {
        if (await _chaseWant(w)) gehaald++;
      }
      await _wants.save();
      return gehaald;
    } finally {
      _sweeping = false;
    }
  }

  /// Eén wens: zoek opnieuw, sla geweigerde peers over, en probeer de beste lossless.
  Future<bool> _chaseWant(LosslessWant w) async {
    List<SoulseekFile> hits;
    try {
      hits = await soulseek.search(w.query);
    } catch (_) {
      return false; // geen net; de wens blijft staan en het ritme schuift niet op
    }
    final lossless = hits
        .where((f) => isLossless(f) && !isMultichannel(f))
        .where((f) => !w.refused.containsKey(f.username))
        .toList()
      ..sort(_rankSlsk);
    _log.line('wens "${w.artist} — ${w.title}": ${hits.length} treffers, '
        '${lossless.length} bruikbaar lossless (poging ${w.tries + 1}'
        '${w.refused.isEmpty ? "" : ", ${w.refused.length} peers overgeslagen"})');
    if (lossless.isEmpty) {
      _wants.update(w.met(tries: w.tries + 1, lastTryMs: DateTime.now().millisecondsSinceEpoch));
      return false;
    }

    final job = DownloadJob(w.title);
    final geweigerd = Map<String, String>.of(w.refused);
    var goed = false;
    try {
      await soulseek.withSession((session) async {
        for (final f in lossless.take(4)) {
          final t0 = DateTime.now();
          SlskResult res;
          try {
            // Ruim wachten mag hier: deze jacht houdt geen downloadslot bezig en er zit niemand op te
            // wachten. Een plaats in een wachtrij is waardevol -- weggooien is wat de app hiervoor deed.
            res = await _rawTransfer(session, f, job, () {},
                waitInQueue: true, maxWait: const Duration(minutes: 30));
          } catch (_) {
            continue;
          }
          _log.line('   ${f.username}: ${_uitkomst(res)}  na ${_kort(DateTime.now().difference(t0))}');
          if (res is SlskFail) {
            final reden = res.reason.toLowerCase();
            // Onthouden, want de enige lossless bron voor een nummer kan er één zijn. Zonder dit
            // verbrandt elke ronde zijn poging op dezelfde peer die het account geband heeft.
            if (reden.contains('banned') || reden.contains('geweigerd')) {
              geweigerd[f.username] = 'banned';
            } else if (reden.contains('firewall')) {
              geweigerd[f.username] = 'firewall';
            }
            continue;
          }
          if (res is! SlskDone) continue;
          try {
            // Het gezag van de wens, niet dat van dit wegwerp-job: een peer stuurt geregeld een
            // bestand zonder één tag, en dan landt het als "Onbekende artiest" in Singles. Precies wat
            // de eerste echte vondst deed voordat dit erin stond.
            await placeFileDetailed(File(res.path), _downloadsRoot,
                tags: w.authority ??
                    TrackTags(title: w.title, artist: w.artist, album: w.album, trackNo: 0),
                staatAl: mapVanBestaande);
          } catch (_) {/* de scan vindt hem waar hij ook landde */}
          goed = true;
          return;
        }
      });
    } catch (_) {/* niets verloren: je houdt de kopie die je had */}

    if (goed) {
      _wants.forget(w.key);
      _log.line('wens "${w.artist} — ${w.title}": FLAC binnen na ${w.tries + 1} '
          'poging${w.tries == 0 ? "" : "en"} — van de lijst');
      try {
        await onLibraryChanged();
      } catch (_) {}
      return true;
    }
    _wants.update(w.met(
        tries: w.tries + 1, lastTryMs: DateTime.now().millisecondsSinceEpoch, refused: geweigerd));
    _log.line('wens "${w.artist} — ${w.title}": nog niet — volgende poging over '
        '${_kort(wachtVoor(w.tries + 1))}');
    return false;
  }

  /// Queue a background hunt for a better copy of a track you can already play.
  void _queueUpgrade(List<SoulseekFile> better, DownloadJob job) {
    job.status = 'upgrading';
    job.detail = 'speelbaar · betere kwaliteit zoeken';
    notifyListeners();
    // Of hij meteen begint of achter een andere jacht staat, is een van de vier verklaringen voor
    // "hij kwam niet binnen" -- en de enige die je nooit op het scherm ziet.
    _log.line('"${job.name}": ${better.length} betere kandidaten, opwaarderen in de rij'
        '${_upgradeRunning ? " (er loopt al een jacht, ${_upgradeQueue.length + 1} wachtend)" : ""}');
    _upgradeQueue.add(() => _chaseUpgrade(better, job));
    unawaited(_drainUpgrades());
  }

  Future<void> _drainUpgrades() async {
    if (_upgradeRunning) return;
    _upgradeRunning = true;
    try {
      while (_upgradeQueue.isNotEmpty) {
        await _upgradeQueue.removeAt(0)();
      }
    } finally {
      _upgradeRunning = false;
    }
  }

  /// Chase a BETTER copy of a track that already landed.
  ///
  /// Bounded on purpose: you HAVE the track, so this must never cost you anything. It holds the
  /// shared session for its whole run — dipping out between peers would let the 120s idle close
  /// fire and make the next attempt a fresh LOGIN, which is what gets the account blocked — and
  /// deliberately takes no download slot, so a track you have nothing of never waits behind it.
  Future<void> _chaseUpgrade(List<SoulseekFile> better, DownloadJob job) async {
    final deadline = DateTime.now().add(_upgradeBudget);
    // A shadow job absorbs the transfer's own status/progress writes: the visible job is already
    // finished and must not flip back to "Bezig 34%" with a half-full bar.
    final shadow = DownloadJob(job.name);

    void settle(String detail) {
      if (job.cancelled) return; // a stopped job must not be forced back to 'done'
      job.status = 'done';
      job.progress = 1;
      job.detail = detail;
      notifyListeners();
    }

    _log.line('"${job.name}": jacht op betere kwaliteit start, budget ${_kort(_upgradeBudget)} '
        'voor ${better.length} peers samen');
    try {
      await soulseek.withSession((session) async {
        for (final f in better) {
          if (job.cancelled) return; // the user stopped this track; don't keep chasing it
          final left = deadline.difference(DateTime.now());
          if (left <= const Duration(seconds: 30)) {
            // DE grens waar dit stukloopt, en zonder deze regel is hij van buitenaf onzichtbaar: de
            // jacht houdt gewoon op en er komt nooit iets binnen.
            _log.line('   budget op na ${_kort(_upgradeBudget - left)} — '
                '${better.length - better.indexOf(f)} peers niet meer geprobeerd');
            return;
          }
          job.status = 'upgrading';
          job.progress = 1;
          job.detail = 'speelbaar · wacht op ${f.username} voor betere kwaliteit';
          notifyListeners();

          SlskResult res;
          final c = SlskCancel();
          job.live.add(c);
          final t0 = DateTime.now();
          try {
            res = await _rawTransfer(session, f, shadow, () {}, waitInQueue: true, maxWait: left, cancel: c);
          } catch (_) {
            _log.line('   ${f.username}: fout  na ${_kort(DateTime.now().difference(t0))}'
                '  (${_kort(left)} budget over bij de start)');
            continue;
          } finally {
            job.live.remove(c);
          }
          // De looptijd naast het resterende budget: zo zie je of een peer nog aan de gang was toen
          // het budget hem afkapte, of dat hij zelf niets deed.
          _log.line('   ${f.username}: ${_uitkomst(res)}  na ${_kort(DateTime.now().difference(t0))}'
              '  (${_kort(left)} budget over bij de start)');
          if (res is SlskCancelled) return;
          if (res is! SlskDone) continue;

          // placeFileDetailed drops the copy this supersedes — but only if it actually won.
          Placement how = Placement.stuck;
          try {
            final staged = File(res.path);
            // The SAME authority as the first landing. Without it the sweep would quietly undo the
            // numbering a quarter of an hour later, using whatever this new peer's tags happen to say.
            how = (await placeFileDetailed(staged, _downloadsRoot, tags: job.authority, staatAl: mapVanBestaande)).how;
          } catch (_) {/* the scan still finds it wherever it landed */}
          if (how == Placement.duplicate) {
            settle('had al de beste kwaliteit');
            return;
          }
          settle(how == Placement.moved
              ? 'kwaliteit verbeterd · ${f.username}'
              : 'betere kopie opgehaald, maar tags onleesbaar');
          try {
            await onLibraryChanged();
          } catch (_) {}
          return;
        }
      });
    } catch (_) {/* nothing lost — you still have the copy that landed first */}

    if (job.status == 'upgrading') {
      // Hier eindigt de jacht zonder resultaat, en dit is de regel die zegt DAT hij geëindigd is.
      // Zonder hem lijkt een opwaardering die niets vond precies op een die nog loopt -- en de app
      // begint hem niet opnieuw, ook niet na een herstart.
      _log.line('"${job.name}": jacht klaar zonder betere kopie, '
          '${_kort(_upgradeBudget - deadline.difference(DateTime.now()))} verbruikt — komt niet terug');
      settle('beste vrije kwaliteit behouden');
    }
  }

  /// The order to try peers in when hunting for one that can start RIGHT NOW.
  ///
  /// Two things the plain quality ranking got wrong, both visible on a popular track with a
  /// hundred free sources while the download sat waiting:
  ///
  /// * ONE FILE PER PEER. Ranked purely on bitrate, the top of the list is the big hi-res rips —
  ///   and those come from a handful of collectors who each offer several. Fourteen attempts then
  ///   amounted to about five actual chances, while dozens of other peers were never asked.
  /// * FREE SLOTS FIRST. A peer that says it has a slot open is the whole point of this pass.
  ///   Quality still decides between two free peers, and the background upgrade goes after the
  ///   hi-res copy afterwards — so nothing is given up, it just plays sooner.
  static List<SoulseekFile> sweepOrderFor(List<SoulseekFile> pool) {
    final bestPerPeer = <String, SoulseekFile>{};
    for (final f in pool) {
      final cur = bestPerPeer[f.username];
      if (cur == null || _slskScore(f) > _slskScore(cur)) bestPerPeer[f.username] = f;
    }
    final out = bestPerPeer.values.toList();
    out.sort((a, b) {
      if (a.freeSlots != b.freeSlots) return a.freeSlots ? -1 : 1;
      if (a.queueLength != b.queueLength) return a.queueLength.compareTo(b.queueLength);
      return _slskScore(b) - _slskScore(a);
    });
    return out;
  }

  /// Lossless (or hi-res) — the tier that may serve as a fast stand-in.
  static bool isLossless(SoulseekFile f) => _slskScore(f) >= 2000000;

  /// Worth interrupting nothing for: a real step up, not rip-to-rip noise.
  ///
  /// Two rips of the same CD differ by a few kbps as a matter of course, so a plain "higher
  /// score" would start a chase after almost every download — and then swap a perfectly good
  /// FLAC for an equally good one. Only a better TIER, or a clearly higher bitrate, counts.
  static bool clearlyBetter(SoulseekFile candidate, SoulseekFile settled) {
    final a = _slskScore(candidate), b = _slskScore(settled);
    final tierA = a ~/ 1000000, tierB = b ~/ 1000000;
    if (tierA != tierB) return tierA > tierB;
    final kbpsA = a % 1000000, kbpsB = b % 1000000;
    return kbpsB > 0 && kbpsA > kbpsB * 1.25;
  }

  /// Root of the app's own, tidily-organised download tree. Only ever writes inside here — the
  /// user's existing collection elsewhere under musicRoot is never touched or moved.
  String get _downloadsRoot => '$musicRoot${Platform.pathSeparator}DebridMusic Downloads';

  /// A peer that never delivered leaves an empty staging folder behind; drop it so `_inkomend`
  /// doesn't slowly fill with the name of every uploader we ever tried. Non-recursive on purpose:
  /// a folder that still holds a partial file is left alone.
  Future<SlskResult> _cleanStaging(Directory dir, File dest, Future<SlskResult> transfer) async {
    final res = await transfer;
    // A loser in a race can still have finished: a small file arrives inside one chunk, so the
    // peer was told "no" only after the bytes were already on disk. Nothing downstream looks at a
    // cancelled attempt, so without this the complete file sat in _inkomend forever — and kept the
    // folder non-empty, so that never got cleaned up either.
    if (res is! SlskDone) {
      try {
        await dest.delete();
      } catch (_) {/* never created, or already gone */}
    }
    try {
      await dir.delete();
    } catch (_) {/* another track of this album is still staging here — leave it */}
    return res;
  }

  /// The raw single-peer transfer over [session] (updates progress only; no status finalization).
  /// [claim] turns this into one runner in a race: it fires the moment the peer's first bytes
  /// arrive, and returns whether this attempt gets to own the job's progress line. A runner that
  /// is told no cancels itself. Without it the attempt drives the UI on its own, as a lone
  /// download does.
  Future<SlskResult> _rawTransfer(
      SlskSession session, SoulseekFile file, DownloadJob job, void Function() onQueued,
      {bool waitInQueue = true,
      Duration maxWait = const Duration(minutes: 30),
      SlskCancel? cancel,
      bool Function()? claim}) async {
    // Land in a staging folder; placeFile() moves it into Albums/Singles/Compilaties after.
    // Per-PEER subfolder: candidates for the same track share a display name, so a slow attempt
    // that is still winding down can never write into the file the next attempt just opened.
    final dir = Directory(
        '$_downloadsRoot${Platform.pathSeparator}_inkomend${Platform.pathSeparator}${_sanitize(file.username)}');
    await dir.create(recursive: true);
    final dest = File('${dir.path}${Platform.pathSeparator}${_sanitize(file.displayName)}');
    var settled = claim == null; // no race → this attempt owns the UI from the start
    var mine = claim == null;
    // Alleen bij een VERANDERING, want een peer herhaalt zijn plaats. Zonder deze regel is een
    // download die in een wachtrij staat onzichtbaar in het logboek tot hij eindigt -- en dat is juist
    // het geval dat we willen kunnen nakijken. Bleek bij het uittesten van het logboek zelf.
    var laatstePlaats = -1;
    return _cleanStaging(dir, dest, session.download(file, dest, (rec, tot) {
      if (!settled && rec > 0) {
        settled = true;
        mine = claim!(); // first bytes decide the race; a runner told no stops itself
      }
      // A stop is final. Bytes already in flight arrive for a moment afterwards, and letting them
      // write here turned "Gestopt" back into "Bezig 34%" — leaving the job permanently busy, which
      // made the duplicate guard refuse that track for the rest of the session.
      if (!mine || job.cancelled) return;
      if (job.status != 'downloading') {
        job.status = 'downloading'; // bytes are flowing — the wait is over
        job.queuePlace = 0;
        job.detail = file.username;
        notifyListeners(); // on its own: a peer that never sends a size has no progress to report
      }
      if (tot > 0) {
        final p = (rec / tot).clamp(0.0, 1.0);
        if (p - job.progress > 0.02) {
          job.progress = p;
          notifyListeners();
        }
      }
    }, onStatus: (q) {
      if (q.place != laatstePlaats) {
        laatstePlaats = q.place;
        _log.line('   ${file.username}: wachtrij${q.place > 0 ? " plaats ${q.place}" : " (plaats onbekend)"}');
      }
      // In a race the job line belongs to the race, which knows about all the runners; one of
      // twenty peers announcing its queue position would just fight the other nineteen for it.
      if (claim == null) {
        job.status = 'waiting';
        job.queuePlace = q.place;
        job.detail = q.place > 0 ? 'wachten op ${file.username} · plaats ${q.place}' : 'wachten op ${file.username}';
        notifyListeners();
      }
      onQueued();
    }, waitInQueue: waitInQueue, maxWait: maxWait, cancel: cancel));
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
  /// [authorities] is parallel to [tracks]: what each one IS according to the official release,
  /// or null where nothing on that release matched. A whole folder from one peer is still one
  /// peer's idea of the record — its internal numbering is no more trustworthy than a single file's.
  Future<int> enqueueSoulseekAlbum(List<List<SoulseekFile>> tracks,
      {List<TrackTags?> authorities = const []}) async {
    if (!soulseek.available) throw 'Stel je Soulseek-login in (Instellingen).';
    final running = <Future<bool>>[];
    for (var i = 0; i < tracks.length; i++) {
      final cands = tracks[i];
      if (cands.isEmpty) continue;
      final job = DownloadJob(cands.first.displayName, status: 'queued')
        ..authority = i < authorities.length ? authorities[i] : null;
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

  /// Fetch one file of a torrent to disk.
  ///
  /// Two things here were only true on the happy path, and both of them put broken music in the
  /// library. The handle and the connection were closed AFTER the loop, so an aborted stream — wifi
  /// dropping, the CDN hanging up — jumped to the catch and left them open. On Windows that stray
  /// handle means the truncated file cannot be moved or deleted for the rest of the session, so the
  /// cleanup, the filing into the library and the duplicate sweep all fail on exactly the files that
  /// need them. [SoulseekClient._pump] already gets this right, with a comment saying why.
  ///
  /// And there was no size check at all: progress went to 1 and the status to 'done' regardless. A
  /// stream that ends early but cleanly is not an error anywhere in this function, so a CDN cutting
  /// off mid-file produced a forty-second track that the app called finished.
  Future<void> _download(int torrentId, TbFile f, Directory destDir, DownloadJob job) async {
    http.Client? client;
    IOSink? sink;
    File? dest;
    var complete = false;
    try {
      final url = await online.resolveTrackUrl(torrentId, f.id);
      client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw 'HTTP ${resp.statusCode}';
      final total = resp.contentLength ?? f.size;
      dest = File('${destDir.path}${Platform.pathSeparator}${_sanitize(f.label)}');
      sink = dest.openWrite();
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
      // Short of what was announced is a failure, however politely the stream ended. Only when the
      // length was never announced (total <= 0) is "it ended" all we have to go on.
      complete = total <= 0 ? received > 0 : received >= total;
      if (!complete) throw 'incompleet: $received van $total bytes';
    } catch (_) {
      job.status = 'failed';
      notifyListeners();
      return;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client?.close();
      // A part-file must not survive: the scanner does not skip this folder, so what is left here
      // ends up in the library as a track that stops halfway.
      if (!complete && dest != null) {
        await dest.delete().catchError((_) => dest!);
      }
    }
    job.progress = 1;
    job.status = 'done';
    notifyListeners();
    await onLibraryChanged();
  }

  String _sanitize(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}
