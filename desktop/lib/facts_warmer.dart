/// Looking records up before you ask for them.
///
/// One album costs two MusicBrainz requests the first time and nothing ever after. Doing that on
/// demand means the first visit to every record still waits — a second and a half now rather than
/// seven, but still a wait, and always at the worst moment. The machine that owns the music is
/// sitting there anyway, so it works through the library quietly instead.
///
/// **Only on the PC.** A phone or a television asks the PC for facts (`/api/album/facts`), so
/// warming there would be four devices doing the same work against one shared per-second budget.
/// Constructed everywhere so the provider tree is uniform; inert unless it owns the music.
///
/// The dangerous part is not the loop, it is what happens when the network is gone. A failed
/// lookup writes `failedMs` and blinds that album for a day, and an offline sweep can do that to a
/// whole library in seconds — once the miss cache is warm it answers instantly. So empty answers
/// are HELD rather than stored, and three in a row without a success is read as an outage: throw
/// them away, stop, and come back later. That guard is the reason this is safe to ship.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'acoustid.dart';
import 'album_facts.dart';
import 'album_facts_resolver.dart';
import 'discogs.dart';
import 'fingerprint.dart';
import 'library.dart';
import 'models.dart';
import 'musicbrainz.dart';
import 'settings.dart';

/// How many empty answers in a row mean "the network is gone" rather than "three obscure records".
///
/// The asymmetry decides the number. Guess too low and three albums get looked at again next time.
/// Guess too high and an offline sweep writes `failedMs` across the whole library, which blinds
/// every album page for twenty-four hours. Three, and lean on the cheap side of that trade.
const int _outageAfter = 3;

/// What one album's artwork attempt came to. "Already there" is not progress and not a failure, and
/// telling those two apart is what stops the artwork loop from either spinning or giving up.
enum _Art { fetched, already, failed, tooSlow }

/// How long one record may spend on its scans before the queue moves on without it.
///
/// The point is that one expensive record must not hold up the rest: read off warm.log, "Het Beste
/// Van Petra" (eighteen tracks, no MusicBrainz id) ran for over three minutes with seventy-eight
/// records waiting behind it.
///
/// Ninety seconds, not twenty-five, and that number came from measuring too. At twenty-five EVERY
/// album timed out — including ones with an id taking the short path — while the cache still grew by
/// three in three minutes, because the abandoned fetches finished in the background afterwards. So
/// the real cost of one record is around a minute, most of it image bytes: three scans at 1200px.
/// Cutting that off at twenty-five seconds abandoned work that was nearly done and then paid for it
/// again on the next round.
///
/// The abandoned fetch keeps running — a Dart timeout does not cancel work — so it may still finish
/// and fill the cache. This only stops the queue from waiting on it.
/// Twenty seconds. Traced from inside the chain, the free sources finish in under six: the archive
/// answers in two and a half and TheAudioDB in a fifth of a second. Ninety was set when the chain
/// still ran on to Discogs; it no longer does when warming, so ninety is only how long the queue sits
/// still when something goes wrong.
const _artDeadline = Duration(seconds: 20);

/// Abandonments in one round before the round gives up. One slow record is normal; six in a row means
/// something is systematically slow and hammering on is how you pile up runaway fetches.
const _tooSlowLimit = 5;


/// A written record of what the warmer decided, in `warm.log` beside the other state files.
///
/// This exists because four attempts at fixing "the counter sticks at 15" were spent guessing. A
/// release build strips [debugPrint], so from the outside the warmer is a black box: the only
/// signals were a counter that turns out to count something other than progress, and a cache
/// directory that either grows or does not. Everything else was inference.
///
/// Deliberately blunt: append a line, truncate when it gets long, never throw. A logger that can
/// break the thing it observes is worse than none.
class WarmLog {
  WarmLog(this._path);
  final String _path;

  /// Kept small enough to read in one go and to never matter on disk. Rewritten from the tail rather
  /// than rotated: there is nothing here worth keeping across sessions.
  static const _maxBytes = 256 * 1024;

