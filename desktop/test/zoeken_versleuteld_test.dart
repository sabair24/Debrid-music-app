/// Zoeken en downloaden vanaf een gekoppeld toestel over de versleutelde weg (47822 thuis, 47821 van
/// buiten). Gemeld op 15-10-2026: "kan niets meer downloaden!!!! soulseek? torrent??" — de downloaddienst
/// op de gsm (`remote_services.dart`) had een eigen gewone client met de HTTP-sleutel, en die vertrouwde
/// het certificaat van de pc niet. Afspelen werkte (de doorgever), zoeken en downloaden niet.
///
/// De pc in deze toets kan zelf niet zoeken (geen TorBox, geen Soulseek): dan antwoordt hij met zijn
/// eigen zin. Die zin terugkrijgen bewijst dat het verzoek bij hem aankwam, versleuteld en met de juiste
/// sleutel — een handdrukfout of een 401 zou iets anders zeggen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/remote_services.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

import 'hulp_tls.dart';

void main() {
  late Directory scratch;
  late LanServer server;
  late DeviceGrant g;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_zoekversl_');
    setAppDirForTest(scratch.path);
    final grants = GrantStore(file: File('${scratch.path}/grants.json'));
    server = LanServer(
      library: LibraryStore(),
      token: 'gedeelde-sleutel',
      state: LanStateStore(File('${scratch.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      settings: AppSettings()..serverId = 'pc-saber-0001',
      certificaat: proefCertificaat,
      tlsPoort: 0,
      publiekPoort: 0,
      grants: grants,
    );
    expect(await server.start(), isNull);
    g = grants.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26', metTls: true);
  });

  tearDown(() async {
    await server.dispose();
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  RemoteEndpoint op(String schema, int poort) => RemoteEndpoint(
        baseUrl: Uri.parse('$schema://127.0.0.1:$poort'),
        token: g.token,
        serverId: 'pc-saber-0001',
        pin: proefCertificaat.pin,
        tlsToken: g.tlsToken!,
        tlsPoort: server.tlsBoundPort!,
      );

  Future<RemoteException> zoekFout(Future<Object?> Function() zoek) async {
    try {
      await zoek();
    } on RemoteException catch (e) {
      return e;
    }
    fail('de pc had moeten zeggen dat hij niet kan zoeken');
  }

  for (final (naam, schema, poort) in [
    ('thuis versleuteld (47822)', 'https', () => server.tlsBoundPort!),
    ('van buiten (47821)', 'https', () => server.publiekBoundPort!),
    ('de gewone weg (47820)', 'http', () => server.boundPort),
  ]) {
    test('$naam: torrent zoeken komt aan bij de pc, met de juiste sleutel', () async {
      final e = op(schema, poort());
      final online = RemoteOnlineService(AppSettings(), () => e);
      addTearDown(online.dispose);
      final f = await zoekFout(() => online.search('portishead'));
      expect(f.statusCode, 503, reason: 'het antwoord van de pc zelf, geen 401 en geen handdrukfout');
      expect(f.message, 'Deze pc kan niet online zoeken.');
    });

    test('$naam: Soulseek zoeken komt aan bij de pc', () async {
      final e = op(schema, poort());
      final slsk = RemoteSoulseekService(AppSettings(), () => e);
      addTearDown(slsk.dispose);
      final f = await zoekFout(() => slsk.search('portishead'));
      expect(f.statusCode, 503);
    });
  }

  test('van gewoon naar versleuteld wisselen: dezelfde dienst praat daarna versleuteld verder', () async {
    var e = op('http', server.boundPort);
    final online = RemoteOnlineService(AppSettings(), () => e);
    addTearDown(online.dispose);
    expect((await zoekFout(() => online.search('x'))).statusCode, 503);
    e = op('https', server.tlsBoundPort!);
    expect((await zoekFout(() => online.search('x'))).statusCode, 503,
        reason: 'de client volgt de verbinding van nu, niet die van toen hij gemaakt werd');
  });
}
