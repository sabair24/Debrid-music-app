import 'editions.dart';
import 'models.dart';
import 'organize.dart';

/// One line of a record as the album page shows it: what the release says belongs there, and the
/// file — if the file is here at all.
class AlbumSlot {
  /// Position in the official tracklist, or -1 for a file the release doesn't name.
  final int index;

  /// The official entry. Null only for a file the release doesn't name.
  final ChoiceTrack? official;

  /// The copy on disk. Null when this track is missing.
  final Track? track;

  /// Does the release this slot belongs to span more than one disc? A double album numbers from 1
  /// on each disc, so a bare position is ambiguous — and printing it raw put a second "1" after
  /// track 13.
  final bool multiDisc;

  const AlbumSlot({required this.index, this.official, this.track, this.multiDisc = false});

  bool get missing => track == null;

  int get disc => official?.disc ?? 1;

  /// The number to WRITE into the file's tag. Always an integer, and unique within the record:
  /// across discs it counts straight through, because a tag cannot hold "2-1" and two tracks
  /// sharing a number is what tears an album into editions.
  int get number {
    if (multiDisc && index >= 0) return index + 1;
    final p = int.tryParse((official?.position ?? '').trim());
    if (p != null && p > 0) return p;
    if (track != null && track!.trackNo > 0) return track!.trackNo;
    return index + 1;
  }

  /// The number to SHOW. "4" on a single disc, "2-1" on a double — what the sleeve says.
  String get label {
    if (!multiDisc) return '$number';
    final pos = (official?.position ?? '').trim();
    return '$disc-${pos.isEmpty ? '${index + 1}' : pos}';
  }

  String get title => official?.title ?? track?.title ?? '';

  int? get seconds => official?.seconds ?? track?.duration?.inSeconds;
}

/// A record laid next to what's on disk: every official track, present or not.
class AlbumCompleteness {
  final List<AlbumSlot> slots;

  /// Where the tracklist came from, for the line under the album ('MusicBrainz' / 'Discogs').
  final String source;

  const AlbumCompleteness(this.slots, {this.source = ''});

  /// Counted over the ROWS the page shows, not over the pressing — so a bonus file the release
  /// doesn't list counts towards both, and "3 van 17" always adds up to the list you're reading.
  int get have => slots.where((s) => s.track != null).length;
  int get total => slots.length;
  List<AlbumSlot> get missing => [for (final s in slots) if (s.missing) s];
  bool get complete => missing.isEmpty;

  /// How many of your tracks this pressing NAMES.
  ///
  /// Deliberately not [have]: that counts the rows on the page, and every file you own is always a
  /// row — matched, or appended at the end as one the pressing doesn't name. Comparing pressings on
  /// [have] therefore scores them all identically.
  int get matched => slots.where((s) => s.index >= 0 && s.track != null).length;

  /// Does this pressing name everything on disk? The question the pressing is chosen on.
  bool get namesEverything => slots.every((s) => s.index >= 0 || s.track == null);
}

/// Is this track a marked variant — a radio edit, a live take, a remix?
///
/// Read from the title and the FILENAME only, never the folders: an album that happens to live
/// under "… (Deluxe Edition)" would otherwise mark every one of its tracks as a variant.
bool isVariant(Track t) =>
    versionMarkers(t.title).isNotEmpty ||
    versionMarkers(t.path.split(RegExp(r'[\\/]')).last).isNotEmpty;

/// How many tracks of the RECORD are here — the number a pressing is measured against.
///
/// Not the number of files. A radio edit sitting beside the album cut is a bonus, not a twelfth
/// track, and counting it ruled out every eleven-track pressing of an eleven-track album.
int albumTrackCount(List<Track> tracks) => tracks.where((t) => !isVariant(t)).length;

