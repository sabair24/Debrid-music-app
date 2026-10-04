/// "Uitgave kiezen" zegt hoeveel pixels elke scan heeft.
///
/// Saber op 04-10-2026: *"bij de uitgave kiezen wil ik graag de resolutie groter zien, nu moet ik blind
/// kiezen zonder ik weet welke resolutie het is."* De hoes van de uitgave die je kiest wordt je
/// albumhoes; de kiezer toonde per uitgave drie miniaturen van 58 punten, en de maat van de scan
/// erachter stond nergens.
///
/// Gemeten tegen de echte servers die dag: de Cover Art Archive gaf voor *In The Lonely Hour* een hoes
/// van 2826×2812 (gelezen uit de eerste 64 kB, twee seconden), Discogs levert via zijn API hooguit 600
/// pixels (600×598, en die maat geeft Discogs zelf mee).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/editions.dart';
import 'package:debridmusic/main.dart' show ScanMaatRegel;
import 'package:debridmusic/scanmaat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// De kop van een PNG van [w]×[h]: handtekening, en dan het IHDR-brok met de maat.
Uint8List _png(int w, int h) {
  final b = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
    ..add(ascii.encode('IHDR'))
    ..add([(w >> 24) & 255, (w >> 16) & 255, (w >> 8) & 255, w & 255])
    ..add([(h >> 24) & 255, (h >> 16) & 255, (h >> 8) & 255, h & 255])
    ..add(List<int>.filled(40, 0));
  return b.toBytes();
}

/// Een JPEG waarvan de maat pas na [vulling] bytes komt: een groot ingesloten voorbeeldje vooraan.
Uint8List _jpegMetLaatsteMaat(int w, int h, int vulling) {
  final b = BytesBuilder()..add([0xFF, 0xD8]);
  // APPn-segmenten van hooguit 65535 bytes elk, tot de vulling erin zit.
  var over = vulling;
  while (over > 0) {
    final stuk = over > 65000 ? 65000 : over;
    b
      ..add([0xFF, 0xE1, (stuk + 2) >> 8, (stuk + 2) & 255])
      ..add(List<int>.filled(stuk, 0));
    over -= stuk;
  }
  b
    ..add([0xFF, 0xC0, 0x00, 0x11, 0x08, h >> 8, h & 255, w >> 8, w & 255])
    ..add(List<int>.filled(30, 0));
  return b.toBytes();
}

/// Een server die reeksen begrijpt, en telt hoe vaak hij gevraagd wordt.
MockClient _server(Uint8List bestand, List<String> reeksen, {int status = 206}) => MockClient((r) async {
      final reeks = r.headers['Range'] ?? r.headers['range'] ?? '';
      reeksen.add(reeks);
      final m = RegExp(r'bytes=0-(\d+)').firstMatch(reeks);
      final eind = m == null ? bestand.length - 1 : int.parse(m.group(1)!);
      final stuk = bestand.sublist(0, eind + 1 < bestand.length ? eind + 1 : bestand.length);
      return http.Response.bytes(stuk, status);
    });

