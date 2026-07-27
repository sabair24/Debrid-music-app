import 'dart:convert';
import 'package:http/http.dart' as http;

import 'settings.dart';

/// One person credited on a release.
class Credit {
  final String role;
  final String name;
  const Credit(this.role, this.name);
}

/// A release someone worked on — the answer to "what else did they make".
class CreditedWork {
  final String title;
  final String? year;
  final String? artist;
  const CreditedWork(this.title, {this.year, this.artist});
}

/// Who made a record, and what else those people made.
///
/// Two sources because they answer different questions and neither does both well:
/// * Discogs knows a release in depth — producer, engineer, who played the bass — and covers
///   almost everything ever pressed. But asking it "what else did this producer do" means
///   trawling its search, which is rate-limited and noisy.
/// * Wikidata answers exactly that reverse question with one query, and correctly: Quincy Jones
///   returns Thriller, Bad, Off the Wall, The Dude. It only knows the notable half — measured on
///   this library, 6 of 9 albums have a producer — which is fine, because a name is only clickable
///   when there is something behind it.
///
/// Roon does this from AllMusic, which is licensed and not available here.
class CreditsService {
  final AppSettings settings;
  CreditsService(this.settings);

  static const _ua = 'DebridMusic/0.3 ( https://github.com/sabair24/Debrid-music-app )';

  /// Roles worth showing. A full Discogs credit list runs to photographers and sleeve designers;
  /// these are the ones that say something about how the record sounds.
  static final _interesting = RegExp(
    r'^(producer|co-producer|executive[- ]producer|written[- ]by|composed[- ]by|arranged[- ]by|'
    r'mixed[- ]by|mastered[- ]by|recorded[- ]by|featuring|remix)',
    caseSensitive: false,
  );

  final Map<String, List<Credit>> _cache = {};

