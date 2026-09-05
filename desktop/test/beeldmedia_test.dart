/// Een dvd bij de cd is geen ontbrekende muziek.
///
/// **Gevonden bij het doorlichten van de hele bibliotheek op 05-09-2026**, niet bij één klacht.
/// Boyzone's *Back Again... No Matter What* is een cd van 17 nummers MÉT een dvd van 14 clips —
/// dezelfde liedjes, als video. De app telde die dvd-rijen mee: "1 van 31 nummers · 30 ontbreken",
/// en elk nummer stond twee keer in de lijst. Thunderdome *The Best Of '98* deed het met een VHS
/// erbij, goed voor 86 rijen.
///
/// Erger dan een verkeerd getal: die videorijen dragen dezelfde titels, dus ze maakten van een
/// gewone plaat een plaat met "twee gelijknamige rijen" — precies het geval waarin alleen de
/// looptijd nog beslist welk bestand waar hoort. Van de 17 zulke platen in deze bibliotheek waren er
/// zo een stuk of wat helemaal geen echte dubbelzinnigheid.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/organize.dart';

void main() {
  group('welke positie wijst naar beeld', () {
    test('DE KERN: de vormen die de catalogi echt schrijven', () {
      expect(isBeeldPositie('DVD-1'), isTrue);
      expect(isBeeldPositie('VHS-7'), isTrue);
      expect(isBeeldPositie('Video-3'), isTrue);
      expect(isBeeldPositie('Blu-ray 2'), isTrue);
    });

    test('DE VAL: "DVD-Audio" is muziek', () {
      // Daarom wordt een FORMAAT op `dvd-video` vergeleken en niet op `dvd`. Uit de POSITIE alleen
      // is dat verschil niet te zien, en daarom mag isBeeldPositie alleen gebruikt worden op een
      // uitgave die zelf zegt dat er beeld bij zit — DiscogsEdition.beeldErbij.
      expect(isBeeldFormaat('DVD-Audio'), isFalse);
      expect(isBeeldFormaat('DVD-Video'), isTrue);
    });

    test('een genummerd medium telt ook', () {
      expect(isBeeldPositie('DVD2-4'), isTrue);
      expect(isBeeldPositie('CD1-9'), isFalse);
    });

    test('en gewone posities blijven met rust', () {
      for (final p in ['1', '12', 'A3', 'B2', 'CD-1', 'CD2-18', '2-04', '34.a', '']) {
        expect(isBeeldPositie(p), isFalse, reason: p);
      }
    });
  });

  group('zonderBeeld', () {
    List<String> posities(List<String> in_) => zonderBeeld(in_, (s) => s);

    test('DE KERN: de dvd-rijen gaan eruit', () {
      // Boyzone, ingekort: cd-nummers en dezelfde titels nog eens op dvd.
      expect(posities(['CD-1', 'CD-2', 'CD-3', 'DVD-1', 'DVD-2']),
          ['CD-1', 'CD-2', 'CD-3']);
    });

    test('DE UITZONDERING: een uitgave die ALLEEN video is houdt zijn lijst', () {
      // Een concertregistratie. Alles weggooien laat een plaat zonder tracklijst achter, en dat is
      // erger dan een lijst met beeld erin.
      expect(posities(['DVD-1', 'DVD-2']), ['DVD-1', 'DVD-2']);
    });

    test('een gewone plaat verandert niet', () {
      expect(posities(['1', '2', '3']), ['1', '2', '3']);
    });
  });
}
