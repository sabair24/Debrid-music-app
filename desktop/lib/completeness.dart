import 'editions.dart';
import 'fingerprint.dart';
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
  ///
  /// Blank for a file the pressing doesn't name. It has no place in this run, and borrowing the
  /// number from its own tag put a second "3" underneath track 13 — which reads as the app being
  /// confused rather than as the file simply not being on this record.
  String get label {
    if (index < 0) return '';
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

  /// Wide enough for a wrong printed time, far too narrow for a different performance.
  ///
  /// Only the last pass uses this, and only on an exact title with a single candidate. Two numbers,
  /// both earned: Petra's "Laat Je Gaan" is 24 seconds off a catalogue that says 3:10 — a rounded or
  /// mistyped time — and RENAISSANCE's "Cozy" has a live take six minutes longer than the studio
  /// cut, which must stay a MISSING track or the download that would fetch it never appears.
  ///
  /// A quarter as well as a minute, because a minute means nothing to a thirty-second interlude.
  bool looseEnough(int? off, int? file) {
    if (off == null || file == null || off <= 0 || file <= 0) return false;
    final gap = (off - file).abs();
    return gap <= 60 && gap <= off * 0.25;
  }

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
    for (final t in tracks) {
      if (claimed.contains(t.path)) continue;
      if (!sameTitle(o.title, t.title,
          secondsA: o.seconds, secondsB: t.duration?.inSeconds)) {
        continue;
      }
      owned[i] = t;
      claimed.add(t.path);
      break;
    }
  }

  // Very last: an EXACT title match that only the running time rejected.
  //
  // Measured on Het Beste Van Petra. The file is `02 - Laat Je Gaan.flac`, in that album's own
  // folder, titled exactly what the pressing calls track 2 — and the catalogue says 3:10 where the
  // file plays 3:34. Twenty-four seconds is well past the slack, so every pass above refused it and
  // the record showed "2 · Laat Je Gaan — niet in bibliotheek" with the file listed underneath as
  // not being on this release. Which is nonsense on its face.
  //
  // Catalogue times for a 1996 CNR compilation are rounded, mistyped, or copied from a different
  // pressing. An exact title on the record's own tracklist is much stronger evidence than a printed
  // duration — but only when nothing else wants either side, which is why this runs after
  // everything else and takes only rows and files that are still free. A radio edit does not reach
  // here at all: its title carries a version marker, so it never matched exactly to begin with.
  for (var i = 0; i < official.length; i++) {
    if (owned.containsKey(i)) continue;
    final want = normKey(official[i].title);
    if (want.isEmpty) continue;
    final passend = [
      for (final t in tracks)
        if (!claimed.contains(t.path) &&
            normKey(t.title) == want &&
            looseEnough(official[i].seconds, t.duration?.inSeconds))
          t,
    ];
    // Exactly one candidate, or it is a guess again.
    if (passend.length != 1) continue;
    owned[i] = passend.single;
    claimed.add(passend.single.path);
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

/// De woorden van de SONGTITEL, zonder de merken.
///
/// Merken worden apart vergeleken door [_sameMarkers]. Ze daarnaast ook nog in de woordoverlap laten
/// meetellen straft hetzelfde verschil twee keer af, en dat is precies genoeg om een treffer te
/// missen: "What's My Name? (Album Version)" tegen een kale rij haalde zo 60% -- onder de grens van
/// vier vijfde -- terwijl het over dezelfde drie woorden gaat. Gemeten over de hele bibliotheek kostte
/// dit Rihanna's Loud drie nummers.
///
/// Alleen erkende merken gaan eruit. Een haakje dat GEEN versie aanduidt -- "(feat. JAY-Z)", "(With
/// Chris Stapleton)" -- blijft meetellen, want daar kan het verschil tussen twee opnames in zitten:
/// Adele's 30 heeft "Easy On Me" en het duet met Chris Stapleton allebei, en die mogen niet op één
/// rij vallen.
Set<String> _words(String s) =>
    normKey(withoutVersionText(s)).split(' ').where((w) => w.isNotEmpty).toSet();

/// True when [a] becomes [b] by changing, adding or removing a single character.
bool _oneEditApart(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  if (a.length == b.length) {
    var afwijkend = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i] && ++afwijkend > 1) return false;
    }
    return afwijkend == 1;
  }
  final lang = a.length > b.length ? a : b, kort = a.length > b.length ? b : a;
  var i = 0, j = 0, overgeslagen = 0;
  while (i < lang.length && j < kort.length) {
    if (lang[i] == kort[j]) {
      i++;
      j++;
      continue;
    }
    if (++overgeslagen > 1) return false;
    i++;
  }
  return true;
}

