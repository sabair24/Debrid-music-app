/// Snel sluiten en weer openen mag nooit "gebruikersnaam of wachtwoord klopt niet" opleveren.
///
/// GEMETEN OP 04-08-2026. Saber sloot de app met de X en opende hem elf seconden later opnieuw:
///
///     21:02:24  afgemeld en afgesloten
///     21:02:35  nieuw proces
///     scherm    "gepauzeerd — vorige sessie staat nog open — probeert zo opnieuw, nog 2 min"
///     scherm    "gepauzeerd — gebruikersnaam of wachtwoord klopt niet, nog 10 min"
///
/// Hij zei het vanaf het begin zelf: "als ik de app sluit, sluit hij niet echt, en blijft Soulseek open
/// in de andere sessie." Niet het proces — dat was aantoonbaar weg, netstat zag geen enkele socket —
/// maar de sessie aan de SERVERKANT. Soulseek houdt een verlaten login nog even vast en antwoordt
/// INVALIDPASS op de volgende, precies dezelfde tekst als bij een echt fout wachtwoord.
///
/// Het gat: `_ruiktNaarHerstart` geldt alleen voor de EERSTE poging na het starten. De tweede viel door
/// naar `badLogin` — tien minuten en het advies om een wachtwoord te wijzigen dat nergens fout was.
/// `afgemeldOp` stond al in het guard-bestand en overleefde de herstart; er was alleen nooit iets dat
/// het las.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_botsing_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Een app die zich netjes heeft afgemeld en meteen daarna opnieuw start.
  Future<SoulseekClient> netAfgemeldEnOpnieuwGestart() async {
    final a = SoulseekClient()
      ..markStart()
      ..noteLoggedIn(credId: SoulseekClient.credId('leedagair', 'goed'))
      ..markClosed();
    await a.guardSaved();

    final b = SoulseekClient();
    await b.loadGuard();
    return b;
  }

  test('de eerste botsing is geen wachtwoordfout', () async {
    final c = await netAfgemeldEnOpnieuwGestart();
    c.noteLoginRefused('INVALIDPASS', credId: SoulseekClient.credId('leedagair', 'goed'));
    expect(c.pause, SlskPause.herstart);
    expect(c.whyNotLogin, isNot(contains('Instellingen')));
  });

  test('en de TWEEDE ook niet — dit is precies wat er misging', () async {
    final c = await netAfgemeldEnOpnieuwGestart();
    const zelfde = 'leedagair';
    final id = SoulseekClient.credId(zelfde, 'goed');

    c.noteLoginRefused('INVALIDPASS', credId: id);
    expect(c.pause, SlskPause.herstart, reason: 'de eerste ging altijd al goed');
    final eerste = c.blockedFor!;

    c.noteLoginRefused('INVALIDPASS', credId: id);
    expect(c.pause, SlskPause.herstart,
        reason: 'hier stond "gebruikersnaam of wachtwoord klopt niet, nog 10 min" op het scherm');
    expect(c.whyNotLogin, isNot(contains('Instellingen')),
        reason: 'iemand naar zijn wachtwoord sturen terwijl WIJ ons net hebben afgemeld is onzin');
    expect(c.blockedFor!, greaterThan(eerste), reason: 'wel langer wachten, want 90s was niet genoeg');

    c.noteLoginRefused('INVALIDPASS', credId: id);
    expect(c.pause, SlskPause.herstart, reason: 'ook de derde blijft dezelfde botsing');
    expect(c.blockedFor!.inMinutes, lessThan(10), reason: 'maar het loopt niet eindeloos op');
  });

  test('een GEWIJZIGD wachtwoord blijft wél gewoon een wachtwoordfout', () async {
    // De rem. Wie zijn wachtwoord wijzigt en het verkeerd overtikt hoort dat meteen te horen, ook als
    // hij net heeft afgemeld — anders verdwijnt het enige signaal waar hij iets mee kan.
    final c = await netAfgemeldEnOpnieuwGestart();
    c.noteLoginRefused('INVALIDPASS', credId: SoulseekClient.credId('leedagair', 'fout'));
    expect(c.pause, SlskPause.badLogin);
    expect(c.whyNotLogin, contains('Instellingen'));
  });

  test('zonder recente afmelding verandert er niets aan het oude gedrag', () async {
    // Geen afmelding in het guard-bestand: dan is er geen reden om een tweede INVALIDPASS te
    // verzachten, en blijft de bestaande beoordeling staan.
    final c = SoulseekClient();
    await c.loadGuard();
    c.noteLoginRefused('INVALIDPASS');
    expect(c.pause, SlskPause.herstart, reason: 'de eerste poging na het starten, zoals altijd');
    c.noteLoginRefused('INVALIDPASS');
    expect(c.pause, SlskPause.badLogin, reason: 'en dan valt hij door, want er staat niets van ons open');
  });

  test('een geslaagde login zet de teller en de afmelding terug', () async {
    final c = await netAfgemeldEnOpnieuwGestart();
    final id = SoulseekClient.credId('leedagair', 'goed');
    c.noteLoginRefused('INVALIDPASS', credId: id);
    c.noteLoginRefused('INVALIDPASS', credId: id);
    expect(c.blockedFor!.inSeconds, greaterThan(90));

    c.noteLoggedIn(credId: id);
    expect(c.blocked, isFalse);
    expect(c.pause, SlskPause.none);

    // En een botsing dáárna begint weer onderaan, niet waar de vorige reeks ophield.
    c.markClosed();
    c.noteLoginRefused('INVALIDPASS', credId: id);
    expect(c.pause, SlskPause.herstart);
    expect(c.blockedFor!.inSeconds, lessThanOrEqualTo(90));
  });
}
