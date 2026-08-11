/// "Je pc staat uit" tegenover "dit toestel mag er niet meer in".
///
/// **Waarom dit bestaat.** Op een telefoon stond de eerste melding terwijl de pc gewoon antwoordde:
/// ping 13 ms, `GET /health` 200 vanaf datzelfde toestel. Het log van de app zei iets heel anders —
/// `De koppeling met de pc is niet meer geldig` — en dat is een 401. De melding stuurde dus naar de
/// router terwijl er met het netwerk niets aan de hand was.
///
/// De oorzaak was één kale `catch (e)` in `loadRemote`: vanaf daar was er geen 401 meer in het
/// systeem, alleen een `false` die óók "niets veranderd" en "er loopt al een scan" betekent.
/// `RemoteException.isUnauthorized` bestond al en werd nergens uitgelezen.
///
/// Deze toetsen draaien tegen een ECHTE HTTP-server die de twee gevallen naspeelt, want het gaat
/// juist om wat er over de lijn komt.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/library.dart';

void main() {
  late HttpServer server;
  late int status;
  late String basis;

  setUp(() async {
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    basis = 'http://127.0.0.1:${server.port}';
    unawaited(() async {
      await for (final req in server) {
        if (req.uri.path == '/health') {
          req.response.statusCode = 200;
          req.response.write(jsonEncode({'status': 'ok', 'name': 'test'}));
          await req.response.close();
          continue;
        }
        req.response.statusCode = status;
        if (status == 200) {
          req.response.write(jsonEncode({'albums': [], 'tracks': [], 'artists': []}));
        }
        await req.response.close();
      }
    }());
  });

  tearDown(() async => server.close(force: true));

  LibraryStore klant() => LibraryStore()
    ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse(basis), token: 'sleutel'));

  test('een 401 heet "sleutel geweigerd", niet "de pc is stil"', () async {
    status = 401;
    final lib = klant();
    expect(await lib.loadRemote(), isFalse);
    expect(lib.geenVerbinding, GeenVerbinding.sleutelGeweigerd,
        reason: 'dit is precies het geval dat als "je pc staat uit" op het scherm kwam');
  });

  test('een 403 telt net zo goed als geweigerd', () async {
    status = 403;
    final lib = klant();
    await lib.loadRemote();
    expect(lib.geenVerbinding, GeenVerbinding.sleutelGeweigerd);
  });

  test('een pc die helemaal niet antwoordt heet "stil"', () async {
    final lib = LibraryStore()
      // Een poort waar niets op luistert: dat is een slapende pc, geen weigering.
      ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:1'), token: 'x'));
    expect(await lib.loadRemote(), isFalse);
    expect(lib.geenVerbinding, GeenVerbinding.pcStil);
  });

  test('een serverfout is ook "stil" — daar valt voor de gebruiker niets aan te doen', () async {
    status = 500;
    final lib = klant();
    await lib.loadRemote();
    expect(lib.geenVerbinding, GeenVerbinding.pcStil);
  });

  test('zodra het weer lukt is de reden weg', () async {
    status = 401;
    final lib = klant();
    await lib.loadRemote();
    expect(lib.geenVerbinding, isNotNull);

    status = 200;
    expect(await lib.loadRemote(), isTrue);
    expect(lib.geenVerbinding, isNull, reason: 'anders blijft de balk staan terwijl alles werkt');
  });
}