/// Are these two version markers the same marker, allowing for one slip of the finger?
///
/// Gemeten op Technotronic's "Trip on This (The Remixes)": de persing schrijft "(Morales Spinster
/// mix)" en de rip "(Morales Spineter Mix)" -- één letter -- en daarmee meldde de plaat nummer 2 als
/// ontbrekend terwijl het bestand er vlak onder stond als "niet op deze uitgave". Twee keer hetzelfde
/// nummer op één scherm, één keer als gat en één keer als weeskind.
///
/// Alleen binnen woorden die lang genoeg zijn om een typfout te herkennen: "mix" tegen "remix" en
/// "edit" tegen "mix" blijven verschillende markeringen, en dat is precies waar het vergelijken van
/// markeringen voor bestaat. Een radio-edit wordt hier nooit de albumversie.
bool _sameMarker(String a, String b) {
  if (a == b) return true;
  final aw = a.split(' '), bw = b.split(' ');
  if (aw.length != bw.length) return false;
  for (var i = 0; i < aw.length; i++) {
    if (aw[i] == bw[i]) continue;
    if (aw[i].length < 6 || bw[i].length < 6) return false;
    if (!_oneEditApart(aw[i], bw[i])) return false;
  }
  return true;
}

/// Do both titles carry the same version markers? "(radio edit)" on one side and nothing on the
/// other means two different recordings, however alike the words are.
bool _sameMarkers(Set<String> a, Set<String> b) {
  if (a.length != b.length) return false;
  // Elk merk aan de ene kant moet zijn EIGEN tegenhanger aan de andere kant vinden, anders zouden
  // twee bijna-gelijke merken allebei op dezelfde partner kunnen matchen.
  final over = b.toList();
  for (final x in a) {
    final i = over.indexWhere((y) => _sameMarker(x, y));
    if (i < 0) return false;
    over.removeAt(i);
  }
  return true;
}

/// Are these two titles the same song, allowing for how differently catalogues spell them?
///
/// MusicBrainz writes "If You Want It to Be Good Girl" where the ripper — and another pressing of
/// the same record — writes "If You Want to Be a Good Girl". Judged on exact text those are two
/// songs, which made a complete album look incomplete and then offered the user a track they
/// already owned as a bonus.
///
/// Narrow on purpose: four fifths of the words shared, running times that agree where both are
/// known, and the SAME version markers on both sides — so a "(radio edit)" is never the album cut,
/// however alike the words.
bool sameTitle(String a, String b, {int? secondsA, int? secondsB}) {
  final aw = _words(a), bw = _words(b);
  if (aw.isEmpty || bw.isEmpty) return false;
  if (secondsA != null &&
      secondsB != null &&
      secondsA > 0 &&
      secondsB > 0 &&
      (secondsA - secondsB).abs() > _slack) {
    return false;
  }
  if (!_sameMarkers(versionMarkers(a), versionMarkers(b))) return false;
  final shared = aw.intersection(bw).length;
  return shared / (aw.length > bw.length ? aw.length : bw.length) >= .8;
}

/// Two files of one record that hold the same recording.
///
/// Named apart from `sameRecordingScore` in organize.dart on purpose: that one asks whether a peer's
/// offering is the track you clicked, this one asks whether two files you already own are the same
/// song. Same question, opposite side of the download.
class SameRecordingPair {
  /// The copy worth keeping, and the one it beats.
  final Track keep, drop;

  /// Why [keep] wins, in words, from the same grounds [firstIsBetter] decides on.
  final String why;
  const SameRecordingPair(this.keep, this.drop, this.why);
}

