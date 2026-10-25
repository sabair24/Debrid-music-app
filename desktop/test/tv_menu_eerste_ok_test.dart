// Op de Shield nagelopen (25-10-2026): lang OK op een nummer opent het menu, maar de EERSTE OK daarna deed niets —
// het menu ging dicht zonder dat de gekozen regel liep ("Beluisteren" bij een klaargezette cd-kopie). Eerst omlaag en
// weer omhoog, en dan OK: dan wel. Deze toets speelt dat na met echte toetsen.
import 'dart:io';

import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/itemmenu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => setTvModeForTest(true));
  tearDown(() => setTvModeForTest(false));

  testWidgets('lang OK opent het menu, en de eerste OK daarna kiest de eerste regel', (tester) async {
    var eerste = 0, tweede = 0;
    final menu = ItemMenu(titel: 'Digital Love', blokken: [
      [
        MenuRegel(Icons.compare_arrows_rounded, 'Beluisteren', () => eerste++),
        MenuRegel(Icons.check_rounded, 'Deze houden', () => tweede++),
      ],
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: Pressable(
              autofocus: true,
              onPressed: () {},
              onLongPress: () => toonItemMenu(context, menu),
              child: const Text('Digital Love'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Lang OK, zoals de afstandsbediening: neer, herhalingen, los.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Beluisteren'), findsOneWidget, reason: 'het menu staat open');
    await tester.pump(const Duration(seconds: 2));
    // De eerste OK in het menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Beluisteren'), findsNothing, reason: 'het menu is dicht');
    expect(eerste, 1, reason: 'en de eerste regel liep');
    expect(tweede, 0);
  });

  test('aangesloten: de vraag "weggooien?" zet de selectie op Nee', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(
        RegExp(r"autofocus: true,\n\s+onPressed: \(\) => Navigator\.of\(c\)\.pop\(false\),\n\s+child: const Text\('Nee'\)\)")
            .allMatches(main)
            .length,
        2,
        reason: 'de klaargezette kopie en het twijfelgeval');
  });
}
