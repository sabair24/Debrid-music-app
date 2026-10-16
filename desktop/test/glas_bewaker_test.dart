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

  testWidgets('twee te zware vensters na elkaar: van vloeibaar naar mat, dan naar plat', (t) async {
    await t.pumpWidget(_vlak());
    expect(GlasKwaliteit.actief, 1);
    GlasKwaliteit.stand.value = GlasStand.vloeibaar;
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar, reason: 'één venster is nog geen patroon');
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    expect(GlasKwaliteit.stand.value, GlasStand.mat);
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    expect(GlasKwaliteit.stand.value, GlasStand.plat);
  });

  testWidgets('een licht venster ertussen begint de telling opnieuw', (t) async {
    await t.pumpWidget(_vlak());
    GlasKwaliteit.stand.value = GlasStand.vloeibaar;
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 3000));
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
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
