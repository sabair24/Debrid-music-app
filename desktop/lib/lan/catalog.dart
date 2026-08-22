import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import '../library.dart';
import '../echtheid_oordelen.dart';
import '../enrichment.dart';
import '../models.dart';
import '../organize.dart';
import 'dtos.dart';
import 'ids.dart';

/// One rendering of the library as the other devices see it, plus the lookups a request needs.
class CatalogSnapshot {
  final CatalogDto catalog;
  final Map<String, Track> trackById;
  final Map<String, Album> albumById;
  final Map<String, String> artistNameById;

  /// De ETag, zodat herhaald synchroniseren niets kost: een toestel dat deze versie al heeft stuurt
  /// `If-None-Match` en krijgt een 304 in plaats van megabytes JSON.
  ///
  /// Komt uit de vingerafdruk en NIET uit [json] — daarom is hij er zonder dat er iets gecodeerd is.
  final String etag;

  CatalogSnapshot({
    required this.catalog,
    required this.trackById,
    required this.albumById,
    required this.artistNameById,
    required this.etag,
  });

  /// De catalogus als verstuurbare bytes — pas berekend als iemand hem werkelijk opvraagt.
  ///
  /// **Waarom lui, en waarom dat veel uitmaakt.** Dit was een gewoon veld, gevuld in `_build()`. Dat
  /// betekende: elke keer dat de momentopname herbouwd werd, ging de HELE bibliotheek naar JSON —
  /// `catalog.toJson()` bouwt daarvoor eerst nog een tweede volledige boom van elk nummer, en dan
  /// gaan `jsonEncode` en `utf8.encode` daaroverheen. Megabytes, op de tekendraad van de pc.
  ///
  /// En herbouwen gebeurt vaker dan je denkt. De momentopname wordt vuil verklaard bij ELKE melding
  /// van de bibliotheek — honderden keren tijdens het verrijken van hoezen — en herbouwd bij het
  /// eerstvolgende verzoek. Dat verzoek is lang niet altijd `/api/catalog`: ook `/art/` en
  /// `/stream/` vragen de momentopname op, want die hebben de opzoektabellen nodig.
  ///
  /// Eén hoesje dat je iPad opvraagt kon dus een volledige JSON-codering van de hele bibliotheek op
  /// de pc uitlokken. Die twee wegen hebben aan `trackById` en `albumById` genoeg; nu betalen ze ook
  /// alleen daarvoor.
  late final List<int> json = utf8.encode(jsonEncode(catalog.toJson()));

  /// Dezelfde catalogus, ingepakt — één keer berekend per versie.
  ///
  /// **Waarom dit er niet was.** De server zet `autoCompress = false` met de reden "audio and covers
  /// are already compressed". Dat klopt voor audio en hoezen, maar het zette het óók uit voor dit
  /// antwoord: het enige dat groot én goed samendrukbaar is. Deze catalogus is JSON van megabytes,
  /// en de cloudkopie in dit project meet zelf dat diezelfde tekst ongeveer vijfvoudig comprimeert.
  ///
  /// Vier toestellen die na elke wijziging opnieuw synchroniseren betaalden dat vijfvoudig te veel
  /// over wifi. Dat is de "hij bevriest even" op de iPad en de Shield.
  ///
  /// Lui en gecachet, want dit hangt aan de momentopname en niet aan het verzoek: een tweede toestel
  /// dat dezelfde versie ophaalt betaalt het inpakken geen tweede keer. En de ETag blijft die van de
  /// ONgecomprimeerde inhoud, zodat een 304 hetzelfde blijft betekenen.
  late final List<int> gzipJson = gzip.encode(json);
}

/// Turns [LibraryStore] into the wire catalogue, and keeps it fresh.
///
/// Reading straight from the live store is the whole point: the covers you picked, the pressings
/// you pinned and the albums you merged live in those objects, so every device sees the library
/// you actually curated rather than a second scan's opinion of the same files.
///
/// Rebuilt lazily. The store notifies on every enriched cover — hundreds of times during startup —
/// and rebuilding eagerly would spend the whole startup hashing ids nobody asked for yet.
class LanCatalog {
  LanCatalog(this.library) {
    library.addListener(_markDirty);
  }

  final LibraryStore library;

  CatalogSnapshot? _snapshot;
  bool _dirty = true;

  /// path → track id. Survives rebuilds, so a rebuild is map-shuffling rather than re-hashing
  /// tens of thousands of paths.
  final Map<String, String> _trackIdCache = {};

  void _markDirty() => _dirty = true;

  void dispose() => library.removeListener(_markDirty);

