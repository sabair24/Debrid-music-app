/// Het zwevende menu van pc, Mac en iPad (Saber, 17-10-2026).
///
/// **Waarom dit bestaat.** Op de pc stond de navigatie in een balk met het woordmerk en de telling, en
/// elke pagina legde er bij scrollen een strook glas achter: *"er is een soort van doorlopende balk dit
/// wil ik niet, ook met de verschuifbare pill erin, slepen met muis, of gewoon klikken"*. Nu is het één
/// capsule zoals op de Shield. Wat hier vastligt:
///
/// * alles staat in de capsule: Zoeken, de elf secties en Instellingen, en geen woordmerk meer;
/// * klikken opent meteen; slepen neemt de pil mee als lens, en pas na de veer opent de sectie;
/// * het muiswiel schuift de pil één sectie per tik en opent na een halve tel stilte;
/// * omlaag scrollen klapt hem in, bovenaan staat hij altijd open;
/// * op een breed scherm geen strook meer achter de capsule;
/// * de pil is helder glas, alleen tekst en icoon zijn paars ("doe enkel de tekst paars").
///
/// (Dit bestand heette al zo toen het nog over de oude balk ging; de naam staat in de lijst van de
/// bouwstraat.)
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart' show NavSections;
import 'package:debridmusic/ui/menu.dart';
import 'package:debridmusic/ui/menu_iconen.dart';

List<MenuPunt> _punten() => [
      const MenuPunt(sleutel: 'zoeken', label: 'Zoeken', icoon: MenuIcoonSoort.zoeken),
      for (final (id, label, _) in NavSections.items)
        MenuPunt(sleutel: MenuPunt.voorSectie(id), label: label, icoon: menuIcoonVoorSectie(id)!, sectie: id),
      const MenuPunt(sleutel: 'instellingen', label: 'Instellingen', icoon: MenuIcoonSoort.instellingen),
    ];

