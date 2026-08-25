/// Wat er in een update zit, uitgelezen uit de beschrijving van de release.
///
/// **Waarom hier een toets op staat.** Dit is een afspraak tussen twee dingen die elkaar niet zien:
/// de bouwstraat schrijft het kopje "## Wat er nieuw is" in de release, en de app leest precies dat
/// blok. Gaat daar iets mis, dan wordt er niets rood — het updatevenster laat gewoon stil de lijst
/// weg, of erger: er komt installatietekst in te staan alsof het een wijziging was. Dat merk je pas
/// op het toestel, en dan is het al uitgegeven.
///
/// De twee gevallen die het echt om doet staan onderaan: tekst NÁ het blok mag er niet in, en een
/// release van vóór deze afspraak moet gewoon niets opleveren.
library;

import 'package:debridmusic/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wat er nieuw is', () {
    test('de regels onder het kopje, zonder streepjes', () {
      final uit = watIsNieuw('''
## DebridMusic v3.9.197 (build 11305)

Dezelfde app als op je pc.

## Wat er nieuw is

- Scrollen hapert niet meer
- De juiste opname, niet alleen het juiste nummer
''');
      expect(uit, ['Scrollen hapert niet meer', 'De juiste opname, niet alleen het juiste nummer']);
    });

    test('het stopt bij het volgende kopje', () {
      // Dit is de valkuil. Zonder deze grens komt "Download de APK hieronder" in het
      // updatevenster te staan alsof het een wijziging was.
      final uit = watIsNieuw('''
## Wat er nieuw is

- Eén ding veranderd

### Installeren
Download de APK hieronder en installeer hem op je telefoon.

> Mogelijk moet je "Installeren uit onbekende bronnen" aanzetten.
''');
      expect(uit, ['Eén ding veranderd']);
    });

    test('een release van vóór deze afspraak levert niets op, en geen fout', () {
      // Elke bestaande release ziet er zo uit. Het venster hoort dan gewoon zijn oude tekst te
      // tonen, niet leeg te blijven of om te vallen.
      expect(
          watIsNieuw('## DebridMusic v3.9.196 (build 11300)\n\nDezelfde app als op je pc.'), isEmpty);
      expect(watIsNieuw(null), isEmpty);
      expect(watIsNieuw(''), isEmpty);
      expect(watIsNieuw('   '), isEmpty);
    });

    test('een kopje zonder regels eronder is ook leeg', () {
      expect(watIsNieuw('## Wat er nieuw is\n\n### Installeren\nIets.'), isEmpty);
      expect(watIsNieuw('## Wat er nieuw is'), isEmpty);
    });

    test('sterretjes tellen net zo goed als streepjes, en regels zonder allebei ook', () {
      expect(watIsNieuw('## Wat er nieuw is\n* Met een sterretje\n- Met een streepje\nZonder iets'),
          ['Met een sterretje', 'Met een streepje', 'Zonder iets']);
    });

    test('Windows-regeleindes breken het niet', () {
      expect(watIsNieuw('## Wat er nieuw is\r\n\r\n- Eén ding\r\n'), ['Eén ding']);
    });

    test('het kopje mag anders geschreven staan, de tekst niet', () {
      expect(watIsNieuw('## WAT ER NIEUW IS\n- Iets'), ['Iets'],
          reason: 'hoofdletters zijn geen andere afspraak');
      expect(watIsNieuw('## Wat is er nieuw\n- Iets'), isEmpty,
          reason: 'een ándere zin is wél een andere afspraak, en dan hoort het stil te blijven');
    });

    test('een lange lijst wordt afgekapt, want een venster is geen changelog', () {
      final veel = ['## Wat er nieuw is', for (var i = 1; i <= 20; i++) '- Ding $i'].join('\n');
      final uit = watIsNieuw(veel);
      expect(uit.length, lessThanOrEqualTo(8));
      expect(uit.first, 'Ding 1', reason: 'de bovenste zijn de nieuwste');
    });

    test('het kopje is precies wat de bouwstraat schrijft', () {
      // Zou dit uit elkaar lopen, dan valt de lijst stil zonder dat er iets rood wordt. Vandaar dat
      // de tekst één keer bestaat en hier tegen zichzelf gelegd wordt.
      expect(kopjeNieuw, '## Wat er nieuw is');
      expect(watIsNieuw('$kopjeNieuw\n- Iets'), ['Iets']);
    });
  });
}
