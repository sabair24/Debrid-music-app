/// De pc vragen wat er mis is, als de telefoon zelf niets kan zien.
///
/// **Waarom dit bestaat.** Op 14-09-2026 kreeg `kapot_bestand.dart` een regel die een afgekapte
/// FLAC herkent aan zijn eigen kop. Diezelfde avond stond er twee keer in `speler.log` van de
/// telefoon:
///
///     19:15:12  OPENEN MISLUKT — Sommeil — Error decoding audio.
///     20:08:48  OPENEN MISLUKT — Sommeil — Error decoding audio.
///
/// Sommeil is precies het bestand waarvan op schijf te zien is dat er 0,13 % van het geluid in
/// staat. De nieuwe regel zweeg — want `_redenUitBestand` kan alleen naar een bestand op DEZE
/// machine kijken, en op de telefoon is het pad een stroomadres. De pc had de bytes voor zich
/// liggen en werd niet gevraagd.
///
/// Dat is dezelfde vorm als de storing waar `kapot_bestand.dart` zelf uit ontstond: de app WIST
/// het en gooide het weg. Nu vraagt hij het na.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer pc;
  // Een tweede server op een ANDERE poort van dezelfde machine. Zonder deze is niet te zien of de
  // poort meegewogen wordt: een verzoek naar een poort waar niets luistert mislukt vanzelf, en dan
  // komt er ook null uit terwijl de controle weg is.
  late HttpServer buurman;
  late String basis;
  late List<String> gevraagd;
  late List<String> bijDeBuurman;
  late int antwoord;
  late String lijf;

  setUp(() async {
    gevraagd = [];
    bijDeBuurman = [];
    antwoord = 200;
    lijf = jsonEncode({
      'reden': 'er staat maar minder dan 1% in van het geluid dat de kop belooft — '
          'het bestand is afgekapt'
    });
    pc = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    basis = 'http://127.0.0.1:${pc.port}';
    unawaited(() async {
      await for (final req in pc) {
        gevraagd.add(req.uri.toString());
        req.response.statusCode = antwoord;
        // Het lijf hoort ook bij een FOUTCODE geschreven te worden. Schrijf je het alleen bij 200,
        // dan kan een toets niet zien of de client op de code let of op het lege antwoord — en dat
        // verschil is precies wat hier vastgehouden moet worden. 204 mag per definitie geen lijf.
        if (antwoord != HttpStatus.noContent && lijf.isNotEmpty) req.response.write(lijf);
        await req.response.close();
      }
    }());
    buurman = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final req in buurman) {
        bijDeBuurman.add(req.uri.toString());
        req.response.statusCode = 200;
        req.response.write(lijf);
        await req.response.close();
      }
    }());
  });

  tearDown(() async {
    await pc.close(force: true);
    await buurman.close(force: true);
  });

  RemoteClient klant() =>
      RemoteClient(RemoteEndpoint(baseUrl: Uri.parse(basis), token: 'sleutel'));

  group('de telefoon vraagt het de pc na', () {
    test('DE KERN: het antwoord van de pc komt terug', () async {
      final reden = await klant().waarom('$basis/stream/abc123.flac?token=sleutel');
      expect(reden, contains('afgekapt'),
          reason: 'zonder dit blijft "Error decoding audio" staan, en dat zegt niets');
    });

    test('DE KERN: hij vraagt het op /waarom, met dezelfde id', () async {
      await klant().waarom('$basis/stream/abc123.flac?token=sleutel');
      expect(gevraagd, hasLength(1));
      expect(gevraagd.single, startsWith('/waarom/abc123.flac'));
      expect(gevraagd.single, contains('token=sleutel'));
    });

    test('DE VAL: een adres dat NIET van onze pc is wordt niet aangeraakt', () async {
      // Een Radio-wachtrij mengt bibliotheeknummers met opgeloste TorBox-stromen. Die vraag zou
      // niet alleen zinloos zijn — de eigenaar kent onze catalogus niet — maar ook onze
      // koppelingssleutel aan een vreemde geven. Zelfde regel als bij `authorized`.
      expect(await klant().waarom('https://store.torbox.app/stream/xyz.flac'), isNull);
      expect(gevraagd, isEmpty, reason: 'er mag geen enkel verzoek de deur uit');
    });

    test('DE VAL: een andere machine op DEZELFDE poort is niet onze pc', () async {
      // De poort alleen is geen onderscheid: elke DebridMusic-pc luistert op 47820, dus een tweede
      // machine in huis heeft precies dezelfde poort en een andere naam. Zou de naam niet
      // meegewogen worden, dan ging onze koppelingssleutel daarheen.
      //
      // De vergelijking is LETTERLIJK, en dat is met opzet: `localhost` is feitelijk dezelfde
      // machine als `127.0.0.1`, maar de app bouwt zijn urls altijd uit `endpoint.baseUrl`, dus
      // alles wat daar niet woordelijk mee overeenkomt komt ergens anders vandaan. Zelfde
      // voorzichtigheid als in `authorized`.
      expect(await klant().waarom('http://localhost:${pc.port}/stream/abc123.flac'), isNull);
      expect(gevraagd, isEmpty, reason: 'de sleutel mag niet naar een naam die we niet kennen');
    });

    test('DE VAL: dezelfde machine op een ANDERE poort evenmin', () async {
      // Op de pc draait meer dan alleen dit: Jackett op 9117, FlareSolverr, een ander stuk
      // gereedschap. Naar zo'n poort mag de koppelingssleutel niet toe, ook al is het dezelfde
      // machine. Er luistert hier echt iets, dus als de poort niet meegewogen wordt, vángt hij het.
      expect(await klant().waarom('http://127.0.0.1:${buurman.port}/stream/abc123.flac'), isNull);
      expect(bijDeBuurman, isEmpty, reason: 'onze sleutel ging naar de verkeerde poort');
      expect(gevraagd, isEmpty);
    });

    test('DE VAL: een ander pad op onze pc telt evenmin', () async {
      // `/art/` en `/api/` zijn geen nummers. Zou dit erdoor glippen, dan bouwde hij een
      // `/waarom/`-url die nergens op slaat.
      expect(await klant().waarom('$basis/art/abc123?token=sleutel'), isNull);
      expect(gevraagd, isEmpty);
    });

    test('DE GRENS: 204 betekent "niets te melden", en dus null', () async {
      // Verreweg de meeste mislukte openingen liggen aan de verbinding. Dan is mpv's eigen woord
      // beter dan een verzonnen verklaring, en moet de bestaande melding blijven staan.
      antwoord = 204;
      expect(await klant().waarom('$basis/stream/abc123.flac'), isNull);
    });

    test('DE GRENS: een foutcode met een net antwoord erin telt niet', () async {
      // Een server die 500 geeft en er toch een `reden` bij zet — een proxy, een foutpagina, een
      // toekomstige versie — moet niet als uitleg op het scherm belanden. Alleen 200 is een
      // antwoord; een lege 204 valt hier vanzelf ook onder.
      antwoord = 500;
      lijf = jsonEncode({'reden': 'dit komt niet van de bestandscontrole'});
      expect(await klant().waarom('$basis/stream/abc123.flac'), isNull);
    });

    test('DE GRENS: een 404, een leeg antwoord of rommel geven null', () async {
      antwoord = 404;
      expect(await klant().waarom('$basis/stream/abc123.flac'), isNull);
      antwoord = 200;
      lijf = 'geen json';
      expect(await klant().waarom('$basis/stream/abc123.flac'), isNull);
      lijf = jsonEncode({'reden': '   '});
      expect(await klant().waarom('$basis/stream/abc123.flac'), isNull,
          reason: 'een zin van alleen spaties is geen uitleg');
      lijf = jsonEncode({'iets anders': 'x'});
      expect(await klant().waarom('$basis/stream/abc123.flac'), isNull);
      lijf = jsonEncode([1, 2, 3]);
      expect(await klant().waarom('$basis/stream/abc123.flac'), isNull);
    });

    test('DE GRENS: een pc die niet antwoordt levert null, geen fout', () async {
      // Dit draait NA een mislukking, om een melding preciezer te maken. Loopt het hier ook mis,
      // dan hoort de melding te blijven staan die er al stond — niet een tweede eroverheen.
      final dood = RemoteClient(
        RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:1'), token: 'sleutel'),
      );
      expect(await dood.waarom('http://127.0.0.1:1/stream/abc.flac'), isNull);
    });
  });
}
