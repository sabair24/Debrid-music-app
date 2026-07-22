import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'organize.dart';
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

  /// When THIS pressing appeared. Not the same thing as when the record did: the digital reissue
  /// of Demon Days is from 2014, the album from 2005.
  final int? year;

  /// When the RECORD came out, from the master. This is the year an album page should lead with —
  /// leading with the pressing's year dated Demon Days to 2014 above a blurb saying 2005.
  final int? albumYear;
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
    this.albumYear,
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
        'albumYear': albumYear,
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
        albumYear: (j['albumYear'] as num?)?.toInt(),
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
  Future<int?> masterId(String artist, String album) async => (await masterIds(artist, album)).firstOrNull;

  /// Candidate masters, most album-like first.
  Future<List<int>> masterIds(String artist, String album) async {
    final title = plainTitle(album);
    final strict =
        await _get('https://api.discogs.com/database/search?type=master&artist=${_q(artist)}&release_title=${_q(title)}');
    final ids = _masters(strict, artist, album);
    if (ids.isNotEmpty) return ids;
    // Titles disagree about "(Deluxe Edition)", "- EP" and the like far more often than they
    // disagree about the words themselves, so fall back to a loose query.
    return _masters(
        await _get("https://api.discogs.com/database/search?type=master&q=${_q("$artist $title")}"), artist, album);
  }

  /// Formats that mean "this master is not the album": a 7" promo of the title track carries the
  /// same artist and title as the record it advertises. Searching for Michael Jackson's *Bad*
  /// returns three masters called exactly that, and the first is a promo flexi-disc with three
  /// pressings — taking it described the album as a Belgian promo single.
  static final _notAnAlbum = RegExp(r'^(promo|sampler|single|ep|flexi-disc|unofficial release|dvd|blu-ray)$',
      caseSensitive: false);

  /// How well a search hit looks like the ALBUM we asked for. Discogs puts "Album" in the format
  /// list of exactly the masters that are one, which makes this cheap and reliable — no extra
  /// request, the answer is already in the search response.
  static int albumScore(List<String> formats) {
    var score = 0;
    for (final f in formats) {
      final t = f.trim();
      if (t.toLowerCase() == 'album') score += 3;
      if (_notAnAlbum.hasMatch(t)) score -= 4;
    }
    return score;
  }

  /// Does a search hit's title actually name the album we asked for?
  ///
  /// Hits come back as "Artist - Title", and searching for *Discovery* returned a Virgin two-disc
  /// bundle scoring well on everything else — it was Human After All. Nothing else caught it,
  /// because a bundle is genuinely an album and genuinely has plausibly many tracks.
  /// An album title with the tags a ripper hung on it stripped off. "Rumours [5.1]" is a folder
  /// name, not a record: Discogs has never heard of it, so nothing matched and the page stayed
  /// blank. What is left is what to search for and what to compare against.
  static String plainTitle(String album) {
    final cut = album.replaceAll(RegExp(r'\s*[\[(][^\])]*[\])]\s*$'), '').trim();
    return cut.isEmpty ? album.trim() : cut;
  }

  static int titleScore(String hitTitle, String artist, String album) {
    var t = hitTitle;
    final dash = t.indexOf(' - ');
    if (dash > 0 && normKey(t.substring(0, dash)) == normKey(artist)) t = t.substring(dash + 3);
    // A slash (or a plus) joins two records into one product. That, not length, is what separates
    // "Human After All / Discovery" from "Discovery (Deluxe Edition)" — the second is this record
    // dressed up, the first is this record bundled with another.
    final bundled = t.contains('/') || RegExp(r'\s\+\s').hasMatch(t);
    final want = normKey(plainTitle(album)), got = normKey(t);
    if (want.isEmpty || got.isEmpty) return 0;
    if (want == got) return 6;
    if (bundled) return -6;
    if (got.startsWith('$want ')) return 4; // (Deluxe Edition), (Remastered), [Bonus Tracks]…
    if (got.contains(want)) return -2;
    return -6;
  }

  /// Every plausible master for this album, best first.
  List<int> _masters(Map<String, dynamic>? body, String artist, String album) {
    final results = body?['results'] as List<dynamic>? ?? const [];
    final scored = <(int, int)>[]; // (id, score)
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      if (r is! Map<String, dynamic>) continue;
      final id = (r['master_id'] as num?)?.toInt() ?? (r['id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      final formats = [for (final f in (r['format'] as List<dynamic>? ?? const [])) f.toString()];
      final s = titleScore(r['title'] as String? ?? '', artist, album) * 10 + albumScore(formats);
      // Discogs' own relevance order breaks ties: it is a better judge than anything here.
      scored.add((id, s * 100 - i));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final s in scored) s.$1];
  }

  /// Pressings of one master, optionally of one format only.
  ///
  /// The format filter is not an optimisation, it is the only way to see a CD of a famous record.
  /// Thriller has hundreds of pressings; asking for a hundred of them sorted by date returns the
  /// 1982-84 vinyl and nothing else, which is how its page came to describe a Costa Rican LP.
  Future<List<DiscogsVersion>> _versions(int master, {String? format}) async {
    final f = format == null ? '' : '&format=${_q(format)}';
    final body = await _get('https://api.discogs.com/masters/$master/versions?per_page=50&sort=released$f');
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

  /// Within a format, a documented pressing beats a stub. Discogs is a collectors' database of
  /// physical media and anyone can add an entry: of the 115 versions of *Discovery*, two are
  /// digital and one of those has no year, no label and no catalogue number. Describing a record
  /// with an entry like that makes the page emptier, which is the opposite of the point.
  /// Does a pressing with [got] tracks hold the record the master says is [want] tracks long?
  ///
  /// Both directions matter, and only one was checked at first. Too few means a single or a sampler
  /// filed under the album's master. Too many means a box set or a two-in-one: searching for
  /// *Discovery* landed on a 30-track double CD that turned out to be Homework as well, and *Bad*
  /// on a 32-track anniversary edition. Bonus tracks are normal, a second album is not.
  ///
  /// [want] is the MASTER's own tracklist, never the library's. Measuring against what is owned was
  /// wrong in the ordinary case: four tracks of Demon Days are still Demon Days, and every real
  /// fifteen-track pressing of it got rejected for being too long.
  static bool fitsTrackCount(int got, int want) => got >= want - 2 && got <= want * 1.5 + 3;

  /// CD before digital, then vinyl. Digital came first at the start, and on the metadata it made no
  /// difference — the year, the genres and the label all come from the master either way. What it
  /// cost was the edition line: digital entries almost never carry a catalogue number or a country,
  /// so Bad went from "cd · EPC 450290 2 · Switzerland" to "digitaal · 2012". The CD pressing is
  /// simply the better-documented object, which is the whole reason to name an edition at all.
  static const _formatOrder = ['CD', 'File', 'Vinyl', 'CDr', 'Cassette'];

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
    final masters = await masterIds(artist, album);
    if (masters.isEmpty) return null;
    DiscogsEdition? fallback;
    for (final master in masters.take(3)) {
      // The master's own tracklist is what a pressing is measured against. One extra request, and
      // it is the difference between describing Demon Days and describing whatever came first.
      final m = await _get('https://api.discogs.com/masters/$master');
      final masterTracks = (m?['tracklist'] as List<dynamic>?)?.length ?? 0;
      final masterYear = (m?['year'] as num?)?.toInt();
      // The record has to be able to hold what the library has of it: owning eleven tracks rules
      // out a master that is a two-track promo, however well it scored on name and format.
      if (expectedTracks > 0 && masterTracks > 0 && masterTracks < expectedTracks - 2) continue;
      // Ask per format, in the order asked for, and stop at the first that delivers. This is what
      // makes "digital, else CD, else vinyl" true for a record with hundreds of pressings.
      for (final format in _formatOrder) {
        final ordered = orderByPreference(await _versions(master, format: format));
        if (ordered.isEmpty) continue;
        // Only ever fetch a handful in full: each one is a request out of sixty a minute.
        for (final v in ordered.take(3)) {
          final e = await release(v.id, albumYear: masterYear);
          if (e == null) continue;
          fallback ??= e;
          if (masterTracks > 0 && !fitsTrackCount(e.tracklist.length, masterTracks)) continue;
          if (!v.isDocumented && format != _formatOrder.last) break; // undocumented → try the next format
          return e;
        }
      }
    }
    // No pressing anywhere matched the track count. Better to describe it with the closest thing
    // found than to leave the page empty.
    return fallback;
  }

  /// One pressing in full: its images, its tracklist, and who made it.
  Future<DiscogsEdition?> release(int id, {int? albumYear}) async {
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
      albumYear: albumYear,
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
