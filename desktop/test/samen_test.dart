/// Toestellen samen laten spelen (groeperen, stap 3.2, Saber 21-10-2026: "hoorbaar gelijk in één kamer",
/// met een vertraging per toestel).
///
/// Wat hier vastligt: waar een volger hoort te zijn; wanneer hij spoelt en wanneer hij zacht bijstuurt (en
/// dat hij niet heen en weer schakelt rond één grens); dat de klok de snelste meting neemt; hoe de pc een
/// groep bijhoudt (een toestel in hoogstens één groep); en dat een melding van de leider als anker bij de
/// volger aankomt, en "los" als einde.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/samen.dart';

const _anker = SamenAnker(
    groep: 'dev:pc', trackId: 't', rij: ['s', 't'], index: 1, positieMs: 60000, pcMs: 1000000, speelt: true);

void main() {
  group('waar een volger hoort te zijn', () {
    test('de plek van de leider plus de tijd sindsdien, min de eigen vertraging', () {
      expect(verwachtePlek(_anker, nuPcMs: 1002500), const Duration(milliseconds: 62500));
      expect(verwachtePlek(_anker, nuPcMs: 1002500, vertragingMs: 200), const Duration(milliseconds: 62300),
          reason: 'positief = dit toestel klinkt later');
      expect(verwachtePlek(_anker, nuPcMs: 1002500, vertragingMs: -150), const Duration(milliseconds: 62650),
          reason: 'Bluetooth: vroeger spelen');
      const stil = SamenAnker(
          groep: 'dev:pc', trackId: 't', rij: [], index: 0, positieMs: 60000, pcMs: 1000000, speelt: false);
      expect(verwachtePlek(stil, nuPcMs: 1009000), const Duration(seconds: 60), reason: 'gepauzeerd schuift niet op');
    });

    test('het anker heen en terug', () {
      final terug = SamenAnker.fromJson(jsonDecode(jsonEncode(_anker.toJson())) as Map<String, dynamic>)!;
      expect(terug.toJson(), _anker.toJson());
      expect(SamenAnker.fromJson({'trackId': ''}), isNull);
    });
  });

  group('bijsturen', () {
    test('ver weg: spoelen; dichtbij: niets; ertussen: zacht sneller of trager', () {
      expect(bijsturing(900).spoel, isTrue);
      expect(bijsturing(-450).spoel, isTrue);
      expect(bijsturing(5).snelheid, 1.0);
      expect(bijsturing(40).snelheid, lessThan(1.0), reason: 'voor: even trager');
      expect(bijsturing(-40).snelheid, greaterThan(1.0), reason: 'achter: even sneller');
      expect(bijsturing(390).snelheid, closeTo(0.97, 1e-9), reason: 'nooit meer dan 3 %');
    });

    test('niet heen en weer rond één grens', () {
      expect(bijsturing(15).snelheid, 1.0, reason: 'nog niet bezig: pas vanaf 20 ms beginnen');
      expect(bijsturing(15, bezig: true).snelheid, lessThan(1.0), reason: 'al bezig: doorgaan tot 8 ms');
      expect(bijsturing(7, bezig: true).snelheid, 1.0);
    });
  });

  test('de klok: de snelste meting telt', () {
    final verschil = klokVerschilUit([
      (t0: 1000, pc: 51600, t1: 3000), // 2 ms rondgang: pc loopt ~49,6 ms voor
      (t0: 5000, pc: 55100, t1: 5200), // 0,2 ms: de beste
      (t0: 9000, pc: 70000, t1: 30000), // 21 ms: vertraagd onderweg
    ]);
    expect(verschil, 55100 - 5100);
    expect(klokVerschilUit(const []), isNull);
  });

  group('de groepen op de pc', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_samen_');
      staat = LanStateStore(File('${map.path}/state.json'));
      reg = ZoneRegister(state: staat, pcId: 'pc-THUIS', pcNaam: 'THUIS');
    });

    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    test('een toestel zit in hoogstens één groep; wie eruit gaat, hoort het', () {
      expect(reg.zetToestelGroep('pc-THUIS', ['gsm', 'ipad']), isEmpty);
      expect(reg.leiderVan('gsm'), 'pc-THUIS');
      // De iPad gaat leiden, met de gsm: weg uit de groep van de pc.
      reg.zetToestelGroep('ipad', ['gsm']);
      expect(reg.toestelGroepen, {
        'ipad': ['gsm'],
      });
      expect(reg.zetToestelGroep('ipad', const []), ['gsm']);
      expect(reg.toestelGroepen, isEmpty);
    });

    test('in de lijst: de leider met de namen van allemaal, de volgers niet apart', () {
      final t = DateTime.now().millisecondsSinceEpoch;
      staat.applyOps([
        {'type': 'progress', 'trackId': 'x', 'positionMs': 1000, 'queue': ['x'], 'index': 0, 'playing': true, 'at': t}
      ], deviceId: 'pc-THUIS', deviceName: 'THUIS');
      reg.stroomOpen('gsm', naam: 'Galaxy', soort: ZoneSoort.gsm);
      reg.zetToestelGroep('pc-THUIS', ['gsm']);
      final z = {for (final x in reg.lijst()) x.id: x};
      expect(z['dev:pc-THUIS']!.naam, 'THUIS + Galaxy');
      expect(z['dev:pc-THUIS']!.groep, ['dev:pc-THUIS', 'dev:gsm']);
      expect(z.containsKey('dev:gsm'), isFalse);
      expect(z['dev:pc-THUIS']!.kanGroeperen, isTrue);
      final a = SamenAnker.fromJson(reg.ankerVan('pc-THUIS'))!;
      expect(a.trackId, 'x');
      expect(a.groep, 'dev:pc-THUIS');
      expect(a.speelt, isTrue);
    });
  });

  group('over de lijn', () {
    late Directory map;
    late LanServer server;
    late RemoteClient c;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_samen_srv_');
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await server.start(), isNull);
      c = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel'));
    });

    tearDown(() async {
      c.close();
      await server.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      map.deleteSync(recursive: true);
    });

    test('de klok van de pc, en een anker bij elke melding van de leider; los = samenStop', () async {
      final pc = await c.tijd();
      expect(pc, isNotNull);
      expect((pc! ~/ 1000 - DateTime.now().millisecondsSinceEpoch).abs(), lessThan(5000));

      final events = <SseEvent>[];
      final sub = c.zoneStroom(toestel: 'gsm-1', naam: 'Galaxy').listen(events.add);
      for (var i = 0; i < 50 && server.zones.bereikbareToestellen().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // De iPad leidt; hij speelt iets.
      await c.ask('/api/state/ops', {
        'ops': [
          {
            'type': 'progress',
            'trackId': 't7',
            'positionMs': 30000,
            'queue': ['t6', 't7'],
            'index': 1,
            'playing': true,
            'at': DateTime.now().millisecondsSinceEpoch,
          }
        ],
        'deviceId': 'ipad-1',
        'deviceName': 'iPad',
      });
      expect((await c.ask('/api/zone/cmd', {'zone': 'dev:ipad-1', 'cmd': 'groepeer', 'leden': ['dev:gsm-1']}))['bezorgd'], 1);
      List<Map<String, dynamic>> cmds() => [
            for (final e in events.where((e) => e.event == 'cmd')) jsonDecode(e.data) as Map<String, dynamic>,
          ];
      for (var i = 0; i < 50 && cmds().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final a = SamenAnker.fromJson((cmds().first['anker'] as Map).cast<String, dynamic>())!;
      expect(cmds().first['cmd'], 'samen');
      expect(a.trackId, 't7');
      expect(a.rij, ['t6', 't7']);

      // Een nieuwe melding van de leider: een nieuw anker.
      await c.ask('/api/state/ops', {
        'ops': [
          {'type': 'progress', 'trackId': 't7', 'positionMs': 35000, 'queue': ['t6', 't7'], 'index': 1, 'playing': false,
           'at': DateTime.now().millisecondsSinceEpoch}
        ],
        'deviceId': 'ipad-1',
        'deviceName': 'iPad',
      });
      for (var i = 0; i < 50 && cmds().length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(SamenAnker.fromJson((cmds()[1]['anker'] as Map).cast<String, dynamic>())!.speelt, isFalse);

      // Los: de gsm hoort dat hij niet meer volgt.
      await c.ask('/api/zone/cmd', {'zone': 'dev:ipad-1', 'cmd': 'groepeer', 'leden': <String>[]});
      for (var i = 0; i < 50 && !cmds().any((m) => m['cmd'] == 'samenStop'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(cmds().any((m) => m['cmd'] == 'samenStop'), isTrue);
      await sub.cancel();
    });
  });
}
