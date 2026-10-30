/// De wedloop van `adreswedloop.dart` aan een echte sessie: de juiste pc wint, een andere pc op een
/// adres niet, en de id van de pc wordt bij de eerste verbinding geleerd.
///
/// Stap 4 van "verbinden zoals Roon ARC" (14-10-2026). Over een echte socket, zoals
/// `onderweg_ander_adres_test`.
library;

import 'dart:async';
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

/// Een luik voor [doel] op een eigen poort, zodat de toets bepaalt wie eerst antwoordt. Wat
/// binnenkomt gaat ongewijzigd door, maar pas als [eerst] klaar is; [opgehangen] hoort het als
/// de vrager ophangt.
Future<Uri> _luik(Uri doel, {Future<void>? eerst, void Function()? opgehangen}) async {
  final luik = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(luik.close);
  luik.listen((vrager) async {
    await eerst;
    final Socket pc;
    try {
      pc = await Socket.connect(InternetAddress.loopbackIPv4, doel.port);
    } catch (_) {
      vrager.destroy();
      return;
    }
    pc.listen(vrager.add, onDone: vrager.destroy, onError: (Object _) => vrager.destroy());
    vrager.listen(pc.add, onDone: () {
      pc.destroy();
      opgehangen?.call();
    }, onError: (Object _) => pc.destroy());
  });
  return Uri.parse('http://127.0.0.1:${luik.port}');
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
    final (_, buren) = await pc('pc-van-de-buren');
    final (_, saber) = await pc('pc-saber-0001');
    // De buren antwoorden eerst, en dat staat vast: de eigen pc krijgt de vraag pas als de buren
    // opgehangen zijn. **Waarom het luik.** Alle drie de adressen zijn 127.0.0.1, dus "thuis": ze
    // beginnen tegelijk, en het eerste juiste antwoord wint meteen. Wie dan eerst antwoordt, is
    // toeval. Op 30-10-2026 antwoordde onder last de eigen pc eerst in 17 van de 288 rondes (24
    // kopieën met 40 branders). In elk van die rondes ontbrak de regel van de buren in het verloop,
    // omdat hun antwoord pas na de uitslag kwam. Het antwoord kwam op de poort van de eigen pc, niet
    // op het dode adres: Windows gaf in 48.424 pogingen nooit een bezette poort uit. Het luik wacht
    // op het ophangen, niet op het antwoord. De wedloop verwerkt het antwoord in microtaken, en het
    // ophangen ziet het luik pas bij de volgende gebeurtenis, als de regel er al staat.
    final burenOpgehangen = Completer<void>();
    final vreemd = await _luik(buren, opgehangen: () {
      if (!burenOpgehangen.isCompleted) burenOpgehangen.complete();
    });
    final eigen = await _luik(saber, eerst: burenOpgehangen.future);
    final dood = Uri.parse('http://127.0.0.1:${await _dichtePoort()}');
    final lib = LibraryStore();
    final s = sessie(lib);
    addTearDown(s.dispose);
    // Thuisadres dood; als uitwijk eerst de buren, dan de eigen pc.
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
