// Saber, 24-10-2026, op de Shield: "als ik in de schuifbaar terecht kom van vertraging bij samen spelen geraak ik
// er niet meer uit om dat up en down ook de schuiver verzet, das niet de bedoeling enkel links en rechts".
// Op tv verzetten ← en → de schuif; ↑ en ↓ gaan naar wat erboven of eronder staat. Op de pc blijft een schuif
// ook met ↑/↓ verschuiven, zoals Flutter dat met een toetsenbord doet.
import 'dart:io';

import 'package:debridmusic/main.dart' show SamenVertragingInstelling;
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _scherm(AppSettings s) => ChangeNotifierProvider<AppSettings>.value(
      value: s,
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            TextButton(key: const ValueKey('boven'), autofocus: true, onPressed: () {}, child: const Text('Boven')),
            const SamenVertragingInstelling(),
            TextButton(key: const ValueKey('onder'), onPressed: () {}, child: const Text('Onder')),
          ]),
        ),
      ),
    );

bool _heeftFocus(WidgetTester t, String sleutel) =>
    t.binding.focusManager.primaryFocus?.context?.findAncestorWidgetOfExactType<TextButton>()?.key ==
    ValueKey(sleutel);

bool _schuifHeeftFocus(WidgetTester t) {
  final ctx = t.binding.focusManager.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is Slider || ctx.findAncestorWidgetOfExactType<Slider>() != null;
}

void main() {
  tearDown(() => setTvModeForTest(false));

  testWidgets('op tv: ← en → verzetten de schuif, ↑ en ↓ gaan eruit', (t) async {
    setTvModeForTest(true);
    final s = AppSettings()..readOnly = true;
    await t.pumpWidget(_scherm(s));
    await t.pump();
    expect(_heeftFocus(t, 'boven'), isTrue);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(_schuifHeeftFocus(t), isTrue, reason: '↓ vanaf de knop erboven komt op de schuif');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(s.samenVertragingMs, 10, reason: '→ schuift één stap (10 ms) naar rechts');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(s.samenVertragingMs, -10);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(s.samenVertragingMs, -10, reason: '↓ verzet de schuif niet');
    expect(_heeftFocus(t, 'onder'), isTrue, reason: '↓ gaat naar wat eronder staat');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(_schuifHeeftFocus(t), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(s.samenVertragingMs, -10, reason: '↑ verzet de schuif niet');
    expect(_heeftFocus(t, 'boven'), isTrue, reason: '↑ gaat naar wat erboven staat');

    await t.pumpWidget(const SizedBox());
  });

  test('het stuk rechts van het bolletje is zichtbaar: niet de paneelkleur', () {
    // Op de Shield (24-10-2026) zag −50 ms eruit als helemaal rechts: Material kleurt dat stuk met
    // `surfaceContainerHighest`, en dat valt in het kleurenschema van de app terug op `surface` (het paneel).
    final bron = File('lib/main.dart').readAsStringSync();
    final thema = bron.indexOf('theme: ThemeData(');
    expect(thema, greaterThan(0));
    expect(bron.indexOf('sliderTheme: SliderThemeData(inactiveTrackColor: kLijn)', thema), greaterThan(thema));
    expect(const ColorScheme.light(surface: Color(0xFF123456)).surfaceContainerHighest, const Color(0xFF123456),
        reason: 'als Flutter dit ooit anders doet, mag de regel weg');
  });

  testWidgets('op de pc verschuift ↑ de schuif nog, zoals Flutter dat doet', (t) async {
    final s = AppSettings()..readOnly = true;
    await t.pumpWidget(_scherm(s));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(_schuifHeeftFocus(t), isTrue);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(s.samenVertragingMs, 10);

    await t.pumpWidget(const SizedBox());
  });
}
