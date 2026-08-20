/// Het venster op de bronnenlijst: hoeveel er staan, en hoeveel er nog wachten.
///
/// **Waarom dit bestaat.** Er stond een harde grens van 250 met de mededeling "verfijn je
/// zoekopdracht om ze te zien". Dat was onuitvoerbaar advies — bij "men at work down under" zijn
/// artiest én titel al getypt en valt er niets te verfijnen; er zijn gewoon zeventienhonderd mensen
/// die dat nummer delen. De grens was ook nooit een grens van de zoekopdracht maar van het tekenen:
/// alle treffers zaten al in het geheugen.
///
/// Nu gaat het venster open, tweehonderd per tik. Deze rekensom is het soort dat er goed uitziet en
/// er één naast zit, dus staat hij los en wordt hij hier nagemeten.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';

void main() {
  group('het venster op de bronnen', () {
    test('een korte lijst staat er in zijn geheel, zonder knop', () {
      final v = bronVenster(7, 200);
      expect(v.tot, 7);
      expect(v.rest, 0, reason: 'niets meer te tonen, dus geen knop');
      expect(v.volgende, 0);
    });

    test('precies vol is ook vol', () {
      final v = bronVenster(200, 200);
      expect(v.tot, 200);
      expect(v.rest, 0);
    });

    test('de eerste tweehonderd van zeventienhonderd', () {
      // Het gemelde geval: 1442 bronnen, 250 getoond, 1435 "niet getoond".
      final v = bronVenster(1685, 200);
      expect(v.tot, 200);
      expect(v.rest, 1485);
      expect(v.volgende, 200);
    });

    test('elke tik schuift er tweehonderd bij, in dezelfde volgorde', () {
      // De rangschikking zit in de LIJST, niet hier: er wordt gesorteerd voordat er gesneden wordt,
      // dus wat erbij komt is de volgende in dezelfde rij.
      var limiet = 200;
      for (final verwacht in [200, 400, 600, 800]) {
        expect(bronVenster(1685, limiet).tot, verwacht);
        limiet += 200;
      }
    });

    test('de laatste tik zegt hoeveel er ECHT nog zijn', () {
      // 1685 − 1600 = 85. "Nog 200 tonen" zou daar een leugen zijn.
      final v = bronVenster(1685, 1600);
      expect(v.rest, 85);
      expect(v.volgende, 85);
    });

    test('een limiet voorbij het einde valt niet uit de lijst', () {
      // Precies de fout die `sublist` gooit in plaats van vergeeft.
      final v = bronVenster(1685, 2000);
      expect(v.tot, 1685);
      expect(v.rest, 0);
    });

    test('een lege lijst is geen bijzonder geval', () {
      final v = bronVenster(0, 200);
      expect(v.tot, 0);
      expect(v.rest, 0);
      expect(v.volgende, 0);
    });
  });
}
