// Nu speelt en de albumpagina, op gsm, iPad en pc (Saber, 18-10-2026): "als cd in hoes zit hoes
// centreren", en de hoes schuift naar links in dezelfde beweging waarmee de cd eruit komt. Eerst stond
// de hoes altijd links, met een lege strook ernaast die op de cd wachtte.
import 'dart:io';

import 'package:debridmusic/main.dart' show hoesEnSchijfX;
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reis = 100.0;

  test('cd in de hoes: de hoes staat precies in het midden van zijn vak', () {
    final p = hoesEnSchijfX(0, reis: reis);
    // Het vak is `s + reis` breed en de hoes `s`: in het midden is links en rechts reis / 2.
    expect(p.hoes, reis / 2);
    expect(p.schijf - p.hoes, closeTo(.26 * reis, 1e-9), reason: 'de cd blijft even ver in de hoes');
  });

  test('cd helemaal uit: alles staat zoals het altijd stond', () {
    final p = hoesEnSchijfX(1, reis: reis);
    expect(p.hoes, 0);
    expect(p.schijf, reis);
    final oud = hoesEnSchijfX(1, reis: reis, centreer: false);
    expect((p.hoes, p.schijf), (oud.hoes, oud.schijf));
  });

  test('één beweging: de hoes gaat even ver naar links als de cd naar buiten, op dezelfde curve', () {
    for (final t in [.1, .25, .5, .75, .9]) {
      final p = hoesEnSchijfX(t, reis: reis);
      final e = Curves.easeOutCubic.transform(t);
      expect(p.hoes, closeTo((1 - e) * reis / 2, 1e-9), reason: 't=$t');
      final uit = (p.schijf - p.hoes - .26 * reis) / (.74 * reis);
      expect(uit, closeTo(e, 1e-9), reason: 'de cd loopt niet voor of achter de hoes aan (t=$t)');
    }
  });

  test('zonder centreren (tv) blijft de hoes links staan', () {
    for (final t in [0.0, .5, 1.0]) {
      expect(hoesEnSchijfX(t, reis: reis, centreer: false).hoes, 0);
    }
    expect(hoesEnSchijfX(0, reis: reis, centreer: false).schijf, closeTo(.26 * reis, 1e-9));
  });

  test('in Nu speelt schuiven het logo en de plaatnaam met de hoes mee', () {
    final bron = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(bron, contains('_slide.addListener(_meldHoesX);'));
    expect(bron, contains('final x = hoesEnSchijfX(_slide.value, reis: _reis, centreer: _centreer).hoes;'));
    expect(bron, contains('hoesX: _hoesX,'));
    expect(bron, contains('metDeHoes(ArtiestKop('));
    expect(bron, contains('metDeHoes(SizedBox(\n                  width: zij ? hoesMaat : dialogWidth(context, 540),'));
  });

  test('de hoes, de spiegeling en de cd gebruiken alle drie deze regel', () {
    final bron = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(bron, contains('    final centreer = !isTv;'));
    expect(bron, contains('child: meeMetDeHoes(HoesSpiegel(beeld: front, maat: s))),'));
    expect(bron, contains('child: meeMetDeHoes(RepaintBoundary(child: kaartGekanteld))),'));
    expect(bron,
        contains('offset: Offset(hoesEnSchijfX(_slide.value, reis: travel, centreer: centreer).schijf, 0),'));
  });
}
