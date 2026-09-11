/// Het glas lag plat: de schaduw die het optilt haalde het scherm nooit.
///
/// **Wat hier misging.** `glassSurface` tekende zijn schaduw in dezelfde decoratie als de vulling
/// en de rand — en die decoratie lag BINNEN de `ClipRRect` die de pil zijn ronde vorm geeft. Een
/// ClipRRect knipt precies op de rand van zijn kind, en een schaduw valt per definitie buiten die
/// rand: negen punten omlaag, zesentwintig vervaagd. Alles wat de pil van de achtergrond had moeten
/// tillen, werd weggeknipt voordat het getekend werd.
///
/// Het eigen commentaar van `glassSurface` noemt die schaduw één van de vier dingen die het glas
/// maken. Er ontbrak er dus al die tijd één, en aan de code zag je het niet: daar stond hij gewoon.
/// Wat telt is niet óf de schaduw er is, maar waar hij hangt ten opzichte van de knip — dezelfde
/// soort bewering als die van `glasbalk_test.dart` over de vulling en de vervaging.
///
/// Beide takken, want ze knipten allebei: met vervaging (pc, iPad) en zonder (de zoekbalk op een
/// telefoon, en een televisie).
library;

import 'package:debridmusic/main.dart';
import 'package:debridmusic/tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const glas = Key('glas');

  tearDown(() => setTvModeForTest(false));

  Future<void> zet(WidgetTester t, {bool zonderBlur = false}) => t.pumpWidget(
        MaterialApp(
          home: Center(
            child: KeyedSubtree(
              key: glas,
              child: glassSurface(
                zonderBlur: zonderBlur,
                child: const SizedBox(width: 200, height: 32),
              ),
            ),
          ),
        ),
      );

  /// Alleen wat onder het glas zelf hangt. Wat MaterialApp eromheen zet, telt niet mee.
  Finder binnen(Finder wat) => find.descendant(of: find.byKey(glas), matching: wat);

  /// Het vlak dat de schaduw werpt. Een `Container` met een decoratie bouwt zelf een `DecoratedBox`,
  /// dus dit vindt hem ook als hij ooit terug in de vulling belandt.
  final schaduw = binnen(find.byWidgetPredicate((w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false)));

  final knip = binnen(find.byType(ClipRRect));

  void schaduwBuitenDeKnip(WidgetTester t) {
    expect(knip, findsOneWidget);
    expect(schaduw, findsOneWidget,
        reason: 'één schaduw — bleef hij ook in de vulling staan, dan wordt de pil van binnen '
            'dubbel donker');
    expect(find.descendant(of: knip, matching: schaduw), findsNothing,
        reason: 'binnen de knip wordt de schaduw weggeknipt — dan ligt de pil plat op de '
            'achtergrond');
    expect((t.widget<DecoratedBox>(schaduw).decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(999),
        reason: 'met rechte hoeken steekt er onder de ronde uiteinden een rechthoekige schaduw uit');
    expect(t.getRect(schaduw), t.getRect(knip),
        reason: 'is het vak groter of kleiner dan de pil, dan hangt er een schaduw onder die niet '
            'bij zijn vorm past');
  }

  testWidgets('met vervaging ligt de schaduw buiten de knip', (t) async {
    // Het glas zoals het op een pc en een iPad staat: de navigatiestrip en de zoekbalk.
    await zet(t);
    expect(binnen(find.byType(BackdropFilter)), findsOneWidget);
    schaduwBuitenDeKnip(t);
  });

  testWidgets('zonder vervaging ook — de zoekbalk op een telefoon', (t) async {
    await zet(t, zonderBlur: true);
    expect(binnen(find.byType(BackdropFilter)), findsNothing);
    schaduwBuitenDeKnip(t);
  });

  testWidgets('en op een televisie', (t) async {
    // Daar kiest `glassSurface` zijn eigen tak, en die knipte net zo.
    setTvModeForTest(true);
    await zet(t);
    expect(binnen(find.byType(BackdropFilter)), findsNothing);
    schaduwBuitenDeKnip(t);
  });
}
