/// Een zoekvraag mag de app niet laten stilstaan.
///
/// **De storing.** Saber op 12-09-2026: "crash bij het beginnen van radio", met een schermafdruk van
/// "DebridMusic reageert niet". Gemeten terwijl het gebeurde, op de echte pc:
///
///     13:18:35    690 MB   987 handles
///     13:18:40   1271 MB  9477 handles      <- radio gestart
///     hartslag.log:  HAPERING 7.3 s niets gedaan | speelt "Don't Stop 'Til You Get Enough"
///     fps.log:       build 0.4ms | raster 2.4ms | WACHT OP START 64443.9ms (de zwaardere keer)
///
/// Op dat moment stonden er 4678 verbindingen open op de Soulseek-luisterpoort, van 4367
/// verschillende adressen. Zo werkt het protocol: je stelt een vraag en elke peer die iets heeft
/// belt ZELF aan om zijn lijst af te leveren. De app nam ze allemaal aan, pakte elk antwoord uit en
/// ontleedde het volledig — tot vijfhonderd bestandsregels per stuk, met naam, lengte en kenmerken —
/// ook nadat de zoektocht allang gestopt was bij zijn vierhonderd treffers. Daarna bleef elke
/// verbinding nog dertig seconden open staan wachten op niets.
///
/// Drie grendels, van goedkoop naar grof: niet ontleden waar niemand op wacht, vijf seconden in
/// plaats van dertig voor een verbinding die alleen resultaten bracht, en een bovengrens op het
/// aantal dat er tegelijk open mag staan.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een zoekantwoord zoals het van de lijn komt, uitgepakt: naam van de peer, dan het kaartje.
Uint8List _antwoord(String peer, int ticket) {
  final naam = utf8.encode(peer);
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  u32(naam.length);
  b.add(naam);
  u32(ticket);
  u32(3); // aantal bestanden — hier verder niet ingevuld, want het mag niet gelezen worden
  return b.toBytes();
}

void main() {
  test('DE KERN: een antwoord op een zoektocht die klaar is wordt niet ontleed', () {
    // De zoektocht met kaartje 111 loopt nog; 222 is gestopt en zijn sink is weggehaald.
    expect(wilZoekantwoord(_antwoord('peer-a', 222), {111}), isFalse,
        reason: 'tot vijfhonderd bestandsregels ontleden voor een zoektocht die al gestopt is');
  });

  test('DE KERN: een antwoord waar wél iemand op wacht komt er gewoon door', () {
    expect(wilZoekantwoord(_antwoord('peer-a', 111), {111, 222}), isTrue);
  });

  test('DE GRENS: zonder lopende zoektocht is elk antwoord overbodig', () {
    // Dit is de staart: de zoektocht is voorbij en de peers blijven nog een halve minuut
    // aanbellen. Gemeten in één radiostart: duizenden van deze.
    expect(wilZoekantwoord(_antwoord('peer-a', 111), const {}), isFalse);
  });

  test('DE VAL: een antwoord dat te kort is voor een kaartje wordt tóch ontleed', () {
    // Een zoektocht die één treffer mist is erger dan een antwoord dat te veel werk kost.
    expect(wilZoekantwoord(Uint8List.fromList([9, 9]), {111}), isTrue,
        reason: 'bij twijfel weggooien kost stil zoekresultaten');
  });

  test('DE KERN: een verbinding die alleen resultaten bracht gaat na vijf seconden dicht', () {
    expect(stilTot(geclaimd: false), const Duration(seconds: 5));
    expect(stilTot(geclaimd: true), const Duration(seconds: 30),
        reason: 'op een gesprek over een bestand wacht wél iemand op antwoord');
  });

  test('DE GRENS: boven de bovengrens wordt een peer geweigerd in plaats van aangenomen', () async {
    final oud = SoulseekClient.maxInbound;
    SoulseekClient.maxInbound = 2;
    addTearDown(() => SoulseekClient.maxInbound = oud);

    // Een vrije poort zoeken en meteen weer loslaten, zodat de client hem kan nemen.
    final proef = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final poort = proef.port;
    await proef.close();

    final client = SoulseekClient()..listenPort = poort;
    expect(await client.ensureListening(), poort, reason: 'de proefpoort was niet te nemen');
    addTearDown(client.stopListening);

    final open = <Socket>[];
    addTearDown(() {
      for (final s in open) {
        s.destroy();
      }
    });
    for (var i = 0; i < 4; i++) {
      open.add(await Socket.connect(InternetAddress.loopbackIPv4, poort));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }

    expect(client.levendeInbound, lessThanOrEqualTo(2),
        reason: 'er staan er meer open dan de bovengrens toelaat');
    expect(client.geweigerdInbound, greaterThan(0),
        reason: 'de vierde peer had geweigerd moeten worden');
  });
}
