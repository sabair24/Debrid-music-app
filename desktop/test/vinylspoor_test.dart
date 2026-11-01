// Het vinylspoor (Saber, 27-10-2026: "Kan je onderscheid maken tussen vinyl en studio opname door spectrum?"): een
// "studio" die groefruis houdt waar je cd digitaal stil wordt, is vinyl. De getallen zijn gemeten op Discovery.
import 'dart:io';

import 'package:debridmusic/vinylspoor.dart';
import 'package:flutter_test/flutter_test.dart';

Stilte s(double stilste, double seconden) => (stilste: stilste, seconden: seconden);

void main() {
  group('klinktAlsVinyl, met wat Discovery gaf', () {
    test('DE KERN: groefruis waar de cd stil is — High Life, Short Circuit, Too Long', () {
      expect(klinktAlsVinyl(s(-52.2, 201.37), s(-200, 201.80)), isTrue, reason: 'High Life, valentinchpx "24/96"');
      expect(klinktAlsVinyl(s(-51.5, 206.13), s(-200, 206.87)), isTrue, reason: 'Short Circuit');
      expect(klinktAlsVinyl(s(-60.7, 598.69), s(-200, 600.28)), isTrue, reason: 'Too Long: 1,6 s korter, nog binnen');
    });

    test('een echte digitale master wordt mee stil: geen vinyl', () {
      expect(klinktAlsVinyl(s(-144.5, 225.25), s(-200, 224.29)), isFalse, reason: 'Harder, Better (ElYoM)');
      expect(klinktAlsVinyl(s(-83.7, 200), s(-200, 200)), isFalse, reason: 'de luidste digitale stilte die we maten');
    });

    test('zonder stille cd geen oordeel: een nummer dat nergens stil wordt', () {
      expect(klinktAlsVinyl(s(-42.4, 320), s(-45.8, 320.8)), isFalse, reason: 'One More Time: ook de cd wordt niet stil');
      expect(klinktAlsVinyl(s(-50, 300), s(-84, 300)), isFalse, reason: 'net niet stil genoeg');
    });

    test('een afgeknipte staart is geen groefruis', () {
      expect(klinktAlsVinyl(s(-60, 590), s(-200, 600)), isFalse, reason: 'tien seconden korter');
      expect(klinktAlsVinyl(s(-60, 598.1), s(-200, 600)), isTrue);
    });

    test('de grens op −75 dB: vinyl gemeten tot −69,4, digitaal vanaf −83,7', () {
      expect(klinktAlsVinyl(s(-74, 200), s(-200, 200)), isTrue);
      expect(klinktAlsVinyl(s(-76, 200), s(-200, 200)), isFalse);
      expect(kGroefruis, lessThan(-69.4));
      expect(kGroefruis, greaterThan(-83.7));
    });
  });

  group('andersom: een "vinyl" die digitaal is (Trip on This, 01-11-2026)', () {
    const cd = (stilste: -200.0, seconden: 335.3);
    test('DE KERN: digitaal stil en precies even snel als je cd (twee metingen) — geen plaat', () {
      // Alle acht "vinyl"-nummers van de Soulseek-map "US 12'' Vinyl LP Compilation": 0 ppm en −200 dB.
      expect(isDigitaleVinyl((stilste: -200.0, seconden: 335.3), cd, (snelheid: 1.0, hoe: 'twee metingen')), isTrue);
      expect(isDigitaleVinyl((stilste: -200.0, seconden: 335.3), cd, (snelheid: 1.000006, hoe: 'twee metingen')), isTrue,
          reason: '6 ppm: binnen één milliseconde over drie minuten');
    });
    test('een echte plaat met gedempte stiltes draait niet precies even snel: blijft vinyl', () {
      expect(isDigitaleVinyl((stilste: -200.0, seconden: 335.3), cd, (snelheid: 1.000231, hoe: 'twee metingen')), isFalse,
          reason: 'Burning Heart: 231 ppm');
      expect(isDigitaleVinyl((stilste: -200.0, seconden: 335.3), cd, (snelheid: 0.99996, hoe: 'twee metingen')), isFalse);
    });
    test('groefruis, of maar één meting, of een cd die zelf niet stil wordt: geen oordeel', () {
      expect(isDigitaleVinyl((stilste: -58.0, seconden: 335.3), cd, (snelheid: 1.0, hoe: 'twee metingen')), isFalse);
      expect(isDigitaleVinyl((stilste: -200.0, seconden: 40.0), cd, (snelheid: 1.0, hoe: 'één meting')), isFalse);
      expect(isDigitaleVinyl((stilste: -200.0, seconden: 335.3), (stilste: -51.6, seconden: 335.3),
          (snelheid: 1.0, hoe: 'twee metingen')), isFalse);
    });
  });

  test('het logboek van ffmpeg lezen: het laagste niveau, digitale stilte als −200', () {
    const log = '[Parsed_ametadata_2 @ 0x1] lavfi.astats.Overall.RMS_level=-31.902505\n'
        '[Parsed_ametadata_2 @ 0x1] lavfi.astats.Overall.RMS_level=-62.5\n'
        '[Parsed_ametadata_2 @ 0x1] lavfi.astats.Overall.RMS_level=-inf\n'
        '[Parsed_ametadata_2 @ 0x1] lavfi.astats.Overall.RMS_level=-33.2\n';
    expect(stilsteUitLog(log), -200);
    expect(stilsteUitLog(log.split('\n').where((l) => !l.contains('-inf')).join('\n')), -62.5);
    expect(stilsteUitLog('geen meting'), isNull);
  });

  test('aangesloten: elke weg die een kopie een soort geeft, kijkt eerst het spoor na; de pc meet', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final online = bron('lib/online.dart');
    for (final regel in [
      '    await merkVinylspoor(f.path, pad, g.bronpad ?? g.bron, log: _log.line);\n'
          '    var plan = versieplanVoor(f, pad, g.bronpad ?? g.bron);',
      '      await merkVinylspoor(staged.path, bestaand, bronpad ?? bron, log: _log.line);',
      '    await merkVinylspoor(f.path, bestaand, f.path, log: _log.line);\n'
          '    var plan = versieplanVoor(f, bestaand, f.path);',
      '    await merkVinylspoor(staged.path, v.pad, bronpad, log: _log.line);\n'
          '    final soort = versieplanVoor(staged, v.pad, bronpad).soort;',
      '              await merkVinylspoor(staged.path, bestaand, f.filename, log: _log.line);',
    ]) {
      expect(online, contains(regel));
    }
    expect(bron('lib/versie_terugzetter.dart'), contains('      await merkVinylspoor(f.path, anker, f.uri.pathSegments.last);'));
    expect(bron('lib/main.dart'),
        contains(r"      stilteVan = Stiltemeter(bestand: '$appDir${Platform.pathSeparator}vinylspoor.json').meet;"));
    expect(bron('lib/main.dart'), contains('        final u = await meetUitlijning(digitaal, kandidaat);\n'));
  });
}
