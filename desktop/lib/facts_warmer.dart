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

import 'album_facts.dart';
import 'album_facts_resolver.dart';
import 'discogs.dart';
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
enum _Art { fetched, already, failed }

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
}) =>
    DiscogsService(settings)
        .releaseArt(artist, album,
            expectedTracks: expectedTracks, pinned: pinned, pinnedMbid: pinnedMbid, roles: roles)
        .then((_) {});

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
  }) warmArt;

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
    library.addListener(_onLibraryChanged);
    // Side by side, not one after the other. The artwork loop is the one that decides whether
    // opening a record is instant, and it must not wait for two dozen tracklists first.
    //
    // The flag goes up BEFORE either starts. Without it the artwork loop can finish its first pass,
    // find nothing (because no tracklist has landed yet), see no facts sweep running, and stop —
    // before the facts sweep has so much as begun. Awaited so a caller can tell when both are done;
    // main() does not wait for this.
    _factsPending = true;
    final art = _artSweep();
    try {
      await _sweep();
    } finally {
      _factsPending = false;
    }
    await art;
  }

  /// A facts sweep is running or about to. The artwork loop keeps looking round while this is true,
  /// because an album it skipped for want of a tracklist may be about to get one.
  bool _factsPending = false;

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
      _factsPending = true;
      unawaited(_artSweep());
      unawaited(_sweep().whenComplete(() => _factsPending = false));
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
          pinned: library.pinnedRelease(a))) {
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

    final todo = _todo();
    _log.line('feiten: veeg start, ${todo.length} te doen van ${library.albums.length} albums');
    if (todo.isEmpty) return;

    _running = true;
    _done = 0;
    _total = todo.length;
    notifyListeners();

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
          );
        } catch (e) {
          _log.line('feiten: "${album.title}" gooide $e — veeg gestopt');
          break;
        }

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
            notifyListeners();
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
        notifyListeners();
      }
      // Anything still held at a clean finish was a genuine miss among successes.
      for (final h in held) {
        library.facts.put(h);
      }
    } finally {
      _running = false;
      await library.facts.flush();
      notifyListeners();
      _log.line('feiten: veeg klaar, $_done van $_total behandeld');
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
      // Keep going while the facts sweep is still producing albums to work on: an album skipped
      // because its tracklist had not landed yet must get another turn, or the two loops racing
      // would cost exactly the coverage this exists for.
      for (var round = 0; round < 200; round++) {
        if (_stopped || !settings.warmFacts) break;
        if (await _warmMissingArt() > 0) continue;
        if (!_factsPending) break; // nothing left, and no tracklists on the way either
        await Future.delayed(rearmDelay);
      }
    } finally {
      _artRunning = false;
      notifyListeners();
    }
  }

  bool _artRunning = false;

  /// One pass over the library. Returns how many records had their scans fetched.
  Future<int> _warmMissingArt() async {
    var did = 0, geenFeiten = 0, alWarm = 0, overgeslagen = 0;
    for (final album in _byNewest()) {
      if (_stopped || !settings.warmFacts || library.scanning) {
        _log.line('scans: ronde afgebroken (gestopt=$_stopped aan=${settings.warmFacts} scan=${library.scanning})');
        break;
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
          _log.line('scans: "${album.title}" opgehaald');
        case _Art.already:
          alWarm++; // one file check, no network — not progress, and not a reason to stop
        case _Art.failed:
          _log.line('scans: "${album.title}" MISLUKT — ronde gestopt '
              '(opgehaald=$did alwarm=$alWarm geenfeiten=$geenFeiten)');
          return did; // usually the network; the next fifty fail the same way
      }
    }
    _log.line('scans: ronde klaar — opgehaald=$did alwarm=$alWarm '
        'geenfeiten=$geenFeiten overgeslagen=$overgeslagen feitenLoopt=$_factsPending');
    return did;
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
      return _Art.already;
    }
    try {
      await warmArt(album.artist, album.title,
          expectedTracks: expected,
          pinned: pinned,
          pinnedMbid: mbid,
          roles: roles,
          settings: settings);
      _artDone++;
      notifyListeners();
      return _Art.fetched;
    } catch (e) {
      _log.line('scans: "${album.title}" gooide $e');
      return _Art.failed;
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
      unawaited(_sweep());
    });
  }

  late Duration _nextBackoff = outageBackoff;

  @override
  void dispose() {
    stop();
    library.removeListener(_onLibraryChanged);
    super.dispose();
  }
}
