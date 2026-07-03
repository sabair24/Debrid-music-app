import 'dart:typed_data';

/// One playable track from the local library.
class Track {
  final String path;
  final String title;
  final String artist;
  final String album;
  final int trackNo;
  final Uint8List? cover;
  final Duration? duration;
  final bool isFlac;

  Track({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    this.trackNo = 0,
    this.cover,
    this.duration,
    this.isFlac = false,
  });
}

/// A group of tracks sharing an artist + album.
class Album {
  final String title;
  final String artist;
  final List<Track> tracks;

  Album(this.title, this.artist, this.tracks);

  Uint8List? get cover {
    for (final t in tracks) {
      if (t.cover != null) return t.cover;
    }
    return null;
  }
}
