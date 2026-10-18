/// Een wieltik van de muis wordt uitgesmeerd, en verder verandert er niets (zie zacht_wiel.dart).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:debridmusic/zacht_wiel.dart';
import 'package:flutter_test/flutter_test.dart';

ui.PointerData _tik(double dy,
        {ui.PointerDeviceKind soort = ui.PointerDeviceKind.mouse, int apparaat = 1, int merk = 7}) =>
    ui.PointerData(
      embedderId: merk,
      kind: soort,
      signalKind: ui.PointerSignalKind.scroll,
      change: ui.PointerChange.hover,
      device: apparaat,
      physicalX: 300,
      physicalY: 400,
      scrollDeltaY: dy,
    );

const _beweeg = ui.PointerData(kind: ui.PointerDeviceKind.mouse, change: ui.PointerChange.hover, physicalX: 5);

class _Proef {
  final pakketten = <List<ui.PointerData>>[];
  final wachtend = <void Function(Duration)>[];
  late final wiel = ZachtWiel(door: (p) => pakketten.add(p.data), plan: wachtend.add);
  var klok = Duration.zero;

  /// Eén beeld verder; geeft terug of er nog een beeld gevraagd is.
  Future<bool> beeld(Duration stap) async {
    klok += stap;
    final nu = List.of(wachtend);
    wachtend.clear();
    for (final t in nu) {
      t(klok);
    }
    await Future<void>.delayed(Duration.zero);
    return wachtend.isNotEmpty;
  }

  Iterable<ui.PointerData> get alles => pakketten.expand((p) => p);
}

void main() {
  test('een tik: een stuk meteen met zijn eigen merk, de rest uitgesmeerd, opgeteld precies de tik', () async {
    final p = _Proef();
    p.wiel.opPakket(ui.PointerDataPacket(data: [_tik(100)]));
    expect(p.pakketten, hasLength(1));
    expect(p.pakketten.single.single.scrollDeltaY, closeTo(100 * kZachtWielMeteen, 1e-9));
    expect(p.pakketten.single.single.embedderId, 7, reason: 'wie tikken telt, ziet deze als de tik');
    var beelden = 0;
    while (await p.beeld(const Duration(microseconds: 6944))) {
      beelden++;
      expect(beelden, lessThan(200), reason: 'hij moet ophouden');
    }
    final vervolg = p.alles.skip(1).toList();
    expect(vervolg, isNotEmpty);
    expect(vervolg.every((d) => d.embedderId == kZachtWielVervolg), isTrue);
    final som = p.alles.fold<double>(0, (s, d) => s + d.scrollDeltaY);
    expect(som, closeTo(100, 1e-9));
    // Op 144 Hz uitgelopen binnen een kwart seconde.
    expect(p.klok, lessThan(const Duration(milliseconds: 250)));
  });

  test('even snel op 60 als op 144 beelden per seconde', () async {
    Future<double> naHonderdMs(Duration stap) async {
      final p = _Proef();
      p.wiel.opPakket(ui.PointerDataPacket(data: [_tik(100)]));
      while (p.klok < const Duration(milliseconds: 100)) {
        if (!await p.beeld(stap)) break;
      }
      return p.alles.fold<double>(0, (s, d) => s + d.scrollDeltaY);
    }

    final traag = await naHonderdMs(const Duration(microseconds: 16667));
    final snel = await naHonderdMs(const Duration(microseconds: 6944));
    expect((traag - snel).abs(), lessThan(4));
  });

  test('twee tikken vlak na elkaar tellen op', () async {
    final p = _Proef();
    p.wiel.opPakket(ui.PointerDataPacket(data: [_tik(100)]));
    await p.beeld(const Duration(milliseconds: 7));
    p.wiel.opPakket(ui.PointerDataPacket(data: [_tik(100)]));
    while (await p.beeld(const Duration(milliseconds: 7))) {}
    expect(p.alles.fold<double>(0, (s, d) => s + d.scrollDeltaY), closeTo(200, 1e-9));
  });

  test('een fijn wiel, een touchpad en gewone bewegingen gaan ongewijzigd door', () async {
    final p = _Proef();
    final fijn = _tik(12);
    final pad = _tik(100, soort: ui.PointerDeviceKind.trackpad);
    final pakket = ui.PointerDataPacket(data: [_beweeg, fijn, pad]);
    p.wiel.opPakket(pakket);
    expect(p.pakketten.single, same(pakket.data), reason: 'zelfs geen kopie');
    expect(p.wachtend, isEmpty);
  });

  test('de volgorde in een pakket blijft staan', () async {
    final p = _Proef();
    p.wiel.opPakket(ui.PointerDataPacket(data: [_beweeg, _tik(-100), _beweeg]));
    final d = p.pakketten.single;
    expect(d, hasLength(3));
    expect(d[0].signalKind, isNull);
    expect(d[1].scrollDeltaY, closeTo(-100 * kZachtWielMeteen, 1e-9));
    expect(d[2].signalKind, isNull);
  });

  test('de app zet hem aan op Windows, en het menu kent de vervolgstappen', () {
    expect(File('lib/main.dart').readAsStringSync(), contains('if (Platform.isWindows) ZachtWiel.installeer();'));
    expect(File('lib/ui/menu.dart').readAsStringSync(), contains('if (isZachtWielVervolg(e)) return;'));
  });

  test('een vervolgstap wordt nooit opnieuw gesplitst', () async {
    final p = _Proef();
    p.wiel.opPakket(ui.PointerDataPacket(data: [_tik(100, merk: kZachtWielVervolg)]));
    expect(p.pakketten.single.single.scrollDeltaY, 100);
    expect(p.wachtend, isEmpty);
  });
}
