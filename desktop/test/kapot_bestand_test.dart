/// Zeggen wat er mis is met een bestand dat niet opengaat.
///
/// **De klacht, op 31-08-2026, met een schermafdruk.** Op het speelscherm stond *"Kan dit nummer niet
/// openen — Failed to recognize file format."* Dat is mpv's eigen zin, in het Engels, en hij zegt
/// niets: is het bestand stuk, leeg, half binnengekomen, of helemaal geen muziek? De gebruiker las
/// het als "de app kan mijn FLAC niet lezen" — *"is gewoon flac file van rutracker"* — en had geen
/// enkele reden om iets anders te denken.
///
/// Het echte antwoord stond in de eerste bytes en in de bestandsgrootte. Dezelfde les als bij het
/// taalmodel dat alleen "400" mocht zeggen: de app wist het en gooide het weg.
library;

import 'package:debridmusic/kapot_bestand.dart';
import 'package:flutter_test/flutter_test.dart';

/// Genoeg bytes om boven de ondergrens uit te komen, met [begin] vooraan.
List<int> met(String begin, {int lengte = 12}) {
  final uit = <int>[...begin.codeUnits];
  while (uit.length < lengte) {
    uit.add(0);
  }
  return uit;
}

String? reden(String naam, int bytes, List<int> kop) =>
    waaromNietTeOpenen(naam: naam, bytes: bytes, kop: kop);

void main() {
  group('een bestand waar niets in zit', () {
    test('nul bytes wordt bij naam genoemd', () {
      // Dit is wat de gebruiker had: het restafval van een mislukte knipbeurt.
      final r = reden(r'C:\Muziek\15 - Work It Out.flac', 0, const []);
      expect(r, isNotNull);
      expect(r, contains('leeg'));
    });

    test('een halve kilobyte ook', () {
      final r = reden(r'C:\Muziek\x.flac', 300, met('fLaC'));
      expect(r, contains('300'), reason: 'het getal erbij, anders is het weer een vage zin');
    });

    test('precies op de grens telt als muziek', () {
      // Duizend vierentwintig bytes is de ondergrens die de knipper al hanteerde. Wat daarboven zit
      // krijgt het voordeel van de twijfel.
      expect(reden(r'C:\Muziek\x.flac', 1024, met('fLaC')), isNull);
    });
  });

  group('de inhoud past niet bij de naam', () {
    test('een webpagina met een muzieknaam', () {
      // Een foutmelding van een server die met de naam van je nummer is neergezet.
      final r = reden(r'C:\Muziek\01 - Iets.flac', 5000, met('<!DOCTYPE html>'));
      expect(r, contains('webpagina'));
    });

    test('een plaatje', () {
      expect(reden(r'C:\Muziek\x.flac', 5000, [0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
          contains('plaatje'));
      expect(reden(r'C:\Muziek\x.flac', 5000, [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]),
          contains('plaatje'));
    });

    test('een WAV die .flac heet', () {
      expect(reden(r'C:\Muziek\x.flac', 5000, met('RIFF')), contains('WAV'));
    });

    test('een zip', () {
      expect(reden(r'C:\Muziek\x.flac', 5000, met('PK')), contains('zip'));
    });
  });

  group('waar niets over te zeggen valt, wordt niets gezegd', () {
    test('een echte FLAC-kop levert geen verhaal op', () {
      // Een AFGEKAPTE flac begint nog altijd met "fLaC". Dan weten we het niet beter dan mpv, en dan
      // is mpv citeren eerlijker dan iets verzinnen.
      expect(reden(r'C:\Muziek\x.flac', 5000000, met('fLaC')), isNull);
    });

    test('een kop die we niet kennen ook niet', () {
      expect(reden(r'C:\Muziek\x.flac', 5000, met('QQQQ')), isNull);
    });

    test('een grootte die niet op te vragen was levert geen bewering op', () {
      expect(reden(r'C:\Muziek\x.flac', -1, const []), isNull);
    });

    test('een mp3 die echt een mp3 is', () {
      // ID3 in een .mp3 is precies wat je verwacht. Alleen in een .flac is het een aanwijzing.
      expect(reden(r'C:\Muziek\x.mp3', 5000, met('ID3')), isNull);
    });
  });

  group('andere formaten', () {
    test('een DSD-bestand dat .dff heet is in orde', () {
      expect(reden(r'C:\Muziek\x.dff', 5000, met('FRM8')), isNull);
    });

    test('maar een DSD-kop in een .flac is dat niet', () {
      expect(reden(r'C:\Muziek\x.flac', 5000, met('FRM8')), contains('DSD'));
    });
  });
}
