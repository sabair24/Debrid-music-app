/// Het merkteken waarmee een toestel merkt dat een hoes veranderd is.
///
/// **Het geval, gemeld op 13-08-2026.** Op de pc stond de juiste Whitney-hoes, op de telefoon het
/// logo van een verzamelaar. De eigenaar corrigeerde het meermaals; na elke herstart was het weer
/// fout. Oorzaak: de hoescache op een toestel heet naar `artiest|titel`, en die naam beweegt niet
/// als je een ándere afbeelding voor hetzelfde album kiest. Het oude bestand lag er dus nog, met de
/// goede naam en de foute inhoud, en werd elke start opnieuw als waarheid genomen.
///
/// Dit merkteken is wat dat doorbreekt: verandert de gekozen hoes, dan verandert het merk, en het
/// toestel haalt hem opnieuw op.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/enrichment.dart';

Uint8List plaatje(int zaad, {int lengte = 4000}) =>
    Uint8List.fromList([for (var i = 0; i < lengte; i++) (zaad * 31 + i * 7) % 256]);

void main() {
  test('dezelfde hoes geeft hetzelfde merk', () {
    expect(CoverEnricher.hoesMerk(plaatje(1)), CoverEnricher.hoesMerk(plaatje(1)));
  });

  test('een ándere hoes geeft een ander merk', () {
    // Dit is de hele bedoeling: hierop besluit een toestel dat zijn cache achterhaald is.
    expect(CoverEnricher.hoesMerk(plaatje(1)), isNot(CoverEnricher.hoesMerk(plaatje(2))));
  });

  test('een hoes van dezelfde lengte maar andere inhoud ook', () {
    // De lengte alleen zou hier gelijk zijn. Daarom wordt er ook een greep uit de bytes genomen.
    final a = plaatje(5, lengte: 8000);
    final b = Uint8List.fromList(a)..[4000] = (a[4000] + 97) % 256;
    expect(CoverEnricher.hoesMerk(a), isNot(CoverEnricher.hoesMerk(b)));
  });

  test('een langere hoes geeft een ander merk', () {
    expect(CoverEnricher.hoesMerk(plaatje(1, lengte: 4000)),
        isNot(CoverEnricher.hoesMerk(plaatje(1, lengte: 4001))));
  });

  group('wat géén merk krijgt', () {
    test('niets', () => expect(CoverEnricher.hoesMerk(null), ''));

    test('een leeg of nietig plaatje', () {
      // Leeg betekent "geen bewuste keuze". Zou dat wél een merk krijgen, dan zou een album zonder
      // gekozen hoes elke keer als "veranderd" gelden en de cache eindeloos opnieuw ophalen.
      expect(CoverEnricher.hoesMerk(Uint8List(0)), '');
      expect(CoverEnricher.hoesMerk(plaatje(1, lengte: 99)), '');
    });
  });

  test('het merk is kort — het gaat over de lijn, per album', () {
    expect(CoverEnricher.hoesMerk(plaatje(3)).length, lessThanOrEqualTo(8));
  });
}
