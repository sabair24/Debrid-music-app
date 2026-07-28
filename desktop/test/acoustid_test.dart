/// Een plaat benoemen op wat hij KLINKT, als geen catalogus hem op naam kan vinden.
///
/// De stemming is het hele idee, en die is met opzet pure rekenkunde: acht platen in de bibliotheek
/// komen leeg terug bij zowel MusicBrainz als Discogs, en het zijn allemaal verzamelaars.
library;

import 'package:debridmusic/acoustid.dart';
import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/editions.dart';
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

    test('één bestand benoemt geen plaat', () {
      // "Vlaamse Diva's" is één bestand. Elke groep waar die ene opname op staat krijgt dan precies
      // één stem, en "de hoogste" is wie de tabel toevallig eerst teruggeeft -- een gok met een
      // getal erbij. Eén nummer staat op een dozijn verzamelaars; dat zegt niets over deze map.
      expect(bestReleaseGroup([['a', 'b', 'c']]), isNull);
    });

    test('een gelijkspel is geen winnaar', () {
      expect(bestReleaseGroup([['a'], ['b']]), isNull);
      // Maar een echte meerderheid wel, ook als er een tweede groep meestemt.
      expect(bestReleaseGroup([['a'], ['a', 'b'], ['a']]), 'a');
    });

    test('helemaal niets is geen antwoord', () {
      expect(bestReleaseGroup(const []), isNull);
      expect(bestReleaseGroup([<String>[], <String>[]]), isNull);
    });
  });

  group('een mislukking van vóór het luisteren krijgt één nieuwe kans', () {
    // Gemeten op de avond dat vingerafdrukken uitkwamen: de acht verzamelaars waar het voor gebouwd
    // was, waren uren eerder al mislukt op titel. Ze droegen dus failedMs, en de takenlijst van de
    // veeg kwam terug met "25 te doen van 132" -- met geen van de acht erin. De functie kon pas de
    // volgende dag geprobeerd worden.
    AlbumFacts mislukt({required bool heard}) => AlbumFacts(
          uid: 'u',
          trackSetHash: 'h',
          failedMs: DateTime.now().millisecondsSinceEpoch,
          heard: heard,
        );

    test('nog niet geluisterd: opnieuw proberen', () {
      expect(
          needsResolve(mislukt(heard: false),
              trackSetHash: 'h', nowMs: DateTime.now().millisecondsSinceEpoch, canHear: true),
          isTrue);
    });

    test('al geluisterd: met rust laten', () {
      expect(
          needsResolve(mislukt(heard: true),
              trackSetHash: 'h', nowMs: DateTime.now().millisecondsSinceEpoch, canHear: true),
          isFalse,
          reason: 'één extra poging, geen lus');
    });

    test('kan niet luisteren: dan verandert er niets', () {
      expect(
          needsResolve(mislukt(heard: false),
              trackSetHash: 'h', nowMs: DateTime.now().millisecondsSinceEpoch, canHear: false),
          isFalse);
    });

    test('een geslaagde opzoeking wordt niet opnieuw gedaan om te luisteren', () {
      final goed = AlbumFacts(
        uid: 'u',
        trackSetHash: 'h',
        source: 'MusicBrainz',
        tracklist: const [ChoiceTrack('1', 'Iets', 200)],
      );
      expect(
          needsResolve(goed,
              trackSetHash: 'h', nowMs: DateTime.now().millisecondsSinceEpoch, canHear: true),
          isFalse);
    });

    test('"geluisterd" overleeft de schijf', () {
      final j = mislukt(heard: true).toJson();
      expect(AlbumFacts.fromJson(j)!.heard, isTrue);
      expect(AlbumFacts.fromJson(mislukt(heard: false).toJson())!.heard, isFalse);
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
