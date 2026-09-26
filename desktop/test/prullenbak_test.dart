/// Opruimen naar de prullenbak, niet definitief.
///
/// Op 26-09-2026 verdwenen dertien radionummers met één klik die voor "Later beslissen" bedoeld was
/// en op "Afsluiten en 19 opruimen" landde, de knop er vlak boven. Dat was `File.delete()`, zonder
/// weg terug. Deze toetsen houden vast dat het opruimen van een radio nu naar de prullenbak gaat, en
/// dat wat daar niet heen kon gewoon blijft staan — nooit alsnog definitief weg.
///
/// Geen enkele toets hier gooit iets in een ECHTE prullenbak: de aanroep van PowerShell wordt
/// nagebootst. Dat het echte werkt is op 26-09-2026 op Sabers pc nagekeken — een proefbestand met
/// een apostrof, een dollarteken en een ampersand in de naam, in 590 ms in de Prullenbak.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/prullenbak.dart';
import 'package:debridmusic/radiosessie.dart';
import 'package:debridmusic/vaste_keuze.dart';
import 'package:flutter_test/flutter_test.dart';

String decodeer(String b64) {
  final bytes = base64.decode(b64);
  return String.fromCharCodes([
    for (var i = 0; i + 1 < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ]);
}

void main() {
  late Directory wortel;
  String pad(String naam) => '${wortel.path}${Platform.pathSeparator}$naam';

  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_pb_toets_');
    setAppDirForTest(wortel.path);
  });
  tearDown(() {
    resetVasteKeuzesForTest();
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('het script', () {
    test('DE KERN: het vraagt om de prullenbak — FOF_ALLOWUNDO — en zonder vensters', () {
      final s = prullenbakScript(r'C:\tmp\lijst.txt');
      expect(s, contains('SHFileOperation'));
      expect(s, contains('0x0040'), reason: 'FOF_ALLOWUNDO: zonder die vlag is het gewoon wissen');
      expect(s, contains('0x0400'),
          reason: 'FOF_NOERRORUI: een verborgen proces met een foutvenster wacht voor altijd');
    });

    test('DE VAL: een apostrof in het pad van de lijst breekt het script niet', () {
      final s = prullenbakScript(r"C:\Users\O'Brien\lijst.txt");
      expect(s, contains(r"'C:\Users\O''Brien\lijst.txt'"));
    });

    test('DE GRENS: gecodeerd en terug is hetzelfde script, ook met é en ’', () {
      const script = "Write-Output 'Céline — ’t is goed'";
      expect(decodeer(psGecodeerd(script)), script);
    });
  });

  group('naar de prullenbak', () {
    test('DE KERN: alleen wat er daarna echt niet meer staat, telt als weg', () async {
      final a = File(pad("I'm on Fire.flac"))..writeAsStringSync('a');
      final b = File(pad('Blijft.flac'))..writeAsStringSync('b');
      late List<String> args;
      final weg = await naarPrullenbak([a.path, b.path, pad('bestaat-niet.flac')],
          windows: true, werkmap: wortel.path, draai: (prog, argumenten) async {
        args = argumenten;
        expect(prog, 'powershell.exe');
        a.deleteSync(); // de prullenbak nam er één; de andere zat vast
        return ProcessResult(0, 0, '', '');
      });

      expect(weg, {a.path});
      expect(b.existsSync(), isTrue);
      expect(args, contains('-EncodedCommand'));
      expect(args.join(' '), isNot(contains("I'm on Fire")),
          reason: 'de paden gaan via een bestand, nooit via de opdrachtregel');
      expect(wortel.listSync().whereType<File>().where((f) => f.path.contains('dm_prullenbak_')),
          isEmpty,
          reason: 'de lijst met paden wordt na afloop opgeruimd');
    });

    test('DE VAL: faalt PowerShell, dan blijft alles staan — nooit alsnog gewist', () async {
      final a = File(pad('a.flac'))..writeAsStringSync('a');
      final weg = await naarPrullenbak([a.path],
          windows: true,
          werkmap: wortel.path,
          draai: (p, a) async => throw const ProcessException('powershell.exe', []));
      expect(weg, isEmpty);
      expect(a.existsSync(), isTrue);
    });

    test('DE GRENS: niets dat bestaat, dan wordt er ook niets gestart', () async {
      var gestart = false;
      final weg = await naarPrullenbak([pad('weg.flac')], windows: true, draai: (p, a) async {
        gestart = true;
        return ProcessResult(0, 0, '', '');
      });
      expect(weg, isEmpty);
      expect(gestart, isFalse);
    });
  });

  group('de bibliotheek', () {
    LibraryStore bibliotheek(List<File> bestanden) => LibraryStore()
      ..configDirOverride = wortel.path
      ..tracks.addAll([
        for (final f in bestanden)
          Track(path: f.path, title: f.uri.pathSegments.last, artist: 'Radio', album: 'Singles'),
      ]);

    test('DE KERN: met naarPrullenbak wordt er NIETS zelf gewist', () async {
      final a = File(pad('a.flac'))..writeAsStringSync('a');
      final lib = bibliotheek([a])..heeftPrullenbak = true;
      final gevraagd = <String>[];
      lib.prullenbak = (paden) async {
        gevraagd.addAll(paden);
        return <String>{}; // de prullenbak weigert
      };

      final weg = await lib.removeTracks([a.path], fromDisk: true, naarPrullenbak: true);

      expect(gevraagd, [a.path]);
      expect(weg, 0);
      expect(a.existsSync(), isTrue, reason: 'wie om een weg terug vraagt, krijgt geen definitieve');
      expect(lib.tracks.map((t) => t.path), [a.path],
          reason: 'wat er nog staat hoort ook in de bibliotheek te blijven');
    });

    test('DE KERN: wat in de prullenbak kwam gaat uit de bibliotheek en telt mee', () async {
      final a = File(pad('a.flac'))..writeAsStringSync('a');
      final b = File(pad('b.flac'))..writeAsStringSync('b');
      final lib = bibliotheek([a, b])..heeftPrullenbak = true;
      lib.prullenbak = (paden) async {
        a.deleteSync();
        return {a.path};
      };

      expect(await lib.removeTracks([a.path, b.path], fromDisk: true, naarPrullenbak: true), 1);
      expect(lib.tracks.map((t) => t.path), [b.path]);
    });

    test('DE VAL: zonder naarPrullenbak blijft het gewoon wissen, zoals elke andere aanroeper wil',
        () async {
      final a = File(pad('a.flac'))..writeAsStringSync('a');
      final lib = bibliotheek([a])..heeftPrullenbak = true;
      lib.prullenbak = (_) async => fail('de prullenbak had niet gevraagd mogen worden');
      expect(await lib.removeTracks([a.path], fromDisk: true), 1);
      expect(a.existsSync(), isFalse);
    });

    test('DE GRENS: op een systeem zonder prullenbak wordt het gewist, anders ruimt er nooit iets op',
        () async {
      final a = File(pad('a.flac'))..writeAsStringSync('a');
      final lib = bibliotheek([a])..heeftPrullenbak = false;
      lib.prullenbak = (_) async => fail('er is hier geen prullenbak');
      expect(await lib.removeTracks([a.path], fromDisk: true, naarPrullenbak: true), 1);
      expect(a.existsSync(), isFalse);
    });
  });

  group('welk bestand een radioregel is', () {
    const g = Gehaald(pad: 'D:/Singles/2 Fabiola/I\x27m on Fire.flac', artiest: '2 Fabiola',
        titel: "I'm on Fire", id: 'rad1');

    test('DE KERN: je eigen exemplaar met dezelfde titel wordt het NOOIT', () {
      // Het radiobestand is al weg; de bibliotheek vindt op artiest + titel een ander bestand.
      expect(
          bestandVanGehaald(g,
              eigenPad: 'D:/Albums/2 Fabiola/Best Of/03 - I\x27m on Fire.flac',
              eigenId: 'eigen9',
              opAfstand: false,
              bestaat: (_) => false),
          isNull,
          reason: 'dat is jouw exemplaar, niet wat de radio haalde');
    });

    test('DE KERN: staat het radiobestand er nog, dan is het dat — ook naast je eigen exemplaar', () {
      expect(
          bestandVanGehaald(g,
              eigenPad: 'D:/Albums/x.flac', eigenId: 'eigen9', opAfstand: false, bestaat: (p) => p == g.pad),
          g.pad);
    });

    test('DE VAL: verhuisd met hetzelfde id is nog steeds het radiobestand', () {
      expect(
          bestandVanGehaald(g,
              eigenPad: 'D:/Singles/2 Fabiola/elders.flac', eigenId: 'rad1', opAfstand: false, bestaat: (_) => false),
          'D:/Singles/2 Fabiola/elders.flac');
    });

    test('DE GRENS: op afstand beslist de pc, en zonder treffer blijft het het radiopad', () {
      expect(bestandVanGehaald(g, opAfstand: true, bestaat: (_) => false), g.pad);
      expect(bestandVanGehaald(g, opAfstand: false, bestaat: (_) => false), isNull);
    });
  });
}
