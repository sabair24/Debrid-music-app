/// Waarom er van een plaat van honderd nummers maar een handvol overbleef.
///
/// Een torrent wordt PLAT uitgepakt: alles gaat op zijn eigen bestandsnaam naar één map. Bij één
/// album gaat dat goed. Bij een verzamelbox, een dubbel-cd of een discografie heet elke schijf
/// opnieuw `01 - ….flac`, en `File.rename` schrijft zonder één woord over het vorige heen. Elke taak
/// meldde "klaar", en de originelen waren daarna al opgeruimd.
///
/// Gemeld op 29-08-2026: "ik wou France Gall downloaden, en maar 2 liedjes zijn binnengekomen?? waar
/// is de rest?"
///
/// [vrijeNamen] is wat dat voorkomt. Zuiver, want welke naam er gekozen wordt mag niet afhangen van
/// wat er toevallig op de schijf staat.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/organize.dart';

/// De eerste [n] namen die aangeboden worden.
List<String> eerste(int n, String naam, {String submap = ''}) =>
    vrijeNamen(naam, submap: submap).take(n).toList();

void main() {
  group('welke naam er aangeboden wordt', () {
    test('de gevraagde naam staat vooraan', () {
      expect(eerste(1, '01 - Sacré Charlemagne.flac'), ['01 - Sacré Charlemagne.flac']);
    });

    test('daarna de map waar het in de torrent stond', () {
      // "CD2 - 01 - ….flac" zegt nog waar het vandaan komt; "01 - … (2).flac" zegt niets.
      expect(eerste(2, '01 - Poupée de cire.flac', submap: 'CD2').last,
          'CD2 - 01 - Poupée de cire.flac');
    });

    test('en pas daarna wordt er geteld', () {
      expect(eerste(4, '01.flac', submap: 'CD2'),
          ['01.flac', 'CD2 - 01.flac', 'CD2 - 01 (2).flac', 'CD2 - 01 (3).flac']);
    });

    test('zonder submap wordt er meteen geteld', () {
      expect(eerste(3, '01.flac'), ['01.flac', '01 (2).flac', '01 (3).flac']);
    });

    test('het volgnummer komt vóór de punt, anders is het geen muziekbestand meer', () {
      // `01.flac (2)` zou door de bibliotheek niet als audio herkend worden en dus onzichtbaar zijn
      // — precies de fout die deze functie moet oplossen, in een nieuwe vorm.
      for (final n in eerste(6, '01 - Titel.flac', submap: 'CD1')) {
        expect(n.endsWith('.flac'), isTrue, reason: n);
      }
    });

    test('een naam zonder punt raakt er geen', () {
      expect(eerste(3, 'stuk', submap: ''), ['stuk', 'stuk (2)', 'stuk (3)']);
    });

    test('een naam die met een punt begint telt niet als extensie', () {
      // ".cue" is de hele naam en geen lege stam met een extensie.
      expect(eerste(2, '.cue'), ['.cue', '.cue (2)']);
    });

    test('een lege submap gedraagt zich als geen submap', () {
      expect(eerste(2, 'a.flac', submap: '   '), ['a.flac', 'a (2).flac']);
    });

    test('er komen er genoeg om een discografie aan te kunnen', () {
      // Bij een verzamelbox botsen dezelfde titels tientallen keren; stopt de reeks te vroeg, dan is
      // het bestand alsnog kwijt.
      expect(vrijeNamen('01.flac', submap: 'CD1').take(200).toList(), hasLength(100));
    });

    test('elke aangeboden naam is anders dan alle vorige', () {
      final namen = eerste(50, '01.flac', submap: 'CD1');
      expect(namen.toSet(), hasLength(namen.length));
    });
  });
}
