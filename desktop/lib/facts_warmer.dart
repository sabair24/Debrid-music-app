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

/// How long one record may spend on the Discogs chain in the backfill.
///
/// Generous on purpose: measured, that chain is about thirty-six requests spaced a second apart, and
/// three seconds each once the budget dips below a fifth. Two minutes is roughly its honest cost, and
/// cutting it shorter only throws away work that was nearly done — the mistake the free pass already
/// taught me at twenty-five seconds.
const _discogsDeadline = Duration(minutes: 2);


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
    this.discogsBreather = const Duration(seconds: 20),
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

  /// The pause between records in the Discogs backfill.
  ///
  /// The point of that pass is not to finish fast, it is to finish without ever being in the user's
  /// way. Twenty seconds hands most of the sixty-a-minute budget back between records, so opening an
  /// album never queues behind it. Forty leftovers therefore take an evening, in the background,
  /// once — and then never again, because what is written stays written.
  ///
  /// Injected so a test can drive the pass without waiting out the real thing.
  final Duration discogsBreather;

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
    // Artwork FIRST, and on its own. Not side by side — that was the mistake.
    //
    // Read off warm.log on the real library: both loops started, and a hundred and twenty seconds
    // later the artwork round had not finished its FIRST album. The bottleneck here is not
    // concurrency, it is sixty Discogs requests a minute; run two loops and they simply halve each
    // other, and the app triples its own spacing once the budget drops below twelve. So one at a
    // time, and the one the user notices goes first: 79 of 130 records already have their tracklist
    // and are missing only their scans.
    await _artSweep();
    await _wantFacts();
    // Once more, for the records the facts sweep just resolved.
    await _artSweep();
    // And finally the ones the free sources could not finish, through Discogs. Last, slowly, and
    // only what is left — see [_discogsBackfill].
    await _discogsBackfill();
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
      // One pass, then return. It used to keep looping every ten seconds for as long as the facts
      // sweep was running, and measured on the real library that was two things at once: a log line
      // every ten seconds saying "115 skipped, 0 fetched", and — far worse — the Discogs backfill
      // never starting at all, because it waits for this to return and this waited for the facts
      // sweep. Records that get their tracklist later are covered by the second call in [start],
      // which is what that call is for.
      await _warmMissingArt();
      _log.line('scans: veeg klaar, $_artDone opgehaald deze sessie');
    } finally {
      _artRunning = false;
      notifyListeners();
    }
  }

  bool _artRunning = false;

  /// One pass over the library. Returns how many records had their scans fetched.
  Future<int> _warmMissingArt() async {
    var did = 0, geenFeiten = 0, alWarm = 0, overgeslagen = 0, teTraag = 0;
    for (final album in _artOrder()) {
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
        case _Art.already:
          alWarm++; // one file check, no network — not progress, and not a reason to stop
        case _Art.tooSlow:
          // Not progress and not a failure: the queue simply stopped waiting for this one.
          if (++teTraag >= _tooSlowLimit) {
            _log.line('scans: $teTraag keer te traag — ronde gestopt, later opnieuw');
            return did;
          }
        case _Art.failed:
          _log.line('scans: "${album.title}" MISLUKT — ronde gestopt '
              '(opgehaald=$did alwarm=$alWarm geenfeiten=$geenFeiten)');
          return did; // usually the network; the next fifty fail the same way
      }
    }
    _log.line('scans: ronde klaar — opgehaald=$did alwarm=$alWarm geenfeiten=$geenFeiten '
        'overgeslagen=$overgeslagen tetraag=$teTraag feitenLoopt=$_factsPending');
    return did;
  }

  /// The leftovers, through Discogs. Last in the queue, one at a time, and deliberately unhurried.
  ///
  /// The free sources cover what they cover. Measured on this library: of fifty-five records warmed,
  /// two got a back cover from TheAudioDB and forty-two got no answer at all — and asking by hand for
  /// I AM...SASHA FIERCE, BREAK MY SOUL REMIXES and MAKSIM returns fourteen bytes of nothing, so those
  /// records genuinely are not in it. Discogs does have them. It is simply expensive: about thirty-six
  /// requests per record out of sixty a minute.
  ///
  /// So it runs here, after everything cheap is done, with a pause between records that leaves the
  /// budget mostly free for whatever the user opens. That matters more than finishing quickly — this
  /// is a one-off backfill, and once a record is written it never comes back.
  ///
  /// Nothing is retried: [_discogsTried] holds one attempt per record per session, exactly like the
  /// free pass, so a record that fails costs one attempt and not a loop.
  Future<void> _discogsBackfill() async {
    if (_stopped || !settings.warmFacts || library.isRemote) return;
    _log.line('discogs-naveeg: start');
    var did = 0, over = 0;
    for (final album in _artOrder()) {
      if (_stopped || !settings.warmFacts || library.scanning) break;
      final uid = library.uidOf(album);
      if (uid.isEmpty || _discogsTried.contains(uid)) continue;
      final facts = library.facts.get(uid);
      if (facts == null || facts.tracklist.isEmpty) continue;

      final expected = facts.tracklist.length;
      final mbid = library.pinnedMbid(album) ?? facts.mbid;
      final pinned = library.pinnedRelease(album);
      final roles = library.albumArtRoles(album.artist, album.title);
      if (await DiscogsService(settings).hasReleaseArt(album.artist, album.title,
          expectedTracks: expected, pinned: pinned, pinnedMbid: mbid, roles: roles)) {
        over++;
        continue; // the free pass already finished this one
      }

      _discogsTried.add(uid);
      _log.line('discogs-naveeg: "${album.title}" ophalen…');
      final t0 = DateTime.now();
      try {
        await warmArt(album.artist, album.title,
                expectedTracks: expected,
                pinned: pinned,
                pinnedMbid: mbid,
                roles: roles,
                settings: settings,
                freeOnly: false)
            .timeout(_discogsDeadline);
        did++;
        _artDone++;
        notifyListeners();
        _log.line('discogs-naveeg: "${album.title}" klaar in '
            '${DateTime.now().difference(t0).inSeconds}s');
      } on TimeoutException {
        _log.line('discogs-naveeg: "${album.title}" over ${_discogsDeadline.inSeconds}s — verder');
      } catch (e) {
        _log.line('discogs-naveeg: "${album.title}" gooide $e — gestopt');
        break;
      }
      // Breathing room, so opening an album never queues behind this.
      await Future<void>.delayed(discogsBreather);
    }
    _log.line('discogs-naveeg: klaar — opgehaald=$did alwarm=$over');
  }

  /// One Discogs attempt per record per session.
  final Set<String> _discogsTried = {};

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
      return _Art.already;
    }
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
      notifyListeners();
      _log.line('scans: "${album.title}" klaar in ${DateTime.now().difference(t0).inSeconds}s');
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
      //
      // BOTH loops. This used to wake only the facts sweep, and by the time it fired the artwork loop
      // had long since seen nothing to do and broken — so every record the retry resolved got its
      // tracklist and never its scans, for the rest of the session, with nothing saying so.
      unawaited(_artSweep());
      unawaited(_wantFacts());
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
