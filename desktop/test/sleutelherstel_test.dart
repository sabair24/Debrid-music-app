/// Een geweigerde sleutel vervangen: eerst via je account, pas daarna via de accountdatabase.
///
/// **Waarom dit bestaat.** Op 11-09-2026 werd de Shield opnieuw door zijn eigen pc geweigerd, terwijl
/// de Mac met zijn sleutel bij diezelfde pc gewoon binnenkwam. Het zelfherstel liep alleen via
/// Firestore -- de dienst die sinds #161 bekendstaat om zijn daglimiet -- en gaf stil op. De
/// accountweg bestond al, maar werkte alleen op het inlogscherm. En dat inlogscherm vroeg om een
/// wachtwoord dat de Shield al had.
///
/// De volgorde wordt hier met nepdiensten getoetst: er gaat niets het netwerk op. Onderaan staan drie
/// bronbewakers voor de plekken waar dit aan de app vastzit.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/sleutelherstel.dart';

final _pc = Uri.parse('http://192.168.0.117:47820');

void main() {
  group('de volgorde', () {
    test('de accountweg eerst, en dan wordt de database niet eens gevraagd', () async {
      var databaseGevraagd = false;
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token',
        viaAccount: (pc, s) async => RemoteEndpoint(baseUrl: pc, token: 'nieuw-via-account'),
        viaDatabase: (_) async {
          databaseGevraagd = true;
          return 'nieuw-via-database';
        },
      );
      expect(r.sleutel, 'nieuw-via-account');
      expect(databaseGevraagd, isFalse,
          reason: 'de database is de dienst met de daglimiet — wie hem niet nodig heeft, vraagt hem niet');
    });

    test('de accountweg krijgt het adres dat weigerde, met de verse inlogsleutel', () async {
      Uri? gevraagd;
      String? getoond;
      await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token-vers',
        viaAccount: (pc, s) async {
          gevraagd = pc;
          getoond = s;
          return null;
        },
        viaDatabase: (_) async => null,
      );
      expect(gevraagd, _pc,
          reason: 'die pc antwoordde net met een weigering, dus hij is bereikbaar — zoeken hoeft niet');
      expect(getoond, 'id-token-vers');
    });

    test('een pc die nee zegt: terug naar de database, en zijn reden bewaard', () async {
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token',
        viaAccount: (pc, s) async =>
            throw const RemoteException('Deze pc hoort bij een ander account.', statusCode: 403),
        viaDatabase: (_) async => 'nieuw-via-database',
      );
      expect(r.sleutel, 'nieuw-via-database');
      expect(r.verloop.join(' '), contains('ander account'),
          reason: 'de zin van de pc is de enige die iemand verder helpt');
    });

    test('een oudere pc die de accountweg niet kent: gewoon de database', () async {
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token',
        viaAccount: (pc, s) async => null,
        viaDatabase: (_) async => 'nieuw-via-database',
      );
      expect(r.sleutel, 'nieuw-via-database');
    });

    test('een netwerkfout in de accountweg breekt niets af', () async {
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token',
        viaAccount: (pc, s) async => throw SocketException('Connection refused'),
        viaDatabase: (_) async => 'nieuw-via-database',
      );
      expect(r.sleutel, 'nieuw-via-database');
    });

    test('niet ingelogd: de accountweg vervalt, de database wordt nog wel geprobeerd', () async {
      var accountGevraagd = false;
      var databaseGevraagd = false;
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => '',
        viaAccount: (pc, s) async {
          accountGevraagd = true;
          return null;
        },
        viaDatabase: (_) async {
          databaseGevraagd = true;
          return null;
        },
      );
      expect(accountGevraagd, isFalse, reason: 'zonder inlogsleutel valt er niets te laten zien');
      expect(databaseGevraagd, isTrue);
      expect(r.sleutel, isNull);
    });

    test('niets werkt: geen sleutel, maar wel een verhaal voor het logboek', () async {
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token',
        viaAccount: (pc, s) async => null,
        viaDatabase: (_) async => throw Exception('Quota exceeded'),
      );
      expect(r.sleutel, isNull);
      expect(r.verloop.length, greaterThanOrEqualTo(2),
          reason: 'stil opgeven is precies hoe dit tien dagen onopgemerkt bleef');
      expect(r.verloop.join(' '), contains('Quota exceeded'));
    });
  });

  group('waar het aan de app vastzit', () {
    late final String hoofd = File('lib/main.dart').readAsStringSync();
    late final String sessie = File('lib/lan/client_session.dart').readAsStringSync();
    late final String inloggen = File('lib/login_screen.dart').readAsStringSync();

    test('het zelfherstel loopt via de accountweg, met de database als terugval', () {
      expect(hoofd, contains('herstelSleutel('));
      expect(hoofd, contains('RemoteClient.pairMetAccount('),
          reason: 'zonder de accountweg is dit weer alleen de database, en die zat aan zijn limiet');
      expect(hoofd, contains('viaDatabase: (pc) => cloud.verseSleutelVoor(pc)'));
    });

    test('een nieuwe sleutel neemt de uitwijkadressen mee', () {
      final start = sessie.indexOf('Future<void> _vernieuwSleutel()');
      expect(start, greaterThan(-1), reason: '_vernieuwSleutel is hernoemd of verdwenen');
      final lijf = sessie.substring(start, sessie.indexOf('Future<void> unpair()', start));
      expect(lijf, contains('uitwijk: huidig.uitwijk'),
          reason: 'anders is het Tailscale-adres na het herstel weg, en kom je buitenshuis niet binnen');
      expect(lijf, contains('debugPrint('), reason: 'het herstel hoort te zeggen wat het doet');
    });

    test('"Opnieuw proberen" probeert het sleutelherstel ook echt opnieuw', () {
      final start = sessie.indexOf('Future<void> refreshNow()');
      expect(start, greaterThan(-1));
      expect(sessie.substring(start, start + 120), contains('_sleutelGevraagd = false'),
          reason: 'na één mislukte poging deed die knop anders niets meer dan de catalogus opvragen');
    });

    test('al ingelogd: het inlogscherm zoekt meteen de pc, zonder formulier', () {
      final start = inloggen.indexOf('void initState()');
      expect(start, greaterThan(-1), reason: 'het inlogscherm heeft geen initState meer');
      final lijf = inloggen.substring(start, inloggen.indexOf('void dispose()', start));
      expect(lijf, contains('widget.session.isSignedIn'));
      expect(lijf, contains('_findServer()'),
          reason: 'anders vraagt het een wachtwoord dat dit toestel al heeft');
    });

    test('het zelfherstel wacht tot de cloudsessie hersteld is', () {
      final start = hoofd.indexOf('inlogsleutel: () async {');
      expect(start, greaterThan(-1),
          reason: 'de inlogsleutel wordt weer meteen gevraagd — dan valt de accountweg vlak na het '
              'opstarten af met "niet ingelogd", zoals op 11-09-2026 om 17:15:56');
      final lijf = hoofd.substring(start, start + 200);
      expect(lijf.indexOf('await cloud.hersteld'), lessThan(lijf.indexOf('cloud.idToken()')),
          reason: 'eerst wachten op de sessie, dán om een sleutel vragen');
    });
  });
}
