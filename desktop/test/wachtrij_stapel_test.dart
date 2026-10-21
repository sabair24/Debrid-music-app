// De wachtrij als stapel op Nu speelt (Saber, 19-10-2026): naar links, ruim, omhoog vegen om te
// bladeren (de voorste vliegt achteraan de rij), omlaag terug, tik om te spelen, vanzelf terug.
import 'dart:io';

import 'package:debridmusic/ui/wachtrij_stapel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een voorste hoes die telt hoe vaak hij opnieuw begint, en hoe vaak hij aangetikt werd.
class _Voorste extends StatefulWidget {
  const _Voorste({required this.begonnen, required this.getikt});
  final List<int> begonnen, getikt;
  @override
  State<_Voorste> createState() => _VoorsteState();
}

class _VoorsteState extends State<_Voorste> {
  @override
  void initState() {
    super.initState();
    widget.begonnen.add(1);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => widget.getikt.add(1),
        child: const SizedBox(width: 260, height: 200, child: ColoredBox(color: Colors.teal)),
      );
}

void main() {
  group('stapelPlek', () {
    test('vooraan, en erachter naar links en omhoog, kleiner en donkerder', () {
      final v = stapelPlek(0, 200);
      expect((v.x, v.y, v.schaal, v.dim, v.zicht), (0.0, 0.0, 1.0, 0.0, 1.0));
      final een = stapelPlek(1, 200);
      expect(een.x, closeTo(200 * kStapelStapX, 1e-9), reason: 'naar links');
      expect(een.y, closeTo(200 * kStapelStapY, 1e-9), reason: 'omhoog');
      expect(een.schaal, closeTo(1 - kStapelKrimp, 1e-9));
      expect(een.dim, greaterThan(0));
      expect(stapelPlek(kStapelZichtbaar.toDouble(), 200).zicht, 0, reason: 'vijf in beeld, de zesde niet');
    });

    test('wie wegvliegt gaat eerst omhoog en vooraan, daarna achteraan, en verdwijnt', () {
      final heen = stapelPlek(-.3, 200);
      expect(heen.y, lessThan(-60), reason: 'omhoog');
      expect(heen.voorop, isTrue);
      final terug = stapelPlek(-.7, 200);
      expect(terug.voorop, isFalse, reason: 'over de top: nu achter de rest');
      expect(terug.x, lessThan(0), reason: 'naar achteraan de rij, links');
      expect(stapelPlek(-.95, 200).zicht, lessThan(.5));
      expect(stapelPlek(-1, 200).zicht, 0);
    });

    test('wat links en boven uitsteekt, past in de ruimte die de stapel vraagt', () {
      // De achterste in beeld (d = 4): zijn linker- en bovenrand.
      const m = 200.0;
      final p = stapelPlek(kStapelZichtbaar - 1.0, m);
      final links = p.x + m * (1 - p.schaal) / 2;
      final boven = p.y + m * (1 - p.schaal) / 2;
      expect(-links, closeTo(m * kStapelLinks, 1e-6));
      expect(-boven, closeTo(m * kStapelBoven, 1e-6));
    });
  });

  group('WachtrijStapel', () {
    late List<int> gespeeld, begonnen, getikt, weg;
    setUp(() {
      gespeeld = [];
      begonnen = [];
      getikt = [];
      weg = [];
    });

    Future<GlobalKey<WachtrijStapelState>> zet(WidgetTester t, {StapelBesturing? besturing}) async {
      final k = GlobalKey<WachtrijStapelState>();
      await t.pumpWidget(MaterialApp(
        home: Center(
          child: WachtrijStapel(
            key: k,
            maat: 200,
            blok: 260,
            voorste: _Voorste(begonnen: begonnen, getikt: getikt),
            volgende: const [null, null, null, null, null],
            onSpeel: gespeeld.add,
            onWeg: () => weg.add(1),
            besturing: besturing,
            terugNa: const Duration(seconds: 4),
          ),
        ),
      ));
      return k;
    }

    testWidgets('omhoog vegen bladert een stap, een tik speelt dat nummer', (t) async {
      final k = await zet(t);
      await t.drag(find.byKey(const ValueKey('wachtrij-stapel')), const Offset(0, -150));
      await t.pumpAndSettle();
      expect(k.currentState!.blad, 1);
      await t.tap(find.byKey(const ValueKey('wachtrij-stapel')));
      await t.pump();
      expect(gespeeld, [1]);
      expect(getikt, isEmpty, reason: 'de verborgen voorste hoes vangt geen tik op');
      expect(k.currentState!.blad, 0);
    });

    testWidgets('de spelende hoes blijft bestaan tijdens het bladeren (zijn cd draait door)', (t) async {
      final k = await zet(t);
      await t.drag(find.byKey(const ValueKey('wachtrij-stapel')), const Offset(0, -300));
      await t.pumpAndSettle();
      expect(k.currentState!.blad, greaterThanOrEqualTo(2));
      await t.drag(find.byKey(const ValueKey('wachtrij-stapel')), const Offset(0, 600));
      await t.pumpAndSettle();
      expect(k.currentState!.blad, 0);
      expect(begonnen, [1], reason: 'niet weggegooid en opnieuw gebouwd');
    });

    testWidgets('zonder tik veert hij terug', (t) async {
      final k = await zet(t);
      await t.drag(find.byKey(const ValueKey('wachtrij-stapel')), const Offset(0, -150));
      await t.pumpAndSettle();
      expect(k.currentState!.blad, 1);
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(k.currentState!.blad, 0);
      expect(gespeeld, isEmpty);
    });

    testWidgets('omlaag vegen terwijl hij vooraan staat sluit Nu speelt, zoals overal', (t) async {
      await zet(t);
      await t.fling(find.byKey(const ValueKey('wachtrij-stapel')), const Offset(0, 200), 1200);
      await t.pumpAndSettle();
      expect(weg, [1]);
    });

    testWidgets('vooraan is een tik op de hoes gewoon een tik op de hoes', (t) async {
      await zet(t);
      await t.tap(find.byType(_Voorste));
      await t.pump(const Duration(milliseconds: 400));
      expect(getikt, [1]);
      expect(gespeeld, isEmpty);
    });

    testWidgets('de tv: links en rechts bladeren, OK speelt', (t) async {
      final b = StapelBesturing();
      addTearDown(b.dispose);
      final k = await zet(t, besturing: b);
      b.blader(1);
      b.blader(1);
      await t.pumpAndSettle();
      expect(k.currentState!.blad, 2);
      b.blader(-1);
      await t.pumpAndSettle();
      expect(k.currentState!.blad, 1);
      b.speel();
      await t.pump();
      expect(gespeeld, [1]);
    });

    testWidgets('niet verder dan er nummers zijn', (t) async {
      final k = await zet(t);
      await t.drag(find.byKey(const ValueKey('wachtrij-stapel')), const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(k.currentState!.blad, 5);
    });
  });

  test('aangesloten: geladen bij het opstarten, in het ⋯-menu, de spiegeling wijkt, tik springt', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('  StapelKeuze.laad();'));
    expect(main, contains("MenuRegel(Icons.layers_rounded, 'Wachtrij als stapel', () => StapelKeuze.zet(true))"));
    expect(main, contains('_toonItemMenu(knopContext, _metStapelKeuze(_nummerMenu(knopContext, t)))'));
    // Op de tv staat de rij met ⋯ er niet: daar een eigen knop achteraan (Shield, 19-10-2026).
    final tv = main.indexOf("key: const ValueKey('np-meer-tv'),");
    expect(tv, greaterThan(0));
    expect(main.substring(tv - 400, tv), contains('if (isTv && t != null) ...['));
    expect(main.substring(tv, tv + 400), contains('_metStapelKeuze(_nummerMenu(knopContext, t))'));
    expect(main, contains('spiegel: !dwars && !stapelAan,'));
    expect(main, contains('p.springNaar(p.currentIndex + n),'),
        reason: 'zoals een tik in de wachtrijlijst: springen, niet opnieuw schudden (21-10-2026)');
    expect(main, contains('final hoesMaat = stapelAan ? hoesMaatVol / (1 + kStapelBoven) : hoesMaatVol;'));
  });
}
