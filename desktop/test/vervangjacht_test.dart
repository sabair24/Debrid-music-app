/// De balk moet lopen terwijl er gewerkt wordt, en niets beweren als er niets loopt.
///
/// **Waarom dit bestaat.** De knop "Laat de app zoeken" zette 173 nummers op de verlanglijst en zei
/// daarna niets meer; alles wat er gebeurde stond alleen in `downloads.log`. Gemeten op 08-09-2026:
/// in de eerste ronde na de knop kwamen er twee opgeschaalde kopieën van 65,4 MB binnen die allebei
/// betrapt en weggegooid werden, en van buiten was dat niet van "de app doet niets" te
/// onderscheiden.
///
/// De valkuil die deze toetsen vastpinnen is de STILSTAND: één wens mag twintig minuten duren, dus
/// een balk die alleen per afgeronde wens opschuift staat het grootste deel van de tijd stil en
/// leest als vastgelopen.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/vervangjacht.dart';

void main() {
  group('hoe vol de balk staat', () {
    test('zonder ronde is er geen balk — en dus geen bewering', () {
      const j = VervangJacht(opDeLijst: 173);
      expect(j.loopt, isFalse);
      expect(j.deel, isNull, reason: 'null is "onbekend", niet nul: nul zou "nog niets" beweren');
    });

    test('de lopende wens telt fractioneel mee', () {
      // Twee van de zes wensen af, en bij de derde is kandidaat 3 van 6 aan de beurt. Die derde
      // wens is dus voor 2/6 geweest: (2 + 0,333) / 6.
      const j = VervangJacht(
          opDeLijst: 165, dezeBeurt: 6, gedaan: 2, poging: 3, maxPoging: 6, bezigMet: 'Gorki — Mia');
      expect(j.deel, closeTo((2 + 2 / 6) / 6, 0.0001));
    });

    test('een net begonnen poging heeft nog niets opgeleverd', () {
      const j = VervangJacht(opDeLijst: 1, dezeBeurt: 2, gedaan: 1, poging: 1, maxPoging: 4);
      expect(j.deel, closeTo(0.5, 0.0001), reason: 'poging 1 draagt nul bij, niet een kwart');
    });

    test('zonder kandidaten schuift hij alleen per wens op', () {
      const j = VervangJacht(opDeLijst: 3, dezeBeurt: 6, gedaan: 3, poging: 0, maxPoging: 0);
      expect(j.deel, closeTo(0.5, 0.0001));
    });

    test('nooit over de rand, ook niet als er meer pogingen komen dan verwacht', () {
      const j = VervangJacht(opDeLijst: 0, dezeBeurt: 1, gedaan: 1, poging: 9, maxPoging: 3);
      expect(j.deel, 1.0);
    });
  });

  group('wat er blijft staan als de ronde voorbij is', () {
    test('de tellers en het ritme overleven, de balk niet', () {
      final volgende = DateTime(2026, 9, 8, 18, 56);
      final j = VervangJacht(
        opDeLijst: 166,
        dezeBeurt: 6,
        gedaan: 6,
        poging: 4,
        maxPoging: 6,
        bezigMet: 'Stromae — Papaoutai',
        binnen: 2,
        weggegooid: 10,
        volgendeOm: volgende,
      ).klaar(opDeLijst: 164);

      expect(j.loopt, isFalse);
      expect(j.deel, isNull);
      expect(j.opDeLijst, 164, reason: 'het getal dat moet dalen komt van de verlanglijst zelf');
      expect(j.binnen, 2);
      expect(j.weggegooid, 10);
      expect(j.volgendeOm, volgende);
      expect(j.bezigMet, isNull, reason: 'een naam laten staan suggereert werk dat niet loopt');
    });
  });

  group('hoe lang het nog duurt', () {
    final nu = DateTime(2026, 9, 8, 18, 40);
    test('leeg als er geen moment bekend is of het al voorbij is', () {
      expect(overTijd(null, nu), '');
      expect(overTijd(nu.subtract(const Duration(minutes: 5)), nu), '');
      expect(overTijd(nu.add(const Duration(seconds: 2)), nu), '',
          reason: 'binnen vijf tellen is geen wachten meer, dat is nu');
    });

    test('een wachttijd zoals je hem uitspreekt, niet als foutcode', () {
      // Het logboek schrijft `20m0s`; op het scherm stond dat er ook, en dat las als een foutcode.
      expect(duurTekst(const Duration(minutes: 20)), '20 min');
      expect(duurTekst(const Duration(hours: 2)), '2 uur');
      expect(duurTekst(const Duration(hours: 1)), 'een uur');
      expect(duurTekst(const Duration(days: 1)), 'een dag');
      expect(duurTekst(const Duration(seconds: 30)), '30 sec');
    });

    test('seconden, minuten en uren', () {
      expect(overTijd(nu.add(const Duration(seconds: 30)), nu), 'over 30 sec');
      expect(overTijd(nu.add(const Duration(seconds: 90)), nu), 'over een minuut');
      expect(overTijd(nu.add(const Duration(minutes: 12)), nu), 'over 12 min');
      expect(overTijd(nu.add(const Duration(minutes: 130)), nu), 'over 2 uur');
    });
  });
}
