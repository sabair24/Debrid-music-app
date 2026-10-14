/// Stap 8.1 van "verbinden zoals Roon ARC" (14-10-2026): een toestel met een TLS-sleutel en de pin
/// praat vanzelf versleuteld met zijn pc, en speelt via de doorgever. Over een echte pc-server op
/// loopback, met een echte sessie, van de wedloop tot de bytes die mpv krijgt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
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

void main() {
  late Directory scratch, pcRoot;
  late File bestand;
  final servers = <LanServer>[];

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_versl_');
    setAppDirForTest(scratch.path);
    pcRoot = Directory.systemTemp.createTempSync('dm_versl_pc_');
  });

  tearDown(() async {
    for (final s in servers) {
      await s.dispose();
    }
    servers.clear();
    for (final m in [pcRoot, scratch]) {
      try {
        m.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  /// Een pc met één nummer. [versleuteld] onwaar = de noodrem staat aan: geen 47822.
  Future<({LanServer server, GrantStore grants})> pc({bool versleuteld = true}) async {
    final map = Directory('${pcRoot.path}/Portishead/Dummy')..createSync(recursive: true);
    bestand = File('${map.path}/01 Mysterons.flac')
      ..writeAsBytesSync(List<int>.generate(200 * 1024, (i) => (i * 13) % 256));
    final lib = LibraryStore()..rootPath = pcRoot.path;
    lib.tracks.add(Track(path: bestand.path, title: 'Mysterons', artist: 'Portishead', album: 'Dummy', isFlac: true));
    lib.rebuildAlbums();
    final grants = GrantStore(file: File('${scratch.path}/grants.json'));
    final s = LanServer(
      library: lib,
      token: 'gedeelde-sleutel',
      state: LanStateStore(File('${pcRoot.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      settings: AppSettings()..serverId = 'pc-saber-0001',
      certificaat: versleuteld ? proefCertificaat : null,
      tlsPoort: 0,
      grants: grants,
    );
    expect(await s.start(), isNull);
    servers.add(s);
    return (server: s, grants: grants);
  }

  ({ClientSession sessie, String Function(String) Function() resolver}) sessie() {
    String Function(String)? r;
    final s = ClientSession(
      library: LibraryStore(),
      settings: AppSettings(),
      owner: false,
      applyMediaResolver: (f) => r = f,
      zoekOpNetwerk: () async => const [],
    );
    addTearDown(s.dispose);
    return (sessie: s, resolver: () => r!);
  }

  Future<List<int>> haal(String url) async {
    final c = HttpClient();
    try {
      final res = await (await c.getUrl(Uri.parse(url))).close();
      expect(res.statusCode, 200, reason: url);
      return await res.fold<List<int>>([], (a, b) => a..addAll(b));
    } finally {
      c.close(force: true);
    }
  }

  test('met TLS-sleutel en pin: de wedloop kiest 47822, de catalogus komt versleuteld, mpv speelt via de doorgever', () async {
    final p = await pc();
    final g = p.grants.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26', metTls: true);
    final s = sessie();
    await s.sessie.connect(
      RemoteEndpoint(
        baseUrl: Uri.parse('http://127.0.0.1:${p.server.boundPort}'),
        token: g.token,
        serverId: 'pc-saber-0001',
        pin: proefCertificaat.pin,
        tlsToken: g.tlsToken!,
        tlsPoort: p.server.tlsBoundPort!,
      ),
      remember: false,
    );
    final e = s.sessie.endpoint!;
    expect(e.versleuteld, isTrue, reason: 'versleuteld gaat voor, ook al antwoordt 47820 ook');
    expect(e.baseUrl.port, p.server.tlsBoundPort);
    expect(s.sessie.library.tracks, hasLength(1), reason: 'de catalogus kwam over de versleutelde ingang');

    final pad = s.sessie.library.tracks.single.path;
    final mpv = s.resolver()(pad);
    final u = Uri.parse(mpv);
    expect(u.host, '127.0.0.1');
    expect(u.port, s.sessie.doorgever!.poort);
    expect(u.queryParameters.containsKey('token'), isFalse, reason: 'geen sleutel in het adres voor mpv');
    expect(mpv, isNot(contains(g.token)));
    expect(mpv, isNot(contains(g.tlsToken!)));
    expect(await haal(mpv), bestand.readAsBytesSync());
    expect(p.server.rodeMelding.value, isNull, reason: 'de TLS-sleutel kwam nooit op 47820');
    expect(p.grants.grantFor(g.tlsToken!)?.lastSeenVia, isNot('buiten'));
  });

  test('de noodrem op de pc (geen 47822): het toestel valt terug op 47820 met zijn HTTP-sleutel', () async {
    final p = await pc(versleuteld: false);
    final g = p.grants.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26', metTls: true);
    final dicht = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final dichtePoort = dicht.port;
    await dicht.close();
    final s = sessie();
    await s.sessie.connect(
      RemoteEndpoint(
        baseUrl: Uri.parse('http://127.0.0.1:${p.server.boundPort}'),
        token: g.token,
        serverId: 'pc-saber-0001',
        pin: proefCertificaat.pin,
        tlsToken: g.tlsToken!,
        tlsPoort: dichtePoort,
      ),
      remember: false,
    );
    final e = s.sessie.endpoint!;
    expect(e.versleuteld, isFalse);
    expect(e.baseUrl.port, p.server.boundPort);
    expect(s.sessie.library.tracks, hasLength(1));
    final mpv = s.resolver()(s.sessie.library.tracks.single.path);
    expect(Uri.parse(mpv).port, p.server.boundPort, reason: 'rechtstreeks op 47820, zoals vóór uitlevering B');
    expect(await haal(mpv), bestand.readAsBytesSync());
  });

  test('zonder TLS-sleutel (nog niet geruild): alles zoals vóór uitlevering B', () async {
    final p = await pc();
    final g = p.grants.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26');
    final s = sessie();
    await s.sessie.connect(
      RemoteEndpoint(
        baseUrl: Uri.parse('http://127.0.0.1:${p.server.boundPort}'),
        token: g.token,
        serverId: 'pc-saber-0001',
        pin: proefCertificaat.pin,
        tlsPoort: p.server.tlsBoundPort!,
      ),
      remember: false,
    );
    expect(s.sessie.endpoint!.versleuteld, isFalse);
    expect(s.sessie.doorgever, isNull, reason: 'geen isolate voor niets');
  });

  test('de eigen deur naar buiten gaat mee in /api/uitwijk, alleen als hij open is, en de gsm onthoudt hem', () async {
    final p = await pc();
    final g = p.grants.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26', metTls: true);
    // Een tweede pc-server met een buitenadres: de deur staat open.
    Uri? deur;
    final s = LanServer(
      library: p.server.library,
      token: 'gedeelde-sleutel',
      state: LanStateStore(File('${pcRoot.path}/state2.json')),
      pairing: PairingStore(),
      port: 0,
      settings: AppSettings()..serverId = 'pc-saber-0001',
      certificaat: proefCertificaat,
      tlsPoort: 0,
      grants: p.grants,
      buitenAdres: () => deur,
    );
    expect(await s.start(), isNull);
    servers.add(s);
    final e = RemoteEndpoint(
      baseUrl: Uri.parse('https://127.0.0.1:${s.tlsBoundPort}'),
      token: g.token,
      serverId: 'pc-saber-0001',
      pin: proefCertificaat.pin,
      tlsToken: g.tlsToken!,
      tlsPoort: s.tlsBoundPort!,
    );
    final c = RemoteClient(e);
    addTearDown(c.close);
    expect((await c.uitwijk()).urls.where((u) => u.startsWith('https://')), isEmpty, reason: 'dicht: niets');
    deur = Uri.parse('https://81.82.83.84:47821');
    expect((await c.uitwijk()).urls, contains('https://81.82.83.84:47821'));
  });

  test('een versleuteld adres zonder pin: geen enkel certificaat wordt aanvaard', () async {
    final p = await pc();
    final h = await RemoteClient.health(Uri.parse('https://127.0.0.1:${p.server.tlsBoundPort}'));
    expect(h, isNull, reason: 'zonder pin nooit "dan maar elk certificaat"');
    final met = await RemoteClient.health(Uri.parse('https://127.0.0.1:${p.server.tlsBoundPort}'), pin: proefCertificaat.pin);
    expect(met?.serverId, 'pc-saber-0001');
  });
}