  void line(String s) {
    try {
      final f = File(_path);
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        final keep = f.readAsStringSync();
        f.writeAsStringSync(keep.substring(keep.length ~/ 2), flush: true);
      }
      final t = DateTime.now().toIso8601String().substring(11, 23);
      f.writeAsStringSync('$t  $s\n', mode: FileMode.append, flush: true);
    } catch (_) {/* observing must never break the observed */}
  }
}

/// Pull an album's scans into the on-disk cache. The default [FactsWarmer.warmArt].
///
/// Returns nothing on purpose: the caller does not want the bytes, it wants them to be on disk by
/// the time the page asks. [DiscogsArtwork.releaseArt] owns the cache key and the in-flight table,
/// so a page that opens mid-warm joins the same fetch instead of starting a second one.
Future<void> fetchReleaseArt(
  String artist,
  String album, {
  required int expectedTracks,
  int? pinned,
  String? pinnedMbid,
  required Map<String, String> roles,
  required AppSettings settings,
  void Function(String)? trace,
  bool freeOnly = true,
}) =>
    DiscogsService(settings)
        .releaseArt(artist, album,
            expectedTracks: expectedTracks,
            pinned: pinned,
            pinnedMbid: pinnedMbid,
            roles: roles,
            trace: trace,
            // The archive and TheAudioDB only. Traced on the real library: those two are done in 2.7
            // seconds, and the Discogs chain after them had not returned in eighty-seven. Seventy-nine
            // records at ninety seconds each is not a background task, it is a week.
            freeOnly: freeOnly)
        .then((_) => trace?.call('  [kunst] releaseArt() teruggekeerd'));

class FactsWarmer extends ChangeNotifier {
  FactsWarmer({
    required this.library,
    required this.settings,
    required this.mb,
    required this.enabled,
    this.resolve = resolveAlbumFacts,
    this.warmArt = fetchReleaseArt,
    this.rearmDelay = const Duration(seconds: 10),
    this.outageBackoff = const Duration(minutes: 15),
    this.scanWait = const Duration(minutes: 3),
    this.factsDeadline = const Duration(seconds: 90),
  });

  final LibraryStore library;
  final AppSettings settings;
  final MusicBrainzService mb;

  /// False on anything that is not the machine holding the music.
  final bool enabled;

  /// Injected so a test can drive the whole loop without a socket.
  final Future<AlbumFacts> Function(
    Album album, {
    required String uid,
    required String trackSetHash,
    required MusicBrainzService mb,
    required AppSettings settings,
    String? pinnedMbid,
    int? pinned,
    DiscogsService? discogs,
  }) resolve;

  /// Injected for the same reason [resolve] is: a test drives the whole loop without a socket.
  final Future<void> Function(
    String artist,
    String album, {
    required int expectedTracks,
    int? pinned,
    String? pinnedMbid,
    required Map<String, String> roles,
    required AppSettings settings,
    bool freeOnly,
    void Function(String)? trace,
  }) warmArt;

  /// Per-step timings from inside the artwork chain, when something wants them.
  ///
  /// Set by [FactsWarmer] so warm.log shows where a record's ninety seconds went. Nullable because a
  /// test's stub has no chain to trace.
  void Function(String)? artTrace;

  /// How long one record may spend on its tracklist before the queue moves on without it.
  ///
  /// Ninety seconds, and that is generous on purpose: a record MusicBrainz has never heard of falls
  /// through to Discogs, which really is about thirty-six requests a second apart. What it is not
  /// generous about is forever. Note that a Dart timeout does not cancel the work — the abandoned
  /// lookup may still finish and fill the caches; this only stops the queue from waiting on it.
  final Duration factsDeadline;

  /// How long the artwork round is willing to sit out a disk scan before giving up on this round.
  ///
  /// Three minutes because that is comfortably longer than a scan of this library takes and far
  /// shorter than an evening. Injected so a test does not have to wait it out.
  final Duration scanWait;

  final Duration rearmDelay;
  final Duration outageBackoff;

  bool _running = false;
  bool _stopped = false;
  int _done = 0;
  int _total = 0;

  /// Albums attempted this session, so one that resolved to nothing is never picked twice — even
  /// though nothing was written for it.
  final Set<String> _tried = {};

