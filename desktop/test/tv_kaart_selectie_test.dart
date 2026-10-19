/// De kaarten van de nieuwe releases laten op een tv zien dat ze de selectie hebben (Shield, 19-10-2026:
/// op "Nieuwe albums & EP's" was nergens te zien waar je stond).
library;

import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/nieuw_kaarten.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NieuwKaart _k(String titel) => NieuwKaart(
      titel: titel,
      regel2: 'Slimane',
      hoes: (m) => SizedBox.square(dimension: m),
      onTap: () {},
    );

Widget _app(Widget kind) => MaterialApp(home: Scaffold(body: Center(child: kind)));

BoxDecoration _deco(WidgetTester t, String sleutel) =>
    t.widget<Container>(find.byKey(ValueKey(sleutel))).decoration! as BoxDecoration;

FocusNode _knoop(WidgetTester t, String titel) => Focus.of(t.element(find.text(titel)));

void main() {
  tearDown(() {
    setTvModeForTest(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  for (final soort in ['breed', 'groot']) {
    testWidgets('op de tv: de $soort kaart met de selectie krijgt een felle rand, zonder niet', (t) async {
      setTvModeForTest(true);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      Widget kaart(String titel) => soort == 'breed'
          ? BredeKaart(_k(titel), breedte: 300, hoogte: 90)
          : GroteKaart(_k(titel), breedte: 420, hoogte: 180);
      await t.pumpWidget(_app(Column(mainAxisSize: MainAxisSize.min, children: [kaart('Een'), kaart('Twee')])));
      expect(find.byKey(const ValueKey('kaart-selectie')), findsNothing);
      _knoop(t, 'Een').requestFocus();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kaart-selectie')), findsOneWidget);
      final rand = (_deco(t, 'kaart-selectie').border! as Border).top;
      expect(rand.width, 2);
      expect(rand.color.a, 1, reason: 'het accent, niet de zachte lijn van in rust');
      expect(rand.color.toARGB32() & 0xFFFFFF, kAccent.toARGB32() & 0xFFFFFF);
      _knoop(t, 'Twee').requestFocus();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kaart-selectie')), findsOneWidget, reason: 'nu de tweede, en alleen die');
      expect(find.ancestor(of: find.text('Twee'), matching: find.byKey(const ValueKey('kaart-selectie'))), findsOneWidget);
    });
  }

  testWidgets('op de pc verandert de kaart niet: daar is de ring van Pressable het teken', (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    await t.pumpWidget(_app(BredeKaart(_k('Een'), breedte: 300, hoogte: 90)));
    _knoop(t, 'Een').requestFocus();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kaart-selectie')), findsNothing);
    expect(find.byKey(const ValueKey('kaart-rust')), findsOneWidget);
  });
}
