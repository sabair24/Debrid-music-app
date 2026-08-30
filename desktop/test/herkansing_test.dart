/// Een bron die één keer blijft hangen mag niet de hele zoekopdracht kosten.
///
/// **Waarom dit bestaat.** Op het scherm stond "PirateBay — te traag (12 s)". Gemeten op
/// 30-08-2026, op dezelfde machine en hetzelfde moment:
///
///     curl, vraag "Adele 30"              0,098 s
///     kaal Dart-programma, zelfde vraag   0,071 s
///     de app, zelfde vraag               12     s  -> bron weggevallen
///     de app, de vraag ervóór en erná     1,5   s  -> gewoon goed
///
/// Wisselvallig dus, en met één poging ben je de hele bron kwijt terwijl de site het prima doet.
/// Twee pogingen van vijf seconden passen samen nog onder de kap van twaalf die de zoekverdeler
/// aanhoudt.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/search.dart';

void main() {
  final url = Uri.parse('https://apibay.org/q.php?q=test&cat=100');

  test('DE KERN: eerst een hik, daarna gewoon antwoord', () async {
    var pogingen = 0;
    final client = MockClient((req) async {
      pogingen++;
      if (pogingen == 1) {
        // Blijft hangen tot de klok van de aanroeper afgaat.
        await Future<void>.delayed(const Duration(seconds: 30));
      }
      return http.Response('{"ok":true}', 200);
    });

    final r = await haalMetHerkansing(url,
        client: client, per: const Duration(milliseconds: 80), pogingen: 2);

    expect(r.statusCode, 200);
    expect(pogingen, 2, reason: 'de tweede poging is precies waar het om gaat');
  });

  test('blijft hij hangen, dan zegt hij wát er geprobeerd is', () async {
    final client = MockClient((req) async {
      await Future<void>.delayed(const Duration(seconds: 30));
      return http.Response('', 200);
    });

    // Niet alleen "te traag": wie dat leest denkt dat de site down is. Er hoort bij hoe vaak en hoe
    // lang er geprobeerd is, want daarmee kun je het verschil zien met een bron die écht weg is.
    await expectLater(
      haalMetHerkansing(url, client: client, per: const Duration(milliseconds: 60), pogingen: 2),
      throwsA(isA<TimeoutException>().having((e) => e.message, 'message',
          allOf(contains('2 pogingen'), contains('te traag')))),
    );
  });

  test('gaat het meteen goed, dan blijft het bij één verzoek', () async {
    var pogingen = 0;
    final client = MockClient((req) async {
      pogingen++;
      return http.Response('{"ok":true}', 200);
    });

    await haalMetHerkansing(url, client: client);

    expect(pogingen, 1, reason: 'een herkansing is voor een hik, niet voor elk verzoek');
  });

  test('een POST gaat op dezelfde manier', () async {
    // Knaben zoekt met een POST; die hoort dezelfde bescherming te krijgen als de rest.
    String? gezien;
    var pogingen = 0;
    final client = MockClient((req) async {
      pogingen++;
      gezien = req.body;
      if (pogingen == 1) await Future<void>.delayed(const Duration(seconds: 30));
      return http.Response('{"hits":[]}', 200);
    });

    final r = await haalMetHerkansing(Uri.parse('https://api.knaben.org/v1'),
        lichaam: '{"query":"x"}',
        koppen: const {'Content-Type': 'application/json'},
        client: client,
        per: const Duration(milliseconds: 80));

    expect(r.statusCode, 200);
    expect(gezien, '{"query":"x"}', reason: 'de herkansing stuurt hetzelfde mee');
  });

  test('een fout die GEEN klok is wordt niet nog eens geprobeerd', () async {
    // Een 500 of een certificaatfout wordt er niet beter op door het meteen te herhalen; dat kost
    // alleen tijd waar de zoekopdracht op wacht.
    var pogingen = 0;
    final client = MockClient((req) async {
      pogingen++;
      return http.Response('boem', 500);
    });

    final r = await haalMetHerkansing(url, client: client);

    expect(r.statusCode, 500);
    expect(pogingen, 1);
  });
}
