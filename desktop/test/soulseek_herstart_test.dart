/// Waarom de app na elke pc-herstart zei dat het wachtwoord niet klopte.
///
/// De keten was: bij het afsluiten meldde de app zich nooit af, dus hield Soulseek de vorige sessie
/// nog even vast. Bij het starten logde de app uit zichzelf in — nog vóór de gebruiker iets deed — en
/// botste met dat spook. De server antwoordt dan INVALIDPASS, dezelfde tekst als bij een echt fout
/// wachtwoord, en de app koos de verkeerde verklaring: tien minuten wachten plus het advies om een
/// login te wijzigen die nergens fout was.
///
/// Het wrange is dat de code die botsing al kende — de opmerking bij de zachte back-off beschrijft
/// hem woordelijk — maar dat de INVALIDPASS-tak daar overheen sprong.
///
/// Deze tests bewaken de twee kanten die tegen elkaar in werken: een botsing mag NIET als
/// wachtwoordfout gelezen worden, en een echte wachtwoordfout mag NIET onder de botsing verdwijnen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_slskherstart_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> readGuard() => jsonDecode(
      File('${scratch.path}${Platform.pathSeparator}soulseek_guard.json').readAsStringSync());

  group('een botsing met de eigen vorige sessie', () {
    test('is geen wachtwoordfout, en zegt dat ook', () {
      final c = SoulseekClient()
        ..markStart()
        ..noteLoginRefused('INVALIDPASS');
      expect(c.pause, SlskPause.herstart);
      expect(c.blockedFor!.inMinutes, lessThan(2), reason: 'kort, want het lost zichzelf op');
      expect(c.whyNotLogin, isNot(contains('Instellingen')),
          reason: 'iemand naar zijn wachtwoord sturen is hier het slechtste antwoord');
      expect(c.pauseLabel, isNotEmpty);
    });

    test('geldt alleen voor de EERSTE poging na het starten', () {
      // Anders zou een echte typefout eindeloos als botsing worden weggewuifd.
      final c = SoulseekClient()..markStart();
      c.noteLoginRefused('INVALIDPASS');
      expect(c.pause, SlskPause.herstart);
      c.noteLoginRefused('INVALIDPASS');
      expect(c.pause, SlskPause.badLogin,
          reason: 'de tweede weigering in dezelfde start is geen spook meer');
      expect(c.whyNotLogin, contains('Instellingen'));
    });

    test('geldt niet meer zodra er één keer is ingelogd', () {
      final c = SoulseekClient()
        ..markStart()
        ..noteLoggedIn();
      c.noteLoginRefused('INVALIDPASS');
      expect(c.pause, SlskPause.inUse,
          reason: 'wie binnen was botst niet met zichzelf; dan is het een ander apparaat');
    });

    test('geldt niet zonder markStart — dus niet zomaar overal', () {
      final c = SoulseekClient()..noteLoginRefused('INVALIDPASS');
      expect(c.pause, SlskPause.badLogin);
    });
  });

  group('een echt fout wachtwoord blijft zichtbaar', () {
    test('andere inloggegevens dan wat werkte: meteen badLogin, ook net na het starten', () {
      // Het gat in "werkte eerder": dat vroeg of er ooit iets werkte, niet of DIT werkte. Wie zijn
      // wachtwoord wijzigt en het verkeerd overtikt hoort dat te horen, niet anderhalve minuut
      // "de vorige sessie staat nog open".
      final oud = SoulseekClient.credId('leedagair', 'goed');
      final nieuw = SoulseekClient.credId('leedagair', 'fout');
      expect(oud, isNot(nieuw));

      final c = SoulseekClient()
        ..markStart()
        ..noteLoggedIn(credId: oud);
      // Nieuwe start, zelfde app: het bewijs van "dit werkte" staat er nog.
      c.markStart();
      c.noteLoginRefused('INVALIDPASS', credId: nieuw);
      expect(c.pause, SlskPause.badLogin);
      expect(c.whyNotLogin, contains('Instellingen'));
    });

    test('dezelfde gegevens die eerder werkten: wél de zachte verklaring', () {
      final zelfde = SoulseekClient.credId('leedagair', 'goed');
      final c = SoulseekClient()
        ..markStart()
        ..noteLoggedIn(credId: zelfde);
      c.markStart();
      c.noteLoginRefused('INVALIDPASS', credId: zelfde);
      expect(c.pause, SlskPause.herstart);
    });

    test('de vingerafdruk is stabiel en verraadt het wachtwoord niet', () async {
      const gebruiker = 'leedagair';
      const geheim = 'een-of-ander-wachtwoord-25.';
      expect(SoulseekClient.credId(gebruiker, geheim), SoulseekClient.credId(gebruiker, geheim));
      expect(SoulseekClient.credId(gebruiker, geheim),
          isNot(SoulseekClient.credId(gebruiker, '$geheim!')));

      final c = SoulseekClient()..noteLoggedIn(credId: SoulseekClient.credId(gebruiker, geheim));
      await c.guardSaved();
      final rauw =
          File('${scratch.path}${Platform.pathSeparator}soulseek_guard.json').readAsStringSync();
      expect(rauw, isNot(contains(geheim)), reason: 'er hoort geen wachtwoord in dit bestand');
      expect(rauw, contains('laatstGoedId'));
    });
  });

  group('een netwerk dat van route wisselt is geen kick', () {
    // Op Sabers pc komt NordVPN vijftien seconden na het opstarten op en verlegt de route van de
    // netwerkkaart (192.168.0.117) naar de tunnel (10.5.0.2). Wie de app in die eerste minuut opent
    // — en dat doet hij — verliest de verbinding zodra de tunnel het overneemt. De app noemde dat
    // "een andere Soulseek-app heeft je account overgenomen", vijf minuten wachten, en het advies om
    // een app te sluiten die niet eens draait.

    test('veranderde adressen leveren de juiste verklaring en een korte wachttijd', () async {
      final c = SoulseekClient()
        // Een verzameling die op geen enkele machine zo bestaat: precies wat een verlegde route
        // achterlaat. Bewust een SET en niet het adres van de socket — `Socket.address` geeft de kant
        // waarnáár je verbindt, en die vergissing stond één versie lang in de code: het logboek meldde
        // `via 208.76.170.59`, en dat is de Soulseek-server. Met dat adres als maatstaf zou élke
        // wegvallende verbinding hier terechtkomen, ook een echte kick.
        ..noteLoggedIn(adressen: const {'203.0.113.99'})
        ..noteConnectionLost();
      expect(c.pause, SlskPause.kicked, reason: 'de kick wordt meteen gezet, dat is de veilige kant');

      // De controle op de netwerkkaarten is async.
      for (var i = 0; i < 40 && c.pause == SlskPause.kicked; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(c.pause, SlskPause.netwerkGewisseld);
      expect(c.blockedFor!.inMinutes, lessThan(1), reason: 'tien seconden, geen vijf minuten');
      expect(c.pauseLabel, isNotEmpty);
      expect(c.whyNotLogin, isNotNull);
      // De kern: hem niet naar een andere Soulseek-app sturen die helemaal niet draait.
      expect(c.whyNotLogin, isNot(contains('Sluit de officiële app')));
      expect(c.whyNotLogin, contains('route'),
          reason: 'de uitleg hoort te benoemen wat er wél aan de hand is');
    });

    test('een netwerk dat gelijk gebleven is blijft gewoon een kick', () async {
      // De tegenhanger, en de belangrijkste van de drie: gaat de verbinding stuk terwijl onze kant
      // ongewijzigd is, dan is de oude verklaring de juiste en moet die blijven staan. Deze test zou
      // de socket-vergissing hierboven gevangen hebben — met het serveradres als maatstaf komt hier
      // altijd "netwerk gewisseld" uit.
      final nu = await SoulseekClient.eigenAdressen();
      if (nu == null || nu.isEmpty) return; // geen netwerk op deze machine, niets te toetsen

      final c = SoulseekClient()
        ..noteLoggedIn(adressen: nu)
        ..noteConnectionLost();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.pause, SlskPause.kicked);
      expect(c.whyNotLogin, contains('andere Soulseek-app'));
    });

    test('eigenAdressen levert onze kant, niet die van de tegenpartij', () async {
      final nu = await SoulseekClient.eigenAdressen();
      if (nu == null || nu.isEmpty) return;
      for (final a in nu) {
        expect(a, isNot('208.76.170.59'), reason: 'dat is de Soulseek-server');
        expect(a, isNot(startsWith('169.254.')), reason: 'link-local zegt niets over de route');
      }
    });

    test('zonder bekende adressen verandert er niets aan het oude gedrag', () async {
      final c = SoulseekClient()
        ..noteLoggedIn()
        ..noteConnectionLost();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.pause, SlskPause.kicked, reason: 'niets om aan af te meten, dus niets beweren');
    });
  });

  group('wat een herstart wel en niet meeneemt', () {
    test('een botsingspauze komt niet terug', () async {
      final a = SoulseekClient()
        ..markStart()
        ..noteLoginRefused('INVALIDPASS');
      expect(a.pause, SlskPause.herstart);
      await a.guardSaved();

      final b = SoulseekClient();
      await b.loadGuard();
      expect(b.blocked, isFalse,
          reason: 'anders begint elke start op een wachttijd die over de vorige ging');
      expect(b.pause, SlskPause.none);
    });

    test('een botsing telt niet mee in de escalatietrap', () async {
      final a = SoulseekClient()
        ..markStart()
        ..noteLoginRefused('INVALIDPASS');
      await a.guardSaved();
      expect(readGuard()['refusals'], 0,
          reason: 'de trap 2/6/15/30 is voor echte weigeringen, niet voor ons eigen spook');
    });

    test('loadGuard zet de klok, ook als het bestand ontbreekt', () async {
      // Juist dan telt het: zonder guard-bestand is er geen `laatstGoed`, en dan zou een botsing
      // langs de oude weg als fout wachtwoord gelezen worden.
      final c = SoulseekClient();
      await c.loadGuard();
      c.noteLoginRefused('INVALIDPASS');
      expect(c.pause, SlskPause.herstart);
    });

    test('afmelden wordt genoteerd, zodat je het achteraf kunt nazien', () async {
      final c = SoulseekClient()..markClosed();
      await c.guardSaved();
      expect(readGuard()['afgemeldOp'], isNotNull);

      final b = SoulseekClient();
      await b.loadGuard();
      // Verandert bewust niets aan de beslissing — ook na een nette afmelding kan de server de
      // sessie nog even vasthouden, en dan is de botsing nog steeds de ware verklaring.
      b.noteLoginRefused('INVALIDPASS');
      expect(b.pause, SlskPause.herstart);
    });
  });
}
