/// Alle shuffles op alle toestellen houden rekening met elkaar (Saber, 31-10-2026: "ik wil dat alle shuffle sessies, op
/// elk apparaat met elkaar rekening houden, om zo de kans om zelfde liedjes die afspelen te vermijden").
///
/// Gemeten in schud.log (25–30 okt): van 487 geopende nummers kwam er binnen drie dagen 85 keer een terug, 47 keer op een
/// ander toestel — vooral wat je oversloeg, want dat wist alleen het toestel zelf. Keuzes: drie dagen weg, overslaan
/// telt even zwaar (niet als beluisterd), en lopende shuffles schuiven meteen mee.
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart' show naarAchterIds;
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/cloud/device_identity.dart'
    show deviceName, setBewaardeNaamForTest, setPlatformDeviceNameForTest;
import 'package:debridmusic/player.dart'
    show Wachtrij, klaarstaandNaarAchteren, klaarstaandWeg, naarAchterenLijst, ordenVoor, recentGeopendInRij, schudIdsGewogen;
import 'package:debridmusic/schudvolgorde.dart';
import 'package:debridmusic/speelstanden.dart';
import 'package:debridmusic/verder_luisteren.dart' show overgenomenVanMij;

Track _t(int i) => Track(path: 'n$i.flac', title: 'Nummer $i', artist: 'Artiest ${i % 37}', album: 'Plaat ${i % 53}',
    trackNo: 1, isFlac: true);

String _bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

const _dag = 24 * 3600 * 1000;

