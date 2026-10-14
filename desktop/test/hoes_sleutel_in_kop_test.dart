/// Hoezen halen met de sleutel in de kop, niet in het adres.
///
/// Stap 5 van "verbinden zoals Roon ARC" (14-10-2026). `artUrl` zette de sleutel in het adres; sinds
/// deze stap gaat hij in de kop. Vergeet één route die kop, dan krijgt elk toestel stil een 401 op elke
/// hoes — en die fout zag geen enkele toets (gevonden met een mutatie: de kop weg bij `art` en
/// `artAls`, alles bleef groen).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';

void main() {
  late HttpServer pc;
  late List<String> adressen;
  final hoes = Uint8List.fromList(List<int>.generate(300, (i) => i % 251));

  setUp(() async {
    adressen = [];
    pc = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    pc.listen((req) async {
      adressen.add(req.uri.toString());
      // Zoals de echte pc: zonder geldige sleutel niets.
      if (req.headers.value(HttpHeaders.authorizationHeader) != 'Bearer sleutel') {
        req.response.statusCode = 401;
        await req.response.close();
        return;
      }
      req.response.headers.set(HttpHeaders.etagHeader, '"merk-1"');
      if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == '"merk-1"') {
        req.response.statusCode = 304;
      } else {
        req.response.add(hoes);
      }
      await req.response.close();
    });
  });

  tearDown(() => pc.close(force: true));

  RemoteClient klant() =>
      RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${pc.port}'), token: 'sleutel'));

  test('art: de hoes komt, met de sleutel in de kop en niet in het adres', () async {
    expect(await klant().art('album-1'), hoes);
    expect(adressen.single, isNot(contains('token=')));
  });

  test('artAls: met en zonder merk, ook met de sleutel in de kop', () async {
    final nieuw = await klant().artAls('album-1', '', maxZijde: 390);
    expect(nieuw?.bytes, hoes);
    expect(nieuw?.etag, 'merk-1');
    final zelfde = await klant().artAls('album-1', 'merk-1');
    expect(zelfde?.ongewijzigd, isTrue, reason: 'het merk ging mee naast de sleutel');
    expect(adressen.first, contains('w=390'));
    expect(adressen.every((a) => !a.contains('token=')), isTrue);
  });

  test('artUrl draagt geen sleutel meer', () {
    expect(klant().artUrl('album-1').toString(), isNot(contains('token')));
    expect(klant().artUrl('album-1', maxZijde: 200).queryParameters, {'w': '200'});
  });
}
