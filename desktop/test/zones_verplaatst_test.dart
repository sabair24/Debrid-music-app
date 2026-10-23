/// Verplaatsen = de oude zone stopt (Saber, 23-10-2026: *"als ik ze verplaats blijft op de andere ook, om den
/// duur weet ik niet meer welke speelt"*; en op de vraag wat de oude zone moet doen: *"A stopt helemaal"*).
///
/// Wat hier vastligt:
/// - de kaart van de oude zone zegt vijf seconden "Verplaatst naar …", en telt daarna als "Speelt niets";
/// - een zone die langer dan tien minuten gepauzeerd staat, telt niet meer als spelend;
/// - de bron die na een overname pauzeert, meldt dat voor haar eigen zone ("alleenZone"), zonder "waar je gebleven
///   bent" te overschrijven — tot nu toe slikte ze die melding in, en stond ze in de lijst nog als spelend;
/// - zodra het doel speelt, zegt de pc het de bron zelf: een toestel krijgt 'verplaatst', ook de pc zelf; één keer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/sharing.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

Map<String, dynamic> _melding(String trackId,
        {required int at, bool playing = true, String overname = '', bool alleenZone = false}) =>
    {
      'type': 'progress',
      'trackId': trackId,
      'positionMs': 1000,
      'queue': [trackId],
      'index': 0,
      'playing': playing,
      'at': at,
      if (overname.isNotEmpty) 'overname': overname,
      if (alleenZone) 'alleenZone': true,
    };

const _z = ZoneStaat(id: 'dev:gsm-1', soort: ZoneSoort.gsm, naam: 'Galaxy', online: true, trackId: 't1', opMs: 100000);

