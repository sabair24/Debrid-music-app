import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'artwork.dart';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart';
import 'discography.dart';
import 'editions.dart';
// Mutual with enrichment.dart, which delegates its cover search here. Deliberate: TheAudioDB's album
// entry holds the back cover and the disc, CoverEnricher.albumInfo already fetches and CACHES that
// entry for the page's blurb, and reading it here reuses that one request instead of asking the same
// endpoint a second time per album. Dart resolves import cycles between libraries without complaint.
import 'enrichment.dart';
import 'musicbrainz.dart';
import 'organize.dart';
import 'release_format.dart';
import 'release_format.dart' as fmt;
import 'settings.dart';
import 'paths.dart';

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

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'thumb': thumb,
    'width': width,
    'height': height,
    'primary': primary,
  };
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

  Map<String, dynamic> toJson() => {
    'position': position,
    'title': title,
    'duration': duration,
    'artists': artists,
  };
  static DiscogsTrack fromJson(Map<String, dynamic> j) => DiscogsTrack(
    j['position'] as String? ?? '',
    j['title'] as String? ?? '',
    j['duration'] as String? ?? '',
    [for (final a in (j['artists'] as List<dynamic>? ?? const [])) a.toString()],
  );
}

/// One pressing of an album, with everything the library page shows about it.
/// Wat één zoeksweep over de masters van een artiest opleverde.
///
/// Twee tabellen en geen rijen: deze sweep VULT bestaande regels aan en voegt er nooit een toe. Dat
/// onderscheid is met opzet — de zoek-endpoint kent ook persingen en heruitgaves die in een
/// discografie niets te zoeken hebben, en een lijst die van vullen naar aanvullen verschuift is niet
/// meer te verantwoorden aan wie hem leest.
class DiscogsSweep {
  /// Discogs-master-id → zijn formaat als tekst, bijvoorbeeld "Vinyl, LP, Album".
  final Map<int, String> formaatPerMaster;

  /// [discoKey] van de titel → miniatuurhoes. Op sleutel en niet op id, want de regels die een hoes
  /// missen komen van MusicBrainz en dragen geen Discogs-id.
  final Map<String, String> hoesPerSleutel;

  const DiscogsSweep(this.formaatPerMaster, this.hoesPerSleutel);

  bool get isLeeg => formaatPerMaster.isEmpty && hoesPerSleutel.isEmpty;
}

class DiscogsEdition {
  final int releaseId;
  final String format; // File / CD / Vinyl / Cassette …
  final String? label, catno, country, notes;

  /// The barcode printed on the case, from Discogs' identifiers.
  ///
  /// Worth carrying because it names the physical product rather than a database row: it is
  /// the one field that matches this exact pressing against another catalogue without
  /// guessing. booklet.dart uses it to find the same record in MusicBrainz.
  final String? barcode;

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
    this.barcode,
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
    'barcode': barcode,
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
    barcode: j['barcode'] as String?,
    year: (j['year'] as num?)?.toInt(),
    albumYear: (j['albumYear'] as num?)?.toInt(),
    genres: [for (final g in (j['genres'] as List<dynamic>? ?? const [])) g.toString()],
    styles: [for (final s in (j['styles'] as List<dynamic>? ?? const [])) s.toString()],
    tracklist: [
      for (final t in (j['tracklist'] as List<dynamic>? ?? const []))
        if (t is Map<String, dynamic>) DiscogsTrack.fromJson(t),
    ],
    images: [
      for (final i in (j['images'] as List<dynamic>? ?? const []))
        if (i is Map<String, dynamic>) DiscogsImage.fromJson(i),
    ],
  );
}

/// A version as it appears in a master's version list — cheap to get, one line each, and enough
/// to choose between them without fetching all 115 of them.
class DiscogsVersion {
  final int id;
  final String format, major;
  final String? label, catno, country, released;

  /// The front cover, already in the versions listing — so a whole master's worth of pressings can
  /// be shown with their sleeves off ONE request, without a lookup each.
  final String? thumb;
  const DiscogsVersion(
    this.id,
    this.format,
    this.major,
    this.label,
    this.catno,
    this.country,
    this.released, [
    this.thumb,
  ]);

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

/// Waar een ingetypt Discogs-nummer naar wijst: één persing, of een heel master.
///
/// Het verschil is niet academisch. `[r7738290]` is de promo-cd van Te Quiero — één rij. `[m1938390]`
/// is het master waar die persing onder hangt en levert er tientallen. Discogs schrijft ze zelf met
/// die letters ervoor, en de kiezer mag ze allebei aannemen.
enum DiscogsSoort { release, master }

class DiscogsVerwijzing {
  final DiscogsSoort soort;
  final int id;
  const DiscogsVerwijzing(this.soort, this.id);

  bool get isMaster => soort == DiscogsSoort.master;

  /// Wat de gebruiker ook plakt, hier komt een nummer uit — of niets.
  ///
  /// **Waarom dit een eigen functie is en geen `int.tryParse` in de dialoog.** Er zijn zes vormen
  /// waarin ditzelfde nummer op een scherm staat, en ze komen allemaal langs: het kale getal onder
  /// aan de releasepagina, dezelfde regel met `[r…]` eromheen zoals Discogs hem in verwijzingen
  /// schrijft, de gedeelde link, diezelfde link met een taalcode erin (`/fr/release/…`, `/nl/…` —
  /// wat je krijgt als je niet in het Engels bladert), de titel-slug erachter, en de api-vorm met
  /// `releases` in het meervoud. Eén ervan niet aannemen betekent dat iemand die de link deelt te
  /// horen krijgt dat zijn nummer niet bestaat, terwijl het er gewoon staat.
  static DiscogsVerwijzing? ontleed(String invoer) {
    final t = invoer.trim();
    if (t.isEmpty) return null;

    DiscogsVerwijzing? maak(String soort, String cijfers) {
      final id = int.tryParse(cijfers);
      if (id == null || id <= 0) return null;
      final m = soort.toLowerCase().startsWith('m');
      return DiscogsVerwijzing(m ? DiscogsSoort.master : DiscogsSoort.release, id);
    }

    // Een link. `[^\s]*?` vangt de taalcode die Discogs ertussen zet zodra je niet in het Engels
    // bladert; `s?` vangt de api-vorm (releases/masters) die in meervoud staat.
    final link = RegExp(r'discogs\.com/[^\s]*?/?(release|master)s?/(\d+)', caseSensitive: false)
        .firstMatch(t);
    if (link != null) return maak(link.group(1)!, link.group(2)!);

    // Discogs' eigen schrijfwijze, met of zonder haken.
    final code = RegExp(r'^\[?([rm])(\d+)\]?$', caseSensitive: false).firstMatch(t);
    if (code != null) return maak(code.group(1)!, code.group(2)!);

    // Een kaal nummer is een UITGAVE. Dat is het nummer dat op de pagina van één persing staat en
    // dat is waar iemand mee hier komt; een master noem je met de `m` ervoor of met zijn link.
    //
    // Alleen cijfers, en niets erachter. Hier stond dat "7738290-Stromae-Te-Quiero" ook mocht,
    // omdat dat is wat je overhoudt als je de slug uit een link kopieert. Dat is waar, maar
    // "1938390-Stromae-Racine-Carree" komt uit een MASTER-link en ziet er precies hetzelfde uit —
    // en master- en uitgavenummers lopen door elkaar heen in hetzelfde bereik. Die vorm aannemen
    // betekent dat een masterslug een wildvreemde persing ophaalt en die bovenaan zet als "degene
    // die je vroeg". Plak de hele link, dan staat er wél in wat het is.
    final kaal = RegExp(r'^\d+$').firstMatch(t);
    if (kaal != null) return maak('r', kaal.group(0)!);
    return null;
  }

  @override
  String toString() => '${isMaster ? 'm' : 'r'}$id';
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
  //
  // STATIC, and that is the whole point. The budget belongs to the token, and there is one token;
  // but this service is constructed fresh at fourteen call sites, so as instance fields these gave
  // every caller its own private idea of the limit. Opening one album page starts three of them at
  // once — the sleeve, the info panel and the credits — each politely spacing ITS requests 1.1 s
  // apart while collectively firing three times the allowance. Sharing the lane is what makes the
  // spacing mean anything.
  static const _minGap = Duration(milliseconds: 1100);
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _turn = Future.value();
  static int _remaining = 60;

  /// Somewhere to write what the rate-limit lane is doing. Set once by the warmer.
  ///
  /// The last blind spot in this chain. warm.log could show that a record reached "naar Discogs" in
  /// 142 ms and then produced nothing for ten minutes, and no more: the wait is inside [_get], behind
  /// a queue that nothing reported on. Meanwhile the Discogs cache directory had not gained a file in
  /// over ten minutes, so not one request was completing — but whether that was a long queue, a stuck
  /// chain or no requests at all could not be told apart from the outside.
  static void Function(String)? laneTrace;

  /// How many requests are waiting for a slot right now.
  static int _queued = 0;

