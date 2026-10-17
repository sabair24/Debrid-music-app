/// "Hier verder luisteren" (Saber, 17-10-2026: "als music afspeelt op pc, en ik ga op men mac, gsm,
/// ipad of shield, dat die hervat waar ik zat").
///
/// Wat hier vastligt: wanneer de balk iets aanbiedt (van een ander toestel, niet als je zelf speelt,
/// tot een dag oud), wat er meegaat (wachtrij, plek, shuffle, herhalen), dat de bron pauzeert als een
/// ander toestel van haar overnam, dat "Speel op …" vanzelf overneemt, en dat de pc meldingen op zijn
/// eigen klok zet.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show RepeatMode;
import 'package:debridmusic/verder_luisteren.dart';

Track _t(String id) => Track(path: 'http://pc.invalid/stream/$id.flac', title: 'Nummer $id', artist: 'X', album: 'A');

final _bib = {for (final id in ['a', 'b', 'c', 'd']) id: _t(id)};

Map<String, dynamic> _stand({
  String trackId = 'b',
  List<String> rij = const ['a', 'b', 'c'],
  int index = 1,
  bool playing = true,
  int op = 1000000,
  String van = 'pc-THUIS',
  String naam = 'THUIS',
  int positie = 60000,
  String overname = '',
}) =>
    {
      'trackId': trackId,
      'positionMs': positie,
      'queue': rij,
      'index': index,
      'playing': playing,
      'updatedAt': op,
      'deviceId': van,
      'deviceName': naam,
      'shuffle': true,
      'repeat': 'all',
      if (overname.isNotEmpty) 'overname': overname,
    };

VerderAanbod? _aanbod(Map<String, dynamic>? p, {int nu = 1005000, bool ikSpeel = false, String mij = 'gsm-1'}) =>
    aanbodUit(p, mijnId: mij, nuMs: nu, ikSpeel: ikSpeel, nummer: (id) => _bib[id]);

class _Nep implements VerderBron {
  _Nep({this.speelt = false});

  bool speelt;
  Map<String, dynamic>? stand;
  Map<String, dynamic>? verzoek;
  int pauzes = 0;
  final gespeeld =
      <({List<Track> rij, int index, Duration positie, bool shuffle, RepeatMode herhaal, String? radio})>[];

  @override
  String get mijnId => 'gsm-1';

  @override
  bool get ikSpeel => speelt;

  @override
  Track? nummer(String id) => _bib[id];

  @override
  Future<({Map<String, dynamic>? stand, Map<String, dynamic>? verzoek})?> haal() async =>
      (stand: stand, verzoek: verzoek);

  @override
  Future<void> speel(List<Track> rij, int index, Duration positie,
      {required bool spelen, required bool shuffle, required RepeatMode herhaal, String? radioArtiest}) async {
    gespeeld.add((rij: rij, index: index, positie: positie, shuffle: shuffle, herhaal: herhaal, radio: radioArtiest));
    speelt = true;
  }

  @override
  void pauzeer() {
    pauzes++;
    speelt = false;
  }
}

