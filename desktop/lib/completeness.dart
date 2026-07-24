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

  const AlbumSlot({required this.index, this.official, this.track});

  bool get missing => track == null;

  /// The number to show. The release decides it, not the file's own tag — a peer's numbering is
  /// whatever its uploader typed, and following it is what put "Anywhere for You" at 20.
  int get number {
    final p = int.tryParse((official?.position ?? '').trim());
    if (p != null && p > 0) return p;
    if (track != null && track!.trackNo > 0) return track!.trackNo;
    return index + 1;
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
}

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

  return AlbumCompleteness(
    [
      for (var i = 0; i < official.length; i++)
        AlbumSlot(index: i, official: official[i], track: owned[i]),
      // Whatever the release doesn't account for, last and still playable.
      for (final t in tracks)
        if (!claimed.contains(t.path)) AlbumSlot(index: -1, track: t),
    ],
    source: source,
  );
}

/// Seconds two timings may differ and still be the same recording. Matches [fileOffersTitle].
const _slack = 12;