  CatalogSnapshot snapshot() {
    final cached = _snapshot;
    if (!_dirty && cached != null) return cached;
    final built = _build();
    _snapshot = built;
    _dirty = false;
    return built;
  }

  Track? track(String id) => snapshot().trackById[id];

  Album? album(String id) => snapshot().albumById[id];

  /// Cover bytes for an artwork ref — an album id, or `artist-<id>` for an artist portrait.
  Uint8List? artwork(String ref) {
    if (ref.startsWith('artist-')) {
      final name = snapshot().artistNameById[ref.substring('artist-'.length)];
      return name == null ? null : library.artistImages[name];
    }
    return snapshot().albumById[ref]?.cover;
  }

  SearchResultDto search(String query, {int limit = 50}) {
    final q = searchKey(query);
    if (q.isEmpty) return const SearchResultDto();
    final snap = snapshot();
    bool hit(String s) => searchKey(s).contains(q);
    return SearchResultDto(
      artists: snap.catalog.artists.where((a) => hit(a.name)).take(limit).toList(),
      albums: snap.catalog.albums
          .where((a) => hit(a.title) || hit(a.artistName))
          .take(limit)
          .toList(),
      tracks: snap.catalog.tracks
          .where((t) => hit(t.title) || hit(t.artistName) || hit(t.albumTitle))
          .take(limit)
          .toList(),
    );
  }