void main() {
  group('wanneer de balk iets aanbiedt', () {
    test('een ander toestel speelt: "speelt op", met de hele rij, de plek, shuffle en herhalen', () {
      final a = _aanbod(_stand())!;
      expect(a.speelde, isTrue);
      expect(a.toestelNaam, 'THUIS');
      expect([for (final t in a.rij) t.path], [for (final id in ['a', 'b', 'c']) _bib[id]!.path]);
      expect(a.index, 1);
      expect(a.nummer, _bib['b']);
      expect(a.shuffle, isTrue);
      expect(a.herhaal, RepeatMode.all);
      // Het speelde door sinds de melding: vijf seconden verder.
      expect(startPositie(a, 1005000), const Duration(seconds: 65));
    });

    test('niet van jezelf, en niet als je zelf iets speelt', () {
      expect(_aanbod(_stand(van: 'gsm-1')), isNull);
      expect(_aanbod(_stand(), ikSpeel: true), isNull);
      expect(_aanbod(null), isNull);
      expect(_aanbod(_stand(trackId: '')), isNull);
    });

    test('gepauzeerd of al even stil: "verder waar je was", tot een dag oud', () {
      final stil = _aanbod(_stand(playing: false))!;
      expect(stil.speelde, isFalse);
      expect(startPositie(stil, 1005000), const Duration(seconds: 60), reason: 'gepauzeerd: niet doortellen');
      // "Speelt" maar al een minuut niets gehoord: dat toestel is weg; niet doortellen.
      final weg = _aanbod(_stand(), nu: 1000000 + 61000)!;
      expect(weg.speelde, isFalse);
      expect(_aanbod(_stand(playing: false), nu: 1000000 + 23 * 3600 * 1000), isNotNull);
      expect(_aanbod(_stand(playing: false), nu: 1000000 + 25 * 3600 * 1000), isNull, reason: 'na een dag niet meer');
    });

    test('ids die hier niet bestaan vallen uit de rij; het nummer zelf blijft het spelende', () {
      final a = _aanbod(_stand(rij: const ['x', 'a', 'y', 'b', 'c'], index: 3))!;
      expect([for (final t in a.rij) t.title], ['Nummer a', 'Nummer b', 'Nummer c']);
      expect(a.nummer, _bib['b']);
      // Klopt de rij niet met het nummer, dan alleen het nummer.
      final los = _aanbod(_stand(rij: const ['a', 'c'], index: 1))!;
      expect(los.rij, [_bib['b']]);
      // Bestaat het nummer hier niet, dan is er niets.
      expect(_aanbod(_stand(trackId: 'zz', rij: const ['zz'], index: 0)), isNull);
    });

    test('verder dan een minuut telt hij niet door', () {
      final a = _aanbod(_stand(), nu: 1000000 + 20000)!;
      expect(startPositie(a, 1000000 + 20000 + 90000), const Duration(seconds: 120));
    });
  });

  group('de bron pauzeert', () {
    test('alleen als een ander toestel van DIT toestel overnam, en één keer', () {
      final p = _stand(van: 'ipad-2', overname: 'gsm-1');
      expect(moetPauzeren(p, mijnId: 'gsm-1', ikSpeel: true), isTrue);
      expect(moetPauzeren(p, mijnId: 'gsm-1', ikSpeel: false), isFalse);
      expect(moetPauzeren(p, mijnId: 'pc-THUIS', ikSpeel: true), isFalse);
      expect(moetPauzeren(p, mijnId: 'gsm-1', ikSpeel: true, alGedaanOp: 1000000), isFalse);
      expect(moetPauzeren(_stand(van: 'ipad-2'), mijnId: 'gsm-1', ikSpeel: true), isFalse);
    });

    test('overnemen: speelt de rij op de plek, en de eerste melding noemt het toestel waarvan', () async {
      final n = _Nep();
      final v = VerderLuisteren(n, klok: () => 1005000);
      await v.opStand(_stand());
      expect(v.aanbod, isNotNull);
      await v.neemOver();
      expect(v.aanbod, isNull);
      expect(n.gespeeld.single.index, 1);
      expect(n.gespeeld.single.positie, const Duration(seconds: 65));
      expect(n.gespeeld.single.shuffle, isTrue);
      expect(n.gespeeld.single.herhaal, RepeatMode.all);
      expect(v.meldNu()?.overname, 'pc-THUIS', reason: 'zo weet de pc dat hij moet pauzeren');
      expect(v.meldNu()?.overname, isNull, reason: 'maar alleen de eerste keer');
    });

    test('pauzeren na een overname, en dan even niet melden', () async {
      var nu = 2000000;
      final n = _Nep(speelt: true);
      final v = VerderLuisteren(n, klok: () => nu);
      await v.opStand(_stand(van: 'ipad-2', overname: 'gsm-1', op: 1999000));
      expect(n.pauzes, 1);
      expect(v.meldNu(), isNull, reason: 'anders overschrijft "gepauzeerd hier" de stand van de iPad');
      nu += 7000;
      expect(v.meldNu(), isNotNull);
      // Dezelfde melding nog eens (de volgende keer kijken): niet nog eens pauzeren.
      n.speelt = true;
      await v.opStand(_stand(van: 'ipad-2', overname: 'gsm-1', op: 1999000));
      expect(n.pauzes, 1);
    });

    test('wegklikken: hetzelfde nummer van hetzelfde toestel komt niet terug', () async {
      final n = _Nep();
      final v = VerderLuisteren(n, klok: () => 1005000);
      await v.opStand(_stand());
      v.wijsAf();
      expect(v.aanbod, isNull);
      await v.opStand(_stand(positie: 70000));
      expect(v.aanbod, isNull);
      await v.opStand(_stand(trackId: 'c', index: 2));
      expect(v.aanbod, isNotNull, reason: 'een ander nummer wel');
    });

    test('zelf iets aanzetten haalt de balk weg', () async {
      final n = _Nep();
      final v = VerderLuisteren(n, klok: () => 1005000);
      await v.opStand(_stand());
      n.speelt = true;
      v.spelerVeranderd();
      expect(v.aanbod, isNull);
    });
  });

  group('de radio', () {
    test('een radio gaat mee: rond dezelfde artiest, met het nummer dat speelde eerst', () async {
      final n = _Nep();
      final v = VerderLuisteren(n, klok: () => 1005000);
      await v.opStand({
        ..._stand(rij: const ['b'], index: 0),
        'radio': {'artiest': "Destiny's Child", 'naam': "Radio Destiny's Child"},
      });
      expect(v.aanbod?.radioArtiest, "Destiny's Child");
      await v.neemOver();
      expect(n.gespeeld.single.radio, "Destiny's Child");
      expect(n.gespeeld.single.rij.single, _bib['b']);
    });

    test('een lege radio-artiest is geen radio', () {
      expect(_aanbod({..._stand(), 'radio': {'artiest': '  '}})!.radioArtiest, isNull);
    });
  });

  group('Speel op …', () {
    test('een verzoek voor dit toestel neemt vanzelf over, één keer en niet als het oud is', () async {
      final n = _Nep();
      final v = VerderLuisteren(n, klok: () => 1005000);
      final verzoek = {..._stand(), 'naar': 'gsm-1', 'at': 1004000};
      await v.opStand(null, verzoek: verzoek);
      expect(n.gespeeld, hasLength(1));
      expect(v.meldNu()?.overname, 'pc-THUIS');
      await v.opStand(null, verzoek: verzoek);
      expect(n.gespeeld, hasLength(1), reason: 'hetzelfde verzoek niet nog eens');
      expect(verzoekVoorMij({'naar': 'gsm-1', 'at': 1000}, mijnId: 'gsm-1', nuMs: 60000), isFalse,
          reason: 'een verzoek dat een halve minuut bleef liggen, voert niemand meer uit');
      expect(verzoekVoorMij({'naar': 'ipad-2', 'at': 1004000}, mijnId: 'gsm-1', nuMs: 1005000), isFalse);
    });
  });

  test('een alleen teruggezette stand wordt niet gemeld, op de pc en op een toestel', () {
    final hoofd = File('lib/main.dart').readAsStringSync();
    expect(hoofd, contains('      if (player.resumedPaused) return;\n'));
    expect(hoofd, contains('        if (c == null || player.resumedPaused) return;\n'));
  });

  group('de gedeelde staat op de pc', () {
    LanStateStore staat() => LanStateStore(File('${Directory.systemTemp.path}/verder_staat_${DateTime.now().microsecondsSinceEpoch}.json'));

    test('een melding draagt shuffle, herhalen en overname, op de klok van de pc', () {
      final s = staat();
      s.applyOps([
        {
          'type': 'progress',
          'trackId': 'b',
          'positionMs': 5000,
          'queue': ['a', 'b'],
          'index': 1,
          'playing': true,
          'shuffle': true,
          'repeat': 'one',
          'overname': 'pc-THUIS',
          // Een toestel met een klok die een uur achterloopt.
          'at': DateTime.now().millisecondsSinceEpoch - 3600 * 1000,
        }
      ], deviceId: 'gsm-1', deviceName: 'S26');
      final p = s.progress.toJson();
      expect(p['shuffle'], isTrue);
      expect(p['repeat'], 'one');
      expect(p['overname'], 'pc-THUIS');
      expect(p['deviceId'], 'gsm-1');
      expect((p['updatedAt'] as int) > DateTime.now().millisecondsSinceEpoch - 60000, isTrue,
          reason: 'een achterlopende klok werd stil genegeerd en kon dan nooit overnemen');
    });

    test('een verzoek staat in de stand, met de tijd van de pc', () {
      final s = staat();
      s.applyOps([
        {'type': 'verzoek', 'naar': 'gsm-1', 'trackId': 'b', 'queue': ['b'], 'index': 0, 'positionMs': 1000}
      ], deviceId: 'pc-THUIS', deviceName: 'THUIS');
      expect(s.verzoek?['naar'], 'gsm-1');
      expect(s.snapshot()['verzoek'], isNotNull);
      expect(s.verzoek?['at'], isA<int>());
    });
  });
}
