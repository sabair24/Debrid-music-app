import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';

/// One image a release or an artist offers. Discogs doesn't say what a picture IS beyond
/// primary/secondary — a release's secondaries are the back, the disc and the booklet, an artist's
/// are simply more photos — so the app decides what to use each one for, and so can the user.
class DiscogsImage {
  final String uri, thumb;
  final int width, height;
  final bool primary;
  const DiscogsImage(this.uri, this.thumb, this.width, this.height, this.primary);

  bool get isSquarish => height > 0 && (width / height - 1).abs() < .12;
  bool get isWide => height > 0 && width / height > 1.4;

  static DiscogsImage? from(Map<String, dynamic> j) {
    final uri = j['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    return DiscogsImage(
      uri,
      (j['uri150'] as String?) ?? uri,
      (j['width'] as num?)?.toInt() ?? 0,
      (j['height'] as num?)?.toInt() ?? 0,
      (j['type'] as String?) == 'primary',
    );
  }

  Map<String, dynamic> toJson() =>
      {'uri': uri, 'thumb': thumb, 'width': width, 'height': height, 'primary': primary};
  static DiscogsImage fromJson(Map<String, dynamic> j) => DiscogsImage(
        j['uri'] as String? ?? '',
        j['thumb'] as String? ?? '',
        (j['width'] as num?)?.toInt() ?? 0,
        (j['height'] as num?)?.toInt() ?? 0,
        j['primary'] as bool? ?? false,
      );
}

class DiscogsTrack {
  final String position, title, duration;
  final List<String> artists; // per-track credits, for compilations and features
  const DiscogsTrack(this.position, this.title, this.duration, this.artists);

  /// Seconds, or null when Discogs has no timing for this track.
  int? get seconds {
    final p = duration.split(':').map((s) => int.tryParse(s.trim())).toList();
    if (p.any((n) => n == null) || p.isEmpty || p.length > 3) return null;
    return p.fold<int>(0, (a, n) => a * 60 + n!);
  }

  Map<String, dynamic> toJson() =>
      {'position': position, 'title': title, 'duration': duration, 'artists': artists};
  static DiscogsTrack fromJson(Map<String, dynamic> j) => DiscogsTrack(
        j['position'] as String? ?? '',
        j['title'] as String? ?? '',
        j['duration'] as String? ?? '',
        [for (final a in (j['artists'] as List<dynamic>? ?? const [])) a.toString()],
      );
}

/// One pressing of an album, with everything the library page shows about it.
class DiscogsEdition {
  final int releaseId;
  final String format; // File / CD / Vinyl / Cassette …
  final String? label, catno, country, notes;
  final int? year;
  final List<String> genres, styles;
  final List<DiscogsTrack> tracklist;
  final List<DiscogsImage> images;

  const DiscogsEdition({
    required this.releaseId,
    required this.format,
    this.label,
    this.catno,
    this.country,
    this.notes,
    this.year,
    this.genres = const [],
    this.styles = const [],
    this.tracklist = const [],
    this.images = const [],
  });

  Map<String, dynamic> toJson() => {
        'releaseId': releaseId,
        'format': format,
        'label': label,
        'catno': catno,
        'country': country,
        'notes': notes,
        'year': year,
        'genres': genres,
        'styles': styles,
        'tracklist': [for (final t in tracklist) t.toJson()],
        'images': [for (final i in images) i.toJson()],
      };

  static DiscogsEdition fromJson(Map<String, dynamic> j) => DiscogsEdition(
        releaseId: (j['releaseId'] as num?)?.toInt() ?? 0,
        format: j['format'] as String? ?? '',
        label: j['label'] as String?,
        catno: j['catno'] as String?,
        country: j['country'] as String?,
        notes: j['notes'] as String?,
        year: (j['year'] as num?)?.toInt(),
        genres: [for (final g in (j['genres'] as List<dynamic>? ?? const [])) g.toString()],
        styles: [for (final s in (j['styles'] as List<dynamic>? ?? const [])) s.toString()],
        tracklist: [
          for (final t in (j['tracklist'] as List<dynamic>? ?? const []))
            if (t is Map<String, dynamic>) DiscogsTrack.fromJson(t)
        ],
        images: [
          for (final i in (j['images'] as List<dynamic>? ?? const []))
            if (i is Map<String, dynamic>) DiscogsImage.fromJson(i)
        ],
      );
}