/// Files in one album that are the same recording twice.
///
/// Deliberately NOT on running time alone. On Backstreet's Back ten of the pairs fall within
/// [_slack] seconds of each other — 4:23 beside 4:25, 3:30 beside 3:33 — so a length-only rule
/// would call half the record a duplicate. The pair has to agree on the TITLE as well, through the
/// same [sameTitle] the pressing match uses: four fifths of the words, running times that agree,
/// and the SAME version markers, so a radio edit is never folded into the album cut.
///
/// This is the pair the album page could not see. Two rips of "If You Want It to Be Good Girl"
/// landed under different names because they were filed against different pressings, and nothing
/// afterwards ever compared two files in the library with each other.
///
/// [better] decides which copy wins; it reads the files, so it is passed in and the pure part of
/// this stays testable without a disk.
/// [prints] is what the AUDIO says, by file path, and when it has an opinion it is the last word.
///
/// The titles were all this ever had, and titles are the thing that is wrong. Michael Jackson's
/// *Off The Wall* holds one recording twice in one folder, filed as "Workin' Day and Night" and
/// "Working Day And Night": three of four words shared, so [sameTitle] says no and the album kept
/// two copies of one song — which is exactly the kind of clash that splits a record into two tiles.
/// The fingerprints score that pair 1.000.
///
/// It overrules in both directions, and the second one matters more. Adele's *30* has "Easy On Me"
/// and "Easy On Me (With Chris Stapleton)" — near-identical titles, near-identical length — and the
/// audio says 0.929: the same backing, a different performance. Without a listen, that duet was a
/// deletion waiting to be offered.
List<SameRecordingPair> sameRecordingPairs(
  List<Track> tracks, {
  required bool Function(Track a, Track b) better,
  String Function(Track keep, Track drop)? why,
  Map<String, List<int>> prints = const {},
}) {
  final out = <SameRecordingPair>[];
  final spoken = <String>{};
  for (var i = 0; i < tracks.length; i++) {
    final a = tracks[i];
    if (spoken.contains(a.path)) continue;
    final sa = a.duration?.inSeconds ?? 0;
    final fa = prints[a.path];
    // No length and no fingerprint means no evidence — a title alone is not enough to drop a file.
    if (sa <= 0 && fa == null) continue;
    for (var j = i + 1; j < tracks.length; j++) {
      final b = tracks[j];
      if (spoken.contains(b.path)) continue;
      final sb = b.duration?.inSeconds ?? 0;
      final fb = prints[b.path];
      if (sb <= 0 && fb == null) continue;
      if (fa != null && fb != null) {
        // Both were heard. Whatever the tags claim, this decides.
        if (similarity(fa, fb) < sameRecordingScore) continue;
      } else {
        if (sa <= 0 || sb <= 0) continue;
        if (!sameTitle(a.title, b.title, secondsA: sa, secondsB: sb)) continue;
      }
      final aWins = better(a, b);
      final keep = aWins ? a : b, drop = aWins ? b : a;
      out.add(SameRecordingPair(keep, drop, why?.call(keep, drop) ?? ''));
      spoken..add(a.path)..add(b.path);
      break; // one partner per file; a third copy is reported the next time round
    }
  }
  return out;
}

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

/// What the other pressings of this record have that you don't.
///
/// Backstreet's Back is eleven tracks in Britain and thirteen in America, plus a Malaysian second
/// disc with a Christmas song on it. None of that is missing from your record — it was never on
/// it — but it is the rest of the record, and worth being able to see and fetch.
///
/// Two things disqualify a track, and BOTH are needed. It must not be on your pressing, and it
/// must not be on your disk: the first pass alone offered the user back the radio edit they
/// already owned, because their pressing doesn't list it. Both comparisons go through [sameTitle],
/// so a pressing that spells a title its own way doesn't produce a phantom bonus — that is exactly
/// how "If You Want to Be a Good Girl" ended up offered to someone who had it as track 10.
List<BonusTrack> bonusTracks(
  List<ChoiceTrack> mine,
  List<Track> onDisk,
  String artist,
  List<(String, List<ChoiceTrack>)> others,
) {
  final out = <BonusTrack>[];
  for (final (edition, tracks) in others) {
    // "Do I have this?" is asked by running the pressing through the ordinary matcher, so a bonus
    // is judged by exactly the same three passes as the tracklist above it. Titles alone were not
    // enough: the radio edit carries its marker in the FILENAME and not in the tag, so on titles
    // it read as a track the user didn't have — and was offered back to them.
    final c = matchAlbumTracks(tracks, onDisk, artist);
    for (final s in c.slots) {
      if (s.index < 0 || !s.missing) continue;
      final t = s.official!;
      if (t.title.trim().isEmpty) continue;
      bool same(ChoiceTrack o) =>
          sameTitle(o.title, t.title, secondsA: o.seconds, secondsB: t.seconds);
      if (mine.any(same) || out.any((b) => same(b.track))) continue;
      out.add(BonusTrack(t, edition));
    }
  }
  return out;
}
