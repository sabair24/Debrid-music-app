/// De eerste geanimeerde schakelaar in deze app.
///
/// Er valt aan een animatie weinig te toetsen zonder ernaar te kijken, en dat is precies waarom deze
/// toets zich beperkt tot wat wél hard is: dat de knop de goede stand toont, dat een tik aankomt, dat
/// de beweging LOOPT wanneer je kiest en NIET wanneer je je keuze terugneemt, en dat hij eindigt waar
/// hij begon. Dat laatste is de fout die je op een toestel pas na een uur ziet: een knop die na elke
/// tik een fractie groter blijft.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/ui/duim.dart';

void main() {
  Future<void> toon(
    WidgetTester t, {
    required bool aan,
    Duimkant kant = Duimkant.omlaag,
    bool gedempt = false,
    VoidCallback? opTik,
    String? bijschrift,
  }) =>
      t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Duim(
              kant: kant,
              aan: aan,
              gedempt: gedempt,
              bijschrift: bijschrift,
              opTik: opTik ?? () {},
            ),
          ),
        ),
      ));

  // De grootste schaal onder alle Transforms IN de duim. Er zijn er twee — draaien en schalen — en
  // welke van de twee als eerste in de boom staat is een detail dat deze toets niet hoort te kennen.
  // Een pure draaiing levert 1,0 op, dus het maximum is precies de schaal.
  double schaalNu(WidgetTester t) {
    var uit = 0.0;
    final alle = t.widgetList<Transform>(
        find.descendant(of: find.byType(Duim), matching: find.byType(Transform)));
    for (final w in alle) {
      final s = w.transform.getMaxScaleOnAxis();
      if (s > uit) uit = s;
    }
    return uit;
  }

  double doofheidNu(WidgetTester t) => t
      .widget<AnimatedOpacity>(
          find.descendant(of: find.byType(Duim), matching: find.byType(AnimatedOpacity)))
      .opacity;

  testWidgets('uit is omlijnd, aan is gevuld', (t) async {
    await toon(t, aan: false);
    expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);

    await toon(t, aan: true);
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.thumb_down_rounded), findsOneWidget,
        reason: 'gevuld is het verschil tussen "hier kun je op drukken" en "hier is op gedrukt"');
  });

  testWidgets('de duim omhoog is een ander teken dan de duim omlaag', (t) async {
    await toon(t, aan: false, kant: Duimkant.omhoog);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
  });

  testWidgets('een tik komt aan', (t) async {
    var tikken = 0;
    await toon(t, aan: false, opTik: () => tikken++);
    await t.tap(find.byType(Duim));
    expect(tikken, 1);
  });

  testWidgets('het bijschrift staat eronder als erom gevraagd is, en anders niet', (t) async {
    await toon(t, aan: false, bijschrift: 'Weg, ook van je pc');
    expect(find.text('Weg, ook van je pc'), findsOneWidget);

    await toon(t, aan: false);
    expect(find.textContaining('Weg'), findsNothing,
        reason: 'in een lijstregel is voor een bijschrift geen plek');
  });

  testWidgets('kiezen zet de beweging in gang en die eindigt waar hij begon', (t) async {
    await toon(t, aan: false);
    final rust = schaalNu(t);

    await toon(t, aan: true);
    await t.pump(const Duration(milliseconds: 60));
    expect(schaalNu(t), greaterThan(rust),
        reason: 'zonder zichtbare bevestiging tik je nog eens omdat je niet weet of het aankwam');

    await t.pumpAndSettle();
    expect(schaalNu(t), closeTo(rust, 0.001),
        reason: 'een knop die na elke tik een fractie groter blijft, is na tien tikken scheef');
  });

  testWidgets('je keuze terugnemen springt niet', (t) async {
    await toon(t, aan: true);
    await t.pumpAndSettle();
    final rust = schaalNu(t);

    await toon(t, aan: false);
    await t.pump(const Duration(milliseconds: 60));
    expect(schaalNu(t), closeTo(rust, 0.001),
        reason: '"ik vond er toch niets van" is een correctie en hoort niet gevierd te worden');
  });

  testWidgets('de andere duim dooft zodra er gekozen is', (t) async {
    await toon(t, aan: false);
    await t.pumpAndSettle();
    final vol = doofheidNu(t);

    await toon(t, aan: false, gedempt: true);
    await t.pumpAndSettle();
    final dof = doofheidNu(t);

    expect(dof, lessThan(vol),
        reason: 'dat er GEKOZEN is, is iets anders dan dat er iets aan staat');
  });
}
