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
      pad.toLowerCase(): {
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
      pad.toLowerCase(): {'bits': 'onbekend', 'boven': 'leeg', 'band': 'onbekend'}
    });
    await laadEchtheid();
    expect(gemeten(r'D:\MUZIEK\A\B.flac'), isNotNull);
    expect(gemeten('D:/Muziek/A/B.flac'), isNotNull);
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
