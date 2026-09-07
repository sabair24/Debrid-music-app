/// Wie er wint als de vervanger van de verlanglijst landt.
///
/// **Dit is de storing die Saber meldde.** Zijn "La Isla Bonita" zegt `FLAC · 24/96` terwijl de app
/// er zelf `24/44.1` naast zet: opgeschaald, en dus bewezen nep. Drukte je dan op "Laat de app
/// zoeken", dan ging het mis in `firstIsBetter` (organize.dart): de regel *wat bewezen nep is
/// verliest* staat bóven de grootte, maar een ONGEMETEN binnenkomer geldt niet als nep. Elke verse
/// kopie won dus van het bestand in de bibliotheek, wat het ook was.
///
/// Deze toets legt de twee uitkomsten vast die daarna moeten gelden.
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

  test('DE KERN: de gemeten cd wint van de opgeschaalde 24/96, ook al is die vier keer groter', () async {
    // 27 MB tegen 108 MB is geen uitzondering maar de regel: een opgeschaald bestand draagt
    // dezelfde muziek in vier keer zoveel bytes. GEMETEN over Sabers 158 opgeschaalde nummers:
    // 20,6 GB waar 4,1 GB volstaat.
    final opgeschaald = schrijf('opgeschaald.flac', 108);
    final echt = schrijf('echt.flac', 27);
    await onthoudOordeel(opgeschaald.path, _opgeschaald);
    await onthoudOordeel(echt.path, _echteCd);

    expect(firstIsBetter(echt, opgeschaald), isTrue, reason: 'de gemeten cd hoort te winnen');
    expect(firstIsBetter(opgeschaald, echt), isFalse);
  });

  test('EN DE STORING: een ONGEMETEN binnenkomer won hiervoor gewoon', () async {
    // Dit is geen wens maar een vaststelling: zó gedraagt `firstIsBetter` zich, en dat is juist
    // waarom er vóór het opbergen gemeten MOET worden. Zonder oordeel op de binnenkomer verliest
    // het bewezen neppe bestand — ook als de binnenkomer zelf een vervalsing is.
    final opgeschaald = schrijf('oud.flac', 108);
    final ongemeten = schrijf('nieuw.flac', 120);
    await onthoudOordeel(opgeschaald.path, _opgeschaald);

    expect(firstIsBetter(ongemeten, opgeschaald), isTrue,
        reason: 'zonder meting telt hij niet als nep — dit is precies het gat');
  });

  test('twee vervalsingen: de tweede verdringt de eerste niet op grootte alleen', () async {
    // Zijn ze allebei betrapt, dan vervalt de nep-regel en beslist de grootte — en de grootste is
    // hier juist de slechtste. Zolang de wensweg geen nep meer binnenlaat ontstaan zulke paren
    // niet meer; dit legt vast wat de huidige regel doet, zodat een latere capaciteitstrap zichtbaar
    // iets verandert.
    final eerste = schrijf('nep1.flac', 108);
    final tweede = schrijf('nep2.flac', 120);
    await onthoudOordeel(eerste.path, _opgeschaald);
    await onthoudOordeel(tweede.path, _opgeschaald);

    expect(firstIsBetter(tweede, eerste), isTrue, reason: 'nu nog op grootte — bekende grens');
  });
}
