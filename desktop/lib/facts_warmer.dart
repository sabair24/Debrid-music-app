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
    await _sweep();
  }

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
    _rearm = Timer(rearmDelay, () => unawaited(_sweep()));
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
    // No facts to fetch is NOT a reason to stop: the artwork pass below is for albums whose facts
    // are already settled, which after the first sweep is nearly all of them. Returning here is
    // exactly why the first version added one entry to the artwork cache and then went quiet.
    if (todo.isEmpty) {
      _running = true;
      notifyListeners();
      try {
        await _warmMissingArt();
      } finally {
        _running = false;
        notifyListeners();
      }
      return;
    }

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
          debugPrint('Warming $uid failed: $e');
          break;
        }

        if (fresh.isEmpty) {
          // Offline, MusicBrainz down, or genuinely an unknown record — indistinguishable from
          // here, so do not decide yet.
          held.add(fresh);
          if (++blanks >= _outageAfter) {
            // Treat it as an outage: throw the held failures away so NOTHING carries failedMs, and
            // come back later. Storing them would blind those albums for a day over a dropped
            // wifi connection, and a warmer can do that to a whole library in seconds — the miss
            // cache answers instantly once it is warm.
            debugPrint('Warming stopped: $_outageAfter records in a row found nothing');
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
        // This record's scans NOW, before moving on to the next album's facts.
        //
        // Measured with the progress line in the corner: the facts loop had 26 albums to work
        // through at roughly half a minute each. An artwork pass that waits for that loop to finish
        // does not land for ten minutes — and the album whose scans you actually want is the one
        // that just downloaded, which is first in this loop. So it gets them here, and the backlog
        // is caught up afterwards.
        await _warmArtFor(album, fresh);
        _done++;
        notifyListeners();
      }
      // Anything still held at a clean finish was a genuine miss among successes.
      for (final h in held) {
        library.facts.put(h);
      }
      await _warmMissingArt();
    } finally {
      _running = false;
      await library.facts.flush();
      notifyListeners();
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
  Future<void> _warmMissingArt() async {
    for (final album in _byNewest()) {
      if (_stopped || !settings.warmFacts || library.scanning) break;
      final uid = library.uidOf(album);
      if (uid.isEmpty || _artTried.contains(uid)) continue;
      final facts = library.facts.get(uid);
      if (facts == null) continue;
      if (!await _warmArtFor(album, facts)) break;
    }
  }

  /// One album's scans, with the arguments the album page will use.
  ///
  /// Returns false only when the fetch itself failed — the caller reads that as "the network is
  /// gone" and stops, because the next fifty will fail the same way.
  ///
  /// The arguments have to match the page's to the letter: expectedTracks and both pins are part of
  /// the cache key, so warming under a different track count means the page still fetches and the
  /// warming was wasted. The count comes from the pressing just resolved — what the page uses once
  /// the facts are in — and falls back to the file count exactly as the page does.
  Future<bool> _warmArtFor(Album album, AlbumFacts facts) async {
    final uid = library.uidOf(album);
    if (uid.isEmpty || _artTried.contains(uid)) return true;
    // No tracklist means no pressing, and without one the artwork is a search by name — the guess
    // that produces the wrong sleeve. Leave those to the page, where the user can see and correct it.
    if (facts.tracklist.isEmpty) return true;

    final expected = facts.tracklist.length;
    final mbid = library.pinnedMbid(album) ?? facts.mbid;
    final pinned = library.pinnedRelease(album);
    final roles = library.albumArtRoles(album.artist, album.title);

    // One attempt per album per session, whatever the outcome — recorded before the check so a
    // throw cannot cause a re-pick, and so the catch-up pass never repeats what this already did.
    _artTried.add(uid);
    if (await DiscogsService(settings).hasReleaseArt(album.artist, album.title,
        expectedTracks: expected, pinned: pinned, pinnedMbid: mbid, roles: roles)) {
      return true; // already on disk — one file check, no network
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
      return true;
    } catch (e) {
      debugPrint('Warming art for ${album.title} failed: $e');
      return false;
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
