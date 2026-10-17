/// "Kop aanpassen" op pc, Mac en iPad: rechtstreeks op de foto, per scherm apart (Saber, 17-10-2026).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:debridmusic/beeldvorm.dart';
import 'package:debridmusic/ui/kopbewerker.dart';
import 'package:debridmusic/ui/kopfoto.dart';

/// Een staande foto zoals die van *NSYNC (599 × 688), klein gehouden.
final _foto = Uint8List.fromList(img.encodePng(img.Image(width: 120, height: 138)));

class _Bewaard {
  final lijst = <(KopScherm, KopInstelling?)>[];
}

Future<_Bewaard> _open(WidgetTester t, {Map<KopScherm, KopInstelling?> huidig = const {}, KopScherm begin = KopScherm.pc}) async {
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final b = _Bewaard();
  await t.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: KopBewerker(
        naam: '*NSYNC',
        beeld: _foto,
        huidig: huidig,
        begin: begin,
        bronMaat: const Size(120, 138),
        bewaar: (s, i) async => b.lijst.add((s, i)),
      ),
    ),
  ));
  await t.pump();
  return b;
}

bool _opslaanAan(WidgetTester t) => t.widget<FilledButton>(find.byKey(const ValueKey('kop-opslaan'))).onPressed != null;

void main() {
  testWidgets('drie schermen om uit te kiezen, en het kader heeft de vorm van dat scherm', (t) async {
    await _open(t);
    for (final s in KopScherm.values) {
      expect(find.byKey(ValueKey('kop-scherm-${s.name}')), findsOneWidget);
    }
    Size kader(KopScherm s) => t.getSize(find.byKey(ValueKey('kop-kader-${s.name}')));
    final pc = kader(KopScherm.pc);
    expect(pc.width / (pc.height - 24), closeTo(1440 / 700, .02));
    await t.tap(find.byKey(const ValueKey('kop-scherm-tv')));
    await t.pump();
    final tv = kader(KopScherm.tv);
    expect(tv.width / (tv.height - 24), closeTo(960 / 435, .02));
    await t.tap(find.byKey(const ValueKey('kop-scherm-gsm')));
    await t.pump();
    final gsm = kader(KopScherm.gsm);
    expect(gsm.width / (gsm.height - 24), closeTo(411 / 520, .02));
  });

  testWidgets('slepen verschuift de foto, en Opslaan bewaart alleen dat scherm', (t) async {
    final b = await _open(t, begin: KopScherm.tv);
    expect(_opslaanAan(t), isFalse, reason: 'nog niets veranderd');
    // Omhoog slepen: de foto schuift omhoog, dus er komt een lager stuk in beeld.
    await t.drag(find.byKey(const ValueKey('kop-foto')), const Offset(0, -60));
    await t.pump();
    expect(_opslaanAan(t), isTrue);
    await t.tap(find.byKey(const ValueKey('kop-opslaan')));
    await t.pump();
    expect(b.lijst, hasLength(1));
    expect(b.lijst.single.$1, KopScherm.tv);
    final i = b.lijst.single.$2!;
    expect(i.zoom, 1);
    // Waar de app zelf begon (de foto is in een toets nog niet bekeken, dus op de maat uit de kop):
    const vak = Size(960, 435);
    final plek0 = KopFoto.plekVoor(vak: vak, maat: const Size(120, 138), blik: null, instelling: null, smal: false, bovenRand: 75);
    final p0 = puntOpDoel(vak: vak, plek: plek0, doel: doelInVak(kopDoel(smal: false), vak, 75));
    final schaal = t.getSize(find.byKey(const ValueKey('kop-foto'))).width / vak.width;
    expect(i.fy - p0.y, closeTo(60 / schaal / plek0.height, .004),
        reason: '60 punten omhoog slepen is precies zoveel van de foto lager op het doel');
  });

  testWidgets('scrollen zoomt in', (t) async {
    final b = await _open(t);
    final midden = t.getCenter(find.byKey(const ValueKey('kop-foto')));
    final muis = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(muis.hover(midden));
    await t.sendEventToBinding(muis.scroll(const Offset(0, -300)));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('kop-opslaan')));
    await t.pump();
    expect(b.lijst.single.$2!.zoom, greaterThan(1.4));
  });

  testWidgets('de onderrand slepen maakt de kop hoger', (t) async {
    final b = await _open(t, begin: KopScherm.tv);
    await t.drag(find.byKey(const ValueKey('kop-onderrand')), const Offset(0, 40));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('kop-opslaan')));
    await t.pump();
    expect(b.lijst.single.$2!.hoogte, greaterThan(360), reason: 'de gewone tv-kop is 360 onder de balk');
  });

  testWidgets('Herstel geeft het scherm terug aan de app, en de andere schermen blijven staan', (t) async {
    const tv = KopInstelling(fx: .6, fy: .2, zoom: 1.3);
    const gsm = KopInstelling(fx: .5, fy: .25);
    final b = await _open(t, huidig: {KopScherm.tv: tv, KopScherm.gsm: gsm}, begin: KopScherm.tv);
    expect(find.text('Zelf ingesteld'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kop-herstel')));
    await t.pump();
    expect(find.text('De app kiest zelf, op de gezichten'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kop-opslaan')));
    await t.pump();
    expect(b.lijst, [(KopScherm.tv, null)]);
  });

  test('de kadermaten zijn die van de echte koppen', () {
    // Zie `kTvKopZicht` (360) en de tv-balk (75) in main.dart: een kader dat niet de echte maat heeft,
    // laat je iets instellen wat je daarna niet ziet.
    final bron = File('lib/main.dart').readAsStringSync();
    expect(bron, contains('const double kTvKopZicht = 360;'));
    expect(kopKader(KopScherm.tv).maat, const Size(960, 435));
    expect(kopKader(KopScherm.tv).balk, 75);
    expect(kopKader(KopScherm.gsm).smal, isTrue);
  });
}
