/// Een geweigerde sleutel vervangen, via je account, rechtstreeks bij de pc.
///
/// **Waarom dit bestaat.** Op 11-09-2026 werd de Shield opnieuw door zijn eigen pc geweigerd, terwijl
/// de Mac met zijn sleutel bij diezelfde pc gewoon binnenkwam. Het zelfherstel liep alleen via
/// Firestore -- de dienst die sinds #161 bekendstaat om zijn daglimiet -- en gaf stil op. De
/// accountweg bestond al, maar werkte alleen op het inlogscherm. En dat inlogscherm vroeg om een
/// wachtwoord dat de Shield al had.
///
/// **Sinds 14-10-2026 alleen nog de accountweg.** De terugval via de accountdatabase zette de sleutel
/// leesbaar in Firestore en is weg; de bronbewaker onderaan houdt dat zo.
///
/// Het verloop wordt hier met nepdiensten getoetst: er gaat niets het netwerk op. Onderaan staan
/// bronbewakers voor de plekken waar dit aan de app vastzit.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/sleutelherstel.dart';

final _pc = Uri.parse('http://192.168.0.117:47820');

void main() {
  group('het verloop', () {
    test('de accountweg geeft de nieuwe sleutel', () async {
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token',
        viaAccount: (pc, s) async => RemoteEndpoint(baseUrl: pc, token: 'nieuw-via-account'),
      );
      expect(r.sleutel, 'nieuw-via-account');
      expect(r.verloop.join(' '), contains('accountweg: toegang'));
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
      );
      expect(gevraagd, _pc,
          reason: 'die pc antwoordde net met een weigering, dus hij is bereikbaar — zoeken hoeft niet');
      expect(getoond, 'id-token-vers');
    });

    test('een pc die nee zegt: geen sleutel, en zijn reden bewaard', () async {
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token',
        viaAccount: (pc, s) async =>
            throw const RemoteException('Deze pc hoort bij een ander account.', statusCode: 403),
      );
      expect(r.sleutel, isNull);
      expect(r.verloop.join(' '), contains('ander account'),
          reason: 'de zin van de pc is de enige die iemand verder helpt');
    });

    test('een oudere pc die de accountweg niet kent: geen sleutel, wel een verhaal', () async {
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token',
        viaAccount: (pc, s) async => null,
      );
      expect(r.sleutel, isNull);
      expect(r.verloop.join(' '), contains('kent hem niet'));
    });

    test('een netwerkfout in de accountweg breekt niets af', () async {
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => 'id-token',
        viaAccount: (pc, s) async => throw SocketException('Connection refused'),
      );
      expect(r.sleutel, isNull);
      expect(r.verloop.join(' '), contains('Connection refused'),
          reason: 'stil opgeven is precies hoe dit tien dagen onopgemerkt bleef');
    });

    test('niet ingelogd: de accountweg wordt niet eens geprobeerd', () async {
      var accountGevraagd = false;
      final r = await herstelSleutel(
        basis: _pc,
        inlogsleutel: () async => '',
        viaAccount: (pc, s) async {
          accountGevraagd = true;
          return null;
        },
      );
      expect(accountGevraagd, isFalse, reason: 'zonder inlogsleutel valt er niets te laten zien');
      expect(r.sleutel, isNull);
      expect(r.verloop.join(' '), contains('niet ingelogd'));
    });
  });

  group('waar het aan de app vastzit', () {
    late final String hoofd = File('lib/main.dart').readAsStringSync();
    late final String sessie = File('lib/lan/client_session.dart').readAsStringSync();
    late final String inloggen = File('lib/login_screen.dart').readAsStringSync();

    test('het zelfherstel loopt via de accountweg, en nooit meer via de database', () {
      expect(hoofd, contains('herstelSleutel('));
      expect(hoofd, contains('RemoteClient.pairMetAccount('),
          reason: 'zonder de accountweg herstelt een geweigerd toestel zich nergens meer');
      expect(hoofd, isNot(contains('viaDatabase')),
          reason: 'die weg zette de sleutel leesbaar in Firestore');
      expect(hoofd, isNot(contains('verseSleutelVoor')));
      expect(inloggen, isNot(contains('awaitAccess(')),
          reason: 'het inlogscherm vraagt de pc zelf, niet de accountdatabase');
    });

    test('een nieuwe sleutel neemt de uitwijkadressen mee', () {
      final start = sessie.indexOf('Future<void> _vernieuwSleutel(');
      expect(start, greaterThan(-1), reason: '_vernieuwSleutel is hernoemd of verdwenen');
      final lijf = sessie.substring(start, sessie.indexOf('Future<void> unpair()', start));
      // Sinds uitlevering B op de HELE koppeling (`huidig.met`): uitwijkadressen, de id van de pc en de pin
      // gaan mee, en alleen de sleutels zijn nieuw.
      expect(lijf, contains('connect(huidig.met('),
          reason: 'anders is het Tailscale-adres na het herstel weg, en kom je buitenshuis niet binnen');
      expect(lijf, isNot(contains('connect(RemoteEndpoint(')), reason: 'een nieuwe koppeling van nul verliest de id en de pin');
      // `_log(` en niet meer `debugPrint(`: sinds 06-10-2026 gaat het ook naar verbinding.log, want
      // debugPrint verdwijnt in een vrijgegeven versie en dan zegt het herstel achteraf niets.
      expect(lijf, contains('_log('), reason: 'het herstel hoort te zeggen wat het doet');
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
