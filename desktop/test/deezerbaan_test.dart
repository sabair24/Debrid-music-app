/// De rijbaan naar Deezer, en zijn weigering die als "gelukt" binnenkomt.
///
/// **Waarom dit bestaat.** Gemeten op 02-09-2026: de startpagina vuurt bij een koude start
/// eenenzestig verzoeken af, waar Deezer er ongeveer vijftig per vijf seconden toestaat. Van zestig
/// gelijktijdige verzoeken kwamen er tien terug met status **200** en dit lichaam:
///
///     {"error":{"type":"Exception","message":"Quota limit exceeded","code":4}}
///
/// De oude `_get` keek alleen naar `statusCode != 200`, gaf die map door, en de aanroeper zocht er
/// `data` in dat er niet in stond. "Deezer weigerde" werd zo een lege lijst — niet te onderscheiden
/// van "er is niets gevonden". Dat is de fout die deze toetsen vastzetten.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/deezerbaan.dart';

void main() {
  setUp(DeezerBaan.vergeet);

  test('DE KERN: een quotaweigering met status 200 is een fout, geen lege lijst', () async {
    final klant = MockClient((_) async => http.Response(
        jsonEncode({
          'error': {'type': 'Exception', 'message': 'Quota limit exceeded', 'code': 4}
        }),
        200,
        headers: {'content-type': 'application/json'}));

    await expectLater(
      DeezerBaan.haal('https://api.deezer.com/chart/0/albums', client: klant),
      throwsA(isA<DeezerFout>().having((e) => e.quota, 'quota', isTrue)),
    );
  });

  test('en een gewoon antwoord komt gewoon door', () async {
    final klant = MockClient((_) async => http.Response(
        jsonEncode({
          'data': [
            {'id': 1, 'title': 'Iets'}
          ]
        }),
        200,
        headers: {'content-type': 'application/json'}));

    final j = await DeezerBaan.haal('https://api.deezer.com/chart/0/albums', client: klant);
    expect((j?['data'] as List?), hasLength(1));
  });

  test('een andere fout van Deezer telt niet als budgetfout', () async {
    // Wachten helpt daar niet, en dat mag het scherm niet suggereren.
    final klant = MockClient((_) async => http.Response(
        jsonEncode({
          'error': {'type': 'DataException', 'message': 'no data', 'code': 800}
        }),
        200));

    await expectLater(
      DeezerBaan.haal('https://api.deezer.com/artist/0/related', client: klant),
      throwsA(isA<DeezerFout>().having((e) => e.quota, 'quota', isFalse)),
    );
  });

  test('een echte foutstatus wordt ook een fout', () async {
    final klant = MockClient((_) async => http.Response('', 503));
    await expectLater(
      DeezerBaan.haal('https://api.deezer.com/genre', client: klant),
      throwsA(isA<DeezerFout>()),
    );
  });

  test('de verzoeken houden afstand van elkaar', () async {
    // Dit is waar de baan voor bestaat: niet sneller dan het budget toestaat. Drie verzoeken
    // moeten dus minstens twee tussenpozen kosten.
    final klant = MockClient((_) async => http.Response('{"data":[]}', 200));
    final begin = DateTime.now();
    await Future.wait([
      for (var i = 0; i < 3; i++) DeezerBaan.haal('https://api.deezer.com/x$i', client: klant),
    ]);
    final duur = DateTime.now().difference(begin);
    expect(duur, greaterThanOrEqualTo(DeezerBaan.minimaleTussenpoos * 2),
        reason: 'zonder afstand houden loopt de startpagina zijn eigen budget omver');
  });

  test('de artiest-id-kaart wordt gedeeld', () {
    // Twee rijen zoeken dezelfde namen op. Delen scheelt niet alleen verzoeken: het dwingt af dat
    // beide dezelfde "Adele" bedoelen.
    expect(DeezerBaan.gekendId('adele'), isNull);
    DeezerBaan.onthoudId('adele', 75798);
    expect(DeezerBaan.gekendId('adele'), 75798);
    DeezerBaan.vergeet();
    expect(DeezerBaan.gekendId('adele'), isNull);
  });
}