  CatalogSnapshot _build() {
    final root = library.rootPath;
    final artists = <String, ArtistDto>{};
    final artistNameById = <String, String>{};
    final albums = <AlbumDto>[];
    final albumById = <String, Album>{};
    final tracks = <TrackDto>[];
    final trackById = <String, Track>{};
    final albumCounts = <String, int>{};

    for (final album in library.albums) {
      if (album.tracks.isEmpty) continue;

      final aKey = artistKey(album.artist);
      final aId = artistIdFor(aKey);
      artists.putIfAbsent(
        aId,
        () => ArtistDto(
          id: aId,
          name: album.artist,
          artworkRef: library.artistImages.containsKey(album.artist) ? 'artist-$aId' : null,
        ),
      );
      artistNameById[aId] = album.artist;
      albumCounts.update(aId, (n) => n + 1, ifAbsent: () => 1);

      final albId = albumIdFor(aKey, normKey(album.title), album.edition);
      albumById[albId] = album;
      albums.add(AlbumDto(
        id: albId,
        artistId: aId,
        artistName: album.artist,
        title: album.title,
        year: album.year,
        // Always offered: a cover the app has not fetched yet simply 404s, and the client falls
        // back to its placeholder. Withholding the ref would make it fall back forever.
        artworkRef: albId,
        trackCount: album.tracks.length,
        edition: album.edition,
        isSingle: album.isSingle,
        addedMs: album.addedMs,
        discogsRelease: library.pinnedRelease(album),
        mbid: library.pinnedMbid(album),
        merged: library.isMerged(album),
        styles: library.stylesOf(album),
        // Alleen een BEWUSTE keuze krijgt een merkteken: een hoes die de eigenaar zelf gecorrigeerd
        // heeft, of die bij een geïdentificeerde persing hoort. De automatisch verrijkte hoes
        // (`enriched`) niet — zie de uitleg bij [AlbumDto.artTag] en bij de vingerafdruk hieronder.
        artTag: CoverEnricher.hoesMerk(album.correctedCover ?? album.resolvedCover),
        // De scans die de eigenaar zelf heeft aangewezen. Stonden alleen op het toestel waar ze
        // gemaakt waren; zie [AlbumDto.artRoles].
        artRoles: library.albumArtRoles(album.artist, album.title),
      ));

      for (final t in album.tracks) {
        final tId = _trackIdCache.putIfAbsent(t.path, () => trackIdFor(t.path, root));
        trackById[tId] = t;
        final ext = t.ext;
        tracks.add(TrackDto(
          id: tId,
          albumId: albId,
          artistId: aId,
          title: t.title,
          artistName: t.artist,
          albumTitle: album.title,
          trackNo: t.trackNo,
          trackTotal: t.trackTotal,
          durationMs: t.duration?.inMilliseconds ?? 0,
          bitrate: t.bitrateKbps,
          sampleRate: t.sampleRate > 0 ? t.sampleRate : null,
          bitsPerSample: t.bitsPerSample > 0 ? t.bitsPerSample : null,
          lossless: t.isFlac || ext == 'wav' || ext == 'alac',
          sizeBytes: t.sizeBytes,
          year: t.year,
          genre: t.genre,
          mime: mimeForExt(ext),
          // The real extension is on the path on purpose: AVFoundation on the Apple clients works
          // out the format from it, and refuses an asset it cannot type.
          streamPath: '/stream/$tId.$ext',
          artworkRef: albId,
          ext: ext,
          addedMs: t.addedMs,
          // De meting gaat mee de lijn over. Alleen hier is `t.path` nog een echt bestandspad; op
          // een iPad heet ditzelfde nummer straks een stream-URL, en dan valt er niets meer te
          // meten of op te zoeken.
          echt: gemeten(t.path)?.toJson(),
        ));
      }
    }

    // Drop tracks that are hidden or otherwise not on an album — they'd be unreachable anyway.
    final artistList = [
      for (final a in artists.values)
        ArtistDto(
          id: a.id,
          name: a.name,
          artworkRef: a.artworkRef,
          albumCount: albumCounts[a.id] ?? 0,
          artChoice: {
            for (final kind in const ['portrait', 'backdrop', 'logo'])
              if (library.chosenArtistArt(a.name, kind) case final url?) kind: url,
          },
        )
    ]..sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));

    final catalog = CatalogDto(
      artists: artistList,
      albums: albums,
      tracks: tracks,
      generatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // Fingerprint the CONTENT, not the moment: `generatedAt` moves on every rebuild, and if that
    // were part of the ETag then enriching one cover — which changes not a byte of this JSON —
    // would push the whole catalogue down to every device again.
    //
    // Folded from a few fields rather than from the encoded body, because the body runs to
    // megabytes and encoding it twice to get a hash would be the most expensive thing here.
    final fingerprint = _Fnv();
    for (final a in artistList) {
      fingerprint
        ..add(a.id)
        ..add(a.name)
        ..add('${a.albumCount}')
        // A picked portrait is not a track change either.
        ..add(a.artChoice.entries.map((e) => '${e.key}=${e.value}').join(','));
    }
    for (final a in albums) {
      fingerprint
        ..add(a.id)
        ..add(a.title)
        ..add('${a.trackCount}')
        ..add(a.edition ?? '')
        // Pinning a pressing changes not a single track, so without this the ETag would not move
        // and no device would ever hear about it.
        ..add('${a.discogsRelease ?? ''}')
        ..add(a.mbid ?? '')
        // Merging, and what a record sounds like, change no track either.
        ..add(a.merged ? 'm' : '')
        ..add(a.styles.join(','))
        // En de hoes die de eigenaar zelf koos. De waarschuwing hierboven blijft staan — daarom
        // draagt dit veld ALLEEN een bewuste keuze en niet de automatische verrijking. Zonder deze
        // regel beweegt de vingerafdruk niet, krijgt een toestel een 304, en hoort het nooit dat de
        // hoes veranderd is: precies de bug die op 13-08-2026 gemeten werd.
        ..add(a.artTag ?? '')
        // En de scans die de eigenaar aanwees. Zelfde reden als hierboven: een aangewezen cd
        // verandert geen enkel nummer, dus zonder deze regel beweegt de vingerafdruk niet, krijgt
        // elk toestel een 304, en blijft die keuze op één toestel hangen.
        ..add(a.artRoles.entries.map((e) => '${e.key}=${e.value}').join(','));
    }
    for (final t in tracks) {
      fingerprint..add(t.id)..add(t.title)..add('${t.trackNo}')..add('${t.sizeBytes}');
    }

    return CatalogSnapshot(
      catalog: catalog,
      trackById: trackById,
      albumById: albumById,
      artistNameById: artistNameById,
      etag: '"${tracks.length}-${fingerprint.value}"',
    );
  }
}

/// FNV-1a, fed piece by piece. Only has to notice that something changed, so a cryptographic
/// hash would be the wrong tool — this runs over the whole library on every rebuild.
class _Fnv {
  int _h = 0xcbf29ce484222325;

  void add(String s) {
    for (final c in s.codeUnits) {
      _h ^= c & 0xFF;
      _h = (_h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    _h ^= 0x1F; // separator, so "ab"+"c" and "a"+"bc" don't collide
    _h = (_h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }

  /// As unsigned hex. Dart's ints are signed, so printing the accumulator directly yields a
  /// leading '-' — legal inside a quoted ETag, but it reads like a bug every time you see it.
  String get value {
    final high = (_h >> 32) & 0xFFFFFFFF;
    final low = _h & 0xFFFFFFFF;
    return high.toRadixString(16).padLeft(8, '0') + low.toRadixString(16).padLeft(8, '0');
  }
}