  Timer? _rearm;
  Timer? _retry;

  bool get running => _running;
  int get done => _done;
  int get total => _total;

  /// Something to put in the status line, or empty when there is nothing to say.
  String get status => _running && _total > 0 ? 'Albuminfo ophalen… $_done/$_total' : '';

  /// Begin, and keep an ear on the library so records added later get picked up too.
  Future<void> start() async {
    if (!enabled || library.isRemote) return;
    // The rate-limit lane gets somewhere to write. Without it warm.log stops at "naar Discogs" and
    // the ten minutes after that are unaccounted for.
    DiscogsService.laneTrace = _log.line;
    MusicBrainzService.laneTrace = _log.line;
    resolveTrace = _log.line;
    AcoustIdService.trace = _log.line;
    // Said once, at the top, because "is the helper actually there" is the first question every
    // fingerprint problem starts with — and a packaging mistake is invisible from inside the app.
    final fp = Fingerprinter();
    _log.line(fp.available ? 'fpcalc: ${fp.tool}' : 'fpcalc: NIET gevonden — geen vingerafdrukken');
    library.addListener(_onLibraryChanged);
    // Artwork FIRST, and on its own. Side by side was the mistake, and warm.log said so: both loops
    // started, and two minutes later the artwork round had not finished its FIRST album. Two loops
    // sharing one per-second budget simply halve each other. So one at a time, and the one the user
    // notices goes first — 79 of 130 records already have their tracklist and are missing only their
    // scans, which is exactly what makes opening a record feel slow.
    await _artSweep();
    await _wantFacts();
    // Once more, for the records the facts sweep just resolved.
    await _artSweep();
    // There is no Discogs pass here, and that is a decision rather than an omission.
    //
    // One was built and measured over six releases. It never completed a single record. Every round
    // found a different reason — it gave up when a scan was running, it rode on a free-only chain
    // that skips Discogs by design, it had no trace at all — and each was fixed, and the next one
    // appeared. The last trace says it plainly: the free sources finish a record in 124 milliseconds
    // and the very first Discogs call then runs for nine minutes without the rate-limit lane
    // reporting a single queued request.
    //
    // It was also the wrong shape. Discogs already runs when someone OPENS an album, which is where
    // its cost is worth paying: one record, on demand, with a person waiting. Warming it for a
    // hundred and thirty records ahead of time holds the one lane that path needs. The free sources
    // are what background work should use — they warm the whole library in minutes.
  }

  /// How many facts sweeps have been asked for and not yet finished.
  ///
  /// A counter, not a flag, and that is the whole point. As a bool it was set true by the rearm timer
  /// and cleared in `whenComplete` — but a second [_sweep] while one is already running returns
  /// immediately at its re-entrancy guard, so `whenComplete` fired at once and cleared the flag while
  /// the first sweep was still going. The artwork loop then saw "no tracklists on the way", broke,
  /// and nothing ever restarted it. One stray notifyListeners from the library was enough to end
  /// artwork warming for the session.
  int _factsWanted = 0;
  bool get _factsPending => _factsWanted > 0;

  /// Ask for a facts sweep and keep [_factsPending] true for as long as this request is outstanding.
  Future<void> _wantFacts() {
    _factsWanted++;
    return _sweep().whenComplete(() => _factsWanted--);
  }

  /// Which record is being looked up right now, by uid, or null when nothing is.
  ///
  /// A ValueNotifier and not part of [notifyListeners] on purpose. A hundred and thirty album tiles
  /// listening to the warmer would each rebuild on every counter tick; this way only the two-pixel
  /// line inside a card is rebuilt, and only when the value actually changes.
  ///
  /// Static because the tiles have no route to the warmer instance — it lives at the top of the
  /// provider tree and they are built deep inside a grid — and because there is only ever one.
  static final ValueNotifier<String?> busyAlbum = ValueNotifier<String?>(null);

  /// Set around one record's work and cleared after, whatever the outcome.
  void _busy(String? uid) {
    if (busyAlbum.value != uid) busyAlbum.value = uid;
  }

