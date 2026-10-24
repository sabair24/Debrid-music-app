/// De zonekaart, stap 3 (Saber, 23-10-2026: "Op een spelende kaart: een bewegend geluidsicoon, 'Hierna: …', de bron
/// (radio, album, afspeellijst) en de kwaliteit (FLAC 24/96, en of er wordt omgezet)").
///
/// Wat hier vastligt:
/// - wat er hierna komt, zoals de speler verdergaat (ook bij herhalen);
/// - de bron, uit de wachtrij zelf: radio, afspeellijst (ook geschud), album, artiest, of "N nummers";
/// - de kwaliteit van het bestand, en naar welke maat de pc onderweg omzet;
/// - het register vult het in voor een toestel (dat meldt wat het ontvangt) en voor een speaker;
/// - de kaart toont het, met de balkjes, alleen op wat speelt.
library;

import 'dart:io';

import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show ZoneBlad, zoneKnoppenMetWoord;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show RepeatMode;
import 'package:debridmusic/verder_luisteren.dart';
import 'package:debridmusic/zone_lijst.dart';
import 'package:debridmusic/zone_speler.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

ZoneNummer? _nummer(String id) => switch (id) {
      'r1' || 'r2' || 'r3' => (titel: 'Nummer $id', artiest: 'Bryan Adams', album: 'Reckless', duurMs: 200000),
      's1' => (titel: 'Summer of 69', artiest: 'Bryan Adams', album: 'So Far So Good', duurMs: 200000),
      'x1' => (titel: 'Iets', artiest: 'Iemand', album: 'Anders', duurMs: 200000),
      _ => null,
    };

