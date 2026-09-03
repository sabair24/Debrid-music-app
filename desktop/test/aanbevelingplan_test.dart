/// De vraag aan het taalmodel, en wat er van zijn antwoord overblijft.
///
/// **Waarom dit zuiver getoetst wordt.** Precies zoals bij `radioplan_test.dart`: het schema en de
/// vraag zijn gewone gegevens, dus ze zijn na te kijken zonder er een aanroep voor te doen. En dat
/// is nodig ook — de Messages-API weigert een heel schema als één veld uit `properties` niet in
/// `required` staat, en dat kost een 400 die je pas ziet als je hem verstuurt.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/aanbevelingplan.dart';

/// Het profiel van deze bibliotheek, zoals het werkelijk gemeten is op 02-09-2026.
const _saber = SmaakProfiel(
  topArtiesten: [
    'Michael Jackson (80)',
    'Backstreet Boys (72)',
    'Adele (38)',
    'Beyoncé (33)',
    'Enrique Iglesias (25)',
    'Khaled (21)',
    'Pommelien Thijs (17)',
    'Stromae (15)',
  ],
  perDecennium: {1990: 448, 2000: 374, 2010: 203, 2020: 92, 1980: 70},
  gespeeld: ['Backstreet Boys', 'Adele'],
  genres: ['Pop', 'Dance', 'R&B', 'Variété française'],
);

void main() {
  group('aanbevelingSchema', () {
    test('DE KERN: elk veld uit properties staat ook in required', () {
      // Dit is geen netheid maar de reden dat het schema geweigerd wordt. Zelfde val als bij
      // `radioSchema`, en hij kost een 400 die pas bij het versturen zichtbaar is.
      void controleer(Map<String, dynamic> s) {
        final props = (s['properties'] as Map).keys.toSet();
        final vereist = ((s['required'] as List?) ?? const []).toSet();
        expect(vereist, props, reason: 'properties en required moeten gelijk lopen');
      }

      final s = aanbevelingSchema();
      controleer(s);
      final item = ((s['properties'] as Map)['voorstellen'] as Map)['items'] as Map<String, dynamic>;
      controleer(item);
    });

    test('het vraagt om artiest, album én een reden', () {
      final item = ((aanbevelingSchema()['properties'] as Map)['voorstellen'] as Map)['items'] as Map;
      expect((item['properties'] as Map).keys, containsAll(['artiest', 'album', 'reden']));
    });

    test('en laat geen velden toe die er niet in horen', () {
      // `additionalProperties: false` is wat een model ervan weerhoudt er zelf iets bij te
      // verzinnen dat verderop stilzwijgend genegeerd wordt.
      expect(aanbevelingSchema()['additionalProperties'], isFalse);
    });
  });

  group('aanbevelingPrompt', () {
    test('DE KERN: het profiel staat er werkelijk in', () {
      final v = aanbevelingPrompt(_saber);
      expect(v, contains('Michael Jackson'));
      expect(v, contains('Khaled'), reason: 'juist de kleine hoeken maken het verschil');
      expect(v, contains('1990s: 448'));
      expect(v, contains('Variété française'));
      expect(v, contains('Backstreet Boys'));
    });

    test('en de drie regels die er echt toe doen', () {
      final v = aanbevelingPrompt(_saber);
      expect(v.toLowerCase(), contains('bestaan'),
          reason: 'een verzonnen titel levert een tegel op die nergens heen gaat');
      expect(v.toLowerCase(), contains('nederlands'),
          reason: 'de reden komt onder de tegel te staan, in zijn eigen taal');
      expect(v, contains('$kMaxVoorstellen'));
    });

    test('een leeg profiel loopt niet stuk', () {
      expect(() => aanbevelingPrompt(const SmaakProfiel()), returnsNormally);
      expect(const SmaakProfiel().leeg, isTrue);
    });
  });

  group('leesVoorstellen', () {
    test('DE KERN: een net antwoord komt er heel uit', () {
      final uit = leesVoorstellen({
        'voorstellen': [
          {'artiest': 'Zucchero', 'album': 'Oro Incenso & Birra', 'reden': 'past bij je chanson'},
          {'artiest': 'Cheb Mami', 'album': 'Meli Meli', 'reden': 'omdat je Khaled draait'},
        ]
      });
      expect(uit, hasLength(2));
      expect(uit.first.artiest, 'Zucchero');
      expect(uit.last.reden, 'omdat je Khaled draait');
    });

    test('een half voorstel valt weg, de rest blijft', () {
      // Eén regel zonder titel is geen reden om de andere elf weg te gooien.
      final uit = leesVoorstellen({
        'voorstellen': [
          {'artiest': 'Zucchero', 'album': '', 'reden': 'x'},
          {'album': 'Zonder artiest', 'reden': 'x'},
          {'artiest': 'Cheb Mami', 'album': 'Meli Meli', 'reden': 'x'},
        ]
      });
      expect(uit.map((v) => v.artiest), ['Cheb Mami']);
    });

    test('twee keer hetzelfde album staat er één keer', () {
      final uit = leesVoorstellen({
        'voorstellen': [
          {'artiest': 'Zucchero', 'album': 'Oro', 'reden': 'a'},
          {'artiest': 'zucchero', 'album': 'ORO', 'reden': 'b'},
        ]
      });
      expect(uit, hasLength(1));
    });

    test('en er komen er nooit meer dan afgesproken', () {
      final uit = leesVoorstellen({
        'voorstellen': [
          for (var i = 0; i < 40; i++) {'artiest': 'A$i', 'album': 'B$i', 'reden': 'x'}
        ]
      });
      expect(uit, hasLength(kMaxVoorstellen));
    });

    test('rommel levert een lege lijst en geen uitzondering', () {
      expect(leesVoorstellen(null), isEmpty);
      expect(leesVoorstellen('geen json'), isEmpty);
      expect(leesVoorstellen({'iets anders': 1}), isEmpty);
      expect(leesVoorstellen({'voorstellen': 'geen lijst'}), isEmpty);
    });
  });
}
