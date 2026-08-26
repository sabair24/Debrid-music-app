/// Een tweede nummer van dezelfde plaat erbij kiezen, zonder het eerste weg te duwen.
///
/// **Waarom dit bestaat.** aria2 kent een torrent aan zijn infohash en weigert een tweede
/// aanmelding van dezelfde plaat. Binnen één opdracht was dat ondervangen, maar niet tussen twee
/// opdrachten door: nummer 5 van een album halen en daarna nummer 9 van hetzelfde album meldde
/// dezelfde torrent opnieuw aan, en dat werd geweigerd met de infohash in de melding. Gemeld op
/// 26-08-2026 als "ik kan niet echt verschillende liedjes downloaden via rutracker".
///
/// De oplossing is aanhaken op de taak die er al is en het gevraagde nummer aan zijn selectie
/// toevoegen. Daar zitten twee manieren in om het stil fout te doen, en allebei hebben ze geen
/// zichtbaar gevolg tot je merkt dat er een nummer ontbreekt:
///
/// * de nieuwe selectie SCHRIJVEN in plaats van de vereniging nemen — dan stopt het nummer dat al
///   aan het binnenkomen was halverwege, zonder één woord;
/// * een lege `select-file` behandelen als "niets gekozen" terwijl het bij aria2 "alles" betekent —
///   dan gooi je met een "toevoeging" juist alles behalve dat ene weg.
library;

import 'package:debridmusic/aria2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DE KERN: de vereniging, niet de vervanging', () {
    test('nummer 9 erbij terwijl 5 nog loopt houdt 5 in de selectie', () {
      expect(selectieErbij('5', [9]), '5,9');
    });

    test('meerdere nummers erbij', () {
      expect(selectieErbij('3,5', [9, 11]), '3,5,9,11');
    });

    test('de uitkomst staat op volgorde, niet op volgorde van vragen', () {
      // aria2 trekt zich er niets van aan, maar een logregel die te lezen is scheelt een avond.
      expect(selectieErbij('9', [3, 11, 5]), '3,5,9,11');
    });

    test('een nummer dat er al in staat verandert niets', () {
      // Null betekent "laat staan". Een overbodige changeOption naar aria2 sturen is niet fataal,
      // maar wel een verzoek dat een lopende download even laat haperen.
      expect(selectieErbij('3,5,9', [5]), isNull);
      expect(selectieErbij('5', [5]), isNull);
    });
  });

  group('DE KERN: leeg betekent alles', () {
    test('een lege selectie laten staan', () {
      // Dit is de gevaarlijkste van de twee. Zou hier '9' uitkomen, dan haalt aria2 vanaf dat moment
      // alléén nog nummer 9 — en alles wat er al binnenkwam wordt afgebroken.
      expect(selectieErbij('', [9]), isNull);
      expect(selectieErbij('   ', [9]), isNull);
    });

    test('rommel telt ook als leeg', () {
      expect(selectieErbij('geen,getallen', [9]), isNull);
    });
  });

  group('de randen', () {
    test('niets erbij vragen verandert niets', () {
      expect(selectieErbij('3,5', const []), isNull);
    });

    test('spaties in de opgave van aria2 storen niet', () {
      expect(selectieErbij(' 3 , 5 ', [9]), '3,5,9');
    });

    test('een index van nul of lager telt niet mee', () {
      // De nummering in een torrent begint bij één. Een nul erin zetten laat aria2 de hele optie
      // afkeuren, en dan verandert er niets terwijl de app denkt van wel.
      expect(selectieErbij('3', [0]), isNull);
      expect(selectieErbij('3', [-1, 9]), '3,9');
    });
  });
}
