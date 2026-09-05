import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'editions.dart';
import 'organize.dart' show isBeeldFormaat;
import 'release_format.dart';
import 'paths.dart';

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
  /// The scan as it was uploaded, and a small copy for a list row.
  final String url, thumb;

  /// The copy to actually SHOW: the archive's 1200px rendering, or the upload itself when there
  /// isn't one.
  ///
  /// Not the 500px it used to take — that is visibly soft once a cover fills the now-playing
  /// screen. And not blindly the original either. Measured on Escape: the front's original IS
  /// 1200×1200 (171 KB, in fact smaller than the archive's own 1200 rendering), but the disc's
  /// original is 3008×2980 and **11.8 MB** — seventy times the bytes of the 1200 copy, for detail
  /// no window here can put on screen, cached per album.
  final String full;

  /// `Front`, `Back`, `Medium`, `Booklet`, `Tray`, `Spine`, `Obi`, …
  final List<String> types;

  /// The archive's own flags for the two that matter most; an image can be the front cover without
  /// carrying the `Front` type.
  final bool isFrontFlag, isBackFlag;
  const MbImage(this.url, this.thumb, this.full, this.types, this.isFrontFlag, this.isBackFlag);

  bool get isFront => isFrontFlag || types.contains('Front');
  bool get isBack => isBackFlag || types.contains('Back');

  /// The disc itself. This is the one the Discogs path has to guess at.
  bool get isDisc => types.contains('Medium');

  static MbImage? from(Map<String, dynamic> j) {
    final url = (j['image'] ?? '').toString();
    if (url.isEmpty) return null;
    final th = j['thumbnails'] is Map ? j['thumbnails'] as Map : const {};
    // A 250 is all a 58px row needs, and there are up to seventy-five of them.
    final thumb = (th['250'] ?? th['small'] ?? th['500'] ?? url).toString();
    // Note "large" is only 500px in this archive, despite the name — so it is no use here.
    final full = (th['1200'] ?? url).toString();
    return MbImage(
      url,
      thumb,
      full,
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

  /// 1-based. A double album numbers from 1 again on the second disc, so a position on its own
  /// does not say where a track sits on the record.
  final int disc;

  /// De artiestcredit van DIT nummer, zoals de uitgave hem schrijft: "Beyonce feat. JAY-Z".
  ///
  /// MusicBrainz zet een gastartiest hier en niet in de titel. Zonder dit veld is een bestand dat
  /// hem juist wel in de titel draagt niet te herkennen als hetzelfde nummer. Zie [ChoiceTrack.artist].
  final String artist;

  const MbTrack(this.position, this.title, this.ms, {this.disc = 1, this.artist = ''});

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

  /// De artiestcredit uit een MusicBrainz-object, of null als er geen staat.
  ///
  /// Dezelfde vorm die deze klasse al voor de UITGAVE gebruikt, letterlijk: een lijst van delen met
  /// `name` (of `artist.name`) plus een `joinphrase` die "feat. " of " & " kan zijn. Die verbindings-
  /// woorden horen erbij -- ze maken van "Beyonce" en "JAY-Z" de credit "Beyonce feat. JAY-Z".
  ///
  /// Op een nummer staat dit veld alleen als de aanvraag `inc=artist-credits` meestuurt; dat doet
  /// [tracklistFor] al. Staat het er niet, dan komt er null uit en gedraagt alles zich als voorheen.
  static String? _credit(dynamic j) {
    if (j is! Map) return null;
    final credits = j['artist-credit'];
    if (credits is! List || credits.isEmpty) return null;
    final uit = StringBuffer();
    for (final c in credits) {
      if (c is! Map) continue;
      final naam = (c['name'] ?? (c['artist'] is Map ? c['artist']['name'] : null) ?? '').toString();
      if (naam.isEmpty) continue;
      uit.write(naam);
      uit.write((c['joinphrase'] ?? '').toString());
    }
    final s = uit.toString().trim();
    return s.isEmpty ? null : s;
  }

  static MbRelease from(Map<String, dynamic> j) {
    final media = (j['media'] as List<dynamic>? ?? const []);
    final formats = <String>[];
    var count = 0;
    final tracks = <MbTrack>[];
    // Beeldmedia tellen niet mee als nummers. Een cd+dvd meldde anders "1 van 31 · 30 ontbreken"
    // terwijl de plaat 17 nummers heeft, en dezelfde titels stonden er twee keer in — zie
    // [isBeeldFormaat]. Alleen als er ook een AUDIOmedium is: een uitgave die enkel een dvd is
    // houdt zijn lijst, want anders verdwijnt er informatie in plaats van ruis.
    final heeftAudio = media.any((m) =>
        m is Map && !isBeeldFormaat((m['format'] ?? '').toString()));
    for (final m in media) {
      if (m is! Map) continue;
      final f = (m['format'] ?? '').toString();
      if (heeftAudio && isBeeldFormaat(f)) continue;
      if (f.isNotEmpty) formats.add(f);
      count += ((m['track-count'] as num?) ?? 0).toInt();
      // Which disc this is. MusicBrainz states it, and without carrying it the two discs of a
      // double album both look like tracks 1..n of the same thing.
      final disc = ((m['position'] as num?) ?? (media.indexOf(m) + 1)).toInt();
      for (final t in (m['tracks'] as List<dynamic>? ?? const [])) {
        if (t is! Map) continue;
        tracks.add(MbTrack(
          (t['number'] ?? '').toString(),
          (t['title'] ?? '').toString(),
          (t['length'] as num?)?.toInt(),
          disc: disc < 1 ? 1 : disc,
          artist: _credit(t) ?? _credit(t['recording']) ?? '',
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

/// An act, as MusicBrainz knows them.
class MbArtist {
  final String mbid, name;
  final String? type, country, disambiguation, begin, end;
  const MbArtist(this.mbid, this.name,
      {this.type, this.country, this.disambiguation, this.begin, this.end});

  /// "Group · US · 1993–" — enough to tell two acts of the same name apart, which is the whole
  /// reason MusicBrainz carries a disambiguation field at all.
  String get line => [
        if ((disambiguation ?? '').isNotEmpty) disambiguation!,
        if ((type ?? '').isNotEmpty) type!,
        if ((country ?? '').isNotEmpty) country!,
        if ((begin ?? '').length >= 4) '${begin!.substring(0, 4)}–${(end ?? '').length >= 4 ? end!.substring(0, 4) : ''}',
      ].join(' · ');

  static MbArtist from(Map<String, dynamic> j) {
    final span = j['life-span'];
    return MbArtist(
      (j['id'] ?? '').toString(),
      (j['name'] ?? '').toString(),
      type: (j['type'] as String?)?.trim(),
      country: (j['country'] as String?)?.trim(),
      disambiguation: (j['disambiguation'] as String?)?.trim().isEmpty ?? true
          ? null
          : (j['disambiguation'] as String).trim(),
      begin: span is Map ? span['begin']?.toString() : null,
      end: span is Map ? span['end']?.toString() : null,
    );
  }
}

/// A RECORD, as opposed to one of its pressings — the level a search result should be at, so
/// twenty pressings of Thriller are one card and not twenty.
class MbReleaseGroup {
  final String mbid, title, artist, artistMbid;

  /// Album / Single / EP / Broadcast / Other.
  final String primaryType;
  final List<String> secondaryTypes;
  final String? firstDate;
  const MbReleaseGroup(this.mbid, this.title, this.artist, this.artistMbid, this.primaryType,
      {this.secondaryTypes = const [], this.firstDate});

  int? get year => (firstDate ?? '').length >= 4 ? int.tryParse(firstDate!.substring(0, 4)) : null;

  /// A live album, a soundtrack and a compilation all say "Album" as their primary type; the
  /// secondary type is the only thing that separates them from a studio record.
  bool get isCompilation => secondaryTypes.any((s) => s.toLowerCase() == 'compilation');

  static MbReleaseGroup from(Map<String, dynamic> j) {
    final credits = (j['artist-credit'] as List<dynamic>? ?? const []);
    var artist = '', artistMbid = '';
    if (credits.isNotEmpty && credits.first is Map) {
      final c = credits.first as Map;
      artist = (c['name'] ?? c['artist']?['name'] ?? '').toString();
      artistMbid = (c['artist'] is Map ? c['artist']['id'] : null)?.toString() ?? '';
    }
    return MbReleaseGroup(
      (j['id'] ?? '').toString(),
      (j['title'] ?? '').toString(),
      artist,
      artistMbid,
      (j['primary-type'] ?? '').toString(),
      secondaryTypes: [
        for (final s in (j['secondary-types'] as List<dynamic>? ?? const [])) s.toString()
      ],
      firstDate: (j['first-release-date'] as String?)?.trim(),
    );
  }
}

/// One recorded performance. Not a track: the same recording appears as a track on every release
/// that carries it, which is why a search hit names the release it was found on.
/// One release a recording appears on: enough to name it, to pin it, and to rank it.
class MbRecordingRelease {
  final String mbid, title;

  /// Album / Single / EP / Broadcast / Other, as the release GROUP calls it. Empty when unstated.
  final String primaryType;

  /// Compilation, Live, Soundtrack, Remix… A studio album has none.
  final List<String> secondaryTypes;

  const MbRecordingRelease(this.mbid, this.title,
      {this.primaryType = '', this.secondaryTypes = const []});

  /// The artist's own record, as opposed to something their song was licensed onto.
  ///
  /// This is the whole difference between a useful answer and a useless one. "Porselein" by Yasmine
  /// is on sixteen releases; fifteen are compilations — *30 kleinkunst klassiekers deel 5*, *Tien om
  /// te zien: Editie 2023* — and exactly one is the album somebody searching for that song wants.
  bool get isStudioAlbum => primaryType == 'Album' && secondaryTypes.isEmpty;

  bool get isCompilation => secondaryTypes.contains('Compilation');
}

class MbRecording {
  final String mbid, title, artist;
  final int? ms;
  final String? onRelease;

  /// EVERY release this recording appears on, not only the first.
  ///
  /// "Which record is this song on" is a question with more than one answer — a track sits on its
  /// album, on a single, and on three compilations. Keeping only the first made a search by track
  /// title able to name one of them and hide the rest, which for the case this exists for ("I know
  /// the song, find me the album") is the wrong one about as often as it is the right one.
  final List<MbRecordingRelease> releases;

  const MbRecording(this.mbid, this.title, this.artist,
      {this.ms, this.onRelease, this.releases = const []});

  int get seconds => ms == null ? 0 : (ms! / 1000).round();

  static MbRecording from(Map<String, dynamic> j) {
    final credits = (j['artist-credit'] as List<dynamic>? ?? const []);
    final artist = credits.isEmpty || credits.first is! Map
        ? ''
        : ((credits.first as Map)['name'] ?? (credits.first as Map)['artist']?['name'] ?? '')
            .toString();
    final rels = (j['releases'] as List<dynamic>? ?? const []);
    final on = <MbRecordingRelease>[];
    for (final r in rels) {
      if (r is! Map) continue;
      final id = (r['id'] ?? '').toString();
      final title = (r['title'] ?? '').toString();
      if (id.isEmpty || title.isEmpty) continue;
      final group = r['release-group'];
      on.add(MbRecordingRelease(
        id,
        title,
        primaryType: group is Map ? (group['primary-type'] ?? '').toString() : '',
        secondaryTypes: group is Map
            ? [for (final s in (group['secondary-types'] as List? ?? const [])) s.toString()]
            : const [],
      ));
    }
    // The artist's own records first, then everything else, and a compilation last of all. Order
    // rather than a filter: a song that only ever appeared on a compilation must still be findable.
    on.sort((a, b) {
      int rank(MbRecordingRelease r) => r.isStudioAlbum ? 0 : (r.isCompilation ? 2 : 1);
      return rank(a).compareTo(rank(b));
    });
    return MbRecording(
      (j['id'] ?? '').toString(),
      (j['title'] ?? '').toString(),
      artist,
      ms: (j['length'] as num?)?.toInt(),
      onRelease: on.isEmpty ? null : on.first.title,
      releases: on,
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

  // STATIC, for the same reason discogs.dart says it there: the budget belongs to the SERVER, and
  // there is one server. This service is constructed at five separate places — the provider, the
  // booklet builder, the metadata editor and twice inside DiscogsService — and as instance fields
  // each of those got a private lane. Five lanes spacing their own requests 1.1 s apart is about
  // 4.5 requests a second at musicbrainz.org, well over the one a second it asks for, while every
  // one of them believes it is being polite.
  static final _lastCall = <String, DateTime>{};
  static final _turn = <String, Future<void>>{};

  /// Wait for a turn on [lane], and ONLY for the turn.
  ///
  /// The request used to sit inside the chained future, so each caller waited out the previous ROUND
  /// TRIP rather than the gap — and a Cover Art Archive lookup takes one to two seconds, not the
  /// 250 ms this lane is spaced for. Eight pressings meant fifteen seconds of standing in line for
  /// work archive.org is happy to take several at a time. Asking the callers in parallel could not
  /// help while the lane held every request from start to finish, which is why that change bought
  /// nothing; this is the part that had to move.
  ///
  /// What the lane still guarantees is exactly what the two services ask for: one request STARTED
  /// per [gap]. Overlapping round trips raise the concurrency, not the rate.
  @visibleForTesting
  static Future<void> laneSlot(String lane, Duration gap) {
    final slot = (_turn[lane] ?? Future.value()).then((_) async {
      final last = _lastCall[lane] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final since = DateTime.now().difference(last);
      // Never longer than the gap itself, whatever the arithmetic says.
      //
      // `gap - since` is only "the rest of the gap" while `since` is positive. Let the clock step
      // backwards — a time sync, a suspend, a timezone shift — and `since` goes negative, so
      // `gap - since` becomes the gap PLUS the whole jump. An hour's correction turns a 1.1 second
      // spacing into an hour of silence, and because the lane is one chain, every request behind it
      // waits too: no socket, no log line, nothing to see. Which is exactly what one record in the
      // facts sweep did, twice, for three-quarters of an hour.
      final wacht = since.isNegative || since > gap ? Duration.zero : gap - since;
      if (wacht > Duration.zero) await Future<void>.delayed(wacht);
      _lastCall[lane] = DateTime.now();
    });
    // The chain must survive a failed turn, or one thrown error deadlocks the lane for the session.
    _turn[lane] = slot.catchError((_) {});
    return slot;
  }

  /// Forget every lane's timing. Tests only — the lanes are static because the budget is.
  @visibleForTesting
  static void resetLanes() {
    _lastCall.clear();
    _turn.clear();
  }

  /// Somewhere to write what this lane is doing. Set once by the warmer.
  ///
  /// The Discogs lane got one first, and it settled the question there in a single line. This side
  /// stayed blind, and it cost an evening: "Vlaamse Diva's" sat in the facts sweep for
  /// three-quarters of an hour without one cache file being written and without one socket open to
  /// musicbrainz.org — which could mean a long queue, a stuck chain, or no request at all, and from
  /// the outside those three look identical.
  static void Function(String)? laneTrace;

  /// How many requests are waiting for a slot right now, across all lanes.
  static int _queued = 0;

  /// Spaced out per host, disk-cached. Null on any failure: a missing album page is a
  /// disappointment, a crashed one is a bug.
  Future<Map<String, dynamic>?> _get(String url, {required String lane, required Duration gap}) async {
    final cached = await _readCache(url);
    if (cached != null) {
      final miss = _missAge(cached);
      if (miss == null) return cached; // a real answer
      if (miss <= (_isNotFound(cached) ? _missKeepFound : _missKeepFlaky)) return null;
      // A remembered "no" that has had its chance to change — fall through and ask again.
    }

    try {
      final queuedAt = DateTime.now();
      _queued++;
      // A slot that never arrives has to say so ITSELF. The line below only prints once the wait is
      // over, so a lane that hangs forever prints nothing at all — and "hung lane", "long queue" and
      // "no request made" then look identical from the outside. That ambiguity cost an evening.
      var binnen = false;
      unawaited(Future<void>.delayed(const Duration(seconds: 5)).then((_) {
        if (binnen) return;
        laneTrace?.call('  [$lane] WACHT AL 5s op een slot voor ${Uri.parse(url).path} '
            '(nog $_queued in de rij)');
      }));
      await laneSlot(lane, gap);
      binnen = true;
      _queued--;
      final wachtte = DateTime.now().difference(queuedAt);
      // Only when it actually cost something. A lane that hands out slots promptly says nothing, and
      // this file must not become the thing that fills warm.log.
      if (wachtte.inMilliseconds > 1500) {
        laneTrace?.call('  [$lane] ${wachtte.inSeconds}s in de rij '
            '(nog $_queued wachtend) voor ${Uri.parse(url).path}');
      }
      final r = await http
          .get(Uri.parse(url), headers: {'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      // 404 from the Cover Art Archive means this pressing has no scans. Very common, and not a
      // failure — it is the signal to fall back to Discogs.
      if (r.statusCode != 200) {
        if (r.statusCode != 404) transportErrors++;
        await _writeMiss(url, notFound: r.statusCode == 404);
        return null;
      }
      final body = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (body is! Map<String, dynamic>) {
        transportErrors++;
        await _writeMiss(url, notFound: false);
        return null;
      }
      await _writeCache(url, body);
      return body;
    } catch (_) {
      transportErrors++;
      await _writeMiss(url, notFound: false);
      return null;
    }
  }

  /// Requests that came back without a usable answer for a reason other than "this does not exist".
  ///
  /// A timeout, a DNS failure, a 503, a body that is not JSON — every one of those arrives at the
  /// caller as the same `null` a clean 404 produces, because [_get] swallows everything and never
  /// throws. Anything that needs to tell "the network is broken" from "the catalogue has never heard
  /// of this record" has to read this; there is no exception to catch.
  ///
  /// That distinction is not academic. The warmer's outage guard exists so that one offline launch
  /// cannot mark a whole library as "nothing found" for a day, and a guard that reads exceptions
  /// reads something that never happens.
  ///
  /// Static and monotonic: callers snapshot it before a lookup and compare after. A 404 deliberately
  /// does not count — the Cover Art Archive answers 404 for most pressings, and that is an answer.
  static int transportErrors = 0;

  Future<Map<String, dynamic>?> _ws(String url) => _get(url, lane: 'ws', gap: _wsGap);

  // ── Cache ───────────────────────────────────────────────────────────────────
  // The data barely changes and the request budget is the scarce thing, so everything fetched is
  // kept. Once a library has been browsed it can be browsed again offline.
  String get _dir => '$appDir${Platform.pathSeparator}musicbrainz';

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

  // ── Remembering a "no" ──────────────────────────────────────────────────────
  // Only answers used to be kept, so a 503 from the rate limiter, a timeout, or one offline moment
  // left nothing behind and the whole six-request chain was paid again at the next album open —
  // forever, because it never got far enough to cache anything. A refusal is information too.
  //
  // Two lifetimes, because two different things are being remembered. "This pressing has no scans"
  // is a fact about the archive and rarely changes; "the server would not talk to me" is about this
  // minute, and holding on to it for a day would leave the app blind long after the outage passed.
  static const _missKey = '_miss';
  static const _notFoundKey = '_notfound';
  static const _missKeepFound = Duration(days: 7);
  static const _missKeepFlaky = Duration(hours: 1);

  /// How long ago this entry recorded a refusal, or null if it is a real answer.
  ///
  /// A marker is exactly `{_miss: ms}` plus an optional flag, so it cannot be confused with a
  /// MusicBrainz document — which is never that small and never carries these keys.
  static Duration? _missAge(Map<String, dynamic> j) {
    final ts = j[_missKey];
    if (ts is! num || j.length > 2) return null;
    return Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - ts.toInt());
  }

  static bool _isNotFound(Map<String, dynamic> j) => j[_notFoundKey] == true;

  Future<void> _writeMiss(String url, {required bool notFound}) => _writeCache(url, {
        _missKey: DateTime.now().millisecondsSinceEpoch,
        if (notFound) _notFoundKey: true,
      });

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

  /// The URL for a release-group browse. Built in one place so a test can ask for the same string
  /// this does, instead of being a copy that drifts.
  ///
  /// The parameter ORDER is load-bearing. The disk cache is keyed on sha1 of the whole URL, so
  /// reordering the query string silently throws away every cached browse on every machine.
  @visibleForTesting
  String editionsUrl(String releaseGroupId, {int max = 100, bool tracklists = false}) =>
      '$_root/release?release-group=${releaseGroupId.trim()}'
      '&fmt=json&inc=media+labels+artist-credits${tracklists ? '+recordings' : ''}&limit=$max';

  /// Every pressing of a record, in one request.
  ///
  /// With [tracklists] the browse also asks for `recordings`, and every pressing comes back with
  /// its tracks already in it. That removes four of the six requests an album used to cost: the
  /// browse without it returns `media[].track-count` but no `media[].tracks`, so [tracklistOf] had
  /// to fetch each shortlisted pressing separately at 1.1 s apart. Measured: the bigger browse is
  /// 145 kB against 18 kB and takes 0.33 s against 0.21 s — still faster than ONE of the four
  /// lookups it replaces. [MbRelease.from] parses it unchanged.
  ///
  /// Off by default: the pressing gallery ([editionChoices]) wants the small answer.
  Future<List<MbRelease>> editionsOf(String releaseGroupId,
      {int max = 100, bool tracklists = false}) async {
    if (releaseGroupId.trim().isEmpty) return const [];
    List<MbRelease> parse(Map<String, dynamic>? body) => [
          for (final r in (body?['releases'] as List<dynamic>? ?? const []))
            if (r is Map<String, dynamic>) MbRelease.from(r),
        ];

    if (!tracklists) {
      return orderByPreference(parse(await _ws(editionsUrl(releaseGroupId, max: max))));
    }

    final rich = await _ws(editionsUrl(releaseGroupId, max: max, tracklists: true));
    var out = parse(rich);

    // The server caps a browse at roughly 500 tracks total and truncates SILENTLY — `release-count`
    // keeps reporting the true number. Measured on Thriller: 41 of 85 come back. That matters
    // because the shortlist ranks over ALL pressings, so a truncated roster could pick a different
    // pressing than before. Never split mid-release, though: what does come back is complete.
    final total = (rich?['release-count'] as num?)?.toInt() ?? 0;
    // `rich == null` is its own case and NOT a special one to skip: the big request failed outright
    // — a timeout, a 503, no network — and that is exactly when the smaller one is worth trying.
    // Folding it into the arithmetic below does the opposite of what it looks like: `total` is then
    // 0, `0 < 0` is false, and a failed browse silently returns nothing where the old code would
    // have returned the roster. A machine with no network passed this locally and CI caught it.
    final truncated = rich == null || out.length < (total < max ? total : max);
    if (truncated) {
      // Fetch the plain roster for the full, correctly ordered list, and graft the tracklists we
      // already paid for onto it by mbid. Iterating the PLAIN list is the point: orderByPreference
      // sorts, Dart's sort is not stable, and a record with genuinely tied pressings has its winner
      // decided by input order. Same order in, same pressing out.
      final plain = parse(await _ws(editionsUrl(releaseGroupId, max: max)));
      if (plain.isNotEmpty) {
        final withTracks = {for (final r in out) r.mbid: r};
        out = [for (final r in plain) withTracks[r.mbid] ?? r];
      }
    }
    return orderByPreference(out);
  }

  /// CD first, digital last, documented before stubs — the shared preference in
  /// [releaseFormatOrder], applied to MusicBrainz's own format names.
  ///
  /// [expectedTracks] drops the pressings that are a different record: a single or a sampler filed
  /// under the same release group, or a box set that carries two albums. Both directions matter —
  /// checking only for "too few" let *Discovery* land on a double CD that was also Homework.
  /// Which release group describes this record — the album, or the single of the same name?
  ///
  /// They exist side by side more often than you would think. Daniel Bedingfield has two groups
  /// called "Gotta Get Thru This": a Single from 2001 that is eight versions of one song, and the
  /// Album from 2002 that the song is track 3 of. Taking the first group that is not a compilation
  /// picked the single, so a sixteen-track record was described by a two-track sleeve — and the
  /// album's own cover could not be found either.
  ///
  /// [isCompilation] cannot answer this: it reads the SECONDARY types, and Single is a PRIMARY one.
  ///
  /// Asked from what the library already decided — a record filed as an album wants an Album group,
  /// a loose track wants a Single. Falls back rather than refusing: a record described by the wrong
  /// kind of group is still more use than a record with no tracklist at all.
  static MbReleaseGroup? pickReleaseGroup(List<MbReleaseGroup> groups, {required bool single}) {
    if (groups.isEmpty) return null;
    final want = single ? 'single' : 'album';
    final studio = groups.where((g) => !g.isCompilation);
    return studio.where((g) => g.primaryType.toLowerCase() == want).firstOrNull ??
        studio.firstOrNull ??
        groups.first;
  }

  static List<MbRelease> orderByPreference(List<MbRelease> all, {int expectedTracks = 0}) {
    final out = [
      for (final r in all)
        // Dezelfde formule als Discogs gebruikt, uit release_format.dart. Hier stond een eigen kopie
        // van precies dezelfde ongelijkheden.
        if (r.mbid.isNotEmpty &&
            (expectedTracks <= 0 || r.trackCount == 0 || fitsTrackCount(r.trackCount, expectedTracks)))
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

  // ── Searching ───────────────────────────────────────────────────────────────
  //
  // What MusicBrainz is and is not good at, measured rather than assumed.
  //
  // It has NO popularity signal whatsoever — its scoring is pure Lucene text matching. Searching
  // "thriller" returns Part Chimp, Swoop and Eddie & the Hot Rods before Michael Jackson, and
  // "quit playing games" returns Mar.Ko and The Baseballs before the Backstreet Boys. Used as a
  // bare search box it would make finding a famous record HARDER, not easier.
  //
  // Its strength is the opposite shape: given an artist, it hands over everything. The complete
  // 24-album Backstreet Boys discography comes back in 71 ms, including the regional oddities
  // ("Very Best 2000", "Bubble Tea Jams 2000") that a streaming catalogue has never heard of.
  //
  // So queries are scoped by artist wherever an artist can be found. `artist:"Michael Jackson" AND
  // releasegroup:"Thriller"` puts the right record first at score 100; the same query without the
  // artist does not find it at all.

  /// Artists matching a name. The one search MusicBrainz is unambiguously good at as-is.
  Future<List<MbArtist>> searchArtists(String q, {int max = 12}) async {
    if (q.trim().isEmpty) return const [];
    final body = await _ws(
        '$_root/artist/?query=${Uri.encodeQueryComponent(_lucene(q.trim()))}&fmt=json&limit=$max');
    final list = body?['artists'] as List<dynamic>? ?? const [];
    return [
      for (final a in list)
        if (a is Map<String, dynamic>) MbArtist.from(a)
    ];
  }

  /// The single best artist match for a name, or null.
  Future<MbArtist?> resolveArtist(String name) async {
    final hits = await searchArtists(name, max: 5);
    if (hits.isEmpty) return null;
    // An exact name match beats a higher-scoring near-miss: searching "Backstreet" must not
    // resolve to "Backstreet Girls" because it scored well on a shared word.
    final want = name.trim().toLowerCase();
    for (final a in hits) {
      if (a.name.toLowerCase() == want) return a;
    }
    return hits.first;
  }

  /// Records — not pressings — matching a title, optionally scoped to an artist.
  ///
  /// A release group is the RECORD; the releases under it are its pressings. Searching groups is
  /// what makes one card per album possible instead of one per pressing.
  Future<List<MbReleaseGroup>> searchReleaseGroups(String album,
      {String artist = '', int max = 25}) async {
    if (album.trim().isEmpty) return const [];
    final q = artist.trim().isEmpty
        ? 'releasegroup:"${_lucene(album.trim())}"'
        : 'artist:"${_lucene(artist.trim())}" AND releasegroup:"${_lucene(album.trim())}"';
    final body =
        await _ws('$_root/release-group/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=$max');
    final list = body?['release-groups'] as List<dynamic>? ?? const [];
    return [
      for (final g in list)
        if (g is Map<String, dynamic>) MbReleaseGroup.from(g)
    ];
  }

  /// Everything an artist released, by their id. Complete where a streaming catalogue is partial.
  Future<List<MbReleaseGroup>> discographyOf(String artistMbid, {int max = 100}) async {
    if (artistMbid.trim().isEmpty) return const [];
    final body = await _ws(
        '$_root/release-group?artist=${artistMbid.trim()}&fmt=json&limit=$max');
    final list = body?['release-groups'] as List<dynamic>? ?? const [];
    final out = [
      for (final g in list)
        if (g is Map<String, dynamic>) MbReleaseGroup.from(g)
    ];
    // Albums before singles and compilations, then newest first — the shape a discography reads in.
    out.sort((a, b) {
      final byKind = _kindRank(a.primaryType).compareTo(_kindRank(b.primaryType));
      if (byKind != 0) return byKind;
      return (b.firstDate ?? '').compareTo(a.firstDate ?? '');
    });
    return out;
  }

  static int _kindRank(String t) {
    switch (t.toLowerCase()) {
      case 'album':
        return 0;
      case 'ep':
        return 1;
      case 'single':
        return 2;
      default:
        return 3;
    }
  }

  /// Recordings matching a title, scoped to an artist where one is known.
  Future<List<MbRecording>> searchRecordings(String title,
      {String artist = '', int max = 25}) async {
    if (title.trim().isEmpty) return const [];
    final q = artist.trim().isEmpty
        ? 'recording:"${_lucene(title.trim())}"'
        : 'artist:"${_lucene(artist.trim())}" AND recording:"${_lucene(title.trim())}"';
    final body =
        await _ws('$_root/recording/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=$max');
    final list = body?['recordings'] as List<dynamic>? ?? const [];
    return [
      for (final r in list)
        if (r is Map<String, dynamic>) MbRecording.from(r)
    ];
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

  /// Every pressing of a record, as choices the picker can offer.
  ///
  /// One release-group search plus one browse names every pressing — where the Discogs path needs
  /// a request per pressing before it can say anything at all. Measured on Adele's *30*: 289 ms
  /// for all twelve, against roughly thirteen seconds.
  ///
  /// [detail] caps how many get their scans and tracklist fetched. Those cost a request each and
  /// the browse can return a hundred pressings, so the rest are listed on what the browse already
  /// said and filled in when tapped. Without the cap the dialog would take two minutes.
  /// [onPartial] is called with the list as it fills in: once as soon as the pressings are named,
  /// then again each time a pressing's scans arrive. Same contract as the Discogs side, so the
  /// gallery can treat both sources the same way.
  Future<List<ReleaseChoice>> editionChoices(String artist, String album,
      {int max = 40, String? pinnedMbid, void Function(List<ReleaseChoice>)? onPartial}) async {
    final out = <ReleaseChoice>[];
    final seen = <String>{};

    // EVERY offered pressing gets its scans looked up — a row saying "no cd-scan" has to mean the
    // archive was asked and had none, never that we stopped looking. That used to be capped at the
    // first eight rows because the tracklist was fetched in the same breath, and a tracklist costs a
    // request on the 1-per-second webservice lane. The scans come from the Cover Art Archive, a
    // different host on its own 250 ms lane, so asking for all of them is cheap. The tracklist is
    // now fetched only when something actually wants it — see [tracklistOf], which the
    // "take this numbering" action already calls on demand.
    /// [known] is whether this pressing's scans have actually been looked up. Without it a row that
    /// is merely still loading claims it HAS no back and no disc, which is a different statement
    /// and a false one — see [ReleaseChoice.detailed].
    ReleaseChoice? rowFor(MbRelease r, List<MbImage> images,
        {bool always = false, bool known = true}) {
      ChoiceImage? front, back, disc;
      for (final i in images) {
        // The archive states what each scan IS — Front, Back, Medium — so nothing here is inferred
        // from pixels. That matters: the Escape CD is a white disc on a white scanner bed, and no
        // brightness test can tell it from a blank booklet page. A stated fact can.
        front ??= i.isFront ? ChoiceImage(i.full, i.thumb) : null;
        back ??= i.isBack ? ChoiceImage(i.full, i.thumb) : null;
        disc ??= i.isDisc ? ChoiceImage(i.full, i.thumb) : null;
      }
      // A stub nobody has filled in: no format, no country, no catalogue number, no year AND no
      // scans. It would draw as a blank row offering nothing to choose on. The pinned pressing is
      // shown regardless — the user's own choice is never hidden, however thin its entry.
      final blank = r.format.isEmpty &&
          (r.country ?? '').isEmpty &&
          (r.catno ?? '').isEmpty &&
          r.year == null &&
          front == null &&
          back == null &&
          disc == null;
      if (blank && !always) return null;
      return ReleaseChoice(
        source: EditionSource.musicbrainz,
        mbid: r.mbid,
        format: r.format,
        label: r.label,
        catno: r.catno,
        country: r.country,
        barcode: r.barcode,
        year: r.year,
        front: front,
        back: back,
        disc: disc,
        detailed: known,
      );
    }

    // Every pressing worth offering, in the order it should be shown, before a single scan is
    // fetched. Naming them costs nothing beyond the browse that already ran.
    final candidates = <(MbRelease, bool)>[];
    void offer(MbRelease r, {bool always = false}) {
      if (r.mbid.isEmpty || !seen.add(r.mbid)) return;
      candidates.add((r, always));
    }

    // The pressing the user already chose is always offered, whether or not it would have made the
    // cut — their own choice missing from the list of choices is the one unacceptable outcome.
    String? pinnedGroup;
    if (pinnedMbid != null && pinnedMbid.isNotEmpty) {
      final p = await release(pinnedMbid);
      if (p != null) {
        offer(p, always: true);
        // A lookup already asks for `release-groups`, so this costs nothing extra — and it is the
        // answer the search below spends ten to twenty seconds arriving at.
        pinnedGroup = (p.releaseGroupId ?? '').isEmpty ? null : p.releaseGroupId;
      }
    }

    // With a pin there is nothing to search FOR: the user named a pressing, and a pressing belongs
    // to exactly one release group, which the lookup above already told us. That matters because
    // MusicBrainz's `?query=` endpoint is by far the slowest thing in opening this dialog —
    // measured on the same album, four times over: 44 ms, 12.1 s, 15.9 s, 17.9 s, while resolving
    // the group straight from the pinned release took 48–232 ms. Nothing was shown until it
    // answered, so the gallery looked broken for a quarter of a minute at a time.
    final List<MbReleaseGroup> ranked;
    if (pinnedGroup != null) {
      ranked = const [];
    } else {
      final groups = await searchReleaseGroups(album, artist: artist);
      if (groups.isEmpty) return out;
      // A compilation carrying the album's name is not the album. Studio records first.
      ranked = [...groups]..sort((a, b) {
        final byComp = (a.isCompilation ? 1 : 0).compareTo(b.isCompilation ? 1 : 0);
        if (byComp != 0) return byComp;
        return _kindRank(a.primaryType).compareTo(_kindRank(b.primaryType));
      });
    }

    // The pinned pressing's own group first, then the ranked search results — which is only ever one
    // or the other, but written as one loop so the browse and the row cap behave identically.
    for (final g in [
      if (pinnedGroup != null) MbReleaseGroup(pinnedGroup, album, artist, '', 'Album'),
      ...ranked.take(2),
    ]) {
      if (candidates.length >= max) break;
      // No track-count filter here, deliberately. Every release in a group IS this record, so a
      // count that differs is a different PRESSING — the 16-track European edition of Escape, the
      // 13-track American one — and those are precisely the choices worth offering. Filtering them
      // is what hid the only pressing whose disc had been scanned.
      for (final e in orderByPreference(await editionsOf(g.mbid))) {
        if (candidates.length >= max) break;
        offer(e);
      }
    }

    // Rows first, scans afterwards.
    //
    // Naming the pressings costs nothing beyond the browse that already ran, so the list can be on
    // screen while the archive is still being asked about the artwork. It used to be the other way
    // round — every scan lookup finished before a single row was built — and since a Cover Art
    // Archive lookup takes one to two seconds, that was most of the wait spent on a spinner.
    //
    // A row only ever APPEARS. Before its scans are known a pressing is offered on its own details
    // (format, country, catalogue number, year); one with none of those waits until its scans turn
    // up, because a row that shows itself and then vanishes is worse than one that arrives late.
    final scans = <String, List<MbImage>>{};
    List<ReleaseChoice> build() {
      final rows = <ReleaseChoice>[];
      for (final (r, always) in candidates) {
        if (rows.length >= max) break;
        final asked = scans.containsKey(r.mbid);
        final row = rowFor(r, scans[r.mbid] ?? const [], always: always, known: asked);
        if (row != null) rows.add(row);
      }
      return rows;
    }

    onPartial?.call(build());
    await Future.wait([
      for (final (r, _) in candidates)
        art(r.mbid).then((imgs) {
          scans[r.mbid] = imgs;
          onPartial?.call(build());
        }).catchError((_) {
          scans[r.mbid] = const <MbImage>[];
        }),
    ]);
    out.addAll(build());
    return out;
  }

  /// The tracklist of a pressing, fetching it only if the caller does not already have it.
  Future<List<ChoiceTrack>> tracklistOf(MbRelease r) async {
    final full = r.tracks.isNotEmpty ? r : await release(r.mbid);
    return [
      for (final t in (full?.tracks ?? const <MbTrack>[]))
        if (t.title.isNotEmpty)
          ChoiceTrack(t.position, t.title, t.seconds, disc: t.disc, artist: t.artist)
    ];
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
