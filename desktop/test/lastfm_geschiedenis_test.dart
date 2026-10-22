// Je Last.fm-geschiedenis naast je bibliotheek (Saber, 22-10-2026, account Sabair24). Gemeten die dag: zijn 1000 meest
// gespeelde nummers in 4,6 s; 507 daarvan niet in zijn bibliotheek, elk minstens drie keer gespeeld (Lauren Daigle — You
// Say 25, Robert Tepper — No Easy Way Out 24, Chris Isaak — Wicked Game 22, Toto — Africa 16).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/lastfm.dart';
import 'package:debridmusic/lastfm_geschiedenis.dart';
import 'package:debridmusic/models.dart' show Track;

Track _t(String a, String t) => Track(path: 'C:/m/$a - $t.flac', title: t, artist: a, album: '');

void main() {
  group('nog niet van jou', () {
    test(
      'DE KERN: wat je speelde en niet hebt, meest gespeeld eerst; hetzelfde liedje zonder haakjes telt als bezit',
      () {
        final mis = nogNietVanJou(
          const [
            (artiest: 'Toto', titel: 'Africa', keer: 16),
            (artiest: 'Lauren Daigle', titel: 'You Say', keer: 25),
            (artiest: 'Michael Jackson', titel: 'Billie Jean', keer: 25),
            (artiest: 'Plaza', titel: 'Yo Yo', keer: 9),
          ],
          [_t('Michael Jackson', 'Billie Jean (Single Version)'), _t('Plaza', 'Yo-Yo (Dance Version)')],
        );
        expect(mis, [
          (artiest: 'Lauren Daigle', titel: 'You Say', keer: 25),
          (artiest: 'Toto', titel: 'Africa', keer: 16),
        ]);
      },
    );

    test('één keer gespeeld telt niet, dubbels één keer, karaoke nooit', () {
      final mis = nogNietVanJou(const [
        (artiest: 'A', titel: 'Een keer', keer: 1),
        (artiest: 'Toto', titel: 'Africa', keer: 16),
        (artiest: 'Toto', titel: 'Africa (Remastered)', keer: 4),
        (artiest: 'B', titel: 'Liedje (Karaoke Version)', keer: 9),
      ], const []);
      expect([for (final m in mis) m.titel], ['Africa']);
    });
  });

  group('bekend, nog niet van jou (artiestpagina)', () {
    // Gemeten op 22-10-2026: Clouseau gaf Domino, Nobelprijs, Afscheid Van Een Vriend…; Petra gaf de toppers van de
    // christelijke rockband (Beyond Belief, Creed) terwijl Saber drie nummers van de Vlaamse Petra heeft.
    const clouseau = <LastfmTopper>[
      (artiest: 'Clouseau', titel: 'Daar Gaat Ze', luisteraars: 36681),
      (artiest: 'Clouseau', titel: 'Passie', luisteraars: 17729),
      (artiest: 'Clouseau', titel: 'Domino', luisteraars: 14820),
      (artiest: 'Clouseau', titel: 'Domino (Remix)', luisteraars: 900),
      (artiest: 'Clouseau', titel: 'Nobelprijs', luisteraars: 13320),
    ];

    test('DE KERN: de bekende nummers die je niet hebt, bekendste eerst, zonder bewerkingen', () {
      final mis = bekendeNummersDieJeMist(clouseau, [_t('Clouseau', 'Daar Gaat Ze'), _t('Clouseau', 'Passie (Live)')]);
      expect([for (final m in mis) m.titel], ['Domino', 'Nobelprijs']);
    });

    test(
      'DE VAL: staat geen enkel bekend nummer in je bibliotheek, dan is het misschien een naamgenoot — geen rij',
      () {
        const naamgenoot = <LastfmTopper>[
          (artiest: 'Petra', titel: 'Beyond Belief', luisteraars: 12700),
          (artiest: 'Petra', titel: 'Creed', luisteraars: 9999),
        ];
        expect(
          bekendeNummersDieJeMist(naamgenoot, [_t('Petra', 'Ik Leef Voor Jou'), _t('Petra', 'Laat Je Gaan')]),
          isEmpty,
        );
        expect(bekendeNummersDieJeMist(clouseau, const []), isEmpty, reason: 'niets van de artiest: geen bewijs');
      },
    );

    test('hoogstens [max]', () {
      final mis = bekendeNummersDieJeMist(clouseau, [_t('Clouseau', 'Daar Gaat Ze')], max: 1);
      expect([for (final m in mis) m.titel], ['Passie']);
    });
  });

  test('de artiesten voor het smaakprofiel: meest gespeeld eerst, zonder wat de app al kent', () {
    expect(
      geschiedenisArtiesten(
        const [(naam: 'Sade', keer: 95), (naam: 'Michael Jackson', keer: 424), (naam: 'Céline Dion', keer: 157)],
        al: const ['michael jackson'],
        max: 2,
      ),
      ['Céline Dion', 'Sade'],
    );
  });

  group('ophalen', () {
    test('bladzijden tot er een niet vol is, plus de artiesten; zonder gebruiker niets', () async {
      final bladen = <String>[];
      final bron = LastfmZoeker(
        tussenpoos: Duration.zero,
        client: MockClient((v) async {
          final q = v.url.queryParameters;
          if (q['method'] == 'user.gettopartists') {
            return http.Response(
              jsonEncode({
                'topartists': {
                  'artist': [
                    {'name': 'Sade', 'playcount': '95'},
                  ],
                },
              }),
              200,
            );
          }
          bladen.add(q['page']!);
          final n = q['page'] == '1' ? 200 : 3;
          return http.Response(
            jsonEncode({
              'toptracks': {
                'track': [
                  for (var i = 0; i < n; i++)
                    {
                      'name': 'T$i',
                      'playcount': '5',
                      'artist': {'name': 'A'},
                    },
                ],
              },
            }),
            200,
          );
        }),
      );
      final g = await haalGeschiedenis(bron, gebruiker: 'Sabair24', sleutel: 's');
      expect(bladen, ['1', '2']);
      expect(g!.nummers.length, 203);
      expect(g.artiesten, [(naam: 'Sade', keer: 95)]);
      expect(await haalGeschiedenis(bron, gebruiker: ' ', sleutel: 's'), isNull);
    });

    test('geen antwoord op de eerste bladzijde: null, zodat de app niets verkeerds toont', () async {
      final bron = LastfmZoeker(tussenpoos: Duration.zero, client: MockClient((_) async => http.Response('', 503)));
      expect(await haalGeschiedenis(bron, gebruiker: 'Sabair24', sleutel: 's'), isNull);
    });
  });
}
