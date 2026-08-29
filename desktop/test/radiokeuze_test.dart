/// Waarom een radio niet vijf keer hetzelfde liedje speelt.
///
/// De lijst van een radio komt van Deezer, en die geeft per artiest de toppers. Bij dance uit de
/// jaren negentig zijn dat zelden tien verschillende liedjes — het zijn er twee of drie in acht
/// uitvoeringen. Gemeld op 29-08-2026: "meer de originele en radio edits dan remixen, het mag wel
/// maar het is te veel nu."
///
/// Dat is smaak, en juist daarom hoort het hier na te rekenen te zijn in plaats van in het hoofd van
/// wie het geschreven heeft.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/radiokeuze.dart';

List<Aanbod> aanbod(List<String> titels, {String artiest = 'Snap!'}) =>
    [for (final t in titels) (artiest: artiest, titel: t)];

List<String> gekozen(List<String> titels, {int bewerkingPerTien = kBewerkingPerTien}) {
  final a = aanbod(titels);
  return [for (final i in kiesNummers(a, bewerkingPerTien: bewerkingPerTien)) a[i].titel];
}

void main() {
  group('wat voor uitvoering het is', () {
    test('een kale titel is de gewone versie', () {
      expect(uitvoeringVan('Rhythm Is a Dancer'), Uitvoering.origineel);
      expect(uitvoeringVan('Mr. Vain'), Uitvoering.origineel);
    });

    test('een radio-edit telt als gewone versie, tussen haakjes én achter een streepje', () {
      // Bij dance uit de jaren negentig ís de radio-edit vaak de versie die iedereen kent, dus die
      // hoort net zo welkom te zijn als de plaatversie.
      expect(uitvoeringVan('Mr. Vain (Radio Edit)'), Uitvoering.radio);
      expect(uitvoeringVan('Mr. Vain - Radio Edit'), Uitvoering.radio);
      expect(uitvoeringVan('Be My Lover (Single Version)'), Uitvoering.radio);
      expect(uitvoeringVan('Coco Jamboo - 7" Version'), Uitvoering.radio);
    });

    test('"Radio Mix" is geen remix, ook al staat het woord mix erin', () {
      // Dit is de val waar een simpele zoektocht naar "mix" in trapt, en het zou juist de versie
      // weggooien die gevraagd werd.
      expect(uitvoeringVan('What Is Love (Radio Mix)'), Uitvoering.radio);
      expect(uitvoeringVan('What Is Love (Original Mix)'), Uitvoering.radio);
    });

    test('en dit zijn wél bewerkingen', () {
      for (final t in [
        'Rhythm Is a Dancer (Extended Mix)',
        'Rhythm Is a Dancer (Club Mix)',
        'Rhythm Is a Dancer - 12" Mix',
        'Rhythm Is a Dancer (Dub)',
        'Rhythm Is a Dancer (Instrumental)',
        'Rhythm Is a Dancer (Live)',
        'Rhythm Is a Dancer (DJ Bobo Remix)',
      ]) {
        expect(uitvoeringVan(t), Uitvoering.bewerking, reason: t);
      }
    });

    test('een remix-edit is een remix en geen radio-edit', () {
      // "Edit" op zichzelf betekent radioversie, maar niet als er ook "remix" staat. De volgorde
      // waarin de merktekens gelezen worden is dus geen willekeur.
      expect(uitvoeringVan('Mr. Vain (Remix Edit)'), Uitvoering.bewerking);
    });

    test('een haakje dat niets over de uitvoering zegt, verandert niets', () {
      expect(uitvoeringVan("What Is Love (Baby Don't Hurt Me)"), Uitvoering.origineel);
      expect(uitvoeringVan('Sadeness - Part I'), Uitvoering.origineel);
    });
  });

  group('van één liedje één uitvoering', () {
    test('de gewone versie wint van de remix', () {
      expect(
        gekozen(['Mr. Vain (Extended Mix)', 'Mr. Vain', 'Mr. Vain (Club Mix)']),
        ['Mr. Vain'],
      );
    });

    test('een radio-edit wint óók van de remix', () {
      expect(
        gekozen(['Mr. Vain (Club Mix)', 'Mr. Vain - Radio Edit']),
        ['Mr. Vain - Radio Edit'],
      );
    });

    test('is er alleen een remix, dan mag die er gewoon in', () {
      // Weggooien zou het liedje kosten, en van sommige dansplaten bestáát alleen een clubversie.
      // Het rantsoen hieronder beslist verder wanneer hij aan de beurt is; hier gaat het erom dat
      // regel 1 hem niet wegstreept bij gebrek aan een gewone versie.
      final uit = gekozen(['A', 'B', 'C', 'D', 'Mr. Vain (Club Mix)']);
      expect(uit, contains('Mr. Vain (Club Mix)'));
    });

    test('twee artiesten met dezelfde titel zijn twee liedjes', () {
      final a = <Aanbod>[
        (artiest: 'Haddaway', titel: 'What Is Love'),
        (artiest: 'Twice', titel: 'What Is Love'),
      ];
      expect(kiesNummers(a), [0, 1]);
    });

    test('de volgorde die erin ging blijft staan', () {
      // Bij een radio is dat een GESCHUDDE volgorde, en die opnieuw sorteren zou betekenen dat je
      // altijd met dezelfde artiest begint.
      expect(
        gekozen(['Coco Jamboo', 'Be My Lover', 'Mr. Vain']),
        ['Coco Jamboo', 'Be My Lover', 'Mr. Vain'],
      );
    });
  });

  group('het rantsoen voor de rest', () {
    test('een radio begint nooit met een bewerking', () {
      final uit = gekozen([
        'A (Club Mix)',
        'B',
        'C',
        'D',
        'E',
      ]);
      expect(uit.first, 'B');
    });

    test('hoogstens twee op de tien', () {
      final titels = [
        for (var i = 0; i < 10; i++) 'Gewoon $i',
        for (var i = 0; i < 10; i++) 'Remixje $i (Club Mix)',
      ];
      final uit = gekozen(titels);
      final bewerkingen = uit.where((t) => uitvoeringVan(t) == Uitvoering.bewerking).length;
      expect(bewerkingen * 10, lessThanOrEqualTo(uit.length * kBewerkingPerTien));
      expect(bewerkingen, greaterThan(0), reason: 'niet nul: het mag wel, het was alleen te veel');
    });

    test('een rantsoen van tien op tien laat alles staan', () {
      final uit = gekozen(['A (Club Mix)', 'B (Dub)'], bewerkingPerTien: 10);
      expect(uit, hasLength(2));
    });

    test('een rantsoen van nul houdt alle bewerkingen tegen', () {
      expect(gekozen(['A (Club Mix)', 'B'], bewerkingPerTien: 0), ['B']);
    });

    test('nog eens zeven verandert niets meer', () {
      // `_radioplan` zeeft élke radio, ook een lijst die in `_nummersVoor` al gezeefd is. Dat mag
      // geen tweede hap uit dezelfde lijst nemen, anders krimpt een radio bij elke stap.
      final titels = [
        for (var i = 0; i < 12; i++) 'Gewoon $i',
        for (var i = 0; i < 8; i++) 'Remixje $i (Extended Mix)',
      ];
      final eerst = gekozen(titels);
      expect(gekozen(eerst), eerst);
    });

    test('een lege lijst geeft een lege lijst', () {
      expect(kiesNummers(const []), isEmpty);
    });
  });
}
