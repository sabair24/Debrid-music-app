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

        // And the scans, straight after, with EXACTLY the arguments the album page will use.
        //
        // This is what makes opening a record instant instead of a wait. The tracklist was already
        // warmed here; the sleeve, the back and the disc were not, and they are the slow part —
        // Discogs has to resolve the pressing and then download the images. Measured on ANTI: after
        // thirty seconds on the page the back and the disc were still missing, and they only showed
        // up on a second visit, off the disk cache the first visit had filled after the user had
        // already left.
        //
        // The arguments have to match the page's to the letter, because expectedTracks and both pins
        // are part of the cache key — warm it under a different key and the page still fetches. So
        // the track count comes from the pressing just resolved (which is what the page uses once
        // the facts are in) and falls back to the file count exactly as the page does.
        try {
          await warmArt(
            album.artist,
            album.title,
            expectedTracks: fresh.tracklist.isNotEmpty ? fresh.tracklist.length : album.tracks.length,
            pinned: library.pinnedRelease(album),
            pinnedMbid: library.pinnedMbid(album) ?? fresh.mbid,
            roles: library.albumArtRoles(album.artist, album.title),
            settings: settings,
          );
        } catch (e) {
          // Artwork is not why this loop exists. A record with a tracklist and no scans is still a
          // better record than one with neither.
          debugPrint('Warming art for ${album.title} failed: $e');
        }

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
    }
  }

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
