/// Het volgende nummer alvast op de telefoon, en blijven proberen als de pc even weg is.
///
/// **Waarom dit een toets verdient.** Gemeten op 22-09-2026 in `speler.log` van de telefoon: 267
/// time-outs naar de pc, in blokken van anderhalf tot vijf minuten — op 21-09 in de sportschool
/// zeven keer tussen 16:15 en 17:26. Midden in een nummer vangt het vooruitlezen zo'n gat op; op de
/// wissel naar het volgende nummer niet, en daar bleef de app staan na één herkansing die bij een
/// time-out nul procent haalde. Zie `lib/vooruithalen.dart`.
///
/// De regels zijn puur en toetsen hier zonder netwerk; het ophalen zelf staat in `offline_test.dart`,
/// en de aansluiting in de speler en in main.dart wordt onderaan uit de bron gelezen — de speler
/// laadt libmpv, en dat kan in een toets niet.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/vooruithalen.dart';

void main() {
  group('wat er vooruit gehaald wordt', () {
    test('DE KERN: op mobiele data wordt het volgende nummer gehaald', () {
      final plan = vooruitPlan(huidig: 'A', volgende: 'B', opMobiel: true, stroomt: (_) => true);
      expect(plan.halen, 'B');
      expect(plan.houden, {'A', 'B'});
    });

    test('DE GRENS: op wifi wordt er niets gehaald, maar wel opgeruimd', () {
      // Thuis zijn de gaten er niet, en een telefoon die een avond lang elk nummer twee keer
      // wegschrijft slijt voor niets. Wat er van de sportschool nog ligt, moet wel weg.
      final plan = vooruitPlan(huidig: 'A', volgende: 'B', opMobiel: false, stroomt: (_) => true);
      expect(plan.halen, isNull);
      expect(plan.houden, {'A', 'B'});
    });

    test('DE VAL: wat al op de telefoon staat, wordt niet nog eens gehaald', () {
      final plan =
          vooruitPlan(huidig: 'A', volgende: 'B', opMobiel: true, stroomt: (p) => p != 'B');
      expect(plan.halen, isNull, reason: 'offline bewaard of al vooruitgehaald: dat is dubbel data');
    });

    test('DE GRENS: aan het eind van de rij valt er niets te halen', () {
      final plan = vooruitPlan(huidig: 'A', volgende: null, opMobiel: true, stroomt: (_) => true);
      expect(plan.halen, isNull);
      expect(plan.houden, {'A'});
    });

    test('DE GRENS: hetzelfde nummer twee keer achter elkaar wordt niet twee keer gehaald', () {
      final plan = vooruitPlan(huidig: 'A', volgende: 'A', opMobiel: true, stroomt: (_) => true);
      expect(plan.halen, isNull);
    });
  });

  group('als de pc niet antwoordt', () {
    test('DE KERN: een time-out is een netwerkfout, een kapot bestand niet', () {
      // Letterlijk zoals ze in speler.log van de telefoon staan.
      expect(isNetwerkfout('tcp: Connection to tcp://100.97.101.113:47820 failed: Connection timed out'),
          isTrue);
      expect(
          isNetwerkfout('tcp: Connection to tcp://100.97.101.113:47820 failed: Software caused '
              'connection abort'),
          isTrue);
      expect(isNetwerkfout('Failed to recognize file format.'), isFalse);
      expect(isNetwerkfout('Error decoding audio.'), isFalse,
          reason: 'een kapot bestand wordt van wachten niet beter');
      expect(isNetwerkfout('Failed to open http://100.97.101.113:47820/stream/x.flac'), isFalse,
          reason: 'dat staat er ook bij een geweigerde sleutel; de netwerkfout zelf komt als eigen regel');
    });

    test('DE KERN: staat het volgende nummer al op de telefoon, dan daarheen', () {
      expect(naOpenfout(sinds: const Duration(seconds: 3), volgendeStaatHier: true),
          NaOpenfout.naarVolgende);
    });

    test('DE VAL: anders blijven proberen — de gaten in de sportschool duurden tot vijf minuten', () {
      // Hiervoor was er één herkansing na vier tellen, en daarna bleef het nummer op 0:00 staan.
      for (final m in [0, 1, 3, 5, 9]) {
        expect(naOpenfout(sinds: Duration(minutes: m), volgendeStaatHier: false), NaOpenfout.opnieuw,
            reason: 'na $m min opgeven laat je in de sportschool zonder muziek staan');
      }
    });

    test('DE GRENS: na tien minuten is het geen gat meer, maar een pc die uit staat', () {
      expect(naOpenfout(sinds: kNetGeduld, volgendeStaatHier: false), NaOpenfout.opgeven);
    });
  });

  group('de aansluiting', () {
    String bron(String pad) => File(pad)
        .readAsLinesSync()
        .where((r) => !r.trimLeft().startsWith('//'))
        .join('\n');

    // Als boolean en niet met `contains()`: die matcher drukt bij een fout het hele bestand af, en
    // main.dart is vijfentwintigduizend regels — dan staat de reden onvindbaar onderaan een logboek
    // van een megabyte.
    void staatErin(String tekst, String stuk, String waarom) =>
        expect(tekst.contains(stuk), isTrue, reason: '$waarom\n  ontbreekt: $stuk');

    test('DE VAL: de speler gebruikt de regel, en de oude ene herkansing alleen voor de rest', () {
      final speler = bron('lib/player.dart');
      staatErin(speler, 'if (eigen == null) _naOpenfout(e);', 'een time-out hoort naar de nieuwe regel');
      staatErin(speler, 'if (!isNetwerkfout(fout)) {\n      _probeerNogEens();',
          'een bestand dat de pc niet kent, houdt zijn ene herkansing en geen tien minuten');
      staatErin(speler, 'onVooruithalen?.call(current,',
          'zonder deze haak wordt het volgende nummer nooit vooruitgehaald');
      staatErin(speler, 'if (p > kVooruitNa &&\n          (_vooruitLaatst == null ||',
          'pas als dit nummer echt loopt, en daarna nog eens: anders vecht het halen met je eigen '
          'buffer, en blijft een poging die halverwege afbrak liggen');
      staatErin(speler, 'void pauzeer() {\n    _stopPcWacht();',
          'wie zelf op pauze drukt, wil niet dat het nummer alsnog begint als de pc terug is');
      staatErin(speler, 'Track? uit(int i) => i >= 0 && i < _radio.length ? _radio[i].local : null;',
          'de radio staat onderweg net zo vaak aan als de wachtrij');
    });

    test('DE VAL: main.dart speelt een vooruitgehaald nummer van de telefoon', () {
      final main = bron('lib/main.dart');
      staatErin(main, 'offline.localFor(path) ?? vooruit.localFor(path)',
          'anders wordt het wel gehaald, maar nooit gespeeld');
      staatErin(main, "OfflineStore(map: 'vooruit', indexNaam: 'vooruit.json')",
          'in je eigen offline-lijst hoort het niet');
      staatErin(main, 'await vooruit.leegMap();', 'wat er van een vorige keer ligt, hoort weg');
      staatErin(main, 'opMobiel: netStore.net == Netsoort.mobiel,', 'alleen op mobiele data halen');
    });
  });
}
