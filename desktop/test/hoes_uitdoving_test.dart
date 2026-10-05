/// De hoes op de achtergrond van "Now playing" dooft nu uit zonder `ShaderMask` — en ziet er hetzelfde uit.
///
/// Gemeten op 05-10-2026 op Sabers S26 met *Scatman's World*: de tekendraad wachtte per beeld 29 ms
/// op de grafische chip (99 % bezet), en het scherm haalde 30 beelden per seconde. Saber: *"natuurlijk
/// als de cd 1000*1000 resolutie is schokt hij, kijk nog eens met scatmen nu"*. Het duurste per beeld
/// was een schermvullende `ShaderMask`, een tussenlaag van 3120×1440 die elke tik van de draaiende cd
/// opnieuw betaald werd. [hoesUitdoving] legt in plaats daarvan dezelfde was er nog eens overheen.
///
/// Deze toets tekent de oude en de nieuwe manier naar pixels en vergelijkt ze op vijf hoogtes.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _b = 100.0, _h = 400.0;

/// Een "hoes": een vlak met een kleur, op 22 % dekking — zoals `Image(opacity: .22)`.
Widget _hoes(Color c) => ColoredBox(color: c.withValues(alpha: .22));

Widget _oud(Color? basis, Color hoes) => Stack(children: [
      Positioned.fill(
          child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: kleurWas(basis), color: basis == null ? kAchtergrond : null))),
      Positioned.fill(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.transparent],
            stops: [.20, .72],
          ).createShader(r),
          child: _hoes(hoes),
        ),
      ),
    ]);

Widget _nieuw(Color? basis, Color hoes) => Stack(children: [
      Positioned.fill(
          child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: kleurWas(basis), color: basis == null ? kAchtergrond : null))),
      Positioned.fill(child: _hoes(hoes)),
      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: hoesUitdoving(basis)))),
    ]);

Future<List<Color>> _pixels(WidgetTester tester, Widget w) async {
  final sleutel = GlobalKey();
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: RepaintBoundary(key: sleutel, child: SizedBox(width: _b, height: _h, child: w)))));
  final rb = tester.renderObject<RenderRepaintBoundary>(find.byKey(sleutel));
  final beeld = (await tester.runAsync(() => rb.toImage()))!;
  final data = (await tester.runAsync(() => beeld.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  return [
    for (final f in [.10, .30, .46, .62, .90])
      () {
        final o = ((_h * f).round() * _b.round() + 50) * 4;
        return Color.fromARGB(255, data.getUint8(o), data.getUint8(o + 1), data.getUint8(o + 2));
      }(),
  ];
}

double _verschil(Color a, Color b) => [
      (a.r - b.r).abs(),
      (a.g - b.g).abs(),
      (a.b - b.b).abs(),
    ].reduce((x, y) => x > y ? x : y) * 255;

void main() {
  for (final (naam, basis, hoes) in [
    ('Scatman: blauwgrijs, witte hoes', const Color(0xFF3E5470), const Color(0xFFF2F2F2)),
    ('Sonique: groen', const Color(0xFF6E8F3A), const Color(0xFFE0D8C8)),
    ('zonder was (geen kleur bekend)', null, const Color(0xFFFFFFFF)),
  ]) {
    testWidgets('DE KERN ($naam): hetzelfde beeld als met het masker, op vijf hoogtes', (tester) async {
      final oud = await _pixels(tester, _oud(basis, hoes));
      final nieuw = await _pixels(tester, _nieuw(basis, hoes));
      for (var i = 0; i < oud.length; i++) {
        expect(_verschil(oud[i], nieuw[i]), lessThanOrEqualTo(6),
            reason: 'hoogte #$i: oud $oud\nnieuw $nieuw');
      }
    });
  }

  test('DE VAL: geen ShaderMask meer in Now playing', () {
    final main = File('lib/main.dart').readAsStringSync();
    final begin = main.indexOf('class NowPlayingScreen extends StatefulWidget');
    final einde = main.indexOf('\nclass ', main.indexOf('class _NowPlayingScreenState', begin) + 10);
    final scherm = main.substring(begin, einde);
    expect(scherm, isNot(contains('ShaderMask(')),
        reason: 'een schermvullende tussenlaag per beeld: 29 ms op de chip bij een draaiende cd');
    expect(scherm, contains('hoesUitdoving(wasBasis(p.wasKleur))'));
  });
}
