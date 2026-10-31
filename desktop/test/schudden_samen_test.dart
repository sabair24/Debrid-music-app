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
import 'package:debridmusic/player.dart' show Wachtrij, naarAchterenLijst, ordenVoor, schudIdsGewogen;
import 'package:debridmusic/schudvolgorde.dart';
import 'package:debridmusic/speelstanden.dart';

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
      expect(s, contains('      _geopendDezeSessie.add(t.path);\n      bijGeopend?.call(t);\n'));
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
}