  late final WarmLog _log = WarmLog('${library.configDir}${Platform.pathSeparator}warm.log');

  void stop() {
    _stopped = true;
    _rearm?.cancel();
    _retry?.cancel();
    _rearm = null;
    _retry = null;
  }

  void _onLibraryChanged() {
    // The library notifies once per cover during enrichment — hundreds of times — so this waits for
    // quiet. `_tried` is deliberately NOT cleared: a library that notifies mid-sweep would
    // otherwise restart the sweep forever.
    _rearm?.cancel();
    _rearm = Timer(rearmDelay, () {
      unawaited(_artSweep());
      unawaited(_wantFacts());
    });
  }

  /// The albums that still need looking up, newest first.
  ///
  /// Re-derived every sweep rather than held: `rebuildAlbums()` replaces every Album object, so a
  /// kept list would be pointing at records that no longer exist.
  List<Album> _todo() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <Album>[];
    for (final a in library.albums) {
      // Singles are never resolved by the album page either, and an album with no uid has nowhere
      // to store an answer. Neither is a tidy extra check: leave either out and the sweep picks the
      // same record every pass, forever, because nothing is ever written for it.
      if (a.isSingle) continue;
      final uid = library.uidOf(a);
      if (uid.isEmpty || _tried.contains(uid)) continue;
      if (!needsResolve(library.facts.get(uid),
          trackSetHash: library.trackSetHashFor(a),
          nowMs: now,
          pinnedMbid: library.pinnedMbid(a),
          pinned: library.pinnedRelease(a),
          canHear: canHear(settings))) {
        continue;
      }
      out.add(a);
    }
    // A record that just finished downloading is the one about to be opened.
    out.sort((x, y) => y.addedMs.compareTo(x.addedMs));
    return out;
  }

  Future<void> _sweep() async {
    if (_running || _stopped || !enabled || library.isRemote) return;
    if (!settings.warmFacts) return;
    if (library.scanning) return; // the album list is about to be replaced anyway

    // The scans get the line to themselves while they are working.
    //
    // Making start() call these one after the other was not enough, and warm.log said so: the artwork
    // sweep began at 09:29:08 and twelve seconds later the rearm timer launched the facts sweep
    // alongside it anyway. Both then shared sixty Discogs requests a minute — and this app triples its
    // own spacing once fewer than twelve are left — so every record ran past ninety seconds and five
    // minutes produced nothing. "One at a time" has to be enforced here, not just in the caller.
    if (_artRunning) {
      _log.line('feiten: uitgesteld, de scans zijn aan de beurt');
      _rearm?.cancel();
      _rearm = Timer(rearmDelay, () => unawaited(_wantFacts()));
      return;
    }

    final todo = _todo();
    _log.line('feiten: veeg start, ${todo.length} te doen van ${library.albums.length} albums');
    if (todo.isEmpty) return;

    _running = true;
    _done = 0;
    _total = todo.length;
    _notify();

    // Empty answers are HELD, not stored — see the note at the top of this file.
    final held = <AlbumFacts>[];
    var blanks = 0;

    try {
      for (final album in todo) {
        if (_stopped || !settings.warmFacts) break;
        if (library.scanning) break;
        final uid = library.uidOf(album);
        if (uid.isEmpty) continue;
        _tried.add(uid); // before the attempt, so a throw cannot cause a re-pick

        // Logged before the attempt, with the clock, for the same reason the artwork round is:
        // without it a facts sweep is a black box. Measured on the real library, this one ran nine
        // minutes on twenty-eight records without writing a single line — a record MusicBrainz does
        // not have falls through to Discogs, which is about thirty-six requests at a second apart.
        // That is fine, and it is completely unreadable from the outside.
        final begonnen = DateTime.now();
        _log.line('feiten: "${album.title}" ophalen… ($_done/$_total)');
        _busy(uid);

        AlbumFacts fresh;
        try {
          fresh = await resolve(
            album,
            uid: uid,
            trackSetHash: library.trackSetHashFor(album),
            mb: mb,
            settings: settings,
            pinnedMbid: library.pinnedMbid(album),
            pinned: library.pinnedRelease(album),
          ).timeout(factsDeadline);
        } on TimeoutException {
          // The queue moves on. It does not retry: this record is already in [_tried], so it gets
          // its turn again next session rather than blocking this one twice.
          //
          // The artwork round has had a deadline since the day it was written, and that is exactly
          // why it finishes. This one had none, and on the real library "Vlaamse Diva's" held the
          // remaining twenty-eight records for three-quarters of an hour — no cache file written, no
          // socket open, nothing to see. One slow record is a nuisance; one stuck record without a
          // deadline is the whole sweep.
          _log.line('feiten: "${album.title}" te traag — overgeslagen, de rij gaat door');
          continue;
        } catch (e) {
          _log.line('feiten: "${album.title}" gooide $e — veeg gestopt');
          break;
        }
        _log.line('feiten: "${album.title}" klaar in '
            '${DateTime.now().difference(begonnen).inSeconds}s '
            '(${fresh.source.isEmpty ? "niets" : fresh.source}, ${fresh.tracklist.length} nummers)');

        if (fresh.isEmpty) {
          held.add(fresh);
          // Only a lookup that BROKE counts towards the outage guard. A record MusicBrainz and
          // Discogs simply do not have is not evidence of anything, and the library has plenty:
          // eleven of those in a row tripped the guard on every single run, which cleared the held
          // answers, scheduled a retry an hour out, and left the counter frozen at 15 of 26 — with
          // everything after it, including all the artwork, never reached. That is the whole reason
          // warming looked broken. See AlbumFacts.networkFailed.
          if (!fresh.networkFailed) {
            blanks = 0;
            _log.line('feiten: "${album.title}" niet in de catalogi — door');
            // Counted as handled. It used to leave the counter where it was, so eleven unknown
            // records in a row read as "frozen at 15 of 26" while the sweep was in fact working.
            _done++;
            _notify();
            continue;
          }
          _log.line('feiten: "${album.title}" opzoeking BRAK (${blanks + 1}/$_outageAfter)');
          if (++blanks >= _outageAfter) {
            // Treat it as an outage: throw the held failures away so NOTHING carries failedMs, and
            // come back later. Storing them would blind those albums for a day over a dropped
            // wifi connection, and a warmer can do that to a whole library in seconds — the miss
            // cache answers instantly once it is warm.
            _log.line('feiten: $_outageAfter gebroken opzoekingen op rij — gestopt, nieuwe poging later');
            held.clear();
            _scheduleRetry();
            break;
          }
          continue;
        }

        // A real answer proves the network is there, so the failures before it were real too.
        blanks = 0;
        for (final h in held) {
          library.facts.put(h);
        }
        held.clear();
        library.facts.put(fresh, folder: library.sidecarFolderFor(album));
        _done++;
        _notify();
      }
      // Anything still held at a clean finish was a genuine miss among successes.
      for (final h in held) {
        library.facts.put(h);
      }
    } finally {
      _running = false;
      _busy(null);
      await library.facts.flush();
      _notify();
      _log.line('feiten: veeg klaar, $_done van $_total behandeld');
    }

    // A tracklist that just landed is a record whose scans can now be fetched, and until this line
    // existed nothing went back for them. start() calls the artwork sweep once more after its facts
    // sweep, which covers the launch — but a record that arrives later, from Soulseek, only got a
    // rearm that woke the FACTS sweep. Its scans then waited for the next unrelated library change.
    // That is the "as soon as a track comes in it should be instant" case, and this is the return
    // trip that makes it true.
    // Awaited, not fired and forgotten. Unawaited, this returns to [start] with `_artRunning` already
    // true, so start's own follow-up sweep hits the re-entrancy guard and returns at once — and start
    // then reports itself finished while the scans it is supposed to have warmed are still running.
    if (_done > 0 && !_stopped) {
      _log.line('feiten: $_done nieuw — scans erachteraan');
      await _artSweep();
    }
  }

  /// Second pass: albums whose facts are settled but whose scans are not.
  ///
  /// Measured after the first version of this shipped: starting the app added exactly ONE entry to
  /// the artwork cache and then stopped. Correct, and useless — the sweep above only visits albums
  /// that still need FACTS, and by then almost every album has them. Which means the records the
  /// complaint was about, the ones with a known tracklist and no scans, were never reached. ANTI is
  /// one of them.
  ///
  /// Newest first for the same reason as the main sweep, and it asks [DiscogsService.hasReleaseArt]
  /// before every fetch so a warm album costs one file check and no network at all.
  /// Its own loop, deliberately not interleaved with the facts sweep.
  ///
  /// The version before this awaited the artwork inside the facts loop, so every album waited for
  /// three image downloads before the next tracklist was even asked for. Measured with the progress
  /// line in the corner: three albums in three minutes, of twenty-six. I made that loop slower to
  /// make the artwork sooner, which is a trade nobody asked for.
  ///
  /// Two loops instead. They share the same per-second lanes into MusicBrainz and Discogs, so they
  /// cannot stampede, and neither waits for the other. Newest first, so the record that just
  /// downloaded gets its scans without standing behind two dozen tracklists.
  Future<void> _artSweep() async {
    if (_artRunning || _stopped || !enabled || library.isRemote) {
      _log.line('scans: veeg NIET gestart (loopt=$_artRunning gestopt=$_stopped '
          'aan=$enabled remote=${library.isRemote})');
      return;
    }
    if (!settings.warmFacts) {
      _log.line('scans: veeg niet gestart — warm_facts staat uit');
      return;
    }
    _log.line('scans: veeg start');
    _artRunning = true;
    try {
      // Rounds until one finds nothing new, then return. NOT a timer that keeps waking while the
      // facts sweep runs: that version wrote a line every ten seconds saying "115 skipped, 0
      // fetched" and never returned to its caller. A record whose tracklist lands later is picked up
      // by the sweep the facts round now kicks off when it finishes, not by polling for it.
      await _warmMissingArt();
      _log.line('scans: veeg klaar, $_artDone opgehaald deze sessie');
    } finally {
      _artRunning = false;
      _notify();
    }
  }

  bool _artRunning = false;

  /// Passes over the library until one adds nothing. Returns how many records had their scans
  /// fetched.
  ///
  /// More than one pass because [_artOrder] is a snapshot: a record that finishes downloading while
  /// the round is halfway through the library is simply not in the list being walked, and a single
  /// pass would leave it until the next library change woke the warmer again. Each pass only visits
  /// what is not in [_artTried], and that set only grows, so this cannot run away — a second pass
  /// with nothing new to do costs one list rebuild and no network at all, and stops.
  ///
  /// A pass that broke off early does NOT get another turn. Both reasons it breaks off — the network
  /// failing, or five records in a row abandoned — are exactly the cases where going round again
  /// means fifty more of the same. Those come back on the next rearm instead.
  Future<int> _warmMissingArt() async {
    var total = 0;
    while (true) {
      final before = _artTried.length;
      final pass = await _warmArtPass();
      total += pass.did;
      if (_stopped || pass.brokeOff || _artTried.length == before) return total;
      _log.line('scans: ${_artTried.length - before} nieuw behandeld — nog een ronde');
    }
  }

  /// Sit out a disk scan. False if it is still going after [scanWait], which is the round's cue to
  /// stop and come back later rather than sit here all evening.
  ///
  /// Polled rather than listened for. A listener would mean adding and removing one inside a loop
  /// that already has a listener on the same object, and half a second of latency costs nothing
  /// against a scan measured in tens of seconds.
  Future<bool> _waitForScan() async {
    if (!library.scanning) return true;
    _log.line('scans: even wachten, de schijfscan loopt');
    final until = DateTime.now().add(scanWait);
    while (library.scanning && !_stopped) {
      if (DateTime.now().isAfter(until)) return false;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (_stopped) return false;
    _log.line('scans: schijfscan klaar — door met de ronde');
    return true;
  }

  /// One pass over the library as it is right now.
  Future<({int did, bool brokeOff})> _warmArtPass() async {
    var did = 0, geenFeiten = 0, alWarm = 0, overgeslagen = 0, teTraag = 0;
    for (final album in _artOrder()) {
      if (_stopped || !settings.warmFacts) {
        _log.line('scans: ronde afgebroken (gestopt=$_stopped aan=${settings.warmFacts})');
        return (did: did, brokeOff: true);
      }
      // A disk scan is a PAUSE, not the end of the round.
      //
      // It used to break off here, and on the real library that fired at every launch: the first
      // round died on "scan=true" fifty seconds in, start's follow-up round died on the same flag a
      // millisecond later, and nothing warmed until a rearm timer happened to come round again.
      // Worse, a finished Soulseek download is itself what triggers a rescan — so the one moment the
      // scans are wanted most was the one moment the round gave up.
      if (!await _waitForScan()) {
        _log.line('scans: ronde afgebroken — de schijfscan duurt te lang');
        return (did: did, brokeOff: true);
      }
      final uid = library.uidOf(album);
      if (uid.isEmpty || _artTried.contains(uid)) {
        overgeslagen++;
        continue;
      }
      final facts = library.facts.get(uid);
      // Not resolved yet, or resolved to nothing. Deliberately NOT marked as tried: the facts sweep
      // may still be on its way to this album, and burning its one attempt here would leave it
      // without scans for the rest of the session.
      if (facts == null || facts.tracklist.isEmpty) {
        geenFeiten++;
        continue;
      }
      switch (await _warmArtFor(album, facts)) {
        case _Art.fetched:
          did++;
        case _Art.already:
          alWarm++; // one file check, no network — not progress, and not a reason to stop
        case _Art.tooSlow:
          // Not progress and not a failure: the queue simply stopped waiting for this one.
          if (++teTraag >= _tooSlowLimit) {
            _log.line('scans: $teTraag keer te traag — ronde gestopt, later opnieuw');
            return (did: did, brokeOff: true);
          }
        case _Art.failed:
          _log.line('scans: "${album.title}" MISLUKT — ronde gestopt '
              '(opgehaald=$did alwarm=$alWarm geenfeiten=$geenFeiten)');
          // Usually the network; the next fifty fail the same way.
          return (did: did, brokeOff: true);
      }
    }
    _log.line('scans: ronde klaar — opgehaald=$did alwarm=$alWarm geenfeiten=$geenFeiten '
        'overgeslagen=$overgeslagen tetraag=$teTraag feitenLoopt=$_factsPending');
    return (did: did, brokeOff: false);
  }



  /// Records to warm the scans for: the ones with a MusicBrainz id first, then the rest.
  ///
  /// Cost, not just recency. An id goes straight to that pressing in the Cover Art Archive — one
  /// request, then the images. Without one the chain is TheAudioDB, then an archive search across
  /// every pressing of the record, then the whole Discogs search.
  ///
  /// A DISCOGS pin deliberately does not count as cheap, and the first version of this had that
  /// wrong. It read "has some kind of pin" as "will be quick", so "Het Beste Van Petra" — no mbid,
  /// but a pinned Discogs release — sorted to the very front and was the one record that blocked
  /// everything. A Discogs pin means the metered path: sixty requests a minute, tripled spacing once
  /// the budget runs low. It belongs at the back.
  ///
  /// Newest still wins within each group, so a record that just downloaded is first among its equals.
  List<Album> _artOrder() {
    final withMbid = <Album>[], rest = <Album>[];
    for (final a in _byNewest()) {
      final mbid = library.pinnedMbid(a) ?? library.facts.get(library.uidOf(a))?.mbid ?? '';
      (mbid.isNotEmpty ? withMbid : rest).add(a);
    }
    return [...withMbid, ...rest];
  }

  /// One album's scans, with the arguments the album page will use.
  ///
  /// The arguments have to match the page's to the letter: expectedTracks and both pins are part of
  /// the cache key, so warming under a different track count means the page still fetches and the
  /// warming was wasted. The count comes from the pressing just resolved — what the page uses once
  /// the facts are in — and falls back to the file count exactly as the page does.
  Future<_Art> _warmArtFor(Album album, AlbumFacts facts) async {
    final uid = library.uidOf(album);
    final expected = facts.tracklist.length;
    final mbid = library.pinnedMbid(album) ?? facts.mbid;
    final pinned = library.pinnedRelease(album);
    final roles = library.albumArtRoles(album.artist, album.title);

    // One attempt per album per session, whatever the outcome — recorded before the attempt so a
    // throw cannot cause a re-pick.
    _artTried.add(uid);
    if (await DiscogsService(settings).hasReleaseArt(album.artist, album.title,
        expectedTracks: expected, pinned: pinned, pinnedMbid: mbid, roles: roles)) {
      return _Art.already; // one file check, nothing to show a line for
    }
    _busy(uid);
    try {
      // Logged BEFORE the call, with the clock. Without this a record that takes four minutes is
      // indistinguishable from a loop that has stopped — which is exactly the two hours I spent
      // guessing at "the counter is stuck".
      _log.line('scans: "${album.title}" ophalen… (aantal=$expected mbid=${mbid ?? "-"})');
      final t0 = DateTime.now();
      try {
        await warmArt(album.artist, album.title,
                expectedTracks: expected,
                pinned: pinned,
                pinnedMbid: mbid,
                roles: roles,
                settings: settings,
                trace: artTrace ?? _log.line)
            .timeout(_artDeadline);
      } on TimeoutException {
        _log.line('scans: "${album.title}" duurde langer dan ${_artDeadline.inSeconds}s — '
            'verder met de rest (hij loopt op de achtergrond door)');
        return _Art.tooSlow;
      }
      _artDone++;
      _notify();
      _log.line('scans: "${album.title}" klaar in ${DateTime.now().difference(t0).inSeconds}s');
      return _Art.fetched;
    } catch (e) {
      _log.line('scans: "${album.title}" gooide $e');
      return _Art.failed;
    } finally {
      // Whatever happened — fetched, abandoned, thrown — the line stops.
      _busy(null);
    }
  }

  /// Every album that could hold facts, newest first. The record that just landed is the one you are
  /// about to open.
  List<Album> _byNewest() {
    final out = [for (final a in library.albums) if (!a.isSingle) a];
    out.sort((x, y) => y.addedMs.compareTo(x.addedMs));
    return out;
  }

  /// Albums whose artwork was looked at this session, so a second sweep does not re-check them.
  final Set<String> _artTried = {};
  int _artDone = 0;

  /// How many records had their scans fetched this session. Shown nowhere yet; it is what a test and
  /// a log line read to tell "warmed" apart from "was already there".
  int get artWarmed => _artDone;

  /// Wait, then try exactly one album. Doubling to an hour, so a machine that is off the network
  /// all evening checks a handful of times rather than continuously.
  void _scheduleRetry() {
    _retry?.cancel();
    final wait = _nextBackoff;
    _nextBackoff = Duration(
        milliseconds: (_nextBackoff.inMilliseconds * 2).clamp(0, const Duration(hours: 1).inMilliseconds));
    _retry = Timer(wait, () {
      // The albums that came back empty are still in `_tried`, so this picks up where it left off
      // rather than re-attempting them. That is correct: nothing was written for them, and they
      // come round again on the next start.
      //
      // BOTH loops. This used to wake only the facts sweep, and by the time it fired the artwork loop
      // had long since seen nothing to do and broken — so every record the retry resolved got its
      // tracklist and never its scans, for the rest of the session, with nothing saying so.
      unawaited(_artSweep());
      unawaited(_wantFacts());
    });
  }

  late Duration _nextBackoff = outageBackoff;

  /// True from [dispose] onwards, so a sweep still in flight cannot notify a dead notifier.
  ///
  /// [stop] sets `_stopped`, but every one of those checks sits at the TOP of a loop or a method: a
  /// round already inside an await finishes what it was doing and reaches its `finally`, and a
  /// ChangeNotifier throws if that `finally` notifies after disposal. Quitting the app while the
  /// warmer is mid-record is exactly that, and so is a test that ends its sweep and tears the object
  /// down in the same turn.
  bool _disposed = false;

  /// [notifyListeners], minus the throw when there is no longer anything to notify.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    library.removeListener(_onLibraryChanged);
    super.dispose();
  }
}
