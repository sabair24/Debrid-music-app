/// Een plaat benoemen op wat hij KLINKT, als geen catalogus hem op naam kan vinden.
///
/// De stemming is het hele idee, en die is met opzet pure rekenkunde: acht platen in de bibliotheek
/// komen leeg terug bij zowel MusicBrainz als Discogs, en het zijn allemaal verzamelaars.
library;

import 'package:debridmusic/acoustid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stemming over de release-groep', () {
    test('waar de meeste nummers het over eens zijn wint', () {
      // Een verzamelaar: elk nummer staat ook op zijn eigen album, maar op één uitgave komen ze
      // allemaal samen.
      final perTrack = [
        ['verzamelaar', 'album-a'],
        ['verzamelaar', 'album-b'],
        ['verzamelaar', 'album-c'],
        ['verzamelaar'],
      ];
      expect(bestReleaseGroup(perTrack), 'verzamelaar');
    });

    test('één nummer op acht persingen overstemt de rest niet', () {
      // Zonder ontdubbelen per bestand zou dit ene bestand met acht vermeldingen van dezelfde groep
      // in zijn eentje elk ander bestand overstemmen.
      final perTrack = [
        ['x', 'x', 'x', 'x', 'x', 'x', 'x', 'x'],
        ['echt'],
        ['echt'],
        ['echt'],
      ];
      expect(bestReleaseGroup(perTrack), 'echt');
    });

    test('te weinig eensgezindheid geeft geen antwoord', () {
      final perTrack = [
        ['a'],
        ['b'],
        ['c'],
        ['d'],
      ];
      expect(bestReleaseGroup(perTrack), isNull,
          reason: 'vier nummers die vier kanten op wijzen benoemen geen plaat');
    });

    test('nummers die AcoustID niet kent tellen niet als tegenstem', () {
      // Op een Belgische hardcore-verzamelaar kent AcoustID een deel van de nummers gewoon niet.
      // Zes van de zes herkende die het eens zijn is een antwoord; de zes onbekende wegtellen als
      // "oneens" zou dat weggooien.
      final perTrack = [
        <String>[], <String>[], <String>[],
        ['de plaat'], ['de plaat'], ['de plaat'],
      ];
      expect(bestReleaseGroup(perTrack), 'de plaat');
    });

    test('helemaal niets is geen antwoord', () {
      expect(bestReleaseGroup(const []), isNull);
      expect(bestReleaseGroup([<String>[], <String>[]]), isNull);
    });
  });

  group('antwoord lezen', () {
    test('beide vormen van release-groepen worden gelezen, beste score eerst', () {
      final body = {
        'status': 'ok',
        'results': [
          {
            'score': 0.6,
            'recordings': [
              {'id': 'rec-laag', 'title': 'Tweede', 'releasegroupids': ['g1', 'g2']}
            ]
          },
          {
            'score': 0.98,
            'recordings': [
              {
                'id': 'rec-hoog',
                'title': 'Eerste',
                'releasegroups': [
                  {'id': 'g3'}
                ]
              }
            ]
          },
        ],
      };
      final out = AcoustIdService.parseLookup(body);
      expect(out, hasLength(2));
      expect(out.first.recordingId, 'rec-hoog', reason: 'de zekerste hoort vooraan');
      expect(out.first.releaseGroups, ['g3']);
      expect(out.last.releaseGroups, ['g1', 'g2']);
    });

    test('rommel levert niets op in plaats van een uitzondering', () {
      expect(AcoustIdService.parseLookup({'status': 'ok'}), isEmpty);
      expect(AcoustIdService.parseLookup({'status': 'ok', 'results': 'geen lijst'}), isEmpty);
      expect(
          AcoustIdService.parseLookup({
            'status': 'ok',
            'results': [
              {'score': 1.0, 'recordings': [{'title': 'zonder id'}]}
            ]
          }),
          isEmpty);
    });
  });
}