  /// Starts every call at least [_minGap] after the last one. Returns null on any failure — a missing
  /// album page is a disappointment, a crashed one is a bug.
  Future<Map<String, dynamic>?> _get(String url) async {
    if (!available) return null;
    final cached = await _readCache(url);
    if (cached != null) return cached;

    // The lane hands out a START SLOT; it does not hold the request. Sixty a minute is a budget of
    // requests SENT, so spacing the sends is what honours it — waiting for each response before
    // sending the next only made the app slower without asking Discogs for anything less.
    final slot = _turn.then((_) async {
      final since = DateTime.now().difference(_lastCall);
      // Below a fifth of the budget, ease off hard: something else (a background sweep) is
      // eating it, and a 429 costs more than waiting.
      final gap = _remaining < 12 ? _minGap * 3 : _minGap;
      // Never longer than the gap itself — see the note on MusicBrainzService.laneSlot. A clock that
      // steps backwards makes `since` negative, and `gap - since` then swallows the whole jump.
      final wacht = since.isNegative || since > gap ? Duration.zero : gap - since;
      if (wacht > Duration.zero) await Future<void>.delayed(wacht);
      _lastCall = DateTime.now();
    });
    // The chain must survive a failed turn, or one thrown error deadlocks the lane for the session.
    _turn = slot.catchError((_) {});
    final queuedAt = DateTime.now();
    _queued++;
    // A slot that never arrives has to say so ITSELF — the line below only prints once the wait is
    // over, so a lane that hangs prints nothing at all. MusicBrainz got this first and its silence
    // is what ruled that side out; this side had no such proof.
    var binnen = false;
    unawaited(Future<void>.delayed(const Duration(seconds: 5)).then((_) {
      if (binnen) return;
      laneTrace?.call('  [discogs] WACHT AL 5s op een slot voor ${Uri.parse(url).path} '
          '(nog $_queued in de rij, budget $_remaining)');
    }));
    try {
      await slot;
      binnen = true;
      final wachtte = DateTime.now().difference(queuedAt);
      _queued--;
      // Only when it actually cost something. A lane that hands out slots promptly says nothing.
      if (wachtte.inMilliseconds > 1500) {
        laneTrace?.call('  [discogs] ${wachtte.inSeconds}s in de rij (nog $_queued wachtend, '
            'budget $_remaining) voor ${Uri.parse(url).path}');
      }
      final r = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': _ua,
              'Authorization': 'Discogs token=${settings.discogsToken.trim()}',
            },
          )
          .timeout(const Duration(seconds: 12));
      final left = int.tryParse(r.headers['x-discogs-ratelimit-remaining'] ?? '');
      // Responses can now land out of order, so a stale header must not raise the budget back up:
      // the lowest number seen is the honest one until a request actually reports more room.
      if (left != null && (left < _remaining || left > _remaining + 5)) _remaining = left;
      if (r.statusCode != 200) {
        // 404 is an answer: Discogs does not have this release. Anything else — 429, 5xx — means we
        // did not get to ask properly, which is a different thing entirely. See [transportErrors].
        if (r.statusCode != 404) transportErrors++;
        return null;
      }
      final body = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (body is! Map<String, dynamic>) {
        transportErrors++;
        return null;
      }
      await _writeCache(url, body);
      return body;
    } catch (e) {
      transportErrors++;
      laneTrace?.call('  [discogs] ${Uri.parse(url).path} brak: $e');
      return null;
    }
  }

  /// Requests that came back without a usable answer for a reason other than "this does not exist".
  ///
  /// Same purpose as [MusicBrainzService.transportErrors], and needed for the same reason: [_get]
  /// turns a timeout, a rate-limit refusal and a 5xx into the same `null` that a genuine 404 gives,
  /// so nothing downstream can tell a broken network from an unknown record without this.
  ///
  /// Static because DiscogsService is constructed fresh at fourteen call sites — an instance field
  /// would give every caller its own private count of a problem that is global.
  static int transportErrors = 0;

  // ── Cache ─────────────────────────────────────────────────────────────────
  // Discogs data barely changes and the rate limit is the scarce resource, so anything fetched is
  // kept. The whole library can then be browsed offline once it has been enriched.
  String get _dir => '$appDir${Platform.pathSeparator}discogs';

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
    } catch (_) {
      /* a cache that can't be written is not a reason to fail the call */
    }
  }

  String _q(String s) => Uri.encodeQueryComponent(s);

  // ── Albums ────────────────────────────────────────────────────────────────

  /// The master id for an album, or null. A master groups every pressing of one record, which is
  /// what makes "which edition do we describe?" a question we can answer at all.
  Future<int?> masterId(String artist, String album) async =>
      (await masterIds(artist, album)).firstOrNull;

  /// A cover image URL straight out of a release search — the cheapest thing Discogs will give.
  ///
  /// Lives here, and not in the cover enricher that wants it, for the reason the rate-limit comment
  /// at the top of this file spells out: the budget belongs to the token, and there is one token. The
  /// enricher was calling api.discogs.com with a bare `http.get`, so those requests were invisible to
  /// this lane and to this cache — two independent ideas of "sixty a minute" on one allowance, and
  /// nothing remembered between starts. Six albums enriched at once made that a burst.
  ///
  /// One request in the common case, two when the strict query finds nothing, both cached on disk.
  Future<String?> coverFromSearch(String artist, String album, {bool generic = false}) async {
    String? pick(Map<String, dynamic>? body) {
      for (final it in (body?['results'] as List?) ?? const []) {
        if (it is! Map) continue;
        final ci = (it['cover_image'] ?? it['thumb']) as String?;
        // Discogs serves a transparent spacer where a release has no image at all.
        if (ci != null && ci.isNotEmpty && !ci.contains('spacer')) return ci;
      }
      return null;
    }

    final who = cleanArtistName(artist);
    final strict = StringBuffer(
        'https://api.discogs.com/database/search?type=release&release_title=${_q(album)}');
    if (!generic && who.isNotEmpty) strict.write('&artist=${_q(who)}');
    final first = pick(await _get(strict.toString()));
    if (first != null) return first;
    final q = generic || who.isEmpty ? album : '$who $album';
    return pick(await _get('https://api.discogs.com/database/search?type=release&q=${_q(q)}'));
  }

  /// Candidate masters, most album-like first.
  Future<List<int>> masterIds(String artist, String album) async {
    final title = plainTitle(album);
    // A Discogs disambiguation suffix in the library ("Adele (3)") finds nothing on Discogs, and
    // the loose fallback then matched a Quebec country album called "30 ans de succès".
    final who = cleanArtistName(artist);
    final strict = await _get(
      'https://api.discogs.com/database/search?type=master&artist=${_q(who)}&release_title=${_q(title)}',
    );
    final ids = _masters(strict, who, album);
    if (ids.isNotEmpty) return ids;
    // Titles disagree about "(Deluxe Edition)", "- EP" and the like far more often than they
    // disagree about the words themselves, so fall back to a loose query.
    return _masters(
      await _get("https://api.discogs.com/database/search?type=master&q=${_q("$who $title")}"),
      who,
      album,
    );
  }

  /// Formats that mean "this master is not the album": a 7" promo of the title track carries the
  /// same artist and title as the record it advertises. Searching for Michael Jackson's *Bad*
  /// returns three masters called exactly that, and the first is a promo flexi-disc with three
  /// pressings — taking it described the album as a Belgian promo single.
  /// Public so the artwork extension can apply the same rule; it is one judgement, not two.
  static final notAnAlbum = RegExp(
    r'^(promo|sampler|single|ep|flexi-disc|unofficial release|dvd|blu-ray)$',
    caseSensitive: false,
  );

  /// How well a search hit looks like the ALBUM we asked for. Discogs puts "Album" in the format
  /// list of exactly the masters that are one, which makes this cheap and reliable — no extra
  /// request, the answer is already in the search response.
  static int albumScore(List<String> formats) {
    var score = 0;
    for (final f in formats) {
      final t = f.trim();
      if (t.toLowerCase() == 'album') score += 3;
      if (notAnAlbum.hasMatch(t)) score -= 4;
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

  /// Words that dress up a title without changing which record it names.
  static final _editionWord = RegExp(
    r'^(deluxe|super|edition|remaster|remastered|remaster\w*|anniversary|expanded|special|bonus|'
    r'tracks?|track|disc|version|reissue|limited|collectors?|collector|the|and|ep|lp|mix|'
    r'stereo|mono|explicit|clean|\d{4}|\d{1,2}(st|nd|rd|th))$',
  );

  static bool _onlyEditionWords(String tail) {
    final words = tail.split(' ').where((w) => w.isNotEmpty);
    return words.isNotEmpty && words.every(_editionWord.hasMatch);
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
    // Anything after the title has to be an edition tag, not more title. Adele's *30* matched
    // "30 ans de succès" by a Quebec country group, and the album page became theirs — cover,
    // credits, catalogue number and all. A short title makes that trap wide open.
    if (got.startsWith('$want ') && _onlyEditionWords(got.substring(want.length + 1))) return 4;
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
  /// Public wrapper, so the picker extension can list pressings per format.
  Future<List<DiscogsVersion>> versionsOf(
    int master, {
    String? format,
    int maxPaginas = 1,
    void Function(List<DiscogsVersion>)? perPagina,
    bool Function()? stop,
    void Function(int totaal, bool meer)? onEinde,
  }) =>
      _versions(master,
          format: format,
          maxPaginas: maxPaginas,
          perPagina: perPagina,
          stop: stop,
          onEinde: onEinde);

  /// Honderd, het maximum dat Discogs toestaat, en alleen voor wie écht alles wil.
  ///
  /// **Waarom de eerste-pagina-oproepen hun oude adres houden.** Honderd halen kost hetzelfde als
  /// vijftig — het budget is zestig REQUESTS per minuut, niet zestig regels — dus overal honderd
  /// vragen lijkt gratis winst. Dat is het niet: het adres ís de cachesleutel. Elke versielijst die
  /// ooit is opgehaald zou in één klap waardeloos worden, en de achtergrondwarmer haalt er vijf per
  /// album op. Op een bibliotheek van een paar honderd platen zijn dat duizenden requests opnieuw,
  /// op precies de baan waar de warmer albums voor een hele sessie overslaat als hij zijn deadline
  /// niet haalt.
  ///
  /// Dus: wie één pagina vraagt (de warmer, de hoeszoeker, het bepalen van de uitgave — allemaal op
  /// zoek naar de BESTE persing, niet naar alle) krijgt letterlijk het oude adres terug en dus zijn
  /// cache. Alleen de kiezer, die om alles vraagt, gebruikt de gepagineerde vorm.
  static const _perPagina = 100;

  /// Hoeveel pagina's dit antwoord zegt te hebben.
  ///
  /// Ontbreekt het blok — een oude cache, een uitgekleed antwoord — dan is het antwoord één, en
  /// niet nul: nul zou de lus laten denken dat er niets is terwijl er net een pagina binnenkwam.
  static int paginaAantal(Map<String, dynamic>? body) {
    final n = _getal(body, 'pages') ?? 1;
    return n < 1 ? 1 : n;
  }

  /// Hoeveel uitgaves dit master er in totaal heeft, volgens Discogs zelf. Null als het niet staat.
  static int? itemAantal(Map<String, dynamic>? body) => _getal(body, 'items');

  /// Een jaartal uit een zoekresultaat, zonder cast die kan gooien.
  ///
  /// Discogs stuurt dit vandaag als tekst ("2010"), maar `as String?` GOOIT op alles wat geen tekst
  /// is in plaats van null te geven — en die fout valt tot in de dialoog, die er "Discogs was niet
  /// bereikbaar" van maakt boven een lijst die keurig was aangekomen. Zelfde val als bij het
  /// pagineringsblok hierboven, en dezelfde oplossing.
  static int? jaarUit(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim().split('-').first);
    return null;
  }

  /// Een getal uit het pagineringsblok, zonder cast die kan gooien.
  ///
  /// `as num?` gooit op een tekst — het levert geen null op — en deze functies bestaan juist om een
  /// uitgekleed of afwijkend antwoord te overleven. Gooien ze wél, dan valt die fout tot in
  /// `_load`, die er "Discogs was niet bereikbaar" van maakt terwijl er net een pagina met uitgaves
  /// binnenkwam.
  static int? _getal(Map<String, dynamic>? body, String sleutel) {
    final p = body?['pagination'];
    if (p is! Map) return null;
    final v = p[sleutel];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static List<DiscogsVersion> _lezVersies(Map<String, dynamic>? body) {
    final list = body?['versions'] as List<dynamic>? ?? const [];
    final out = <DiscogsVersion>[];
    for (final v in list) {
      if (v is! Map<String, dynamic>) continue;
      final majors = [
        for (final m in (v['major_formats'] as List<dynamic>? ?? const [])) m.toString(),
      ];
      out.add(
        DiscogsVersion(
          (v['id'] as num?)?.toInt() ?? 0,
          v['format'] as String? ?? '',
          majors.isEmpty ? '' : majors.first,
          (v['label'] as String?)?.trim(),
          (v['catno'] as String?)?.trim(),
          (v['country'] as String?)?.trim(),
          (v['released'] as String?)?.trim(),
          (v['thumb'] as String?)?.trim(),
        ),
      );
    }
    return out;
  }

  /// [maxPaginas] is standaard 1, en dat is met opzet: elke pagina is een request uit een budget
  /// van zestig per minuut. De automatische paden (hoes zoeken, uitgave bepalen) hebben aan de
  /// eerste pagina genoeg — ze zoeken de BESTE pressing, niet alle. Alleen de kiezer, waar de
  /// gebruiker om álles vraagt, zet hem hoger en krijgt elke pagina meteen te zien via [perPagina].
  Future<List<DiscogsVersion>> _versions(
    int master, {
    String? format,
    int maxPaginas = 1,
    void Function(List<DiscogsVersion>)? perPagina,
    bool Function()? stop,
    void Function(int totaal, bool meer)? onEinde,
  }) async {
    final f = format == null ? '' : '&format=${_q(format)}';
    final out = <DiscogsVersion>[];
    var totaal = 0;
    var meer = false;
    for (var pagina = 1; pagina <= maxPaginas; pagina++) {
      // De aanroeper heeft genoeg. Doorgaan zou requests kosten uit een budget van zestig per
      // minuut voor rijen die toch niet meer in de lijst passen.
      if (stop != null && stop()) {
        meer = true;
        break;
      }
      final body = await _get(
        // Letterlijk het oude adres zodra er één pagina gevraagd wordt — zie [_perPagina]. Een
        // andere query is een andere cachesleutel, en die cache is hier het halve verhaal.
        maxPaginas <= 1
            ? 'https://api.discogs.com/masters/$master/versions?per_page=50&sort=released$f'
            : 'https://api.discogs.com/masters/$master/versions'
                '?per_page=$_perPagina&page=$pagina&sort=released$f',
      );
      // Geen antwoord: teruggeven wat er wél is. Een halve lijst is meer dan een lege, en de
      // volgende pagina opvragen na een 429 maakt die 429 alleen maar langer. Wel `meer`, want er
      // ís meer — we konden er alleen niet bij, en dat mag niet als "dit was alles" doorgaan.
      if (body == null) {
        meer = pagina > 1 || out.isNotEmpty;
        break;
      }
      if (pagina == 1) totaal = itemAantal(body) ?? 0;
      final gelezen = _lezVersies(body);
      out.addAll(gelezen);
      if (gelezen.isNotEmpty) perPagina?.call(gelezen);
      if (pagina >= paginaAantal(body)) break;
      // Laatste ronde en er staat nog een pagina open.
      if (pagina == maxPaginas) meer = true;
    }
    onEinde?.call(totaal, meer);
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
  ///
  /// De formule zelf staat in release_format.dart, waar MusicBrainz hem ook uit leest.
  static bool fitsTrackCount(int got, int want) => fmt.fitsTrackCount(got, want);

  /// CD first, digital last — the shared preference in [releaseFormatOrder]. It lives outside this
  /// class because MusicBrainz ranks the same records by the same rule, and two copies of a rule
  /// this hard-won would eventually disagree.
  static int _formatRank(String major) => releaseFormatRank(major);

  static List<DiscogsVersion> orderByPreference(List<DiscogsVersion> all, {int main = 0}) {
    final out = [...all.where((v) => v.id > 0)];
    out.sort((a, b) {
      // The master's own main release, when it happens to be of this format, is the canonical copy.
      if (main > 0 && (a.id == main) != (b.id == main)) return a.id == main ? -1 : 1;
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
  /// Which pressing this record is, according to Discogs.
  ///
  /// One question at a time per record, like [DiscogsArtwork.releaseArt] already did. The album page
  /// asks for the edition and for the artwork at the same moment now, and the artwork chain resolves
  /// the edition itself — so without this the page would run that whole search twice at once, and
  /// each run is a handful of requests out of sixty a minute.
  Future<DiscogsEdition?> edition(
    String artist,
    String album, {
    int expectedTracks = 0,
    int? pinned,
  }) {
    final key = '${normKey(artist)}|${normKey(album)}|$expectedTracks|${pinned ?? 0}';
    final running = _editionInFlight[key];
    if (running != null) {
      // Joining a chain that is ALREADY hung means hanging with it, silently and forever. Worth
      // saying out loud: an abandoned lookup keeps running (a Dart timeout does not cancel), so this
      // table can hand out a future that will never complete.
      laneTrace?.call('  [discogs] sluit aan bij een lopende uitgave-zoektocht voor $key');
      return running;
    }
    // A BLOCK body, and that is the whole bug fixed.
    //
    // `() => _editionInFlight.remove(key)` is an arrow, so it RETURNS what remove() returns — and on
    // a Map<String, Future<…>> that is the removed Future. whenComplete's contract is explicit: if
    // the callback returns a future, the result does not complete until that future does. The value
    // just removed is `work` itself, so work waited for work. Forever.
    //
    // No socket, no CPU, no queue, no log line: exactly the shape of a record that sat in the facts
    // sweep for three-quarters of an hour. Only records MusicBrainz cannot answer ever reach this
    // line, which is why the library looked healthy — and why the Discogs backfill never finished a
    // single record across six rewrites. It was calling this.
    final work = _editionFresh(artist, album, expectedTracks, pinned).whenComplete(() {
      _editionInFlight.remove(key);
    });
    _editionInFlight[key] = work;
    return work;
  }

  static final _editionInFlight = <String, Future<DiscogsEdition?>>{};

  Future<DiscogsEdition?> _editionFresh(
    String artist,
    String album,
    int expectedTracks,
    int? pinned,
  ) async {
    final t0 = DateTime.now();
    void stap(String s) =>
        laneTrace?.call('    [uitgave +${DateTime.now().difference(t0).inMilliseconds}ms] $s');
    stap('begin "$artist" / "$album" (aantal=$expectedTracks pin=${pinned ?? "-"})');

    // A release the user pointed at is not a candidate to be weighed against the others — it is the
    // answer. Everything the page shows is read from it.
    if (pinned != null && pinned > 0) {
      final picked = await release(pinned);
      stap('gepinde uitgave: ${picked == null ? "niets" : "gevonden"}');
      if (picked != null) return picked;
    }
    final masters = await masterIds(artist, album);
    stap('masters: ${masters.length}');
    if (masters.isEmpty) return null;
    DiscogsEdition? fallback;
    for (final master in masters.take(3)) {
      // The master's own tracklist is what a pressing is measured against. One extra request, and
      // it is the difference between describing Demon Days and describing whatever came first.
      final m = await _get('https://api.discogs.com/masters/$master');
      final masterTracks = (m?['tracklist'] as List<dynamic>?)?.length ?? 0;
      final masterYear = (m?['year'] as num?)?.toInt();
      // Discogs names one pressing per master as the main one. Among equally documented pressings
      // of the same year that is a far better tiebreak than list order, which put Dangerous on a
      // Taiwanese CD when a US one was sitting right beside it.
      final main = (m?['main_release'] as num?)?.toInt() ?? 0;
      // The record has to be able to hold what the library has of it: owning eleven tracks rules
      // out a master that is a two-track promo, however well it scored on name and format.
      if (expectedTracks > 0 && masterTracks > 0 && masterTracks < expectedTracks - 2) continue;
      // Ask per format, in the order asked for, and stop at the first that delivers. This is what
      // makes "digital, else CD, else vinyl" true for a record with hundreds of pressings.
      for (final format in releaseFormatOrder) {
        final ordered = orderByPreference(await _versions(master, format: format), main: main);
        stap('  master $master, formaat $format: ${ordered.length} persingen');
        if (ordered.isEmpty) continue;
        // Only ever fetch a handful in full: each one is a request out of sixty a minute.
        for (final v in ordered.take(3)) {
          final e = await release(v.id, albumYear: masterYear);
          if (e == null) continue;
          fallback ??= e;
          if (masterTracks > 0 && !fitsTrackCount(e.tracklist.length, masterTracks)) continue;
          if (!v.isDocumented && format != releaseFormatOrder.last)
            break; // undocumented → try the next format
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
      format: formats.isEmpty
          ? ''
          : ((formats.first as Map<String, dynamic>)['name'] as String? ?? ''),
      label: (first?['name'] as String?)?.trim(),
      catno: (first?['catno'] as String?)?.trim(),
      country: (b['country'] as String?)?.trim(),
      notes: (b['notes'] as String?)?.trim(),
      // Discogs lists the barcode among free-form identifiers, often with spaces or a
      // "scanned"/"text" qualifier. Keep the digits only, so it can be matched elsewhere.
      barcode: () {
        for (final i in (b['identifiers'] as List<dynamic>? ?? const [])) {
          if (i is! Map<String, dynamic>) continue;
          if ((i['type'] as String?)?.toLowerCase() != 'barcode') continue;
          final digits = (i['value'] as String? ?? '').replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.length >= 8) return digits;
        }
        return null;
      }(),
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
                  if (a is Map<String, dynamic>) (a['name'] as String? ?? ''),
              ]..removeWhere((s) => s.isEmpty),
            ),
      ],
      images: [
        for (final i in (b['images'] as List<dynamic>? ?? const []))
          if (i is Map<String, dynamic>) DiscogsImage.from(i),
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

  /// Wat de zoek-endpoint over de masters van deze artiest zegt: formaat en miniatuurhoes.
  ///
  /// Bestaat omdat `/artists/{id}/releases` voor een `type: master` GEEN `format`-veld levert — alleen
  /// id, titel, `main_release`, jaar en hoes. GEMETEN op Sia: 95 van haar 162 eigen regels zijn zo'n
  /// master, en die belandden allemaal in het blok "Overig" omdat [kindFromDiscogs] een lege string
  /// kreeg. Een vijfde van de discografie ongesorteerd.
  ///
  /// De zoek-endpoint zet het formaat er wél bij, honderd masters per verzoek. Dat is dezelfde
  /// eigenschap waar [albumScore] al op leunt — "Discogs puts 'Album' in the format list of exactly
  /// the masters that are one" — nu voor de hele discografie in plaats van één plaat.
  ///
  /// De prijs is het hele punt. Per regel de hoofdpersing opvragen zou voor Sia 95 verzoeken kosten op
  /// een baan van zestig per minuut; dit kost er twee. GEMETEN: dekking 92 van 95, en op een
  /// steekproef van twaalf gaf het twaalf keer hetzelfde antwoord als het echte formaat van de
  /// hoofdpersing.
  ///
  /// De hoes komt gratis mee en dicht een tweede gat: MusicBrainz levert op releasegroep-niveau nooit
  /// een hoes, en de Cover Art Archive ook niet (gemeten: 0 van 25 Céline-verzamelaars). Voor een
  /// grote catalogus ziet deze sweep bovendien masters die buiten de twee pagina's van
  /// [artistReleases] vallen — daar zitten juist de oude verzamelaars zonder hoes.
  Future<DiscogsSweep> artistSweep(int artistId, {int pages = 3}) async {
    final perMaster = <int, String>{};
    final hoesPerSleutel = <String, String>{};
    for (var p = 1; p <= pages; p++) {
      final b = await _get('https://api.discogs.com/database/search'
          '?artist_id=$artistId&type=master&per_page=100&page=$p');
      final rijen = b?['results'] as List<dynamic>? ?? const [];
      if (rijen.isEmpty) break;
      for (final r in rijen) {
        if (r is! Map<String, dynamic>) continue;
        final mid = (r['id'] as num?)?.toInt();
        final formaat = (r['format'] as List<dynamic>? ?? const []).join(', ');
        if (mid != null && formaat.isNotEmpty) perMaster[mid] = formaat;

        // De zoekopdracht schrijft "Céline Dion - The French Collection II"; alleen de titel is de
        // sleutel waarop de rest van de discografie vergelijkt.
        var titel = (r['title'] as String? ?? '').trim();
        final streep = titel.indexOf(' - ');
        if (streep > 0) titel = titel.substring(streep + 3).trim();
        final thumb = (r['thumb'] as String? ?? '').trim();
        if (titel.isNotEmpty && thumb.isNotEmpty && !thumb.contains('spacer')) {
          hoesPerSleutel.putIfAbsent(discoKey(titel), () => thumb);
        }
      }
      final totaal = (b?['pagination'] as Map<String, dynamic>?)?['pages'] as num?;
      if (totaal == null || p >= totaal.toInt()) break;
    }
    return DiscogsSweep(perMaster, hoesPerSleutel);
  }

  /// Alles wat deze artiest zelf uitbracht, voor de discografie.
  ///
  /// Het enige endpoint dat hier ontbrak. Discogs weet dingen die Deezer noch MusicBrainz weet — het
  /// formaat, en gratis een miniatuurhoes — en die hoes is de goedkoopste die er is: MusicBrainz heeft
  /// er op dit niveau geen, en er per plaat een ophalen kost een verzoek op een baan van 1100 ms.
  ///
  /// `role == 'Main'` is de belangrijkste regel van dit endpoint. Zonder dat filter levert de pagina
  /// van een gevraagde producer of sessiemuzikant honderden platen van anderen op, en dan is het geen
  /// discografie meer maar een cv.
  ///
  /// Hard begrensd op twee pagina's. `pagination.pages` kan tien zijn, elke pagina is één verzoek uit
  /// zestig per minuut, en dat budget wordt gedeeld met de albumpagina, het creditspaneel en de
  /// warmer. Twee pagina's is tweehonderd uitgaves; wie meer heeft, heeft ook geen leesbare lijst meer.
  ///
  /// Loopt door dezelfde [_get] als de rest: baan, cache en foutentelling zitten daar al in.
  Future<List<DiscoRelease>> artistReleases(int id, {int pages = 2, DiscogsSweep? sweep_}) async {
    // Zonder de sweep draagt elke master hier `RecordKind.other`. De aanroeper mag hem meegeven als
    // hij hem toch al ophaalt; zie [artistSweep] voor waarom niet per regel.
    final sweep = sweep_ ?? await artistSweep(id);
    final uit = <DiscoRelease>[];
    for (var p = 1; p <= pages; p++) {
      final b = await _get('https://api.discogs.com/artists/$id/releases'
          '?sort=year&sort_order=desc&per_page=100&page=$p');
      final rijen = b?['releases'] as List<dynamic>? ?? const [];
      if (rijen.isEmpty) break;
      for (final r in rijen) {
        if (r is! Map<String, dynamic>) continue;
        if ((r['role'] as String? ?? '').trim() != 'Main') continue;
        final rid = (r['id'] as num?)?.toInt();
        final titel = (r['title'] as String? ?? '').trim();
        if (rid == null || titel.isEmpty) continue;
        // Een master is de PLAAT, een release één persing ervan. Beide takken bestaan al aan de
        // andere kant, bij het openen van een album.
        final master = (r['type'] as String? ?? '') == 'master';
        var thumb = (r['thumb'] as String? ?? '').trim();
        if (thumb.isEmpty || thumb.contains('spacer')) {
          thumb = sweep.hoesPerSleutel[discoKey(titel)] ?? '';
        }
        final jaar = (r['year'] as num?)?.toInt() ?? 0;
        // Een master draagt hier geen formaat; de sweep weet het wel. Zonder deze regel valt een
        // vijfde van de discografie in "Overig".
        final formaat = (r['format'] as String? ?? '').trim().isNotEmpty
            ? (r['format'] as String)
            : (master ? (sweep.formaatPerMaster[rid] ?? '') : '');
        uit.add(DiscoRelease(
          title: titel,
          kind: kindFromDiscogs(formaat),
          // Jaar nul betekent hier "onbekend" en niet het jaar nul. Als tekst laten staan zou die
          // regel bij het sorteren op datum onderaan de twintigste eeuw belanden.
          firstDate: jaar > 0 ? '$jaar' : null,
          cover: thumb.isEmpty || thumb.contains('spacer') ? null : thumb,
          sources: const {DiscoSource.discogs},
          refs: {
            DiscoSource.discogs:
                master ? CatalogRef.discogsMaster(rid) : CatalogRef.discogsRelease(rid),
          },
        ));
      }
      final totaal = (b?['pagination'] as Map<String, dynamic>?)?['pages'] as num?;
      if (totaal == null || p >= totaal.toInt()) break;
    }
    return uit;
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
          if (m is Map<String, dynamic> && (m['name'] as String?) != null) m['name'] as String,
      ],
      aliases: [
        for (final a in (b['aliases'] as List<dynamic>? ?? const []))
          if (a is Map<String, dynamic> && (a['name'] as String?) != null) a['name'] as String,
      ],
      images: [
        for (final i in (b['images'] as List<dynamic>? ?? const []))
          if (i is Map<String, dynamic>) DiscogsImage.from(i),
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
      [...images.where((i) => !i.isWide)]
        ..sort((a, b) => (b.primary ? 1 : 0).compareTo(a.primary ? 1 : 0));

  /// The ones wide enough to sit behind a page.
  List<DiscogsImage> get backdrops => images.where((i) => i.isWide).toList();
}

/// Where an album's scans live on disk, as one name.
///
/// Both pins are part of it. Without that a new choice would keep answering with the scans fetched
/// for the old one — which is half of why picking a release changed the front cover and left the back
/// and the disc exactly as they were.
///
/// expectedTracks is in it because it CHANGES the answer — it decides which pressings qualify.
/// Leaving it out meant a library album and the same album opened from browse (which knows no track
/// count) shared one entry, and whichever ran first won permanently.
///
/// A hand-assigned role belongs in it for the same reason a pin does: change what the back cover IS
/// and the entry cached under the old answer must not keep being served.
///
/// The version marks a schema change: nothing here expires, so without bumping it every album would
/// keep serving the art it cached first. v2 was when the archive started being consulted; v3 was the
/// move to 1200px scans; v4 is roles becoming part of the question; v5 drops the search terms once a
/// pin makes them irrelevant.
///
/// v6 is what the `done` marker MEANS. Until now it was written whenever anything at all was found,
/// so a record the Cover Art Archive answered with a front cover and nothing else was marked finished
/// — and then nothing ever looked for its back or its disc again. ANTI was exactly that: TheAudioDB
/// has both scans for it, the warmer skipped it as "already warm", and the page kept showing only the
/// sleeve. Every old entry has to be re-derived for that to come loose, which is what a version bump
/// is for.
///
/// With a pin, artist/album/expectedTracks do not reach the answer — the pin does; they are only how
/// a release is FOUND when there is none. Leaving them in meant renaming an album guaranteed a miss,
/// and a miss is a network round trip during which the page keeps showing the previous record's
/// scans. Correcting a name is exactly when someone is looking at the sleeve.
///
/// Shared with [DiscogsService.hasReleaseArt] so the warmer asks the same question the reader does.
/// Two spellings of this key would mean warming one place and reading another.
String artCacheKey(
  String artist,
  String album,
  int expectedTracks,
  int? pinned,
  String? pinnedMbid,
  Map<String, String> roles,
) {
  final pinnedKey = '${pinned ?? 0}|${pinnedMbid ?? ''}';
  final searchKey =
      (pinned == null && pinnedMbid == null) ? '$artist|$album|$expectedTracks' : '';
  final roleKey = (roles.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join(',');
  return sha1.convert(utf8.encode('art|v6|$searchKey|$pinnedKey|$roleKey')).toString();
}

/// The three scans an album page shows: the sleeve, its back, and the disc itself.
class ReleaseArt {
  final Uint8List? front, back, disc;
  const ReleaseArt({this.front, this.back, this.disc});
  bool get isEmpty => front == null && back == null && disc == null;
}

extension DiscogsArtwork on DiscogsService {
  /// Fetch and identify the front, back and disc scans for an album, cached on disk.
  ///
  /// Only the first handful of scans are downloaded. Dangerous has 31 — a booklet page by page —
  /// and the three that matter are always near the top, so pulling the lot would cost megabytes
  /// to answer a question already settled.
  Future<ReleaseArt?> releaseArt(
    String artist,
    String album, {
    int expectedTracks = 0,
    int? pinned,
    String? pinnedMbid,
    Map<String, String> roles = const {},
    /// Only the sources that cost nothing: the Cover Art Archive and TheAudioDB. Never Discogs.
    ///
    /// For the background warmer, which has 79 records to get through. Measured from inside the chain
    /// on the real library: the archive answers in 2.5 seconds and TheAudioDB in another 0.2, and then
    /// `edition` — up to three masters × three formats × three pressings, about thirty-six requests,
    /// spaced a second apart and three seconds once the budget dips — did not return within
    /// eighty-seven. Per record. Warming a library that way finishes some time next week.
    ///
    /// The page keeps the full chain: that is one record, on demand, with someone watching it.
    bool freeOnly = false,
    // Where the seconds actually go, when a caller cares. The warmer passes its log here.
    //
    // Earned by three wrong guesses in a row: "it is the images", "it is the Discogs budget", "it is
    // the two loops competing". Each was ruled out by measurement and none of them was it — with the
    // facts sweep fully deferred and the whole budget free, one record still ran past ninety seconds.
    // Guessing at a chain with five stages from the outside does not work.
    void Function(String)? trace,
  }) async {
    // Both pins are part of the cache key. Without that a new choice would keep answering with the
    // scans fetched for the old one — which is half of why picking a release changed the front
    // cover and left the back and the disc exactly as they were.
    // expectedTracks is in the key because it CHANGES the answer — it decides which pressings
    // qualify. Leaving it out meant a library album and the same album opened from browse (which
    // knows no track count) shared one entry, and whichever ran first won permanently.
    //
    // A hand-assigned role belongs in the key for the same reason a pin does: change what the back
    // cover IS and the entry cached under the old answer must not keep being served.
    //
    // The version marks a schema change: nothing here expires, so without bumping it every album
    // would keep serving the art it cached first. v2 was when the archive started being consulted;
    // v3 was the move to 1200px scans; v4 is roles becoming part of the question; v5 drops the
    // search terms once a pin makes them irrelevant.
    //
    // With a pin, artist/album/expectedTracks do not reach the answer — the pin does; they are only
    // how a release is FOUND when there is none. Leaving them in meant renaming an album guaranteed
    // a miss, and a miss is a network round trip during which the page keeps showing the previous
    // record's scans. Correcting a name is exactly when someone is looking at the sleeve.
    final key = artCacheKey(artist, album, expectedTracks, pinned, pinnedMbid, roles);
    final dir = Directory('$artDir${Platform.pathSeparator}$key');
    // Only a FINISHED entry short-circuits. The warmer may have left images here from the free
    // sources without the marker; those are worth having on screen but they are not the last word, and
    // serving them as the answer would mean the back and the disc never get looked for.
    final cached = await _readArt(dir);
    if (cached != null && await _afgerond(dir, cached)) {
      return cached;
    }

    // One chain per album, however many widgets ask.
    //
    // Opening an album page starts two of these at the same moment with IDENTICAL arguments — the
    // sleeve widget wants all three scans, the info panel wants the back cover — and on a cold cache
    // they both missed above and both ran the whole thing: two searches, two rounds of scan lookups,
    // two sets of image downloads, and two writes into the same directory. The disk cache only helps
    // the SECOND opening; nothing was stopping the first from doing everything twice.
    //
    // Static, like the rate-limit lane and for the same reason: DiscogsService is constructed fresh
    // at fourteen call sites, so an instance field would give each caller its own idea of what is
    // already running.
    // The lane key carries freeOnly, and the cache key deliberately does not.
    //
    // On disk they are the same entry — the same three pictures of the same record — so the cache key
    // must not split. But two chains for one record are NOT interchangeable while they run: the free
    // one stops before Discogs. Sharing this table meant the backfill could join a free-only chain
    // already in progress and get its answer, so the metered pass it exists to perform never
    // happened. And they do overlap: warm.log shows the free sweep re-arming at 16:03:02 while the
    // backfill was working on a record from 16:02:53.
    final lane = '$key|${freeOnly ? 'vrij' : 'vol'}';
    final running = _artInFlight[lane];
    if (running != null) {
      trace?.call('  [kunst] al onderweg voor dezelfde sleutel — meegelift');
      return running;
    }
    final work =
        _releaseArtFresh(artist, album, expectedTracks, pinned, pinnedMbid, roles, dir, trace, freeOnly)
            .whenComplete(() {
      _artInFlight.remove(lane);
      trace?.call('  [kunst] whenComplete — uit de in-flight tabel');
    });
    _artInFlight[lane] = work;
    trace?.call('  [kunst] work aangemaakt en teruggegeven aan de aanroeper');
    return work;
  }

  static final _artInFlight = <String, Future<ReleaseArt?>>{};

  /// The artwork chain itself. Only reached on a cache miss, and only once per album at a time —
  /// see [releaseArt], which owns the cache key and the in-flight table.
  Future<ReleaseArt?> _releaseArtFresh(
    String artist,
    String album,
    int expectedTracks,
    int? pinned,
    String? pinnedMbid,
    Map<String, String> roles,
    Directory dir,
    void Function(String)? trace,
    bool freeOnly,
  ) async {
    final t0 = DateTime.now();
    void step(String what) =>
        trace?.call('  [kunst] +${DateTime.now().difference(t0).inMilliseconds}ms $what');
    step('begin');
    // What the user SAID an image is outranks everything below — the archive's own labels included.
    // Fetched first and kept aside; the automatic answers fill only the roles left unassigned.
    Uint8List? saidFront, saidBack, saidDisc;
    if (roles.isNotEmpty) {
      final wanted = ['front', 'back', 'disc'];
      final got = await Future.wait(
          [for (final r in wanted) (roles[r] ?? '').isEmpty ? Future.value(null) : _rolPlaatje(roles[r]!)]);
      saidFront = got[0];
      saidBack = got[1];
      saidDisc = got[2];
      // Every role answered by hand: nothing left to look up.
      if (saidFront != null && saidBack != null && saidDisc != null) {
        final art = ReleaseArt(front: saidFront, back: saidBack, disc: saidDisc);
        await _writeArt(dir, art);
        return art;
      }
    }

    // Anything found below fills only the roles the user did NOT assign.
    ReleaseArt said(ReleaseArt found) => ReleaseArt(
          front: saidFront ?? found.front,
          back: saidBack ?? found.back,
          disc: saidDisc ?? found.disc,
        );

    /// Enough to stop looking, without paying Discogs for the rest.
    ///
    /// The back and the disc are what the free sources can actually supply and what the page is
    /// missing; the FRONT the library almost always already has, embedded in the files, and the album
    /// page falls back to it. Requiring all three before stopping is what kept sending every record
    /// on to Discogs: measured on the real library, each one then ran past ninety seconds and
    /// finished nothing at all in five minutes, because the sixty-a-minute budget is shared with the
    /// tracklist sweep and its spacing triples when the budget runs low.
    bool enough(ReleaseArt a) => a.back != null && a.disc != null;

    // A pinned MusicBrainz pressing is an exact answer: take its scans and no one else's.
    ReleaseArt? partial;
    if (pinnedMbid != null && pinnedMbid.isNotEmpty) {
      final exact = await _artFromCaa(pinnedMbid);
      step('archief voor de gepinde persing: '
          '${exact == null ? "niets" : "voor=${exact.front != null} achter=${exact.back != null} cd=${exact.disc != null}"}');
      if (exact != null) {
        final art = said(exact);
        if (enough(art) || (art.front != null && art.back != null && art.disc != null)) {
          await _writeArt(dir, art);
          return art;
        }
        partial = art;
      }
    }

    // TheAudioDB, before anything metered. It keeps a back cover and a disc scan per album
    // (strAlbumBack, strAlbumCDart), it is keyless and unmetered, and the album page fetches this
    // very response for the blurb already — the two fields were simply never read.
    //
    // This sits here on purpose. Below is Discogs, whose sixty requests a minute are the scarcest
    // thing in this app: measured on the real library with two loops running, ONE album's artwork
    // spent over two minutes waiting for a slot. Anything free that can answer first should.
    if ((partial?.back == null || partial?.disc == null) && artist.isNotEmpty && album.isNotEmpty) {
      final info = await CoverEnricher(settings).albumInfo(artist, album);
      step('theaudiodb: ${info == null ? "GEEN ANTWOORD" : "achter=${info.backUrl != null} cd=${info.discUrl != null}"}');
      final back = partial?.back ?? await _fetchIf(info?.backUrl);
      final disc = partial?.disc ?? await _fetchIf(info?.discUrl);
      step('theaudiodb-afbeeldingen: achter=${back != null} cd=${disc != null}');
      if (back != null || disc != null) {
        final art = said(ReleaseArt(front: partial?.front, back: back, disc: disc));
        if (enough(art)) {
          await _writeArt(dir, art);
          return art;
        }
        partial = art;
      }
    }

    // The archive again, now across the record's OTHER pressings.
    //
    // This used to be skipped entirely whenever anything was pinned. For a Discogs pin that is right:
    // the user answered "which pressing is this", and describing it with someone else's scans is the
    // disregard that made pinning feel broken. But for a MusicBrainz pin it was throwing away the
    // cheapest source there is. Traced on ANTI: the pinned pressing gives `voor=true achter=false
    // cd=false`, and one pressing having no back cover says nothing about the record — a sibling
    // pressing in the same free archive very often has one. The front still comes from the pinned
    // pressing; only the roles it cannot fill are looked for elsewhere.
    ReleaseArt? caa = partial;
    final needMore = partial == null || partial.back == null || partial.disc == null;
    if (pinned == null && needMore) {
      final wider = await _artFromMusicBrainz(artist, album, expectedTracks);
      step('archief over andere persingen: ${wider == null ? "niets" : "voor=${wider.front != null} "
          "achter=${wider.back != null} cd=${wider.disc != null}"}');
      if (wider != null) {
        caa = ReleaseArt(
          front: partial?.front ?? wider.front,
          back: partial?.back ?? wider.back,
          disc: partial?.disc ?? wider.disc,
        );
        final art = said(caa);
        if (enough(art)) {
          await _writeArt(dir, art);
          return art;
        }
      }
      // A partial answer is kept, not discarded. Requiring a front threw away a back cover and a
      // disc scan that were already downloaded whenever the front was the one image missing.
    }
    partial = caa;

    // The warmer stops here. What the free sources found is written, but WITHOUT the done marker
    // unless it is complete enough — so the page still knows to run the full chain when someone
    // actually opens this record, and the sleeve it does have shows up immediately meanwhile.
    if (freeOnly) {
      final art = said(partial ?? const ReleaseArt());
      step('gratis bronnen klaar — geen Discogs (warmen): '
          'voor=${art.front != null} achter=${art.back != null} cd=${art.disc != null}');
      if (!art.isEmpty) {
        await _writeArt(dir, art, done: enough(art));
        step('weggeschreven (done=${enough(art)}) — keten klaar');
        return art;
      }
      step('niets gevonden — keten klaar');
      return null;
    }

    step('naar Discogs — de gemeterde weg');
    // One search plus one release, before the pressing hunt.
    //
    // [edition] answers "WHICH pressing is this record", and it earns its cost on the album page,
    // where the pressing line and the scans have to describe the same object. Here we only want
    // pictures, and it was charging about thirty-six requests for them: measured in warm.log, "Tout
    // Un Jour" and "Per ongeluk" each ran past two full minutes and wrote nothing at all.
    //
    // Asked by hand against the same API, one search and one release fetch reach the images in two
    // requests — and the material is there: three, seven and eighty images for the three records I
    // tried. Borrowing pictures from a sibling pressing is already how this file works; the disc has
    // been fetched that way for a long time (see [_discFromAnotherPressing]).
    //
    // Not when the user pinned a release. Then they answered the question themselves and the answer
    // is that pressing's own scans.
    DiscogsEdition? e;
    if (pinned == null) {
      e = await _quickRelease(artist, album);
      step('Discogs snelzoek: ${e == null ? "niets" : "${e.images.length} afbeeldingen"}');
    }
    e ??= await edition(artist, album, expectedTracks: expectedTracks, pinned: pinned);
    step('Discogs-persing: ${e == null ? "niets" : "${e.images.length} afbeeldingen"}');
    if (e == null || e.images.isEmpty) {
      // Discogs has nothing to add, but the archive may still have given us something.
      final art = said(caa ?? const ReleaseArt());
      if (!art.isEmpty) {
        await _writeArt(dir, art);
        return art;
      }
      return null;
    }
    const look = 6;
    final take = e.images.length < look ? e.images.length : look;
    // Together, not one after another. These are plain image GETs to Discogs' CDN and do NOT go
    // through the rate-limited _get above, so waiting for each in turn bought nothing but delay.
    final datas = await Future.wait([for (var i = 0; i < take; i++) fetchImage(e.images[i].uri)]);
    final guessed = assignRoles(
      [for (var i = 0; i < take; i++) e.images[i].primary],
      [
        for (var i = 0; i < take; i++)
          e.images[i].height == 0 ? 1.0 : e.images[i].width / e.images[i].height,
      ],
      datas,
    );
    Uint8List? at(int? i) => (i == null || i >= datas.length) ? null : datas[i];
    var disc = at(guessed.disc);
    // Not every pressing has its disc photographed, and a missing scan is a missing animation —
    // for a record the library demonstrably holds. So borrow one from another pressing of the SAME
    // master: it is the same disc art, just someone else's scanner.
    disc ??= await _discFromAnotherPressing(artist, album, e.releaseId);
    // Order of authority: what the user assigned, then what the archive STATES an image is, then
    // what was inferred here from shape and pixels. Each only fills what the one above left open.
    final art = said(ReleaseArt(
      front: caa?.front ?? at(guessed.front),
      back: caa?.back ?? at(guessed.back),
      disc: caa?.disc ?? disc,
    ));
    if (art.isEmpty) return null; // nothing found — don't cache a blank as the answer
    await _writeArt(dir, art);
    return art;
  }

  /// The three scans from the Cover Art Archive, which says outright what each image is.
  ///
  /// The whole reason to ask here first: `Front`, `Back` and `Medium` are stated, where the Discogs
  /// path below has to infer them from shape and pixels. Nothing is guessed and nothing is
  /// downloaded to find out.
  ///
  /// Walks a few pressings, not one. The Japanese CD of *30* carries twenty-one scans and the
  /// British one carries none, so stopping at the best-ranked pressing would report "no back cover"
  /// for a record that plainly has one. A borrowed disc scan is the same disc art either way.
  Future<ReleaseArt?> _artFromMusicBrainz(String artist, String album, int expectedTracks) async {
    try {
      final mb = MusicBrainzService();
      final hits = await mb.searchReleases(
        artist,
        DiscogsService.plainTitle(album),
        expectedTracks: expectedTracks,
        max: 25,
      );
      if (hits.isEmpty) return null;

      // In waves, and the wave is the point. This walked up to twenty-five pressings ONE AT A TIME,
      // and the cap of four counted only pressings that turned out to have scans — so a record whose
      // first twenty entries are bare (common: catalogue stubs rank as high as documented pressings)
      // paid for twenty round trips in single file before it reached the fourth useful one. At one to
      // two seconds each that is half a minute, and it is the reason an album page could sit there
      // with no back cover and no disc for far longer than it had any right to.
      //
      // Four at a time, at most three waves. Asking four when one would have done costs three cached
      // lookups; asking them in turn cost seconds each. Order is still respected: the front comes
      // from the FIRST pressing that has one, because that is the sleeve this record is known by, so
      // the results are walked in hit order regardless of which answer arrived first.
      // Four at a time, and now it keeps going while a role is still missing.
      //
      // It used to stop after four pressings that had ANY scans, which is what a request budget buys
      // you — except the Cover Art Archive does not have one. Their own API documentation says it
      // plainly: "There are currently no rate limiting rules in place at coverartarchive.org."
      // Stopping at four while the back cover and the disc were still empty was caution paid to a
      // toll booth that is not there, and it is a large part of why so many records ended up with a
      // front and nothing else. The front is usually settled by the first pressing; the back and the
      // disc are the rare ones, so those are what the extra waves are for.
      //
      // Still bounded — this is somebody's charity server and each wave is four image lookups.
      const perWave = 4;
      const maxLooked = 12;
      Uint8List? front, back, disc;
      var looked = 0;
      for (var w = 0; w * perWave < hits.length && w < 5; w++) {
        if (looked >= maxLooked || (front != null && back != null && disc != null)) break;
        final wave = hits.skip(w * perWave).take(perWave).toList();
        final scans = await Future.wait([for (final r in wave) mb.art(r.mbid)]);
        for (final images in scans) {
          if (images.isEmpty) continue;
          if (looked >= maxLooked) break;
          looked++;
          // The three downloads together: they are separate GETs to archive.org and waiting for one
          // before starting the next added a second per role for nothing.
          final want = <String, MbImage>{};
          for (final i in images) {
            if (front == null && i.isFront) want.putIfAbsent('front', () => i);
            if (back == null && i.isBack) want.putIfAbsent('back', () => i);
            if (disc == null && i.isDisc) want.putIfAbsent('disc', () => i);
          }
          if (want.isEmpty) continue;
          final keys = want.keys.toList();
          final bytes = await Future.wait([for (final k in keys) mb.fetchImage(want[k]!.full)]);
          for (var n = 0; n < keys.length; n++) {
            switch (keys[n]) {
              case 'front':
                front ??= bytes[n];
              case 'back':
                back ??= bytes[n];
              case 'disc':
                disc ??= bytes[n];
            }
          }
        }
      }
      if (front == null && back == null && disc == null) return null;
      return ReleaseArt(front: front, back: back, disc: disc);
    } catch (_) {
      return null; // no art from here is not an error — the Discogs path takes over
    }
  }

  /// The first release Discogs offers for this record, in two requests.
  ///
  /// Deliberately not [edition]: no master walk, no per-format version lists, no track-count fitting.
  /// Those exist to pick the RIGHT pressing, and that question costs about thirty-six requests out of
  /// sixty a minute. For artwork any pressing of the record will do — the pictures are of the same
  /// record either way — so this asks the search for a release and fetches it. Two requests.
  ///
  /// Returns null on anything doubtful, and the caller then falls back to the full chain: a wrong
  /// record's sleeve is worse than a slow one.
  Future<DiscogsEdition?> _quickRelease(String artist, String album) async {
    final who = cleanArtistName(artist);
    final title = DiscogsService.plainTitle(album);
    final body = await _get(
      'https://api.discogs.com/database/search?type=release&per_page=5'
      '&artist=${_q(who)}&release_title=${_q(title)}',
    );
    final results = body?['results'] as List<dynamic>? ?? const [];
    for (final r in results.take(3)) {
      if (r is! Map<String, dynamic>) continue;
      final id = (r['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      // The search states the formats; a promo single carrying the album's name is not the album.
      final formats = [for (final f in (r['format'] as List<dynamic>? ?? const [])) f.toString()];
      if (formats.any(DiscogsService.notAnAlbum.hasMatch)) continue;
      final e = await release(id);
      if (e != null && e.images.isNotEmpty) return e;
    }
    return null;
  }

  /// The scans of ONE pressing, because the user named it. No borrowing from anywhere else.
  Future<ReleaseArt?> _artFromCaa(String mbid) async {
    try {
      final mb = MusicBrainzService();
      final images = await mb.art(mbid);
      if (images.isEmpty) return null;
      Uint8List? front, back, disc;
      for (final i in images) {
        if (front == null && i.isFront) front = await mb.fetchImage(i.full);
        if (back == null && i.isBack) back = await mb.fetchImage(i.full);
        if (disc == null && i.isDisc) disc = await mb.fetchImage(i.full);
      }
      if (front == null && back == null && disc == null) return null;
      return ReleaseArt(front: front, back: back, disc: disc);
    } catch (_) {
      return null;
    }
  }

  /// A disc scan from any other pressing of this record, or null.
  ///
  /// Bounded hard: two extra releases, three images each. The disc is nearly always among the
  /// first few scans, and this runs on the sixty-a-minute budget shared with everything else.
  Future<Uint8List?> _discFromAnotherPressing(String artist, String album, int skip) async {
    try {
      final masters = await masterIds(artist, album);
      if (masters.isEmpty) return null;
      final versions = DiscogsService.orderByPreference(
        await _versions(masters.first, format: 'CD'),
      );
      var tried = 0;
      for (final v in versions) {
        if (v.id == skip || tried >= 2) continue;
        tried++;
        final other = await release(v.id);
        for (final img in (other?.images ?? const <DiscogsImage>[]).take(3)) {
          final bytes = await fetchImage(img.uri);
          if (bytes != null && looksLikeDisc(bytes)) return bytes;
        }
      }
    } catch (_) {
      /* no disc is not an error, just no animation */
    }
    return null;
  }

  String get artDir => '$appDir${Platform.pathSeparator}releaseart';

  /// Are this record's scans already on disk?
  ///
  /// Answers from the `done` marker rather than from the images, because a release that genuinely
  /// has only a front cover is finished too — see [DiscogsArtwork._writeArt]. Exists so the warmer
  /// can tell an album that still needs its artwork from one that already has it, without going near
  /// the network.
  Future<bool> hasReleaseArt(
    String artist,
    String album, {
    int expectedTracks = 0,
    int? pinned,
    String? pinnedMbid,
    Map<String, String> roles = const {},
  }) async {
    final key = artCacheKey(artist, album, expectedTracks, pinned, pinnedMbid, roles);
    try {
      return await File('$artDir${Platform.pathSeparator}$key${Platform.pathSeparator}done').exists();
    } catch (_) {
      return false;
    }
  }

  Future<ReleaseArt?> _readArt(Directory dir) async {
    try {
      if (!await dir.exists()) return null;
      Future<Uint8List?> one(String n) async {
        final f = File('${dir.path}${Platform.pathSeparator}$n');
        return await f.exists() ? await f.readAsBytes() : null;
      }

      final art = ReleaseArt(
        front: await one('front'),
        back: await one('back'),
        disc: await one('disc'),
      );
      // Een map zonder één enkele afbeelding is GEEN antwoord.
      //
      // Hij gaf hier `ReleaseArt(null, null, null)` terug, en dat is niet hetzelfde als "niets
      // gevonden" — het telt bovenaan als een cachetreffer en in de widget als `art != null`, dus het
      // OVERSCHRIJFT wat er al op het scherm stond. Zo werd een leeggeruimd mapje een album zonder
      // hoes en zonder cd, en werd er nooit meer gezocht.
      if (art.front == null && art.back == null && art.disc == null) return null;
      return art;
    } catch (_) {
      return null;
    }
  }

  /// Een door de gebruiker AANGEWEZEN scan ophalen, bij de juiste balie.
  ///
  /// Elk archief bedient zijn eigen afbeeldingen, en Discogs wil zijn sleutel op het verzoek. Die
  /// splitsing maakt de app elders al — zie het opslaan van een gekozen hoes in `main.dart` en
  /// `booklet.dart`, waar letterlijk staat: *"Discogs images need the app's token; the Cover Art
  /// Archive is open"*. Alleen hier niet, en juist hier deed het pijn.
  ///
  /// Wijs je een cd aan in de MusicBrainz-kolom van de galerij, dan is dat een `coverartarchive.org`-
  /// adres. Dat werd met een `Authorization: Discogs token=…` opgehaald — een sleutel voor een heel
  /// ander huis, en bij een leeg token zelfs een lege sleutel. Mislukte die GET, dan bleef `saidDisc`
  /// leeg, ging de app **zelf gokken** welke scan de schijf was, en werd die gok gecached. Precies de
  /// klacht: "de cd is er niet altijd terwijl ik die wel heb aangeduid."
  Future<Uint8List?> _rolPlaatje(String url) =>
      url.contains('coverartarchive.org') ? MusicBrainzService().fetchImage(url) : fetchImage(url);

  /// Hoe lang een ONVOLLEDIG antwoord meegaat.
  ///
  /// Sommige platen hebben werkelijk geen scan van de achterkant of de schijf, en die elke keer
  /// opnieuw gaan zoeken is precies waar het merkteken `done` voor gemaakt is. Maar "nu niet
  /// gevonden" is niet hetzelfde als "bestaat niet": scans worden bij het Cover Art Archive dagelijks
  /// bijgeladen, en een Discogs-token dat later ingevuld wordt opent een bron die er eerst niet was.
  ///
  /// Een VOLLEDIG antwoord — hoes, achterkant én cd — vervalt nooit; daar valt niets aan te
  /// verbeteren. Alleen een onvolledig antwoord krijgt een houdbaarheidsdatum, zodat het hooguit
  /// eens per twee weken één zoekronde kost in plaats van bij elk bezoek.
  static const _onvolledigGeldig = Duration(days: 14);

  /// Is dit een afgerond antwoord waar niets meer aan te halen valt?
  Future<bool> _afgerond(Directory dir, ReleaseArt art) async {
    final merk = File('${dir.path}${Platform.pathSeparator}done');
    if (!await merk.exists()) return false;
    if (art.front != null && art.back != null && art.disc != null) return true;
    try {
      return DateTime.now().difference((await merk.stat()).modified) < _onvolledigGeldig;
    } catch (_) {
      return true; // een tijd die niet te lezen is, is geen reden om alles opnieuw te doen
    }
  }

  Future<void> _writeArt(Directory dir, ReleaseArt art, {bool done = true}) async {
    try {
      await dir.create(recursive: true);
      Future<void> one(String n, Uint8List? b) async {
        if (b != null) await File('${dir.path}${Platform.pathSeparator}$n').writeAsBytes(b);
      }

      await one('front', art.front);
      await one('back', art.back);
      await one('disc', art.disc);
      // A marker, so a release that genuinely has only a front cover isn't refetched every visit.
      //
      // Withheld when the background warmer wrote a partial answer from the free sources only. The
      // images are worth keeping — the sleeve shows at once — but the record has not been fully looked
      // up, and marking it done would mean the page never goes on to find the back and the disc.
      if (!done) return;
      await File('${dir.path}${Platform.pathSeparator}done').writeAsString('1');
    } catch (_) {
      /* a cache that can't be written is not worth failing over */
    }
  }

  /// Discogs serves images from its own CDN and wants the same User-Agent as the API.
  /// [fetchImage] for a url that may not be there. Saves the caller a null dance per image.
  Future<Uint8List?> _fetchIf(String? url) async =>
      (url == null || url.isEmpty) ? null : fetchImage(url);

  Future<Uint8List?> fetchImage(String url) async {
    try {
      final r = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': DiscogsService._ua,
              'Authorization': 'Discogs token=${settings.discogsToken.trim()}',
            },
          )
          .timeout(const Duration(seconds: 20));
      return r.statusCode == 200 && r.bodyBytes.length > 500 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}

/// Hoeveel treffers één zoekpagina geeft. Ook de maat waaraan [DiscogsChoices.losseReleases]
/// afmeet of die pagina hélemaal bruikbaar was, dus die twee mogen niet uit elkaar lopen.
const _zoekPagina = 100;

extension DiscogsChoices on DiscogsService {
  /// Every pressing Discogs lists, offered at once, with the scans filled in as they are found.
  ///
  /// Escape has SEVENTY-FIVE pressings, and the picker used to show two dozen after half a minute
  /// of waiting. The reason was the shape of the work: it fetched each release in full — one
  /// request apiece, a second apart — before showing anything at all.
  ///
  /// But a master's versions listing already carries — a hundred pressings per request — everything
  /// a row needs to be worth reading: format, label, catalogue number, country, year and the front
  /// cover. Measured on Escape, all seventy-five come back in 655 ms. So the list is built from that
  /// and handed over immediately, page by page.
  ///
  /// The per-release lookups — the only way to learn whether a pressing has a back or a disc, since
  /// Discogs never says what an image is — are NOT done here. Running them for forty rows up front,
  /// a request apiece on a lane that allows sixty a minute, spent most of a minute on rows the user
  /// never scrolled to. They belong to whoever puts a row on screen: see [DiscogsService.detailOf].
  ///
  /// Walks SEVERAL masters, not just the best-scoring one. Discogs has twenty-two masters titled
  /// "Michael Jackson - Thriller", and the top-scoring one is a vinyl-only entry with two versions
  /// — so the gallery showed vinyl and swore there were no CDs, while the site plainly has them.
  ///
  /// [pinned] is prepended unconditionally: the pressing the user already chose must never be
  /// missing from the list of choices.
  Future<List<ReleaseChoice>> releaseChoices(
    String artist,
    String album, {
    int max = 400,
    int maxPaginas = 6,
    int? pinned,
    void Function(List<ReleaseChoice>)? onPartial,
    void Function(int totaal, bool meer, int andereMasters)? onEinde,
    bool Function()? gestopt,
  }) async {
    final rows = <ReleaseChoice>[];
    final seen = <int>{};

    var vol = false;
    void addVersion(DiscogsVersion v) {
      if (v.id <= 0) return;
      // A tape scan is not what anyone is choosing to describe their FLACs with.
      //
      // VOOR `seen`, en dat is geen detail: kwam het id hier in de lijst van geziene, dan gold de
      // vastgezette uitgave hieronder als "staat er al" en werd hij niet opgehaald. Iemand met een
      // cassette als vaste keuze zag zijn eigen keuze dan nergens meer staan.
      if (v.major.toLowerCase().contains('cassette')) return;
      // KIJKEN of hij al gezien is, nog niet BIJSCHRIJVEN. Die volgorde draagt twee dingen die
      // allebei fout gingen toen ze door elkaar liepen:
      //
      //  - Een dubbele mag geen "de lijst is afgekapt" opleveren; er gaat niets verloren.
      //  - Maar een persing die wegvalt OMDAT de lijst vol is, mag niet als gezien te boek staan.
      //    De vastgezette uitgave hieronder wordt namelijk alleen apart opgehaald als hij níet in
      //    deze verzameling zit — en dan verdwijnt precies de uitgave die de gebruiker zelf koos
      //    uit de lijst met keuzes, zonder een woord.
      if (seen.contains(v.id)) return;
      if (rows.length >= max) {
        // De lijst zit vol MIDDEN in een pagina. `stop` kijkt alleen tussen pagina's door, dus
        // zonder deze regel vielen die laatste vijftig persingen weg terwijl de lus daarna netjes
        // meldde dat alles binnen was.
        vol = true;
        return;
      }
      seen.add(v.id);
      rows.add(rijVanVersie(v));
    }

    // ── De lijst, pagina voor pagina ─────────────────────────────────────────
    //
    // Er stond één request per master en dat was één PAGINA per master: vijftig persingen, en van
    // een plaat met meer was de rest onzichtbaar. Er was geen melding, geen "en nog 90" — de lijst
    // hield gewoon op, en wie de cd zocht die er wél is kreeg hem nooit te zien.
    //
    // Elke pagina wordt doorgegeven zodra hij binnen is. Dat is wat het snel houdt: de eerste
    // honderd staan er na één request, de rest schuift er in stilte achteraan.
    //
    // De voorkeursvolgorde geldt BINNEN een pagina en niet over het geheel, en dat is een keuze.
    // Over het geheel sorteren kan pas als alles binnen is — dan zou de lijst pas ná de laatste
    // pagina mogen verschijnen, of hij zou bij elke pagina onder je vinger door schudden. Discogs
    // levert op datum, dus de oorspronkelijke persing staat sowieso op pagina één; wie iets
    // specifieks zoekt heeft de formaatknoppen en het nummerveld.
    var totaal = 0;
    var meer = false;
    final masters = await masterIds(artist, album);
    final teLopen = masters.take(3).toList();
    for (final master in teLopen) {
      if (gestopt?.call() ?? false) break;
      if (rows.length >= max) {
        // Hier stond alleen `break`. Dan bleven master twee en drie ONGELEZEN terwijl de lijst
        // rapporteerde dat alles binnen was — en het master met de cd die iemand zoekt kan er
        // precies één van zijn.
        meer = true;
        break;
      }
      // No format filter: one unfiltered call returns every pressing, where asking per format cost
      // a request each and still capped what came back.
      await versionsOf(
        master,
        maxPaginas: maxPaginas,
        // Twee redenen om te stoppen: de lijst is vol, of er kijkt niemand meer. Dat tweede is de
        // dialoog die dichtgegaan is — doorgaan zou minuten aan een baan van zestig per minuut
        // kosten voor een venster dat er niet meer is.
        stop: () => rows.length >= max || (gestopt?.call() ?? false),
        // Het GROOTSTE aantal, niet de som. Optellen over masters levert een getal dat niets
        // beschrijft: dezelfde persing hangt onder meerdere masters, cassettes tellen mee terwijl
        // ze hier wegvallen, en de masters die we niet gelopen hebben ontbreken erin. Het grootste
        // is wél een echte ondergrens — dát master heeft er zoveel — en zo wordt het ook gezegd.
        onEinde: (n, m) {
          if (n > totaal) totaal = n;
          meer = meer || m;
        },
        perPagina: (pagina) {
          for (final v in DiscogsService.orderByPreference(pagina)) {
            addVersion(v);
          }
          onPartial?.call([...rows]);
        },
      );
    }
    // Bewust NIET `masters.length > 3`. Dat leek eerlijk, maar [_masters] geeft élke treffer terug
    // die het zoeken opleverde, ook de promo-singles en de gelijknamige platen van iemand anders die
    // het juist wegscoorde. Voor een doorsnee album zijn dat er meer dan drie, dus die waarschuwing
    // zou bijna altijd aan staan — en een waarschuwing die altijd aan staat leest niemand meer,
    // precies wanneer de lijst wél echt afgekapt is.
    // En wat onder geen enkel gelopen master hing — zie [losseReleases]. Ná de masters, want die
    // leveren de volledige en best beschreven lijst; dit is de aanvulling erop.
    if (rows.length < max && !(gestopt?.call() ?? false)) {
      final losse = await losseReleases(artist, album, max: max);
      meer = meer || losse.meer;
      for (final r in losse.rijen) {
        if (r.releaseId <= 0 || seen.contains(r.releaseId)) continue;
        if (rows.length >= max) {
          vol = true;
          break;
        }
        seen.add(r.releaseId);
        rows.add(r);
      }
      onPartial?.call([...rows]);
    }
    meer = meer || vol;
    if (pinned != null && pinned > 0 && !seen.contains(pinned)) {
      final rij = await keuzeVanRelease(pinned);
      if (rij != null) {
        rows.insert(0, rij);
        seen.add(pinned);
        // Ook doorgeven. De aanroeper leest de lijst via [onPartial] — deze regel als enige alleen
        // via de retourwaarde geven is hoe de vastgezette uitgave uit de kiezer verdween.
        onPartial?.call([...rows]);
      }
    }
    // Hoeveel kandidaat-masters er ONGELEZEN bleven. Niet als waarschuwing — zie hierboven waarom
    // die bijna altijd zou afgaan — maar als mededeling, want dit is wél het plafond waarachter een
    // gezochte persing zich het makkelijkst verstopt: het zoeken kiest op naam, en de promo hangt
    // net onder de vierde gelijknamige plaat.
    onEinde?.call(totaal, meer, masters.length - teLopen.length);
    return rows;
  }

  /// Uitgaves die onder GEEN van de gelopen masters hangen.
  ///
  /// **Waarom dit er los naast staat.** De kiezer werkt van master naar persingen: zoek het album,
  /// pak de drie best scorende, en haal daar alle versies van op. Dat vindt alles wat netjes onder
  /// een master hangt — en niets anders. Op Discogs mag een uitgave ook helemaal los bestaan: een
  /// promo die niemand aan een master heeft geknoopt, een heruitgave die onder een vierde master
  /// zit, een persing die als los item is ingevoerd. Die stonden nergens, en er was geen manier om
  /// erachter te komen dat ze bestonden.
  ///
  /// Eén request, dezelfde zoekmachine die het master vond. Losser dan een master, dus dezelfde
  /// titelscore beslist die ook een master zou hebben afgewezen — anders komt hier de gelijknamige
  /// plaat van iemand anders bij.
  Future<({List<ReleaseChoice> rijen, bool meer})> losseReleases(String artist, String album,
      {int max = 100}) async {
    final who = cleanArtistName(artist);
    final titel = DiscogsService.plainTitle(album);
    final body = await _get(
      'https://api.discogs.com/database/search?type=release&per_page=$_zoekPagina'
      '${who.isEmpty ? '' : '&artist=${_q(who)}'}&release_title=${_q(titel)}',
    );
    final out = <ReleaseChoice>[];
    for (final it in (body?['results'] as List<dynamic>? ?? const [])) {
      if (out.length >= max) break;
      if (it is! Map<String, dynamic>) continue;
      final id = (it['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      if (DiscogsService.titleScore(it['title'] as String? ?? '', artist, album) < 4) continue;
      final formats = [for (final f in (it['format'] as List<dynamic>? ?? const [])) f.toString()];
      if (formats.any((f) => f.toLowerCase().contains('cassette'))) continue;
      final labels = [for (final l in (it['label'] as List<dynamic>? ?? const [])) l.toString()];
      // Discogs serveert een doorzichtige stip waar een uitgave geen afbeelding heeft; die als hoes
      // tonen is erger dan een leeg vak, want dan lijkt de rij een hoes te hebben.
      final thumb = (it['thumb'] as String?)?.trim() ?? '';
      out.add(ReleaseChoice(
        source: EditionSource.discogs,
        releaseId: id,
        format: formats.isEmpty ? '' : formats.first,
        label: labels.isEmpty ? null : labels.first,
        catno: (it['catno'] as String?)?.trim(),
        country: (it['country'] as String?)?.trim(),
        year: DiscogsService.jaarUit(it['year']),
        front: thumb.isEmpty || thumb.contains('spacer')
            ? null
            : ChoiceImage(thumb, thumb, alleenMiniatuur: true),
        detailed: false,
      ));
    }
    // Eén zoekpagina, en verder pagineren doet dit bewust niet: dit is de AANVULLING op de masters,
    // niet de hoofdlijst, en elke pagina is een request uit een budget van zestig per minuut.
    //
    // "Er zijn meer pagina's" is hier GEEN reden tot waarschuwen, en dat is de val waar dit bijna
    // in liep. Het zoeken op releases telt rauwe treffers — vóór de titelscore hieronder en vóór
    // het ontdubbelen. Een plaat met honderdtwintig persingen die de masters allang compleet hebben
    // opgehaald levert twee pagina's zoekresultaten op, en een korte titel als "30" duizenden die
    // hier stuk voor stuk afvallen. Op "meer pagina's" alarm slaan zet de oranje regel dus
    // permanent aan — precies waarom `masters.length > 3` er eerder uit is gehaald, en het zou de
    // grijze "alles opgehaald" op de andere tak voorgoed het zwijgen opleggen.
    //
    // Wat hier wél iets zegt: deze pagina was HELEMAAL bruikbaar. Viel geen enkele treffer af, dan
    // is de kans reëel dat de volgende er ook nog van dit album heeft. Dat is zeldzaam, en dat is
    // precies wat een waarschuwing hoort te zijn.
    final helePaginaBruikbaar = out.length >= _zoekPagina;
    return (rijen: out, meer: helePaginaBruikbaar && DiscogsService.paginaAantal(body) > 1);
  }

  /// Eén regel uit de versielijst, als rij voor de kiezer.
  ReleaseChoice rijVanVersie(DiscogsVersion v) => ReleaseChoice(
        source: EditionSource.discogs,
        releaseId: v.id,
        format: v.major.isEmpty ? v.format : v.major,
        label: v.label,
        catno: v.catno,
        country: v.country,
        year: v.year,
        // The sleeve, straight from the listing — no lookup needed to show it.
        front: (v.thumb ?? '').isEmpty ? null : ChoiceImage(v.thumb!, v.thumb!, alleenMiniatuur: true),
        detailed: false,
      );

  /// Eén uitgave, op nummer opgezocht.
  ///
  /// Voor het veld waar de gebruiker een Discogs-nummer intypt. `detailed: false`, zodat de kiezer
  /// de scans langs zijn gewone weg ophaalt zodra de rij op het scherm staat — één weg naar die
  /// lookup en niet twee. De hoes komt wel meteen mee: het antwoord ligt er toch al, en een rij die
  /// een tel lang leeg is leest als "deze uitgave heeft niets".
  Future<ReleaseChoice?> keuzeVanRelease(int releaseId) async {
    if (releaseId <= 0) return null;
    final e = await release(releaseId);
    if (e == null) return null;
    DiscogsImage? hoes;
    for (final i in e.images) {
      if (i.primary) {
        hoes = i;
        break;
      }
    }
    hoes ??= e.images.isEmpty ? null : e.images.first;
    return ReleaseChoice(
      source: EditionSource.discogs,
      releaseId: e.releaseId,
      format: e.format,
      label: e.label,
      catno: e.catno,
      country: e.country,
      barcode: e.barcode,
      year: e.year,
      front: hoes == null ? null : ChoiceImage(hoes.uri, hoes.thumb),
      detailed: false,
    );
  }

  /// Elke persing onder één master, op nummer opgezocht.
  ///
  /// Voor hetzelfde veld: plak je de link van een master, dan is dat de vraag "laat mij ALLE
  /// uitgaves van dít master zien" — en dat is meteen de uitweg als het zoeken op naam op het
  /// verkeerde master uitkwam, wat bij een plaat met een titel die vaker voorkomt gewoon gebeurt.
  ///
  /// Anders dan [releaseChoices] laat dit ook cassettes staan. Daar worden ze weggelaten omdat
  /// niemand zijn FLAC-map met een bandje beschrijft; hier is er expliciet om dít master gevraagd,
  /// en dan is "alles" ook alles.
  Future<List<ReleaseChoice>> keuzesVanMaster(
    int master, {
    int max = 400,
    int maxPaginas = 6,
    void Function(List<ReleaseChoice>)? onPartial,
    void Function(int totaal, bool meer)? onEinde,
    bool Function()? gestopt,
  }) async {
    if (master <= 0) return const [];
    final rows = <ReleaseChoice>[];
    final seen = <int>{};
    var vol = false;
    await versionsOf(
      master,
      maxPaginas: maxPaginas,
      stop: () => rows.length >= max || (gestopt?.call() ?? false),
      onEinde: (totaal, meer) => onEinde?.call(totaal, meer || vol),
      perPagina: (pagina) {
        for (final v in DiscogsService.orderByPreference(pagina)) {
          if (v.id <= 0 || !seen.add(v.id)) continue;
          if (rows.length >= max) {
            vol = true;
            continue;
          }
          rows.add(rijVanVersie(v));
        }
        onPartial?.call([...rows]);
      },
    );
    return rows;
  }

  /// EVERY scan of one pressing, unlabelled and in the order Discogs lists them.
  ///
  /// The picker shows three; a release can carry thirty. When the roles come out wrong — and on a
  /// catalogue that never says what an image shows, they sometimes will — the user needs to see the
  /// rest to point at the right one.
  Future<List<ChoiceImage>> allImages(int releaseId) async {
    final e = await release(releaseId);
    return [for (final i in e?.images ?? const <DiscogsImage>[]) ChoiceImage(i.uri, i.thumb)];
  }

  /// One pressing's scans, worked out and labelled. Public so the picker can ask for a row as it
  /// scrolls into view.
  ///
  /// This used to run for the first forty rows the moment the dialog opened, one after another, at
  /// a request each on a lane that allows sixty a minute — the better part of a minute of work for
  /// rows nobody had looked at yet. The listing already carries a sleeve for every row, so the list
  /// is usable immediately and this fills in what you actually put on screen.
  Future<ReleaseChoice?> detailOf(ReleaseChoice row) => _detail(row);

  /// Look up one pressing's scans and work out which is the front, the back and the disc.
  ///
  /// Only images that could BE a disc are downloaded. Discogs gives every image's dimensions, so the
  /// front (its one "primary") and the back (a rear inlay wraps the spine, so it is wider than tall)
  /// are settled without fetching anything. That leaves the squarish secondaries, and it stops at
  /// the first one that reads as a disc — typically one or two small thumbnails instead of twelve.
  Future<ReleaseChoice?> _detail(ReleaseChoice row) async {
    final e = await release(row.releaseId);
    if (e == null) return null;
    final imgs = e.images;
    ChoiceImage of(DiscogsImage i) => ChoiceImage(i.uri, i.thumb);

    DiscogsImage? front, back, disc;
    for (final i in imgs) {
      if (front == null && i.primary) front = i;
    }
    for (final i in imgs) {
      if (identical(i, front)) continue;
      if (back == null && i.isWide) back = i;
    }
    // The disc candidates, tested together. Still "the first one that reads as a disc wins" — the
    // order below decides, not whichever download happens to finish first — but the thumbnails are
    // 150px and off the rate-limited path, so fetching a handful at once costs less than waiting
    // for each in turn. Capped, because a release can carry thirty scans.
    final maybeDisc = [
      for (final i in imgs)
        if (!identical(i, front) && !identical(i, back) && !i.isWide) i
    ].take(6).toList();
    final discBytes = await Future.wait([for (final i in maybeDisc) fetchImage(i.thumb)]);
    for (var k = 0; k < maybeDisc.length; k++) {
      final bytes = discBytes[k];
      if (bytes != null && looksLikeDisc(bytes)) {
        disc = maybeDisc[k];
        break;
      }
    }
    // No inlay-shaped scan: fall back to the convention that the first spare secondary is the back.
    if (back == null) {
      for (final i in imgs) {
        if (identical(i, front) || identical(i, disc)) continue;
        back = i;
        break;
      }
    }
    front ??= imgs.isEmpty ? null : imgs.first;
    return row.withArt(
      front: front == null ? row.front : of(front),
      back: back == null ? null : of(back),
      disc: disc == null ? null : of(disc),
      // The same answer carries the tracklist. Kept rather than discarded: it costs nothing, and
      // without it "take this pressing's numbering" had nothing to take.
      tracks: e.tracklist.isEmpty
          ? null
          : [for (final t in e.tracklist) ChoiceTrack(t.position, t.title, t.seconds)],
    );
  }
}

extension DiscogsSearch on DiscogsService {
  /// Album hits from Discogs, as the browse list already understands them.
  ///
  /// Deezer catalogues what streams; Discogs catalogues what was pressed, which is where the
  /// editions, the promos and the regional issues live. The id is the NEGATED release id so the
  /// album page can tell where a hit came from — Deezer ids are positive, and asking Deezer about
  /// a Discogs release would simply fail.
  Future<List<CatalogAlbumHit>> searchAlbums(String query, {int max = 12}) async {
    if (!available || query.trim().isEmpty) return const [];
    final b = await _get(
      'https://api.discogs.com/database/search'
      '?type=release&q=${_q(query.trim())}&per_page=${max * 2}',
    );
    final results = b?['results'] as List<dynamic>? ?? const [];
    final out = <CatalogAlbumHit>[];
    final seen = <String>{};
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final id = (r['id'] as num?)?.toInt();
      final title = (r['title'] as String?)?.trim() ?? '';
      if (id == null || id <= 0 || title.isEmpty) continue;
      // Hits read "Artist - Title"; without the split every card would repeat the artist.
      var artist = '', album = title;
      final dash = title.indexOf(' - ');
      if (dash > 0) {
        artist = cleanArtistName(title.substring(0, dash));
        album = title.substring(dash + 3).trim();
      }
      // Cassettes and videos are not what anyone is looking for here.
      final formats = [
        for (final f in (r['format'] as List<dynamic>? ?? const [])) f.toString().toLowerCase(),
      ];
      if (formats.any((f) => f.contains('cassette') || f.contains('dvd') || f.contains('blu-ray')))
        continue;
      // One card per record, not one per pressing: twenty Thriller CDs is not twenty results.
      if (!seen.add('${artistKey(artist)}|${normKey(album)}')) continue;
      final cover = (r['cover_image'] ?? r['thumb']) as String?;
      final year = (r['year'] as String?)?.trim();
      out.add(
        CatalogAlbumHit(
          CatalogAlbum(
            -id,
            album,
            (cover != null && cover.isNotEmpty && !cover.contains('spacer')) ? cover : null,
            (year != null && year.length >= 4) ? year : null,
            0,
            'album',
            origin: CatalogRef.discogsRelease(id),
          ),
          artist,
        ),
      );
      if (out.length >= max) break;
    }
    return out;
  }
}

extension DiscogsStyles on DiscogsService {
  /// Albums in a given style — the one search Deezer cannot do at all.
  ///
  /// Deezer knows a handful of genres; Discogs has thousands of styles and will filter on them
  /// directly, which is what makes "more like this" mean something narrower than "more pop".
  /// [deep] trades the front of the list for further down it. Sorting by fewest owners would
  /// surface unfinished entries rather than obscure records, so the well-known sort is kept and the
  /// page is moved instead: the same quality of entry, just past the ones everybody knows.
  Future<List<CatalogAlbumHit>> searchByStyle(
    String style, {
    int max = 24,
    bool deep = false,
  }) async {
    if (!available || style.trim().isEmpty) return const [];
    final b = await _get(
      'https://api.discogs.com/database/search'
      '?type=master&style=${_q(style.trim())}&sort=have&sort_order=desc'
      '&per_page=${max * 2}&page=${deep ? 4 : 1}',
    );
    final results = b?['results'] as List<dynamic>? ?? const [];
    final out = <CatalogAlbumHit>[];
    final seen = <String>{};
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final id = (r['master_id'] as num?)?.toInt() ?? (r['id'] as num?)?.toInt();
      final title = (r['title'] as String?)?.trim() ?? '';
      if (id == null || id <= 0 || title.isEmpty) continue;
      var artist = '', album = title;
      final dash = title.indexOf(' - ');
      if (dash > 0) {
        artist = cleanArtistName(title.substring(0, dash));
        album = title.substring(dash + 3).trim();
      }
      if (artist.isEmpty) continue;
      if (!seen.add('${artistKey(artist)}|${normKey(album)}')) continue;
      final cover = (r['cover_image'] ?? r['thumb']) as String?;
      final year = (r['year'] as String?)?.trim();
      out.add(
        CatalogAlbumHit(
          CatalogAlbum(
            -id,
            album,
            (cover != null && cover.isNotEmpty && !cover.contains('spacer')) ? cover : null,
            (year != null && year.length >= 4) ? year : null,
            0,
            'album',
          ),
          artist,
        ),
      );
      if (out.length >= max) break;
    }
    return out;
  }
}
