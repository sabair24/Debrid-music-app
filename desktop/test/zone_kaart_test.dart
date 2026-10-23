/// De zonekaart, stap 2 (Saber, 23-10-2026: "De zones vindt ik wel verwarrend … Maak het practice en
/// overzichtelijker").
///
/// Wat hier vastligt:
/// - de volgorde: dit toestel, dan wat speelt (ook kort gepauzeerd), dan wat bereikbaar is, dan wat weg is;
/// - bovenaan groot "Je bedient: …", en die kaart licht op;
/// - "Pc" in plaats van de naam van de computer, en geen "via …" meer;
/// - knoppen Pauze/Verder, Stop, Hierheen, Daarheen en Samen: een woordje onder het icoon op een aanraakscherm, een tip
///   op pc en Mac;
/// - een volumeschuif op elke kaart die speelt; op de Shield − en +;
/// - een groep is één kaart: per lid een schuif en "Los", en "Opheffen";
/// - "Stop" telt meteen als "Speelt niets", tot de zone weer iets krijgt;
/// - op 360 en 1920 punten breed loopt niets over.
library;

import 'dart:io';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show ZoneBlad, zoneKnoppenMetWoord;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show RepeatMode;
import 'package:debridmusic/tv.dart' show setTvModeForTest;
import 'package:debridmusic/verder_luisteren.dart';
import 'package:debridmusic/zone_lijst.dart';
import 'package:debridmusic/zone_speler.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Bron implements VerderBron {
  @override
  String get mijnId => 'gsm-1';

  @override
  bool get ikSpeel => false;

  @override
  Track? nummer(String id) =>
      Track(path: 'http://pc.invalid/stream/$id.flac', title: 'Nummer $id', artist: 'X', album: 'A');

  @override
  Future<({Map<String, dynamic>? stand, Map<String, dynamic>? verzoek})?> haal() async => null;

  @override
  Future<void> speel(List<Track> rij, int index, Duration positie,
      {required bool spelen, required bool shuffle, required RepeatMode herhaal, String? radioArtiest}) async {}

  @override
  void pauzeer() {}
}

const _nu = 1000000;

ZoneStaat _zone(String id, String naam,
        {ZoneSoort soort = ZoneSoort.gsm,
        bool online = true,
        bool playing = false,
        String trackId = '',
        int opMs = _nu - 5000,
        int volume = -1,
        String via = '',
        List<ZoneLid> leden = const []}) =>
    ZoneStaat(
      id: id,
      soort: soort,
      naam: naam,
      online: online,
      playing: playing,
      trackId: trackId,
      positionMs: 60000,
      durationMs: 240000,
      opMs: opMs,
      volume: volume,
      via: via,
      kanGroeperen: true,
      groep: [for (final l in leden) l.id],
      leden: leden,
    );

