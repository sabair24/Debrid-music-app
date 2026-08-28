/// De enige rem tussen een model dat zich vergist en honderdduizend downloads.
///
/// De Messages-API weigert getalgrenzen in een JSON-schema: `minimum` en `maximum` leveren een 400 op,
/// en een schema dat geweigerd wordt levert helemaal geen antwoord. Er is dus NIETS wat begrenst wat
/// er terugkomt, behalve [leesRadioOpdracht]. Deze functie ís de grens, en daarom staat elke regel
/// ervan hieronder als toets.
///
/// De gevallen zijn niet verzonnen om streng te lijken: een taalmodel dat "500" leest als "50000",
/// dat een jaartal van twee cijfers teruggeeft, of dat dezelfde artiest zes keer noemt met een andere
/// hoofdletter — dat gebeurt, en elk daarvan zou hier iets kosten dat niet terug te draaien is.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/radioplan.dart';

void main() {
  group('het aantal', () {
    test('een gewoon getal komt gewoon door', () {
      expect(leesRadioOpdracht({'aantal': 300, 'zaadArtiesten': ['A']}).aantal, 300);
    });

    test('boven het plafond wordt geklemd en niet geweigerd', () {
      // Klemmen en niet weigeren: een radio van vijfhonderd is nog steeds een radio, en de gebruiker
      // die 100000 typte krijgt liever muziek dan een foutmelding.
      expect(leesRadioOpdracht({'aantal': 100000, 'zaadArtiesten': ['A']}).aantal, kMaxRadio);
    });

    test('nul of negatief wordt één — een radio van nul nummers is geen radio', () {
      expect(leesRadioOpdracht({'aantal': 0, 'zaadArtiesten': ['A']}).aantal, 1);
      expect(leesRadioOpdracht({'aantal': -40, 'zaadArtiesten': ['A']}).aantal, 1);
    });

    test('geen aantal, of onzin, geeft het standaardaantal', () {
      expect(leesRadioOpdracht({'zaadArtiesten': ['A']}).aantal, kStandaardAantal);
      expect(leesRadioOpdracht({'aantal': 'veel', 'zaadArtiesten': ['A']}).aantal, kStandaardAantal);
      expect(leesRadioOpdracht({'aantal': null, 'zaadArtiesten': ['A']}).aantal, kStandaardAantal);
    });

    test('een getal als tekst wordt gelezen', () {
      expect(leesRadioOpdracht({'aantal': '250', 'zaadArtiesten': ['A']}).aantal, 250);
    });
  });

  group('de jaren', () {
    test('een gewoon tijdvak komt door', () {
      final o = leesRadioOpdracht({'jaarVan': 1990, 'jaarTot': 1999, 'zaadArtiesten': ['A']});
      expect(o.jaarVan, 1990);
      expect(o.jaarTot, 1999);
    });

    test('een jaartal dat geen jaartal is, valt weg', () {
      final o = leesRadioOpdracht({'jaarVan': 90, 'jaarTot': 20250, 'zaadArtiesten': ['A']});
      expect(o.jaarVan, isNull);
      expect(o.jaarTot, isNull);
    });

    test('een tijdvak dat achteruit loopt wordt rechtgezet', () {
      // Anders is het tijdvak leeg en levert de radio niets op, zonder dat er iets misgaat.
      final o = leesRadioOpdracht({'jaarVan': 1999, 'jaarTot': 1990, 'zaadArtiesten': ['A']});
      expect(o.jaarVan, 1999);
      expect(o.jaarTot, 1999);
    });

    test('alleen een beginjaar mag', () {
      final o = leesRadioOpdracht({'jaarVan': 1995, 'zaadArtiesten': ['A']});
      expect(o.jaarVan, 1995);
      expect(o.jaarTot, isNull);
    });
  });

  group('de zaadartiesten', () {
    test('spaties eraf, lege namen eruit', () {
      final o = leesRadioOpdracht({
        'zaadArtiesten': ['  2 Unlimited ', '', '   ', 'Snap!']
      });
      expect(o.zaadArtiesten, ['2 Unlimited', 'Snap!']);
    });

    test('dezelfde artiest twee keer telt één keer, ook met andere hoofdletters', () {
      final o = leesRadioOpdracht({
        'zaadArtiesten': ['Haddaway', 'haddaway', 'HADDAWAY', 'Culture Beat']
      });
      expect(o.zaadArtiesten, ['Haddaway', 'Culture Beat']);
    });

    test('een naam van vierhonderd tekens is geen artiest', () {
      final o = leesRadioOpdracht({
        'zaadArtiesten': ['x' * 400, 'Technotronic']
      });
      expect(o.zaadArtiesten, ['Technotronic']);
    });

    test('wat geen tekst is, wordt overgeslagen', () {
      final o = leesRadioOpdracht({
        'zaadArtiesten': [42, null, {'naam': 'X'}, 'Milk Inc']
      });
      expect(o.zaadArtiesten, ['Milk Inc']);
    });

    test('er komen er hoogstens zestig door', () {
      final o = leesRadioOpdracht({
        'zaadArtiesten': [for (var i = 0; i < 500; i++) 'Artiest $i']
      });
      expect(o.zaadArtiesten, hasLength(60));
    });

    test('zonder artiesten is de opdracht onbruikbaar', () {
      // Dan valt er niets op te zoeken, en dat hoort te leiden tot "ik snapte het niet" in plaats van
      // een radio die stil leeg blijft.
      expect(leesRadioOpdracht({'genre': 'eurodance'}).bruikbaar, isFalse);
      expect(leesRadioOpdracht({'zaadArtiesten': ['A']}).bruikbaar, isTrue);
    });
  });

  group('wat er terugkomt is niet altijd een antwoord', () {
    test('null, een lijst of een getal levert een lege opdracht op en geen fout', () {
      for (final rommel in <Object?>[null, 'tekst', 42, <int>[1, 2]]) {
        final o = leesRadioOpdracht(rommel);
        expect(o.bruikbaar, isFalse, reason: 'bij $rommel');
        expect(o.aantal, kStandaardAantal);
      }
    });
  });

  group('hoe de radio heet', () {
    test('een tiental leest als "jaren 90" en niet als 1990–1999', () {
      final o = leesRadioOpdracht({
        'genre': 'Eurodance',
        'jaarVan': 1990,
        'jaarTot': 1999,
        'zaadArtiesten': ['A']
      });
      expect(o.naam, 'Eurodance · jaren 90');
    });

    test('de jaren nul houden hun nul', () {
      final o = leesRadioOpdracht(
          {'genre': 'Trance', 'jaarVan': 2000, 'jaarTot': 2009, 'zaadArtiesten': ['A']});
      expect(o.naam, 'Trance · jaren 00');
    });

    test('een eigen tijdvak wordt uitgeschreven', () {
      final o = leesRadioOpdracht(
          {'genre': 'Disco', 'jaarVan': 1976, 'jaarTot': 1981, 'zaadArtiesten': ['A']});
      expect(o.naam, 'Disco · 1976–1981');
    });

    test('zonder iets om over te vertellen heet hij gewoon Radio', () {
      expect(leesRadioOpdracht({'zaadArtiesten': ['A']}).naam, 'Radio');
    });
  });

  group('het schema dat meegaat', () {
    test('staat geen onbekende velden toe', () {
      expect(radioSchema()['additionalProperties'], isFalse,
          reason: 'zonder deze regel weigert de API het schema');
    });

    test('ELK veld staat in required', () {
      // Dit leverde bij de eerste echte poging een 400 op: `jaarVan`, `jaarTot` en `stemming`
      // stonden wel in `properties` maar niet in `required`, en dan weigert de API het hele schema.
      // Er komt dan geen antwoord — niet eens een half antwoord. Een veld dat mag ontbreken hoort
      // een `anyOf` met `null` te zijn, niet een veld dat je weglaat.
      final s = radioSchema();
      final velden = (s['properties'] as Map).keys.map((k) => '$k').toList();
      expect(s['required'], unorderedEquals(velden));
    });

    test('wat mag ontbreken is nullbaar in plaats van afwezig', () {
      final props = radioSchema()['properties'] as Map;
      for (final veld in ['jaarVan', 'jaarTot']) {
        final keuzes = (props[veld] as Map)['anyOf'] as List;
        expect(keuzes.map((k) => (k as Map)['type']), containsAll(<String>['integer', 'null']),
            reason: '$veld moet null kunnen zijn, want hij staat in required');
      }
    });

    test('draagt GEEN getalgrenzen', () {
      // Die worden door de API geweigerd met een 400, en dan komt er helemaal geen antwoord. Het
      // klemmen hoort in leesRadioOpdracht te gebeuren, en deze toets is wat dat zo houdt.
      final velden = (radioSchema()['properties'] as Map).values;
      for (final v in velden) {
        expect((v as Map).containsKey('minimum'), isFalse);
        expect(v.containsKey('maximum'), isFalse);
      }
    });
  });
}
