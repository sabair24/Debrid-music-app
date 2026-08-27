/// Zoekresultaten zeven op waar ze vandaan komen.
///
/// Gevraagd op 27-08-2026: *"ook wil ik bij men torrent zoeken resultaten kunnen filteren, enkel
/// rutracker bevoorbeeld of een ander."*
///
/// Zuiver: lijsten in, lijsten uit. Geen netwerk, geen scherm, dus na te meten zonder toestel.
library;

import 'package:debridmusic/bronzeef.dart';
import 'package:debridmusic/torbox.dart';
import 'package:flutter_test/flutter_test.dart';

SearchResult r(String bron, {String naam = 'iets', int seeders = 1}) =>
    SearchResult(name: naam, magnet: 'magnet:?xt=urn:btih:x', hash: 'x', source: bron, seeders: seeders);

List<String> namen(List<({String bron, int aantal})> b) => [for (final e in b) e.bron];

void main() {
  group('welke bronnen er in de lijst zitten', () {
    test('elke bron één keer, met zijn aantal', () {
      final b = bronnenInResultaten([r('RuTracker'), r('Knaben'), r('RuTracker')]);
      expect(namen(b), ['RuTracker', 'Knaben']);
      expect(b.first.aantal, 2);
      expect(b.last.aantal, 1);
    });

    test('de grootste bron voorop', () {
      final b = bronnenInResultaten([
        r('Knaben'),
        for (var i = 0; i < 5; i++) r('BitSearch'),
        r('Knaben'),
        r('Knaben'),
      ]);
      expect(namen(b), ['BitSearch', 'Knaben']);
    });

    test('bij een gelijk aantal op naam, zodat de knoppen niet omspringen', () {
      // Zonder deze regel hangt de volgorde af van de toevallige volgorde van binnenkomst, en dan
      // staat de knop waar je net op tikte de volgende keer ergens anders.
      final eerst = bronnenInResultaten([r('Zeta'), r('Alfa')]);
      final andersom = bronnenInResultaten([r('Alfa'), r('Zeta')]);
      expect(namen(eerst), ['Alfa', 'Zeta']);
      expect(namen(andersom), ['Alfa', 'Zeta']);
    });

    test('een treffer zonder bron telt niet mee', () {
      // Er is niets om op te tikken, dus er hoort geen lege knop te verschijnen.
      expect(namen(bronnenInResultaten([r(''), r('  '), r('RuTracker')])), ['RuTracker']);
    });

    test('een lege lijst geeft een lege lijst', () {
      expect(bronnenInResultaten(const []), isEmpty);
    });
  });

  group('de zeef zelf', () {
    test('null laat alles door', () {
      expect(pastBijBron(r('RuTracker'), null), isTrue);
      expect(pastBijBron(r('Knaben'), null), isTrue);
    });

    test('een keuze laat alleen die bron door', () {
      expect(pastBijBron(r('RuTracker'), 'RuTracker'), isTrue);
      expect(pastBijBron(r('Knaben'), 'RuTracker'), isFalse);
    });

    test('spaties eromheen tellen niet mee', () {
      expect(pastBijBron(r(' RuTracker '), 'RuTracker'), isTrue);
    });

    test('hoofdletters tellen wél mee — het zijn de namen die de bronnen zelf sturen', () {
      expect(pastBijBron(r('rutracker'), 'RuTracker'), isFalse);
    });
  });

  group('DE KERN: een keuze die niets meer betekent valt terug op alles', () {
    test('een bron die na een nieuwe zoekopdracht niets opleverde', () {
      // Anders kijk je naar een lege lijst met een knop die nergens meer bij hoort, en lijkt het
      // alsof de zoekopdracht niets vond.
      final bronnen = bronnenInResultaten([r('Knaben'), r('BitSearch')]);
      expect(geldigeKeuze('RuTracker', bronnen), isNull);
    });

    test('een bron die er nog wél is blijft staan', () {
      final bronnen = bronnenInResultaten([r('Knaben'), r('RuTracker')]);
      expect(geldigeKeuze('RuTracker', bronnen), 'RuTracker');
    });

    test('geen keuze blijft geen keuze', () {
      expect(geldigeKeuze(null, bronnenInResultaten([r('Knaben')])), isNull);
    });

    test('een lege uitslag laat geen keuze overeind', () {
      expect(geldigeKeuze('RuTracker', const []), isNull);
    });
  });

  group('samen: zeven zoals het scherm het doet', () {
    test('alleen RuTracker houdt precies de RuTracker-rijen over', () {
      final alles = [
        r('RuTracker', naam: 'a'),
        r('Knaben', naam: 'b'),
        r('RuTracker', naam: 'c'),
        r('BitSearch', naam: 'd'),
      ];
      final keuze = geldigeKeuze('RuTracker', bronnenInResultaten(alles));
      final over = [for (final x in alles) if (pastBijBron(x, keuze)) x.name];
      expect(over, ['a', 'c']);
    });

    test('het aantal op de knop klopt met wat je erna ziet', () {
      // Dit is de belofte van die knop: staat er "RuTracker 2", dan staan er daarna twee rijen.
      final alles = [r('RuTracker'), r('Knaben'), r('RuTracker')];
      final bronnen = bronnenInResultaten(alles);
      for (final b in bronnen) {
        final over = alles.where((x) => pastBijBron(x, b.bron)).length;
        expect(over, b.aantal, reason: 'de teller van ${b.bron} moet kloppen');
      }
    });
  });
}
