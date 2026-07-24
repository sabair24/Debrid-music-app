// Verifies the Deezer recommendation engine (artist radio + mix) used by Radio.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/recommend.dart';

/// Deezer's own answer to "Adele", trimmed to the fields that decide, captured 2026-07-24.
/// The real Adele is FIFTH. This list is the bug, written down.
const _adele = [
  {'id': 76792372, 'name': 'Adele & The Chandeliers', 'nb_fan': 41},
  {'id': 61817012, 'name': 'Adele', 'nb_fan': 145},
  {'id': 69171232, 'name': 'Adèle & Robin', 'nb_fan': 3162},
  {'id': 76152522, 'name': 'Adele & Andy', 'nb_fan': 104},
  {'id': 75798, 'name': 'Adele', 'nb_fan': 15429227},
  {'id': 5673798, 'name': 'Adele', 'nb_fan': 11574},
];

void main() {
  group('pickArtist', () {
    test('the artist people listen to, not the first row Deezer returns', () {
      // Row one has 41 fans and no catalogue: /radio answers "no data" for it, which is exactly
      // how the Radio button came back empty for Adele.
      expect(pickArtist(_adele, 'Adele'), 75798);
    });

    test('an exact name beats fans, so a collaboration never steals the query', () {
      final hits = [
        {'id': 1, 'name': 'Enrique Iglesias & Ana Mena', 'nb_fan': 9000000},
        {'id': 2792, 'name': 'Enrique Iglesias', 'nb_fan': 5950666},
      ];
      expect(pickArtist(hits, 'Enrique Iglesias'), 2792);
    });

    test('accents are not a different artist', () {
      final hits = [
        {'id': 4501495, 'name': 'Mc Beyonce', 'nb_fan': 14530},
        {'id': 145, 'name': 'Beyoncé', 'nb_fan': 12793646},
      ];
      expect(pickArtist(hits, 'Beyonce'), 145);
      expect(pickArtist(hits, 'Beyoncé'), 145);
    });

    test('with no exact match at all, the most listened-to hit still wins', () {
      // Better a near miss than nothing: refusing here would silence Radio for every artist whose
      // name Deezer spells differently.
      final hits = [
        {'id': 1, 'name': 'Tribute to Someone', 'nb_fan': 12},
        {'id': 2, 'name': 'Someone & Friends', 'nb_fan': 900},
      ];
      expect(pickArtist(hits, 'Someone'), 2);
    });

    test('nothing usable is null, not a crash', () {
      expect(pickArtist(const [], 'Adele'), isNull);
      expect(pickArtist(const ['rommel'], 'Adele'), isNull);
      expect(pickArtist(const [{'name': 'Adele'}], 'Adele'), isNull, reason: 'geen id');
    });

    test('a missing fan count is zero, not a reason to throw', () {
      final hits = [
        {'id': 1, 'name': 'Adele'},
        {'id': 2, 'name': 'Adele', 'nb_fan': 5},
      ];
      expect(pickArtist(hits, 'Adele'), 2);
    });
  });
}
