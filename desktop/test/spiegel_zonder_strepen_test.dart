/// De spiegeling onder een hoes hoort een glad verloop te zijn, zonder strepen (Saber, 01-11-2026, Nu speelt: "zit er in
/// de reflectie altijd lijk strepen in, kijk ergens anders ook").
///
/// Echt getekend (toImage), niet nagelezen: per pixelrij de dekking van de spiegeling van een egaal grijze hoes. In
/// stroken (tot 01-11-2026) waren dat treden: onder de grote hoes op de gsm 8 à 9 rijen gelijk en dan een sprong van 2 à
/// 3 op 255 (50, 48, 45, 42 …), onder een tegel op de pc sprongen van 5, en gebakken een laatste rij op 41 van 255. Een
/// glad verloop wordt van rij tot rij hoogstens een of twee stappen doorzichtiger, nooit dekkender, en eindigt op niets.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/ui/tegel_spiegel.dart';

Future<ui.Image> _egaal(int maat) async {
  final r = ui.PictureRecorder();
  Canvas(r).drawRect(Rect.fromLTWH(0, 0, maat.toDouble(), maat.toDouble()), Paint()..color = const Color(0xFF808080));
  final p = r.endRecording();
  final b = await p.toImage(maat, maat);
  p.dispose();
  return b;
}

/// De dekking (0–255) per rij, in het midden van de breedte.
Future<List<int>> _dekkingPerRij(ui.Image beeld) async {
  final data = (await beeld.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final b = beeld.width, x = b ~/ 2;
  return [for (var y = 0; y < beeld.height; y++) data.getUint8((y * b + x) * 4 + 3)];
}

void verloopIsGlad(List<int> rijen, String waar) {
  expect(rijen.first, greaterThan(30), reason: '$waar: bovenaan zichtbaar (20 % dekking = 51)');
  expect(rijen.last, 0, reason: '$waar: onderaan niets — geen streep');
  for (var y = 1; y < rijen.length; y++) {
    final stap = rijen[y - 1] - rijen[y];
    expect(stap, greaterThanOrEqualTo(0), reason: '$waar: rij $y dekkender dan de rij erboven (${rijen[y - 1]} → ${rijen[y]})');
    expect(stap, lessThanOrEqualTo(2), reason: '$waar: rij $y een trede (${rijen[y - 1]} → ${rijen[y]})');
  }
}

void main() {
  for (final (naam, maat, dpr) in [('grote hoes in Nu speelt (gsm)', 320.0, 3.0), ('albumtegel (pc)', 150.0, 1.0), ('albumtegel (gsm)', 160.0, 2.75)]) {
    testWidgets('$naam: gebakken (Nu speelt, de albumpagina, tegels op Mac en iPad) glad', (tester) async {
      await tester.runAsync(() async {
        final hoes = await _egaal(600);
        final beeld = bakSpiegel(hoes, maat: maat, dpr: dpr);
        verloopIsGlad(await _dekkingPerRij(beeld), '$naam gebakken');
        beeld.dispose();
        hoes.dispose();
      });
    });

    testWidgets('$naam: rechtstreeks (tegels op pc, gsm en tv) glad', (tester) async {
      await tester.runAsync(() async {
        final hoes = await _egaal(600);
        final hoogte = maat * kTegelSpiegelHoogte;
        final r = ui.PictureRecorder();
        tekenSpiegel(Canvas(r)..scale(dpr), hoes, maat: maat, hoogte: hoogte);
        final p = r.endRecording();
        final beeld = await p.toImage((maat * dpr).ceil(), (hoogte * dpr).ceil());
        p.dispose();
        verloopIsGlad(await _dekkingPerRij(beeld), '$naam rechtstreeks');
        beeld.dispose();
        hoes.dispose();
      });
    });
  }
}
