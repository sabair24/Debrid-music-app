/// Glas dat een knop is — en zich gedraagt als glas én als knop.
///
/// **Waarom dit er is.** Op 11-09-2026 werden de knoppen op de artiestpagina van dichte pillen glas
/// (Saber: "de buttons moeten transparant glass blur effect hebben, waarbij de achtergrond licht
/// vervormd zoals bij apple"). Glas is vier lagen die precies goed ten opzichte van elkaar moeten
/// liggen, en elk van de vier heeft een manier om stil te falen: een vervaging die alleen vervaagt,
/// een vulling die met de vervaging meeverdwijnt, een schaduw die het glas van binnen zwart maakt, en
/// een knop waarvan de focusring doormidden geknipt wordt. Geen daarvan zie je in een toets die alleen
/// kijkt of de lagen er ZIJN — dat was precies de les van `glasbalk_test.dart`.
library;

import 'dart:ui' show ImageFilter;

import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => setTvModeForTest(false));

  Future<void> zet(WidgetTester t, Widget knop) =>
      t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: knop))));

  GlasKnop radio([VoidCallback? tik]) =>
      GlasKnop(icoon: Icons.radio_rounded, label: 'Radio', onPressed: tik ?? () {});

  final gekleurd = find.byWidgetPredicate((w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).gradient != null);

  // Met een predicaat en niet met `byType`: `FilledButton.icon` mag een subklasse opleveren, en dan
  // vindt `byType` hem niet en slaagt de bewering hieronder om de verkeerde reden.
  final knop = find.byWidgetPredicate((w) => w is FilledButton);

  double dekking(WidgetTester t) =>
      (t.widget<DecoratedBox>(gekleurd).decoration as BoxDecoration).gradient!.colors.first.a;

  testWidgets('DE KERN: de ruit vervormt, hij vervaagt niet alleen', (t) async {
    await zet(t, radio());
    final filter = t.widget<BackdropFilter>(find.byType(BackdropFilter)).filter;
    expect(filter, glasVervorming);
    expect(filter, isNot(ImageFilter.blur(sigmaX: 14, sigmaY: 10)),
        reason: 'alleen vervagen is matglas: de achtergrond wordt vaag, niet vervormd');
  });

  testWidgets('DE VAL: de vulling is GEEN kind van de vervaging', (t) async {
    // Dezelfde storing als bij de balk: op een Android-toestel valt een BackdropFilter binnen een
    // scrollende lijst weg, en deze knoppen staan in een `CustomScrollView`.
    await zet(t, radio());
    expect(gekleurd, findsOneWidget);
    expect(find.descendant(of: find.byType(BackdropFilter), matching: gekleurd), findsNothing,
        reason: 'valt de vervaging op een toestel weg, dan gaat de kleur mee — en staat er niets');
  });

  testWidgets('DE VAL: de knop staat buiten de afknipping', (t) async {
    await zet(t, radio());
    expect(knop, findsOneWidget);
    expect(find.descendant(of: find.byType(ClipRRect), matching: knop), findsNothing,
        reason: 'binnen de afknipping wordt de focusring doormidden geknipt');
  });

  testWidgets('DE VAL: de schaduw valt alleen buiten de pil', (t) async {
    await zet(t, radio());
    final schaduwen = [
      for (final d in t.widgetList<DecoratedBox>(find.byType(DecoratedBox)))
        if (d.decoration case BoxDecoration(:final boxShadow?)) ...boxShadow,
    ];
    expect(schaduwen, isNotEmpty, reason: 'zonder schaduw ligt de knop plat op de foto');
    for (final s in schaduwen) {
      expect(s.blurStyle, BlurStyle.outer,
          reason: 'een gewone schaduw tekent ook onder de ruit, en dan vervaagt het glas een '
              'achtergrond die al voor een kwart zwart is');
    }
  });

  testWidgets('DE GRENS: op een televisie geen vervaging, wel meer dekking', (t) async {
    await zet(t, radio());
    final pc = dekking(t);

    setTvModeForTest(true);
    await zet(t, radio());
    expect(find.byType(BackdropFilter), findsNothing,
        reason: 'een BackdropFilter is op een Tegra X1 het duurste wat er op het scherm staat');
    expect(dekking(t), greaterThan(pc),
        reason: 'zonder vervaging lost de pil van drie meter afstand op in het donker');
  });

  testWidgets('DE KERN: hij doet wat een knop doet, ook de ronde', (t) async {
    var getikt = 0;
    await zet(t, radio(() => getikt++));
    await t.tap(find.text('Radio'));

    await zet(
        t,
        GlasKnop.rond(
            icoon: Icons.arrow_back_rounded, tooltip: 'Terug', onPressed: () => getikt++));
    await t.tap(find.byIcon(Icons.arrow_back_rounded));
    expect(getikt, 2, reason: 'het glas ligt over de knop en vangt de tik weg');
  });

  testWidgets('DE GRENS: minstens 44 punten, en de ruit even groot als de knop', (t) async {
    // 44 is het kleinste wat Apple een vinger laat raken. En de ruit moet precies zo groot zijn als
    // de knop: anders licht er bij aanwijzen een kleinere pil op binnen een grotere.
    await zet(t, radio());
    final maat = t.getSize(knop);
    expect(maat.height, greaterThanOrEqualTo(44));
    expect(t.getSize(find.byType(GlasKnop)), maat,
        reason: 'de ruit is groter of kleiner dan de knop die erin licht');

    await zet(t, GlasKnop.rond(icoon: Icons.arrow_back_rounded, onPressed: () {}));
    expect(t.getSize(find.byType(IconButton)).height, greaterThanOrEqualTo(44));
    expect(t.getSize(find.byType(GlasKnop)), t.getSize(find.byType(IconButton)));
  });
}
