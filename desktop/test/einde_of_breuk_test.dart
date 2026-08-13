/// Wanneer "afgelopen" niet betekent dat het nummer uit is.
///
/// **Het geval, gemeld uit de auto op 13-08-2026:** "ik hoor de muziek wel, maar hij skipt naar het
/// volgende midden in een track." De telefoon streamt van de pc; valt die verbinding onderweg even
/// weg, dan ziet mpv het einde van het bestand en meldt "afgelopen". De app deed vervolgens precies
/// wat haar gevraagd werd — door naar het volgende. Op mobiel internet gebeurt dat om de haverklap,
/// en van buiten lijkt het alsof de app zelf staat te springen.
///
/// De positie en de looptijd stonden er allebei al. Er keek alleen niemand naar.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/player.dart';

Duration s(int n) => Duration(seconds: n);

void main() {
  test('een nummer dat halverwege ophoudt is een breuk, geen einde', () {
    expect(
      watNaHetEinde(positie: s(94), duur: s(215), herhaal: RepeatMode.off, mislukt: 0),
      NaHetEinde.stroomHervatten,
    );
  });

  test('een nummer dat uitspeelt gaat gewoon door', () {
    expect(
      watNaHetEinde(positie: s(215), duur: s(215), herhaal: RepeatMode.off, mislukt: 0),
      NaHetEinde.volgende,
    );
  });

  test('een paar seconden korter is nog steeds afgelopen', () {
    // Afrondingen en de stilte aan het eind. Zou dit als breuk tellen, dan opende de app élk nummer
    // drie keer opnieuw voordat hij verder ging.
    expect(
      watNaHetEinde(positie: s(213), duur: s(215), herhaal: RepeatMode.off, mislukt: 0),
      NaHetEinde.volgende,
    );
  });

  test('de grens ligt op tien seconden', () {
    expect(watNaHetEinde(positie: s(205), duur: s(215), herhaal: RepeatMode.off, mislukt: 0),
        NaHetEinde.volgende);
    expect(watNaHetEinde(positie: s(204), duur: s(215), herhaal: RepeatMode.off, mislukt: 0),
        NaHetEinde.stroomHervatten);
  });

  test('zonder looptijd valt er niets te vergelijken', () {
    // Een radiostroom heeft geen einde. Dan maar het oude gedrag, in plaats van eindeloos hervatten.
    expect(
      watNaHetEinde(positie: s(94), duur: Duration.zero, herhaal: RepeatMode.off, mislukt: 0),
      NaHetEinde.volgende,
    );
  });

  test('na drie pogingen gaan we toch door', () {
    // Anders blijft de app op één nummer hangen als de pc echt uit staat, zonder ooit iets te zeggen.
    for (var i = 0; i < 3; i++) {
      expect(watNaHetEinde(positie: s(94), duur: s(215), herhaal: RepeatMode.off, mislukt: i),
          NaHetEinde.stroomHervatten,
          reason: 'poging $i');
    }
    expect(watNaHetEinde(positie: s(94), duur: s(215), herhaal: RepeatMode.off, mislukt: 3),
        NaHetEinde.volgende);
  });

  group('naast de herhaalstand', () {
    test('"dit nummer" herhaalt pas als het écht uit is', () {
      expect(
        watNaHetEinde(positie: s(215), duur: s(215), herhaal: RepeatMode.one, mislukt: 0),
        NaHetEinde.ditNummerOpnieuw,
      );
    });

    test('een breuk gaat vóór de herhaalstand', () {
      // Anders begint een afgebroken nummer bij herhaal-één telkens van voren af aan, en kom je
      // nooit voorbij de plek waar het netwerk hikt.
      expect(
        watNaHetEinde(positie: s(94), duur: s(215), herhaal: RepeatMode.one, mislukt: 0),
        NaHetEinde.stroomHervatten,
      );
    });

    test('en na het opgeven herhaalt hij alsnog', () {
      expect(
        watNaHetEinde(positie: s(94), duur: s(215), herhaal: RepeatMode.one, mislukt: 3),
        NaHetEinde.ditNummerOpnieuw,
      );
    });
  });
}