/// Line a record's official tracklist up with the files actually on disk.
///
/// Owning a track is not the same as holding a file with that name. A peer spells titles its own
/// way, the release may write "Pt. 1" where the ripper wrote "Part 1", and the library can hold a
/// live take under the same title as the studio cut. So: normalised titles first, and where both
/// running times are known they have to agree within [_slack] seconds — the same tolerance every
/// other matcher in this app uses. Anything still unclaimed gets one more pass through
/// [fileOffersTitle], which reads the whole path and can explain away the artist and folder words.
///
/// Files the release doesn't name are never dropped — they come back at the end as slots with
/// index -1. A wrong tracklist must not be able to make music you own disappear from its own page.
AlbumCompleteness matchAlbumTracks(
  List<ChoiceTrack> official,
  List<Track> tracks,
  String artist, {
  String source = '',
}) {
  final owned = <int, Track>{};
  final claimed = <String>{};
  final multiDisc = official.map((o) => o.disc).toSet().length > 1;

  bool durationsAgree(int? a, int? b) => a == null || b == null || a <= 0 || b <= 0 || (a - b).abs() <= _slack;

  // Exact title first, across the whole list, so a looser match can never steal a file from the
  // entry that names it outright.
  for (var i = 0; i < official.length; i++) {
    final want = normKey(official[i].title);
    if (want.isEmpty) continue;
    for (final t in tracks) {
      if (claimed.contains(t.path)) continue;
      if (normKey(t.title) != want) continue;
      if (!durationsAgree(official[i].seconds, t.duration?.inSeconds)) continue;
      owned[i] = t;
      claimed.add(t.path);
      break;
    }
  }

  // Then the filename, for the ones whose tags were never written or were written wrong — the WAV
  // that scanned as "Onbekende artiest" still has the title in its name.
  for (var i = 0; i < official.length; i++) {
    if (owned.containsKey(i)) continue;
    final o = official[i];
    if (o.title.trim().isEmpty) continue;
    for (final t in tracks) {
      if (claimed.contains(t.path)) continue;
      if (!fileOffersTitle(o.title, o.seconds, artist, t.path, t.duration?.inSeconds)) continue;
      owned[i] = t;
      claimed.add(t.path);
      break;
    }
  }

  // Last, the catalogues' own disagreements. MusicBrainz writes "If You Want It to Be Good Girl"
  // where the ripper wrote "If You Want to Be a Good Girl" — one song, two spellings — and that
  // single title was enough to disqualify the pressing that IS the record.
  //
  // Deliberately last and deliberately narrow: four fifths of the words shared, running times that
  // agree, and the SAME version markers on both sides. That last rule is what stops a pressing's
  // "(radio edit)" from being folded into the album cut, which is a different recording.
  for (var i = 0; i < official.length; i++) {
    if (owned.containsKey(i)) continue;
    final o = official[i];
    final ow = _words(o.title);
    if (ow.isEmpty) continue;
    for (final t in tracks) {
      if (claimed.contains(t.path)) continue;
      if (!durationsAgree(o.seconds, t.duration?.inSeconds)) continue;
      if (!_sameMarkers(versionMarkers(o.title), versionMarkers(t.title))) continue;
      final tw = _words(t.title);
      if (tw.isEmpty) continue;
      final shared = ow.intersection(tw).length;
      if (shared / (ow.length > tw.length ? ow.length : tw.length) < .8) continue;
      owned[i] = t;
      claimed.add(t.path);
      break;
    }
  }

  return AlbumCompleteness(
    [
      for (var i = 0; i < official.length; i++)
        AlbumSlot(index: i, official: official[i], track: owned[i], multiDisc: multiDisc),
      // Whatever the release doesn't account for, last and still playable.
      for (final t in tracks)
        if (!claimed.contains(t.path)) AlbumSlot(index: -1, track: t),
    ],
    source: source,
  );
}

/// Seconds two timings may differ and still be the same recording. Matches [fileOffersTitle].
const _slack = 12;

Set<String> _words(String s) => normKey(s).split(' ').where((w) => w.isNotEmpty).toSet();

