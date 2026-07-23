/// Wire types shared with the Android/TV client and the Apple apps.
///
/// The field names are copied verbatim from the Kotlin server's
/// `server/src/main/kotlin/com/debridmusic/server/model/Dtos.kt`. That is deliberate: the Android
/// app already deserialises exactly this shape (`app/.../server/ServerDtos.kt`) and turns it into
/// its library (`MusicRepository.syncServerLibrary`), so speaking the same JSON means the phone
/// and the Shield work against this server without being rewritten.
///
/// Fields added here that Kotlin doesn't have (`edition`, `isSingle`, `bitsPerSample`, `ext`) are
/// safe: both clients ignore unknown keys.
library;

class ArtistDto {
  final String id;
  final String name;
  final String? artworkRef;
  final int albumCount;

  const ArtistDto({
    required this.id,
    required this.name,
    this.artworkRef,
    this.albumCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'artworkRef': artworkRef,
        'albumCount': albumCount,
      };
}

class AlbumDto {
  final String id;
  final String artistId;
  final String artistName;
  final String title;
  final int? year;
  final String? artworkRef;
  final int trackCount;

  /// Which pressing this is, when the library holds more than one of the same record. Null for
  /// the ordinary case of a single pressing.
  final String? edition;
  final bool isSingle;

  /// Newest file time among its tracks — lets a client sort "recently added" without the tracks.
  final int addedMs;

  const AlbumDto({
    required this.id,
    required this.artistId,
    required this.artistName,
    required this.title,
    this.year,
    this.artworkRef,
    this.trackCount = 0,
    this.edition,
    this.isSingle = false,
    this.addedMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'artistId': artistId,
        'artistName': artistName,
        'title': title,
        'year': year,
        'artworkRef': artworkRef,
        'trackCount': trackCount,
        'edition': edition,
        'isSingle': isSingle,
        'addedMs': addedMs,
      };
}

class TrackDto {
  final String id;
  final String albumId;
  final String artistId;
  final String title;
  final String artistName;
  final String albumTitle;
  final int trackNo;
  final int discNo;
  final int durationMs;
  final int? bitrate;
  final int? sampleRate;
  final int? bitsPerSample;
  final bool lossless;
  final int sizeBytes;
  final int? year;
  final String? genre;
  final String? mime;
  final String streamPath;
  final String? artworkRef;
  final String ext;
  final int addedMs;

  const TrackDto({
    required this.id,
    required this.albumId,
    required this.artistId,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.streamPath,
    required this.ext,
    this.trackNo = 0,
    this.discNo = 1,
    this.durationMs = 0,
    this.bitrate,
    this.sampleRate,
    this.bitsPerSample,
    this.lossless = false,
    this.sizeBytes = 0,
    this.year,
    this.genre,
    this.mime,
    this.artworkRef,
    this.addedMs = 0,
  });

  /// True when the file is beyond what Sonos will accept (it plays FLAC/ALAC up to 24-bit but
  /// only to 48 kHz, and *skips* anything above rather than downsampling it). The cast path uses
  /// this to decide whether a Sonos target needs a converted stream.
  bool get needsSonosDownsample => (sampleRate ?? 0) > 48000;

  Map<String, dynamic> toJson() => {
        'id': id,
        'albumId': albumId,
        'artistId': artistId,
        'title': title,
        'artistName': artistName,
        'albumTitle': albumTitle,
        'trackNo': trackNo,
        'discNo': discNo,
        'durationMs': durationMs,
        'bitrate': bitrate,
        'sampleRate': sampleRate,
        'bitsPerSample': bitsPerSample,
        'lossless': lossless,
        'sizeBytes': sizeBytes,
        'year': year,
        'genre': genre,
        'mime': mime,
        'streamPath': streamPath,
        'artworkRef': artworkRef,
        'ext': ext,
        'addedMs': addedMs,
      };
}

class CatalogDto {
  final List<ArtistDto> artists;
  final List<AlbumDto> albums;
  final List<TrackDto> tracks;
  final int generatedAt;

  const CatalogDto({
    this.artists = const [],
    this.albums = const [],
    this.tracks = const [],
    this.generatedAt = 0,
  });

  Map<String, dynamic> toJson() => {
        'artists': [for (final a in artists) a.toJson()],
        'albums': [for (final a in albums) a.toJson()],
        'tracks': [for (final t in tracks) t.toJson()],
        'generatedAt': generatedAt,
      };
}

class SearchResultDto {
  final List<ArtistDto> artists;
  final List<AlbumDto> albums;
  final List<TrackDto> tracks;

  const SearchResultDto({
    this.artists = const [],
    this.albums = const [],
    this.tracks = const [],
  });

  Map<String, dynamic> toJson() => {
        'artists': [for (final a in artists) a.toJson()],
        'albums': [for (final a in albums) a.toJson()],
        'tracks': [for (final t in tracks) t.toJson()],
      };
}

/// MIME type per extension. Handed to the speaker in the UPnP metadata and set on `/stream`,
/// where it matters more than it looks: AVFoundation on the Apple clients refuses an asset whose
/// type it cannot work out, and a UPnP renderer refuses a `protocolInfo` it doesn't recognise.
const Map<String, String> audioMimeTypes = {
  'flac': 'audio/flac',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'alac': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'opus': 'audio/opus',
  'wma': 'audio/x-ms-wma',
};

String mimeForExt(String ext) => audioMimeTypes[ext.toLowerCase()] ?? 'application/octet-stream';
