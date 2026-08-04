/// Acht fouten die een adversariële nalezing van soulseek.dart opleverde, en die geen van alle door
/// een bestaande test werden gedekt.
///
/// De aanleiding was er zelf ook één: `Socket.address` werd gelezen als "ons lokale IP", terwijl dat
/// in Dart het adres is waar je NAARTOE verbindt. Het logboek dat die fout betrapte — `via
/// 208.76.170.59`, de Soulseek-server — was ook de reden om de rest van dit bestand na te lopen op
/// dezelfde soort: een veld of API met de juiste vorm en de verkeerde inhoud, of een controle die in
/// de praktijk altijd (of nooit) aanslaat.
///
/// De zwaarste vondst staat hieronder als eerste groep. Die is niet beredeneerd maar nagespeeld met
/// de echte Dart-VM: twaalf van de twaalf keer een sessie die zichzelf voor altijd "ingelogd" waande
/// op een vernietigde socket.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_slskzombie_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('een adresopvraging mag niet tussen het loginantwoord en _conn = c passen', () {
    // DE FOUT. `await SoulseekClient.eigenAdressen()` stond ná `await login.future`. Dat is een echte
    // IO-reis, geen microtaak, dus er ging een volledige slag van de event-lus overheen. Sluit de
    // server ons in díé slag af — precies wat een kick doet — dan vuurt `onDone` terwijl `_conn` nog
    // null is: `_lost()` slaat `noteConnectionLost()` over en `_drop()` ruimt alles op. Daarna hervat
    // `_login()` en zet `_conn = c` op een dode socket.
    //
    // Deze test toetst de eigenschap waar de reparatie op steunt: dat een `done` van een socket pas
    // aan de beurt komt ná de microtaken, zodat er zonder await tussen antwoord en toewijzing niets
    // meer tussen kan komen. Slaat die eigenschap om, dan valt de reparatie en faalt deze test.

    test('een socketgebeurtenis komt NA de microtaken, maar WEL tijdens een IO-await', () async {
      final volgorde = <String>[];

      // Microtaak: hoort vóór elke gebeurtenis van de event-lus te lopen.
      scheduleMicrotask(() => volgorde.add('microtaak'));
      // Een gebeurtenis van de event-lus, zoals het `done` van een socket.
      Timer.run(() => volgorde.add('gebeurtenis'));

      // Dít is de await die in `_login()` het gat maakte.
      await NetworkInterface.list(type: InternetAddressType.IPv4);

      expect(volgorde, contains('microtaak'));
      expect(volgorde, contains('gebeurtenis'),
          reason: 'NetworkInterface.list geeft de event-lus af — daar paste de hele fout in');
      expect(volgorde.first, 'microtaak',
          reason: 'microtaken gaan voor; daarom is "geen await ertussen" een afdoende reparatie');
    });

    test('eigenAdressen scheidt "geen netwerk" van "niet kunnen opvragen"', () async {
      // Beide gaven eerst `{}` terug. Daardoor moest `_netwerkVeranderd()` kiezen tussen twee kwaden
      // en koos het de verkeerde: een kabel eruit — het hardste bewijs dát het netwerk weg is — werd
      // gelezen als "niet vast te stellen", en dan bleef er `kicked` staan met het advies om een app
      // te sluiten die niet draait.
      final nu = await SoulseekClient.eigenAdressen();
      expect(nu, isNotNull, reason: 'op deze machine is het opvraagbaar');
      expect(nu, isA<Set<String>>());
      for (final a in nu!) {
        expect(a, isNot('208.76.170.59'), reason: 'dat is de Soulseek-server, niet wij');
        expect(a, isNot(startsWith('169.254.')), reason: 'Dart laat link-local zelf al weg');
        expect(a, isNot('127.0.0.1'), reason: 'Dart laat loopback zelf al weg');
      }
    });
  });

  group('het loginbudget', () {
    test('"toch proberen" laat ÉÉN poging door, niet vier', () {
      // Hier stond `_loginTimes.clear()`. Dat gaf geen enkele poging door maar het hele venster vrij —
      // precies de burst waar dit budget tegen gebouwd is, en waar Soulseek zelf op blokkeert.
      final c = SoulseekClient();
      for (var i = 0; i < 4; i++) {
        c.noteLoginAttempt();
      }
      expect(c.mustNotLogin, isTrue);

      c.allowOneRetry();
      expect(c.mustNotLogin, isFalse, reason: 'de knop moet iets doen');

      c.noteLoginAttempt(); // dit is die ene poging
      expect(c.mustNotLogin, isTrue,
          reason: 'en daarna staat de rem er weer op — dit is de hele bedoeling van de knop');
    });

    test('ook als de teller boven het budget staat komt er precies één door', () {
      // De teller wordt nergens afgekapt, dus hij kan hoger staan dan de grens. Eén tijdstip weghalen
      // deed dan niets en de knop bleef dood — de reden dat het snoeien tot ONDER de grens loopt.
      final c = SoulseekClient();
      for (var i = 0; i < 6; i++) {
        c.noteLoginAttempt();
      }
      expect(c.mustNotLogin, isTrue);
      c.allowOneRetry();
      expect(c.mustNotLogin, isFalse);
      c.noteLoginAttempt();
      expect(c.mustNotLogin, isTrue);
    });

    test('de knop blijft werken als het budget nog niet vol is', () {
      final c = SoulseekClient()..noteLoginRefused('busy');
      expect(c.blocked, isTrue);
      c.allowOneRetry();
      expect(c.blocked, isFalse);
      expect(c.mustNotLogin, isFalse);
    });
  });

  group('de luisterpoort', () {
    test('een gewijzigde poort wordt echt opnieuw gebonden', () async {
      // `ensureListening()` keerde terug op de bestaande listener vóórdat het naar `listenPort` keek,
      // en `stopListening()` had in de hele app geen aanroeper. Wie de poort in Instellingen wijzigde
      // bleef dus de oude adverteren tot hij de app herstartte.
      final c = SoulseekClient();
      // Poort 0 laat het besturingssysteem kiezen; dat is hier onbruikbaar als "andere poort", dus
      // twee vrije poorten opzoeken en die gebruiken.
      final a = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final b = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final poortA = a.port, poortB = b.port;
      await a.close();
      await b.close();

      c.listenPort = poortA;
      expect(await c.ensureListening(), poortA);

      c.listenPort = poortB;
      expect(await c.ensureListening(), poortB,
          reason: 'anders adverteert de app een poort die de router niet meer doorstuurt');

      c.listenPort = 0; // "niet luisteren"
      expect(await c.ensureListening(), 0, reason: 'en dan hoort de socket ook echt dicht te gaan');

      // Bewijs dat hij losgelaten is: hij moet opnieuw te binden zijn.
      final her = await ServerSocket.bind(InternetAddress.anyIPv4, poortB);
      await her.close();

      c.stopListening();
    });
  });
}
