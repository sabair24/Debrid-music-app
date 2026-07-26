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

import 'album_facts.dart';
import 'completeness.dart';
import 'discogs.dart';
import 'editions.dart';
import 'models.dart';
import 'musicbrainz.dart';
import 'settings.dart';

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

  try {
    MbRelease? rel;
    if (pinnedMbid != null && pinnedMbid.isNotEmpty) rel = await mb.release(pinnedMbid);
    if (rel == null) {
      final groups =
          await mb.searchReleaseGroups(DiscogsService.plainTitle(album.title), artist: album.artist);
      // Not merely "not a compilation": a SINGLE of the same name is a different record, and
      // picking it described a sixteen-track album with a two-track sleeve.
      final g = MusicBrainzService.pickReleaseGroup(groups, single: album.isSingle);
      if (g != null) {
        // One request for every pressing of the record, already in preference order.
        // With the tracklists in the browse itself this is the LAST MusicBrainz request for most
        // records: the loop below then finds every pressing already carrying its tracks.
        final all = await mb.editionsOf(g.mbid, tracklists: true);
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
        for (final i in shortlist) {
          final list = await mb.tracklistOf(all[i]);
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
  } catch (_) {/* Discogs gets its turn below */}

  if (out.isEmpty) {
    try {
      // Here expectedTracks IS safe to pass: Discogs only uses it to drop masters too SMALL to hold
      // the library, never ones bigger.
      final e = await (discogs ?? DiscogsService(settings)).edition(album.artist, album.title,
          expectedTracks: albumTrackCount(album.tracks), pinned: pinned);
      if (e != null && e.tracklist.isNotEmpty) {
        out = [for (final t in e.tracklist) ChoiceTrack(t.position, t.title, t.seconds)];
        year = e.albumYear ?? e.year;
        from = 'Discogs';
        release = e.releaseId;
      }
    } catch (_) {}
  }

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
    failedMs: out.isEmpty ? now : null,
  );
}
