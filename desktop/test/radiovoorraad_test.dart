/// De rekensom die de stilte tussen twee nummers weghoudt.
///
/// Een fout hier hoor je meteen: de radio valt stil terwijl er nog van alles te spelen valt, of hij
/// zet in één klap alle muziek die je al hebt vooraan en houdt het nieuwe voor het laatst. Beide zijn
/// precies wat er niet mag gebeuren, en beide zijn hier af te dwingen zonder toestel, zonder net en
/// zonder Soulseek.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/radiovoorraad.dart';

List<Haalstand> standen(String vorm) => [
      for (final c in vorm.split(''))
        switch (c) {
          'w' => Haalstand.wacht,
          'o' => Haalstand.onderweg,
          'k' => Haalstand.klaar,
          'g' => Haalstand.geland,
          'r' => Haalstand.inRij,
          'x' => Haalstand.mislukt,
          _ => throw ArgumentError('onbekende stand: $c'),
        },
    ];

void main() {
  group('wat er in de rij mag', () {
    test('vult aan tot minVooruit en geen nummer meer', () {
      final b = voorraadPlan(standen('kkkkkkkkkk'), vooruitNu: 0, minVooruit: 6);
      expect(b.inRij, [0, 1, 2, 3, 4, 5]);
      expect(b.vooruit, 6);
    });

    test('staat er al genoeg vooruit, dan komt er niets bij', () {
      final b = voorraadPlan(standen('kkkkk'), vooruitNu: 6, minVooruit: 6);
      expect(b.inRij, isEmpty,
          reason: 'alles wat klaar is meteen in de rij zetten geeft eerst een uur eigen muziek en '
              'pas daarna het nieuwe — precies andersom dan de bedoeling');
      expect(b.vooruit, 6);
    });

    test('stapt over wat nog onderweg is in plaats van erop te wachten', () {
      // Plek 0 en 2 worden opgehaald; 1, 3, 4 heb je al. Dit is het geval waarin de radio anders
      // stilvalt: wachten op plek 0 betekent stilte terwijl er drie nummers klaarstaan.
      final b = voorraadPlan(standen('okokk'), vooruitNu: 0, minVooruit: 3);
      expect(b.inRij, [1, 3, 4]);
      expect(b.vooruit, 3);
    });

    test('een overgeslagen plek blijft staan en gaat er later alsnog in', () {
      final eerst = voorraadPlan(standen('okk'), vooruitNu: 0, minVooruit: 2);
      expect(eerst.inRij, [1, 2]);

      // Plek 0 is intussen geland, en de rij is leeggelopen tot één.
      final daarna = voorraadPlan(standen('grr'), vooruitNu: 1, minVooruit: 2);
      expect(daarna.inRij, [0], reason: 'de volgorde van een radio is geen belofte, maar wat '
          'geland is hoort wel gespeeld te worden');
    });

    test('wat in de rij staat komt er nooit een tweede keer in', () {
      final b = voorraadPlan(standen('rrrkk'), vooruitNu: 0, minVooruit: 6);
      expect(b.inRij, [3, 4]);
    });

    test('een mislukte plek laat geen gat: hij telt nergens in mee', () {
      final b = voorraadPlan(standen('xkxkxk'), vooruitNu: 0, minVooruit: 3);
      expect(b.inRij, [1, 3, 5]);
      expect(b.vooruit, 3);
    });

    test('een leeg plan geeft niets en valt niet om', () {
      final b = voorraadPlan(const [], vooruitNu: 0);
      expect(b.inRij, isEmpty);
      expect(b.starten, isEmpty);
      expect(b.vooruit, 0);
    });
  });

  group('wat er opgehaald mag worden', () {
    test('nooit meer dan maxOnderweg tegelijk', () {
      final b = voorraadPlan(standen('wwwwwwwwwwww'), vooruitNu: 9, maxOnderweg: 8);
      expect(b.starten, [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('wat al loopt telt mee voor die grens', () {
      final b = voorraadPlan(standen('ooooowww'), vooruitNu: 9, maxOnderweg: 8);
      expect(b.starten, [5, 6, 7], reason: 'vijf lopen er al, dus er mogen er nog drie bij');
    });

    test('zit de grens vol, dan wordt er niets gestart', () {
      final b = voorraadPlan(standen('oooooooowww'), vooruitNu: 9, maxOnderweg: 8);
      expect(b.starten, isEmpty);
    });

    test('meer dan vol — bijvoorbeeld na een verlaagde grens — start niets en gaat niet negatief', () {
      final b = voorraadPlan(standen('oooooooooow'), vooruitNu: 9, maxOnderweg: 8);
      expect(b.starten, isEmpty);
    });

    test('altijd de vroegste plek die nog niets deed, zodat de radio vooruit MEELOOPT', () {
      final b = voorraadPlan(standen('rrrwwwwwww'), vooruitNu: 3, maxOnderweg: 3);
      expect(b.starten, [3, 4, 5],
          reason: 'achteraan beginnen zou vijfhonderd nummers ophalen voordat je bij de tweede bent');
    });

    test('een mislukte, klare of gelande plek wordt niet opnieuw gestart', () {
      final b = voorraadPlan(standen('xkrxgw'), vooruitNu: 9, maxOnderweg: 8);
      expect(b.starten, [5]);
    });
  });

  group('wat net opgehaald is, gaat er ALTIJD in', () {
    // Dit is de fout die op het toestel gemeld werd, en het is de duurste soort: hij ziet er niet uit
    // als een fout. De radio haalde netjes op, de bestanden stonden er, de schijf liep vol — maar in
    // de speelrij kwamen ze niet, want er stond altijd wel genoeg eigen muziek vooruit. "Ik zit vol
    // met gedownloade liedjes die ik niet zag."
    test('ook als er al ruim genoeg vooruit staat', () {
      final b = voorraadPlan(standen('gg'), vooruitNu: 20, minVooruit: 6);
      expect(b.inRij, [0, 1]);
      expect(b.vooruit, 22);
    });

    test('en eigen muziek juist niet, in datzelfde geval', () {
      final b = voorraadPlan(standen('kgk'), vooruitNu: 20, minVooruit: 6);
      expect(b.inRij, [1], reason: 'alleen het gelande nummer; de rest is vulling die niet nodig is');
    });

    test('gehaalde nummers gaan vóór de vulling, ook als ze verderop in het plan staan', () {
      // De volgorde van [inRij] is de volgorde waarin ze klinken. Wat opgehaald is hoort niet achter
      // een half uur eigen muziek te belanden dat er alleen maar bij kwam om het gat te dichten.
      final b = voorraadPlan(standen('kkg'), vooruitNu: 0, minVooruit: 3);
      expect(b.inRij, [2, 0, 1]);
      expect(b.vooruit, 3);
    });

    test('telt mee voor het gat, dus er komt minder vulling bij', () {
      final b = voorraadPlan(standen('ggkkkkkk'), vooruitNu: 0, minVooruit: 4);
      expect(b.inRij, [0, 1, 2, 3], reason: 'twee geland plus twee eigen nummers is er vier vooruit');
      expect(b.vooruit, 4);
    });
  });

  group('de twee besluiten samen', () {
    test('een verse radio: zes eigen nummers in de rij en acht haaltjes eropuit', () {
      // Zoals hij er bij de start uitziet: wat je al hebt is klaar, de rest wacht.
      final plan = standen('kwkwkwkwkwkwkwkwkwkw');
      final b = voorraadPlan(plan, vooruitNu: 0);

      expect(b.inRij, [0, 2, 4, 6, 8, 10], reason: 'zes speelbare nummers vooruit');
      expect(b.vooruit, kMinVooruit);
      expect(b.starten, hasLength(kMaxOnderweg));
      expect(b.starten.first, 1, reason: 'vooruit meelopen begint bij het eerste gat, niet achteraan');
    });
  });
}