void main() {
  group('de kaart', () {
    test('"Verplaatst naar …" vijf seconden, daarna niet meer', () {
      final z = ZoneStaat.fromJson({..._z.toJson(), 'verplaatstNaar': 'iPad', 'verplaatstOp': 200000});
      expect(verplaatstMelding(z, nuMs: 200000), 'Verplaatst naar iPad');
      expect(verplaatstMelding(z, nuMs: 204999), 'Verplaatst naar iPad');
      expect(verplaatstMelding(z, nuMs: 205000), isNull);
      expect(verplaatstMelding(_z, nuMs: 200000), isNull, reason: 'niets verplaatst, niets te zeggen');
      expect(speeltNu(z, nuMs: 200000), isFalse, reason: 'haar muziek speelt nu elders');
      expect(speeltNu(ZoneStaat.fromJson({...z.toJson(), 'playing': true}), nuMs: 200000), isFalse,
          reason: 'ook als haar laatste melding nog "speelt" zei');
      expect(ZoneStaat.fromJson(jsonDecode(jsonEncode(z.toJson())) as Map<String, dynamic>), z,
          reason: 'gaat zo naar de andere toestellen');
    });

    test('gepauzeerd telt tien minuten als spelend, daarna als niets', () {
      expect(speeltNu(ZoneStaat.fromJson({..._z.toJson(), 'playing': true}), nuMs: 100000 + 3600000), isTrue);
      expect(speeltNu(_z, nuMs: 100000 + 599999), isTrue);
      expect(speeltNu(_z, nuMs: 100000 + 600000), isFalse);
      expect(speeltNu(const ZoneStaat(id: 'dev:x', soort: ZoneSoort.pc, naam: 'Pc', online: true), nuMs: 100000),
          isFalse, reason: 'zonder nummer speelt er niets');
    });
  });

  group('het register', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;
    var nu = 0;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_verplaatst_');
      staat = LanStateStore(File('${map.path}/state.json'));
      nu = DateTime.now().millisecondsSinceEpoch;
      reg = ZoneRegister(
        state: staat,
        pcId: 'pc-THUIS',
        pcNaam: 'THUIS',
        nummer: (id) => (titel: 'Titel $id', artiest: 'Artiest', album: 'Album', duurMs: 200000),
        klok: () => nu,
      );
      reg.stroomOpen('gsm-1', naam: 'Galaxy', soort: ZoneSoort.gsm);
    });

    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    ZoneStaat gsm() => reg.lijst().firstWhere((z) => z.id == 'dev:gsm-1');

    // De gedeelde staat zet een melding op de echte klok van de pc (hij corrigeert scheve klokken), dus melden
    // gebeurt op "nu", en schuift alleen het moment van verplaatsen ([nu] van het register) naar achteren.
    int echt() => DateTime.now().millisecondsSinceEpoch;

    test('verplaatst: de naam van het doel, tot de zone ruim daarna zelf weer speelt', () {
      final t = echt();
      staat.applyOps([_melding('t1', at: t)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      expect(reg.netVerplaatst('dev:gsm-1'), isFalse);
      nu = t - 3000;
      reg.verplaatst('dev:gsm-1', 'iPad');
      expect(gsm().verplaatstNaar, 'iPad');
      expect(gsm().verplaatstOp, t - 3000);
      expect(reg.netVerplaatst('dev:gsm-1'), isTrue, reason: 'niet nog eens stoppen');
      // Een late melding "speelt" van de bron (3 s na het verplaatsen), die het nog niet wist: het blijft staan.
      nu = t;
      staat.applyOps([_melding('t1', at: echt())], deviceId: 'gsm-1', deviceName: 'Galaxy');
      expect(gsm().verplaatstNaar, 'iPad');
      nu = t - 3000 + 15000;
      expect(reg.netVerplaatst('dev:gsm-1'), isFalse, reason: 'na vijftien seconden mag het weer');
      // Speelt de gsm ruim na het verplaatsen zelf weer: dan is hij gewoon een spelende zone.
      nu = t - 10000;
      reg.verplaatst('dev:gsm-1', 'iPad');
      nu = t;
      staat.applyOps([_melding('t2', at: echt())], deviceId: 'gsm-1', deviceName: 'Galaxy');
      expect(gsm().verplaatstNaar, isEmpty);
      expect(gsm().playing, isTrue);
      expect(gsm().verplaatstNaar, isEmpty, reason: 'en dat blijft zo');
    });

    test('gepauzeerd na het verplaatsen blijft "verplaatst", ook na de zes seconden', () {
      final t = echt();
      nu = t - 8000;
      reg.verplaatst('dev:gsm-1', 'iPad');
      nu = t;
      staat.applyOps([_melding('t1', at: echt(), playing: false)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      expect(gsm().verplaatstNaar, 'iPad');
      expect(speeltNu(gsm(), nuMs: nu), isFalse);
    });

    test('na een halve dag is "verplaatst" vergeten', () {
      final t = echt();
      nu = t - const Duration(hours: 12, seconds: 1).inMilliseconds;
      reg.verplaatst('dev:gsm-1', 'iPad');
      nu = t;
      staat.applyOps([_melding('t1', at: echt(), playing: false)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      expect(gsm().verplaatstNaar, isEmpty);
    });
  });

  group('de gedeelde staat', () {
    late Directory map;
    late LanStateStore staat;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_verplaatst_staat_');
      staat = LanStateStore(File('${map.path}/state.json'));
    });

    tearDown(() async {
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    test('alleenZone: wel in de eigen zone, niet in "waar je gebleven bent"', () {
      final t = DateTime.now().millisecondsSinceEpoch;
      staat.applyOps([_melding('ipad-nummer', at: t)], deviceId: 'ipad-1', deviceName: 'iPad');
      staat.applyOps([_melding('t1', at: t + 500, playing: false, alleenZone: true)],
          deviceId: 'gsm-1', deviceName: 'Galaxy');
      expect(staat.perToestel['gsm-1']!.playing, isFalse, reason: 'de zonelijst ziet de pauze');
      expect(staat.progress.trackId, 'ipad-nummer', reason: 'de iPad nam over; dat blijft de stand');
      // Zonder de vlag gaat het wel naar de stand (de gewone melding).
      staat.applyOps([_melding('t1', at: t + 900, playing: false)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      expect(staat.progress.trackId, 't1');
    });

    test('een overname gaat rond, één per melding, en niet van zichzelf', () async {
      final gezien = <({String van, String naar, String trackId})>[];
      final sub = staat.overnames.listen(gezien.add);
      final t = DateTime.now().millisecondsSinceEpoch;
      staat.applyOps([_melding('t1', at: t, overname: 'gsm-1')], deviceId: 'ipad-1', deviceName: 'iPad');
      staat.applyOps([_melding('t1', at: t + 100)], deviceId: 'ipad-1', deviceName: 'iPad');
      staat.applyOps([_melding('t1', at: t + 200, overname: 'ipad-1')], deviceId: 'ipad-1', deviceName: 'iPad');
      await Future<void>.delayed(Duration.zero);
      expect(gezien, hasLength(1));
      expect(gezien.single.van, 'gsm-1');
      expect(gezien.single.naar, 'ipad-1');
      expect(gezien.single.trackId, 't1');
      await sub.cancel();
    });
  });

  test('de pc meldt zijn eigen pauze na een overname ook alleen voor zijn zone', () {
    final map = Directory.systemTemp.createTempSync('dm_verplaatst_pc_');
    addTearDown(() => map.deleteSync(recursive: true));
    setAppDirForTest(map.path);
    final pc = LanSharing(
        library: LibraryStore()
          ..rootPath = map.path
          ..configDirOverride = map.path,
        settings: AppSettings()..lanEnabled = false);
    final pad = '${map.path}${Platform.pathSeparator}a.flac';
    expect(pc.progressOp(pad, Duration.zero, false, [pad], 0, alleenZone: true)!['alleenZone'], isTrue);
    expect(pc.progressOp(pad, Duration.zero, false, [pad], 0)!.containsKey('alleenZone'), isFalse);
  });

  group('de pc zegt het de bron', () {
    late Directory map;
    late LanServer server;
    late String basis;
    RemoteClient? vast;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_verplaatst_srv_');
      final library = LibraryStore()..rootPath = map.path;
      server = LanServer(
        library: library,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await server.start(), isNull);
      basis = 'http://127.0.0.1:${server.boundPort}';
    });

    tearDown(() async {
      vast?.close();
      vast = null;
      await server.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      map.deleteSync(recursive: true);
    });

    RemoteClient client() => vast ??= RemoteClient(RemoteEndpoint(baseUrl: Uri.parse(basis), token: 'sleutel'));

    Future<void> meld(String toestel, String naam, Map<String, dynamic> op) =>
        client().ask('/api/state/ops', {'ops': [op], 'deviceId': toestel, 'deviceName': naam});

    Future<void> wachtOp(bool Function() klaar) async {
      for (var i = 0; i < 150 && !klaar(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('een toestel als bron: "verplaatst" over zijn lijn, één keer, en de lijst zegt het', () async {
      final events = <SseEvent>[];
      final sub = client().zoneStroom(toestel: 'gsm-1', naam: 'Galaxy', platform: 'android').listen(events.add);
      await wachtOp(() => server.zones.bereikbareToestellen().isNotEmpty);
      final t = DateTime.now().millisecondsSinceEpoch;
      await meld('gsm-1', 'Galaxy', _melding('t1', at: t));
      // De iPad nam over (Hier verder, of het verzoek van "Daarheen"): zijn eerste melding noemt de gsm.
      server.zones.gezien('ipad-1', naam: 'iPad');
      await meld('ipad-1', 'iPad', _melding('t1', at: t + 200, overname: 'gsm-1'));
      List<Map<String, dynamic>> opdrachten() => [
            for (final e in events)
              if (e.event == 'cmd') (jsonDecode(e.data) as Map).cast<String, dynamic>(),
          ];
      await wachtOp(() => opdrachten().isNotEmpty);
      expect(opdrachten().single['cmd'], 'verplaatst');
      expect(opdrachten().single['naar'], 'iPad');
      expect(opdrachten().single['zone'], 'dev:gsm-1');
      // Nog een melding met dezelfde overname (een tweede pad, zoals de overdracht zelf): niet nog eens.
      await meld('ipad-1', 'iPad', _melding('t1', at: t + 400, overname: 'gsm-1'));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(opdrachten(), hasLength(1));
      expect(server.zones.lijst().firstWhere((z) => z.id == 'dev:gsm-1').verplaatstNaar, 'iPad');
      await sub.cancel();
    });

    test('de pc als bron: de opdracht komt bij zijn eigen zone', () async {
      final eigen = <Map<String, dynamic>>[];
      server.bijZoneOpdracht = (op) async {
        eigen.add(op);
        return null;
      };
      final pc = server.zones.pcId;
      final t = DateTime.now().millisecondsSinceEpoch;
      server.state.applyOps([_melding('t1', at: t)], deviceId: pc, deviceName: 'THUIS');
      server.zones.gezien('ipad-1', naam: 'iPad');
      await meld('ipad-1', 'iPad', _melding('t1', at: t + 200, overname: pc));
      await wachtOp(() => eigen.isNotEmpty);
      expect(eigen.single['cmd'], 'verplaatst');
      expect(eigen.single['naar'], 'iPad');
    });

    test('twee wegen tegelijk (de overdracht en de melding): de bron hoort het één keer', () async {
      final eigen = <Map<String, dynamic>>[];
      server.bijZoneOpdracht = (op) async {
        eigen.add(op);
        return null;
      };
      final pc = server.zones.pcId;
      final t = DateTime.now().millisecondsSinceEpoch;
      server.state.applyOps([_melding('t1', at: t)], deviceId: pc, deviceName: 'THUIS');
      server.zones.gezien('ipad-1', naam: 'iPad');
      // Allebei wachten ze tot de iPad speelt …
      await meld('ipad-1', 'iPad', _melding('t1', at: t + 100, overname: pc, playing: false));
      await meld('ipad-1', 'iPad', _melding('t1', at: t + 200, overname: pc, playing: false));
      // … en dan speelt hij.
      await meld('ipad-1', 'iPad', _melding('t1', at: t + 300));
      await wachtOp(() => eigen.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(eigen, hasLength(1));
    });

    test('speelt het doel (nog) niet, dan stopt de bron niet', () async {
      final eigen = <Map<String, dynamic>>[];
      server.bijZoneOpdracht = (op) async {
        eigen.add(op);
        return null;
      };
      final pc = server.zones.pcId;
      final t = DateTime.now().millisecondsSinceEpoch;
      server.state.applyOps([_melding('t1', at: t)], deviceId: pc, deviceName: 'THUIS');
      server.zones.gezien('ipad-1', naam: 'iPad');
      await meld('ipad-1', 'iPad', _melding('t1', at: t + 200, overname: pc, playing: false));
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(eigen, isEmpty);
    });
  });
}
