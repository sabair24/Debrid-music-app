/// De wedloop van `adreswedloop.dart` aan een echte sessie: de juiste pc wint, een andere pc op een
/// adres niet, en de id van de pc wordt bij de eerste verbinding geleerd.
///
/// Stap 4 van "verbinden zoals Roon ARC" (14-10-2026). Over een echte socket, zoals
/// `onderweg_ander_adres_test`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/client_mode.dart';
import 'package:debridmusic/lan/client_session.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

Future<int> _dichtePoort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final poort = s.port;
  await s.close();
  return poort;
}

Future<void> _wachtTot(bool Function() klaar, {Duration max = const Duration(seconds: 20)}) async {
  final eind = DateTime.now().add(max);
  while (!klaar() && DateTime.now().isBefore(eind)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late Directory scratch, pcRoot;
  final servers = <LanServer>[];

  Future<(LanServer, Uri)> pc(String serverId) async {
    final map = Directory('${pcRoot.path}/$serverId/Portishead/Dummy')..createSync(recursive: true);
    final f = File('${map.path}/01.flac')..writeAsBytesSync(List<int>.filled(2048, 0));
    final lib = LibraryStore()..tracks.add(Track(path: f.path, title: 'Mysterons', artist: 'Portishead', album: 'Dummy'));
    lib.albums = [Album('Dummy', 'Portishead', lib.tracks.toList())];
    final s = LanServer(
      library: lib,
      token: 'gedeelde-$serverId',
      state: LanStateStore(File('${pcRoot.path}/$serverId/state.json')),
      pairing: PairingStore(),
      port: 0,
      settings: AppSettings()..serverId = serverId,
    );
    expect(await s.start(), isNull);
    servers.add(s);
    return (s, Uri.parse('http://127.0.0.1:${s.boundPort}'));
  }

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_wedloop_');
    setAppDirForTest(scratch.path);
    pcRoot = Directory.systemTemp.createTempSync('dm_wedloop_pc_');
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

  ClientSession sessie(LibraryStore lib) => ClientSession(
        library: lib,
        settings: AppSettings(),
        owner: false,
        applyMediaResolver: (_) {},
        zoekOpNetwerk: () async => const [],
      );

  test('/health en het zoekantwoord zeggen welke pc dit is', () async {
    final (_, adres) = await pc('pc-saber-0001');
    final h = await RemoteClient.health(adres);
    expect(h?.serverId, 'pc-saber-0001');
  });

  test('de id wordt bij de eerste verbinding geleerd en bewaard', () async {
    final (_, adres) = await pc('pc-saber-0001');
    final lib = LibraryStore();
    final s = sessie(lib);
    addTearDown(s.dispose);
    await s.connect(RemoteEndpoint(baseUrl: adres, token: 'gedeelde-pc-saber-0001'));
    await _wachtTot(() => s.endpoint?.serverId.isNotEmpty ?? false);
    expect(s.endpoint?.serverId, 'pc-saber-0001');
    // Het wegschrijven loopt los van het verbinden; even laten landen.
    String? opSchijf;
    for (var i = 0; i < 100 && opSchijf != 'pc-saber-0001'; i++) {
      opSchijf = (await loadPairedServer())?.serverId;
      if (opSchijf != 'pc-saber-0001') await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(opSchijf, 'pc-saber-0001');
  });

  test('een andere pc op een uitwijkadres wint niet; de eigen pc wel', () async {
    final (_, vreemd) = await pc('pc-van-de-buren');
    final (_, eigen) = await pc('pc-saber-0001');
    final dood = Uri.parse('http://127.0.0.1:${await _dichtePoort()}');
    final lib = LibraryStore();
    final s = sessie(lib);
    addTearDown(s.dispose);
    // Thuisadres dood; als uitwijk eerst de buren (antwoordt sneller of even snel), dan de eigen pc.
    await s.connect(
      RemoteEndpoint(
        baseUrl: dood,
        token: 'gedeelde-pc-saber-0001',
        serverId: 'pc-saber-0001',
        uitwijk: [vreemd.toString(), eigen.toString()],
      ),
      remember: false,
    );
    await _wachtTot(() => s.endpoint?.baseUrl == eigen);
    expect(s.endpoint?.baseUrl, eigen, reason: 'alleen de pc met de onthouden id telt');
    final log = File('${scratch.path}${Platform.pathSeparator}verbinding.log').readAsStringSync();
    expect(log, contains('een andere pc (pc-van-de-buren)'));
    expect(log, contains('winnaar ${eigen.authority}'));
  });

  test('alleen de buren antwoorden: dan geen overstap, de sessie blijft bij het onthouden adres', () async {
    final (_, vreemd) = await pc('pc-van-de-buren');
    final dood = Uri.parse('http://127.0.0.1:${await _dichtePoort()}');
    final lib = LibraryStore();
    final s = sessie(lib);
    addTearDown(s.dispose);
    await s.connect(
      RemoteEndpoint(baseUrl: dood, token: 'x', serverId: 'pc-saber-0001', uitwijk: [vreemd.toString()]),
      remember: false,
    );
    expect(s.endpoint?.baseUrl, dood, reason: 'liever geen verbinding dan je sleutel aan een vreemde pc');
  });

  test('het adresboek in je account is de laatste kans, alleen voor de eigen pc', () async {
    final (_, eigen) = await pc('pc-saber-0001');
    final dood = Uri.parse('http://127.0.0.1:${await _dichtePoort()}');
    String? gevraagd;
    final lib = LibraryStore();
    final s = ClientSession(
      library: lib,
      settings: AppSettings(),
      owner: false,
      applyMediaResolver: (_) {},
      zoekOpNetwerk: () async => const [],
      adressenUitAccount: (id) async {
        gevraagd = id;
        return [eigen];
      },
    );
    addTearDown(s.dispose);
    await s.connect(RemoteEndpoint(baseUrl: dood, token: 'gedeelde-pc-saber-0001', serverId: 'pc-saber-0001'),
        remember: false);
    expect(gevraagd, 'pc-saber-0001');
    expect(s.endpoint?.baseUrl, eigen);
  });
}
