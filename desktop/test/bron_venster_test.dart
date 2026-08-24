/// Het venster op de bronnenlijst: hoeveel er staan, en hoeveel er nog wachten.
///
/// **Waarom dit bestaat.** Er stond een harde grens van 250 met de mededeling "verfijn je
/// zoekopdracht om ze te zien". Dat was onuitvoerbaar advies — bij "men at work down under" zijn
/// artiest én titel al getypt en valt er niets te verfijnen; er zijn gewoon zeventienhonderd mensen
/// die dat nummer delen. De grens was ook nooit een grens van de zoekopdracht maar van het tekenen:
/// alle treffers zaten al in het geheugen.
///
/// Nu gaat het venster open, [bronStap] per tik. Deze rekensom is het soort dat er goed uitziet en
/// er één naast zit, dus staat hij los en wordt hij hier nagemeten.
///
/// **Het getal staat hier nergens uitgeschreven, en dat is de les van vandaag.** Er stond `200` in
/// deze toets, en toen de stap naar vijftig ging brak hij — niet omdat de rekensom fout was, maar
/// omdat de toets een tweede keer opschreef wat al ergens vastlag. Een toets die zijn eigen
/// verwachting uit de code haalt, bewaakt het gedrag; een toets die het getal herhaalt, bewaakt
/// alleen het getal.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';

void main() {
  group('het venster op de bronnen', () {
    test('een korte lijst staat er in zijn geheel, zonder knop', () {
      final v = bronVenster(7, bronStap);
      expect(v.tot, 7);
      expect(v.rest, 0, reason: 'niets meer te tonen, dus geen knop');
      expect(v.volgende, 0);
    });

    test('precies vol is ook vol', () {
      final v = bronVenster(bronStap, bronStap);
      expect(v.tot, bronStap);
      expect(v.rest, 0);
    });

    test('de eerste stap van een lange lijst', () {
      // Het gemelde geval: 1442 bronnen, 250 getoond, 1435 "niet getoond".
      final v = bronVenster(1685, bronStap);
      expect(v.tot, bronStap);
      expect(v.rest, 1685 - bronStap);
      expect(v.volgende, bronStap);
    });

    test('elke tik schuift er een stap bij, in dezelfde volgorde', () {
      // De rangschikking zit in de LIJST, niet hier: er wordt gesorteerd voordat er gesneden wordt,
      // dus wat erbij komt is de volgende in dezelfde rij.
      var limiet = bronStap;
      for (var ronde = 1; ronde <= 4; ronde++) {
        expect(bronVenster(1685, limiet).tot, bronStap * ronde);
        limiet += bronStap;
      }
    });

    test('de laatste tik zegt hoeveel er ECHT nog zijn', () {
      // Zeven over, dus "Nog een hele stap tonen" zou hier een leugen zijn.
      final v = bronVenster(1685, 1685 - 7);
      expect(v.rest, 7);
      expect(v.volgende, 7);
    });

    test('zolang er méér dan een stap over is, staat er een hele stap', () {
      final v = bronVenster(1685, 1685 - bronStap - 1);
      expect(v.rest, bronStap + 1);
      expect(v.volgende, bronStap, reason: 'niet meer beloven dan een tik oplevert');
    });

    test('een limiet voorbij het einde valt niet uit de lijst', () {
      // Precies de fout die `sublist` gooit in plaats van vergeeft.
      final v = bronVenster(1685, 2000);
      expect(v.tot, 1685);
      expect(v.rest, 0);
    });

    test('een lege lijst is geen bijzonder geval', () {
      final v = bronVenster(0, bronStap);
      expect(v.tot, 0);
      expect(v.rest, 0);
      expect(v.volgende, 0);
    });
  });
}