/// A version as it appears in a master's version list — cheap to get, one line each, and enough
/// to choose between them without fetching all 115 of them.
class DiscogsVersion {
  final int id;
  final String format, major;
  final String? label, catno, country, released;
  const DiscogsVersion(this.id, this.format, this.major, this.label, this.catno, this.country, this.released);

  /// Is this entry actually filled in, or is it a stub someone added and never finished?
  ///
  /// A year of "0" or nothing, no label and no catalogue number means nobody has documented this
  /// pressing. Preferring it over a fully described CD would make the album page emptier, which is
  /// the opposite of the point.
  bool get isDocumented {
    final y = int.tryParse((released ?? '').split('-').first) ?? 0;
    return y > 1900 && ((label ?? '').isNotEmpty || (catno ?? '').isNotEmpty);
  }

  int? get year {
    final y = int.tryParse((released ?? '').split('-').first) ?? 0;
    return y > 1900 ? y : null;
  }
}

/// Discogs: the deepest catalogue there is for what a record actually IS — every pressing, its
/// label, its catalogue number, who played on it. Deezer stays the search engine (it is faster and
/// far less noisy for pop, and it is the only one of the two that can recommend anything); this
/// fills in what Deezer doesn't know.
class DiscogsService {
  final AppSettings settings;
  DiscogsService(this.settings);

  static const _ua = 'DebridMusic/1.0 +https://github.com/sabair24/Debrid-music-app';

  bool get available => settings.discogsToken.trim().isNotEmpty;

  // ── Rate limit ────────────────────────────────────────────────────────────
  // Discogs allows 60 requests a minute per token and says how many are left in a header on every
  // response. Going over doesn't just fail the one call — it returns 429s for a while — so requests
  // are spaced out rather than fired in bursts, and the app slows down further when the header says
  // we're running low.
  static const _minGap = Duration(milliseconds: 1100);
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _turn = Future.value();
  int _remaining = 60;

