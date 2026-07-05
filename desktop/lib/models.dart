import 'dart:typed_data';

/// One playable track. Covers are NOT stored per-track (memory) — they live on the
/// Album. Only a queued/playing track carries its cover, passed via the player.
class Track {
  final String path;
  final String title;
  final String artist;
  final String album; // empty tag => treated as a single
  final int trackNo;
  final Duration? duration;
  final bool isFlac;
  final int? year;
  final String? genre;

  Track({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    this.trackNo = 0,
    this.duration,
    this.isFlac = false,
    this.year,
    this.genre,
  });
}

/// A group of tracks sharing an artist + album (or a single, when there's no album tag).
class Album {
  final String title;
  final String artist;
  final List<Track> tracks;
  final bool isSingle;

  /// Cover embedded in the audio file (read once per album).
  Uint8List? embeddedCover;

  /// Web-fetched cover (Deezer/Discogs/MusicBrainz), set by the enricher.
  Uint8List? enriched;

  /// User-picked cover via the manual metadata editor — wins over everything and
  /// survives rescans (a wrong embedded cover must not come back).
  Uint8List? correctedCover;

  Album(this.title, this.artist, this.tracks, {this.isSingle = false});

  Uint8List? get cover => correctedCover ?? embeddedCover ?? enriched;

  int? get year {
    for (final t in tracks) {
      if (t.year != null) return t.year;
    }
    return null;
  }

  String? get genre {
    for (final t in tracks) {
      if (t.genre != null && t.genre!.isNotEmpty) return t.genre;
    }
    return null;
  }
}
