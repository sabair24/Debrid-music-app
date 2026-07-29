/// Asking what a recording IS, when no catalogue can be asked by name.
///
/// Eight records in this library come back empty from both MusicBrainz and Discogs, and they are all
/// the same kind of thing: *Serious Beats 51*, *Club Kaos 34*, *Vlaamse Diva's*, *Kamping Kitsch
/// Club Box 2018-2019*. "Various Artists" says nothing and the title is generic, so a search on
/// those two words is not a question — it is a shrug, and both catalogues answer accordingly.
///
/// Fingerprints turn the question round. Instead of asking "which album is called this", ask each
/// FILE what recording it is, and then see which release the answers agree on. A compilation is
/// exactly the case where that works best: twelve tracks that individually point at a dozen
/// different release groups, but at ONE they all share.
///
/// **The vote is the whole idea**, and [bestReleaseGroup] is deliberately pure so it can be tested
/// without a socket. One track matching a release group means nothing — every track appears on
/// something. Ten of twelve agreeing is an answer.
///
/// Needs a free application key from acoustid.org, and does nothing at all without one. Everything
/// else fingerprinting does in this app — telling two rips of one song apart from two different
/// songs — happens on this machine and needs no key and no network.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fingerprint.dart';
import 'settings.dart';

/// What AcoustID says one file is: the recording, and the releases it appears on.
class AcoustIdMatch {
  const AcoustIdMatch(this.score, this.recordingId, this.title, this.releaseGroups,
      {this.artist = ''});

  /// How sure AcoustID is, 0..1. Its own number, not ours.
  final double score;
  final String recordingId;
  final String title;

  /// Everyone credited, joined the way the tag would read it. Empty when the recording carries no
  /// artist — which happens, and is why nothing downstream may assume this is filled.
  ///
  /// Kept beside the title because for a loose file the pair IS the answer: a track sitting in the
  /// root under a compilation's name is not going to be identified by its album, only by what it is.
  final String artist;

  /// Release-group MBIDs this recording appears on. The raw material for the vote.
  final List<String> releaseGroups;
}

/// Which release group do these tracks agree on?
///
/// [perTrack] is one list of candidate release-group MBIDs per file. Returns the group that the most
/// files point at, or null when nothing reaches [minShare] of them.
///
/// A share rather than a count, because a two-track single and a fifty-track box set are the same
/// question at different sizes. Two thirds is strict enough that a compilation whose tracks happen to
/// share one popular album cannot win it, and loose enough to survive the tracks AcoustID has never
/// heard of — which on a Belgian hardcore compilation is a real fraction of them.
///
/// Each file votes at most ONCE per group. Without that a single file listed on eight pressings of
/// the same release group would outvote every other file by itself.
String? bestReleaseGroup(List<List<String>> perTrack, {double minShare = 2 / 3}) {
  final met = perTrack.where((l) => l.isNotEmpty).toList();
  if (met.isEmpty) return null;
  final stemmen = <String, int>{};
  for (final l in met) {
    for (final g in l.toSet()) {
      stemmen[g] = (stemmen[g] ?? 0) + 1;
    }
  }
  String? beste;
  var hoogste = 0, evenveel = 0;
  for (final e in stemmen.entries) {
    if (e.value > hoogste) {
      hoogste = e.value;
      beste = e.key;
      evenveel = 1;
    } else if (e.value == hoogste) {
      evenveel++;
    }
  }
  // A tie is not a winner, and that rule is what makes a single file safe.
  //
  // "Vlaamse Diva's" is one file. Every release group that one recording appears on then has exactly
  // one vote, so "the highest" is whichever the map happened to hand over first — a guess wearing a
  // number. One track appears on a dozen compilations; that is not evidence about which record this
  // folder is. Requiring a STRICT majority makes a lone file abstain by construction, without a
  // special case for it.
  if (evenveel != 1) return null;
  // Measured against the files that got an ANSWER, not against every file in the folder: a
  // compilation where AcoustID knows six of twelve tracks and all six agree is a solid answer, and
  // counting the six it never heard of as votes against would throw it away.
  return hoogste >= (met.length * minShare) ? beste : null;
}

class AcoustIdService {
  AcoustIdService(this.settings);
  final AppSettings settings;

  bool get available => settings.acoustidKey.trim().isNotEmpty;

  /// AcoustID asks for no more than three requests a second. One at a time with a third of a second
  /// between them is well inside that and simpler than a burst allowance — a dozen tracks is four
  /// seconds, once, and the answer is cached by the catalogue lookups that follow.
  static const _gap = Duration(milliseconds: 350);
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _turn = Future.value();

