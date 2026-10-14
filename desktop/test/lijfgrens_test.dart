import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hulp_tls.dart';

/// Een verzoek kan de pc niet meer laten bufferen tot het geheugen vol is.
///
/// Elke route las het lijf onbegrensd in, ook `/pair` en `/pair-cloud`, die zonder sleutel open
/// staan. Stap 2.4 van "verbinden zoals Roon ARC" (14-10-2026).
void main() {
  late Directory map;
  late LanServer server;
  late PairingStore pairing;
  var googleGevraagd = 0;

  setUp(() async {
    map = Directory.systemTemp.createTempSync('dm_lijf_');
    pairing = PairingStore();
    googleGevraagd = 0;
    server = LanServer(
      library: LibraryStore()..rootPath = map.path,
      token: 'gedeelde-sleutel',
      state: LanStateStore(File('${map.path}/state.json')),
      pairing: pairing,
      grants: GrantStore(file: File('${map.path}/grants.json')),
      port: 0,
      settings: AppSettings(),
      cloudUid: () => 'uid',
      uidVanSleutel: (s) async {
        googleGevraagd++;
        return 'uid';
      },
      certificaat: proefCertificaat,
      tlsPoort: 0,
    )
      ..lijfZonderSleutel = 4 * 1024
      ..lijfMetSleutel = 64 * 1024;
    expect(await server.start(), isNull);
  });

  tearDown(() async {
    await server.dispose();
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  Uri adres(String pad, {bool tls = false}) => tls
      ? Uri.parse('https://127.0.0.1:${server.tlsBoundPort}$pad')
      : Uri.parse('http://127.0.0.1:${server.boundPort}$pad');

  /// Een verzoek met [lengte] bytes, met of zonder Content-Length (dan in stukken).
  Future<int> stuur(String pad, int lengte, {bool metLengte = true, String? sleutel, bool tls = false}) async {
    final http = tls ? pinHttpClient() : HttpClient();
    try {
      final req = await http.postUrl(adres(pad, tls: tls));
      if (sleutel != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sleutel');
      req.headers.contentType = ContentType.json;
      final lijf = utf8.encode('{"code":"${'1' * (lengte - 11)}"}');
      if (metLengte) {
        req.contentLength = lijf.length;
      } else {
        req.bufferOutput = false;
      }
      try {
        // In stukken, zoals een upload zonder lengte binnenkomt.
        for (var i = 0; i < lijf.length; i += 8192) {
          req.add(lijf.sublist(i, i + 8192 > lijf.length ? lijf.length : i + 8192));
        }
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      } on SocketException {
        // De pc sloot de verbinding na zijn 413 terwijl wij nog schreven. Dat is het antwoord.
        return HttpStatus.requestEntityTooLarge;
      } on HttpException {
        return HttpStatus.requestEntityTooLarge;
      }
    } finally {
      http.close(force: true);
    }
  }

  test('zonder sleutel: een te groot lijf naar /pair krijgt 413 en verbruikt de code niet', () async {
    final code = pairing.start();
    expect(await stuur('/pair', 5000), 413);
    expect(pairing.code, code, reason: 'een te groot verzoek is geen poging');
  });

  test('zonder sleutel: /pair-cloud weigert een te groot lijf vóór er iets aan Google gevraagd wordt', () async {
    // Versleuteld (47822): over 47820 bestaat koppelen via het account niet meer.
    expect(await stuur('/pair-cloud', 5000, tls: true), 413);
    expect(await stuur('/pair-cloud', 9000, metLengte: false, tls: true), 413);
    expect(googleGevraagd, 0);
    expect(await stuur('/pair-cloud', 100), 410, reason: 'een inlogsleutel gaat nooit meer onversleuteld');
  });

  test('een lijf zonder lengte wordt tijdens het lezen afgebroken', () async {
    expect(await stuur('/pair', 20000, metLengte: false), 413);
  });

  test('een opgegeven lengte boven de grens: meteen nee, zonder op het lijf te wachten', () async {
    // Zegt het verzoek "er komen 10 MB", en komt er niets: de pc wacht er niet op.
    final sok = await Socket.connect('127.0.0.1', server.boundPort);
    try {
      sok.write('POST /pair HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n'
          'Content-Length: 10485760\r\n\r\n{"code":');
      await sok.flush();
      final antwoord = await sok
          .cast<List<int>>()
          .transform(utf8.decoder)
          .firstWhere((t) => t.contains('HTTP/1.1'))
          .timeout(const Duration(seconds: 3));
      expect(antwoord, contains('413'));
    } finally {
      sok.destroy();
    }
  });

  test('met sleutel: een gewoon lijf gaat door, een te groot krijgt 413', () async {
    expect(await stuur('/api/state/ops', 2000, sleutel: 'gedeelde-sleutel'), 200);
    expect(await stuur('/api/state/ops', 70 * 1024, sleutel: 'gedeelde-sleutel'), 413);
    expect(await stuur('/api/move/plan', 70 * 1024, sleutel: 'gedeelde-sleutel', metLengte: false), 413);
  });

  test('de grenzen in de app zelf', () {
    expect(LanServer.kLijfZonderSleutel, 4 * 1024);
    expect(LanServer.kLijfMetSleutel, 8 * 1024 * 1024);
    final bron = File('lib/lan/server.dart').readAsStringSync();
    final code = bron.split('\n').where((r) => !r.trimLeft().startsWith('//')).join('\n');
    expect(code, isNot(contains('utf8.decoder.bind(req)')), reason: 'geen enkele route leest nog onbegrensd');
  });
}
