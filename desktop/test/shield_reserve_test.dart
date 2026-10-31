/// "Slaapt" op de zonekaart, en de reserve als Debrid Music op de Shield niet antwoordt (Saber, 31-10-2026: "slaap en
/// wekken … als reserve bouwen" — gekozen: "Wekken, en dan via adb starten").
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/adb_wekker.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/wekker.dart' show wachtTot;

String _bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('slaapt', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_slaapt_');
      staat = LanStateStore(File('${map.path}${Platform.pathSeparator}state.json'));
      reg = ZoneRegister(
        state: staat,
        pcId: 'pc-THUIS',
        pcNaam: 'THUIS',
        nummer: (id) => (titel: 'Titel $id', artiest: 'Artiest', album: 'Album', duurMs: 200000),
      );
    });
    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    ZoneStaat? tv() => reg.lijst().where((z) => z.id == 'dev:shield').firstOrNull;

    test('DE KERN: een tv die slaapt maar bereikbaar is, staat als "slaapt" in de lijst — en wakker weer niet', () async {
      reg.stroomOpen('shield', naam: 'Tv in woonkamer', soort: ZoneSoort.tv);
      expect(tv()?.slaapt, isFalse);
      final veranderd = <String>[];
      final sub = staat.zoneChanges.listen(veranderd.add);
      final rev = staat.rev;
      staat.applyOps([
        {'type': 'slaapt', 'value': true}
      ], deviceId: 'shield');
      await Future<void>.delayed(Duration.zero);
      expect(tv()?.slaapt, isTrue);
      expect(tv()?.toJson()['slaapt'], true);
      staat.applyOps([
        {'type': 'slaapt', 'value': true}
      ], deviceId: 'shield');
      await Future<void>.delayed(Duration.zero);
      expect(veranderd, ['shield'], reason: 'nog eens hetzelfde melden is geen verandering');
      staat.applyOps([
        {'type': 'slaapt', 'value': false}
      ], deviceId: 'shield');
      await Future<void>.delayed(Duration.zero);
      expect(tv()?.slaapt, isFalse);
      expect(staat.rev, rev, reason: 'niets voor op schijf of voor de gedeelde staat');
      await sub.cancel();
    });

    test('weg (geen lijn): "niet bereikbaar", niet "slaapt"', () async {
      var nu = DateTime.now().millisecondsSinceEpoch;
      final r2 = ZoneRegister(
        state: staat,
        pcId: 'pc-THUIS',
        pcNaam: 'THUIS',
        nummer: (id) => (titel: 'T', artiest: 'A', album: 'B', duurMs: 1000),
        klok: () => nu,
      );
      staat.applyOps([
        {'type': 'progress', 'trackId': 'x', 'positionMs': 0, 'queue': ['x'], 'index': 0, 'playing': false, 'updatedAt': nu}
      ], deviceId: 'shield', deviceName: 'Tv in woonkamer');
      staat.applyOps([
        {'type': 'slaapt', 'value': true}
      ], deviceId: 'shield');
      r2.stroomOpen('shield', naam: 'Tv in woonkamer', soort: ZoneSoort.tv);
      expect(r2.lijst().firstWhere((z) => z.id == 'dev:shield').slaapt, isTrue);
      r2.stroomDicht('shield');
      nu += 60 * 1000;
      final z = r2.lijst().firstWhere((z) => z.id == 'dev:shield');
      expect(z.online, isFalse);
      expect(z.slaapt, isFalse, reason: 'alleen wie bereikbaar is, slaapt — anders: niet bereikbaar');
      await r2.dispose();
    });

    test('heen en terug over de lijn', () {
      const z = ZoneStaat(id: 'dev:x', soort: ZoneSoort.tv, naam: 'Tv', online: true, slaapt: true);
      expect(ZoneStaat.fromJson(z.toJson()).slaapt, isTrue);
      expect(ZoneStaat.fromJson(z.toJson()), z);
      expect(z == const ZoneStaat(id: 'dev:x', soort: ZoneSoort.tv, naam: 'Tv', online: true), isFalse);
    });
  });

  group('de reserve via adb', () {
    test('adb vinden: de SDK van Android Studio, ANDROID_HOME eerst; nergens = geen reserve', () {
      final sep = Platform.pathSeparator;
      final naam = Platform.isWindows ? 'adb.exe' : 'adb';
      final sdk = 'C:${sep}Users${sep}s${sep}AppData${sep}Local${sep}Android${sep}Sdk${sep}platform-tools$sep$naam';
      expect(zoekAdb(omgeving: {'LOCALAPPDATA': 'C:${sep}Users${sep}s${sep}AppData${sep}Local'}, bestaat: (p) => p == sdk),
          sdk);
      expect(
          zoekAdb(
              omgeving: {'ANDROID_HOME': 'D:${sep}sdk', 'LOCALAPPDATA': 'C:${sep}x'},
              bestaat: (p) => true),
          'D:${sep}sdk${sep}platform-tools$sep$naam');
      expect(zoekAdb(omgeving: {'LOCALAPPDATA': 'C:${sep}x'}, bestaat: (_) => false), isNull);
    });

    test('DE KERN: verbinden, dan wakker en Debrid Music vooraan', () async {
      final gedaan = <List<String>>[];
      final regels = <String>[];
      final ok = await wekViaAdb('192.168.0.238', adb: 'adb', log: regels.add, draai: (p, a) async {
        gedaan.add(a);
        return ProcessResult(1, 0, a.first == 'connect' ? 'already connected to 192.168.0.238:5555' : 'Starting: Intent', '');
      });
      expect(ok, isTrue);
      expect(gedaan, [
        ['connect', '192.168.0.238:5555'],
        ['-s', '192.168.0.238:5555', 'shell', kAdbWekOpdracht],
      ]);
      expect(kAdbWekOpdracht, contains('input keyevent KEYCODE_WAKEUP'));
      expect(kAdbWekOpdracht, contains('-c android.intent.category.LEANBACK_LAUNCHER -n com.debridmusic.app/.MainActivity'));
      expect(regels.single, contains('gewekt'));
    });

    test('niet te bereiken of niet toegestaan: nee, en dan niet verder', () async {
      final gedaan = <List<String>>[];
      expect(
          await wekViaAdb('192.168.0.238', adb: 'adb', draai: (p, a) async {
            gedaan.add(a);
            return ProcessResult(1, 1, 'failed to connect to 192.168.0.238:5555', '');
          }),
          isFalse);
      expect(gedaan.length, 1);
      expect(
          await wekViaAdb('192.168.0.238', adb: 'adb', draai: (p, a) async {
            return a.first == 'connect'
                ? ProcessResult(1, 0, 'connected to 192.168.0.238:5555', '')
                : ProcessResult(1, 1, '', 'error: device unauthorized.');
          }),
          isFalse);
      expect(
          await wekViaAdb('192.168.0.238', adb: 'adb', draai: (p, a) async {
            return a.first == 'connect'
                ? ProcessResult(1, 0, 'connected to 192.168.0.238:5555', '')
                : ProcessResult(1, 0, 'Error: Activity class {com.debridmusic.app/.MainActivity} does not exist.', '');
          }),
          isFalse,
          reason: 'de app staat er niet op');
      expect(await wekViaAdb('192.168.0.238', adb: 'adb', draai: (p, a) async => throw const ProcessException('adb', [])),
          isFalse);
    });

    test('wachtTot: tot het waar is, of tot het geduld op is', () async {
      var n = 0;
      expect(await wachtTot(() => ++n > 3, geduld: const Duration(seconds: 2), stap: const Duration(milliseconds: 5)),
          isTrue);
      final klok = Stopwatch()..start();
      expect(await wachtTot(() => false, geduld: const Duration(milliseconds: 60), stap: const Duration(milliseconds: 5)),
          isFalse);
      expect(klok.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  test('aangesloten: de pc onthoudt waar een tv woont en wekt hem als hij niet antwoordt; de tv meldt zijn slaap', () {
    final server = _bron('lib/lan/server.dart');
    expect(server, contains(
        "      if (soort == ZoneSoort.tv && adres != null && !adres.isLoopback) _onthoudAdres(toestel, adres.address);\n"));
    expect(server, contains('      if (lijnen.isEmpty && reserve != null && adres != null && wektToestel(cmd)) {\n'));
    expect(server, contains('        final terug = await reserve(t, adres) &&\n'
        '            await wachtTot(() => (_zoneLijnen[t] ?? const []).isNotEmpty, geduld: const Duration(seconds: 25));\n'));
    expect(server, contains('        if (terug) await Future<void>.delayed(kNaReserve);\n'));
    final zones = _bron('lib/lan/zones.dart');
    expect(zones, contains("        if (online && state.slapend.contains(id)) 'slaapt': true,\n"));
    final hoofd = _bron('lib/main.dart');
    expect(hoofd, contains('      s.wekViaAdb = adb == null ? null : (toestel, adres) => wekViaAdb(adres, adb: adb, log: adbLog.line);\n'));
    expect(hoofd, contains("              {'type': 'slaapt', 'value': s}\n"));
    expect(hoofd, contains('        Timer.periodic(const Duration(seconds: 20), (_) => unawaited(meldSlaap()));\n'));
    expect(hoofd, contains("              ? 'Slaapt · wordt gewekt als je hier speelt'\n"));
  });
}
