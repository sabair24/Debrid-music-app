// Last.fm als extra bron voor de radio (Saber, 22-10-2026: "baseer ook op andere dingen" en zijn eigen API-sleutel).
// Gemeten die dag met track.getSimilar: Freak Out en Clouseau gaven tientallen passende nummers van anderen; Petra
// gaf een hoop naamgenoten (22 van 31 "Petra", de rest christelijke rock) — die lijst slaat de radio over.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/lastfm.dart';

Map<String, dynamic> _antwoord(List<(String, String)> nummers) => {
  'similartracks': {
    'track': [
      for (final (a, t) in nummers)
        {
          'name': t,
          'artist': {'name': a},
          'match': 0.5,
          'duration': 220,
        },
    ],
  },
};

void main() {
  group('het antwoord', () {
    test('DE KERN: de nummers van anderen; die van de zaadartiest zelf vallen weg', () {
      final r = lastfmVergelijkbaar(
        _antwoord([
          ('2 Fabiola', 'Flashback'),
          ('X-Session', 'On and On'),
          ('Da Boy Tommy', 'Candyman'),
          ('2 Brothers on the 4th Floor', 'Never Alone'),
          ('T-Spoon', 'Mercedes Benz'),
          ('Ann Lee', '2 Times'),
          ('Captain Jack', 'Captain Jack'),
          ('Masterboy', 'Just for you'),
          ('Cappella', 'U Got 2 Know'),
        ]),
        zaadArtiest: '2 Fabiola',
      );
      expect(r.totaal, 9);
      expect(r.vanZelf, 1);
      expect(r.nummers.first, (artiest: 'X-Session', titel: 'On and On'));
      expect(r.nummers.length, 8);
    });

    test('DE VAL: naamgenoten op één hoop (Petra) — meer dan 40 % van de zaadartiest zelf: niets', () {
      final r = lastfmVergelijkbaar(
        _antwoord([
          for (var i = 0; i < 22; i++) ('Petra', 'Nummer $i'),
          for (var i = 0; i < 9; i++) ('White Heart', 'Lied $i'),
        ]),
        zaadArtiest: 'Petra',
      );
      expect((r.totaal, r.vanZelf), (31, 22));
      expect(r.nummers, isEmpty, reason: 'de andere 9 waren christelijke rock');
      expect(kLastfmZelfHoogstens, 0.4);
    });

    test('te weinig van anderen is ook niets; kapot of leeg is niets', () {
      final r = lastfmVergelijkbaar(_antwoord([for (var i = 0; i < 7; i++) ('A$i', 'T$i')]), zaadArtiest: 'Z');
      expect(r.nummers, isEmpty);
      expect(kLastfmMinimum, 8);
      expect(lastfmVergelijkbaar(null, zaadArtiest: 'Z').totaal, 0);
      expect(lastfmVergelijkbaar({'similartracks': 'onzin'}, zaadArtiest: 'Z').totaal, 0);
      expect(
        lastfmVergelijkbaar({
          'similartracks': {
            'track': [
              {
                'name': '',
                'artist': {'name': 'A'},
              },
              {'name': 'T', 'artist': 'geen map'},
            ],
          },
        }, zaadArtiest: 'Z').totaal,
        0,
      );
    });
  });

  group('de vraag', () {
    test('track.getsimilar met autocorrect; de sleutel gaat mee in de vraag', () async {
      Uri? gevraagd;
      final z = LastfmZoeker(
        client: MockClient((v) async {
          gevraagd = v.url;
          return http.Response.bytes(
            utf8.encode(jsonEncode(_antwoord([for (var i = 0; i < 10; i++) ('A$i', 'T$i')]))),
            200,
          );
        }),
      );
      final r = await z.vergelijkbaar('2 Fabiola', 'Freak Out', sleutel: 'toets-sleutel');
      expect(r!.nummers.length, 10);
      expect(gevraagd!.host, 'ws.audioscrobbler.com');
      expect(
        gevraagd!.queryParameters,
        allOf(
          containsPair('method', 'track.getsimilar'),
          containsPair('autocorrect', '1'),
          containsPair('artist', '2 Fabiola'),
          containsPair('track', 'Freak Out'),
          containsPair('api_key', 'toets-sleutel'),
        ),
      );
    });

    test('een geweigerde sleutel, een fout of geen net is null; zonder sleutel wordt er niets gevraagd', () async {
      var vragen = 0;
      final nee = LastfmZoeker(
        client: MockClient((_) async {
          vragen++;
          return http.Response('{"error":10,"message":"Invalid API key"}', 200);
        }),
      );
      expect(await nee.vergelijkbaar('A', 'B', sleutel: 'x'), isNull);
      expect(
        await LastfmZoeker(
          client: MockClient((_) async => http.Response('', 500)),
        ).vergelijkbaar('A', 'B', sleutel: 'x'),
        isNull,
      );
      expect(
        await LastfmZoeker(
          client: MockClient((_) async => throw const SocketException('geen net')),
        ).vergelijkbaar('A', 'B', sleutel: 'x'),
        isNull,
      );
      expect(await nee.vergelijkbaar('A', 'B', sleutel: '  '), isNull);
      expect(vragen, 1);
    });
  });

  test(
    'aangesloten: bij de start, opgezocht als de modellijst, streng op sfeer, en de sleutel nooit in het logboek',
    () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final i = main.indexOf('    final lastfmSleutel = cfg.lastfmKey.trim();');
      expect(i, greaterThan(0));
      final blok = main.substring(i, main.indexOf('    // En de nummers van het model erbij', i));
      expect(blok, contains('await _lastfmBron.vergelijkbaar(artist, lastfmTitel, sleutel: lastfmSleutel);'));
      expect(blok, contains("van: 'Last.fm');"));
      expect(blok, contains("bron: 'lastfm');"));
      expect(blok, contains('keuring.vraagSfeer(vanLastfm);\n'), reason: 'streng: niet `gekozen`');
      expect(blok, contains('_voegGekeurdBij(radio, sessie, _afstemBeurt, keuring, vanLastfm);'));
      expect(
        RegExp(r"log\.line\([^;]*lastfmSleutel").hasMatch(blok),
        isFalse,
        reason: 'de sleutel nooit in een logregel',
      );
      expect(
        main.indexOf('    final lastfmSleutel'),
        lessThan(main.indexOf('    final model = ai, wie = profiel;')),
        reason: 'los van het model: ook zonder taalmodel',
      );
    },
  );
}
