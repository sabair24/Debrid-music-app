/// De toestelkant van stap 5: de pin leren, één keer vanzelf ruilen, en koppelen via het account alleen
/// nog versleuteld.
///
/// Stap 5.5/5.6 van "verbinden zoals Roon ARC" (14-10-2026). Over echte sockets tegen een LanServer met
/// het proefcertificaat.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/client_mode.dart';
import 'package:debridmusic/lan/client_session.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

import 'hulp_tls.dart';

Future<int> _dichtePoort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

Future<void> _wachtTot(bool Function() klaar, {Duration max = const Duration(seconds: 15)}) async {
  final eind = DateTime.now().add(max);
  while (!klaar() && DateTime.now().isBefore(eind)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory scratch, pcRoot;
  late LanServer server;
  late GrantStore grants;
  late Uri http;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_vk_');
    setAppDirForTest(scratch.path);
    pcRoot = Directory.systemTemp.createTempSync('dm_vk_pc_');
    final map = Directory('${pcRoot.path}/Portishead/Dummy')..createSync(recursive: true);
    final f = File('${map.path}/01.flac')..writeAsBytesSync(List<int>.filled(2048, 1));
    final lib = LibraryStore()..tracks.add(Track(path: f.path, title: 'Mysterons', artist: 'Portishead', album: 'Dummy'));
    lib.albums = [Album('Dummy', 'Portishead', lib.tracks.toList())];
    grants = GrantStore(file: File('${pcRoot.path}/grants.json'));
    server = LanServer(
      library: lib,
      token: 'gedeelde-sleutel-van-de-pc',
      state: LanStateStore(File('${pcRoot.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      settings: AppSettings()..serverId = 'pc-saber-0001',
      cloudUid: () => 'uid-saber',
      uidVanSleutel: (s) async => s == 'inlog-van-saber' ? 'uid-saber' : 'uid-iemand-anders',
      certificaat: proefCertificaat,
      tlsPoort: 0,
      grants: grants,
    );
    expect(await server.start(), isNull);
    http = Uri.parse('http://127.0.0.1:${server.boundPort}');
  });

  tearDown(() async {
    await server.dispose();
    for (final m in [pcRoot, scratch]) {
      try {
        m.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<RemoteEndpoint?> koppelViaAccount({String pin = '', String verwacht = '', Uri? basis, int? tlsPoort}) =>
      RemoteClient.pairMetAccount(
        basis ?? http,
        idToken: 'inlog-van-saber',
        deviceId: 'gsm-van-saber-01',
        deviceName: 'S26',
        platform: 'android',
        pin: pin,
        verwachtePin: verwacht,
        tlsPoort: tlsPoort ?? server.tlsBoundPort!,
      );

  group('koppelen via het account', () {
    test('eerste kennismaking: beide sleutels, en de pin van DEZE pc vastgelegd', () async {
      final e = await koppelViaAccount();
      expect(e, isNotNull);
      expect(e!.baseUrl, http, reason: 'het gewone verkeer blijft voorlopig op 47820');
      expect(e.pin, proefCertificaat.pin);
      expect(e.tlsPoort, server.tlsBoundPort);
      expect(grants.accepts(e.token), isTrue);
      expect(grants.acceptsTls(e.tlsToken), isTrue);
    });

    test('met de pin uit je account: een pc met een ander certificaat valt af', () async {
      await expectLater(koppelViaAccount(verwacht: 'c' * 64),
          throwsA(isA<RemoteException>().having((x) => x.message, 'zin', contains('ander certificaat'))));
      expect(grants.all, isEmpty, reason: 'de inlogsleutel kwam nooit aan');
    });

    test('een bekende pin die niet klopt: geen verbinding, en geen terugval naar HTTP', () async {
      await expectLater(koppelViaAccount(pin: 'd' * 64), throwsA(isA<RemoteException>()));
      expect(grants.all, isEmpty);
    });

    test('een oude pc (geen 47822): een zin, en aantoonbaar geen inlogsleutel over 47820', () async {
      final gezien = <String>[];
      final oud = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => oud.close(force: true));
      oud.listen((req) async {
        gezien.add(req.uri.path);
        final lijf = await utf8.decoder.bind(req).join();
        if (lijf.contains('inlog-van-saber')) gezien.add('INLOGSLEUTEL');
        if (req.uri.path == '/health') {
          req.response.write(jsonEncode({'status': 'ok', 'name': 'oude-pc', 'version': '3.9.478'}));
        }
        await req.response.close();
      });
      await expectLater(
          koppelViaAccount(basis: Uri.parse('http://127.0.0.1:${oud.port}'), tlsPoort: await _dichtePoort()),
          throwsA(isA<RemoteException>().having((x) => x.message, 'zin', contains('oudere versie'))));
      expect(gezien, isNot(contains('/pair-cloud')));
      expect(gezien, isNot(contains('INLOGSLEUTEL')));
    });

    test('op een openbaar adres geen eerste kennismaking (dat komt pas met uitlevering C)', () async {
      final klok = Stopwatch()..start();
      expect(await koppelViaAccount(basis: Uri.parse('http://203.0.113.9:47820')), isNull);
      expect(klok.elapsed, lessThan(const Duration(seconds: 1)), reason: 'er ging niets over de lijn');
    });

    test('over 47820 bestaat koppelen via het account niet meer: 410 met een zin', () async {
      final c = HttpClient();
      try {
        final req = await c.postUrl(http.replace(path: '/pair-cloud'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'idToken': 'inlog-van-saber', 'deviceId': 'gsm-van-saber-01'}));
        final res = await req.close();
        final lijf = await utf8.decoder.bind(res).join();
        expect(res.statusCode, 410);
        expect(lijf, contains('Werk de app op dit toestel bij'));
      } finally {
        c.close(force: true);
      }
    });
  });

  group('de sessie', () {
    ClientSession sessie({Future<RemoteEndpoint?> Function(RemoteEndpoint)? verse}) => ClientSession(
          library: LibraryStore(),
          settings: AppSettings(),
          owner: false,
          applyMediaResolver: (_) {},
          zoekOpNetwerk: () async => const [],
          verseSleutel: verse,
        );

    Future<RemoteEndpoint> metCode(String id) =>
        RemoteClient.pair(http, server.pairing.start(), deviceName: 'iPad', deviceId: id);

    test('koppelen met de code, en dan vanzelf: pin geleerd, één keer geruild, bewaard', () async {
      final e = await metCode('ipad-van-saber-01');
      expect(e.tlsToken, isEmpty, reason: 'over 47820 komt er nooit een TLS-sleutel');
      final s = sessie();
      addTearDown(s.dispose);
      await s.connect(e);
      await _wachtTot(() => (s.endpoint?.tlsToken ?? '').isNotEmpty);
      final nu = s.endpoint!;
      expect(nu.pin, proefCertificaat.pin);
      expect(nu.tlsPoort, server.tlsBoundPort);
      expect(grants.acceptsTls(nu.tlsToken), isTrue);
      expect(grants.accepts(nu.token), isTrue, reason: 'de HTTP-sleutel blijft voor 47820');
      String? opSchijf;
      for (var i = 0; i < 100 && opSchijf != nu.tlsToken; i++) {
        opSchijf = (await loadPairedServer())?.tlsToken;
        if (opSchijf != nu.tlsToken) await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      expect(opSchijf, nu.tlsToken);
    });

    test('al geruild door een ander toestel (409): waarschuwing, en opnieuw koppelen via het account', () async {
      final e = await metCode('ipad-van-saber-01');
      expect(grants.ruil(e.token).status, 200, reason: 'iemand met de HTTP-sleutel was eerder');
      var opnieuw = 0;
      final s = sessie(verse: (huidig) async {
        opnieuw++;
        return null;
      });
      addTearDown(s.dispose);
      await s.connect(e);
      await _wachtTot(() => opnieuw > 0);
      expect(s.waarschuwing.value, contains('omgeruild'));
      expect(opnieuw, 1);
      expect(s.endpoint!.tlsToken, isEmpty);
    });

    test('een pc die opeens een ander certificaat noemt: waarschuwing, de oude pin blijft, geen ruil', () async {
      final e = await metCode('ipad-van-saber-01');
      final s = sessie();
      addTearDown(s.dispose);
      await s.connect(e.met(pin: 'e' * 64));
      await _wachtTot(() => s.waarschuwing.value != null);
      expect(s.waarschuwing.value, contains('ander certificaat'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(s.endpoint!.pin, 'e' * 64);
      expect(s.endpoint!.tlsToken, isEmpty);
      expect(grants.byDevice('ipad-van-saber-01')!.tlsToken, isNull, reason: 'er is niet geruild');
    });
  });
}
