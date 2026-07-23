import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'release_format.dart';

/// MusicBrainz + the Cover Art Archive.
///
/// Why this exists next to Discogs rather than instead of it. MusicBrainz answers in ONE request
/// what Discogs needs four for — a release lookup returns the tracklist with millisecond timings,
/// the label, the catalogue number, the country, the barcode and the release group together, and a
/// release-group browse returns every pressing of a record at once instead of one request per
/// pressing. Measured on Adele's *30*: 386 ms against roughly 4,4 s, and 289 ms against 13 s. It
/// needs no token, so it also can't run out of one.
///
/// And the Cover Art Archive states what each scan IS — `Front`, `Back`, `Medium` — where the
/// Discogs path has to work it out from the pixels (see artwork.dart). A stated fact beats a good
/// guess, and the disc animation depends on getting that right.
///
/// Discogs keeps two jobs it is genuinely better at. Its scan collection is far broader: the
/// British CD of *30* has no art in the CAA at all while the Japanese one has twenty-one images,
/// so the fallback is not a formality. And its styles ("Deep House", "Synth-pop") are curated,
/// where MusicBrainz genres are vote counts with a long tail of noise — the release group of *30*
/// carries `trance` and `house` alongside `pop`.

/// One image in the Cover Art Archive, with what the archive says it is.
class MbImage {
  final String url, thumb;

  /// `Front`, `Back`, `Medium`, `Booklet`, `Tray`, `Spine`, `Obi`, …
  final List<String> types;

  /// The archive's own flags for the two that matter most; an image can be the front cover without
  /// carrying the `Front` type.
  final bool isFrontFlag, isBackFlag;
  const MbImage(this.url, this.thumb, this.types, this.isFrontFlag, this.isBackFlag);

  bool get isFront => isFrontFlag || types.contains('Front');
  bool get isBack => isBackFlag || types.contains('Back');

  /// The disc itself. This is the one the Discogs path has to guess at.
  bool get isDisc => types.contains('Medium');

  static MbImage? from(Map<String, dynamic> j) {
    final url = (j['image'] ?? '').toString();
    if (url.isEmpty) return null;
    final th = j['thumbnails'];
    final thumb = th is Map ? ((th['500'] ?? th['large'] ?? th['250'] ?? url).toString()) : url;
    return MbImage(
      url,
      thumb,
      [for (final t in (j['types'] as List<dynamic>? ?? const [])) t.toString()],
      j['front'] == true,
      j['back'] == true,
    );
  }
}

class MbTrack {
  final String position, title;

  /// Milliseconds, or null when this recording has no timing.
  final int? ms;
  const MbTrack(this.position, this.title, this.ms);

  int? get seconds => ms == null ? null : (ms! / 1000).round();
}

/// One pressing.
class MbRelease {
  final String mbid, title, artist;
  final String? country, date, barcode, label, catno, releaseGroupId, status;

  /// As MusicBrainz spells it: `CD`, `12" Vinyl`, `Digital Media`, `Enhanced CD`.
  final String format;
  final int trackCount;
  final List<MbTrack> tracks;
  final List<String> genres;

  /// When the RECORD came out, as opposed to when this pressing did.
  final int? albumYear;

  const MbRelease({
    required this.mbid,
    required this.title,
    this.artist = '',
    this.country,
    this.date,
    this.barcode,
    this.label,
    this.catno,
    this.releaseGroupId,
    this.status,
    this.format = '',
    this.trackCount = 0,
    this.tracks = const [],
    this.genres = const [],
    this.albumYear,
  });

  String get major => majorFormat(format);

  int? get year {
    final d = date ?? '';
    if (d.length < 4) return null;
    return int.tryParse(d.substring(0, 4));
  }

  /// Is this entry filled in, or a stub nobody has documented? Same question the Discogs path asks,
  /// for the same reason: describing a record with an empty entry makes its page emptier.
  bool get isDocumented =>
      (label ?? '').isNotEmpty || (catno ?? '').isNotEmpty || (country ?? '').isNotEmpty;

  /// "CD · JP · SICP-6425 · 2021"
  String get line => [
        if (format.isNotEmpty) format,
        if ((country ?? '').isNotEmpty) country!,
        if ((catno ?? '').isNotEmpty) catno!,
        if (year != null) '$year',
      ].join(' · ');