  /// The people behind an album, most interesting roles first.
  Future<List<Credit>> forAlbum(String artist, String album) async {
    final key = '${artist.toLowerCase()}|${album.toLowerCase()}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final token = settings.discogsToken.trim();
    if (token.isEmpty) return const [];

    try {
      final headers = {'User-Agent': _ua, 'Authorization': 'Discogs token=$token'};

      /// The strict field search misses more than you'd think — Thriller came back empty on
      /// artist+release_title while a plain query found it at once — so fall back to that.
      Future<List?> search(String url) async {
        final r = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) return null;
        return (jsonDecode(utf8.decode(r.bodyBytes))['results'] as List?) ?? const [];
      }

      // Gather candidates from both searches. Not every pressing carries credits — Thriller's
      // top strict hit had none at all — so try a few and keep the first that actually does.
      final ids = <int>[];
      for (final url in [
        'https://api.discogs.com/database/search?type=release&per_page=3'
            '&artist=${Uri.encodeComponent(artist)}&release_title=${Uri.encodeComponent(album)}',
        'https://api.discogs.com/database/search?type=release&per_page=3'
            '&q=${Uri.encodeComponent('$artist $album')}',
      ]) {
        for (final r in (await search(url)) ?? const []) {
          final id = (r as Map)['id'];
          if (id is int && !ids.contains(id)) ids.add(id);
        }
      }
      if (ids.isEmpty) return _cache[key] = const [];

      for (final id in ids.take(4)) {
        final r = await http
            .get(Uri.parse('https://api.discogs.com/releases/$id'), headers: headers)
            .timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) continue;
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

        final out = <Credit>[];
        final seen = <String>{};
        for (final e in (j['extraartists'] as List?) ?? const []) {
          final m = e as Map;
          final role = ((m['role'] ?? '') as String).trim();
          // Discogs writes "Producer", but also "Recorded By, Mixed By" — take the leading role.
          final lead = role.split(',').first.trim();
          if (!_interesting.hasMatch(lead)) continue;
          // "Louis Johnson (2)" — the number disambiguates on Discogs, it isn't part of the name.
          final name = ((m['name'] ?? '') as String).replaceAll(RegExp(r'\s*\(\d+\)$'), '').trim();
          if (name.isEmpty || !seen.add('$lead|${name.toLowerCase()}')) continue;
          out.add(Credit(lead, name));
        }
        if (out.isEmpty) continue; // this pressing lists nobody — try the next
        out.sort((a, b) => _rank(a.role).compareTo(_rank(b.role)));
        return _cache[key] = out;
      }
      return _cache[key] = const [];
    } catch (_) {
      return const [];
    }
  }

  static int _rank(String role) {
    final r = role.toLowerCase();
    if (r.startsWith('producer')) return 0;
    if (r.contains('producer')) return 1;
    if (r.startsWith('written') || r.startsWith('composed')) return 2;
    if (r.startsWith('featuring')) return 3;
    if (r.startsWith('mixed') || r.startsWith('mastered') || r.startsWith('recorded')) return 4;
    return 5;
  }

  final Map<String, List<CreditedWork>> _worksCache = {};

  /// Everything Wikidata says this person produced. Empty for people it doesn't know — which is
  /// how the UI decides whether their name is worth making clickable.
  /// The records this person is credited on, and whether the lookup actually SUCCEEDED.
  ///
  /// Every failure used to be cached as an empty list: a Wikidata timeout, a 503, a network drop —
  /// all remembered as "this person produced nothing", for the rest of the session, and shown to the
  /// user as a fact about the person. Wikidata's SPARQL endpoint times out often enough on prolific
  /// producers that this was the common case rather than the rare one.
  ///
  /// A genuine empty answer is still cached, because that IS the answer. A failure is not cached at
  /// all, so opening the page again tries again.
  Future<({List<CreditedWork> works, bool failed})> producedBy(String person) async {
    final key = person.toLowerCase();
    final hit = _worksCache[key];
    if (hit != null) return (works: hit, failed: false);
    try {
      final qid = await _entityFor(person);
      // No entity is a real answer: Wikidata has never heard of this name.
      if (qid == null) return (works: _worksCache[key] = const [], failed: false);
      // DISTINCT, and no performer join: a work with several performers multiplied the rows, and
      // for a prolific producer that grew heavy enough to time out — Quincy Jones returned nothing
      // while a smaller catalogue came back fine.
      final query = '''
SELECT DISTINCT ?workLabel ?date WHERE {
  ?work wdt:P162 wd:$qid .
  OPTIONAL { ?work wdt:P577 ?date }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "nl,en". }
} LIMIT 60''';
      final r = await http.get(
        Uri.parse('https://query.wikidata.org/sparql?format=json&query=${Uri.encodeComponent(query)}'),
        headers: {'User-Agent': _ua, 'Accept': 'application/sparql-results+json'},
      ).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return (works: const <CreditedWork>[], failed: true);
      final rows = (jsonDecode(utf8.decode(r.bodyBytes))['results']?['bindings'] as List?) ?? const [];
      final seen = <String>{};
      final out = <CreditedWork>[];
      for (final row in rows) {
        final m = row as Map;
        final title = (m['workLabel']?['value'] ?? '') as String;
        if (title.isEmpty || title.startsWith('Q')) continue; // unlabelled entity
        final year = (m['date']?['value'] as String?)?.split('-').first;
        if (!seen.add(title.toLowerCase())) continue;
        out.add(CreditedWork(title, year: year));
      }
      out.sort((a, b) => (b.year ?? '').compareTo(a.year ?? ''));
      return (works: _worksCache[key] = out, failed: false);
    } catch (_) {
      // Not cached: a timeout says nothing about this person, and remembering it as "nothing" made
      // the page state that as a fact until the app was restarted.
      return (works: const <CreditedWork>[], failed: true);
    }
  }

  /// The Wikidata entity for a person. Takes the first hit that actually has production credits,
  /// because "Quincy Jones" also matches a foundation CEO and a Guyanese politician.
  Future<String?> _entityFor(String person) async {
    final r = await http.get(
      Uri.parse('https://www.wikidata.org/w/api.php?action=wbsearchentities&format=json&language=en&limit=5'
          '&search=${Uri.encodeComponent(person)}'),
      headers: {'User-Agent': _ua},
    ).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final hits = (jsonDecode(utf8.decode(r.bodyBytes))['search'] as List?) ?? const [];
    for (final h in hits) {
      final desc = (((h as Map)['description'] ?? '') as String).toLowerCase();
      if (desc.contains('producer') || desc.contains('musician') || desc.contains('composer') ||
          desc.contains('singer') || desc.contains('band') || desc.contains('dj')) {
        return h['id'] as String?;
      }
    }
    return hits.isEmpty ? null : (hits.first as Map)['id'] as String?;
  }
}
