// De gsm als afstandsbediening van de Shield (27-10-2026, Saber: "neem men gsm over om shield te bedienen"). Na vijf
// minuten op de achtergrond kwam een tik op "volgende" wel in de app aan, maar nooit bij de pc: de eerste vraag viel op
// een verbinding die de pc al gesloten had. Eén keer opnieuw, en de pc voert hetzelfde id hoogstens één keer uit.
import 'dart:io';

import 'package:debridmusic/lan/client.dart' show RemoteException;
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/zone_lijst.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('opnieuw als het antwoord uitbleef', () {
    test('DE KERN: de eerste vraag valt op een dode verbinding, de tweede komt aan', () async {
      var keer = 0;
      final fout = await stuurMetHerkansing(() async {
        if (++keer == 1) throw const RemoteException('Kon de pc niet bereiken: Connection closed before full header was received');
      });
      expect(fout, isNull);
      expect(keer, 2);
    });

    test('DE GRENS: een antwoord van de pc (een status) wordt niet herhaald', () async {
      var keer = 0;
      final fout = await stuurMetHerkansing(() async {
        keer++;
        throw const RemoteException('Tv in woonkamer is niet verbonden.', statusCode: 409);
      });
      expect(fout, 'Tv in woonkamer is niet verbonden.');
      expect(keer, 1);
    });

    test('hoogstens één keer opnieuw: blijft de pc weg, dan zegt de app het', () async {
      var keer = 0;
      final fout = await stuurMetHerkansing(() async {
        keer++;
        throw const RemoteException('Kon de pc niet bereiken: timeout');
      });
      expect(fout, 'Kon de pc niet bereiken: timeout');
      expect(keer, 2);
    });

    test('aangesloten: elke opdracht van een toestel naar een zone', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains("    return stuurMetHerkansing(() => c.ask('/api/zone/cmd', op));"));
    });
  });

  group('de pc voert een opdracht één keer uit', () {
    late Directory map;
    late LanServer server;
    late List<Map<String, dynamic>> uitgevoerd;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_zone_herkansing_');
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await server.start(), isNull);
      uitgevoerd = [];
      server.bijZoneOpdracht = (op) async {
        uitgevoerd.add(op);
        return null;
      };
    });

    tearDown(() async {
      await server.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      map.deleteSync(recursive: true);
    });

    test('DE KERN: hetzelfde id twee keer — "volgende" slaat er geen twee over', () async {
      final pc = 'dev:${server.zones.pcId}';
      final op = {'zone': pc, 'cmd': 'next', 'id': 'gsm-1-17'};
      expect((await server.zoneOpdracht(op, van: 'Saber ultra 26')).status, 200);
      final weer = await server.zoneOpdracht(op, van: 'Saber ultra 26');
      expect(weer.status, 200, reason: 'voor de gsm is ze aangekomen');
      expect(weer.antwoord['dubbel'], isTrue);
      expect(uitgevoerd, hasLength(1));
      expect((await server.zoneOpdracht({...op, 'id': 'gsm-1-18'}, van: 'Saber ultra 26')).status, 200);
      expect(uitgevoerd, hasLength(2), reason: 'een nieuwe druk wel');
    });

    test('DE GRENS: zonder id zoals altijd; een opdracht die mislukte mag hetzelfde id opnieuw proberen', () async {
      final pc = 'dev:${server.zones.pcId}';
      await server.zoneOpdracht({'zone': pc, 'cmd': 'pause'}, van: 'de pc');
      await server.zoneOpdracht({'zone': pc, 'cmd': 'pause'}, van: 'de pc');
      expect(uitgevoerd, hasLength(2));
      final weg = {'zone': 'dev:bestaat-niet', 'cmd': 'next', 'id': 'gsm-1-19'};
      expect((await server.zoneOpdracht(weg, van: 'Saber ultra 26')).status, isNot(200));
      expect((await server.zoneOpdracht(weg, van: 'Saber ultra 26')).antwoord['dubbel'], isNull,
          reason: 'de eerste kwam niet aan, dus is de tweede geen herhaling');
    });
  });
}