void main() {
  group('de volgorde', () {
    test('dit toestel, dan wat speelt, dan wat bereikbaar is, dan wat weg is; daarbinnen op naam', () {
      final zones = [
        _zone('dev:pc', 'Pc', soort: ZoneSoort.pc),
        _zone('spk:amp', 'Sonos Amp', soort: ZoneSoort.speaker, playing: true, trackId: 'a'),
        _zone('dev:ipad', 'iPad', online: false, trackId: 'b'),
        _zone('dev:gsm-1', 'Galaxy'),
        _zone('dev:mac', 'Mac', trackId: 'c', opMs: _nu - 60000),
        _zone('spk:kef', 'KEF', soort: ZoneSoort.speaker, trackId: 'd', opMs: _nu - 11 * 60000),
        _zone('dev:shield', 'Shield', playing: true, trackId: 'e'),
      ];
      expect([for (final z in ordenVoorHier(zones, hier: 'dev:gsm-1', nuMs: _nu)) z.naam],
          ['Galaxy', 'Mac', 'Shield', 'Sonos Amp', 'KEF', 'Pc', 'iPad'],
          reason: 'de Mac staat een minuut gepauzeerd en telt nog als spelend; de KEF elf minuten: niet meer');
    });
  });

  group('het register', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;
    var nu = 0;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_zonekaart_');
      staat = LanStateStore(File('${map.path}/state.json'));
      nu = DateTime.now().millisecondsSinceEpoch;
      reg = ZoneRegister(
        state: staat,
        pcId: 'pc-THUIS',
        pcNaam: 'Pc',
        nummer: (id) => (titel: 'Titel $id', artiest: 'Artiest', album: 'Album', duurMs: 200000),
        klok: () => nu,
      );
    });

    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    Map<String, dynamic> melding(String trackId, {int volume = -1, bool playing = true}) => {
          'type': 'progress',
          'trackId': trackId,
          'positionMs': 0,
          'queue': [trackId],
          'index': 0,
          'playing': playing,
          'at': DateTime.now().millisecondsSinceEpoch,
          if (volume >= 0) 'volume': volume,
        };

    test('een groep toestellen: de leider eerst, en elk lid met zijn naam en volume', () {
      reg.stroomOpen('gsm-1', naam: 'Galaxy', soort: ZoneSoort.gsm);
      reg.stroomOpen('ipad-1', naam: 'iPad', soort: ZoneSoort.tablet);
      staat.applyOps([melding('a', volume: 70)], deviceId: 'gsm-1', deviceName: 'Galaxy');
      staat.applyOps([melding('a', volume: 40)], deviceId: 'ipad-1', deviceName: 'iPad');
      reg.zetToestelGroep('gsm-1', ['ipad-1', 'pc-THUIS']);
      final z = reg.lijst().firstWhere((x) => x.id == 'dev:gsm-1');
      expect([for (final l in z.leden) l.id], ['dev:gsm-1', 'dev:ipad-1', 'dev:pc-THUIS']);
      expect([for (final l in z.leden) l.naam], ['Galaxy', 'iPad', 'Pc']);
      expect([for (final l in z.leden) l.volume], [70, 40, -1], reason: 'de pc meldde nog niets');
      expect(z.leden[1].soort, ZoneSoort.tablet);
      expect(z.leden[2].soort, ZoneSoort.pc);
      expect(ZoneStaat.fromJson(z.toJson()), z, reason: 'zo gaat het naar de andere toestellen');
    });

    test('een groep Sonossen: de leider eerst, met het volume van elk', () {
      reg.zetSpeakers([
        (id: 'move', naam: 'Sonos Move', trackId: 'x', index: 0, lengte: 1, speelt: true, positieMs: 0, duurMs: 0, opMs: nu, volume: 25, radio: ''),
        (id: 'amp', naam: 'Sonos Amp', trackId: 'x', index: 0, lengte: 1, speelt: true, positieMs: 0, duurMs: 0, opMs: nu, volume: 60, radio: ''),
      ], bekend: [
        (id: 'amp', naam: 'Sonos Amp', sonos: true),
        (id: 'move', naam: 'Sonos Move', sonos: true),
      ], groepen: [
        (leider: 'amp', leden: ['move', 'amp']),
      ]);
      final z = reg.lijst().firstWhere((x) => x.id == 'spk:amp');
      expect([for (final l in z.leden) l.id], ['spk:amp', 'spk:move']);
      expect([for (final l in z.leden) l.volume], [60, 25]);
      expect(z.via, 'Pc', reason: 'de pc heet "Pc" (het scherm toont "via" niet meer)');
      // Een groep die niets speelt, kan ook opgeheven worden: de leden staan erbij.
      reg.zetSpeakers(const []);
      expect([for (final l in reg.lijst().firstWhere((x) => x.id == 'spk:amp').leden) l.id], ['spk:amp', 'spk:move']);
    });

    test('"Stop": meteen "Speelt niets", tot de zone weer speelt', () {
      reg.stroomOpen('gsm-1', naam: 'Galaxy', soort: ZoneSoort.gsm);
      staat.applyOps([melding('a')], deviceId: 'gsm-1', deviceName: 'Galaxy');
      ZoneStaat gsm() => reg.lijst().firstWhere((x) => x.id == 'dev:gsm-1');
      expect(speeltNu(gsm(), nuMs: nu), isTrue);
      reg.gestopt('dev:gsm-1');
      expect(speeltNu(gsm(), nuMs: nu), isFalse, reason: 'ook al meldde de gsm zijn pauze nog niet');
      expect(verplaatstMelding(gsm(), nuMs: nu), isNull, reason: 'gestopt is niet verplaatst');
      expect(gsm().speeltIets, isTrue, reason: 'verder spelen vanaf daar kan nog');
      expect(speeltNu(ZoneStaat.fromJson(gsm().toJson()), nuMs: nu), isFalse, reason: 'ook op de andere toestellen');
      reg.speeltWeer('dev:gsm-1');
      expect(speeltNu(gsm(), nuMs: nu), isTrue);
      // Wie na een stop meer dan anderhalve seconde later zelf weer speelt, speelt gewoon.
      nu = DateTime.now().millisecondsSinceEpoch - 2000;
      reg.gestopt('dev:gsm-1');
      nu += 2000;
      staat.applyOps([melding('a')], deviceId: 'gsm-1', deviceName: 'Galaxy');
      expect(speeltNu(gsm(), nuMs: nu), isTrue);
    });
  });

  group('de pc', () {
    late Directory map;
    late LanServer server;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_zonekaart_srv_');
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await server.start(), isNull);
      server.bijZoneOpdracht = (op) async => null;
    });

    tearDown(() async {
      await server.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      map.deleteSync(recursive: true);
    });

    test('heet "Pc"; "stop" zet hem op "Speelt niets", "play" haalt dat weg; het stoppen na een overdracht niet', () async {
      final pc = 'dev:${server.zones.pcId}';
      ZoneStaat zone() => server.zones.lijst().firstWhere((z) => z.id == pc);
      expect(zone().naam, 'Pc', reason: 'Saber: "\'Pc\' in plaats van \'Saber\'"');
      server.state.applyOps([
        {'type': 'progress', 'trackId': 't1', 'positionMs': 0, 'queue': ['t1'], 'index': 0, 'playing': true,
          'at': DateTime.now().millisecondsSinceEpoch},
      ], deviceId: server.zones.pcId, deviceName: 'THUIS');
      expect(speeltNu(zone(), nuMs: server.zones.nu), isTrue);
      expect((await server.zoneOpdracht({'zone': pc, 'cmd': 'stop'}, van: 'Galaxy')).status, 200);
      expect(speeltNu(zone(), nuMs: server.zones.nu), isFalse);
      expect((await server.zoneOpdracht({'zone': pc, 'cmd': 'play'}, van: 'Galaxy')).status, 200);
      expect(speeltNu(zone(), nuMs: server.zones.nu), isTrue);
      await server.zoneOpdracht({'zone': pc, 'cmd': 'stop'}, van: 'overdracht');
      expect(zone().verplaatstOp, 0, reason: 'dat zet "Verplaatst naar …" zelf');
    });
  });

  group('het blad', () {
    tearDown(() {
      zoneKnoppenMetWoord = null;
      setTvModeForTest(false);
    });

    Future<({ZoneLijst lijst, List<(String, Map<String, dynamic>)> gestuurd, GekozenZone gekozen, List<(String, String)> verplaatst})> open(
        WidgetTester t, List<ZoneStaat> zones,
        {double breed = 400, double hoog = 900}) async {
      t.view.physicalSize = Size(breed, hoog);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final v = VerderLuisteren(_Bron(), klok: () => _nu);
      final gestuurd = <(String, Map<String, dynamic>)>[];
      final verplaatst = <(String, String)>[];
      final lijst = ZoneLijst(hier: 'dev:gsm-1', klok: () => _nu)
        ..zet({'nu': _nu, 'zones': [for (final z in zones) z.toJson()]})
        ..stuur = (zone, op) async {
          gestuurd.add((zone, op));
          return null;
        }
        ..verplaats = (van, naar) async {
          verplaatst.add((van, naar));
          return null;
        };
      final gekozen = GekozenZone(
        lijst: lijst,
        bewaar: (_) {},
        maak: (id) => ZoneSpeler(
            lijst: lijst, zoneId: id, nummer: v.bron.nummer, idVan: (t) => t.title, hoesVan: (_) => null, stuur: (_) async => null),
      );
      addTearDown(gekozen.dispose);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
          ChangeNotifierProvider<VerderLuisteren>.value(value: v),
          ChangeNotifierProvider<ZoneLijst>.value(value: lijst),
          ChangeNotifierProvider<GekozenZone>.value(value: gekozen),
        ],
        child: const MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: ZoneBlad()))),
      ));
      await t.pump(const Duration(milliseconds: 100));
      return (lijst: lijst, gestuurd: gestuurd, gekozen: gekozen, verplaatst: verplaatst);
    }

    final pc = _zone('dev:pc-THUIS', 'Pc', soort: ZoneSoort.pc, playing: true, trackId: 'b', volume: 55);
    final amp = _zone('spk:amp', 'Sonos Amp', soort: ZoneSoort.speaker, playing: true, trackId: 'c', volume: 30, via: 'Pc');
    final gsm = _zone('dev:gsm-1', 'Galaxy');
    final weg = _zone('dev:ipad-1', 'iPad', online: false);

    for (final breed in [360.0, 1920.0]) {
      testWidgets('op $breed breed: "Je bedient", de volgorde, de knoppen met een woordje, en geen "via"', (t) async {
        zoneKnoppenMetWoord = true;
        final o = await open(t, [weg, pc, amp, gsm], breed: breed, hoog: 2400);
        expect(find.textContaining('Je bedient: Galaxy · dit toestel', findRichText: true), findsOneWidget);
        final kaarten = [
          for (final id in ['dev:gsm-1', 'dev:pc-THUIS', 'spk:amp', 'dev:ipad-1'])
            t.getTopLeft(find.byKey(ValueKey('zone-kaart-$id'))).dy,
        ];
        expect([...kaarten]..sort(), kaarten, reason: 'dit toestel, dan wat speelt (op naam), dan wat weg is');
        final kaart = find.byKey(const ValueKey('zone-kaart-dev:pc-THUIS'));
        for (final w in ['Pauze', 'Stop', 'Hierheen', 'Daarheen', 'Samen']) {
          expect(find.descendant(of: kaart, matching: find.text(w)), findsOneWidget, reason: w);
        }
        expect(find.textContaining('via'), findsNothing);
        expect(find.byKey(const ValueKey('zone-volume-dev:pc-THUIS')), findsOneWidget);
        expect(find.byKey(const ValueKey('zone-volume-dev:gsm-1')), findsNothing, reason: 'hier speelt niets');
        expect(find.byKey(const ValueKey('zone-stop-dev:ipad-1')), findsNothing, reason: 'niet bereikbaar');
        expect(find.byKey(const ValueKey('zone-groep-dev:gsm-1')), findsNothing,
            reason: '"Samen" alleen waar iets speelt: op een lege zone is het ruis');
        expect(find.byKey(const ValueKey('zone-groep-dev:pc-THUIS')), findsOneWidget);

        await t.tap(find.text('Pauze').first);
        await t.pump();
        await t.tap(find.descendant(of: kaart, matching: find.text('Stop')));
        await t.pump();
        expect(o.gestuurd.map((g) => (g.$1, g.$2['cmd'])), [('dev:pc-THUIS', 'pause'), ('dev:pc-THUIS', 'stop')]);
        // "Hierheen" vanaf een speaker: de pc verplaatst zijn muziek naar dit toestel.
        await t.tap(find.descendant(of: find.byKey(const ValueKey('zone-kaart-spk:amp')), matching: find.text('Hierheen')));
        await t.pump();
        expect(o.verplaatst, [('spk:amp', 'dev:gsm-1')]);
        await t.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('een zone die net weg is: geen Pauze, Stop of volume (die komen niet aan), wel "Hierheen"', (t) async {
      zoneKnoppenMetWoord = true;
      final net = _zone('dev:ipad-1', 'iPad', online: false, trackId: 'b', opMs: _nu - 60000, volume: 40);
      await open(t, [net, gsm]);
      expect(find.byKey(const ValueKey('zone-pauze-dev:ipad-1')), findsNothing);
      expect(find.byKey(const ValueKey('zone-stop-dev:ipad-1')), findsNothing);
      expect(find.byKey(const ValueKey('zone-volume-dev:ipad-1')), findsNothing);
      expect(find.byKey(const ValueKey('zone-verder-dev:ipad-1')), findsOneWidget,
          reason: 'zijn laatste stand staat op de pc: overnemen kan');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('op pc en Mac een tip in plaats van een woordje', (t) async {
      zoneKnoppenMetWoord = false;
      await open(t, [pc, gsm], breed: 1920);
      expect(find.text('Pauze'), findsNothing);
      expect(find.byTooltip('Pauzeren'), findsOneWidget);
      expect(find.byTooltip('Hier verder spelen — Pc stopt'), findsOneWidget);
      expect(find.byTooltip('Naar een andere zone sturen …'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('de kaart die je bedient, licht op; kies je een andere, dan zegt de kop het', (t) async {
      zoneKnoppenMetWoord = true;
      final o = await open(t, [pc, gsm]);
      BoxBorder? rand(String id) =>
          ((t.widget<Container>(find.byKey(ValueKey('zone-kaart-$id')))).decoration as BoxDecoration).border;
      expect((rand('dev:gsm-1')! as Border).top.width, 1.5);
      expect((rand('dev:pc-THUIS')! as Border).top.width, 1);
      o.gekozen.kies('dev:pc-THUIS');
      await t.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Je bedient: Pc', findRichText: true), findsOneWidget);
      expect((rand('dev:pc-THUIS')! as Border).top.width, 1.5);
      // Terug naar dit toestel: de zone op afstand houdt anders een klok open.
      o.gekozen.kies('dev:gsm-1');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('de volumeschuif stuurt, en de laatste stand komt altijd aan', (t) async {
      zoneKnoppenMetWoord = true;
      final o = await open(t, [pc, gsm]);
      final schuif = find.descendant(of: find.byKey(const ValueKey('zone-volume-dev:pc-THUIS')), matching: find.byType(Slider));
      await t.drag(schuif, const Offset(-400, 0));
      await t.pump(const Duration(milliseconds: 400));
      final volumes = [for (final g in o.gestuurd) if (g.$2['cmd'] == 'volume') g];
      expect(volumes, isNotEmpty);
      expect(volumes.every((g) => g.$1 == 'dev:pc-THUIS'), isTrue);
      expect(volumes.last.$2['waarde'], 0, reason: 'helemaal naar links');
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('een groep: één kaart, per lid een schuif en "Los", en "Opheffen"', (t) async {
      zoneKnoppenMetWoord = true;
      final groep = _zone('spk:amp', 'Sonos Amp + Tv in woonkamer',
          soort: ZoneSoort.speaker,
          playing: true,
          trackId: 'c',
          volume: 30,
          leden: const [
            ZoneLid(id: 'spk:amp', naam: 'Sonos Amp', soort: ZoneSoort.speaker, volume: 30),
            ZoneLid(id: 'dev:shield', naam: 'Tv in woonkamer', soort: ZoneSoort.tv, volume: 70),
            ZoneLid(id: 'spk:move', naam: 'Sonos Move', soort: ZoneSoort.speaker, volume: 20),
          ]);
      final o = await open(t, [groep, gsm], breed: 360);
      expect(find.byKey(const ValueKey('zone-volume-spk:amp')), findsOneWidget, reason: 'de schuif van de groep');
      expect(find.byKey(const ValueKey('zone-lidvolume-dev:shield')), findsOneWidget);
      expect(find.byKey(const ValueKey('zone-lidvolume-spk:move')), findsOneWidget);
      expect(find.byKey(const ValueKey('zone-los-spk:amp')), findsNothing, reason: 'de leider gaat niet "los"');
      await t.ensureVisible(find.byKey(const ValueKey('zone-los-dev:shield')));
      await t.tap(find.byKey(const ValueKey('zone-los-dev:shield')));
      await t.pump();
      expect(o.gestuurd.last.$1, 'spk:amp');
      expect(o.gestuurd.last.$2, {'cmd': 'groepeer', 'leden': ['spk:move']});
      await t.ensureVisible(find.byKey(const ValueKey('zone-ophef-spk:amp')));
      await t.tap(find.byKey(const ValueKey('zone-ophef-spk:amp')));
      await t.pump();
      expect(o.gestuurd.last.$2, {'cmd': 'groepeer', 'leden': <String>[]});
      // De schuif van de groep zet elk lid even luid.
      o.gestuurd.clear();
      await t.drag(
          find.descendant(of: find.byKey(const ValueKey('zone-volume-spk:amp')), matching: find.byType(Slider)),
          const Offset(-400, 0));
      await t.pump(const Duration(milliseconds: 400));
      final laatste = {for (final g in o.gestuurd) if (g.$2['cmd'] == 'volume') g.$1: g.$2['waarde']};
      expect(laatste, {'spk:amp': 0, 'dev:shield': 0, 'spk:move': 0});
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('op de Shield: groter, en volume met − en + in plaats van een schuif', (t) async {
      setTvModeForTest(true);
      final o = await open(t, [pc, gsm], breed: 1920, hoog: 1080);
      final vol = find.byKey(const ValueKey('zone-volume-dev:pc-THUIS'));
      expect(find.descendant(of: vol, matching: find.byType(Slider)), findsNothing);
      await t.tap(find.descendant(of: vol, matching: find.byTooltip('Luider')));
      await t.pump();
      expect(o.gestuurd.single.$2, {'cmd': 'volume', 'waarde': 60});
      expect(find.text('Pauze'), findsOneWidget, reason: 'een tv is een aanraak-/afstandsscherm: met een woordje');
      await t.pump(const Duration(seconds: 4));
    });
  });
}
