/// De functie die je bestanden wist.
///
/// `opruimplan` beslist welke nummers er van je schijf gaan als je een radio afsluit, en wissen heeft
/// geen weg terug. Elke regel hieronder is er één die op het toestel niet meer te herstellen zou zijn:
/// een favoriet die verdwijnt, een afspeellijst met een gat erin, of — het ergste geval — muziek die
/// je zelf verzameld hebt en die de radio nooit had mogen aanraken.
///
/// De onderste toets in deze groep gaat over precies dat laatste. Hij lijkt flauw ("alleen wat er in
/// de lijst staat"), maar hij legt de afspraak vast waar de hele opzet aan hangt: de lijst bevat
/// uitsluitend landingen op een pad dat vóór de download níét in je bibliotheek stond.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/oordelen.dart';
import 'package:debridmusic/radiosessie.dart';

Gehaald g(String titel, {String pad = '', int bytes = 0}) => Gehaald(
      pad: pad.isEmpty ? 'D:\\m\\Singles\\A\\$titel.flac' : pad,
      artiest: 'A',
      titel: titel,
      id: 'id-$titel',
      bytes: bytes,
    );

List<String> titels(List<Gehaald> l) => [for (final x in l) x.titel];

void main() {
  group('opruimplan', () {
    test('zonder oordeel gaat het weg — alleen groen blijft', () {
      final uit = opruimplan(gehaald: [g('een'), g('twee')]);
      expect(titels(uit.blijft), isEmpty);
      expect(titels(uit.weg), ['een', 'twee']);
    });

    test('duim omhoog blijft, duim omlaag gaat weg', () {
      final oordelen = {'een': Oordeel.omhoog, 'twee': Oordeel.omlaag};
      final uit = opruimplan(
        gehaald: [g('een'), g('twee'), g('drie')],
        oordeel: (x) => oordelen[x.titel],
      );
      expect(titels(uit.blijft), ['een']);
      expect(titels(uit.weg), ['twee', 'drie']);
    });

    test('een favoriet blijft, ook met een rode duim erop', () {
      final uit = opruimplan(
        gehaald: [g('een')],
        oordeel: (_) => Oordeel.omlaag,
        isFavoriet: (_) => true,
      );
      expect(titels(uit.blijft), ['een'],
          reason: 'die twee kunnen alleen samen bestaan als iemand van gedachten veranderd is, en '
              'dan is bewaren het antwoord dat terug te draaien is');
      expect(uit.weg, isEmpty);
    });

    test('een nummer in een afspeellijst blijft, ook met een rode duim erop', () {
      final uit = opruimplan(
        gehaald: [g('een')],
        oordeel: (_) => Oordeel.omlaag,
        inAfspeellijst: (_) => true,
      );
      expect(titels(uit.blijft), ['een'],
          reason: 'een afspeellijst met een gat erin is stuk, en dat merk je pas maanden later');
    });

    test('wat je bij het afsluiten terughaalt blijft', () {
      final een = g('een');
      final uit = opruimplan(
        gehaald: [een, g('twee')],
        oordeel: (_) => Oordeel.omlaag,
        gered: {een.pad},
      );
      expect(titels(uit.blijft), ['een']);
      expect(titels(uit.weg), ['twee']);
    });

    test('hetzelfde pad twee keer wordt één keer geteld', () {
      // Kan echt: een haal die mislukte en later alsnog landde staat er twee keer in. Twee keer
      // wissen van hetzelfde bestand is de tweede keer een foutmelding, en twee keer in het
      // overzicht is een leugen over hoeveel er weggaat.
      final uit = opruimplan(gehaald: [g('een'), g('een')]);
      expect(uit.weg, hasLength(1));
    });

    test('alleen wat in de lijst staat — de radio raakt niets anders aan', () {
      // De afspraak waar alles aan hangt: deze lijst bevat uitsluitend landingen op een pad dat vóór
      // de download niet in de bibliotheek stond. Een lege lijst betekent dus dat er niets te wissen
      // valt, hoeveel muziek er ook gespeeld is.
      final uit = opruimplan(gehaald: const [], oordeel: (_) => Oordeel.omlaag);
      expect(uit.weg, isEmpty);
      expect(uit.blijft, isEmpty);
    });
  });

  group('de notitie op schijf', () {
    test('gaat heen en terug zonder iets te verliezen', () {
      final s = RadioSessie(
        naam: 'Eurodance',
        begonnenMs: 1700000000000,
        gehaald: [g('een', bytes: 38 * 1024 * 1024), g('twee')],
      );
      final terug = RadioSessie.fromJson(s.toJson())!;
      expect(terug.naam, 'Eurodance');
      expect(terug.begonnenMs, 1700000000000);
      expect(titels(terug.gehaald), ['een', 'twee']);
      expect(terug.gehaald.first.bytes, 38 * 1024 * 1024);
      expect(terug.gehaald.first.id, 'id-een');
    });

    test('een half geschreven of met de hand bewerkt bestand levert geen brokken op', () {
      expect(RadioSessie.fromJson(null), isNull);
      expect(RadioSessie.fromJson('rommel'), isNull);
      final half = RadioSessie.fromJson({'gehaald': ['geen kaart', {}, {'pad': ''}]})!;
      expect(half.gehaald, isEmpty, reason: 'een rij zonder pad is nergens naar te wijzen');
      expect(half.leeg, isTrue);
    });
  });

  group('oordeelBonus', () {
    test('groen weegt zwaarder, rood weegt lichter, geen mening verandert niets', () {
      expect(oordeelBonus(Oordeel.omhoog), greaterThan(1));
      expect(oordeelBonus(null), 1);
      expect(oordeelBonus(Oordeel.omlaag), lessThan(1));
    });

    test('rood is nooit nul', () {
      // Bij een nummer dat je HOUDT is rood geen "gooi weg" maar "liever niet nu". Nul zou betekenen
      // dat je het nooit meer hoort, ook niet over een jaar, en dat is niet wat een duim zegt.
      expect(oordeelBonus(Oordeel.omlaag), greaterThan(0));
    });
  });

  group('de naam waaronder een oordeel wordt opgeslagen', () {
    test('blijft "up" en "down"', () {
      // Dit gaat over de lijn en in een bestand. Een hernoemde enum zou stilletjes elk opgeslagen
      // oordeel ongeldig maken — geen foutmelding, gewoon weg.
      expect(Oordeel.omhoog.opNaam, 'up');
      expect(Oordeel.omlaag.opNaam, 'down');
      expect(Oordeel.vanNaam('up'), Oordeel.omhoog);
      expect(Oordeel.vanNaam('down'), Oordeel.omlaag);
      expect(Oordeel.vanNaam(''), isNull);
      expect(Oordeel.vanNaam(null), isNull);
      expect(Oordeel.vanNaam('omhoog'), isNull);
    });
  });
}