  /// Serialises every call and keeps them [_minGap] apart. Returns null on any failure — a missing
  /// album page is a disappointment, a crashed one is a bug.
  Future<Map<String, dynamic>?> _get(String url) async {
    if (!available) return null;
    final cached = await _readCache(url);
    if (cached != null) return cached;

    final done = Completer<Map<String, dynamic>?>();
    _turn = _turn.then((_) async {
      try {
        final since = DateTime.now().difference(_lastCall);
        // Below a fifth of the budget, ease off hard: something else (a background sweep) is
        // eating it, and a 429 costs more than waiting.
        final gap = _remaining < 12 ? _minGap * 3 : _minGap;
        if (since < gap) await Future<void>.delayed(gap - since);
        _lastCall = DateTime.now();
        final r = await http.get(Uri.parse(url), headers: {
          'User-Agent': _ua,
          'Authorization': 'Discogs token=${settings.discogsToken.trim()}',
        }).timeout(const Duration(seconds: 12));
        final left = int.tryParse(r.headers['x-discogs-ratelimit-remaining'] ?? '');
        if (left != null) _remaining = left;
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

  // ── Cache ─────────────────────────────────────────────────────────────────
  // Discogs data barely changes and the rate limit is the scarce resource, so anything fetched is
  // kept. The whole library can then be browsed offline once it has been enriched.
  String get _dir =>
      '${Platform.environment['APPDATA'] ?? Directory.current.path}${Platform.pathSeparator}DebridMusic'
      '${Platform.pathSeparator}discogs';

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

  String _q(String s) => Uri.encodeQueryComponent(s);

  // ── Albums ────────────────────────────────────────────────────────────────

  /// The master id for an album, or null. A master groups every pressing of one record, which is
  /// what makes "which edition do we describe?" a question we can answer at all.
  Future<int?> masterId(String artist, String album) async {
    final strict =
        await _get('https://api.discogs.com/database/search?type=master&artist=${_q(artist)}&release_title=${_q(album)}');
    final id = _firstMaster(strict);
    if (id != null) return id;
    // Titles disagree about "(Deluxe Edition)", "- EP" and the like far more often than they
    // disagree about the words themselves, so fall back to a loose query.
    return _firstMaster(await _get('https://api.discogs.com/database/search?type=master&q=${_q('$artist $album')}'));
  }

  int? _firstMaster(Map<String, dynamic>? body) {
    final results = body?['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final id = (r['master_id'] as num?)?.toInt() ?? (r['id'] as num?)?.toInt();
      if (id != null && id > 0) return id;
    }
    return null;
  }

  Future<List<DiscogsVersion>> _versions(int master) async {
    final body = await _get('https://api.discogs.com/masters/$master/versions?per_page=100&sort=released');
    final list = body?['versions'] as List<dynamic>? ?? const [];
    final out = <DiscogsVersion>[];
    for (final v in list) {
      if (v is! Map<String, dynamic>) continue;
      final majors = [for (final m in (v['major_formats'] as List<dynamic>? ?? const [])) m.toString()];
      out.add(DiscogsVersion(
        (v['id'] as num?)?.toInt() ?? 0,
        v['format'] as String? ?? '',
        majors.isEmpty ? '' : majors.first,
        (v['label'] as String?)?.trim(),
        (v['catno'] as String?)?.trim(),
        (v['country'] as String?)?.trim(),
        (v['released'] as String?)?.trim(),
      ));
    }
    return out;
  }

  /// Digital first, then CD, then vinyl — the order asked for, with the caveat that made it worth
  /// asking about. Discogs is a collectors' database of physical media: of the 115 versions of
  /// *Discovery*, two are digital and one of those has no year. So a digital pressing only wins
  /// when it is actually documented, and an undocumented one steps aside for the CD.
  static const _formatOrder = ['File', 'CD', 'Vinyl', 'CDr', 'Cassette'];

  static int _formatRank(String major) {
    final i = _formatOrder.indexOf(major);
    return i < 0 ? _formatOrder.length : i;
  }

  static List<DiscogsVersion> orderByPreference(List<DiscogsVersion> all) {
    final out = [...all.where((v) => v.id > 0)];
    out.sort((a, b) {
      // Documented entries first WITHIN a format, but never across one: a documented CD must not
      // jump ahead of a documented digital release.
      final byDoc = (a.isDocumented ? 0 : 1).compareTo(b.isDocumented ? 0 : 1);
      final byFormat = _formatRank(a.major).compareTo(_formatRank(b.major));
      if (a.isDocumented != b.isDocumented && byFormat != 0) {
        // Undocumented digital vs documented CD → the CD, which is the whole point of the rule.
        return a.isDocumented ? -1 : 1;
      }
      if (byFormat != 0) return byFormat;
      if (byDoc != 0) return byDoc;
      // Oldest first: the original pressing describes the record, a 2015 repress describes itself.
      return (a.year ?? 9999).compareTo(b.year ?? 9999);
    });
    return out;
  }

  /// The edition to describe an album with, fully loaded.
  ///
  /// [expectedTracks] is what the library says the album holds; a pressing with far fewer tracks is
  /// a single or a sampler that got filed under the same master, and describing the album with it
  /// would be worse than useless.
  Future<DiscogsEdition?> edition(String artist, String album, {int expectedTracks = 0}) async {
    final master = await masterId(artist, album);
    if (master == null) return null;
    final ordered = orderByPreference(await _versions(master));
    // Only ever fetch a handful in full: each one is a request out of sixty a minute.
    for (final v in ordered.take(4)) {
      final e = await release(v.id);
      if (e == null) continue;
      if (expectedTracks > 0 && e.tracklist.length < expectedTracks - 2) continue;
      return e;
    }
    // Nothing matched the track count — describe it with the best pressing anyway rather than
    // showing an empty page.
    for (final v in ordered.take(2)) {
      final e = await release(v.id);
      if (e != null) return e;
    }
    return null;
  }

  /// One pressing in full: its images, its tracklist, and who made it.
  Future<DiscogsEdition?> release(int id) async {
    final b = await _get('https://api.discogs.com/releases/$id');
    if (b == null) return null;
    final formats = b['formats'] as List<dynamic>? ?? const [];
    final labels = b['labels'] as List<dynamic>? ?? const [];
    final first = labels.isEmpty ? null : labels.first as Map<String, dynamic>?;
    return DiscogsEdition(
      releaseId: id,
      format: formats.isEmpty ? '' : ((formats.first as Map<String, dynamic>)['name'] as String? ?? ''),
      label: (first?['name'] as String?)?.trim(),
      catno: (first?['catno'] as String?)?.trim(),
      country: (b['country'] as String?)?.trim(),
      notes: (b['notes'] as String?)?.trim(),
      year: (b['year'] as num?)?.toInt(),
      genres: [for (final g in (b['genres'] as List<dynamic>? ?? const [])) g.toString()],
      styles: [for (final s in (b['styles'] as List<dynamic>? ?? const [])) s.toString()],
      tracklist: [
        for (final t in (b['tracklist'] as List<dynamic>? ?? const []))
          if (t is Map<String, dynamic> && (t['type_'] == 'track' || t['type_'] == null))
            DiscogsTrack(
              t['position'] as String? ?? '',
              t['title'] as String? ?? '',
              t['duration'] as String? ?? '',
              [
                for (final a in (t['artists'] as List<dynamic>? ?? const []))
                  if (a is Map<String, dynamic>) (a['name'] as String? ?? '')
              ]..removeWhere((s) => s.isEmpty),
            )
      ],
      images: [
        for (final i in (b['images'] as List<dynamic>? ?? const []))
          if (i is Map<String, dynamic>) DiscogsImage.from(i)
      ].whereType<DiscogsImage>().toList(),
    );
  }

  /// Every cover Discogs holds for an album — across all its pressings, not just the one we chose.
  /// This is the pool the user picks their cover from; a Japanese CD often has the best scan.
  Future<List<DiscogsImage>> coverChoices(String artist, String album, {int max = 6}) async {
    final master = await masterId(artist, album);
    if (master == null) return const [];
    final ordered = orderByPreference(await _versions(master));
    final out = <DiscogsImage>[];
    final seen = <String>{};
    for (final v in ordered.take(max)) {
      final e = await release(v.id);
      for (final img in e?.images ?? const <DiscogsImage>[]) {
        if (img.isSquarish && seen.add(img.uri)) out.add(img);
      }
    }
    return out;
  }

  // ── Artists ───────────────────────────────────────────────────────────────

  Future<int?> artistId(String name) async {
    final b = await _get('https://api.discogs.com/database/search?type=artist&q=${_q(name)}');
    final results = b?['results'] as List<dynamic>? ?? const [];
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final title = (r['title'] as String? ?? '').trim().toLowerCase();
      final id = (r['id'] as num?)?.toInt();
      // Exact name first: a search for "Justice" otherwise lands on whoever has the most releases.
      if (id != null && title == name.trim().toLowerCase()) return id;
    }
    final first = results.isEmpty ? null : results.first as Map<String, dynamic>?;
    return (first?['id'] as num?)?.toInt();
  }

  /// What Discogs knows about an act: the write-up, who is in it, and every photo it holds.
  Future<DiscogsArtist?> artist(String name) async {
    final id = await artistId(name);
    if (id == null) return null;
    final b = await _get('https://api.discogs.com/artists/$id');
    if (b == null) return null;
    return DiscogsArtist(
      id: id,
      name: (b['name'] as String?)?.trim() ?? name,
      // Discogs marks up its profiles with [a=Name] and [l=Label] links; readable text wins here.
      profile: _plain((b['profile'] as String?)?.trim() ?? ''),
      members: [
        for (final m in (b['members'] as List<dynamic>? ?? const []))
          if (m is Map<String, dynamic> && (m['name'] as String?) != null) m['name'] as String
      ],
      aliases: [
        for (final a in (b['aliases'] as List<dynamic>? ?? const []))
          if (a is Map<String, dynamic> && (a['name'] as String?) != null) a['name'] as String
      ],
      images: [
        for (final i in (b['images'] as List<dynamic>? ?? const []))
          if (i is Map<String, dynamic>) DiscogsImage.from(i)
      ].whereType<DiscogsImage>().toList(),
    );
  }

  /// Discogs profile markup → plain text. `[a=Thomas Bangalter]` is a link to an artist page;
  /// left as-is it reads like a typo in the middle of a biography.
  static String _plain(String s) => s
      .replaceAllMapped(RegExp(r'\[(?:a|l|m|r)(?:=|\d+\])([^\]]*)\]?'), (m) => m.group(1) ?? '')
      .replaceAll(RegExp(r'\[/?[bius]\]'), '')
      .replaceAll(RegExp(r'\[url=([^\]]*)\]'), '')
      .replaceAll('[/url]', '')
      .trim();
}

class DiscogsArtist {
  final int id;
  final String name, profile;
  final List<String> members, aliases;
  final List<DiscogsImage> images;
  const DiscogsArtist({
    required this.id,
    required this.name,
    this.profile = '',
    this.members = const [],
    this.aliases = const [],
    this.images = const [],
  });

  /// The photos that could serve as a portrait, best first — squarish ones, primary before the
  /// rest. Discogs doesn't label them, so this is a shape heuristic, not a promise.
  List<DiscogsImage> get portraits =>
      [...images.where((i) => !i.isWide)]..sort((a, b) => (b.primary ? 1 : 0).compareTo(a.primary ? 1 : 0));

  /// The ones wide enough to sit behind a page.
  List<DiscogsImage> get backdrops => images.where((i) => i.isWide).toList();
}
