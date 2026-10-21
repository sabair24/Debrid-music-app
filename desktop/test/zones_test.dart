/// De zones, deelstap 2.1 (Saber, 21-10-2026: "als ik op de pc een liedje aan het spelen ben, dat de
/// ander devices dit zien … Roon heeft daar een goed systeem").
///
/// Wat hier vastligt: de pc houdt per toestel bij wat het speelt (ook als een ander toestel later meldde),
/// wie bereikbaar is (een open lijn, of een melding van de laatste halve minuut), wat de speakers doen,
/// en dat een toestel elke wijziging meteen over `/api/zones/events` krijgt — in plaats van om de vier
/// seconden te vragen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show RepeatMode;
import 'package:debridmusic/verder_luisteren.dart';
import 'package:debridmusic/zone_lijst.dart';

Map<String, dynamic> _melding(String trackId, {required int at, bool playing = true, List<String>? rij, int pos = 0}) =>
    {
      'type': 'progress',
      'trackId': trackId,
      'positionMs': pos,
      'queue': rij ?? [trackId],
      'index': 0,
      'playing': playing,
      'at': at,
    };

void main() {
  group('ZoneStaat', () {
    test('gaat heen en terug als json', () {
      const z = ZoneStaat(
        id: 'dev:gsm-1',
        soort: ZoneSoort.gsm,
        naam: 'Galaxy',
        online: true,
        playing: true,
        trackId: 't1',
        titel: 'Be My Lover',
        artiest: 'La Bouche',
        album: 'Sweet Dreams',
        positionMs: 61000,
        durationMs: 240000,
        opMs: 5000,
        index: 3,
        lengte: 12,
        shuffle: true,
        repeat: 'all',
        radio: 'Radio La Bouche',
      );
      expect(ZoneStaat.fromJson(jsonDecode(jsonEncode(z.toJson())) as Map<String, dynamic>), z);
      expect(z.toestel, 'gsm-1');
      expect(const ZoneStaat(id: 'spk:sonos', soort: ZoneSoort.speaker, naam: 'Amp').toestel, isNull);
    });

    test('de plek schuift op terwijl het speelt, nooit voorbij het einde; gepauzeerd blijft ze staan', () {
      const z = ZoneStaat(
          id: 'dev:x', soort: ZoneSoort.pc, naam: 'pc', playing: true, trackId: 't', positionMs: 10000, durationMs: 20000, opMs: 1000);
      expect(positieNu(z, nuMs: 6000), const Duration(seconds: 15));
      expect(positieNu(z, nuMs: 60000), const Duration(seconds: 20));
      const stil = ZoneStaat(id: 'dev:x', soort: ZoneSoort.pc, naam: 'pc', trackId: 't', positionMs: 10000, opMs: 1000);
      expect(positieNu(stil, nuMs: 60000), const Duration(seconds: 10));
    });

    test('het soort toestel uit platform en naam', () {
      expect(zoneSoortVoor(platform: 'windows', naam: 'SABER-PC'), ZoneSoort.pc);
      expect(zoneSoortVoor(platform: 'macos', naam: 'MacBook'), ZoneSoort.mac);
      expect(zoneSoortVoor(platform: 'ios', naam: 'iPad van Saber'), ZoneSoort.tablet);
      expect(zoneSoortVoor(platform: 'ios', naam: 'iPhone'), ZoneSoort.gsm);
      expect(zoneSoortVoor(platform: 'android', naam: 'SHIELD Android TV'), ZoneSoort.tv);
      expect(zoneSoortVoor(platform: 'android', naam: 'Galaxy S26', tv: true), ZoneSoort.tv);
      expect(zoneSoortVoor(platform: 'android', naam: 'Galaxy S26'), ZoneSoort.gsm);
    });
  });

  group('SseLezer', () {
    test('events met naam, meerdere dataregels, en commentaar overgeslagen', () {
      final l = SseLezer();
      final uit = <SseEvent>[];
      for (final r in [': ping', '', 'event: zones', 'data: {"a":1}', '', 'data: een', 'data: twee', '', 'id: 3', '']) {
        final e = l.regel(r);
        if (e != null) uit.add(e);
      }
      expect(uit, [
        (event: 'zones', data: '{"a":1}'),
        (event: 'message', data: 'een\ntwee'),
      ]);
    });
  });

  group('ZoneRegister', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;
    var nu = 1000000000;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_zones_');
      staat = LanStateStore(File('${map.path}/state.json'));
      nu = DateTime.now().millisecondsSinceEpoch;
      reg = ZoneRegister(
        state: staat,
        pcId: 'pc-THUIS',
        pcNaam: 'THUIS',
        nummer: (id) => (titel: 'Titel $id', artiest: 'Artiest', album: 'Album', duurMs: 200000),
        klok: () => nu,
      );
    });

    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    test('elk toestel apart, ook als een ander later meldde — de pc staat er altijd', () {
      final t = DateTime.now().millisecondsSinceEpoch;
      staat.applyOps([_melding('a', at: t)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      staat.applyOps([_melding('b', at: t + 100)], deviceId: 'ipad-1', deviceName: 'iPad');
      // De gsm meldt opnieuw: vroeger was er één plek voor de laatste melding van wie dan ook, nu heeft
      // elk toestel zijn eigen zone.
      staat.applyOps([_melding('c', at: t + 50)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      reg.stroomOpen('gsm-1', naam: 'Galaxy', soort: ZoneSoort.gsm);
      reg.stroomOpen('ipad-1', naam: 'iPad', soort: ZoneSoort.tablet);
      final z = {for (final x in reg.lijst()) x.id: x};
      expect(z.keys, containsAll(['dev:pc-THUIS', 'dev:gsm-1', 'dev:ipad-1']));
      expect(z['dev:gsm-1']!.trackId, 'c');
      expect(z['dev:gsm-1']!.titel, 'Titel c', reason: 'wat de pc over het nummer weet');
      expect(z['dev:ipad-1']!.trackId, 'b');
      expect(z['dev:pc-THUIS']!.online, isTrue);
      expect(z['dev:pc-THUIS']!.speeltIets, isFalse);
      expect(reg.lijst().first.id, 'dev:pc-THUIS', reason: 'de pc vooraan');
    });

    test('bereikbaar: een open lijn, of een melding van de laatste halve minuut; weg = speelt niet meer', () {
      staat.applyOps([_melding('a', at: DateTime.now().millisecondsSinceEpoch)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      reg.stroomOpen('gsm-1', naam: 'Galaxy', soort: ZoneSoort.gsm);
      ZoneStaat gsm() => reg.lijst().firstWhere((z) => z.id == 'dev:gsm-1');
      expect(gsm().online, isTrue);
      expect(gsm().playing, isTrue);
      reg.stroomDicht('gsm-1');
      nu += 20000;
      expect(gsm().online, isTrue, reason: 'nog geen halve minuut');
      nu += 15000;
      expect(gsm().online, isFalse);
      expect(gsm().playing, isFalse, reason: 'een toestel dat weg is, speelt niet');
      expect(gsm().trackId, 'a', reason: 'maar wat het speelde blijft zichtbaar (en over te nemen)');
    });

    test('wat een dag oud is en niet bereikbaar, valt eruit', () {
      staat.applyOps([_melding('a', at: DateTime.now().millisecondsSinceEpoch)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      nu += const Duration(hours: 25).inMilliseconds;
      expect(reg.lijst().map((z) => z.id), ['dev:pc-THUIS']);
    });

    test('speakers staan erbij, met wie ze de muziek gaf', () {
      reg.zetSpeakers([
        (id: 'uuid:amp', naam: 'Sonos Amp', trackId: 'x', index: 2, lengte: 9, speelt: true, positieMs: 1000, duurMs: 0, opMs: nu),
      ]);
      final s = reg.lijst().firstWhere((z) => z.id == 'spk:uuid:amp');
      expect(s.soort, ZoneSoort.speaker);
      expect(s.via, 'THUIS');
      expect(s.durationMs, 200000, reason: 'een Sonos meldt geen lengte; de bibliotheek weet hem');
      expect(s.toestel, isNull);
    });

    test('de volledige stand van een zone, mét de wachtrij', () {
      staat.applyOps([_melding('b', at: DateTime.now().millisecondsSinceEpoch, rij: ['a', 'b', 'c'])],
          deviceId: 'gsm-1', deviceName: 'Galaxy');
      expect(reg.standVan('dev:gsm-1')!.queue, ['a', 'b', 'c']);
      expect(reg.standVan('dev:niemand'), isNull);
      expect(reg.standVan('spk:uuid:amp'), isNull);
    });

    test('elke melding gaat rond', () async {
      var n = 0;
      final sub = reg.veranderd.listen((_) => n++);
      staat.applyOps([_melding('a', at: DateTime.now().millisecondsSinceEpoch)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      reg.stroomOpen('ipad-1', naam: 'iPad', soort: ZoneSoort.tablet);
      await Future<void>.delayed(Duration.zero);
      expect(n, 2);
      await sub.cancel();
    });
  });

  group('van buiten', () {
    test('de zones mogen ook via de deur naar buiten (Saber: "Ja, alles")', () {
      expect(weigerVanBuiten('/api/zones', 'GET'), isNull);
      expect(weigerVanBuiten('/api/zones/events', 'GET'), isNull);
      expect(weigerVanBuiten('/api/zones/stand', 'GET'), isNull);
    });
  });

  group('de lijn naar een toestel', () {
    late Directory map;
    late LanServer server;
    late String basis;
    RemoteClient? vast;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_zones_srv_');
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

    test('wat een ander toestel meldt, staat binnen een seconde op de lijn', () async {
      final c = client();
      final events = <SseEvent>[];
      final sub = c.zoneStroom(toestel: 'gsm-1', naam: 'Galaxy', platform: 'android').listen(events.add);
      // De eerste lijst, met de gsm erin (hij heeft de lijn open).
      for (var i = 0; i < 50 && !events.any((e) => e.event == 'zones'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final eerste = jsonDecode(events.firstWhere((e) => e.event == 'zones').data) as Map<String, dynamic>;
      expect([for (final z in eerste['zones'] as List) z['id']], contains('dev:gsm-1'));

      final klok = Stopwatch()..start();
      await c.ask('/api/state/ops', {
        'ops': [_melding('t9', at: DateTime.now().millisecondsSinceEpoch, rij: ['t8', 't9'])],
        'deviceId': 'ipad-1',
        'deviceName': 'iPad',
      });
      Map<String, dynamic>? ipad;
      while (ipad == null && klok.elapsed < const Duration(seconds: 1)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        for (final e in events.where((e) => e.event == 'zones')) {
          for (final z in (jsonDecode(e.data) as Map)['zones'] as List) {
            if (z['id'] == 'dev:ipad-1' && z['trackId'] == 't9') ipad = (z as Map).cast<String, dynamic>();
          }
        }
      }
      expect(ipad, isNotNull, reason: 'binnen een seconde, niet na vier');
      expect(events.any((e) => e.event == 'stand' && e.data.contains('t9')), isTrue,
          reason: 'de stand voor "Hier verder luisteren" komt ook meteen');

      // En de volledige stand, met de wachtrij, om over te nemen.
      expect((await c.zoneStand('dev:ipad-1'))!['queue'], ['t8', 't9']);
      expect(await c.zoneStand('dev:niemand'), isNull);
      await sub.cancel();
    });

    test('wie de lijn open heeft, kan "Speel daar" krijgen', () async {
      final sub = client().zoneStroom(toestel: 'gsm-1', naam: 'Galaxy').listen((_) {});
      for (var i = 0; i < 50 && server.zones.bereikbareToestellen().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(server.zones.bereikbareToestellen().map((t) => t.id), ['gsm-1']);
      await sub.cancel();
    });

    test('ZoneVerbinding: de lijst komt binnen, en bij een pc zonder zones blijft hij leeg', () async {
      final lijst = ZoneLijst(hier: 'dev:gsm-1');
      final standen = <String>[];
      final lijn = ZoneVerbinding(
        lijst: lijst,
        client: client,
        toestel: 'gsm-1',
        naam: 'Galaxy',
        opStand: (p, v) => standen.add('${p?['trackId']}'),
      )..start();
      for (var i = 0; i < 100 && !lijst.verbonden; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(lijst.ondersteund, isTrue);
      expect(lijst.verbonden, isTrue);
      expect(lijst.dezeZone?.naam, 'Galaxy');
      lijn.stop();

      // Een pc van vóór de zones: 404.
      final oud = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      oud.listen((r) {
        r.response.statusCode = 404;
        r.response.close();
      });
      final leeg = ZoneLijst(hier: 'dev:gsm-1');
      final oudeClient = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${oud.port}'), token: 'x'));
      final oudeLijn = ZoneVerbinding(
        lijst: leeg,
        client: () => oudeClient,
        toestel: 'gsm-1',
        naam: 'Galaxy',
      )..start();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(leeg.ondersteund, isFalse);
      oudeLijn.stop();
      oudeClient.close();
      await oud.close(force: true);
    });
  });

  group('Hier verder vanaf een gekozen zone', () {
    test('neemt over, ook als hier al iets speelt', () async {
      final bron = _Bron()..speelt = true;
      final v = VerderLuisteren(bron, klok: () => 1005000);
      final ok = await v.neemOverUit({
        'trackId': 'b',
        'positionMs': 60000,
        'queue': ['a', 'b'],
        'index': 1,
        'playing': true,
        'updatedAt': 1000000,
        'deviceId': 'pc-THUIS',
        'deviceName': 'THUIS',
      });
      expect(ok, isTrue);
      expect(bron.gespeeld, ['b@65']);
      expect(await v.neemOverUit(null), isFalse);
      v.dispose();
    });
  });
}

class _Bron implements VerderBron {
  bool speelt = false;
  final gespeeld = <String>[];

  @override
  String get mijnId => 'gsm-1';

  @override
  bool get ikSpeel => speelt;

  @override
  Track? nummer(String id) => Track(path: 'http://pc.invalid/stream/$id.flac', title: id, artist: 'X', album: 'A');

  @override
  Future<({Map<String, dynamic>? stand, Map<String, dynamic>? verzoek})?> haal() async => null;

  @override
  Future<void> speel(List<Track> rij, int index, Duration positie,
      {required bool spelen, required bool shuffle, required RepeatMode herhaal, String? radioArtiest}) async {
    gespeeld.add('${rij[index].title}@${positie.inSeconds}');
  }

  @override
  void pauzeer() => speelt = false;
}
