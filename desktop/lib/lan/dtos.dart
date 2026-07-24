/// Wire types shared with the Android/TV client and the Apple apps.
///
/// The field names are copied verbatim from the Kotlin server's
/// `server/src/main/kotlin/com/debridmusic/server/model/Dtos.kt`. That is deliberate: the Android
/// app already deserialises exactly this shape (`app/.../server/ServerDtos.kt`) and turns it into
/// its library (`MusicRepository.syncServerLibrary`), so speaking the same JSON means the phone
/// and the Shield work against this server without being rewritten.
///
/// Fields added here that Kotlin doesn't have (`edition`, `isSingle`, `bitsPerSample`, `ext`,
/// `trackTotal`) are safe: both clients ignore unknown keys.
///
/// The `fromJson` side is used by this same app running as a CLIENT — on the Mac and the iPad it
/// fills its [LibraryStore] from `/api/catalog` instead of from disk. Encoder and decoder sitting
/// in one file is the point: a field added to the wire cannot be forgotten on the way back in.
library;

/// JSON numbers arrive as int, but a hand-written fixture or another client may send a double or
/// a string. Coercing here keeps every call site free of the question.
int _int(Object? v, [int fallback = 0]) => switch (v) {
      final int i => i,
      final num n => n.toInt(),
      final String s => int.tryParse(s) ?? fallback,
      _ => fallback,
    };

int? _intOrNull(Object? v) => v == null ? null : _int(v);

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

class ArtistDto {
  final String id;
  final String name;
  final String? artworkRef;
  final int albumCount;

  /// Portraits and backdrops the user picked by hand, by kind ("portrait", "backdrop", "logo").
  /// Carried so a Mac and an iPad show the picture that was chosen rather than going off and
  /// finding their own — which is the app arguing with its owner.
  final Map<String, String> artChoice;

  const ArtistDto({
    required this.id,
    required this.name,
    this.artworkRef,
    this.albumCount = 0,
    this.artChoice = const {},
  });

  factory ArtistDto.fromJson(Map<String, dynamic> j) => ArtistDto(
        id: _str(j['id']),
        name: _str(j['name']),
        artworkRef: j['artworkRef'] as String?,
        albumCount: _int(j['albumCount']),
        artChoice: {
          for (final e in (j['artChoice'] as Map? ?? const {}).entries)
            if (e.value is String) '${e.key}': e.value as String,
        },
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'artworkRef': artworkRef,
        'albumCount': albumCount,
        'artChoice': artChoice,
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

  /// The exact pressing the user pinned, if they pinned one. Carried because the sleeve looks up
  /// its disc scan by release: without it a Mac or an iPad falls back to searching by artist and
  /// title, which gets the wrong pressing for exactly the records someone pinned one BECAUSE the
  /// automatic guess was wrong.
  final int? discogsRelease;
  final String? mbid;

  /// Told to keep its pressings together. The merge/unmerge control reads this, and without it a
  /// client shows the wrong state — offering to merge a record that already is.
  final bool merged;

  /// What this record sounds like, as Discogs describes it. Feeds the Ontdek screen, which is
  /// simply empty on a device that has none.
  final List<String> styles;

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
    this.discogsRelease,
    this.mbid,
    this.merged = false,
    this.styles = const [],
  });

  factory AlbumDto.fromJson(Map<String, dynamic> j) => AlbumDto(
        id: _str(j['id']),
        artistId: _str(j['artistId']),
        artistName: _str(j['artistName']),
        title: _str(j['title']),
        year: _intOrNull(j['year']),
        artworkRef: j['artworkRef'] as String?,
        trackCount: _int(j['trackCount']),
        edition: j['edition'] as String?,
        isSingle: j['isSingle'] == true,
        addedMs: _int(j['addedMs']),
        discogsRelease: _intOrNull(j['discogsRelease']),
        mbid: j['mbid'] as String?,
        merged: j['merged'] == true,
        styles: [
          for (final v in (j['styles'] as List? ?? const []))
            if (v is String) v,
        ],
      );

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
        'discogsRelease': discogsRelease,
        'mbid': mbid,
        'merged': merged,
        'styles': styles,
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

  /// How many tracks the pressing has, as the file's own tag says it. Carried because the track
  /// list shows "3 / 12", and because it is what names an edition ("12 nummers") when the library
  /// holds more than one pressing of a record.
  final int trackTotal;
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
    this.trackTotal = 0,
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

  factory TrackDto.fromJson(Map<String, dynamic> j) => TrackDto(
        id: _str(j['id']),
        albumId: _str(j['albumId']),
        artistId: _str(j['artistId']),
        title: _str(j['title']),
        artistName: _str(j['artistName']),
        albumTitle: _str(j['albumTitle']),
        streamPath: _str(j['streamPath']),
        ext: _str(j['ext']),
        trackNo: _int(j['trackNo']),
        trackTotal: _int(j['trackTotal']),
        discNo: _int(j['discNo'], 1),
        durationMs: _int(j['durationMs']),
        bitrate: _intOrNull(j['bitrate']),
        sampleRate: _intOrNull(j['sampleRate']),
        bitsPerSample: _intOrNull(j['bitsPerSample']),
        lossless: j['lossless'] == true,
        sizeBytes: _int(j['sizeBytes']),
        year: _intOrNull(j['year']),
        genre: j['genre'] as String?,
        mime: j['mime'] as String?,
        artworkRef: j['artworkRef'] as String?,
        addedMs: _int(j['addedMs']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'albumId': albumId,
        'artistId': artistId,
        'title': title,
        'artistName': artistName,
        'albumTitle': albumTitle,
        'trackNo': trackNo,
        'trackTotal': trackTotal,
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

  factory CatalogDto.fromJson(Map<String, dynamic> j) => CatalogDto(
        artists: _list(j['artists'], ArtistDto.fromJson),
        albums: _list(j['albums'], AlbumDto.fromJson),
        tracks: _list(j['tracks'], TrackDto.fromJson),
        generatedAt: _int(j['generatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'artists': [for (final a in artists) a.toJson()],
        'albums': [for (final a in albums) a.toJson()],
        'tracks': [for (final t in tracks) t.toJson()],
        'generatedAt': generatedAt,
      };
}

/// Decode a JSON array, skipping anything that isn't an object. A single malformed entry must not
/// cost the whole library — on a client that means an empty screen, with no way to tell why.
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) from) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (e is Map<String, dynamic>) from(e),
  ];
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