  static MbRelease from(Map<String, dynamic> j) {
    final media = (j['media'] as List<dynamic>? ?? const []);
    final formats = <String>[];
    var count = 0;
    final tracks = <MbTrack>[];
    for (final m in media) {
      if (m is! Map) continue;
      final f = (m['format'] ?? '').toString();
      if (f.isNotEmpty) formats.add(f);
      count += ((m['track-count'] as num?) ?? 0).toInt();
      for (final t in (m['tracks'] as List<dynamic>? ?? const [])) {
        if (t is! Map) continue;
        tracks.add(MbTrack(
          (t['number'] ?? '').toString(),
          (t['title'] ?? '').toString(),
          (t['length'] as num?)?.toInt(),
        ));
      }
    }
    // A double LP reports its format twice; one name is enough to rank it by.
    final format = formats.isEmpty ? '' : formats.toSet().join(' + ');

    final credits = (j['artist-credit'] as List<dynamic>? ?? const []);
    final artist = credits.isEmpty
        ? ''
        : credits
            .map((c) => c is Map ? ((c['name'] ?? c['artist']?['name'] ?? '').toString()) : '')
            .join(' ')
            .trim();

    String? label, catno;
    for (final li in (j['label-info'] as List<dynamic>? ?? const [])) {
      if (li is! Map) continue;
      label ??= (li['label'] is Map ? li['label']['name'] : null)?.toString();
      catno ??= li['catalog-number']?.toString();
    }

    final rg = j['release-group'];
    final rgDate = rg is Map ? (rg['first-release-date'] ?? '').toString() : '';

    return MbRelease(
      mbid: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      artist: artist,
      country: (j['country'] as String?)?.trim(),
      date: (j['date'] as String?)?.trim(),
      barcode: (j['barcode'] as String?)?.trim(),
      label: (label ?? '').trim().isEmpty ? null : label!.trim(),
      catno: (catno ?? '').trim().isEmpty ? null : catno!.trim(),
      releaseGroupId: rg is Map ? rg['id']?.toString() : null,
      status: (j['status'] as String?)?.trim(),
      format: format,
      // `track-count` at the top level is what search results carry; media is what a lookup carries.
      trackCount: count > 0 ? count : ((j['track-count'] as num?) ?? 0).toInt(),
      tracks: tracks,
      genres: [
        for (final g in (j['genres'] as List<dynamic>? ?? const []))
          if (g is Map && g['name'] != null) g['name'].toString()
      ],
      albumYear: rgDate.length >= 4 ? int.tryParse(rgDate.substring(0, 4)) : null,
    );
  }
}

class MusicBrainzService {
  /// MusicBrainz refuses anonymous clients and asks that the agent name a way to reach whoever
  /// wrote it. That is the whole price of admission — there is no token.
  static const _ua = 'DebridMusic/1.0 ( https://github.com/sabair24/Debrid-music-app )';

  static const _root = 'https://musicbrainz.org/ws/2';
  static const _caa = 'https://coverartarchive.org';

  /// Nothing to configure, so this source is always up.
  bool get available => true;

  // ── Rate limit ──────────────────────────────────────────────────────────────
  // MusicBrainz asks for one request a second, averaged, and returns 503 above it. The webservice
  // and the Cover Art Archive are different machines — the archive serves static files from
  // archive.org — so they queue separately; making a gallery of twelve pressings wait twelve
  // seconds for its images would be politeness aimed at the wrong host.
  static const _wsGap = Duration(milliseconds: 1100);
  static const _caaGap = Duration(milliseconds: 250);
  final _lastCall = <String, DateTime>{};
  final _turn = <String, Future<void>>{};

  /// Serialised per host, spaced out, disk-cached. Null on any failure: a missing album page is a
  /// disappointment, a crashed one is a bug.
  Future<Map<String, dynamic>?> _get(String url, {required String lane, required Duration gap}) async {
    final cached = await _readCache(url);
    if (cached != null) return cached;

    final done = Completer<Map<String, dynamic>?>();
    _turn[lane] = (_turn[lane] ?? Future.value()).then((_) async {
      try {
        final last = _lastCall[lane] ?? DateTime.fromMillisecondsSinceEpoch(0);
        final since = DateTime.now().difference(last);
        if (since < gap) await Future<void>.delayed(gap - since);
        _lastCall[lane] = DateTime.now();
        final r = await http
            .get(Uri.parse(url), headers: {'User-Agent': _ua, 'Accept': 'application/json'})
            .timeout(const Duration(seconds: 12));
        // 404 from the Cover Art Archive means this pressing has no scans. Very common, and not a
        // failure — it is the signal to fall back to Discogs.
        if (r.statusCode != 200) {
          done.complete(null);
          return;
        }
        final body = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
        if (body is! Map<String, dynamic>) {
          done.complete(null);
          return;
        }
        await _writeCache(url, body);
        done.complete(body);
      } catch (_) {
        done.complete(null);
      }
    });
    return done.future;
  }

  Future<Map<String, dynamic>?> _ws(String url) => _get(url, lane: 'ws', gap: _wsGap);

  // ── Cache ───────────────────────────────────────────────────────────────────
  // The data barely changes and the request budget is the scarce thing, so everything fetched is
  // kept. Once a library has been browsed it can be browsed again offline.
  String get _dir =>
      '${Platform.environment['APPDATA'] ?? Directory.current.path}${Platform.pathSeparator}DebridMusic'
      '${Platform.pathSeparator}musicbrainz';

  File _cacheFile(String url) =>
      File('$_dir${Platform.pathSeparator}${sha1.convert(utf8.encode(url))}.json');

