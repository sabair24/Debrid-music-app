/// Wie er wint als de vervanger van de verlanglijst landt.
///
/// **Dit is de storing die Saber meldde.** Zijn "La Isla Bonita" zegt `FLAC · 24/96` terwijl de app
/// er zelf `24/44.1` naast zet: opgeschaald, en dus bewezen nep. Drukte je dan op "Laat de app
/// zoeken", dan ging het mis in `firstIsBetter` (organize.dart): de regel *wat bewezen nep is
/// verliest* staat bóven de grootte, maar een ONGEMETEN binnenkomer geldt niet als nep. Elke verse
/// kopie won dus van het bestand in de bibliotheek, wat het ook was.
///
/// Deze toets legt de uitkomsten vast die daarna moeten gelden.
///
/// **Bijgewerkt op 29-09-2026.** Toen bleek de wens het omgekeerde te doen van wat Saber wilde: zijn
/// opgeschaalde 24/96-bestanden werden ingeruild voor eerlijke 24/48 en 24/44,1 die niets beter waren,
/// en dat las hij als "in mindere kwaliteit". Sindsdien telt alleen wat BEWEZEN beter is (keuring.dart):
/// een opgeschaalde 24/96 draagt een cd, een eerlijke cd ook — gelijk, en dan blijft wat er stond.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';

const _opgeschaald = Echtheidsoordeel(
  bits: Bitdiepte.spreektNietTegen,
  boven: Bovenband.leeg,
  band: Bandbreedte.doorlopend,
  vensters: 32,
);

/// Een cd-rip: proef A en B kunnen hier niets zeggen, de muurproef zag geen muur.
const _echteCd = Echtheidsoordeel(
  bits: Bitdiepte.onbekend,
  boven: Bovenband.onbekend,
  band: Bandbreedte.doorlopend,
  vensters: 32,
);

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dm_wens_');
    setAppDirForTest(root.path);
    resetEchtheidVoorTest();
    await laadEchtheid();
  });

  tearDown(() {
    resetEchtheidVoorTest();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  File schrijf(String naam, int mb) {
    final f = File('${root.path}${Platform.pathSeparator}$naam');
    f.writeAsBytesSync(List.filled(mb * 1024 * 1024, 7));
    return f;
  }

  test('DE KERN: een gemeten cd en een opgeschaalde 24/96 zijn gelijk — wat er stond blijft', () async {
    // Tot 29-09-2026 won de cd hier. Maar een opgeschaald bestand draagt dezelfde muziek als de cd, in
    // vier keer zoveel bytes — geen winst om een bestand van Saber voor weg te duwen.
    final opgeschaald = schrijf('opgeschaald.flac', 108);
    final echt = schrijf('echt.flac', 27);
    await onthoudOordeel(opgeschaald.path, _opgeschaald);
    await onthoudOordeel(echt.path, _echteCd);

    expect(firstIsBetter(echt, opgeschaald), isFalse, reason: 'gelijk: de opgeschaalde blijft staan');
    expect(firstIsBetter(opgeschaald, echt), isFalse, reason: 'en andersom evenmin');
  });

  test('DE STORING IS DICHT: een ONGEMETEN binnenkomer wint niet meer', () async {
    // Hier won hij: zonder meting telde hij niet als nep, en op grootte was hij groter. Nu bewijst een
    // ongemeten bestand niets, en een bestand dat niets bewijst duwt niets weg.
    final opgeschaald = schrijf('oud.flac', 108);
    final ongemeten = schrijf('nieuw.flac', 120);
    await onthoudOordeel(opgeschaald.path, _opgeschaald);

    expect(firstIsBetter(ongemeten, opgeschaald), isFalse,
        reason: '29-09-2026: precies zo verdrong een ongemeten WavPack een FLAC');
  });

  test('twee vervalsingen: de tweede verdringt de eerste niet', () async {
    // De "bekende grens" van hiervoor — de grootte besliste, en de grootste was de slechtste — is weg.
    final eerste = schrijf('nep1.flac', 108);
    final tweede = schrijf('nep2.flac', 120);
    await onthoudOordeel(eerste.path, _opgeschaald);
    await onthoudOordeel(tweede.path, _opgeschaald);

    expect(firstIsBetter(tweede, eerste), isFalse);
  });
}