void main() {
  setUp(resetScanmatenVoorTest);

  group('de maat', () {
    test('DE KERN: uit de eerste bytes, met een reeks — nooit het hele bestand', () async {
      final reeksen = <String>[];
      final m = await scanMaatVan(const ChoiceImage('https://caa/x.png', 'https://caa/t.png'),
          client: _server(_png(2826, 2812), reeksen));
      expect(m, (w: 2826, h: 2812));
      expect(reeksen, ['bytes=0-65535']);
    });

    test('DE VAL: staat de maat verder dan 64 kB, dan nog één keer tot een megabyte', () async {
      final reeksen = <String>[];
      final m = await scanMaatVan(const ChoiceImage('https://caa/x.jpg', 'https://caa/t.jpg'),
          client: _server(_jpegMetLaatsteMaat(1500, 1400, 90000), reeksen));
      expect(m, (w: 1500, h: 1400));
      expect(reeksen, ['bytes=0-65535', 'bytes=0-1048575']);
    });

    test('wat Discogs al meegaf, wordt niet opgehaald', () async {
      final reeksen = <String>[];
      final m = await scanMaatVan(const ChoiceImage('https://i.discogs.com/x.jpg', 't', breedte: 600, hoogte: 598),
          client: _server(_png(1, 1), reeksen));
      expect(m, (w: 600, h: 598));
      expect(reeksen, isEmpty);
    });

    test('DE GRENS: een rij met alleen een miniatuur zegt niets — "150×150" zou over de scan liegen', () async {
      final reeksen = <String>[];
      final m = await scanMaatVan(const ChoiceImage('https://i.discogs.com/150.jpg', 'https://i.discogs.com/150.jpg',
          alleenMiniatuur: true), client: _server(_png(150, 150), reeksen));
      expect(m, isNull);
      expect(reeksen, isEmpty);
    });

    test('één keer per scan, ook als er tien rijen om vragen', () async {
      final reeksen = <String>[];
      final client = _server(_png(1200, 1200), reeksen);
      const img = ChoiceImage('https://caa/x.png', 'https://caa/t.png');
      await Future.wait([for (var i = 0; i < 10; i++) scanMaatVan(img, client: client)]);
      expect(reeksen, hasLength(1));
    });

    test('een fout van de server is geen maat', () async {
      final m = await scanMaatVan(const ChoiceImage('https://caa/weg.png', 't'),
          client: MockClient((_) async => http.Response('nee', 404)));
      expect(m, isNull);
    });

    test('een netwerkhik mag de volgende keer opnieuw', () async {
      var keer = 0;
      final client = MockClient((_) async {
        keer++;
        if (keer == 1) throw http.ClientException('weg');
        return http.Response.bytes(_png(900, 900), 206);
      });
      const img = ChoiceImage('https://caa/hik.png', 't');
      expect(await scanMaatVan(img, client: client), isNull);
      expect(await scanMaatVan(img, client: client), (w: 900, h: 900));
    });
  });

  group('hoe scherp', () {
    test('de korte kant beslist', () {
      expect(scherpteVan((w: 2826, h: 2812)), Scherpte.scherp);
      expect(scherpteVan((w: 3532, h: 2752)), Scherpte.scherp, reason: 'een achterkant is zelden vierkant');
      expect(scherpteVan((w: 600, h: 598)), Scherpte.bruikbaar, reason: 'wat Discogs levert');
      expect(scherpteVan((w: 1200, h: 450)), Scherpte.klein, reason: 'een strook, geen hoes');
      expect(scherpteVan((w: 300, h: 300)), Scherpte.klein);
      expect(maatTekst((w: 1400, h: 1400)), '1400×1400');
    });
  });

  group('op het scherm', () {
    Widget kader(Widget w) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 58, child: w))));

    testWidgets('DE KERN: onder de miniatuur staat de maat', (tester) async {
      await tester.pumpWidget(kader(const ScanMaatRegel(img: ChoiceImage('u', 't', breedte: 1400, hoogte: 1400))));
      expect(find.text('1400×1400'), findsOneWidget);
    });

    testWidgets('DE GRENS: niet bekend is niets, geen verzonnen getal', (tester) async {
      await tester.pumpWidget(
          kader(const ScanMaatRegel(img: ChoiceImage('u', 'u', alleenMiniatuur: true))));
      await tester.pump();
      expect(find.byKey(const Key('scanmaat')), findsNothing);
    });

    testWidgets('een maat van vijf cijfers past ook in 58 punten', (tester) async {
      await tester.pumpWidget(kader(const ScanMaatRegel(img: ChoiceImage('u', 't', breedte: 12000, hoogte: 9000))));
      expect(find.text('12000×9000'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'geen overloop');
    });

    test('de kiezer en "Alle scans" tonen hem allebei', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(RegExp(r'ScanMaatRegel\(img: img\)').allMatches(main).length, greaterThanOrEqualTo(2));
      expect(main, contains('richMessage: WidgetSpan(child: _ScanVoorbeeld(img: img))'),
          reason: 'en groot in een zweeftip bij "Alle scans"');
      expect(main, contains('WidgetSpan(child: _ScanVoorbeeld(img: img)),'), reason: 'en bij de miniaturen in de rij');
    });
  });
}
