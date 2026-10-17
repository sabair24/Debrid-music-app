/// De iconen van het menu (Saber, 17-10-2026: "in de menu mag naast de tekst mooie animated iconen
/// komen"): lijniconen die vollopen onder de pil, elk met een eigen beweging.
///
/// Wat hier vastligt: elke beweging eindigt precies waar hij begon (anders springt het icoon aan het
/// eind terug), vol is echt anders dan leeg, elke sectie heeft een icoon, en het icoon speelt bij het
/// kiezen en staat daarna stil.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart' show NavSections;
import 'package:debridmusic/ui/menu_iconen.dart';

Future<Uint8List> _teken(WidgetTester t, MenuIcoonSchilder s) async {
  final opname = ui.PictureRecorder();
  s.paint(Canvas(opname), const Size(48, 48));
  final beeld = await t.runAsync(() => opname.endRecording().toImage(48, 48));
  final bytes = await t.runAsync(() => beeld!.toByteData(format: ui.ImageByteFormat.rawRgba));
  return bytes!.buffer.asUint8List();
}

/// Het grootste verschil tussen twee beelden, per kleurkanaal (0–255).
int _verschil(Uint8List a, Uint8List b) {
  var m = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > m) m = d;
  }
  return m;
}

void main() {
  const wit = Color(0xFFFFFFFF);

  testWidgets('elke beweging eindigt waar hij begon', (t) async {
    for (final soort in MenuIcoonSoort.values) {
      for (final vul in [0.0, 1.0]) {
        final rust = await _teken(t, MenuIcoonSchilder(soort: soort, kleur: wit, vul: vul));
        for (final sterk in [1.0, .5]) {
          final bijnaKlaar =
              await _teken(t, MenuIcoonSchilder(soort: soort, kleur: wit, vul: vul, t: .999, sterk: sterk));
          // Een paar tinten verschil is randvervaging; een sprong is meteen 150 of meer.
          expect(_verschil(rust, bijnaKlaar), lessThan(64),
              reason: '$soort (vul $vul, sterk $sterk) springt aan het eind van zijn beweging');
        }
      }
    }
  });

  testWidgets('halverwege beweegt er echt iets', (t) async {
    for (final soort in MenuIcoonSoort.values) {
      final rust = await _teken(t, MenuIcoonSchilder(soort: soort, kleur: wit, vul: 1));
      var bewoog = false;
      for (final tt in [.15, .3, .45, .6]) {
        final nu = await _teken(t, MenuIcoonSchilder(soort: soort, kleur: wit, vul: 1, t: tt));
        if (_verschil(rust, nu) > 60) bewoog = true;
      }
      expect(bewoog, isTrue, reason: '$soort heeft geen zichtbare beweging');
    }
  });

  testWidgets('vol is anders dan leeg', (t) async {
    for (final soort in MenuIcoonSoort.values) {
      final leeg = await _teken(t, MenuIcoonSchilder(soort: soort, kleur: wit));
      final vol = await _teken(t, MenuIcoonSchilder(soort: soort, kleur: wit, vul: 1));
      expect(_verschil(leeg, vol), greaterThan(60), reason: '$soort loopt niet vol');
    }
  });

  test('elke sectie heeft een icoon', () {
    for (final (id, label, _) in NavSections.items) {
      expect(menuIcoonVoorSectie(id), isNotNull, reason: '$label heeft geen icoon');
    }
    final alle = {for (final (id, _, _) in NavSections.items) menuIcoonVoorSectie(id)};
    expect(alle.length, NavSections.items.length, reason: 'twee secties met hetzelfde icoon');
  });

  testWidgets('kiezen: vollopen en één keer bewegen, daarna stil', (t) async {
    Widget icoon(bool gekozen) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: MenuIcoon(soort: MenuIcoonSoort.favorieten, kleur: wit, gekozen: gekozen),
          ),
        );
    MenuIcoonSchilder schilder() =>
        t.widget<CustomPaint>(find.descendant(of: find.byType(MenuIcoon), matching: find.byType(CustomPaint))).painter!
            as MenuIcoonSchilder;
    await t.pumpWidget(icoon(false));
    expect(schilder().vul, 0);
    await t.pumpWidget(icoon(true));
    await t.pump(const Duration(milliseconds: 100));
    expect(schilder().vul, inExclusiveRange(0, 1), reason: 'het loopt vloeiend vol');
    expect(schilder().t, lessThan(1), reason: 'de beweging speelt');
    await t.pumpAndSettle();
    expect(schilder().vul, 1);
    expect(schilder().t, 1, reason: 'daarna staat hij stil');
  });

  testWidgets('Mijn downloads blijft bewegen zolang er iets binnenkomt', (t) async {
    Widget icoon(bool bezig) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: MenuIcoon(soort: MenuIcoonSoort.downloads, kleur: wit, bezig: bezig)),
        );
    await t.pumpWidget(icoon(true));
    await t.pump(const Duration(seconds: 3));
    expect(t.hasRunningAnimations, isTrue, reason: 'de pijl valt telkens opnieuw');
    await t.pumpWidget(icoon(false));
    await t.pumpAndSettle();
    expect(t.hasRunningAnimations, isFalse, reason: 'klaar is klaar: hij maakt zijn ronde af en stopt');
  });
}
