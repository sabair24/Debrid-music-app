/// Ziet een iPad hetzelfde als de pc?
///
/// De meting gebeurt op de pc, want daar staan de bestanden. Een iPad of een gsm kent datzelfde
/// nummer onder een heel andere naam — `http://100.97.101.113:47820/stream/<id>.flac` in plaats van
/// `D:\...\track.flac` — en het oordeel is op die naam gesleuteld. Gaat er in die keten iets mis,
/// dan is het resultaat niet "een foutmelding" maar een Kwaliteit-lijst die "0 nummers" zegt terwijl
/// er achtentwintig staan. Dat is erger dan leeg: het liegt, en niets valt erover.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/paths.dart';

const _afgekapt = Echtheidsoordeel(
  bits: Bitdiepte.spreektNietTegen,
  boven: Bovenband.leeg,
  band: Bandbreedte.afgekapt,
  gebruikteBits: 24,
  afkapHz: 17656.25,
  wandDb: 54.226452640020476,
  vensters: 32,
);

TrackDto _dto({Map<String, dynamic>? echt}) => TrackDto(
      id: 'abc123',
      albumId: 'alb',
      artistId: 'art',
      title: 'Tous les mêmes',
      artistName: 'Stromae',
      albumTitle: 'Racine carrée',
      streamPath: '/stream/abc123.flac',
      ext: 'flac',
      echt: echt,
    );

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_lijn_');
    setAppDirForTest(scratch.path);
    resetEchtheidVoorTest();
    await laadEchtheid();
  });

  tearDown(() {
    resetEchtheidVoorTest();
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('het oordeel over de lijn', () {
    test('overleeft de reis heen en terug zonder een cijfer te verliezen', () {
      final heen = _dto(echt: _afgekapt.toJson());
      final terug = TrackDto.fromJson(jsonDecode(jsonEncode(heen.toJson())) as Map<String, dynamic>);

      final o = Echtheidsoordeel.fromJson(terug.echt!)!;
      expect(o.band, Bandbreedte.afgekapt);
      expect(o.boven, Bovenband.leeg);
      expect(o.gebruikteBits, 24);
      // Op de komma: de afkapfrequentie ordent de hele Kwaliteit-lijst, en een afgeronde waarde zou
      // de volgorde stilletjes veranderen tussen pc en tablet.
      expect(o.afkapHz, 17656.25);
      expect(o.wandDb, closeTo(54.2264526, 1e-6));
      expect(o.isNep, isTrue);
    });

    test('een ongemeten nummer stuurt het veld helemaal niet mee', () {
      // Bijna elk nummer is ongemeten bij een verse bibliotheek. Een `"echt": null` per nummer zou
      // bytes kosten zonder iets te zeggen — op zevenhonderd nummers telt dat aan.
      final j = _dto().toJson();
      expect(j.containsKey('echt'), isFalse);
      expect(TrackDto.fromJson(j).echt, isNull);
    });

    test('rommel in het veld maakt er geen oordeel van in plaats van te crashen', () {
      expect(TrackDto.fromJson({'id': 'x', 'echt': 'kapot'}).echt, isNull);
      expect(TrackDto.fromJson({'id': 'x', 'echt': 42}).echt, isNull);
      expect(TrackDto.fromJson({'id': 'x'}).echt, isNull);
    });
  });

  group('en wordt teruggevonden onder de naam die het nummer HIER heeft', () {
    test('op de stream-URL, niet op het pad van de pc', () {
      const url = 'http://100.97.101.113:47820/stream/abc123.flac';
      onthoudOordeelVanPc(url, _afgekapt);

      expect(gemeten(url), isNotNull, reason: 'hier zou het op een iPad stilvallen');
      expect(bewezenNep(url), isTrue);
      expect(waaromAfkap(gemeten(url)!), startsWith('harde afkap op 17.7 kHz'));

      // En het pad van de pc zegt hier niets — dat bestand bestaat op dit toestel niet.
      expect(gemeten(r'D:\flac music 2024\stromae\05 - tous les mêmes.flac'), isNull);
    });

    test('een oordeel van de pc wordt NIET op de schijf van de client bewaard', () async {
      // De pc is de eigenaar van deze getallen en meet opnieuw zodra er iets verandert. Een kopie op
      // een tablet zou verouderen, en dan blijft die een nummer beschuldigen dat allang vervangen is.
      onthoudOordeelVanPc('http://pc/stream/x.flac', _afgekapt);
      final bestand = File('${scratch.path}${Platform.pathSeparator}echtheid_oordelen.json');
      expect(bestand.existsSync(), isFalse,
          reason: 'de client hoort niets weg te schrijven van wat hij van de pc kreeg');
    });

    test('na een herstart is het weg — en dat hoort', () async {
      onthoudOordeelVanPc('http://pc/stream/y.flac', _afgekapt);
      expect(gemeten('http://pc/stream/y.flac'), isNotNull);
      resetEchtheidVoorTest();
      await laadEchtheid();
      expect(gemeten('http://pc/stream/y.flac'), isNull,
          reason: 'het komt bij de volgende catalogus gewoon opnieuw mee');
    });
  });
}
