/// De drie ingangen van de pc: 47820 (HTTP, thuis), 47822 (TLS, thuis) en 47821 (TLS, van buiten).
/// Welke sleutel waar geldt, de ruil, de witte lijst voor buiten, het bronfilter en het plafond voor
/// verbindingen die niets bewijzen.
///
/// Stap 5 van "verbinden zoals Roon ARC" (14-10-2026). Over echte sockets op loopback, met een client
/// die het certificaat van de pc vastpint.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/certificaat.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tls_ingang.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

final _cert = PcCertificaat.maak();

/// Eén verzoek. [pin] = vastpinnen op dat certificaat (TLS); null = gewone HTTP.
Future<({int status, String lijf, HttpHeaders? koppen})> _vraag(
  int poort,
  String pad, {
  String? pin,
  String? sleutel,
  String methode = 'GET',
  Object? json,
}) async {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = const Duration(seconds: 5)
    ..badCertificateCallback = (cert, host, port) => pin != null && pinVan(cert.der) == pin;
  try {
    final url = Uri.parse('${pin == null ? 'http' : 'https'}://127.0.0.1:$poort$pad');
    final req = await client.openUrl(methode, url);
    if (sleutel != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sleutel');
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    }
    final res = await req.close();
    final lijf = await utf8.decoder.bind(res).join();
    return (status: res.statusCode, lijf: lijf, koppen: res.headers);
  } on HandshakeException {
    return (status: -1, lijf: 'handdruk geweigerd', koppen: null);
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Directory scratch, pcRoot;
  late LanServer server;
  late GrantStore grants;
  late int http, thuis, buiten;
  const gedeeld = 'de-gedeelde-sleutel-van-deze-pc';

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_ingang_');
    setAppDirForTest(scratch.path);
    pcRoot = Directory.systemTemp.createTempSync('dm_ingang_pc_');
    final map = Directory('${pcRoot.path}/Portishead/Dummy')..createSync(recursive: true);
    final f = File('${map.path}/01.flac')..writeAsBytesSync(List<int>.filled(4096, 7));
    final lib = LibraryStore()..tracks.add(Track(path: f.path, title: 'Mysterons', artist: 'Portishead', album: 'Dummy'));
    lib.albums = [Album('Dummy', 'Portishead', lib.tracks.toList())];
    grants = GrantStore(file: File('${scratch.path}/grants.json'));
    server = LanServer(
      library: lib,
      token: gedeeld,
      state: LanStateStore(File('${pcRoot.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      settings: AppSettings()..serverId = 'pc-saber-0001',
      certificaat: _cert,
      tlsPoort: 0,
      publiekPoort: 0,
      grants: grants,
    );
    expect(await server.start(), isNull);
    http = server.boundPort;
    thuis = server.tlsBoundPort!;
    buiten = server.publiekBoundPort!;
  });

  tearDown(() async {
    await server.dispose();
    for (final m in [pcRoot, scratch]) {
      try {
        m.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  ({String http, String tls}) toestel([String id = 'gsm-van-saber-01']) {
    final g = grants.nieuweSleutel(deviceId: id, deviceName: 'S26', metTls: true);
    return (http: g.token, tls: g.tlsToken!);
  }

  group('welke sleutel waar', () {
    test('47822: de TLS-sleutel in de kop; een HTTP-sleutel, de gedeelde en ?token= niet', () async {
      final s = toestel();
      expect((await _vraag(thuis, '/api/catalog', pin: _cert.pin, sleutel: s.tls)).status, 200);
      expect((await _vraag(thuis, '/api/catalog', pin: _cert.pin, sleutel: s.http)).status, 401);
      expect((await _vraag(thuis, '/api/catalog', pin: _cert.pin, sleutel: gedeeld)).status, 401);
      expect((await _vraag(thuis, '/api/catalog?token=${s.tls}', pin: _cert.pin)).status, 401,
          reason: 'een sleutel in het adres belandt in logboeken');
    });

    test('47820: de HTTP-sleutel zoals altijd; een TLS-sleutel wordt geweigerd, ingetrokken en rood gemeld', () async {
      final s = toestel();
      expect((await _vraag(http, '/api/catalog', sleutel: s.http)).status, 200);
      expect((await _vraag(http, '/api/catalog', sleutel: gedeeld)).status, 200, reason: 'de cast-URLs gebruiken hem');
      expect((await _vraag(http, '/api/catalog', sleutel: s.tls)).status, 401);
      expect(server.rodeMelding.value, contains('onversleuteld'));
      expect((await _vraag(thuis, '/api/catalog', pin: _cert.pin, sleutel: s.tls)).status, 401,
          reason: 'hij reisde onversleuteld: ook versleuteld geldt hij niet meer');
      expect((await _vraag(http, '/api/catalog', sleutel: s.http)).status, 200, reason: 'de HTTP-sleutel blijft');
    });

    test('een ander certificaat: geen handdruk, dus ook geen sleutel over de lijn', () async {
      final s = toestel();
      final r = await _vraag(thuis, '/api/catalog', pin: 'b' * 64, sleutel: s.tls);
      expect(r.status, -1);
    });
  });

  group('de ruil', () {
    test('één keer, alleen op 47822, met de huidige sleutel van een echt toestel', () async {
      final g = grants.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26');
      final r = await _vraag(thuis, '/api/sleutel/ruil', pin: _cert.pin, methode: 'POST', json: {'sleutel': g.token});
      expect(r.status, 200);
      final tls = (jsonDecode(r.lijf) as Map)['tlsToken'] as String;
      final melding = grants.nieuweSleutelMelding.value;
      expect(melding?.via, 'ruil', reason: 'ook een ruil is een nieuwe sleutel: melding op de pc');
      expect(melding?.sleutel, tls, reason: '[Intrekken] trekt precies deze sleutel in');
      expect(melding?.tekst, startsWith("'S26' gebruikt nu een versleutelde verbinding"));
      expect((await _vraag(thuis, '/api/catalog', pin: _cert.pin, sleutel: tls)).status, 200);
      expect((await _vraag(http, '/api/catalog', sleutel: g.token)).status, 200, reason: 'de HTTP-sleutel blijft op 47820');
      // Opnieuw: 409 en rood op de pc.
      final nog = await _vraag(thuis, '/api/sleutel/ruil', pin: _cert.pin, methode: 'POST', json: {'sleutel': g.token});
      expect(nog.status, 409);
      expect(server.rodeMelding.value, contains('omgeruild'));
      // Niet met de gedeelde sleutel.
      expect((await _vraag(thuis, '/api/sleutel/ruil', pin: _cert.pin, methode: 'POST', json: {'sleutel': gedeeld})).status, 403);
      // Niet op 47820 (daar bestaat de weg niet) en niet van buiten.
      expect((await _vraag(http, '/api/sleutel/ruil', sleutel: g.token, methode: 'POST', json: {'sleutel': g.token})).status, 404);
      expect((await _vraag(buiten, '/api/sleutel/ruil', pin: _cert.pin, methode: 'POST', json: {'sleutel': g.token})).status, 403);
    });

    test('koppelen met de code over 47822 geeft beide sleutels; over 47820 alleen de HTTP-sleutel', () async {
      final code1 = server.pairing.start();
      final r1 = await _vraag(thuis, '/pair', pin: _cert.pin, methode: 'POST', json: {'code': code1, 'deviceId': 'ipad-van-saber-01', 'deviceName': 'iPad'});
      expect(r1.status, 200);
      final m1 = jsonDecode(r1.lijf) as Map;
      expect(m1['token'], isNotEmpty);
      expect(grants.acceptsTls(m1['tlsToken'] as String), isTrue);
      final code2 = server.pairing.start();
      final r2 = await _vraag(http, '/pair', methode: 'POST', json: {'code': code2, 'deviceId': 'mac-van-saber-001', 'deviceName': 'Mac'});
      expect(r2.status, 200);
      expect((jsonDecode(r2.lijf) as Map).containsKey('tlsToken'), isFalse, reason: 'een TLS-sleutel reist nooit over HTTP');
    });
  });

  group('van buiten (47821)', () {
    test('/health zonder naam, versie of aantallen', () async {
      final r = await _vraag(buiten, '/health', pin: _cert.pin);
      expect(r.status, 200);
      final m = jsonDecode(r.lijf) as Map;
      expect(m['serverId'], 'pc-saber-0001');
      for (final k in ['name', 'version', 'deviceName', 'trackCount', 'albumCount']) {
        expect(m.containsKey(k), isFalse, reason: '$k hoort niet op een poort die het internet ziet');
      }
    });

    test('de witte lijst: catalogus en stroom wel, zoeken, koppelen, starten en bijwerken niet', () async {
      final s = toestel();
      expect((await _vraag(buiten, '/api/catalog', pin: _cert.pin, sleutel: s.tls)).status, 200);
      final zoek = await _vraag(buiten, '/api/search?q=x', pin: _cert.pin, sleutel: s.tls);
      expect(zoek.status, 403);
      expect((jsonDecode(zoek.lijf) as Map)['error'], 'Dit kan alleen thuis of via Tailscale.');
      expect((await _vraag(buiten, '/api/library/tracks', pin: _cert.pin, sleutel: s.tls)).status, 403);
      expect((await _vraag(buiten, '/api/events', pin: _cert.pin, sleutel: s.tls)).status, 403);
      expect((await _vraag(buiten, '/pair', pin: _cert.pin, methode: 'POST', json: {'code': '123456'})).status, 403);
      final ru = await _vraag(buiten, '/api/rutracker/sessie', pin: _cert.pin, sleutel: s.tls);
      expect((jsonDecode(ru.lijf) as Map)['error'], 'Kan alleen met je gsm thuis op wifi.');
      expect((await _vraag(buiten, '/api/update', pin: _cert.pin, sleutel: s.tls, methode: 'POST', json: {'op': 'start'})).status, 403);
      expect((await _vraag(buiten, '/api/cast/control', pin: _cert.pin, sleutel: s.tls, methode: 'POST', json: {'deviceId': 'x', 'action': 'play'})).status, 403);
      expect((await _vraag(buiten, '/api/cast/play', pin: _cert.pin, sleutel: s.tls, methode: 'POST', json: {})).status, 403);
    });

    test('geen sleutel of een HTTP-sleutel: 401; geen CORS op de versleutelde ingangen', () async {
      final s = toestel();
      expect((await _vraag(buiten, '/api/catalog', pin: _cert.pin)).status, 401);
      expect((await _vraag(buiten, '/api/catalog', pin: _cert.pin, sleutel: s.http)).status, 401);
      final b = await _vraag(buiten, '/api/catalog', pin: _cert.pin, sleutel: s.tls);
      expect(b.koppen!.value('access-control-allow-origin'), isNull);
      final h = await _vraag(http, '/api/catalog', sleutel: s.http);
      expect(h.koppen!.value('access-control-allow-origin'), '*');
    });

    test('de witte lijst zelf, als regel', () {
      expect(weigerVanBuiten('/stream/abc.flac', 'GET'), isNull);
      expect(weigerVanBuiten('/api/online/search', 'POST'), isNull);
      expect(weigerVanBuiten('/api/nieuw-morgen', 'GET'), isNotNull, reason: 'wat er morgen bij komt, kan van buiten niet');
      expect(weigerVanBuiten('/api/diag/warmte', 'POST'), isNotNull);
    });
  });

  test('het bronfilter: van buiten niets op 47820 en 47822, 47821 blijft open', () async {
    final s = toestel();
    server.bronMagThuisVoorToets = (_) => false; // elke bron telt nu als "buiten"
    final h = await _vraag(http, '/api/catalog', sleutel: s.http);
    expect(h.status, 403);
    expect((jsonDecode(h.lijf) as Map)['error'], 'Dit kan alleen thuis of via Tailscale.');
    expect((await _vraag(thuis, '/api/catalog', pin: _cert.pin, sleutel: s.tls)).status, 403);
    expect((await _vraag(buiten, '/api/catalog', pin: _cert.pin, sleutel: s.tls)).status, 200);
    expect(magOpThuisingang(InternetAddress('100.97.1.2')), isTrue, reason: 'Tailscale');
    expect(magOpThuisingang(InternetAddress('192.168.0.20')), isTrue);
    expect(magOpThuisingang(InternetAddress('203.0.113.9')), isFalse);
  });

  test('het slot tegen een tweede kopie zit niet op een poort van de pc', () {
    // Tot 3.9.480 hield de app 127.0.0.1:47821 vast — de poort van de deur naar buiten (gezien 14-10-2026).
    final m = RegExp(r'const _instancePort = (\d+);').firstMatch(File('lib/main.dart').readAsStringSync());
    expect(m, isNotNull, reason: '_instancePort is hernoemd of verdwenen');
    final slot = int.parse(m!.group(1)!);
    expect([kLanPort, kTlsPoort, kPubliekPoort], isNot(contains(slot)));
    expect(slot >= 47980 && slot <= 47990, isFalse, reason: 'die poorten houdt Windows vast');
  });

  test('/api/uitwijk geeft de pin en de versleutelde poort mee', () async {
    final s = toestel();
    final r = await _vraag(http, '/api/uitwijk', sleutel: s.http);
    final m = jsonDecode(r.lijf) as Map;
    expect(m['pin'], _cert.pin);
    expect(m['tlsPoort'], thuis);
  });

  test('handdruk gedaan en dan zwijgen (of alleen 401 halen): na de klok gaat de verbinding dicht', () async {
    final ingang = await TlsIngang.bind(InternetAddress.loopbackIPv4, 0, _cert.context(),
        handdruk: const Duration(milliseconds: 300), eersteVerzoek: const Duration(milliseconds: 300));
    final srv = HttpServer.listenOn(ingang);
    addTearDown(() => srv.close(force: true));
    // Deze server noemt nooit iets geldig: elk verzoek is een 401.
    srv.listen((req) async {
      req.response.statusCode = 401;
      await req.response.close();
    });
    final zwijger = await SecureSocket.connect(InternetAddress.loopbackIPv4, ingang.port,
        onBadCertificate: (c) => pinVan(c.der) == _cert.pin);
    final dicht = Completer<void>();
    zwijger.listen((_) {}, onDone: () => dicht.complete(), onError: (_) => dicht.complete());
    expect(ingang.wachtend, 1);
    // Ook wie keurig blijft vragen zonder sleutel, krijgt geen eeuwige plek.
    zwijger.write('GET /x HTTP/1.1\r\nHost: x\r\n\r\n');
    await dicht.future.timeout(const Duration(seconds: 3), onTimeout: () => fail('de verbinding bleef open'));
    expect(ingang.wachtend, 0);
    zwijger.destroy();
  });

  test('200 stille verbindingen: een lopende stroom gaat door, de stille vliegen eruit', () async {
    final ingang = await TlsIngang.bind(InternetAddress.loopbackIPv4, 0, _cert.context(),
        handdruk: const Duration(milliseconds: 400), eersteVerzoek: const Duration(milliseconds: 400));
    final srv = HttpServer.listenOn(ingang);
    addTearDown(() => srv.close(force: true));
    srv.listen((req) async {
      ingang.geldig(req.connectionInfo);
      req.response.contentLength = 40 * 16384;
      for (var i = 0; i < 40; i++) {
        req.response.add(List<int>.filled(16384, i));
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await req.response.close();
    });
    final stroom = _vraag(ingang.port, '/stroom', pin: _cert.pin);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final stil = <Socket>[];
    for (var i = 0; i < 200; i++) {
      stil.add(await Socket.connect(InternetAddress.loopbackIPv4, ingang.port));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(ingang.wachtend, lessThanOrEqualTo(64));
    expect(ingang.geweigerd, greaterThanOrEqualTo(136));
    final r = await stroom;
    expect(r.status, 200);
    expect(r.lijf.length, 40 * 16384, reason: 'de lopende stroom kwam helemaal aan');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(ingang.wachtend, 0, reason: 'wie niets zegt, vliegt er na de klok uit');
    for (final s in stil) {
      s.destroy();
    }
    // En daarna komt een nieuw toestel gewoon weer binnen.
    final weer = await _vraag(ingang.port, '/weer', pin: _cert.pin);
    expect(weer.status, 200);
  });
}