/// Do both titles carry the same version markers? "(radio edit)" on one side and nothing on the
/// other means two different recordings, however alike the words are.
bool _sameMarkers(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

/// Which pressings are worth fetching a tracklist for, cheaply, from their track counts alone.
///
/// Costs nothing — the release-group browse already states every pressing's count — and it is the
/// step that keeps the expensive one bounded: MusicBrainz allows one request per second, and a
/// record can have seventy-five pressings.
///
/// Smallest-that-fits first. A pressing that holds exactly what you own describes the record; a
/// bigger one describes a different edition of it. A pressing SMALLER than what you own cannot be
/// your record at all, so it is only reached when nothing else qualifies — better to describe the
/// album with a near miss than not at all.
///
/// Returns indices into [trackCounts], preserving its order among equal counts, so the caller's
/// existing preference ranking (CD before vinyl, documented, original pressing) breaks ties.
List<int> shortlistPressings(List<int> trackCounts, int owned, {int take = 3}) {
  final fits = <int>[];
  final rest = <int>[];
  for (var i = 0; i < trackCounts.length; i++) {
    if (trackCounts[i] <= 0) continue; // count unstated — nothing to rank on
    (trackCounts[i] >= owned ? fits : rest).add(i);
  }
  int bySize(int a, int b) {
    final c = trackCounts[a].compareTo(trackCounts[b]);
    return c != 0 ? c : a.compareTo(b);
  }

  fits.sort(bySize);
  // The fallbacks are the BIGGEST of the too-small ones — the closest thing to holding it all.
  rest.sort((a, b) => bySize(b, a));
  return [...fits, ...rest].take(take).toList();
}

/// Which of the fetched pressings actually describes this record.
///
/// The rule that matters is containment, not size: a pressing that does not name every track on
/// disk is not the record you own, however well it scores otherwise. Among the ones that do name
/// everything, the smallest wins — for Backstreet's Back that is the eleven-track pressing over the
/// sixteen-track double CD, which is the difference between "complete" and five invented gaps.
///
/// When nothing names everything, the best-covering pressing wins rather than none: a record
/// described by a near miss is more use than a record not described at all. The caller can tell
/// the two apart with [AlbumCompleteness.namesEverything] and say so.
///
/// [candidates] arrives in preference order, so index order is the tiebreak.
int pickPressing(List<AlbumCompleteness> candidates) {
  if (candidates.isEmpty) return -1;
  var best = 0;
  for (var i = 1; i < candidates.length; i++) {
    if (_beats(candidates[i], candidates[best])) best = i;
  }
  return best;
}

bool _beats(AlbumCompleteness a, AlbumCompleteness b) {
  final aAll = a.namesEverything, bAll = b.namesEverything;
  if (aAll != bAll) return aAll;
  if (aAll) return a.missing.length < b.missing.length; // smallest pressing that still holds it
  final byMatched = a.matched.compareTo(b.matched);
  if (byMatched != 0) return byMatched > 0; // covers more of what you own
  return a.missing.length < b.missing.length;
}

/// A track that isn't on your pressing, but is on another one of the same record.
class BonusTrack {
  final ChoiceTrack track;

  /// Which pressing it comes from, as its edition line reads ("CD · US · 1997").
  final String edition;

  const BonusTrack(this.track, this.edition);
}

/// What the other pressings of this record have that yours doesn't.
///
/// Backstreet's Back is eleven tracks in Britain and thirteen in America, plus a Malaysian second
/// disc with a Christmas song on it. None of that is missing from your record — it was never on
/// it — but it is the rest of the record, and worth being able to see and fetch.
///
/// Compared on normalised titles, so a pressing that spells "10,000 Promises" with a full stop
/// doesn't read as a different song. First pressing to name a title gets the credit.
List<BonusTrack> bonusTracks(List<ChoiceTrack> mine, List<(String, List<ChoiceTrack>)> others) {
  final have = {for (final t in mine) normKey(t.title)}..remove('');
  final out = <BonusTrack>[];
  for (final (edition, tracks) in others) {
    for (final t in tracks) {
      final k = normKey(t.title);
      if (k.isEmpty || !have.add(k)) continue;
      out.add(BonusTrack(t, edition));
    }
  }
  return out;
}