void main() {
  late final String hoofd = File('lib/main.dart').readAsStringSync();

  Future<List<MenuPunt>> menu(WidgetTester t,
      {double breedte = 2400, String actief = 'sectie-5', Duration wiel = kMenuWielWacht, bool in_ = false}) async {
    final gekozen = <MenuPunt>[];
    t.view.physicalSize = Size(breedte, 120);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: ZwevendMenu(
            punten: _punten(),
            actief: actief,
            onKies: gekozen.add,
            wielWacht: wiel,
            gekrompen: in_,
          ),
        ),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    return gekozen;
  }

  Rect pil(WidgetTester t) => t.getRect(find.byKey(const ValueKey('menu-pil')));

  group('wat er in staat', () {
    testWidgets('Zoeken, alle elf secties en Instellingen', (t) async {
      await menu(t);
      for (final p in _punten()) {
        expect(find.text(p.label), findsOneWidget, reason: '${p.label} hoort in de capsule');
      }
    });

    test('de schil geeft alle secties door, en het woordmerk staat niet meer in de balk', () {
      final a = hoofd.indexOf('List<MenuPunt> _menuPunten(int bezig)');
      expect(a, greaterThan(-1));
      final stuk = hoofd.substring(a, a + 900);
      expect(stuk, contains('for (final (id, label, _) in NavSections.items)'));
      expect(stuk, contains("sleutel: 'zoeken'"));
      expect(stuk, contains("sleutel: 'instellingen'"));
      final b = hoofd.indexOf('  Widget _pcBovenlaag() {');
      expect(b, greaterThan(-1));
      final balk = hoofd.substring(b, a);
      expect(balk, isNot(contains("'DebridMusic'")),
          reason: 'het woordmerk en de telling zijn uit de balk (Saber koos "alles erin, zoals Shield")');
      expect(balk, isNot(contains('albums · ')));
      expect(hoofd, contains('Widget _topBar() => isCompact(context) ? _compactTopBar() : _pcBovenlaag();'));
    });

    test('op een breed scherm geen strook achter de capsule', () {
      expect(hoofd, contains('if (!isTv && !isCompact(context)) return const SizedBox.shrink();'),
          reason: '_MeeschuivendGlas tekende de "doorlopende balk" die Saber niet wil');
    });

    test('de pil is helder glas, alleen de tekst is paars', () {
      const t = MenuTint.paars;
      expect(t.tekst, const Color(0xFFB3A2FF));
      for (final c in [t.boven, t.onder]) {
        expect(c.r, c.g, reason: 'geen kleur in het glas van de pil');
        expect(c.g, c.b);
      }
      final vorm = menuPilVorm(t);
      expect(vorm.boxShadow, isEmpty, reason: 'geen gekleurde gloed rond de pil');
    });
  });

  group('klikken en slepen', () {
    testWidgets('klik: de sectie opent meteen en de pil schuift erheen', (t) async {
      final gekozen = await menu(t);
      await t.tap(find.text('Albums'));
      expect(gekozen.map((p) => p.sectie), [0]);
      await t.pumpAndSettle();
      expect(pil(t).center.dx, closeTo(t.getCenter(find.text('Albums')).dx, 14));
    });

    testWidgets('Zoeken en Instellingen verschuiven de pil niet', (t) async {
      final gekozen = await menu(t);
      final voor = pil(t);
      await t.tap(find.text('Instellingen'));
      await t.pumpAndSettle();
      expect(gekozen.map((p) => p.sleutel), ['instellingen']);
      expect(pil(t), voor);
    });

    testWidgets('slepen: de pil gaat mee als lens, en pas na de veer opent de sectie', (t) async {
      final gekozen = await menu(t);
      final van = t.getCenter(find.text('Start'));
      final naar = t.getCenter(find.text('Artiesten'));
      final g = await t.startGesture(van, kind: PointerDeviceKind.mouse);
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset.lerp(van, naar, i / 8)!);
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey('menu-lens')), findsOneWidget, reason: 'tijdens het slepen een lens');
      expect(pil(t).center.dx, closeTo(naar.dx, 30), reason: 'de pil volgt de muis');
      expect(pil(t).height, greaterThan(34), reason: 'de lens zwelt op');
      expect(gekozen, isEmpty, reason: 'tijdens het slepen opent er niets');
      await g.up();
      await t.pump();
      expect(gekozen, isEmpty, reason: 'eerst de veer, dan pas de sectie');
      expect(find.byKey(const ValueKey('menu-lens')), findsNothing);
      await t.pump(kMenuSchuif + const Duration(milliseconds: 20));
      expect(gekozen.map((p) => p.sectie), [1]);
    });

    testWidgets('loslaten tussen twee woorden: het dichtstbijzijnde', (t) async {
      final gekozen = await menu(t);
      final van = t.getCenter(find.text('Start'));
      final a = t.getRect(find.text('Tracks'));
      // Net rechts van het midden van Tracks, vóór Artiesten.
      final g = await t.startGesture(van, kind: PointerDeviceKind.mouse);
      await g.moveTo(Offset(a.center.dx + 6, van.dy));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(gekozen.map((p) => p.sectie), [4]);
    });

    testWidgets('loslaten op de sectie waar je al bent opent niets', (t) async {
      final gekozen = await menu(t);
      final van = t.getCenter(find.text('Start'));
      final g = await t.startGesture(van, kind: PointerDeviceKind.mouse);
      await g.moveTo(van + const Offset(30, 0));
      await t.pump();
      await g.moveTo(van);
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(gekozen, isEmpty);
    });
  });

  group('het muiswiel', () {
    testWidgets('één sectie per tik, en pas na een halve tel stil opent die', (t) async {
      final gekozen = await menu(t);
      final hier = t.getCenter(find.text('Tracks'));
      final muis = TestPointer(1, PointerDeviceKind.mouse);
      await t.sendEventToBinding(muis.hover(hier));
      await t.sendEventToBinding(muis.scroll(const Offset(0, 100)));
      await t.pump(const Duration(milliseconds: 200));
      await t.sendEventToBinding(muis.scroll(const Offset(0, 100)));
      await t.pump(const Duration(milliseconds: 300));
      expect(gekozen, isEmpty, reason: 'de pil schoof door, nog niet stil');
      await t.pump(kMenuWielWacht);
      expect(gekozen.map((p) => p.sectie), [4], reason: 'Start → Albums → Tracks');
    });
  });

  group('inklappen', () {
    test('bovenaan altijd open, omlaag in, omhoog uit, trillen verandert niets', () {
      expect(menuInklappen(nu: true, positie: 10, stap: 30), isFalse);
      expect(menuInklappen(nu: false, positie: 400, stap: 12), isTrue);
      expect(menuInklappen(nu: true, positie: 400, stap: -12), isFalse);
      expect(menuInklappen(nu: true, positie: 400, stap: 2), isTrue);
      expect(menuInklappen(nu: false, positie: 400, stap: -2), isFalse);
    });

    testWidgets('ingeklapt: alleen de sectie waar je bent', (t) async {
      await menu(t, actief: 'sectie-0', in_: true);
      expect(find.byKey(const ValueKey('menu-ingeklapt')), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Tracks'), findsNothing);
    });

    test('de schil luistert naar het scrollen van de pagina\'s', () {
      expect(hoofd, contains('child: NotificationListener<ScrollUpdateNotification>(\n'
          '                          onNotification: _opScrol,'));
    });
  });
}