  Future<Map<String, dynamic>?> _readCache(String url) async {
    try {
      final f = _cacheFile(url);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String url, Map<String, dynamic> body) async {
    try {
      await Directory(_dir).create(recursive: true);
      await _cacheFile(url).writeAsString(jsonEncode(body));
    } catch (_) {/* a cache that can't be written is not a reason to fail the call */}
  }

  /// Lucene needs its own punctuation escaped, or a title with a colon in it — *Interstella 5555:
  /// The Story* — becomes a field query and matches nothing.
  static String _lucene(String s) => s.replaceAllMapped(
      RegExp(r'([+\-!(){}\[\]^"~*?:\\/]|&&|\|\|)'), (m) => '\\${m[0]}');

  // ── Releases ────────────────────────────────────────────────────────────────

  /// Pressings of a record, best first.
  ///
  /// The search response already carries format, country, track count and date, so ranking costs no
  /// extra request — the thing that makes the Discogs path walk masters and versions one at a time.
  Future<List<MbRelease>> searchReleases(String artist, String album,
      {int expectedTracks = 0, int max = 25}) async {
    if (album.trim().isEmpty) return const [];
    final q = artist.trim().isEmpty
        ? 'release:"${_lucene(album.trim())}"'
        : 'artist:"${_lucene(artist.trim())}" AND release:"${_lucene(album.trim())}"';
    final body = await _ws('$_root/release/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=$max');
    final list = body?['releases'] as List<dynamic>? ?? const [];
    final out = <MbRelease>[];
    for (final r in list) {
      if (r is Map<String, dynamic>) out.add(MbRelease.from(r));
    }
    return orderByPreference(out, expectedTracks: expectedTracks);
  }

  /// One pressing, fully loaded: tracklist with timings, label, catalogue number, release group.
  Future<MbRelease?> release(String mbid) async {
    if (mbid.trim().isEmpty) return null;
    final body = await _ws(
        '$_root/release/${mbid.trim()}?fmt=json&inc=recordings+artist-credits+labels+release-groups');
    return body == null ? null : MbRelease.from(body);
  }

  /// Every pressing of a record, in one request.
  Future<List<MbRelease>> editionsOf(String releaseGroupId, {int max = 100}) async {
    if (releaseGroupId.trim().isEmpty) return const [];
    final body = await _ws('$_root/release?release-group=${releaseGroupId.trim()}'
        '&fmt=json&inc=media+labels+artist-credits&limit=$max');
    final list = body?['releases'] as List<dynamic>? ?? const [];
    final out = <MbRelease>[];
    for (final r in list) {
      if (r is Map<String, dynamic>) out.add(MbRelease.from(r));
    }
    return orderByPreference(out);
  }

  /// CD first, digital last, documented before stubs — the shared preference in
  /// [releaseFormatOrder], applied to MusicBrainz's own format names.
  ///
  /// [expectedTracks] drops the pressings that are a different record: a single or a sampler filed
  /// under the same release group, or a box set that carries two albums. Both directions matter —
  /// checking only for "too few" let *Discovery* land on a double CD that was also Homework.
  static List<MbRelease> orderByPreference(List<MbRelease> all, {int expectedTracks = 0}) {
    final out = [
      for (final r in all)
        if (r.mbid.isNotEmpty &&
            (expectedTracks <= 0 ||
                r.trackCount == 0 ||
                (r.trackCount >= expectedTracks - 2 && r.trackCount <= expectedTracks * 1.5 + 3)))
          r
    ];
    out.sort((a, b) {
      // Official beats a bootleg or a promo for describing what the record is.
      final byStatus = ((a.status ?? '') == 'Official' ? 0 : 1)
          .compareTo((b.status ?? '') == 'Official' ? 0 : 1);
      final byFormat = releaseFormatRank(a.major).compareTo(releaseFormatRank(b.major));
      // A documented CD must beat an undocumented one, but never let an undocumented digital entry
      // jump a documented CD — the format preference is the stronger of the two.
      if (byFormat != 0) return byFormat;
      if (byStatus != 0) return byStatus;
      final byDoc = (a.isDocumented ? 0 : 1).compareTo(b.isDocumented ? 0 : 1);
      if (byDoc != 0) return byDoc;
      // Oldest first: the original pressing describes the record, a 2015 repress describes itself.
      return (a.year ?? 9999).compareTo(b.year ?? 9999);
    });
    return out;
  }

  // ── Cover Art Archive ───────────────────────────────────────────────────────

  /// The scans for a pressing, each saying what it is. Empty when the archive has none — which is
  /// common enough that the caller must have somewhere else to go.
  Future<List<MbImage>> art(String mbid) async {
    if (mbid.trim().isEmpty) return const [];
    final body = await _get('$_caa/release/${mbid.trim()}', lane: 'caa', gap: _caaGap);
    final list = body?['images'] as List<dynamic>? ?? const [];
    final out = <MbImage>[];
    for (final i in list) {
      if (i is! Map<String, dynamic>) continue;
      final img = MbImage.from(i);
      if (img != null) out.add(img);
    }
    return out;
  }

  Future<Uint8List?> fetchImage(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url), headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
      return r.statusCode == 200 && r.bodyBytes.length > 500 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}
