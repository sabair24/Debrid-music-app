// Waar het overzicht "Radio afsluiten" verschijnt. Saber, 23-10-2026: "die melding moet komen op de device die de radio
// begon", en op zijn vragen: waar je afsluit; vanzelf geëindigd = waar je startte; is dat toestel dicht, dan bij het
// volgende openen; nooit op de Shield (dan de gsm); niets te beslissen = een korte melding.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart' show SseEvent;
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart' show setAppDirForTest;
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiosessie.dart';
import 'package:debridmusic/radiovoorraad.dart' show Haalstand;
import 'package:debridmusic/zone_opdracht.dart';

class _Speler implements PlayerStore {
  final rij = <RadioItem>[];
  @override
  Future<List<RadioItem>> Function()? radioExtend;
  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;
  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;
  @override
  List<RadioItem> get radioQueue => rij;
  @override
  int get radioIndex => 0;
  @override
  bool get playing => true;
  @override
  bool get radioDroog => false;
  @override
  bool get wilVerder => false;
  @override
  Duration duration = Duration.zero;
  @override
  Duration get positieErgens => Duration.zero;
  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async => rij
    ..clear()
    ..addAll(items);
  @override
  void voegToeAanRadio(List<RadioItem> meer) => rij.addAll(meer);
  @override
  Future<bool> haalUitRadio(String pad) async => true;
  @override
  void addListener(void Function() listener) {}
  @override
  void removeListener(void Function() listener) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bron implements Radiobron {
  _Bron(this.tracks);
  final Map<String, Track> tracks;
  @override
  Future<String?> begin() async => null;
  @override
  void einde() {}
  @override
  void staak() {}
  @override
  Future<Track?> haal(Radioplek p) async => tracks[p.titel];
  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async => true;
}

Track _t(String titel) => Track(
    path: '${Directory.systemTemp.path}${Platform.pathSeparator}ovz - $titel.flac',
    title: titel,
    artist: 'Artiest $titel',
    album: '');

void main() {
  late Directory wortel;
  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_ovz_');
    setAppDirForTest(wortel.path);
  });
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Een radio die twee nummers ophaalde, op deze zone [hier], gestart door [door].
  Future<RadioBesturing> radio({String hier = 'dev:pc-THUIS', String? door, List<String>? elders}) async {
    final tracks = {'1': _t('1'), '2': _t('2')};
    final r = RadioBesturing(speler: _Speler(), bron: _Bron(tracks))..hier = hier;
    if (elders != null) {
      r.bijOverzichtElders = (s, doel) async {
        elders.add('$doel:${s.gehaald.length}');
        return true;
      };
    }
    await r.start([
      Radioplek(artiest: 'Zaad', titel: 'Zaad', eigen: _t('zaad'), zaad: true),
      Radioplek(artiest: 'Artiest 1', titel: '1'),
      Radioplek(artiest: 'Artiest 2', titel: '2'),
    ], door: door);
    for (var i = 0; i < 100 && r.plan.any((p) => p.stand == Haalstand.onderweg || p.stand == Haalstand.wacht); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      r.tikVoorToets();
    }
    return r;
  }

  group('waar het heen gaat', () {
    test('DE KERN: wie afsluit krijgt het — een ander toestel via de brievenbus, en hier dan niets', () async {
      final elders = <String>[];
      final r = await radio(elders: elders);
      r.stop(naar: 'dev:gsm-1');
      await Future<void>.delayed(Duration.zero);
      expect(elders, ['dev:gsm-1:2']);
      expect(r.openstaand, isNull, reason: 'niet ook hier');
      expect(File('${wortel.path}${Platform.pathSeparator}radio_sessie.json').existsSync(), isFalse,
          reason: 'en geen notitie die bij de volgende start hier opduikt');
    });

    test('afsluiten op dit toestel: hier, zoals altijd', () async {
      final elders = <String>[];
      final r = await radio(elders: elders);
      r.stop();
      expect(elders, isEmpty);
      expect(r.openstaand?.gehaald, hasLength(2));
    });

    test('vanzelf geëindigd (iets anders op de speaker): waar hij startte', () async {
      final elders = <String>[];
      final r = await radio(door: 'dev:ipad-1', elders: elders);
      expect(r.gestartDoor, 'dev:ipad-1');
      r.speler.bijRadioEinde!(const []);
      await Future<void>.delayed(Duration.zero);
      expect(elders, ['dev:ipad-1:2']);
    });

    test('een tv wordt de gsm — ook als de radio op de Shield zelf afgesloten wordt', () async {
      final elders = <String>[];
      final r = await radio(hier: 'dev:shield', elders: elders)
        ..richt = (doel) => doel == 'dev:shield' ? 'gsm' : doel;
      r.stop();
      await Future<void>.delayed(Duration.zero);
      expect(elders, ['gsm:2']);
      expect(r.openstaand, isNull);
    });

    test('lukt de brievenbus niet (geen verbinding), dan blijft het hier — liever dan nergens', () async {
      final r = await radio()
        ..bijOverzichtElders = (s, doel) async => false;
      r.stop(naar: 'dev:gsm-1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(r.openstaand?.gehaald, hasLength(2));
    });
  });

  group('de brievenbus op het doeltoestel', () {
    Map<String, dynamic> post(String voor, int at, {bool klaar = false, int nummers = 1}) => klaar
        ? {'klaar': true, 'at': at}
        : {
            'voor': voor,
            'at': at,
            'sessie': RadioSessie(naam: 'Sade', begonnenMs: at, gehaald: [
              for (var i = 0; i < nummers; i++) Gehaald(pad: 'D:\\x$i.flac', artiest: 'A', titel: 'T$i', id: 'id$i'),
            ]).toJson(),
          };

    test('het oudste voor dit toestel; "gsm" alleen op een gsm; afgehandeld en anderen niet', () {
      final bus = {
        'a': post('dev:ipad-1', 100),
        'b': post('dev:gsm-1', 300),
        'c': post('gsm', 200),
        'd': post('dev:gsm-1', 50, klaar: true),
      };
      expect(overzichtVoorHier(bus, hier: 'dev:gsm-1', isGsm: true)?.sleutel, 'c');
      expect(overzichtVoorHier(bus, hier: 'dev:gsm-1', isGsm: false)?.sleutel, 'b');
      expect(overzichtVoorHier(bus, hier: 'dev:mac', isGsm: false), isNull);
      expect(overzichtVoorHier(null, hier: 'dev:gsm-1', isGsm: true), isNull);
    });

    test('tonen, afhandelen, en wat niet weg kon gaat terug', () async {
      final r = RadioBesturing(speler: _Speler(), bron: _Bron(const {}));
      final gemeld = <String>[];
      r.bijOverzichtAfgehandeld = (sleutel, rest) => gemeld.add('$sleutel:${rest?.gehaald.length ?? 'klaar'}');
      final s = RadioSessie.fromJson(post('dev:gsm-1', 1, nummers: 2)['sessie'])!;
      expect(r.ontvangOverzicht(s, 'k1'), isTrue);
      expect(identical(r.openstaand, s), isTrue);
      // Een tweede kan pas na deze.
      final ander = RadioSessie.fromJson(post('dev:gsm-1', 2)['sessie'])!;
      expect(r.ontvangOverzicht(ander, 'k2'), isFalse);
      // Eén ging weg, één niet: die gaat terug in de brievenbus.
      await r.houdAlleen(s, (g) => g.titel == 'T1');
      expect(gemeld, ['k1:1']);
      await r.houdAlleen(s, (g) => false);
      expect(gemeld, ['k1:1', 'k1:klaar']);
      expect(r.openstaand, isNull);
      expect(r.ontvangOverzicht(ander, 'k2'), isTrue, reason: 'nu is er plaats');
      await r.vergeetOpenstaand();
      expect(gemeld.last, 'k2:klaar');
    });
  });

  group('de gedeelde staat', () {
    late Directory map;
    late LanStateStore staat;
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_ovz_staat_');
      staat = LanStateStore(File('${map.path}/state.json'));
    });
    tearDown(() async {
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    test('erin, afgehandeld, en een late op zet het niet terug; het seintje noemt voor wie', () async {
      final seintjes = <Object?>[];
      final sub = staat.changes.listen((e) => seintjes.add(e['overzichtVoor']));
      final sessie = RadioSessie(naam: 'Sade', begonnenMs: 1, gehaald: [const Gehaald(pad: 'p', artiest: 'a', titel: 't')]);
      staat.applyOps([
        {'type': 'radio.overzicht', 'key': 'k', 'voor': 'dev:gsm-1', 'sessie': sessie.toJson(), 'at': 10},
      ]);
      expect(staat.radioOverzichten['k']?['voor'], 'dev:gsm-1');
      expect(staat.snapshot()['radioOverzichten'], contains('k'));
      staat.applyOps([
        {'type': 'radio.overzicht.klaar', 'key': 'k', 'at': 20},
      ]);
      staat.applyOps([
        {'type': 'radio.overzicht', 'key': 'k', 'voor': 'dev:gsm-1', 'sessie': sessie.toJson(), 'at': 30},
      ]);
      expect(staat.radioOverzichten['k']?['klaar'], isTrue, reason: 'afgehandeld komt niet terug');
      await Future<void>.delayed(Duration.zero);
      expect(seintjes.first, ['dev:gsm-1']);
      await sub.cancel();
    });
  });

  group('over de lijn', () {
    late Directory map;
    late LanServer server;
    late RemoteClient c;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_ovz_lijn_');
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

    test('een overzicht voor de gsm: de gsm krijgt meteen een seintje over zijn zonelijn', () async {
      final events = <SseEvent>[];
      final sub = c.zoneStroom(toestel: 'gsm-1', naam: 'Galaxy S26').listen(events.add);
      for (var i = 0; i < 50 && server.zones.bereikbareToestellen().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final sessie = RadioSessie(naam: 'Sade', begonnenMs: 1, gehaald: [const Gehaald(pad: 'p', artiest: 'a', titel: 't')]);
      await c.ask('/api/state/ops', {
        'ops': [
          {'type': 'radio.overzicht', 'key': 'k', 'voor': 'gsm', 'sessie': sessie.toJson(), 'at': 10},
        ],
        'deviceId': 'shield',
      });
      for (var i = 0; i < 50 && !events.any((e) => e.event == 'cmd'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final cmd = jsonDecode(events.firstWhere((e) => e.event == 'cmd').data) as Map<String, dynamic>;
      expect(cmd['cmd'], 'radioOverzicht');
      await sub.cancel();
    });
  });

  test('het toestel: afsluiten vanaf een ander toestel zegt wie; een seintje laat kijken', () async {
    String? gesloten;
    var gekeken = 0;
    final u = ZoneUitvoerder(
      speler: _NepSpeelbron(),
      rij: _NepRij(),
      nummer: (_) => null,
      radioStop: ({String? door}) => gesloten = door,
      kijkInBrievenbus: () => gekeken++,
    );
    expect(await u.voerUit({'cmd': 'radioStop', 'door': 'dev:gsm-1'}), isNull);
    expect(gesloten, 'dev:gsm-1');
    expect(await u.voerUit({'cmd': 'radioOverzicht'}), isNull);
    expect(gekeken, 1);
  });

  test('de korte melding als er niets te beslissen valt', () {
    expect(radioSamenvatting(gehouden: 3, opgeruimd: 37), 'De radio haalde 40 nummers; 3 gehouden, 37 opgeruimd.');
    expect(radioSamenvatting(gehouden: 1, opgeruimd: 0), 'De radio haalde 1 nummer; 1 gehouden, 0 opgeruimd.');
    final s = RadioSessie(naam: '', begonnenMs: 1, opgeruimd: 5);
    expect(s.leeg, isTrue);
    expect(s.teMelden, isTrue, reason: 'alles onderweg opgeruimd: toch iets te melden');
    expect(RadioSessie.fromJson(s.toJson())?.opgeruimd, 5);
  });

  test('aangesloten: wie startte en wie afsloot reizen mee', () {
    final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(m, contains('radio.stop(naar: door.isEmpty ? null : door);'), reason: 'een speaker via de zone');
    expect(m, contains('if (radio.loopt) radio.stop(naar: door);'), reason: 'een toestel via zijn lijn');
    expect(m, contains("door: '\${op['door'] ?? ''}'.isEmpty ? null : '\${op['door']}');"), reason: 'een speakerradio');
    expect(m, contains('return soort == ZoneSoort.tv ? \'gsm\' : doel;'));
    expect(m, contains("toonUitBrievenbus((s['radioOverzichten'] as Map?)?.cast<String, dynamic>());"));
    expect(m, contains('if (vooraf.weg.isEmpty) {\n    kortGemeld(vooraf.blijft.length);'));
    final z = File('lib/zone_speler.dart').readAsStringSync();
    expect(z, contains("Future<void> radioStop() => _stuur('radioStop', {'door': lijst.hier});"));
    expect(z, contains("        'door': lijst.hier,"));
  });
}

class _NepSpeelbron implements Speelbron {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NepRij implements Rijbediening {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
