/// Een pijl op de tv laat de pagina niet verspringen (Saber, 18-10-2026: "bij het navigeren van links
/// naar rechts springen de hoezen, dit is niet fijn, is te bruut").
///
/// Op de Shield gefilmd (b12000): een rij hoezen stond net te hoog voor het beeld. Flutter schoof bij
/// elke pijl eerst zelf, met `ensureVisible` in één beeld, en daarna schoof de app de rij terug naar
/// zijn vaste plek. Zo sprong de pagina bij elke stap naar rechts 35 punten omhoog en gleed hij terug.
library;

import 'dart:io';

import 'package:debridmusic/tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een rij tegels van [hoog] punten hoog, zodat hij op zijn vaste plek onder het beeld uit steekt.
Widget _rij(String naam, {required double hoog}) => SizedBox(
      height: hoog + 20,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: 12,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => Center(
          child: Pressable(
            key: ValueKey('$naam$i'),
            onPressed: () {},
            ringOnFocus: false,
            child: SizedBox(width: 100, height: hoog),
          ),
        ),
      ),
    );

/// Zoals in de app: het eigen focusverzoek boven de navigator.
Widget _app(Widget pagina, {bool zonderSprong = true}) => MaterialApp(
      builder: (_, kind) => zonderSprong
          ? FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvFocusZonderSprong),
              child: kind!,
            )
          : kind!,
      home: Scaffold(body: pagina),
    );

FocusNode _knoop(WidgetTester t, String sleutel) =>
    Focus.of(t.element(find.descendant(of: find.byKey(ValueKey(sleutel)), matching: find.byType(GestureDetector)).first));

/// Een pijl naar rechts, en dan elk beeld tot het stil staat: hoe ver week de pagina af van waar hij stond?
Future<double> _grootsteUitwijking(WidgetTester t, ScrollController pagina) async {
  final stond = pagina.offset;
  var grootste = 0.0;
  tvPijlStap(FocusManager.instance.primaryFocus!, TraversalDirection.right);
  // Meteen, nog voor er een beeld is: hier zat de sprong.
  grootste = (pagina.offset - stond).abs();
  for (var i = 0; i < 40; i++) {
    await t.pump(const Duration(milliseconds: 16));
    final nu = (pagina.offset - stond).abs();
    if (nu > grootste) grootste = nu;
  }
  return grootste;
}

void main() {
  setUp(() {
    setTvModeForTest(true);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    setTvModeForTest(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Widget pagina(ScrollController c) => SizedBox(
        height: 300,
        child: ListView(controller: c, children: [
          const SizedBox(height: 200),
          // Op de vaste plek begint de rij 56 punten onder de bovenrand en loopt hij tot 56 + 270 =
          // 326, voorbij de onderrand van 300. Precies wat de Albums-rij op de Shield deed.
          _rij('a', hoog: 250),
          const SizedBox(height: 600),
        ]),
      );

  testWidgets('rechts in een te hoge rij: de pagina blijft staan, ook niet één beeld', (t) async {
    final c = ScrollController();
    await t.pumpWidget(_app(pagina(c)));
    _knoop(t, 'a0').requestFocus();
    await t.pumpAndSettle();
    expect(c.offset, greaterThan(0), reason: 'de rij staat op zijn vaste plek');

    expect(await _grootsteUitwijking(t, c), lessThan(1),
        reason: 'de rij staat al op zijn vaste plek; zonder dit sprong de pagina eerst naar de onderrand');
    expect(_knoop(t, 'a1').hasPrimaryFocus, isTrue);
  });

  testWidgets('tegenproef: met Flutters eigen verzoek springt hij wel', (t) async {
    final c = ScrollController();
    await t.pumpWidget(_app(pagina(c), zonderSprong: false));
    _knoop(t, 'a0').requestFocus();
    await t.pumpAndSettle();
    expect(await _grootsteUitwijking(t, c), greaterThan(10),
        reason: 'anders bewijst de eerste toets niets: dan was er hier nooit een sprong');
  });

  testWidgets('wat geen Pressable is, schuift nog steeds in beeld, maar zacht', (t) async {
    final c = ScrollController();
    await t.pumpWidget(_app(SizedBox(
      height: 300,
      child: ListView(controller: c, children: [
        for (var i = 0; i < 12; i++)
          InkWell(key: ValueKey('r$i'), onTap: () {}, child: const SizedBox(height: 60, width: 300)),
      ]),
    )));
    Focus.of(t.element(find.descendant(of: find.byKey(const ValueKey('r4')), matching: find.byType(SizedBox)).first))
        .requestFocus();
    await t.pump();
    expect(c.offset, 0, reason: 'r4 staat van 240 tot 300: nog in beeld');

    FocusManager.instance.primaryFocus!.focusInDirection(TraversalDirection.down);
    expect(c.offset, 0, reason: 'geen sprong in hetzelfde beeld');
    // Elk beeld: de eerste stap van de pagina is een stukje, niet de hele weg.
    final stappen = <double>[];
    for (var i = 0; i < 30 && c.offset < 59.5; i++) {
      await t.pump(const Duration(milliseconds: 16));
      if (c.offset > 0) stappen.add(c.offset);
    }
    expect(stappen, isNotEmpty, reason: 'hij schoof helemaal niet');
    expect(stappen.first, lessThan(45), reason: 'onderweg, niet in één keer');
    await t.pumpAndSettle();
    expect(c.offset, closeTo(60, .5), reason: 'r5 (300 tot 360) staat nu tegen de onderrand');
  });

  testWidgets('een Pressable met de selectie schuift zelf, iets anders niet', (t) async {
    await t.pumpWidget(_app(Column(children: [
      Pressable(key: const ValueKey('tegel'), onPressed: () {}, child: const SizedBox(width: 100, height: 100)),
      InkWell(key: const ValueKey('ink'), onTap: () {}, child: const SizedBox(width: 100, height: 40)),
    ])));
    final tegel = _knoop(t, 'tegel');
    tegel.requestFocus();
    await t.pump();
    expect(schuiftZelf(tegel.context!), isTrue, reason: 'die brengt zichzelf naar zijn vaste plek');
    final ink = Focus.of(t.element(find.descendant(of: find.byKey(const ValueKey('ink')), matching: find.byType(SizedBox)).first));
    ink.requestFocus();
    await t.pump();
    expect(schuiftZelf(ink.context!), isFalse, reason: 'een InkWell schuift niets uit zichzelf');
  });

  test('in de app staat het eigen verzoek boven alles op een tv', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvFocusZonderSprong),'));
  });
}
