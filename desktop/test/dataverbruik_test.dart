// Dataverbruik (Saber, 27-10-2026: "data verbruik buitenshuis … ik wil een volledige analyse, de app moet vanaf nu alles
// bijhouden in een log, plus ik wil bij instellingen, sectie info wat men data verbruik is").
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/dataverbruik.dart';
import 'package:debridmusic/lan/certificaat.dart';
import 'package:debridmusic/lan/doorgever.dart';
import 'package:debridmusic/lan/range.dart';
import 'package:debridmusic/lan/verzendteller.dart';
import 'package:debridmusic/library.dart' show hoesMerkZonderPlafond;
import 'package:debridmusic/netsoort.dart';
import 'package:debridmusic/ui/dataverbruik_info.dart' show verdelingZin;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'hulp_tls.dart';

void main() {
  group('de soort, de maat en de naam', () {
    test('soort uit het pad: muziek, hoezen, catalogus, zones, de pc, internet', () {
      expect(soortVanPad('/stream/ab12.flac', vanDePc: true), Verkeerssoort.muziek);
      expect(soortVanPad('/groei/ab12.flac', vanDePc: true), Verkeerssoort.muziek);
      expect(soortVanPad('/art/xyz', vanDePc: true), Verkeerssoort.hoezen);
      expect(soortVanPad('/api/catalog', vanDePc: true), Verkeerssoort.catalogus);
      expect(soortVanPad('/api/zones/events', vanDePc: true), Verkeerssoort.zones);
      expect(soortVanPad('/api/state', vanDePc: true), Verkeerssoort.zones);
      expect(soortVanPad('/api/search', vanDePc: true), Verkeerssoort.pc);
      expect(soortVanPad('/2.0/', vanDePc: false), Verkeerssoort.buiten);
    });

    test('maten zoals op het scherm', () {
      expect(bytesZin(512), '512 B');
      expect(bytesZin(373 * 1024), '373 KB');
      expect(bytesZin((33.9 * 1048576).round()), '33,9 MB');
      expect(bytesZin(250 * 1048576), '250 MB');
      expect(bytesZin((6.3 * 1073741824).round()), '6,30 GB');
    });

    test('de naam van een stroom uit de bibliotheek, met of zonder plafond', () {
      final nummers = [(pad: 'http://pc.invalid/stream/ab12.flac', naam: 'Foreigner – I Want to Know What Love Is')];
      expect(stroomNaam(nummers, '/stream/ab12.flac?maxRate=44100&maxBits=16'),
          'Foreigner – I Want to Know What Love Is (met plafond)');
      expect(stroomNaam(nummers, '/stream/ab12.flac'), 'Foreigner – I Want to Know What Love Is');
      expect(stroomNaam(nummers, '/stream/onbekend.flac?maxRate=44100'), '/stream/onbekend.flac (met plafond)');
      expect(stroomNaam(nummers, '/art/xyz?w=1024'), '/art/xyz?w=1024');
    });
  });

  group('de teller op het toestel', () {
    var net = Netsoort.mobiel;
    var nu = DateTime(2026, 10, 27, 14, 45);

    test('DE KERN: per dag, per netwerk en per soort; een nummer krijgt een eigen regel', () async {
      final regels = <String>[];
      final s = DataverbruikStore(bestand: null, logboek: regels.add, netNu: () => net, klok: () => nu);
      await s.laad();
      s.tel(Verkeerssoort.muziek, (33.9 * 1048576).round(), wat: 'Foreigner – I Want to Know What Love Is');
      s.tel(Verkeerssoort.catalogus, 373 * 1024, wat: '/api/catalog');
      net = Netsoort.wifi;
      s.tel(Verkeerssoort.hoezen, 130 * 1024);
      final d = s.dag(nu);
      expect(d.van('mobiel', 'muziek'), (33.9 * 1048576).round());
      expect(d.van('mobiel', 'catalogus'), 373 * 1024);
      expect(d.van('wifi', 'hoezen'), 130 * 1024);
      expect(regels, ['27-10 mobiel  muziek  33,9 MB  Foreigner – I Want to Know What Love Is'],
          reason: 'alleen wat groter is dan 1 MB krijgt een eigen regel; de rest staat in het kwartier');
      expect(verdelingZin(d, 'mobiel'), 'muziek 33,9 MB · catalogus 373 KB');
      // Het kwartier: een samenvatting, en de regels gaan mee naar de pc.
      await s.kwartier();
      expect(regels.last, startsWith('27-10 kwartier  mobiel: muziek 33,9 MB, catalogus 373 KB | wifi: hoezen 130 KB'));
      expect(s.neemRegels(), hasLength(2));
      expect(s.neemRegels(), isEmpty);
      // Een nieuwe dag, en de maand telt beide.
      nu = DateTime(2026, 10, 28, 9);
      net = Netsoort.mobiel;
      s.tel(Verkeerssoort.muziek, 1000);
      expect(s.dag(nu).van('mobiel', 'muziek'), 1000);
      expect(s.maand(nu).van('mobiel', 'muziek'), (33.9 * 1048576).round() + 1000);
      expect(s.maand(DateTime(2026, 11, 1)).per, isEmpty);
      s.dispose();
    });

    test('bewaren en weer inlezen', () async {
      final map = Directory.systemTemp.createTempSync('dm_verbruik_');
      addTearDown(() => map.deleteSync(recursive: true));
      final bestand = '${map.path}${Platform.pathSeparator}dataverbruik.json';
      File(bestand).writeAsStringSync(jsonEncode({
        '2026-10-26': {
          'mobiel': {'muziek': 5000, 'ongeteld': 7},
        },
      }));
      final s = DataverbruikStore(bestand: bestand, logboek: null, netNu: () => Netsoort.mobiel);
      await s.laad();
      expect(s.dag(DateTime(2026, 10, 26)).van('mobiel', 'muziek'), 5000);
      expect(s.dag(DateTime(2026, 10, 26)).van('mobiel', 'ongeteld'), 7);
      s.dispose();
    });

    test('niet verstuurd: terug vooraan', () {
      final s = DataverbruikStore(bestand: null, logboek: null, netNu: () => Netsoort.mobiel);
      s.tel(Verkeerssoort.muziek, 2 << 20);
      final r = s.neemRegels();
      s.legTerug(r);
      expect(s.neemRegels(), r);
      s.dispose();
    });
  });

  group('de tellende client (alles wat met de pc praat)', () {
    tearDown(() => telVerkeer = null);

    test('DE KERN: de inhoud plus de koppen; een ingepakte catalogus op zijn ingepakte lengte', () async {
      final geteld = <String, int>{};
      telVerkeer = (u, n) => geteld[u.path] = (geteld[u.path] ?? 0) + n;
      final c = TellendeClient(MockClient((req) async {
        if (req.url.path == '/api/catalog') {
          // Wat de lijn droeg: 373 KB ingepakt; wat de app leest: 1,9 MB.
          return http.Response.bytes(Uint8List(1921 * 1024), 200,
              headers: {'content-length': '${373 * 1024}', 'content-encoding': 'gzip'});
        }
        if (req.url.path == '/art/x') return http.Response('', 304);
        return http.Response.bytes(Uint8List(130 * 1024), 200);
      }));
      await c.get(Uri.parse('https://pc/api/catalog'));
      await c.get(Uri.parse('https://pc/art/x'));
      await c.get(Uri.parse('https://pc/art/y'));
      expect(geteld['/api/catalog'], 373 * 1024 + kKoppenBytes);
      expect(geteld['/art/x'], kKoppenBytes, reason: 'een 304 kost ook iets');
      expect(geteld['/art/y'], 130 * 1024 + kKoppenBytes);
    });

    test('zonder teller gewoon doorgeven', () async {
      final c = TellendeClient(MockClient((req) async => http.Response('ok', 200)));
      expect((await c.get(Uri.parse('https://pc/x'))).body, 'ok');
    });
  });

  group('de pc: wat hij werkelijk stuurt', () {
    test('DE KERN: een nummer met zijn naam en wat er van het bestand ging; per kwartier per adres', () {
      final regels = <String>[];
      final t = Verzendteller(log: regels.add, publiek: () => '178.118.55.105', klok: () => DateTime(2026, 10, 27, 14, 46));
      t.tel('94.72.66.157', Verkeerssoort.muziek, 12 << 20,
          wat: 'Foreigner – I Want to Know What Love Is', totaal: 34 << 20, vraag: 'bytes=0-, omgezet 16/44100');
      t.tel('94.72.66.157', Verkeerssoort.hoezen, 130 << 10);
      t.tel('94.72.66.157', Verkeerssoort.hoezen, 130 << 10);
      t.tel('178.118.55.105', Verkeerssoort.catalogus, 373 << 10);
      expect(regels, [
        '27-10  94.72.66.157 (buiten)  muziek 12,0 MB van 34,0 MB  "Foreigner – I Want to Know What Love Is"  '
            '(bytes=0-, omgezet 16/44100)',
      ]);
      t.kwartier();
      expect(regels, contains('27-10  kwartier  94.72.66.157 (buiten)  12,3 MB: muziek 12,0 MB (1×), hoezen 260 KB (2×)'));
      expect(regels, contains('27-10  kwartier  178.118.55.105 (thuis)  373 KB: catalogus 373 KB (1×)'),
          reason: 'je eigen publieke adres is thuis — de Mac via de eigen deur');
      expect(Verzendteller.vandaag.value['buiten|muziek'], 12 << 20);
      expect(Verzendteller.vandaag.value['thuis|catalogus'], 373 << 10);
    });

    // 29-10-2026: op een zwakke wifi 505 kleine vragen van soort "zones" per kwartier, en niet te zien welke.
    test('het kwartier noemt de drukste kleine vragen, niet de muziek', () {
      final regels = <String>[];
      final t = Verzendteller(log: regels.add, klok: () => DateTime(2026, 10, 28, 11, 0));
      for (var i = 0; i < 300; i++) {
        t.tel('100.71.219.104', Verkeerssoort.zones, 3000, pad: '/api/zones/stand');
      }
      for (var i = 0; i < 25; i++) {
        t.tel('100.71.219.104', Verkeerssoort.zones, 3000, pad: '/api/state');
      }
      t.tel('100.71.219.104', Verkeerssoort.pc, 100, pad: '/api/tijd');
      for (var i = 0; i < 40; i++) {
        t.tel('100.71.219.104', Verkeerssoort.muziek, 1000, pad: '/stream/x.flac');
      }
      t.kwartier();
      expect(regels.single, endsWith(' · meest: /api/zones/stand 300×, /api/state 25×'),
          reason: 'muziek telt per nummer al mee; een pad onder de 20 keer is geen stapel');
      regels.clear();
      t.tel('100.71.219.104', Verkeerssoort.zones, 3000, pad: '/api/zones/stand');
      t.kwartier();
      expect(regels.single, isNot(contains('meest')), reason: 'elk kwartier begint opnieuw te tellen');
    });

    test('de weg van een adres', () {
      expect(wegVanAdres('192.168.0.176'), 'thuis');
      expect(wegVanAdres('127.0.0.1'), 'thuis');
      expect(wegVanAdres('100.71.219.104'), 'tailscale');
      expect(wegVanAdres('188.5.136.145'), 'buiten');
      expect(wegVanAdres('178.118.55.105', publiek: '178.118.55.105'), 'thuis');
    });

    test('serveFile telt wat er werkelijk uitging: heel, een stuk, en niets bij HEAD', () async {
      final map = Directory.systemTemp.createTempSync('dm_serve_');
      final f = File('${map.path}${Platform.pathSeparator}n.flac')..writeAsBytesSync(Uint8List(200 * 1024));
      final geteld = <int>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) => serveFile(req, f, contentType: 'audio/flac', verstuurd: geteld.add));
      addTearDown(() async {
        await server.close(force: true);
        map.deleteSync(recursive: true);
      });
      final c = HttpClient();
      Future<void> vraag(String methode, [String? range]) async {
        final r = await c.openUrl(methode, Uri.parse('http://127.0.0.1:${server.port}/stream/n.flac'));
        if (range != null) r.headers.set(HttpHeaders.rangeHeader, range);
        await (await r.close()).drain<void>();
      }

      await vraag('GET');
      await vraag('GET', 'bytes=100-199');
      await vraag('HEAD');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      c.close(force: true);
      expect(geteld, [200 * 1024, 100]);
    });
  });

  test('de doorgever meldt wat hij van de pc doorgaf', () async {
    final map = Directory.systemTemp.createTempSync('dm_doorgever_verbruik_');
    final f = File('${map.path}${Platform.pathSeparator}n.flac')..writeAsBytesSync(Uint8List(300 * 1024));
    final pc = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, proefCertificaat.context());
    pc.listen((req) => serveFile(req, f, contentType: 'audio/flac'));
    final geleverd = <(String, int)>[];
    final d = Doorgever(geleverd: (p, n) => geleverd.add((p, n)));
    await d.start();
    d.zetBron(DoorgeverBron(basis: Uri.parse('https://127.0.0.1:${pc.port}'), sleutel: 's', pin: proefCertificaat.pin));
    addTearDown(() async {
      await d.stop();
      await pc.close(force: true);
      map.deleteSync(recursive: true);
    });
    final c = HttpClient();
    final r = await c.getUrl(d.adresVoor(Uri.parse('http://pc.invalid/stream/ab12.flac?maxRate=44100')));
    await (await r.close()).drain<void>();
    c.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(geleverd, [('/stream/ab12.flac?maxRate=44100', 300 * 1024)]);
  });

  test('DE KERN: het merkteken van de pc draagt het plafond; zonder is het dat van de catalogus', () {
    // Gemeten 27-10-2026: artTag f660aba6, ETag "f660aba6-w1024" — nooit gelijk, dus elke hoes elke ronde opnieuw.
    expect(hoesMerkZonderPlafond('f660aba6-w1024'), 'f660aba6');
    expect(hoesMerkZonderPlafond('f660aba6'), 'f660aba6');
    expect(hoesMerkZonderPlafond(null), isNull);
    expect(hoesMerkZonderPlafond('a-wb'), 'a-wb');
  });

  test('aangesloten: alles wat met de pc praat telt, de pc telt wat hij stuurt, en Info toont het', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    expect(bron('lib/lan/client.dart'), contains('    TellendeClient(e.versleuteld ? pinClient('));
    final server = bron('lib/lan/server.dart');
    expect(server, contains('    _telVerzonden(res, Verkeerssoort.catalogus, lijf.length);'));
    expect(server, contains('      _telVerzonden(res, Verkeerssoort.hoezen, bytes.length);'));
    expect(server, contains("    _telVerzonden(res, soortVanPad(_padVan[res] ?? '', vanDePc: true), bytes.length);"));
    expect(server, contains("      case '/api/diag/verbruik':"));
    expect(RegExp(r'verstuurd: \(n\) => _telStroom\(').allMatches(server), hasLength(3));
    final main = bron('lib/main.dart');
    expect(main, contains('    telVerkeer = (u, n) => verbruik.tel(soortVanPad(u.path, vanDePc: true), n, wat: u.path);'));
    expect(main, contains('    session.doorgeverLeverde ='));
    expect(main, contains("        await c.ask('/api/diag/verbruik', {'toestel': warmteToestel(await ik), 'regels': regels});"));
    expect(main, contains('        DataverbruikInfo(store: dataverbruik, isPc: context.read<ClientSession>().owner),'));
    expect(bron('lib/library.dart'), contains('      final verouderd = merk.isNotEmpty && hoesMerkZonderPlafond(bewaard) != merk;'));
  });
}
