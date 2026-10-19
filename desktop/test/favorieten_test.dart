/// Favorieten, aan beide kanten van de lijn.
///
/// Op de pc gaan ze rechtstreeks in de gedeelde staat; op een iPad of gsm staat die winkel niet en
/// gaat dezelfde op over de lijn. Dat is de reden dat er één klasse is en geen twee: twee wegen naar
/// dezelfde lijst worden vroeg of laat twee lijsten die niet meer gelijk lopen.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/favorieten.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/models.dart';

Track tr(String naam) => Track(
      path: 'D:\\Flac music 2024\\A\\Alb\\$naam.flac',
      title: naam,
      artist: 'A',
      album: 'Alb',
      trackNo: 1,
      duration: const Duration(seconds: 200),
      isFlac: true,
    );

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dm_fav_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Favorieten opDePc() {
    final winkel = LanStateStore(File('${root.path}${Platform.pathSeparator}state.json'));
    return Favorieten()
      ..winkel = winkel
      ..wortel = () => 'D:\\Flac music 2024';
  }

  group('op de pc', () {
    test('een hartje aan en weer uit', () async {
      final fav = opDePc();
      final t = tr('een');
      expect(fav.isFavorietTrack(t), isFalse);

      expect(await fav.wisselTrack(t), isTrue);
      expect(fav.isFavorietTrack(t), isTrue);
      expect(fav.aantal, 1);

      expect(await fav.wisselTrack(t), isFalse);
      expect(fav.isFavorietTrack(t), isFalse);
      expect(fav.aantal, 0);
    });

    test('het id komt van het PAD, niet van de titel', () {
      // De gedeelde staat wordt gelezen door toestellen waar D:\Flac music 2024 niet bestaat. Twee
      // nummers met dezelfde titel op verschillende platen zijn verschillende favorieten.
      final fav = opDePc();
      final a = tr('zelfde');
      final b = Track(
        path: 'D:\\Flac music 2024\\B\\Ander\\zelfde.flac',
        title: 'zelfde',
        artist: 'B',
        album: 'Ander',
        trackNo: 1,
        isFlac: true,
      );
      expect(fav.idVanTrack(a), isNot(fav.idVanTrack(b)));
    });

    test('zonder wortel valt er geen id te maken en gebeurt er niets', () {
      // Op een client staat de muziek niet, dus is er geen wortel. Daar hoort dit stil te falen in
      // plaats van een id te verzinnen dat op de pc niets betekent.
      final fav = Favorieten()..winkel = LanStateStore(File('${root.path}\\s.json'));
      expect(fav.idVanTrack(tr('x')), isNull);
      expect(fav.isFavorietTrack(tr('x')), isFalse);
    });

    test('filtert een bibliotheek in de volgorde die ze al had', () async {
      final fav = opDePc();
      final lijst = [tr('a'), tr('b'), tr('c')];
      await fav.wisselTrack(lijst[2]);
      await fav.wisselTrack(lijst[0]);
      expect([for (final t in fav.nummers(lijst)) t.title], ['a', 'c'],
          reason: 'niet in de volgorde waarin je ze aanklikte');
    });
  });

  group('op een iPad of gsm', () {
    test('een favoriet NUMMER van de pc staat ook op de gsm (18-10-2026: daar stond "Nog geen favorieten")', () {
      // Op een client is er geen muziekmap; het id komt uit de stream-URL (library.gedeeldId).
      final t = Track(
          path: 'http://pc:47820/stream/t1', title: 'Talkin', artist: 'Tracy', album: 'TC', trackNo: 1,
          duration: const Duration(seconds: 200), isFlac: true);
      final fav = Favorieten()..idVanPad = (p) => p.endsWith('/t1') ? 't1' : null;
      fav.vanServer(['t1'], const []);
      expect(fav.idVanTrack(t), 't1');
      expect(fav.isFavorietTrack(t), isTrue);
      expect(fav.nummers([t, tr('ander')]), [t]);
    });

    test('wat de pc meldt wordt getoond', () {
      final fav = Favorieten();
      fav.vanServer(['t1', 't2'], ['a1']);
      expect(fav.isFavoriet('t1'), isTrue);
      expect(fav.isFavoriet('a1'), isTrue);
      expect(fav.isFavoriet('t9'), isFalse);
      expect(fav.aantal, 3);
    });

    test('een hartje verschijnt METEEN, niet pas als de pc antwoordt', () async {
      // Een knop die een halve seconde niets doet leest als een knop die het niet deed, en dan drukt
      // iemand nog eens -- en zet hem daarmee weer uit.
      final verstuurd = <List<Map<String, dynamic>>>[];
      final poort = Completer<void>();
      final fav = Favorieten()
        ..duwOps = (ops) async {
          verstuurd.add(ops);
          await poort.future;
        };

      final bezig = fav.wissel(id: 't1', album: false);
      expect(fav.isFavoriet('t1'), isTrue, reason: 'het scherm mag niet op de pc wachten');
      expect(verstuurd.single.single['type'], 'favorite');
      expect(verstuurd.single.single['on'], isTrue);
      poort.complete();
      await bezig;
      expect(fav.isFavoriet('t1'), isTrue);
    });

    test('weigert de pc het, dan draait het scherm terug', () async {
      // Anders staat er een gevuld hartje bij iets wat nergens bewaard is, en dat is het soort
      // leugen dat je pas ontdekt als je op een ander toestel kijkt.
      final fav = Favorieten()..duwOps = (_) async => throw 'pc onbereikbaar';
      await expectLater(fav.wissel(id: 't1', album: false), throwsA(anything));
      expect(fav.isFavoriet('t1'), isFalse);
    });

    test('een album krijgt kind=album mee', () async {
      final verstuurd = <Map<String, dynamic>>[];
      final fav = Favorieten()..duwOps = (ops) async => verstuurd.addAll(ops.cast());
      await fav.wissel(id: 'alb1', album: true);
      expect(verstuurd.single['kind'], 'album');
    });
  });

  test('aangesloten: favorieten en afspeellijsten zoeken nummers via gedeeldId, ook op een gsm', () {
    final hoofd = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(hoofd, contains('final favorieten = Favorieten()..idVanPad = library.gedeeldId;'));
    expect(hoofd, contains('if (lib.gedeeldId(t.path) case final i?) i: t,'));
    expect(hoofd, contains('if (library.gedeeldId(t.path) case final i?) i: t,'));
  });
}
