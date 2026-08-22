/// Working out which pressing of a record you actually own.
///
/// Lifted out of `_AlbumDetailPageState._loadOfficial` unchanged. The selection logic here was hard
/// won — containment rather than size, the release group rather than a free-text search, the
/// fullest pressing always scored — and none of it is being reconsidered. What changed is where the
/// answer goes: to [AlbumFactsStore] instead of into a `setState` that the next `Navigator.pop`
/// throws away.
///
/// That is the whole fix for "it fetches the tracklist again every single time". This runs once per
/// record, not once per visit.
library;

import 'acoustid.dart';
import 'album_facts.dart';
import 'completeness.dart';
import 'discogs.dart';
import 'editions.dart';
import 'fingerprint.dart';
import 'models.dart';
import 'musicbrainz.dart';
import 'settings.dart';

/// Somewhere to write which STEP of a resolve is running. Set once by the warmer.
///
/// A library-level hook rather than a parameter on purpose: [resolveAlbumFacts] is injected into
/// FactsWarmer as a function value, so adding an argument would rewrite that typedef and every stub
/// in the tests to observe something no caller cares about.
///
/// It exists because one record — "Vlaamse Diva's" — sat here for three-quarters of an hour on two
/// separate runs with no socket open, no cache file written, no queue line and no CPU. The lane got
/// a trace and stayed silent, which ruled the lane out and left the rest of this function as one
/// unlit room. This lights it.
void Function(String)? resolveTrace;

