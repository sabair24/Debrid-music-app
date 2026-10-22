// De Last.fm-bron zelf: wat elke vraag teruggeeft, de buffer op schijf (zonder de sleutel), en de rem. Saber,
// 22-10-2026: "doe wat zeker beter zou zijn voor de app" — de bekendste nummers, tags, verwante artiesten, luisteraars en
// zijn eigen geschiedenis (10.722 scrobbles, 2017–2023) komen allemaal hiervandaan.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/lastfm.dart';

http.Response _json(Object j) => http.Response.bytes(utf8.encode(jsonEncode(j)), 200);

void main() {
  group('wat elke vraag teruggeeft', () {
    test('artist.getTopTracks: bekendste eerst, met luisteraars', () {
      final n = lastfmTopNummers({
        'toptracks': {
          'track': [
            {
              'name': 'Daar Gaat Ze',
              'listeners': '36681',
              'artist': {'name': 'Clouseau'},
            },
            {
              'name': 'Passie',
              'listeners': '17729',
              'artist': {'name': 'Clouseau'},
            },
            {
              'name': '',
              'listeners': '1',
              'artist': {'name': 'Clouseau'},
            },
          ],
        },
      });
      expect(n, [
        (artiest: 'Clouseau', titel: 'Daar Gaat Ze', luisteraars: 36681),
        (artiest: 'Clouseau', titel: 'Passie', luisteraars: 17729),
      ]);
    });

    test('artist.getTopTags: klein geschreven, alleen met genoeg stemmen', () {
      expect(
        lastfmTags({
          'toptags': {
            'tag': [
              {'name': 'Nederlandstalig', 'count': 100},
              {'name': 'Belgian', 'count': '54'},
              {'name': 'seen live', 'count': 3},
            ],
          },
        }),
        ['nederlandstalig', 'belgian'],
      );
      expect(lastfmTags(null), isEmpty);
    });

    test('artist.getSimilar, track.getInfo, user.getTopTracks en user.getTopArtists', () {
      expect(
        lastfmVerwanteArtiesten({
          'similarartists': {
            'artist': [
              {'name': 'Bart Kaëll', 'match': '1'},
              {'name': 'Sam Gooris', 'match': '0.93'},
            ],
          },
        }),
        [(naam: 'Bart Kaëll', maat: 1.0), (naam: 'Sam Gooris', maat: 0.93)],
      );
      expect(
        lastfmLuisteraars({
          'track': {'listeners': '42526'},
        }),
        42526,
      );
      expect(lastfmLuisteraars({'error': 6}), isNull);
      expect(
        lastfmGebruikerTop({
          'toptracks': {
            'track': [
              {
                'name': 'Billie Jean',
                'playcount': '25',
                'artist': {'name': 'Michael Jackson'},
              },
            ],
          },
        }),
        [(artiest: 'Michael Jackson', titel: 'Billie Jean', keer: 25)],
      );
      expect(
        lastfmGebruikerArtiesten({
          'topartists': {
            'artist': [
              {'name': 'Michael Jackson', 'playcount': '424'},
            ],
          },
        }),
        [(naam: 'Michael Jackson', keer: 424)],
      );
    });
  });

  group('de vraag', () {
    test('met een MusicBrainz-id gaat de naam niet mee: geen naamgenoten', () async {
      Uri? gevraagd;
      final z = LastfmZoeker(
        tussenpoos: Duration.zero,
        client: MockClient((v) async {
          gevraagd = v.url;
          return _json({
            'toptracks': {'track': []},
          });
        }),
      );
      await z.topNummers('Petra', sleutel: 's', mbid: 'e52a3cd0-0000');
      expect(gevraagd!.queryParameters['mbid'], 'e52a3cd0-0000');
      expect(gevraagd!.queryParameters.containsKey('artist'), isFalse);
      await z.topNummers('Clouseau', sleutel: 's');
      expect(gevraagd!.queryParameters, allOf(containsPair('artist', 'Clouseau'), containsPair('autocorrect', '1')));
    });
  });

  group('de buffer', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_lastfm_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: dezelfde vraag binnen de houdbaarheid komt uit de buffer; daarna opnieuw', () async {
      var vragen = 0;
      var nu = DateTime(2026, 10, 22, 17);
      final pad = '${map.path}${Platform.pathSeparator}lastfm';
      LastfmZoeker maak() => LastfmZoeker(
        buffer: pad,
        klok: () => nu,
        tussenpoos: Duration.zero,
        client: MockClient((_) async {
          vragen++;
          return _json({
            'toptags': {
              'tag': [
                {'name': 'eurodance', 'count': 100},
              ],
            },
          });
        }),
      );
      final z = maak();
      expect(await z.tags('2 Fabiola', sleutel: 'geheim-123'), ['eurodance']);
      expect(await z.tags('2 fabiola', sleutel: 'geheim-123'), ['eurodance'], reason: 'hoofdletters tellen niet');
      expect(vragen, 1);
      nu = nu.add(const Duration(days: 31));
      await z.tags('2 Fabiola', sleutel: 'geheim-123');
      expect(vragen, 2, reason: 'tags blijven 30 dagen');
      final bestanden = Directory(pad).listSync().whereType<File>().toList();
      expect(bestanden.length, 1, reason: 'één bestand per antwoord');
      final opSchijf = bestanden.single.readAsStringSync();
      expect(opSchijf, contains('eurodance'));
      expect(opSchijf, isNot(contains('geheim-123')), reason: 'de sleutel nooit in de buffer');
      nu = nu.add(const Duration(days: 1));
      expect(await maak().tags('2 Fabiola', sleutel: 'geheim-123'), ['eurodance'], reason: 'ook na een herstart');
      expect(vragen, 2);
    });

    test('houdbaarheid: eigen geschiedenis een dag, smaak en bekendheid langer; een fout wordt niet bewaard', () async {
      expect(lastfmHoudbaar('user.gettoptracks'), const Duration(days: 1));
      expect(lastfmHoudbaar('artist.gettoptags'), const Duration(days: 30));
      expect(lastfmHoudbaar('track.getsimilar'), const Duration(days: 14));
      var vragen = 0;
      final z = LastfmZoeker(
        buffer: '${map.path}${Platform.pathSeparator}lastfm',
        tussenpoos: Duration.zero,
        client: MockClient((_) async {
          vragen++;
          return http.Response('{"error":29,"message":"Rate limit exceeded"}', 200);
        }),
      );
      expect(await z.tags('X', sleutel: 's'), isNull);
      expect(await z.tags('X', sleutel: 's'), isNull);
      expect(vragen, 2, reason: 'een weigering is geen antwoord om te bewaren');
    });

    test('de rem: twee vragen liggen minstens de tussenpoos uit elkaar', () async {
      final tijden = <DateTime>[];
      final z = LastfmZoeker(
        tussenpoos: const Duration(milliseconds: 200),
        client: MockClient((_) async {
          tijden.add(DateTime.now());
          return _json({
            'toptags': {'tag': []},
          });
        }),
      );
      await Future.wait([z.tags('A', sleutel: 's'), z.tags('B', sleutel: 's')]);
      expect(tijden.length, 2);
      expect(tijden[1].difference(tijden[0]).inMilliseconds, greaterThanOrEqualTo(190));
    });
  });
}
