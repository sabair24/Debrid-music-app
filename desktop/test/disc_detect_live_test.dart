@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:debridmusic/artwork.dart';

/// Runs [looksLikeDisc] over every real scan of two releases, using the Cover Art Archive's own
/// labels as the answer key: `Medium` IS the disc, everything else is not.
///
/// This is the honest way to judge a detector that has to work on pixels — the Discogs path has no
/// stated types, so it must get this right from the image alone. The releases are chosen to cover
/// the case that used to fail: Enrique's *Escape* CD is a WHITE disc on a white scanner bed, and its
/// own booklet pages are white too.
const _ua = 'DebridMusic/1.0 ( https://github.com/sabair24/Debrid-music-app )';

Future<List<({String types, bool isDisc, bool guessed})>> _judge(String mbid) async {
  final r = await http.get(Uri.parse('https://coverartarchive.org/release/$mbid'),
      headers: {'User-Agent': _ua});
  final out = <({String types, bool isDisc, bool guessed})>[];
  if (r.statusCode != 200) return out;
  for (final i in (jsonDecode(r.body)['images'] as List)) {
    final types = (i['types'] as List).map((e) => e.toString()).toList();
    final url = (i['thumbnails']?['500'] ?? i['image']).toString();
    final b = await http.get(Uri.parse(url), headers: {'User-Agent': _ua});
    if (b.statusCode != 200) continue;
    out.add((
      types: types.join(','),
      isDisc: types.contains('Medium'),
      guessed: looksLikeDisc(b.bodyBytes),
    ));
  }
  return out;
}

void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('every disc is found and nothing else is mistaken for one', () async {
    final all = [
      ...await _judge('f8920e1b-5552-4301-85ac-cc9b0ab6e454'), // Escape — the white CD
      ...await _judge('ce4eb4e1-e490-4808-9cc6-d0c0d8001ff0'), // Millennium — two discs, 12 pages
    ];
    expect(all.length, greaterThan(20), reason: 'both releases carry a lot of scans');

    final discs = all.where((x) => x.isDisc).toList();
    final rest = all.where((x) => !x.isDisc).toList();
    expect(discs, isNotEmpty);

    final missed = discs.where((x) => !x.guessed).map((x) => x.types).toList();
    final wrong = rest.where((x) => x.guessed).map((x) => x.types).toList();

    expect(missed, isEmpty, reason: 'these discs went unrecognised: $missed');
    expect(wrong, isEmpty, reason: 'these were mistaken for a disc: $wrong');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
