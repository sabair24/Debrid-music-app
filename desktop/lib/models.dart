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

  /// File modified time (ms since epoch) — used for "recently added" sorting + the home screen.
  final int addedMs;

  /// File size in bytes — with the duration this yields the effective bitrate, so we can show
  /// whether a FLAC is CD-quality (16/44) or hi-res (24-bit).
  final int sizeBytes;

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
    this.addedMs = 0,
    this.sizeBytes = 0,
  });

  /// File extension (lowercase, no dot), e.g. "flac", "mp3".
  String get ext {
    final i = path.lastIndexOf('.');
    return i < 0 ? '' : path.substring(i + 1).toLowerCase();
  }
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

  /// Most recent file time among the tracks — "recently added".
  int get addedMs {
    var m = 0;
    for (final t in tracks) {
      if (t.addedMs > m) m = t.addedMs;
    }
    return m;
  }
}