void main() {
  group('drie dagen weg', () {
    const nu = 1761900000000;
    test('binnen drie dagen geopend: bijna niets; daarna, of nooit: gewoon', () {
      expect(recentFactor(nu - 60 * 1000, nuMs: nu), kRecentGewicht);
      expect(recentFactor(nu - 3 * _dag + 1000, nuMs: nu), kRecentGewicht);
      expect(recentFactor(nu - 3 * _dag, nuMs: nu), 1);
      expect(recentFactor(null, nuMs: nu), 1);
      expect(recentFactor(0, nuMs: nu), 1);
      // Een toestel waarvan de klok voorloopt: "net", niet "nooit".
      expect(recentFactor(nu + 5000, nuMs: nu), kRecentGewicht);
    });

    test('DE KERN: wat elders opende, komt in een nieuwe shuffle bijna nooit vooraan — maar het komt wel', () {
      final alles = [for (var i = 0; i < 300; i++) _t(i)];
      final recent = {for (var i = 0; i < 30; i++) alles[i * 10].path: nu - 3600 * 1000};
      var vooraanMet = 0, vooraanZonder = 0;
      for (var zaad = 0; zaad < 50; zaad++) {
        final met = ordenVoor(alles, null,
                shuffle: true, gewicht: (t) => recentFactor(recent[t.path], nuMs: nu), toeval: Random(zaad))
            .order;
        final zonder = ordenVoor(alles, null, shuffle: true, gewicht: (t) => 1, toeval: Random(zaad)).order;
        expect(met.length, 300);
        expect({for (final t in met) t.path}.length, 300, reason: 'elk nummer precies één keer');
        vooraanMet += met.take(100).where((t) => recent.containsKey(t.path)).length;
        vooraanZonder += zonder.take(100).where((t) => recent.containsKey(t.path)).length;
      }
      // Gemeten (zaden 0–49): zonder 485 (9,7 per shuffle, verwacht 30 × 100/300 = 10), met 28 (0,56 per shuffle).
      expect(vooraanZonder, greaterThan(400));
      expect(vooraanMet, lessThan(60));
    });

    test('de speler weegt het mee, naast hoe vaak je het hoorde en je duim', () {
      final s = _bron('lib/player.dart');
      expect(s, contains('    if (lees == null && duim == null && recent == null) return null;\n'));
      expect(s, contains('      if (recent != null) basis *= recentFactor(recent(t), nuMs: nu);\n'));
      expect(s, contains('      _geopendDezeSessie.add(t.path);\n'
          '      _geopendHierOp[t.path] = DateTime.now().millisecondsSinceEpoch;\n      bijGeopend?.call(t);\n'));
    });
  });

  group('lopende shuffles schuiven mee', () {
    final rij = [for (var i = 0; i < 8; i++) _t(i)];
    Wachtrij w(int index) => (origineel: rij, volgorde: rij, index: index);

    test('wat elders opende en hier nog komt, gaat achteraan — in dezelfde volgorde', () {
      final uit = naarAchterenLijst(w(2), {'n4.flac', 'n3.flac'});
      expect([for (final t in uit.volgorde) t.title.split(' ').last], ['0', '1', '2', '5', '6', '7', '3', '4']);
      expect(uit.index, 2, reason: 'het spelende nummer blijft waar het is');
      expect(identical(uit.origineel, rij), isTrue, reason: 'de albumvolgorde verandert niet');
    });

    test('wat al klonk of nu speelt, blijft staan; niets te doen = dezelfde rij', () {
      expect(identical(naarAchterenLijst(w(4), {'n1.flac', 'n4.flac'}).volgorde, rij), isTrue);
      expect(identical(naarAchterenLijst(w(2), {'n7.flac'}).volgorde, rij), isTrue, reason: 'stond al achteraan');
      expect(identical(naarAchterenLijst(w(2), const {}).volgorde, rij), isTrue);
    });

    test('een speaker: het volgende nummer heeft hij al, dat blijft', () {
      final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      expect(naarAchterIds(ids, 1, 'c'), isNull, reason: 'c is het volgende (SetNextAVTransportURI)');
      expect(naarAchterIds(ids, 1, 'd'), ['a', 'b', 'c', 'e', 'f', 'd']);
      expect(naarAchterIds(ids, 1, 'f'), isNull, reason: 'stond al achteraan');
      expect(naarAchterIds(ids, 1, 'x'), isNull);
      expect(naarAchterIds(ids, 0, 'a'), isNull, reason: 'speelt nu');
    });

    test('"Shuffle alles" naar een speaker: dezelfde nummers, gewogen, onbekende achteraan', () {
      final alles = [for (var i = 0; i < 200; i++) _t(i)];
      final perId = {for (var i = 0; i < 200; i++) 'id$i': alles[i]};
      final ids = [...perId.keys, 'onbekend'];
      final recent = {for (var i = 0; i < 20; i++) 'n$i.flac'};
      var vooraan = 0;
      for (var zaad = 0; zaad < 20; zaad++) {
        final uit = schudIdsGewogen(ids,
            nummer: (id) => perId[id], gewicht: (t) => recent.contains(t.path) ? kRecentGewicht : 1, toeval: Random(zaad));
        expect(uit.toSet(), ids.toSet());
        expect(uit.length, ids.length);
        expect(uit.last, 'onbekend');
        vooraan += uit.take(50).where((id) => recent.contains(perId[id]?.path)).length;
      }
      // Zonder weging verwacht 20 × 50/200 = 5 per shuffle (100 over 20); gemeten met de weging: 5 over 20.
      expect(vooraan, lessThan(20));
    });
  });

  group('de gedeelde staat op de pc', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_schud_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });
    LanStateStore winkel() => LanStateStore(File('${map.path}${Platform.pathSeparator}state.json'));

    test('"opened" onthoudt wanneer en waar, telt niet als beluisterd, en meldt het meteen', () async {
      final w = winkel();
      final gemeld = <String>[];
      final sub = w.geopendNu.listen((g) => gemeld.add('${g.trackId}@${g.dev}'));
      final nu = DateTime.now().millisecondsSinceEpoch;
      w.applyOps([
        {'type': 'opened', 'trackId': 'x', 'at': nu - 1000}
      ], deviceId: 'gsm1');
      w.applyOps([
        {'type': 'opened', 'trackId': 'x', 'at': nu - 5000}
      ], deviceId: 'tv');
      await Future<void>.delayed(Duration.zero);
      expect(w.geopend['x'], {'at': nu - 1000, 'dev': 'gsm1'}, reason: 'een oudere melding zet het niet terug');
      expect(w.plays['x'], isNull, reason: 'overslaan is geen beluisteren');
      expect(gemeld, ['x@gsm1', 'x@tv']);
      expect((w.snapshot()['geopend'] as Map)['x'], isNotNull);
      await sub.cancel();
    });

    test('ouder dan drie dagen valt eruit, ook na een herstart', () async {
      final w = winkel();
      final nu = DateTime.now().millisecondsSinceEpoch;
      w.applyOps([
        {'type': 'opened', 'trackId': 'oud', 'at': nu - 4 * _dag},
        {'type': 'opened', 'trackId': 'vers', 'at': nu - _dag},
      ]);
      expect(w.geopend.keys, ['vers']);
      await w.save();
      final terug = winkel();
      await terug.load();
      expect(terug.geopend.keys, ['vers']);
    });

    test('een state.json van een week geleden: bij het inlezen al gesnoeid', () async {
      final nu = DateTime.now().millisecondsSinceEpoch;
      File('${map.path}${Platform.pathSeparator}state.json').writeAsStringSync(
          '{"rev":3,"geopend":{"oud":{"at":${nu - 5 * _dag},"dev":"tv"},"vers":{"at":${nu - 3600000},"dev":"gsm"}}}');
      final w = winkel();
      await w.load();
      expect(w.geopend.keys, ['vers']);
      expect(w.geopend['vers']?['dev'], 'gsm');
    });
  });

  group('een toestel', () {
    test('meldt wat hier opent, weet het zelf meteen, en neemt over wat elders opende', () async {
      final verstuurd = <Map<String, dynamic>>[];
      final s = Speelstanden()
        ..idVanPad = ((p) => p.replaceAll('.flac', ''))
        ..duwOps = (ops) async => verstuurd.addAll(ops);
      await s.geopend(_t(1));
      expect(verstuurd.single['type'], 'opened');
      expect(verstuurd.single['trackId'], 'n1');
      expect(s.geopendOp(_t(1)), verstuurd.single['at']);

      s.elders('n2', 500);
      s.vanServerGeopend({
        'n2': {'at': 400, 'dev': 'tv'},
        'n3': {'at': 900, 'dev': 'pc'},
      });
      expect(s.geopendOp(_t(2)), 500, reason: 'de lijn was nieuwer dan het antwoord');
      expect(s.geopendOp(_t(3)), 900);
      expect(s.geopendOp(_t(4)), isNull);
    });

    test('geen pc: hier weet hij het toch', () async {
      final s = Speelstanden()
        ..idVanPad = ((p) => p.replaceAll('.flac', ''))
        ..duwOps = (_) async => throw 'pc onbereikbaar';
      await s.geopend(_t(5));
      expect(s.geopendOp(_t(5)), isNotNull);
    });
  });

  test('aangesloten: de pc zegt het over de zonelijnen, en elk toestel en elke speaker doet mee', () {
    final server = _bron('lib/lan/server.dart');
    expect(server, contains("          l('geopend', {'trackId': g.trackId, 'dev': g.dev, 'at': g.at});\n"));
    expect(server, contains('                final uit = f(ids);\n'));
    expect(server, contains('alsZone: true, geschud: geschud);'));
    expect(_bron('lib/zone_lijst.dart'), contains("          case 'geopend':\n            opGeopend?.call("));
    final cast = _bron('lib/lan/cast_manager.dart');
    expect(cast, contains('      if (s.zagIndex != s.index && s.alsZone) {\n'));
    expect(cast, contains("if (s.geschud) 'geschud': true}"));
    expect(cast, contains("..geschud = e['geschud'] == true;"));
    final hoofd = _bron('lib/main.dart');
    expect(hoofd, contains('  player.geopendOp = speelstanden.geopendOp;\n'));
    expect(hoofd, contains('  player.bijGeopend = (t) => unawaited(speelstanden.geopend(t));\n'));
    expect(hoofd, contains('          speelstanden.vanServerGeopend(\n'));
    // Eigen melding herkend aan dezelfde id die de pc in `dev` zet (`ik.id`). Niet settings.serverId: die is op een
    // toestel leeg, en dan gooide elk toestel ook de meldingen van de andere weg (31-10-2026: 49 van 50 met dev '').
    expect(hoofd, contains("          'deviceId': ik?.id ?? settings.serverId,\n"));
    expect(hoofd, contains('          if (dev == ik.id) return;\n          speelstanden.elders(id, at);\n'
        '          if (samenVolger.volgt) return;\n'));
    expect(hoofd, contains('    sharing.state.geopendNu.listen((g) {\n'));
    expect(hoofd, contains("          ], deviceId: 'spk:\$speaker');\n"));
    expect(hoofd, contains('      s.schudIds = (ids) => schudIdsGewogen(ids, nummer: verder.bron.nummer, gewicht: player.schudGewicht);\n'));
  });

  // Saber, 03-11-2026, na het schudlogboek: "Geheugen op de gsm", "Altijd de juiste naam", "Ook het klaarstaande nummer".
  group('het klaarstaande nummer', () {
    const uur = 3600000;
    const nu = 100 * uur;
    test('opende het intussen elders, dan naar achteren — maar niet als het hier al speelt of lang geleden was', () {
      expect(klaarstaandWeg(geopendOp: nu - uur, hierOp: nu - 2 * uur, plek: Duration.zero, nuMs: nu), isTrue,
          reason: 'de Shield sloeg Rehab over nadat de gsm het klaarzette');
      expect(klaarstaandWeg(geopendOp: nu - 2 * uur, hierOp: nu - 2 * uur, plek: Duration.zero, nuMs: nu), isFalse,
          reason: 'alleen hier geopend: gewoon verder');
      expect(klaarstaandWeg(geopendOp: nu - uur, hierOp: null, plek: Duration.zero, nuMs: nu), isTrue,
          reason: 'na een herstart: binnen drie dagen ergens geopend');
      expect(klaarstaandWeg(geopendOp: nu - uur, hierOp: null, plek: const Duration(seconds: 30), nuMs: nu), isFalse,
          reason: 'al begonnen: verder waar je was');
      expect(klaarstaandWeg(geopendOp: nu - 80 * uur, hierOp: null, plek: Duration.zero, nuMs: nu), isFalse,
          reason: 'ouder dan drie dagen');
      expect(klaarstaandWeg(geopendOp: null, hierOp: null, plek: Duration.zero, nuMs: nu), isFalse);
    });

    test('het klaarstaande nummer gaat achteraan, het volgende staat klaar', () {
      final a = Track(path: 'a', title: 'A', artist: 'x', album: '');
      final b = Track(path: 'b', title: 'B', artist: 'y', album: '');
      final c = Track(path: 'c', title: 'C', artist: 'z', album: '');
      final w = klaarstaandNaarAchteren((origineel: [a, b, c], volgorde: [a, b, c], index: 1));
      expect([for (final t in w.volgorde) t.path], ['a', 'c', 'b']);
      expect(w.index, 1);
      final laatste = (origineel: [a, b], volgorde: [a, b], index: 1);
      expect(identical(klaarstaandNaarAchteren(laatste), laatste), isTrue, reason: 'er komt niets na: laten staan');
    });

    test('aangesloten: bij verder spelen en na een herstart', () {
      final speler = File('lib/player.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(speler, contains('    if (!playing && _klaarstaandElders()) {\n      unawaited(_openCurrent());\n'));
      final h = speler.indexOf('  Future<void> restore(');
      final herstart = speler.substring(h, h + 4000);
      expect(herstart.indexOf('klaarstaandWeg('), greaterThan(0));
      expect(herstart.indexOf('klaarstaandWeg('), lessThan(herstart.indexOf('      _nieuwVoorDeTelling(t);')),
          reason: 'vóór het melden als geopend, anders telt de herstart zelf als "elders geopend"');
    });
  });

  group('geheugen op de gsm', () {
    late Directory krab;
    setUp(() => krab = Directory.systemTemp.createTempSync('dm_speelstanden_'));
    tearDown(() {
      try {
        krab.deleteSync(recursive: true);
      } catch (_) {}
    });

    Speelstanden nieuw() => Speelstanden()
      ..idVanPad = ((p) => p)
      ..bestand = '${krab.path}${Platform.pathSeparator}speelstanden_hier.json'
      ..bewaarNa = Duration.zero;
    final t = Track(path: 'id1', title: 'Rehab', artist: 'Amy Winehouse', album: '');

    test('wat de pc gaf en wat ergens opende, overleeft een herstart zonder pc', () async {
      final s = nieuw();
      s.vanServer({
        'id1': {'count': 3, 'lastPlayedMs': 1000}
      });
      s.elders('id1', DateTime.now().millisecondsSinceEpoch);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final na = nieuw();
      await na.laad();
      expect(na.standVan(t)?.aantal, 3);
      expect(na.geopendOp(t), isNotNull, reason: 'anders weet een shuffle zonder pc niet wat net klonk');
    });

    test('geen pc: wat hier klonk telt toch, en blijft bewaard', () async {
      final s = nieuw()..duwOps = (ops) async => throw 'geen pc';
      await s.meld(t);
      expect(s.standVan(t)?.aantal, 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final na = nieuw();
      await na.laad();
      expect(na.standVan(t)?.aantal, 1);
      na.vanServer({
        'id1': {'count': 1, 'lastPlayedMs': DateTime.now().millisecondsSinceEpoch + 1000}
      });
      expect(na.standVan(t)?.aantal, 1, reason: 'weet de pc het zelf, dan niet dubbel tellen');
    });

    test('de gsm heet zoals Android de vorige keer zei, ook als het kanaal zwijgt', () {
      setPlatformDeviceNameForTest(null);
      setBewaardeNaamForTest('Saber ultra 26');
      expect(deviceName(), 'Saber ultra 26');
      setBewaardeNaamForTest(null);
      expect(deviceName(), isNot('Saber ultra 26'));
      final id = File('lib/cloud/device_identity.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(id, contains('            await _naamBestand.writeAsString(trimmed);\n'));
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains("    speelstanden.bestand = '\$appDir\${Platform.pathSeparator}speelstanden_hier.json';\n"
          '    await speelstanden.laad();\n'));
    });
  });

  // Gemeten 06-11-2026 in schud.log: sinds 3.9.709 kwam 5 % terug binnen drie dagen (was 15 %), 15 keer op een ander
  // toestel. 8 daarvan: de pc speelde of sloeg het over terwijl de app op de gsm dicht was. 1: de Shield nam No Scrubs
  // over, en de gsm speelde het later nog eens verder. Saber: "ja doe maar".
  group('na een herstart en na een overname', () {
    const nu = 1762450000000;
    const min = 60 * 1000;

    test('wat nog komt en de laatste drie dagen ergens opende — niet wat al klonk of nu speelt', () {
      final rij = [for (var i = 0; i < 8; i++) _t(i)];
      final op = <String, int>{
        'n1.flac': nu - 5 * min, // klonk al in deze shuffle
        'n2.flac': nu - 5 * min, // staat klaar
        'n4.flac': nu - 10 * min,
        'n5.flac': 0,
        'n6.flac': nu - 3 * _dag + 1000,
        'n7.flac': nu - 3 * _dag, // precies drie dagen: niet meer
      };
      final w = (origineel: rij, volgorde: rij, index: 2);
      expect(recentGeopendInRij(w, (t) => op[t.path], nuMs: nu), {'n4.flac', 'n6.flac'});
      expect(recentGeopendInRij((origineel: rij, volgorde: rij, index: 7), (t) => op[t.path], nuMs: nu), isEmpty);
    });

    test('DE KERN: de gsm gaat na een herstart verder, en wat de pc net oversloeg komt achteraan', () {
      // 05-11: de pc sloeg om 17:45–17:51 Kalemba, Enrique Iglesias en P!nk over; de gsm ging om 17:55 verder vanaf plek
      // 533, met Kalemba op 537, Enrique op 557 en P!nk op 595.
      final rij = [for (var i = 0; i < 700; i++) _t(i)];
      final op = {'n537.flac': nu - 10 * min, 'n557.flac': nu - 4 * min, 'n595.flac': nu - 10 * min};
      final w = (origineel: rij, volgorde: rij, index: 533);
      final uit = naarAchterenLijst(w, recentGeopendInRij(w, (t) => op[t.path], nuMs: nu));
      final na = [for (final t in uit.volgorde) t.path];
      expect(na.take(537), [for (var i = 0; i < 537; i++) 'n$i.flac'], reason: 'wat klonk en wat klaarstaat, blijft');
      expect(na[537], 'n538.flac', reason: 'Kalemba is weg uit de volgende nummers');
      expect(na.skip(697), ['n537.flac', 'n557.flac', 'n595.flac'], reason: 'achteraan, niet weg');
      expect(na.toSet().length, 700, reason: 'elk nummer één keer');
      expect(uit.index, 533);
    });

    test('een overname: alleen als een ander toestel van HIER overnam, ook als hier niets meer speelde, één keer', () {
      final p = {'trackId': 'x', 'deviceId': 'tv-1', 'overname': 'gsm-1', 'updatedAt': 1000};
      expect(overgenomenVanMij(p, mijnId: 'gsm-1'), isTrue);
      expect(overgenomenVanMij(p, mijnId: 'gsm-1', alGedaanOp: 1000), isFalse, reason: 'al gezien');
      expect(overgenomenVanMij(p, mijnId: 'ipad-2'), isFalse, reason: 'van een ander toestel overgenomen');
      expect(overgenomenVanMij({...p, 'deviceId': 'gsm-1'}, mijnId: 'gsm-1'), isFalse);
      expect(overgenomenVanMij({...p}..remove('overname'), mijnId: 'gsm-1'), isFalse);
      expect(overgenomenVanMij(p, mijnId: ''), isFalse);
      expect(overgenomenVanMij(null, mijnId: 'gsm-1'), isFalse);
    });

    test('aangesloten: bij afspelen, bij het bewaren van de plek, na een herstart en als de pc zijn geopend geeft', () {
      final speler = _bron('lib/player.dart');
      expect(speler, contains('    if (!playing && _overgenomenWeg()) {\n      unawaited(_openCurrent());\n'));
      expect(speler, contains("        if (_overgenomenPad == t.path) 'overgenomen': true,\n"));
      final h = speler.indexOf('  Future<void> restore(');
      final herstart = speler.substring(h, speler.indexOf('reopen PAUSED', h));
      expect(herstart, contains("overgenomen = byPath >= 0 && p['overgenomen'] == true;"));
      expect(herstart, contains('          (overgenomen ||\n              klaarstaandWeg('));
      final inhalen = herstart.indexOf("haalGeopendIn(waarom: 'na een herstart')");
      expect(inhalen, greaterThan(herstart.indexOf('klaarstaandNaarAchteren(_nu)')));
      expect(inhalen, lessThan(herstart.indexOf("bijHervatten?.call(_order, hoe: 'na een herstart'")),
          reason: 'schud.log toont dan de volgorde die echt komt');
      final telling = speler.substring(speler.indexOf('  void _nieuwVoorDeTelling('));
      expect(telling.indexOf('_overgenomenPad = null;'), greaterThan(0));
      expect(telling.indexOf('_overgenomenPad = null;'), lessThan(telling.indexOf('bijGeopend?.call(t);')));
      final main = _bron('lib/main.dart');
      expect(main, contains('          if (!samenVolger.volgt) player.haalGeopendIn();\n'));
      expect(main.indexOf('player.haalGeopendIn();'), greaterThan(main.indexOf('speelstanden.vanServerGeopend(')));
      expect(main, contains('  verder.bijOvername = (id) {\n'));
      final verder = _bron('lib/verder_luisteren.dart');
      expect(verder, contains("      bijOvername?.call('\${stand['trackId'] ?? ''}');\n"));
      expect(verder, contains('    bron.pauzeer();\n    bijOvername?.call(null);\n'));
    });
  });
}

