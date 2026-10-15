// Een selectie die je niet ziet (Shield, 15-10-2026): een InkWell om een Container met een eigen
// achtergrond tekent zijn focus ONDER die achtergrond. ui/tv_halo.dart legt er een witte rand over.
import 'dart:io';

import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/tv_halo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// De kaart zoals "Zeg wat je wil horen" hem bouwt: de InkWell zit BUITEN de gekleurde Container.
Widget kaart(FocusNode n, {double breed = 300, double hoog = 80}) => InkWell(
      focusNode: n,
      borderRadius: BorderRadius.circular(12),
      onTap: () {},
      child: Container(
        width: breed,
        height: hoog,
        decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(12)),
      ),
    );

final _rand = find.byWidgetPredicate((w) =>
    w is DecoratedBox &&
    w.decoration is BoxDecoration &&
    (w.decoration as BoxDecoration).border == Border.all(color: Colors.white, width: 3));

Future<void> focus(WidgetTester tester, FocusNode n) async {
  n.requestFocus();
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  tearDown(() => setTvModeForTest(false));

  group('haloVoor', () {
    testWidgets('een InkWell om een gekleurde kaart: ja, met de hoek van de kaart', (tester) async {
      final n = FocusNode();
      addTearDown(n.dispose);
      await tester.pumpWidget(MaterialApp(home: Material(child: Center(child: kaart(n)))));
      final h = haloVoor(n.context!);
      expect(h.nodig, isTrue);
      expect(h.hoek, 12);
    });

    testWidgets('een knop tekent zijn eigen rand: nee', (tester) async {
      final tekst = FocusNode(), icoon = FocusNode(), verheven = FocusNode();
      addTearDown(tekst.dispose);
      addTearDown(icoon.dispose);
      addTearDown(verheven.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Material(
              child: Column(children: [
        TextButton(focusNode: tekst, onPressed: () {}, child: const Text('Speel alles')),
        IconButton(focusNode: icoon, onPressed: () {}, icon: const Icon(Icons.shuffle)),
        ElevatedButton(focusNode: verheven, onPressed: () {}, child: const Text('Bekijken')),
      ]))));
      expect(haloVoor(tekst.context!).nodig, isFalse, reason: 'TextButton');
      expect(haloVoor(icoon.context!).nodig, isFalse, reason: 'IconButton');
      expect(haloVoor(verheven.context!).nodig, isFalse, reason: 'ElevatedButton');
    });

    testWidgets('iets zonder InkWell (een tekstveld): nee', (tester) async {
      final n = FocusNode();
      addTearDown(n.dispose);
      await tester.pumpWidget(MaterialApp(home: Material(child: TextField(focusNode: n))));
      expect(haloVoor(n.context!).nodig, isFalse);
    });
  });

  group('TvFocusHalo', () {
    testWidgets('op een tv: een witte rand om de kaart die de selectie heeft', (tester) async {
      setTvModeForTest(true);
      final n = FocusNode();
      addTearDown(n.dispose);
      await tester.pumpWidget(MaterialApp(
          builder: (_, kind) => TvFocusHalo(child: kind!),
          home: Material(child: Center(child: kaart(n)))));
      expect(_rand, findsNothing, reason: 'zonder selectie geen rand');
      await focus(tester, n);
      expect(_rand, findsOneWidget);
      final kaartRect = tester.getRect(find.byType(InkWell));
      expect(tester.getRect(_rand), kaartRect.inflate(3));
    });

    testWidgets('op een knop niet: die heeft zijn eigen rand al', (tester) async {
      setTvModeForTest(true);
      final n = FocusNode();
      addTearDown(n.dispose);
      await tester.pumpWidget(MaterialApp(
          builder: (_, kind) => TvFocusHalo(child: kind!),
          home: Material(
              child: Center(child: TextButton(focusNode: n, onPressed: () {}, child: const Text('Speel'))))));
      await focus(tester, n);
      expect(_rand, findsNothing);
    });

    testWidgets('verdwijnt als de selectie naar een knop gaat', (tester) async {
      setTvModeForTest(true);
      final k = FocusNode(), knop = FocusNode();
      addTearDown(k.dispose);
      addTearDown(knop.dispose);
      await tester.pumpWidget(MaterialApp(
          builder: (_, kind) => TvFocusHalo(child: kind!),
          home: Material(
              child: Column(children: [
            kaart(k),
            TextButton(focusNode: knop, onPressed: () {}, child: const Text('Speel')),
          ]))));
      await focus(tester, k);
      expect(_rand, findsOneWidget);
      await focus(tester, knop);
      expect(_rand, findsNothing);
    });

    testWidgets('half uit een lijst geschoven: de rand blijft binnen de lijst', (tester) async {
      setTvModeForTest(true);
      final n = FocusNode();
      addTearDown(n.dispose);
      final rol = ScrollController();
      addTearDown(rol.dispose);
      await tester.pumpWidget(MaterialApp(
          builder: (_, kind) => TvFocusHalo(child: kind!),
          home: Material(
              child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 400,
                    height: 200,
                    child: ListView(controller: rol, children: [
                      const SizedBox(height: 160),
                      kaart(n),
                      const SizedBox(height: 400),
                    ]),
                  )))));
      // Vastzetten vóór de focus: Flutter schuift hem anders zelf in beeld.
      await focus(tester, n);
      rol.jumpTo(0);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final lijst = tester.getRect(find.byType(ListView));
      final rand = tester.getRect(_rand);
      expect(rand.bottom, lessThanOrEqualTo(lijst.bottom + 3.01),
          reason: 'de kaart steekt onder de lijst uit; de rand mag dat niet');
      expect(rand.top, closeTo(160 - 3, .01));
    });

    testWidgets('buiten een tv doet hij niets', (tester) async {
      final n = FocusNode();
      addTearDown(n.dispose);
      await tester.pumpWidget(MaterialApp(
          builder: (_, kind) => TvFocusHalo(child: kind!),
          home: Material(child: Center(child: kaart(n)))));
      await focus(tester, n);
      expect(_rand, findsNothing);
    });
  });

  test('aangesloten: boven de Navigator, alleen op een tv', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final b = main.indexOf('builder: (context, child) {');
    expect(b, greaterThan(-1));
    final blok = main.substring(b, main.indexOf('return Shortcuts(', b));
    expect(blok, contains('if (isTv) {'));
    expect(blok, contains('inhoud = TvFocusHalo(child: inhoud);'));
  });
}
