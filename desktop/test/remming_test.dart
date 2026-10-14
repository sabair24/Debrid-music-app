import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/accountkoppeling.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/remming.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stap 2.5 van "verbinden zoals Roon ARC" (14-10-2026): remmen op verkeerde sleutels en op
/// koppelen via het account, en nooit op een geldige sleutel.
String _jwt(Map<String, Object?> inhoud) {
  String deel(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${deel({'alg': 'RS256', 'typ': 'JWT'})}.${deel(inhoud)}.handtekening';
}

const _project = 'debridmusic-app';
final _straks = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
Map<String, Object?> _goed({String sub = 'uid-iemand'}) => {
      'aud': _project,
      'iss': 'https://securetoken.google.com/$_project',
      'exp': _straks,
      'sub': sub,
    };

void main() {
  group('Remming', () {
    test('drie keer mis is gratis, daarna verdubbelt het, tot tien seconden', () {
      var nu = DateTime(2026, 10, 14, 12);
      final r = Remming(klok: () => nu);
      final wachten = [for (var i = 0; i < 10; i++) r.naMislukt('1.2.3.4').inMilliseconds];
      expect(wachten, [0, 0, 0, 250, 500, 1000, 2000, 4000, 8000, 10000]);
    });

    test('per adres, en een geldige sleutel wist wat er stond', () {
      final r = Remming();
      for (var i = 0; i < 6; i++) {
        r.naMislukt('a');
      }
      expect(r.naMislukt('b'), Duration.zero, reason: 'een ander adres heeft er niets mee te maken');
      r.gelukt('a');
      expect(r.naMislukt('a'), Duration.zero);
    });

    test('na tien minuten telt een mislukte poging niet meer', () {
      var nu = DateTime(2026, 10, 14, 12);
      final r = Remming(klok: () => nu);
      for (var i = 0; i < 8; i++) {
        r.naMislukt('a');
      }
      nu = nu.add(const Duration(minutes: 11));
      expect(r.naMislukt('a'), Duration.zero);
    });

    test('begrensd geheugen: de oudste adressen vallen eruit', () {
      final r = Remming(maxAdressen: 100);
      for (var i = 0; i < 500; i++) {
        r.naMislukt('10.0.${i ~/ 256}.${i % 256}');
      }
      expect(r.aantalAdressen, 100);
    });
  });

  group('KoppelBudget', () {
    test('tien per minuut, en dan zegt hij vanaf wanneer weer', () {
      var nu = DateTime(2026, 10, 14, 12);
      final b = KoppelBudget(klok: () => nu);
      for (var i = 0; i < 10; i++) {
        expect(b.neem(), isNull);
      }
      expect(b.neem(), DateTime(2026, 10, 14, 12, 1));
      nu = nu.add(const Duration(minutes: 1));
      expect(b.neem(), isNull);
    });

    test('dertig per dag', () {
      var nu = DateTime(2026, 10, 14, 0);
      final b = KoppelBudget(klok: () => nu);
      for (var i = 0; i < 30; i++) {
        expect(b.neem(), isNull);
        nu = nu.add(const Duration(minutes: 2));
      }
      expect(b.neem(), DateTime(2026, 10, 15, 0));
    });
  });

  group('inlogsleutelFout: de eerste blik', () {
    test('een sleutel van dit project gaat door naar Google', () {
      expect(inlogsleutelFout(_jwt(_goed()), project: _project), isNull);
    });

    test('rommel, een ander project, een andere uitgever, verlopen of zonder account: nee', () {
      expect(inlogsleutelFout('zomaar-iets', project: _project), isNotNull);
      expect(inlogsleutelFout('a.b.c', project: _project), isNotNull);
      expect(inlogsleutelFout(_jwt({..._goed(), 'aud': 'ander-project'}), project: _project), contains('ander project'));
      expect(inlogsleutelFout(_jwt({..._goed(), 'iss': 'https://example.invalid/'}), project: _project),
          contains('uitgever'));
      expect(inlogsleutelFout(_jwt({..._goed(), 'exp': 1000}), project: _project), contains('verlopen'));
      expect(inlogsleutelFout(_jwt({..._goed(), 'sub': ''}), project: _project), contains('account'));
    });
  });

  group('aan de server', () {
    late Directory map;
    late LanServer server;
    var google = 0;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_remming_');
      google = 0;
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'gedeelde-sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        grants: GrantStore(file: File('${map.path}/grants.json')),
        port: 0,
        settings: AppSettings(),
        cloudUid: () => 'uid-saber',
        uidVanSleutel: (s) async {
          google++;
          return 'uid-iemand-anders';
        },
        firebaseProject: () => _project,
      );
      expect(await server.start(), isNull);
    });

    tearDown(() async {
      await server.dispose();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Uri adres(String pad) => Uri.parse('http://127.0.0.1:${server.boundPort}$pad');

    Future<int> haal(String sleutel) async {
      final http = HttpClient();
      try {
        final req = await http.getUrl(adres('/api/catalog'));
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sleutel');
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      } finally {
        http.close(force: true);
      }
    }

    Future<(int, String)> koppel(String idToken) async {
      final http = HttpClient();
      try {
        final req = await http.postUrl(adres('/pair-cloud'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'idToken': idToken, 'deviceId': '0123456789abcdef', 'deviceName': 'x'}));
        final res = await req.close();
        return (res.statusCode, await res.transform(utf8.decoder).join());
      } finally {
        http.close(force: true);
      }
    }

    test('verkeerde sleutels worden per adres onthouden, en een geldige wist dat', () async {
      for (var i = 0; i < 4; i++) {
        expect(await haal('fout-$i'), 401);
      }
      expect(server.remming.aantalAdressen, 1);
      expect(await haal('gedeelde-sleutel'), 200, reason: 'een geldige sleutel komt er altijd in');
      expect(server.remming.aantalAdressen, 0);
    });

    test('de zevende verkeerde sleutel op rij wacht echt', () async {
      for (var i = 0; i < 6; i++) {
        await haal('fout-$i');
      }
      final klok = Stopwatch()..start();
      expect(await haal('fout-7'), 401);
      expect(klok.elapsedMilliseconds, greaterThanOrEqualTo(1500), reason: 'verwacht 2 s');
    });

    test('een geweigerd verzoek met een aangekondigd lijf hangt niet', () async {
      final sok = await Socket.connect('127.0.0.1', server.boundPort);
      try {
        sok.write('POST /api/state/ops HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer fout\r\n'
            'Content-Length: 10485760\r\n\r\n{');
        await sok.flush();
        final antwoord = await sok
            .cast<List<int>>()
            .transform(utf8.decoder)
            .firstWhere((t) => t.contains('HTTP/1.1'))
            .timeout(const Duration(seconds: 3));
        expect(antwoord, contains('401'));
      } finally {
        sok.destroy();
      }
    });

    test('/pair-cloud: rommel kost geen opzoeking en geen budget', () async {
      final (status, lichaam) = await koppel('zomaar-iets');
      expect(status, 403);
      expect(lichaam, contains('klopt niet'));
      expect(google, 0);
      for (var i = 0; i < 20; i++) {
        await koppel(_jwt({..._goed(), 'aud': 'ander'}));
      }
      expect(google, 0);
      final (eerlijk, _) = await koppel(_jwt(_goed()));
      expect(eerlijk, 403, reason: 'naar Google, en die zegt: ander account');
      expect(google, 1);
    });

    test('/pair-cloud: na tien echte pogingen in een minuut 429, zonder nog Google te vragen', () async {
      for (var i = 0; i < 10; i++) {
        await koppel(_jwt(_goed()));
      }
      expect(google, 10);
      final (status, lichaam) = await koppel(_jwt(_goed()));
      expect(status, 429);
      expect(lichaam, contains('zes cijfers'));
      expect(google, 10);
    });
  });
}
