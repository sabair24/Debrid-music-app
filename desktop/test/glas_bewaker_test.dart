// De bewaker van het glas en de lensrand (ui/glas.dart, 16-10-2026). Saber koos vloeibaar glas met
// als voorwaarde: "waar het te veel kost, valt het vanzelf terug op matglas".
import 'dart:io';
import 'dart:ui' as ui;

import 'package:debridmusic/ui/glas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een rij beelden met deze tekentijd (in microseconden). De andere tijden doen er hier niet toe.
List<ui.FrameTiming> beelden(int n, int rasterUs) => [
      for (var i = 0; i < n; i++)
        ui.FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 1000,
          rasterStart: 1000,
          rasterFinish: 1000 + rasterUs,
          rasterFinishWallTime: 1000 + rasterUs,
        ),
    ];

Widget _vlak() => const Directionality(
    textDirection: TextDirection.ltr,
    child: GlasVlak(vorm: BorderRadius.all(Radius.circular(12)), vulling: BoxDecoration(color: Color(0x80101219))));

void main() {
  setUp(GlasKwaliteit.vergeet);
  tearDown(GlasKwaliteit.vergeet);

  test('het 90e percentiel', () {
    expect(GlasKwaliteit.negentigste([for (var i = 1; i <= 100; i++) i]), 90);
    expect(GlasKwaliteit.negentigste([...List.filled(85, 5), ...List.filled(15, 50)]), 50);
    expect(GlasKwaliteit.negentigste([...List.filled(95, 5), ...List.filled(5, 50)]), 5,
        reason: 'een paar uitschieters zijn geen zwaar scherm');
  });

  testWidgets('drie te zware vensters na elkaar: van vloeibaar naar mat, dan naar plat', (t) async {
    await t.pumpWidget(_vlak());
    expect(GlasKwaliteit.actief, 1);
    expect(kGlasTeZwaar, 3);
    GlasKwaliteit.stand.value = GlasStand.vloeibaar;
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar,
        reason: 'twee vensters zijn anderhalve seconde: een pagina die opengaat, geen patroon');
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    expect(GlasKwaliteit.stand.value, GlasStand.mat);
    for (var i = 0; i < kGlasTeZwaar; i++) {
      GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    }
    expect(GlasKwaliteit.stand.value, GlasStand.plat);
  });

  testWidgets('een licht venster ertussen begint de telling opnieuw', (t) async {
    await t.pumpWidget(_vlak());
    GlasKwaliteit.stand.value = GlasStand.vloeibaar;
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 3000));
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
  });

  testWidgets('de eerste tien seconden telt hij niet mee', (t) async {
    // Shaders die voor het eerst gebouwd worden, hoezen, de catalogus: zonder aanloop zakte het glas
    // zo binnen drie seconden naar plat, voor de hele sessie (16-10-2026: een menu zonder vervaging).
    await t.pumpWidget(_vlak());
    GlasKwaliteit.stand.value = GlasStand.vloeibaar;
    for (var i = 0; i < 6; i++) {
      GlasKwaliteit.opBeelden(beelden(kGlasVenster, 20000), verstreken: const Duration(seconds: 4));
    }
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
    for (var i = 0; i < kGlasTeZwaar; i++) {
      GlasKwaliteit.opBeelden(beelden(kGlasVenster, 20000), verstreken: kGlasAanloop);
    }
    expect(GlasKwaliteit.stand.value, GlasStand.mat, reason: 'daarna wel');
  });

  testWidgets('het verslag voor warmte.log: de stand, en één keer waarom hij zakte', (t) async {
    await t.pumpWidget(_vlak());
    GlasKwaliteit.stand.value = GlasStand.vloeibaar;
    expect(GlasKwaliteit.verslag(), 'glasstand vloeibaar');
    for (var i = 0; i < kGlasTeZwaar; i++) {
      GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    }
    final v = GlasKwaliteit.verslag();
    expect(v, startsWith('glasstand mat (vloeibaar → mat, 90e percentiel 9.0 ms'));
    expect(GlasKwaliteit.verslag(), 'glasstand mat', reason: 'de reden staat één keer in de log');
  });

  group('dicht genoeg (Saber, 16-10-2026: "alles is veel te transparant")', () {
    double gemiddeld(BoxDecoration d) {
      final c = (d.gradient! as LinearGradient).colors;
      return c.map((k) => k.a).reduce((a, b) => a + b) / c.length;
    }

    test('vervaagd een waas, plat bijna dicht', () {
      expect(gemiddeld(glasVulling(const Color(0xFF2B3142), GlasStand.mat)), closeTo(kGlasDekking, .02));
      expect(gemiddeld(glasVulling(const Color(0xFF2B3142), GlasStand.vloeibaar)), closeTo(kGlasDekking, .02));
      expect(kGlasDekking, greaterThanOrEqualTo(.8), reason: 'met 74 % las hij de lijst eronder');
      expect(gemiddeld(glasVulling(const Color(0xFF2B3142), GlasStand.plat)), 1.0,
          reason: 'zonder vervaging is de vulling het enige wat tegenhoudt');
    });

    testWidgets('een vlak met een kleur volgt de stand', (t) async {
      final vulling = find.byWidgetPredicate((w) =>
          w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient != null);
      double dekking() => gemiddeld(t.widget<DecoratedBox>(vulling).decoration as BoxDecoration);
      Widget vlak() => const Directionality(
          textDirection: TextDirection.ltr, child: GlasVlak(kleur: Color(0xFF2B3142), child: SizedBox(width: 100, height: 100)));
      GlasKwaliteit.stand.value = GlasStand.mat;
      await t.pumpWidget(vlak());
      expect(dekking(), closeTo(kGlasDekking, .02));
      GlasKwaliteit.stand.value = GlasStand.plat;
      await t.pump();
      expect(dekking(), 1.0);
    });

    test('het menu bij lang indrukken gebruikt die vulling, de tv blijft dicht', () {
      final menu = File('lib/ui/itemmenu.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(menu, contains('vulling: isTv ? const BoxDecoration(color: kBovenop) : null,\n          kleur: isTv ? null : kBovenop,'));
      expect(menu, isNot(contains('alpha: .74')));
    });
  });

  test('zonder glas op het scherm telt de bewaker niets', () {
    GlasKwaliteit.stand.value = GlasStand.vloeibaar;
    for (var i = 0; i < 5; i++) {
      GlasKwaliteit.opBeelden(beelden(kGlasVenster, 20000));
    }
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar,
        reason: 'een zwaar scherm zonder glas is niet de schuld van het glas');
  });

  testWidgets('plat glas tekent geen vervaging; mat glas het gedeelde filter, gegroepeerd', (t) async {
    GlasKwaliteit.stand.value = GlasStand.plat;
    await t.pumpWidget(_vlak());
    expect(find.byType(BackdropFilter), findsNothing);
    GlasKwaliteit.stand.value = GlasStand.mat;
    await t.pump();
    final f = t.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(identical(f.filter, glasMat), isTrue);
  });

  test('de waarden voor de shader: in zijn volgorde, in fysieke pixels', () {
    final w = lensWaarden(const Rect.fromLTWH(10, 700, 400, 100), 3, hoek: 16, rand: 9, buiging: 7, licht: .55);
    expect(w, [30, 2100, 1200, 300, 48, 27, 21, .55]);
  });

  test('de shader verwacht die volgorde, en staat in pubspec', () {
    final frag = File('shaders/glas_lens.frag').readAsStringSync();
    final volgorde = [
      frag.indexOf('uniform vec2 uSize;'),
      frag.indexOf('uniform vec4 uRect;'),
      frag.indexOf('uniform vec4 uP;'),
      frag.indexOf('uniform sampler2D uTex;'),
    ];
    expect(volgorde.every((i) => i >= 0), isTrue);
    expect(volgorde, orderedEquals([...volgorde]..sort()),
        reason: 'een andere volgorde geeft in Flutter 3.41.9 geen fout, alleen een leeg vlak');
    expect(File('pubspec.yaml').readAsStringSync(), contains('- shaders/glas_lens.frag'));
  });
}
