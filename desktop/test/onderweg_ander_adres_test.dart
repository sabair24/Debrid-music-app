/// Een draaiende app stapt over op het Tailscale-adres zodra het thuisadres niets meer is.
///
/// **Waarom dit bestaat.** Op 06-10-2026 kwam Sabers telefoon op 5G niet meer bij de pc, met
/// Tailscale aan en verbonden. De app was thuis gestart, had verbonden met het thuisadres en bleef
/// dat daarna elke vijftien seconden proberen — de uitwijkadressen werden alleen bij een KOUDE start
/// afgegaan. Op de pc stond tussen 07:51 en 08:22 geen enkele aanvraag; koppelen lukte uiteindelijk
/// alleen met een code via Chrome Remote Desktop.
///
/// Over een echte socket, zoals `client_session_test.dart`: een echte [LanServer] als "het
/// Tailscale-adres", en als thuisadres een poort waar niemand opneemt.
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

/// Een poort waar zeker niemand op luistert: even binden en meteen weer loslaten.
Future<int> _dichtePoort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final poort = s.port;
  await s.close();
  return poort;
}

Future<void> _wachtTot(bool Function() klaar, {Duration max = const Duration(seconds: 20)}) async {
  final eind = DateTime.now().add(max);
  while (!klaar() && DateTime.now().isBefore(eind)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory scratch, pcRoot;
  late LanServer server;
  late PairingStore pairing;
  late Uri tailscale;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_onderweg_');
    setAppDirForTest(scratch.path);
    pcRoot = Directory.systemTemp.createTempSync('dm_onderweg_pc_');
    final map = Directory('${pcRoot.path}/Portishead/Dummy')..createSync(recursive: true);
    final f = File('${map.path}/01 - Mysterons.flac')..writeAsBytesSync(List<int>.filled(4096, 0));
    final pc = LibraryStore()
      ..tracks.add(Track(path: f.path, title: 'Mysterons', artist: 'Portishead', album: 'Dummy'));
    pc.albums = [Album('Dummy', 'Portishead', pc.tracks.toList())];
    pairing = PairingStore();
    server = LanServer(
      library: pc,
      token: 'de-echte-sleutel',
      state: LanStateStore(File('${pcRoot.path}/state.json')),
      pairing: pairing,
      port: 0,
      version: '1.2.3',
      settings: AppSettings(),
    );
    expect(await server.start(), isNull);
    tailscale = Uri.parse('http://127.0.0.1:${server.boundPort}');
  });

  tearDown(() async {
    await server.dispose();
    for (final map in [pcRoot, scratch]) {
      for (var poging = 0; poging < 10; poging++) {
        try {
          map.deleteSync(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    }
  });

  test('DE KERN: op 5G stapt een draaiende sessie zelf over op het uitwijkadres', () async {
    final gekoppeld = await RemoteClient.pair(tailscale, pairing.start(), deviceName: 'S26');
    // Zo stond hij vanochtend: verbonden met het thuisadres, met het Tailscale-adres als uitwijk.
    final thuis = Uri.parse('http://127.0.0.1:${await _dichtePoort()}');
    final library = LibraryStore();
    final session = ClientSession(
      library: library,
      settings: AppSettings(),
      owner: false,
      applyMediaResolver: (_) {},
      // Niet op het echte netwerk zoeken: daar staat op deze pc vaak de echte app.
      zoekOpNetwerk: () async => const [],
    );
    addTearDown(session.dispose);

    await session.connect(RemoteEndpoint(
      baseUrl: thuis,
      token: gekoppeld.token,
      name: 'Saber',
      uitwijk: [tailscale.toString()],
    ));
    await _wachtTot(() => session.endpoint?.baseUrl == tailscale && library.albums.isNotEmpty);

    expect(session.endpoint?.baseUrl, tailscale,
        reason: 'de sessie bleef het thuisadres proberen — op 5G is dat niets, en het Tailscale-adres '
            'stond klaar');
    expect(library.albums, isNotEmpty, reason: 'na het overstappen hoort de bibliotheek er te zijn');
    expect((await loadPairedServer())?.baseUrl, tailscale,
        reason: 'anders begint de volgende start weer op het dode thuisadres');
    expect(session.endpoint?.token, gekoppeld.token, reason: 'een ander adres is geen andere koppeling');

    final logboek = File('${scratch.path}${Platform.pathSeparator}verbinding.log').readAsStringSync();
    expect(logboek, contains('overgestapt op ${tailscale.authority}'),
        reason: 'zonder regel valt achteraf niet te zeggen wat de telefoon deed');
    expect(logboek, isNot(contains(gekoppeld.token)), reason: 'een sleutel hoort nooit in het logboek');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('DE GRENS: zonder ander adres dat antwoordt blijft hij staan en meldt hij het', () async {
    final gekoppeld = await RemoteClient.pair(tailscale, pairing.start(), deviceName: 'S26');
    final thuis = Uri.parse('http://127.0.0.1:${await _dichtePoort()}');
    final ookDood = Uri.parse('http://127.0.0.1:${await _dichtePoort()}');
    final session = ClientSession(
      library: LibraryStore(),
      settings: AppSettings(),
      owner: false,
      applyMediaResolver: (_) {},
      // Niet op het echte netwerk zoeken: daar staat op deze pc vaak de echte app.
      zoekOpNetwerk: () async => const [],
    );
    addTearDown(session.dispose);
    await session.connect(RemoteEndpoint(
      baseUrl: thuis,
      token: gekoppeld.token,
      name: 'Saber',
      uitwijk: [ookDood.toString()],
    ));
    final logPad = File('${scratch.path}${Platform.pathSeparator}verbinding.log');
    await _wachtTot(() => logPad.existsSync() && logPad.readAsStringSync().contains('geen ander adres'));
    expect(session.endpoint?.baseUrl, thuis, reason: 'zonder antwoordend adres valt er niets over te stappen');
    expect(logPad.readAsStringSync(), contains('geen ander adres antwoordt; blijft op ${thuis.authority}'));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
