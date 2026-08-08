/// Afspeellijsten, aan beide kanten van de lijn.
///
/// Dezelfde ops als de iPad al stuurt, dus één waarheid. Wat hier vastligt zijn de drie dingen die
/// stil kunnen breken: dat een gewiste lijst een tombstone wordt en geen gat, dat hetzelfde nummer
/// twee keer in een lijst mag staan, en dat een client niet op de pc staat te wachten.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/afspeellijsten.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/models.dart';

Track tr(String naam) => Track(
      path: 'D:\\m\\$naam.flac',
      title: naam,
      artist: 'A',
      album: 'Alb',
      trackNo: 1,
      isFlac: true,
    );

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('dm_pl_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Afspeellijsten opDePc() => Afspeellijsten()
    ..winkel = LanStateStore(File('${root.path}${Platform.pathSeparator}state.json'));

  group('op de pc', () {
    test('maken, hernoemen, vullen', () async {
      final l = opDePc();
      expect(l.leeg, isTrue);

      final id = await l.maak('Zondagochtend');
      expect(l.lijsten.single.name, 'Zondagochtend');

      await l.hernoem(id, 'Zaterdagavond');
      expect(l.byId(id)!.name, 'Zaterdagavond');

      await l.voegToe(id, ['t1', 't2']);
      expect(l.byId(id)!.trackIds, ['t1', 't2']);
    });

    test('hetzelfde nummer mag er twee keer in', () async {
      // Een echte wens — een nummer dat twee keer voorbijkomt in een set. De winkel ontdubbelt
      // daarom ook niet, en deze test bewaakt dat we dat er niet alsnog in bouwen.
      final l = opDePc();
      final id = await l.maak('x');
      await l.voegToe(id, ['t1']);
      await l.voegToe(id, ['t1']);
      expect(l.byId(id)!.trackIds, ['t1', 't1']);
    });

    test('één kopie eruit halen laat de andere staan', () async {
      // Dit is waarom er setTracks wordt gebruikt en geen playlist.remove: die gooit ELKE kopie van
      // dat id eruit, en dan verdwijnen ze allebei terwijl je er één aanklikte.
      final l = opDePc();
      final id = await l.maak('x');
      await l.voegToe(id, ['t1', 't2', 't1']);
      final ids = [...l.byId(id)!.trackIds]..removeAt(0);
      await l.zetNummers(id, ids);
      expect(l.byId(id)!.trackIds, ['t2', 't1']);
    });

    test('een gewiste lijst is weg uit beeld maar blijft als tombstone bestaan', () async {
      // De tombstone is er voor een toestel dat uit stond: een regel die simpelweg verdwijnt wordt
      // daar gelezen als "die heb ik nog niet" en meteen teruggeduwd.
      final l = opDePc();
      final id = await l.maak('weg');
      await l.wis(id);
      expect(l.byId(id), isNull);
      expect(l.lijsten, isEmpty);
      expect(l.winkel!.playlists[id]!.deleted, isTrue, reason: 'de tombstone hoort te blijven');
    });

    test('nieuwste bovenaan', () async {
      final l = opDePc();
      await l.maak('eerste');
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await l.maak('tweede');
      expect(l.lijsten.first.name, 'tweede');
    });

    test('twee id\'s botsen niet', () async {
      final l = opDePc();
      final ids = {for (var i = 0; i < 50; i++) await l.maak('n$i')};
      expect(ids.length, 50, reason: 'een botsing zou de tweede lijst stil laten verdwijnen');
    });

    test('nummers opzoeken slaat over wat er niet meer is', () async {
      // Een verwijderd bestand hoort geen lege regel in je afspeellijst te worden.
      final l = opDePc();
      final id = await l.maak('x');
      await l.voegToe(id, ['a', 'weg', 'b']);
      final kaart = {'a': tr('a'), 'b': tr('b')};
      final uit = l.nummersVan(l.byId(id)!, (i) => kaart[i]);
      expect([for (final t in uit) t.title], ['a', 'b']);
    });
  });

  group('op een iPad of gsm', () {
    test('een nieuwe lijst staat er METEEN, niet pas als de pc antwoordt', () async {
      final poort = Completer<void>();
      final verstuurd = <Map<String, dynamic>>[];
      final l = Afspeellijsten()
        ..duwOps = (ops) async {
          verstuurd.addAll(ops);
          await poort.future;
        };

      final bezig = l.maak('onderweg');
      await Future<void>.delayed(Duration.zero);
      expect(l.lijsten.single.name, 'onderweg', reason: 'het scherm mag niet op de pc wachten');
      expect(verstuurd.single['type'], 'playlist.create');
      poort.complete();
      await bezig;
    });

    test('weigert de pc het, dan verdwijnt hij weer', () async {
      // Anders staat er een lijst op je iPad die op geen enkel ander toestel bestaat.
      final l = Afspeellijsten()..duwOps = (_) async => throw 'pc onbereikbaar';
      await expectLater(l.maak('spook'), throwsA(anything));
      expect(l.lijsten, isEmpty);
    });

    test('wat de pc meldt wordt overgenomen, tombstones eruit gefilterd', () {
      final l = Afspeellijsten();
      l.vanServer([
        {'id': 'p1', 'name': 'Blijft', 'trackIds': ['t1'], 'updatedAt': 2},
        {'id': 'p2', 'name': 'Gewist', 'trackIds': <String>[], 'updatedAt': 1, 'deletedAt': 5},
      ]);
      expect([for (final p in l.lijsten) p.name], ['Blijft']);
      expect(l.byId('p2'), isNull);
    });
  });
}
