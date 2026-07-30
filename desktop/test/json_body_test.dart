/// JSON is UTF-8, wat de server ook meestuurt.
///
/// De eerste test hier bewijst de VAL en niet onze code: hij laat zien dat `response.body` de tekst
/// echt kapotmaakt. Zonder die regel leest de tweede test als een overbodige omweg, en dan zet iemand
/// hem later "netjes" terug naar `.body`.
library;

import 'dart:convert';

import 'package:debridmusic/json_body.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Een antwoord zoals TheAudioDB het stuurt: nette JSON, geen charset in de kop.
http.Response _zonderCharset(String json) => http.Response.bytes(
      utf8.encode(json),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  // Precies wat er op de albumpagina van Unapologetic stond, en in de feitencache bij Enrique.
  const json = '{"t":"Nobody’s Business","a":"Más es amar"}';

  test('geen charset opgegeven: dan raadt het pakket zelf goed', () {
    // Gemeten, en het weerlegt waar ik van uitging. Ik dacht dat een ontbrekende charset hier op
    // latin1 zou terugvallen -- dat staat zo in oudere documentatie -- maar deze versie doet dat niet.
    // Het staat er als test zodat de volgende lezer niet denkt dat jsonBody dit geval oplost.
    expect((jsonDecode(_zonderCharset(json).body) as Map)['t'], 'Nobody’s Business');
  });

  test('de val: een server die de VERKEERDE charset opgeeft', () {
    // Hier gaat `.body` wel om, en terecht: het pakket doet netjes wat de kop zegt. Alleen zegt de
    // kop iets onmogelijks, want JSON is per RFC 8259 altijd UTF-8. Vandaar dat we de kop negeren.
    final r = http.Response.bytes(utf8.encode(json), 200,
        headers: {'content-type': 'application/json; charset=iso-8859-1'});
    expect(r.body, isNot(contains('’')), reason: 'de kop volgen levert kapotte tekst');
    expect((jsonBody(r) as Map)['t'], 'Nobody’s Business', reason: 'de bytes volgen levert de tekst');
  });

  test('jsonBody leest de bytes en houdt de tekst heel', () {
    final goed = jsonBody(_zonderCharset(json)) as Map;
    expect(goed['t'], 'Nobody’s Business');
    expect(goed['a'], 'Más es amar');
  });

  test('een server die WEL charset stuurt gaat er niet aan onderuit', () {
    final r = http.Response.bytes(utf8.encode(json), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
    expect((jsonBody(r) as Map)['t'], 'Nobody’s Business');
  });

  test('één kapotte byte kost niet de hele opzoeking', () {
    // allowMalformed: een vraagteken in een titel is beter dan een uitzondering die de plaat
    // naamloos laat.
    final r = http.Response.bytes(
        [...utf8.encode('{"t":"ok'), 0xff, ...utf8.encode('"}')], 200,
        headers: {'content-type': 'application/json'});
    expect((jsonBody(r) as Map)['t'], startsWith('ok'));
  });
}