/// The official tracklist: which pressing of this record you actually own.
///
/// Chosen by CONTAINMENT, not by size. Asking for the first pressing big enough to hold the
/// library picked a Malaysian double CD for an eleven-track album and then reported five gaps, one
/// of them a Christmas song. The pressing that names every track on disk and adds fewest of its own
/// is the record; see pickPressing().
///
/// Candidates come from the RELEASE GROUP, not a free-text release search, so every one of them is
/// a pressing of this same record and a same-named single can never win.
///
/// A pinned pressing wins outright — if you picked an edition in the gallery, that edition is the
/// answer, not a candidate.
///
/// Never throws. A record nothing answers for comes back with an empty tracklist and a
/// [AlbumFacts.failedMs], which is what stops the six-request chain from being paid again at every
/// open for the rest of time.
Future<AlbumFacts> resolveAlbumFacts(
  Album album, {
  required String uid,
  required String trackSetHash,
  required MusicBrainzService mb,
  required AppSettings settings,
  String? pinnedMbid,
  int? pinned,
  DiscogsService? discogs,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;

  var out = const <ChoiceTrack>[];
  var from = '';
  var bonus = const <BonusTrack>[];
  var bestFit = true;
  String? mbid;
  int? year;
  int? release;

  /// Did a lookup actually BREAK, as opposed to answering "never heard of it"?
  ///
  /// Both used to arrive here as an empty tracklist, and the warmer reads three empties in a row as
  /// "the network is gone" — so eleven genuinely obscure records in a row shut the sweep down and
  /// froze it at fifteen of twenty-six, every single run. Telling the two apart is the whole point.
  ///
  /// An exception is NOT enough to detect it, and relying on one was worse than the bug it replaced.
  /// Neither service throws on a network fault: `MusicBrainzService._get` and `DiscogsService._get`
  /// both catch everything and return null, so a timeout, a 503 and a clean 404 are indistinguishable
  /// at this level. With only the catch blocks below, this flag could never be true, the guard was
  /// dead, and one offline launch would have written `failedMs` across the entire library — blinding
  /// every album page for a day and stopping the artwork loop too, since it skips records with no
  /// tracklist. Hence the counters: they are the only place that knows.
  var threw = false;
  final errorsBefore = MusicBrainzService.transportErrors + DiscogsService.transportErrors;

  final t0 = DateTime.now();
  void stap(String s) =>
      resolveTrace?.call('    [oplos +${DateTime.now().difference(t0).inMilliseconds}ms] $s');
  stap('begin — ${album.tracks.length} bestanden, pin=${pinned ?? "-"} mbid=${pinnedMbid ?? "-"}');

  try {
    MbRelease? rel;
    if (pinnedMbid != null && pinnedMbid.isNotEmpty) {
      rel = await mb.release(pinnedMbid);
      stap('gepinde persing: ${rel == null ? "niets" : "gevonden"}');
    }
    if (rel == null) {
      stap('zoeken op release-groep…');
      final groups =
          await mb.searchReleaseGroups(DiscogsService.plainTitle(album.title), artist: album.artist);
      stap('release-groepen: ${groups.length}');
      // Not merely "not a compilation": a SINGLE of the same name is a different record, and
      // picking it described a sixteen-track album with a two-track sleeve.
      final g = MusicBrainzService.pickReleaseGroup(groups, single: album.isSingle);
      if (g != null) {
        // One request for every pressing of the record, already in preference order.
        // With the tracklists in the browse itself this is the LAST MusicBrainz request for most
        // records: the loop below then finds every pressing already carrying its tracks.
        stap('persingen ophalen voor groep ${g.mbid}…');
        final all = await mb.editionsOf(g.mbid, tracklists: true);
        stap('persingen: ${all.length}');
        final owned = albumTrackCount(album.tracks);
        final counts = [for (final r in all) r.trackCount];
        // The three smallest that fit, PLUS the fullest pressing of the record.
        //
        // Smallest-that-fits alone is not enough. Owning three tracks of Gotta Get Thru This
        // shortlists three twelve-track pressings, and the acoustic version you hold is only on the
        // sixteen — so the pressing that actually describes what you have never gets looked at. The
        // fullest one is fetched anyway for the bonus list, so scoring it costs nothing.
        final fullest =
            counts.isEmpty ? -1 : counts.indexed.reduce((x, y) => y.$2 > x.$2 ? y : x).$1;
        final shortlist = <int>{
          ...shortlistPressings(counts, owned),
          if (fullest >= 0) fullest,
        }.toList();

        final tried = <MbRelease>[];
        final lists = <List<ChoiceTrack>>[];
        final scored = <AlbumCompleteness>[];
        stap('shortlist: ${shortlist.length} persingen wegen');
        for (final i in shortlist) {
          final list = await mb.tracklistOf(all[i]);
          stap('  persing $i: ${list.length} nummers');
          if (list.isEmpty) continue;
          tried.add(all[i]);
          lists.add(list);
          scored.add(matchAlbumTracks(list, album.tracks, album.artist));
        }
        final pick = pickPressing(scored);
        if (pick >= 0) {
          rel = tried[pick];
          out = lists[pick];
          bestFit = scored[pick].namesEverything;
          // Everything fetched that is not the chosen pressing is where the extras come from.
          bonus = bonusTracks(out, album.tracks, album.artist, [
            for (var i = 0; i < tried.length; i++)
              if (i != pick) (tried[i].line, lists[i])
          ]);
        }
      }
    }
    if (rel != null) {
      if (out.isEmpty) out = await mb.tracklistOf(rel);
      year = rel.albumYear ?? rel.year;
      if (out.isNotEmpty) {
        from = 'MusicBrainz';
        mbid = rel.mbid; // so the sleeve comes from this pressing, not from a second guess
      }
    }
  } catch (_) {
    threw = true; // Discogs gets its turn below; remember that this side broke
  }

  stap('MusicBrainz klaar — ${out.length} nummers');

  /// Heeft de gebruiker een DISCOGS-persing vastgezet, en is dat de vraag die telt?
  ///
  /// **Dit stond op `out.isEmpty` alleen, en dat was een lus die zichzelf voedde.** Kende
  /// MusicBrainz de plaat, dan was `out` gevuld en werd Discogs nooit gevraagd — dus de vastgezette
  /// persing werd genegeerd én `release` bleef leeg. En `needsResolve` kijkt juist daarnaar:
  /// `known.discogsRelease != pinned` was dan altijd waar. Gevolg: dat album stond in ELKE ronde van
  /// de warmer opnieuw op de lijst, en die schreef er telkens de zelfgekozen MusicBrainz-persing
  /// overheen. Precies de klacht "ik duid iets aan en het komt terug" — en het kostte bovendien
  /// eeuwig verzoeken op een budget dat op kan.
  ///
  /// Een pin is een opdracht, geen suggestie. Staat er een MBID vastgezet, dan gaat die vóór: dan is
  /// MusicBrainz de gevraagde bron en heeft een oud Discogs-nummer niets te zeggen.
  final discogsGevraagd = pinned != null && pinned > 0 && (pinnedMbid == null || pinnedMbid.isEmpty);
  if (out.isEmpty || discogsGevraagd) {
    try {
      stap(discogsGevraagd ? 'naar Discogs (vastgezette persing $pinned)…' : 'naar Discogs…');
      // Here expectedTracks IS safe to pass: Discogs only uses it to drop masters too SMALL to hold
      // the library, never ones bigger.
      final e = await (discogs ?? DiscogsService(settings)).edition(album.artist, album.title,
          expectedTracks: albumTrackCount(album.tracks), pinned: pinned);
      stap('Discogs: ${e == null ? "niets" : "${e.tracklist.length} nummers"}');
      if (e != null && e.tracklist.isNotEmpty) {
        out = [for (final t in e.tracklist) ChoiceTrack(t.position, t.title, t.seconds)];
        year = e.albumYear ?? e.year;
        from = 'Discogs';
        release = e.releaseId;
      }
    } catch (_) {
      threw = true;
    }
  }

  /// Is de vastgezette persing werkelijk gehaald?
  ///
  /// `edition` mag terugvallen op een andere persing als de vastgezette niet op te halen is, dus
  /// "Discogs antwoordde" is niet hetzelfde als "je keuze is gehonoreerd". Alleen het echte nummer
  /// telt. Zonder dit onderscheid zou een terugval als succes worden opgeslagen en zou de app
  /// beweren dat je keuze staat terwijl er iets anders ligt.
  final pinGehaald = discogsGevraagd && release == pinned;
  if (discogsGevraagd && !pinGehaald) {
    stap('vastgezette persing $pinned NIET gehaald — een dag rust voordat het opnieuw geprobeerd wordt');
  }

  // Last, and only when asking by name has failed both times: ask the AUDIO.
  //
  // This is the compilations. "Various Artists — Serious Beats 51" is not a search anybody can
  // answer, and eight records in this library come back empty from both catalogues for exactly that
  // reason. Fingerprints turn the question round: each file says what recording it is, and the
  // release group they agree on is the record. Deliberately last — it costs a fingerprint per file
  // and a request per file, which is far more than a title lookup, and it is wasted on the ninety
  // per cent of records a title lookup already answers.
  var heard = 0;
  if (out.isEmpty) {
    try {
      heard = canHear(settings) ? kSoundVersion : 0;
      final gevonden = await _fromSound(album, mb, settings, stap);
      if (gevonden != null && gevonden.$2.isNotEmpty) {
        mbid = gevonden.$1.mbid;
        out = gevonden.$2;
        year = gevonden.$1.albumYear ?? gevonden.$1.year;
        from = 'AcoustID';
      }
    } catch (_) {
      threw = true;
    }
  }

  stap('klaar — bron "${from.isEmpty ? "niets" : from}", ${out.length} nummers');

  return AlbumFacts(
    uid: uid,
    trackSetHash: trackSetHash,
    updatedMs: now,
    source: from,
    mbid: mbid,
    discogsRelease: release,
    bestFit: bestFit,
    tracklist: out,
    bonus: bonus,
    year: year,
    // Only an empty answer is a failure. A record that resolved is never retried on a timer.
    // Recorded even when the audio found nothing, because "we asked" is what stops it being asked
    // every single sweep for the rest of the day.
    heardVersion: heard,
    // Een leeg antwoord is een mislukking — en sinds de pin een opdracht is, een pin die niet
    // gehaald werd ook. Zonder dat tweede geval blijft [needsResolve] waar en draait de warmer er
    // eeuwig op door. Mét dat stempel is het één poging per dag, wat de rest van dit bestand ook al
    // aanhoudt.
    failedMs: out.isEmpty || (discogsGevraagd && !pinGehaald) ? now : null,
    networkFailed: out.isEmpty &&
        (threw ||
            MusicBrainzService.transportErrors + DiscogsService.transportErrors > errorsBefore),
  );
}

/// Can this machine ask the audio at all — is there an fpcalc AND a key?
///
/// Read by [needsResolve] as well as here, so that "a failure from before we could listen" and
/// "a failure with the audio included" are decided by the same test in both places.
bool canHear(AppSettings settings) =>
    AcoustIdService(settings).available && Fingerprinter().available;

/// How many files of a record are worth fingerprinting to identify it.
///
/// The vote does not need every track — six agreeing out of eight asked is already conclusive — and
/// each one costs a fingerprint plus a request. Twelve keeps a fifty-track box set from turning into
/// a fifty-request errand while still giving a normal compilation nearly all of itself to vote with.
const _heardAtMost = 12;

/// Name a record by what its files SOUND like, when no catalogue could name it by title.
///
/// Returns the chosen pressing and its tracklist, or null. Everything after the release group is the
/// ordinary machinery — [MusicBrainzService.editionsOf] and [pickPressing] — because once the
/// release group is known this is an ordinary record again. That is the point of stopping here
/// rather than building a second way to choose a pressing.
Future<(MbRelease, List<ChoiceTrack>)?> _fromSound(
  Album album,
  MusicBrainzService mb,
  AppSettings settings,
  void Function(String) stap,
) async {
  final acoust = AcoustIdService(settings);
  if (!acoust.available) {
    stap('geluid: geen AcoustID-sleutel — overgeslagen');
    return null;
  }
  final fp = Fingerprinter();
  if (!fp.available) {
    stap('geluid: fpcalc ontbreekt — overgeslagen');
    return null;
  }

  final perTrack = <List<String>>[];
  var gevraagd = 0;
  for (final t in album.tracks) {
    if (gevraagd >= _heardAtMost) break;
    final a = await fp.of(t.path, compressed: true);
    if (a == null) continue;
    gevraagd++;
    final matches = await acoust.identify(a);
    perTrack.add([for (final m in matches) ...m.releaseGroups]);
  }
  stap('geluid: $gevraagd bestanden gevraagd, '
      '${perTrack.where((l) => l.isNotEmpty).length} herkend');
  if (perTrack.isEmpty) return null;

  final groep = bestReleaseGroup(perTrack);
  if (groep == null) {
    stap('geluid: geen uitgave waar genoeg nummers het over eens zijn');
    return null;
  }
  stap('geluid: release-groep $groep');

  final all = await mb.editionsOf(groep, tracklists: true);
  if (all.isEmpty) return null;
  final tried = <MbRelease>[];
  final lists = <List<ChoiceTrack>>[];
  final scored = <AlbumCompleteness>[];
  for (final r in all.take(4)) {
    final list = await mb.tracklistOf(r);
    if (list.isEmpty) continue;
    tried.add(r);
    lists.add(list);
    scored.add(matchAlbumTracks(list, album.tracks, album.artist));
  }
  final pick = pickPressing(scored);
  if (pick < 0) return null;
  stap('geluid: persing ${tried[pick].mbid}, ${lists[pick].length} nummers');
  return (tried[pick], lists[pick]);
}