void main() {
  group('hierna', () {
    test('het volgende nummer; bij "één" hetzelfde, aan het eind bij "alles" weer het eerste', () {
      expect(volgendInRij(const ['a', 'b', 'c'], 0, 'off'), 'b');
      expect(volgendInRij(const ['a', 'b', 'c'], 2, 'off'), '', reason: 'aan het eind komt er niets');
      expect(volgendInRij(const ['a', 'b', 'c'], 2, 'all'), 'a');
      expect(volgendInRij(const ['a', 'b', 'c'], 1, 'one'), 'b');
      expect(volgendInRij(const [], 0, 'off'), '');
      expect(volgendInRij(const ['a'], 5, 'off'), '', reason: 'een plek buiten de rij');
    });
  });

  group('de bron', () {
    test('een radio, een album, een artiest, of "N nummers"', () {
      expect(bronVanRij(const ['r1', 'r2'], radio: 'Freak Out', nummer: _nummer), (soort: 'radio', naam: 'Freak Out'));
      expect(bronVanRij(const ['r1', 'r2', 'r3'], nummer: _nummer), (soort: 'album', naam: 'Reckless'));
      expect(bronVanRij(const ['r1', 's1'], nummer: _nummer), (soort: 'artiest', naam: 'Bryan Adams'));
      expect(bronVanRij(const ['r1', 'x1'], nummer: _nummer), (soort: 'wachtrij', naam: '2 nummers'));
      expect(bronVanRij(const ['r1'], nummer: _nummer), isNull, reason: 'één nummer zegt niets over waar het vandaan komt');
    });

    test('een afspeellijst, ook geschud — en die gaat voor het album', () {
      final lijsten = [(naam: 'Zomer', ids: const ['r1', 'r2', 'r3'])];
      expect(bronVanRij(const ['r3', 'r1', 'r2'], nummer: _nummer, lijsten: lijsten), (soort: 'afspeellijst', naam: 'Zomer'));
      expect(bronVanRij(const ['r1', 'x1'], nummer: _nummer, lijsten: lijsten), (soort: 'wachtrij', naam: '2 nummers'),
          reason: 'een nummer dat niet in de lijst staat: niet die lijst');
    });
  });

  group('de kwaliteit', () {
    test('het bestand, en of er onderweg omgezet wordt', () {
      expect(kwaliteitLabel(ext: 'flac', rate: 96000, bits: 24), 'FLAC 24/96');
      expect(kwaliteitLabel(ext: 'flac', rate: 44100, bits: 16), 'FLAC 16/44.1');
      expect(kwaliteitLabel(ext: 'mp3', rate: 44100, bits: 16), 'MP3');
      expect(kwaliteitLabel(ext: ''), '');
      expect(omgezetNaar(bestandRate: 96000, bestandBits: 24, stroomRate: 44100, stroomBits: 16), '16/44.1');
      expect(omgezetNaar(bestandRate: 96000, bestandBits: 24, stroomRate: 48000, stroomBits: 0), '24/48',
          reason: 'zonder diepte blijft die van het bestand');
      expect(omgezetNaar(bestandRate: 44100, bestandBits: 16, stroomRate: 48000, stroomBits: 24), '',
          reason: 'een grens boven het bestand: het origineel');
      expect(omgezetNaar(bestandRate: 96000, bestandBits: 24, stroomRate: 0, stroomBits: 0), '');
    });

    test('de regel op de kaart', () {
      ZoneStaat z(Map<String, dynamic> extra) =>
          ZoneStaat.fromJson({'id': 'dev:a', 'soort': 'gsm', 'naam': 'A', ...extra});
      expect(zoneBronRegel(z({'bronSoort': 'album', 'bronNaam': 'Reckless', 'kwaliteit': 'FLAC 16/44.1'})),
          'Album: Reckless · FLAC 16/44.1');
      expect(zoneBronRegel(z({'bronSoort': 'radio', 'bronNaam': 'Freak Out', 'kwaliteit': 'FLAC 24/96', 'omgezet': '16/44.1'})),
          'Radio: Freak Out · FLAC 24/96, omgezet naar 16/44.1');
      expect(zoneBronRegel(z({})), '');
    });
  });

  group('het register', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;
    final nu = DateTime.now().millisecondsSinceEpoch;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_zoneinfo_');
      staat = LanStateStore(File('${map.path}/state.json'));
      reg = ZoneRegister(
        state: staat,
        pcId: 'pc-THUIS',
        pcNaam: 'Pc',
        nummer: _nummer,
        bestandVan: (id) => (ext: 'flac', rate: 96000, bits: 24),
        klok: () => nu,
      );
    });

    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    test('DE KERN: een toestel — hierna, de bron, de kwaliteit, en dat het omgezet krijgt', () {
      reg.stroomOpen('gsm-1', naam: 'Galaxy', soort: ZoneSoort.gsm);
      staat.applyOps([
        {
          'type': 'progress', 'trackId': 'r1', 'positionMs': 0, 'queue': ['r1', 'r2', 'r3'], 'index': 0,
          'playing': true, 'at': nu, 'stroom': {'rate': 44100, 'bits': 16},
        }
      ], deviceId: 'gsm-1', deviceName: 'Galaxy');
      final z = reg.lijst().firstWhere((x) => x.id == 'dev:gsm-1');
      expect(z.hierna, 'Nummer r2 — Bryan Adams');
      expect((z.bronSoort, z.bronNaam), ('album', 'Reckless'));
      expect(z.kwaliteit, 'FLAC 24/96');
      expect(z.omgezet, '16/44.1');
      expect(ZoneStaat.fromJson(z.toJson()), z, reason: 'zo gaat het naar de andere toestellen');
    });

    test('DE GRENS: zonder melding van de stroom is het het origineel; een oud toestel meldt het niet', () {
      reg.stroomOpen('gsm-1', naam: 'Galaxy', soort: ZoneSoort.gsm);
      staat.applyOps([
        {'type': 'progress', 'trackId': 'r1', 'positionMs': 0, 'queue': ['r1'], 'index': 0, 'playing': true, 'at': nu},
      ], deviceId: 'gsm-1', deviceName: 'Galaxy');
      final z = reg.lijst().firstWhere((x) => x.id == 'dev:gsm-1');
      expect(z.omgezet, '');
      expect(z.hierna, '', reason: 'het laatste nummer');
      expect(z.bronSoort, '', reason: 'één nummer zegt niets over de bron');
    });

    test('een speaker: zijn rij van de pc, en de omzetting van de pc', () {
      reg.speakerRij = (id) => (rij: const ['r1', 'r2'], index: 0);
      reg.omzettingOpSpeaker = (speaker, trackId) => '24/48';
      reg.zetSpeakers([
        (id: 'amp', naam: 'Sonos Amp', trackId: 'r1', index: 0, lengte: 2, speelt: true, positieMs: 0, duurMs: 0, opMs: nu, volume: 30, radio: ''),
      ], bekend: [(id: 'amp', naam: 'Sonos Amp', sonos: true)]);
      final z = reg.lijst().firstWhere((x) => x.id == 'spk:amp');
      expect(z.hierna, 'Nummer r2 — Bryan Adams');
      expect((z.bronSoort, z.bronNaam), ('album', 'Reckless'));
      expect(z.omgezet, '24/48');
    });
  });

  group('de kaart', () {
    tearDown(() => zoneKnoppenMetWoord = null);

    testWidgets('wat speelt: de balkjes, de bron en de kwaliteit, en hierna; wat niet speelt: niets daarvan', (t) async {
      t.view.physicalSize = const Size(400, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      zoneKnoppenMetWoord = true;
      const klok = 1000000;
      final v = VerderLuisteren(_Bron(), klok: () => klok);
      final speelt = ZoneStaat.fromJson({
        'id': 'dev:pc-THUIS', 'soort': 'pc', 'naam': 'Pc', 'online': true, 'playing': true, 'trackId': 'b',
        'positionMs': 1000, 'durationMs': 200000, 'opMs': klok - 1000, 'index': 0, 'lengte': 3,
        'hierna': 'Heaven — Bryan Adams', 'bronSoort': 'album', 'bronNaam': 'Reckless', 'kwaliteit': 'FLAC 24/96',
        'omgezet': '16/44.1',
      });
      final stil = ZoneStaat.fromJson({'id': 'dev:gsm-1', 'soort': 'gsm', 'naam': 'Galaxy', 'online': true});
      final lijst = ZoneLijst(hier: 'dev:gsm-1', klok: () => klok)
        ..zet({'nu': klok, 'zones': [speelt.toJson(), stil.toJson()]});
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
        child: const MaterialApp(home: Scaffold(body: ZoneBlad())),
      ));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Album: Reckless · FLAC 24/96, omgezet naar 16/44.1'), findsOneWidget);
      expect(find.text('Hierna: Heaven — Bryan Adams'), findsOneWidget);
      expect(find.byKey(const ValueKey('zone-balkjes-dev:pc-THUIS')), findsOneWidget);
      expect(find.byKey(const ValueKey('zone-balkjes-dev:gsm-1')), findsNothing);
      expect(find.byKey(const ValueKey('zone-hierna-dev:gsm-1')), findsNothing);
      await t.pump(const Duration(seconds: 1));
    });

    test('het toestel meldt wat het ontvangt', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains("if (player.stroomGrens case final g?) 'stroom': {'rate': g.rate, 'bits': g.bits},"));
    });
  });
}

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
