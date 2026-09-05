/// Een ingebakken hoes die op twee verschillende platen staat, is van geen van beide.
///
/// **Gevonden op 05-09-2026** bij het doorlichten van de bibliotheek op verkeerde hoezen, en
/// nagemeten door het plaatje met ffmpeg uit de FLAC's te trekken:
///
///     01 - Genie in a Bottle.flac                     58944 bytes  ┐ exact dezelfde
///     01 - Bye Bye Bye.flac                           58944 bytes  ┘ BRAVO Hits 00's
///     02 - Amazing.flac                               68492 bytes  ┐ exact dezelfde
///     16 - Whitney Houston - My Love Is Your Love.flac 68492 bytes ┘ Sublime Top 1000
///
/// Nummers die uit een verzamelrip komen dragen de hoes van die verzamelplaat mee, en die reisde
/// ongemerkt mee naar de echte plaat. De bestanden zijn fout — maar de app maakte het erger door
/// die hoes vóór de hoes te laten gaan die de verrijker opzoekt. Christina Aguilera's plaat toonde
/// dus *BRAVO Hits 00's*, en George Michaels *Patience* toonde *Sublime Top 1000*.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart';

Uint8List beeld(int zaad, {int lengte = 4096}) =>
    Uint8List.fromList([for (var i = 0; i < lengte; i++) (zaad + i * 7) & 0xff]);

Album plaat(String artiest, String titel, Uint8List? ingebakken, {Uint8List? web}) {
  final a = Album(titel, artiest, [
    Track(path: 'D:\\m\\$artiest-$titel.flac', title: 'x', artist: artiest, album: titel),
  ]);
  a.embeddedCover = ingebakken;
  a.enriched = web;
  return a;
}

void main() {
  group('de hoes die op het scherm hoort', () {
    test('gewoon: de ingebakken hoes gaat vóór die van het web', () {
      final a = plaat('Adele', '30', beeld(1), web: beeld(2));
      expect(a.cover, beeld(1));
      expect(a.zekereHoes, beeld(1));
    });

    test('DE KERN: een verdachte hoes zakt onder die van het web', () {
      final a = plaat('Christina Aguilera', 'Christina Aguilera', beeld(9), web: beeld(2))
        ..embeddedIsVanEenAndere = true;
      expect(a.cover, beeld(2));
    });

    test('maar hij blijft de laatste terugval, zodat er niets kwijtraakt', () {
      // Vindt de verrijker niets, dan is een verkeerde hoes nog altijd zichtbaarder dan een leeg
      // vlak — en zodra de goede binnenkomt wint die vanzelf.
      final a = plaat('Christina Aguilera', 'Christina Aguilera', beeld(9))
        ..embeddedIsVanEenAndere = true;
      expect(a.cover, beeld(9));
    });

    test('DE VAL: maar dan moet er wél nog gezocht worden', () {
      // Twee vragen die niet dezelfde zijn. "Wat teken ik?" mag eindigen bij een verdachte hoes;
      // "moet ik er nog een zoeken?" mag dat niet. Met één getter voor allebei sloeg de verrijker
      // deze platen over — `cover` gaf immers iets terug — en kwam er nooit een goede voor in de
      // plaats. Precies dat gebeurde bij de eerste poging, gemeten: vier platen bleven de hoes van
      // *BRAVO Hits 00's* en *Sublime Top 1000* dragen.
      final a = plaat('Christina Aguilera', 'Christina Aguilera', beeld(9))
        ..embeddedIsVanEenAndere = true;
      expect(a.cover, isNotNull, reason: 'er staat wel iets op het scherm');
      expect(a.zekereHoes, isNull, reason: 'maar de verrijker moet er nog een zoeken');
    });

    test('een eigen keuze en een aangewezen persing blijven bovenaan', () {
      final a = plaat('Christina Aguilera', 'Christina Aguilera', beeld(9), web: beeld(2))
        ..embeddedIsVanEenAndere = true
        ..resolvedCover = beeld(3);
      expect(a.cover, beeld(3));
      a.correctedCover = beeld(4);
      expect(a.cover, beeld(4));
    });
  });

  group('welke hoes verdacht is', () {
    test('DE KERN: andere artiest én andere titel — allebei verdacht', () {
      final aguilera = plaat('Christina Aguilera', 'Christina Aguilera', beeld(9));
      final nsync = plaat('*NSYNC', 'No Strings Attached', beeld(9));
      markeerVreemdeHoezen([aguilera, nsync]);
      expect(aguilera.embeddedIsVanEenAndere, isTrue);
      expect(nsync.embeddedIsVanEenAndere, isTrue);
    });

    test('DE REM 1: dezelfde plaat in twee tegels blijft met rust', () {
      // *Thunderdome XXIII* staat twee keer in de bibliotheek, onder verschillende artiestvelden.
      // Zelfde titel, en terecht dezelfde hoes.
      final een = plaat('DJ Promo', 'Thunderdome XXIII', beeld(9));
      final twee = plaat('The Stunned Guys & DJ Paul', 'Thunderdome XXIII', beeld(9));
      markeerVreemdeHoezen([een, twee]);
      expect(een.embeddedIsVanEenAndere, isFalse);
      expect(twee.embeddedIsVanEenAndere, isFalse);
    });

    test('DE REM 2: een single naast zijn album blijft met rust', () {
      // *Pon De Replay* draagt de hoes van *Music Of The Sun*, en dat hoort zo.
      final album = plaat('Rihanna', 'Music Of The Sun', beeld(9));
      final single = plaat('Rihanna', 'Pon De Replay', beeld(9));
      markeerVreemdeHoezen([album, single]);
      expect(album.embeddedIsVanEenAndere, isFalse);
      expect(single.embeddedIsVanEenAndere, isFalse);
    });

    test('een hoes die maar op één plaat staat is nooit verdacht', () {
      final a = plaat('Adele', '30', beeld(1));
      final b = plaat('Adele', '25', beeld(2));
      markeerVreemdeHoezen([a, b]);
      expect(a.embeddedIsVanEenAndere, isFalse);
      expect(b.embeddedIsVanEenAndere, isFalse);
    });

    test('en de vlag wordt elke ronde opnieuw bepaald, niet opgestapeld', () {
      final a = plaat('Adele', '30', beeld(1))..embeddedIsVanEenAndere = true;
      markeerVreemdeHoezen([a]);
      expect(a.embeddedIsVanEenAndere, isFalse);
    });

    test('een piepklein plaatje telt niet mee', () {
      // Onder een halve kilobyte is het geen hoes maar een pictogram, en dan zegt "dezelfde bytes"
      // niets over welke plaat het is.
      final a = plaat('X', 'Een', beeld(1, lengte: 400));
      final b = plaat('Y', 'Twee', beeld(1, lengte: 400));
      markeerVreemdeHoezen([a, b]);
      expect(a.embeddedIsVanEenAndere, isFalse);
    });
  });
}
