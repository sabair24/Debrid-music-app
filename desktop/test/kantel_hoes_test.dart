// Hoezen die kantelen met een glans, een spiegeling eronder, en omdraaien met dikte (Saber, 18-10-2026).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:debridmusic/ui/draaihoes.dart';
import 'package:debridmusic/ui/kantel_hoes.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _doos(KantelHoes k, {bool minderBeweging = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: minderBeweging),
        child: Center(child: SizedBox.square(dimension: 200, child: k)),
      ),
    );

const _hoes = ColoredBox(color: Color(0xFF884422));

/// De hoek rond y van de kanteltransform, of null in rust.
double? _hoekY(WidgetTester t) {
  final glans = find.byKey(const ValueKey('kantel-glans'));
  if (glans.evaluate().isEmpty) return null;
  final tr = t.widget<Transform>(find.ancestor(of: glans, matching: find.byType(Transform)).first);
  return math.asin(tr.transform.entry(0, 2).clamp(-1.0, 1.0));
}

void main() {
  tearDown(() => KantelHoes.toestelVoorToets = null);

  test('nooit meer dan zes graden', () {
    final m = kantelMatrix(const Offset(1, 1));
    expect(math.asin(m.entry(0, 2)).abs(), lessThanOrEqualTo(kKantelHoek + 1e-9));
    expect(kKantelHoek, closeTo(6 * math.pi / 180, 1e-12));
  });

  testWidgets('in rust niets: geen transform en geen glans', (t) async {
    await t.pumpWidget(_doos(const KantelHoes(child: _hoes)));
    expect(_hoekY(t), isNull);
    // En er loopt niets dat om beelden blijft vragen.
    await t.pumpAndSettle();
  });

  testWidgets('met de muis: kantelt naar waar hij staat, en terug als hij weggaat', (t) async {
    await t.pumpWidget(_doos(const KantelHoes(child: _hoes)));
    final muis = await t.createGesture(kind: PointerDeviceKind.mouse);
    await muis.addPointer(location: Offset.zero);
    addTearDown(muis.removePointer);
    final midden = t.getCenter(find.byType(KantelHoes));
    await muis.moveTo(midden + const Offset(95, 0));
    await t.pump();
    await t.pump(kKantelVolg);
    final y = _hoekY(t);
    expect(y, isNotNull);
    expect(y!, greaterThan(kKantelHoek * .8), reason: 'rechts op de hoes: bijna de volle hoek');
    await muis.moveTo(const Offset(5, 5));
    await t.pump();
    await t.pump(kKantelVolg);
    expect(_hoekY(t), isNull, reason: 'weg van de hoes: terug in rust');
  });

  testWidgets('op een tv: schuin met de selectie, recht zonder', (t) async {
    await t.pumpWidget(_doos(const KantelHoes(bron: KantelBron.selectie, aan: true, child: _hoes)));
    await t.pump(kKantelVolg);
    expect(_hoekY(t), closeTo(math.asin(math.sin(kKantelSelectie.dx * kKantelHoek) * math.cos(kKantelSelectie.dy * kKantelHoek)), .02));
    await t.pumpWidget(_doos(const KantelHoes(bron: KantelBron.selectie, child: _hoes)));
    await t.pump(kKantelVolg);
    expect(_hoekY(t), isNull);
  });

  testWidgets('met het toestel: hoe je hem vasthoudt is rust, kantelen ervan kantelt de hoes', (t) async {
    final melder = StreamController<Offset>();
    KantelHoes.toestelVoorToets = () => melder.stream;
    await t.pumpWidget(_doos(const KantelHoes(bron: KantelBron.toestel, child: _hoes)));
    expect(melder.hasListener, isTrue);
    // Schuin vastgehouden (30° naar je toe): dat is de rust.
    for (var i = 0; i < 5; i++) {
      melder.add(const Offset(0, .5));
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pump(kKantelVolg);
    expect(_hoekY(t), isNull, reason: 'stilhouden kantelt niets, ook niet schuin');
    // Een hand die trilt (een tiende graad heen en weer): niets.
    for (var i = 0; i < 30; i++) {
      melder.add(Offset(i.isEven ? .002 : -.002, .5));
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pump(kKantelVolg);
    expect(_hoekY(t), isNull, reason: 'trillen kantelt niets en vraagt geen beelden');
    // Tien graden naar links, een kwart seconde lang (de melder meldt doorlopend).
    for (var i = 0; i < 16; i++) {
      melder.add(const Offset(.17, .5));
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pump(kKantelVolg);
    expect(_hoekY(t), isNotNull);
    // Niet de volle zes graden: de rust schuift intussen al een stukje mee (zo hoort het).
    expect(_hoekY(t)!.abs(), greaterThan(kKantelHoek * .5));
    await t.pumpWidget(const SizedBox());
    expect(melder.hasListener, isFalse, reason: 'weg uit Nu speelt: de melder luistert niet meer');
  });

  testWidgets('een bewegende hand: hooguit dertig nieuwe standen per seconde, geen eigen animatie', (t) async {
    // Gsm, 18-10-2026: Nu speelt tekende 120 beelden per seconde zolang de gsm in de hand lag.
    final melder = StreamController<Offset>();
    KantelHoes.toestelVoorToets = () => melder.stream;
    await t.pumpWidget(_doos(const KantelHoes(bron: KantelBron.toestel, child: _hoes)));
    melder.add(const Offset(0, .5));
    await t.pump(const Duration(milliseconds: 16));
    final standen = <double?>{};
    for (var i = 0; i < 60; i++) {
      // Een flinke, doorlopende beweging: elke melding is een andere stand.
      melder.add(Offset(.15 * math.sin(i / 6), .5));
      await t.pump(const Duration(milliseconds: 16));
      standen.add(_hoekY(t));
    }
    expect(standen.length, inInclusiveRange(10, 31), reason: 'een seconde bewegen: tien tot dertig standen');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('de app naar de achtergrond: de melder stopt; terug: hij luistert weer', (t) async {
    final melder = StreamController<Offset>.broadcast();
    KantelHoes.toestelVoorToets = () => melder.stream;
    await t.pumpWidget(_doos(const KantelHoes(bron: KantelBron.toestel, child: _hoes)));
    expect(melder.hasListener, isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(melder.hasListener, isFalse);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(melder.hasListener, isTrue);
  });

  testWidgets('minder beweging: niets kantelt, en er luistert geen melder', (t) async {
    final melder = StreamController<Offset>();
    KantelHoes.toestelVoorToets = () => melder.stream;
    await t.pumpWidget(_doos(const KantelHoes(bron: KantelBron.toestel, child: _hoes), minderBeweging: true));
    expect(melder.hasListener, isFalse);
    await t.pumpWidget(_doos(const KantelHoes(bron: KantelBron.selectie, aan: true, child: _hoes), minderBeweging: true));
    await t.pump(kKantelVolg);
    expect(_hoekY(t), isNull);
  });

  testWidgets('de spiegeling: ruim een vijfde van de hoes hoog, en hij vangt geen tikken', (t) async {
    await t.pumpWidget(MaterialApp(home: Center(child: HoesSpiegel(beeld: _png, maat: 300))));
    expect(t.getSize(find.byKey(const ValueKey('hoes-spiegel'))), const Size(300, 300 * kSpiegelHoogte));
    expect(find.ancestor(of: find.byKey(const ValueKey('hoes-spiegel')), matching: find.byType(IgnorePointer)),
        findsWidgets);
  });

  testWidgets('omdraaien: halverwege dikte en een veeg, in rust niets daarvan', (t) async {
    final c = DraaiHoesController();
    await t.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 200,
          child: DraaiHoes(controller: c, voor: _hoes, achter: const ColoredBox(color: Color(0xFF224488))),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('draai-veeg')), findsNothing);
    c.draai(heeftAchterkant: true);
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('draai-veeg')), findsOneWidget);
    expect(find.byKey(const ValueKey('draai-rand--1')), findsOneWidget);
    expect(find.byKey(const ValueKey('draai-rand-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('draai-schaduw')), findsOneWidget);
    await t.pumpAndSettle();
    // Omgedraaid en in rust: ook dan geen veeg meer.
    expect(veegSterkte(1), closeTo(0, 1e-9));
    expect(veegSterkte(.5), closeTo(.32, 1e-9));
  });

  test('de rand staat loodrecht op de hoes, aan zijn kant', () {
    // Op t = 0 staat de rand rechts op x = +w/2 en wijst hij naar je toe (een kwartslag).
    final m = randMatrix(0, 200, 1);
    expect(m.getTranslation().x, closeTo(100, 1e-6));
    // Een kwartslag: de x-as van de rand wijst nu langs z.
    expect(m.entry(0, 0), closeTo(0, 1e-9));
  });

  group('SpiegelVak (Nu speelt gestapeld)', () {
    Widget scherm({required double hoog, required ValueNotifier<bool> voor, required ValueNotifier<double> x}) =>
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: hoog,
              child: Column(children: [
                const SizedBox(height: 300, width: 300),
                Flexible(child: SpiegelVak(beeld: _png, maat: 300, blok: 390, zichtbaar: voor, x: x)),
                const SizedBox(height: 100, child: Text('titel')),
              ]),
            ),
          ),
        );

    testWidgets('met ruimte: de volle spiegeling, en de titel staat eronder', (t) async {
      final voor = ValueNotifier(true), x = ValueNotifier(0.0);
      await t.pumpWidget(scherm(hoog: 700, voor: voor, x: x));
      expect(t.getSize(find.byType(SpiegelVak)).height, SpiegelVak.hoogte(300));
      expect(t.getTopLeft(find.text('titel')).dy, greaterThanOrEqualTo(300 + SpiegelVak.hoogte(300)));
      expect(find.byType(HoesSpiegel), findsOneWidget);
    });

    testWidgets('weinig ruimte: korter en geknipt, niets loopt over en de hoes krimpt niet', (t) async {
      final voor = ValueNotifier(true), x = ValueNotifier(0.0);
      await t.pumpWidget(scherm(hoog: 420, voor: voor, x: x));
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(SpiegelVak)).height, 20);
      expect(t.getTopLeft(find.text('titel')).dy, 320, reason: 'de titel direct onder het korte vak');
    });

    testWidgets('weg tijdens het omdraaien, en hij schuift mee met de hoes', (t) async {
      final voor = ValueNotifier(true), x = ValueNotifier(0.0);
      await t.pumpWidget(scherm(hoog: 700, voor: voor, x: x));
      final eerst = t.getTopLeft(find.byType(HoesSpiegel)).dx;
      x.value = 40;
      await t.pump();
      expect(t.getTopLeft(find.byType(HoesSpiegel)).dx, closeTo(eerst + 40, .01));
      voor.value = false;
      await t.pump();
      expect(find.byType(HoesSpiegel), findsNothing);
    });
  });

  test('aangesloten: Nu speelt en de albumpagina spiegelen, de tegel kantelt', () {
    final bron = File('lib/main.dart').readAsStringSync();
    // Naast elkaar valt hij buiten het blok; gestapeld in zijn eigen vak, met de plaatnaam erboven, en op
    // de albumpagina met eigen ruimte (19-10-2026; op 18-10 lag hij over "Album" en de plaatnaam).
    expect(bron, contains('spiegel: !isTv && naast,'));
    expect(bron, contains('spiegel: !isTv,\n'));
    expect(bron, contains('SizedBox(height: isTv ? 16 : SpiegelVak.hoogte(artSize) + 16)'));
    final gestapeld = bron.substring(bron.indexOf("key: const Key('np-gestapeld')"));
    expect(gestapeld.substring(0, 600), contains('Flexible(\n                            child: SpiegelVak('));
    final plaatnaam = bron.indexOf('if (!zij && albumNaam.isNotEmpty)');
    expect(plaatnaam, greaterThan(0));
    expect(plaatnaam, lessThan(bron.indexOf('hoesMetTikken,\n              if (zij && albumNaam.isNotEmpty)')),
        reason: 'gestapeld staat de plaatnaam boven de hoes');
    expect(bron, contains('''kantel: isTv
                        ? KantelBron.selectie
                        : _isDesktop
                            ? KantelBron.muis
                            : KantelBron.toestel,'''));
    final tegel = File('lib/ui/tegel.dart').readAsStringSync();
    expect(tegel, contains('bron: isTv ? KantelBron.selectie : KantelBron.muis,'));
  });
}

/// Een PNG van 1 bij 1, doorzichtig.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00,
  0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
