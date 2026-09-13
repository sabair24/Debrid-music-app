/// Kan de app het oordeel dat op schijf staat werkelijk terugvinden?
///
/// Deze test bestaat omdat het in de draaiende app NIET lukte: echtheid_oordelen.json bevatte het
/// juiste oordeel onder de juiste sleutel, en het scherm toonde niets. Tussen "het staat erin" en "de
/// app vindt het" zit blijkbaar iets, en dat hoort een test te zijn en geen redenering.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/paths.dart';

/// Hoe de sleutel op schijf eruitziet, precies zoals `_sleutel` in `echtheid_oordelen.dart` hem maakt.
///
/// **Waarom dit niet gewoon `toLowerCase()` mag zijn.** Op Windows en macOS is `Foo.flac` hetzelfde
/// bestand als `foo.flac`, dus worden sleutels daar naar kleine letters gehaald en de scheidingstekens
/// gelijkgetrokken. Op Linux is dat een ANDER bestand en gebeurt dat bewust niet. Deze toets nam het
/// Windows-gedrag onvoorwaardelijk aan en stond daardoor rood in de bouwstraat - een van de zes die
/// daar vielen terwijl ze hier groen waren, en waardoor er tien uitleveringen lang geen APK kwam.
String _opSchijf(String pad) => (Platform.isWindows || Platform.isMacOS)
    ? pad.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator).toLowerCase()
    : pad;

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_echtl_');
    setAppDirForTest(scratch.path);
    resetEchtheidVoorTest();
  });

  tearDown(() {
    resetEchtheidVoorTest();
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  void schrijf(Map<String, dynamic> inhoud) {
    File('${scratch.path}${Platform.pathSeparator}echtheid_oordelen.json')
        .writeAsStringSync(jsonEncode(inhoud));
  }

  test('precies de vorm die het kalibratiescript wegschrijft, wordt teruggevonden', () async {
    const pad = r"D:\Flac music 2024\DebridMusic Downloads\Albums\Céline Dion\D'Eux\01 - Pour.flac";
    schrijf({
      _opSchijf(pad): {
        'bits': 'spreektNietTegen',
        'boven': 'leeg',
        'band': 'afgekapt',
        'gebruikteBits': 24,
        'afkapHz': 20998.291015625,
        'wandDb': 41.10827136542216,
        'vensters': 32,
      }
    });

    await laadEchtheid();
    expect(laatsteFout, isNull, reason: 'het inlezen mag niet stilletjes mislukken');
    expect(aantalGemeten, 1);

    // Met de ORIGINELE schrijfwijze opvragen, zoals de app doet — de sleutel op schijf is kleine letters.
    final o = gemeten(pad);
    expect(o, isNotNull, reason: 'hier ging het in de app mis');
    expect(o!.isNep, isTrue);
    expect(bewezenNep(pad), isTrue);
    expect(waarom(o), contains('22 kHz'));
  });

  test('een pad met andere hoofdletters of scheidingstekens vindt hetzelfde oordeel', () async {
    const pad = r'D:\Muziek\A\B.flac';
    schrijf({
      _opSchijf(pad): {'bits': 'onbekend', 'boven': 'leeg', 'band': 'onbekend'}
    });
    await laadEchtheid();

    expect(gemeten(pad), isNotNull, reason: 'dezelfde schrijfwijze hoort altijd terug te vinden');

    if (Platform.isWindows || Platform.isMacOS) {
      expect(gemeten(r'D:\MUZIEK\A\B.flac'), isNotNull);
      expect(gemeten('D:/Muziek/A/B.flac'), isNotNull);
    } else {
      // DE GRENS: op een hoofdlettergevoelig bestandssysteem is dit een ANDER bestand. Daar
      // hetzelfde oordeel teruggeven zou juist fout zijn - en precies die aanname maakte deze
      // toets rood in de bouwstraat.
      expect(gemeten(r'D:\MUZIEK\A\B.flac'), isNull);
    }
  });

  test('een ongemeten bestand is nadrukkelijk niet nep', () async {
    schrijf({});
    await laadEchtheid();
    expect(gemeten(r'D:\iets.flac'), isNull);
    expect(bewezenNep(r'D:\iets.flac'), isFalse);
  });

  test('onleesbare inhoud meldt zich in plaats van stil te blijven', () async {
    File('${scratch.path}${Platform.pathSeparator}echtheid_oordelen.json').writeAsStringSync('{kapot');
    await laadEchtheid();
    expect(laatsteFout, isNotNull);
    expect(aantalGemeten, 0);
  });
}
