/// De kleurwas: één recept voor twee schermen.
///
/// **Waarom deze toets bestaat.** De was staat op de albumpagina én op het speelscherm, en het zijn
/// precies de getallen die uit elkaar lopen zodra ze op twee plekken staan: er wordt er één
/// bijgesteld naar aanleiding van één schermafbeelding, en dan tekent dezelfde plaat op twee
/// schermen een andere kleur. Sinds ronde 2 staat het recept in `ui/vlak.dart`; dit bewaakt het.
///
/// En de getallen zelf zijn niet willekeurig. Ze zijn afgestemd op de grijstrap: toen de
/// achtergrond in ronde 1 donkerder werd, moest de top van de was mee omhoog om op dezelfde
/// helderheid uit te komen. Wie de trap nog eens verschuift, hoort dit te zien.
library;

import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('de tint van een hoes', () {
    test('geen kleur betekent geen was', () {
      // Een zwart-witte hoes hoort géén was te krijgen: geen was is beter dan een grijze.
      expect(wasBasis(null), isNull);
      expect(kleurWas(null), isNull);
    });

    test('een bijna zwarte hoes wordt een zichtbare kleur', () {
      // Thriller geeft rgb(25,37,43). Die kleur op #07080C leggen verandert niets zichtbaars — dat
      // is de reden dat alleen de TINT overgenomen wordt en de helderheid gelijkgetrokken.
      final basis = wasBasis(0xFF19252B)!;
      expect(HSLColor.fromColor(basis).lightness, closeTo(.42, .01));
      // En het blijft blauw: de tint mag niet verschuiven.
      expect(HSLColor.fromColor(basis).hue, closeTo(HSLColor.fromColor(const Color(0xFF19252B)).hue, 2));
    });

    test('een flauwe hoes krijgt een ondergrens en een felle een bovengrens', () {
      // Anders blijft een grijzige hoes grijzig, en schreeuwt een felle hoes de tekst weg.
      expect(HSLColor.fromColor(wasBasis(0xFF6A6866)!).saturation, greaterThanOrEqualTo(.32));
      expect(HSLColor.fromColor(wasBasis(0xFFFF0033)!).saturation, lessThanOrEqualTo(.78));
    });
  });

  group('het verloop', () {
    final was = kleurWas(wasBasis(0xFFC5492D))!;

    test('het eindigt op de achtergrond en niet op iets anders', () {
      // Anders is de plek waar de was ophoudt een RAND in plaats van een overgang.
      expect(was.colors.last, kAchtergrond);
    });

    test('het loopt van boven naar beneden en dooft uit', () {
      expect(was.begin, Alignment.topCenter);
      expect(was.end, Alignment.bottomCenter);
      expect(was.stops, [0.0, .34, .78]);
      // Elke stop is flauwer dan de vorige.
      for (var i = 1; i < was.colors.length; i++) {
        expect(_afstandTot(was.colors[i]), lessThan(_afstandTot(was.colors[i - 1])),
            reason: 'stop $i ligt niet dichter bij de achtergrond dan de vorige');
      }
    });

    test('de top is sterk genoeg om te zien, en niet zo sterk dat tekst eronder lijdt', () {
      final top = was.colors.first;
      // Tegen de achtergrond moet je hem ZIEN…
      expect(sterrenL(top) - sterrenL(kAchtergrond), greaterThan(6),
          reason: 'de was is niet van de achtergrond te onderscheiden');
      // …en witte tekst moet er nog ruim overheen kunnen.
      expect(contrast(kTekst, top), greaterThanOrEqualTo(4.5));
    });
  });
}

/// Hoe ver een kleur van de achtergrond af ligt, in L*.
double _afstandTot(Color c) => (sterrenL(c) - sterrenL(kAchtergrond)).abs();
