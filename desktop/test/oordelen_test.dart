/// Een duim die je zet op de telefoon staat er ook op de pc.
///
/// De op gaat door dezelfde weg als een favoriet — [LanStateStore.applyOps] — en moet daar drie
/// dingen goed doen: opslaan, overschrijven, en weer WEGHALEN. Dat laatste is het geval dat je bij
/// een favoriet niet hebt: daar is "uit" een `on: false`, hier is het de afwezigheid van een oordeel.
/// Een lege waarde die als derde stand blijft staan zou de kaart laten vollopen met niets.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/state_store.dart';

void main() {
  late Directory map;
  late LanStateStore winkel;

  setUp(() {
    map = Directory.systemTemp.createTempSync('oordelen');
    winkel = LanStateStore(File('${map.path}${Platform.pathSeparator}state.json'));
  });

  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, int> zet(String id, String waarde) =>
      winkel.applyOps([
        {'type': 'rating', 'trackId': id, 'value': waarde}
      ]);

  test('een duim wordt bewaard en telt als wijziging', () {
    final was = winkel.rev;
    zet('a', 'up');
    expect(winkel.ratings['a'], 'up');
    expect(winkel.rev, greaterThan(was), reason: 'anders haalt geen enkel ander toestel hem op');
  });

  test('dezelfde duim nog eens verandert niets', () {
    zet('a', 'up');
    final na = winkel.rev;
    zet('a', 'up');
    expect(winkel.rev, na,
        reason: 'een revisie die omhoog gaat zonder dat er iets veranderd is, laat elk toestel de '
            'hele staat opnieuw ophalen');
  });

  test('de andere duim vervangt de eerste', () {
    zet('a', 'up');
    zet('a', 'down');
    expect(winkel.ratings['a'], 'down');
    expect(winkel.ratings, hasLength(1), reason: 'een nummer heeft precies één oordeel');
  });

  test('een lege waarde HAALT het oordeel weg in plaats van het leeg te zetten', () {
    zet('a', 'up');
    zet('a', '');
    expect(winkel.ratings.containsKey('a'), isFalse);
  });

  test('een oordeel weghalen dat er niet was, is geen wijziging', () {
    final was = winkel.rev;
    zet('a', '');
    expect(winkel.rev, was);
  });

  test('een id zonder inhoud wordt genegeerd', () {
    winkel.applyOps([
      {'type': 'rating', 'trackId': '', 'value': 'up'}
    ]);
    expect(winkel.ratings, isEmpty);
  });

  test('onzin als waarde wist niets en zet niets', () {
    zet('a', 'up');
    zet('a', 'misschien');
    expect(winkel.ratings['a'], isNull,
        reason: 'alles wat geen up of down is, is "geen oordeel" — en dat is afwezigheid');
  });

  test('oordelen gaan mee in de momentopname en in het bestand', () {
    zet('a', 'up');
    zet('b', 'down');
    expect(winkel.snapshot()['ratings'], {'a': 'up', 'b': 'down'});
    expect(winkel.toJson()['ratings'], {'a': 'up', 'b': 'down'});
  });

  test('een oude staat zonder oordelen leest gewoon in', () async {
    final f = File('${map.path}${Platform.pathSeparator}oud.json');
    await f.writeAsString('{"rev":3,"favoriteTracks":["x"]}');
    final oud = LanStateStore(f);
    await oud.load();
    expect(oud.rev, 3);
    expect(oud.ratings, isEmpty);
    expect(oud.favoriteTracks, {'x'});
  });

  test('een staat met rommel in de oordelen leest de goede regels wel', () async {
    final f = File('${map.path}${Platform.pathSeparator}rommel.json');
    await f.writeAsString('{"ratings":{"a":"up","b":7,"c":"misschien","d":"down"}}');
    final s = LanStateStore(f);
    await s.load();
    expect(s.ratings, {'a': 'up', 'd': 'down'});
  });
}