  /// Somewhere to write what this is doing. Set by the warmer, like the other services.
  static void Function(String)? trace;

  /// What to ask for back. Separated by a SPACE, and that one character is the difference between
  /// an answer and silence.
  ///
  /// The documentation writes `meta=recordings+releasegroups`, but that is a URL, where `+` IS a
  /// space — AcoustID splits this value on spaces. Sent as a form field, Dart encodes a literal plus
  /// as %2B, so the server received one unknown word "recordings+releasegroupids" and answered
  /// exactly as it should: a perfect fingerprint match, score 0.9998 on Michael Jackson, and no
  /// metadata whatsoever. From the outside that reads as "AcoustID does not know this record", which
  /// is how eight compilations came back "0 herkend" with nothing in the log to say why.
  static const String metaParam = 'recordings releasegroupids';

  static Future<void> _slot() {
    final slot = _turn.then((_) async {
      final since = DateTime.now().difference(_lastCall);
      // Never longer than the gap itself — a clock that steps backwards would otherwise swallow the
      // whole jump. The same trap that hung the Discogs lane.
      final wacht = since.isNegative || since > _gap ? Duration.zero : _gap - since;
      if (wacht > Duration.zero) await Future<void>.delayed(wacht);
      _lastCall = DateTime.now();
    });
    _turn = slot.catchError((_) {});
    return slot;
  }

  /// What one file is, according to AcoustID. Empty on any failure — never throws.
  Future<List<AcoustIdMatch>> identify(Fingerprint fp) async {
    final key = settings.acoustidKey.trim();
    if (key.isEmpty) return const [];
    final code = fp.compressed;
    if (code == null || code.isEmpty) return const [];

    try {
      await _slot();
      // POST, not GET: a fingerprint is a few kilobytes of base64 and puts a GET well past what
      // proxies will carry. The key travels in the body for the same reason it belongs there — it is
      // not part of the address of anything.
      final r = await http
          .post(
            Uri.parse('https://api.acoustid.org/v2/lookup'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'client': key,
              'duration': fp.seconds.round().toString(),
              'fingerprint': code,
              'meta': metaParam,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        trace?.call('  [acoustid] HTTP ${r.statusCode}');
        return const [];
      }
      final body = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (body is! Map<String, dynamic>) return const [];
      if (body['status'] != 'ok') {
        trace?.call('  [acoustid] ${body['error']?['message'] ?? body['status']}');
        return const [];
      }
      return parseLookup(body);
    } catch (e) {
      trace?.call('  [acoustid] $e');
      return const [];
    }
  }

  /// The shape of an answer, pulled out so it can be tested against a recorded response.
  static List<AcoustIdMatch> parseLookup(Map<String, dynamic> body) {
    // `is List`, never `as List`. A cast turns a field that came back the wrong shape into an
    // exception thrown out of a parser, and everything upstream here is written on the promise that
    // a lookup failing is an empty answer and not a crash.
    List<dynamic> lijst(Object? v) => v is List ? v : const [];

    final out = <AcoustIdMatch>[];
    for (final r in lijst(body['results'])) {
      if (r is! Map<String, dynamic>) continue;
      final score = (r['score'] as num?)?.toDouble() ?? 0;
      for (final rec in lijst(r['recordings'])) {
        if (rec is! Map<String, dynamic>) continue;
        final id = '${rec['id'] ?? ''}';
        if (id.isEmpty) continue;
        final groups = <String>[];
        // `releasegroupids` gives bare strings; `releasegroups` gives objects. Accept both, because
        // which one comes back depends on the meta asked for and that is easy to change by accident.
        for (final g in lijst(rec['releasegroupids'])) {
          final s = '$g'.trim();
          if (s.isNotEmpty) groups.add(s);
        }
        for (final g in lijst(rec['releasegroups'])) {
          if (g is Map<String, dynamic>) {
            final s = '${g['id'] ?? ''}'.trim();
            if (s.isNotEmpty) groups.add(s);
          }
        }
        // "artists" is a list because a duet is two credits, and joining them with the ampersand
        // the tag would use keeps the answer usable as-is.
        final wie = <String>[];
        for (final a in lijst(rec['artists'])) {
          if (a is Map<String, dynamic>) {
            final n = '${a['name'] ?? ''}'.trim();
            if (n.isNotEmpty) wie.add(n);
          }
        }
        out.add(AcoustIdMatch(score, id, '${rec['title'] ?? ''}', groups,
            artist: wie.join(' & ')));
      }
    }
    // Best first: a caller that only wants one answer should get the likeliest.
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}
