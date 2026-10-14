import 'dart:io';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/toestellen_lijst.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stap 2.7 en 2.8 van "verbinden zoals Roon ARC" (14-10-2026): per toestel waar en wanneer het
/// binnenkwam, één toestel intrekken, en waarvoor de gedeelde sleutel nog gebruikt wordt.
const _gsm = '0123456789abcdef0123456789abcdef';

void main() {
  group('toestelWeg', () {
    test('elk soort adres', () {
      expect(toestelWeg(InternetAddress.loopbackIPv4), 'deze pc');
      expect(toestelWeg(InternetAddress('100.97.101.113')), 'Tailscale');
      expect(toestelWeg(InternetAddress('192.168.0.42')), 'thuis');
      expect(toestelWeg(InternetAddress('10.1.2.3')), 'thuis');
      expect(toestelWeg(InternetAddress('172.20.0.1')), 'thuis');
      expect(toestelWeg(InternetAddress('94.110.3.4')), 'buiten');
      expect(toestelWeg(InternetAddress('100.128.0.1')), 'buiten', reason: 'net buiten 100.64/10');
      expect(toestelWeg(InternetAddress('::ffff:192.168.0.42')), 'thuis');
      expect(toestelWeg(InternetAddress('fd7a:115c:a1e0::1')), 'Tailscale');
      expect(toestelWeg(InternetAddress('2a02:1810::1')), 'buiten');
    });
  });

  group('laatst gezien', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_gezien_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('een andere weg telt meteen, dezelfde weg binnen de minuut niet', () {
      final g = GrantStore(file: File('${map.path}/grants.json'));
      final s = g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      expect(g.touch(s, via: 'thuis'), isTrue);
      expect(g.touch(s, via: 'thuis'), isFalse, reason: 'elke stukje stroom hoort geen schrijfbeurt te zijn');
      expect(g.touch(s, via: 'Tailscale'), isTrue, reason: 'thuis de deur uit hoort meteen in de lijst');
      expect(g.all.single.lastSeenVia, 'Tailscale');
    });

    test('de weg overleeft opslaan en inlezen', () async {
      final g = GrantStore(file: File('${map.path}/grants.json'));
      final s = g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      g.touch(s, via: 'Tailscale');
      await g.save();
      final na = GrantStore(file: File('${map.path}/grants.json'));
      await na.load();
      expect(na.all.single.lastSeenVia, 'Tailscale');
    });

    test('de tekst in de lijst', () {
      final nu = DateTime(2026, 10, 14, 15);
      expect(laatstGezienTekst(DateTime(2026, 10, 14, 14, 2).millisecondsSinceEpoch, 'thuis', nu: nu),
          'laatst gezien 14:02, via thuis');
      expect(laatstGezienTekst(DateTime(2026, 10, 13, 22, 15).millisecondsSinceEpoch, null, nu: nu),
          'laatst gezien 13-10 22:15');
      expect(laatstGezienTekst(null, null, nu: nu), 'nog niet gezien');
    });
  });

  group('aan de server', () {
    late Directory map;
    late LanServer server;
    late GrantStore grants;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_gezien_srv_');
      grants = GrantStore(file: File('${map.path}/grants.json'));
      server = LanServer(
        library: LibraryStore()
          ..rootPath = map.path
          ..configDirOverride = map.path,
        token: 'gedeelde-sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        grants: grants,
        port: 0,
        settings: AppSettings(),
      );
      expect(await server.start(), isNull);
    });

    tearDown(() async {
      await server.dispose();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<int> haal(String pad, String sleutel) async {
      final http = HttpClient();
      try {
        final req = await http.getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}$pad'));
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sleutel');
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      } finally {
        http.close(force: true);
      }
    }

    test('een eigen sleutel: de lijst weet dat hij van deze pc kwam', () async {
      final s = grants.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      expect(await haal('/api/catalog', s), 200);
      expect(grants.all.single.lastSeenVia, 'deze pc');
      expect(grants.all.single.lastSeenAt, isNotNull);
    });

    test('de gedeelde sleutel komt in koppeling.log, één keer per pad en adres per uur', () async {
      expect(await haal('/api/catalog', 'gedeelde-sleutel'), 200);
      expect(await haal('/api/catalog', 'gedeelde-sleutel'), 200);
      expect(await haal('/api/state', 'gedeelde-sleutel'), 200);
      final log = File('${map.path}/koppeling.log').readAsStringSync();
      final regels = log.split('\n').where((r) => r.contains('GEDEELDE SLEUTEL')).toList();
      expect(regels, hasLength(2));
      expect(regels.first, contains('GET /api/catalog  van 127.0.0.1 (deze pc)'));
      expect(regels.last, contains('/api/state'));
    });

    test('een eigen sleutel komt niet als gedeelde in het logboek', () async {
      final s = grants.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      await haal('/api/catalog', s);
      final f = File('${map.path}/koppeling.log');
      final log = f.existsSync() ? f.readAsStringSync() : '';
      expect(log, isNot(contains('GEDEELDE SLEUTEL')));
    });
  });

}
