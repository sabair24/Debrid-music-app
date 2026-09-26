/// Bekend · Gemengd · Ontdekken: hoe diep een radio in het werk van een artiest graaft.
///
/// Saber op 26-09-2026: *"ik wil ergens een keuze maken dat de radio bekende of minder bekende liedjes
/// neemt, functie bekend in youtube music."* De middelste stand moet de radio blijven zoals hij was,
/// en afstemmen mag niet onderbreken wat je nu hoort.
library;

import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiosmaak.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Nr = ({String titel, int rank});

List<String> titels(List<Nr> l) => [for (final n in l) n.titel];

Radioplek plek(String artiest, String titel, Haalstand stand) =>
    Radioplek(artiest: artiest, titel: titel)..stand = stand;

void main() {
  group('de maten', () {
    test('DE GRENS: Gemengd is precies de radio van vóór deze keuze', () {
      // `mixRadio` vroeg vijftien toppers van de zaad, vier buren met hun top vijf, en van de namen
      // van het model de top vier. Wie niets kiest, merkt niets.
      final m = maatVan(Radiosmaak.gemengd);
      expect((m.zaadVanaf, m.zaadAantal, m.buren, m.burenVanaf, m.burenAantal),
          (0, 15, 4, 0, 5));
      expect((m.modelVanaf, m.modelAantal), (0, 4));
    });

    test('DE KERN: Bekend blijft bij de kop van elke lijst', () {
      final m = maatVan(Radiosmaak.bekend);
      expect(m.zaadVanaf, 0);
      expect(m.burenVanaf, 0);
      expect(m.modelVanaf, 0);
      expect(m.zaadAantal, lessThan(maatVan(Radiosmaak.gemengd).zaadAantal));
    });

    test('DE KERN: Ontdekken slaat de grootste hits over en neemt meer buren', () {
      final m = maatVan(Radiosmaak.ontdekken);
      expect(m.zaadVanaf, greaterThan(0), reason: 'niet weer Freak Out en Lift U Up');
      expect(m.burenVanaf, greaterThan(0));
      expect(m.buren, greaterThan(maatVan(Radiosmaak.gemengd).buren));
    });
  });

  group('de artiestenradio van Deezer', () {
    // Een stuk van wat Deezer op 26-09-2026 voor 2 Fabiola gaf, met zijn `rank`.
    const radio = <Nr>[
      (titel: 'Insanity', rank: 106803),
      (titel: "I Don't Care", rank: 297699),
      (titel: 'Single All Summer', rank: 50588),
      (titel: 'Rame', rank: 272912),
      (titel: 'Raise Your Hands', rank: 2934),
      (titel: 'Friends', rank: 186762),
    ];

    test('DE KERN: Bekend houdt de bovenste helft, in de volgorde waarin hij kwam', () {
      expect(titels(radioHelft(radio, (n) => n.rank, Radiosmaak.bekend)),
          ["I Don't Care", 'Rame', 'Friends']);
    });

    test('DE KERN: Ontdekken de onderste helft', () {
      expect(titels(radioHelft(radio, (n) => n.rank, Radiosmaak.ontdekken)),
          ['Insanity', 'Single All Summer', 'Raise Your Hands']);
    });

    test('DE GRENS: Gemengd laat alles staan', () {
      expect(titels(radioHelft(radio, (n) => n.rank, Radiosmaak.gemengd)), titels(radio));
    });

    test('DE VAL: samen is het de hele lijst — er valt niets tussen de twee in', () {
      const oneven = <Nr>[
        (titel: 'a', rank: 5),
        (titel: 'b', rank: 3),
        (titel: 'c', rank: 4),
        (titel: 'd', rank: 1),
        (titel: 'e', rank: 2),
      ];
      final boven = titels(radioHelft(oneven, (n) => n.rank, Radiosmaak.bekend));
      final onder = titels(radioHelft(oneven, (n) => n.rank, Radiosmaak.ontdekken));
      expect(boven, ['a', 'b', 'c'], reason: 'bij een oneven aantal krijgt Bekend de middelste');
      expect(onder, ['d', 'e']);
    });

    test('DE VAL: gelijke rang breekt op de volgorde, niet op toeval', () {
      const gelijk = <Nr>[(titel: 'x', rank: 0), (titel: 'y', rank: 0)];
      expect(titels(radioHelft(gelijk, (n) => n.rank, Radiosmaak.bekend)), ['x']);
      expect(titels(radioHelft(gelijk, (n) => n.rank, Radiosmaak.ontdekken)), ['y']);
    });
  });

  group('de namen van het model', () {
    // `true` = je kent deze artiest waarschijnlijk al.
    const namen = [('Technotronic', true), ('Fiocco', false), ('Snap!', true), ('Sylver', false)];

    test('DE KERN: Ontdekken zet wie nieuw voor je is vooraan', () {
      expect([for (final n in modelVolgorde(namen, (n) => n.$2, Radiosmaak.ontdekken)) n.$1],
          ['Fiocco', 'Sylver', 'Technotronic', 'Snap!']);
    });

    test('DE KERN: Bekend zet wie je kent vooraan', () {
      expect([for (final n in modelVolgorde(namen, (n) => n.$2, Radiosmaak.bekend)) n.$1],
          ['Technotronic', 'Snap!', 'Fiocco', 'Sylver']);
    });

    test('DE GRENS: Gemengd laat de volgorde van het model staan', () {
      expect(modelVolgorde(namen, (n) => n.$2, Radiosmaak.gemengd), namen);
    });
  });

  group('afstemmen tijdens het luisteren', () {
    test('DE KERN: wat speelt, onderweg is of net landde blijft; de rest wordt vervangen', () {
      final plan = [
        plek('2 Fabiola', 'Freak Out', Haalstand.inRij),
        plek('Cappella', 'Move On Baby', Haalstand.onderweg),
        plek('Mo-Do', 'Eins, Zwei, Polizei', Haalstand.geland),
        plek('Kadoc', 'The Night Train', Haalstand.mislukt),
        plek('Sash!', 'Encore Une Fois', Haalstand.wacht),
        plek('Dune', 'Hardcore Vibes', Haalstand.klaar),
      ];
      final nieuw = [
        plek('T-Spoon', 'Sex on the Beach', Haalstand.wacht),
        plek('Cappella', 'Move On Baby', Haalstand.wacht),
      ];
      final uit = stemPlanAf(plan, nieuw);
      expect([for (final p in uit) p.titel],
          ['Freak Out', 'Move On Baby', 'Eins, Zwei, Polizei', 'The Night Train', 'Sex on the Beach'],
          reason: 'Sash! en Dune waren gekozen onder de vorige stand; Move On Baby is al onderweg');
    });

    test('DE VAL: eigen muziek die al IN de rij staat blijft, en die nog niet in de rij stond niet', () {
      // Een eigen nummer dat nog niet klinkt is `klaar`; staat het in de rij, dan is het `inRij`.
      final plan = [
        plek('Milk Inc.', 'Walk on Water', Haalstand.inRij),
        plek('Milk Inc.', 'In My Eyes', Haalstand.klaar),
      ];
      expect([for (final p in stemPlanAf(plan, const [])) p.titel], ['Walk on Water']);
    });
  });

  test('DE GRENS: een onbekende of lege stand leest als Gemengd', () {
    expect(Radiosmaak.uit('bekend'), Radiosmaak.bekend);
    expect(Radiosmaak.uit('ontdekken'), Radiosmaak.ontdekken);
    expect(Radiosmaak.uit(''), Radiosmaak.gemengd);
    expect(Radiosmaak.uit(null), Radiosmaak.gemengd);
    expect(Radiosmaak.uit('populair'), Radiosmaak.gemengd);
  });
}
