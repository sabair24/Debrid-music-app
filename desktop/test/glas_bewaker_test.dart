// De bewaker van het glas en de lensrand (ui/glas.dart, 16-10-2026). Saber koos vloeibaar glas met
// als voorwaarde: "waar het te veel kost, valt het vanzelf terug op matglas".
import 'dart:io';
import 'dart:ui' as ui;

import 'package:debridmusic/artwork.dart' show HoesVlek;
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/glas.dart';
import 'package:debridmusic/ui/vlak.dart';
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
  // Op 120 Hz, zoals de gsm: het budget is dan de ondergrens van 7 ms. Het nepscherm van flutter_test
  // zegt 60 Hz, en dan is 9 ms per beeld gewoon op tijd.
  setUp(() {
    GlasKwaliteit.vergeet();
    GlasKwaliteit.hzVoorToets = 120;
  });
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
    // Mat is sneller (7,5 tegen 9 ms: de terugval hielp) maar nog altijd te zwaar.
    for (var i = 0; i < kGlasTeZwaar; i++) {
      GlasKwaliteit.opBeelden(beelden(kGlasVenster, 7500));
    }
    expect(GlasKwaliteit.stand.value, GlasStand.plat);
    // En plat is weer sneller: dan blijft hij plat.
    GlasKwaliteit.opBeelden(beelden(kGlasVenster, 4000));
    expect(GlasKwaliteit.stand.value, GlasStand.plat);
    GlasKwaliteit.vergeet(); // de klok voor opnieuw proberen mag niet blijven lopen
  });

  group('alleen het glas krijgt de schuld van wat het glas doet (pc, 18-10-2026)', () {
    testWidgets('een terugval die niet sneller is, gaat terug: het lag niet aan het glas', (t) async {
      await t.pumpWidget(_vlak());
      final regels = <String>[];
      GlasKwaliteit.meld = regels.add;
      addTearDown(() => GlasKwaliteit.meld = null);
      GlasKwaliteit.stand.value = GlasStand.vloeibaar;
      for (var i = 0; i < kGlasTeZwaar; i++) {
        GlasKwaliteit.opBeelden(beelden(kGlasVenster, 15000));
      }
      expect(GlasKwaliteit.stand.value, GlasStand.mat);
      // Mat: nog altijd 14 ms (zo stond het in kop.log: 15,4 → 14,3 → plat).
      GlasKwaliteit.opBeelden(beelden(kGlasVenster, 14000));
      expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
      expect(GlasKwaliteit.terugval.value, isNull, reason: 'geen "te zwaar" in Instellingen voor iets wat het glas niet deed');
      expect(regels.last, contains('het lag niet aan het glas'));
      // En daarna een half uur niet opnieuw schuldig verklaren.
      for (var i = 0; i < 3 * kGlasTeZwaar; i++) {
        GlasKwaliteit.opBeelden(beelden(kGlasVenster, 15000));
      }
      expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
      GlasKwaliteit.vergeet();
    });

    testWidgets('beelden na een stilte tellen niet mee', (t) async {
      await t.pumpWidget(_vlak());
      final regels = <String>[];
      GlasKwaliteit.meld = regels.add;
      addTearDown(() => GlasKwaliteit.meld = null);
      GlasKwaliteit.stand.value = GlasStand.vloeibaar;
      // Elf beelden per seconde, elk 15 ms: een scherm dat stil staat en af en toe iets opbouwt.
      List<ui.FrameTiming> los(int n) => [
            for (var i = 0; i < n; i++)
              ui.FrameTiming(
                vsyncStart: i * 90000,
                buildStart: i * 90000,
                buildFinish: i * 90000 + 1000,
                rasterStart: i * 90000 + 1000,
                rasterFinish: i * 90000 + 16000,
                rasterFinishWallTime: i * 90000 + 16000,
              ),
          ];
      for (var i = 0; i < 4 * kGlasTeZwaar; i++) {
        GlasKwaliteit.opBeelden(los(kGlasVenster));
      }
      expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
      expect(regels, isEmpty, reason: 'zelfs geen terugval die daarna teruggedraaid wordt');
      GlasKwaliteit.vergeet();
    });
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
    GlasKwaliteit.vergeet(); // de klok voor opnieuw proberen mag niet blijven lopen
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
    GlasKwaliteit.vergeet(); // de klok voor opnieuw proberen mag niet blijven lopen
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
      expect(menu, contains('vulling: isTv ? BoxDecoration(color: kBovenop) : null,\n          kleur: isTv ? null : kBovenop,'));
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

  test('geen eigen y-omkering op GLES: sinds Flutter 3.47 doet de engine dat zelf', () {
    // flutter#186554: een offscreen-pass keert op GLES de y om in de vertex-shader. Kwam de oude
    // omkering terug, dan stond de lens op Windows (ANGLE) en oudere Androids op zijn kop.
    final frag = File('shaders/glas_lens.frag').readAsStringSync();
    expect(frag, isNot(contains('uv.y = 1.0 - uv.y;')));
    expect(frag, isNot(contains('#ifdef IMPELLER_TARGET_OPENGLES')));
    for (final werk in ['build-release.yml', 'windows_build.yml', 'apple_build.yml']) {
      expect(File('../.github/workflows/$werk').readAsStringSync(), contains("flutter-version: '3.47.7'"),
          reason: '$werk: de shader is geschreven voor 3.47; op 3.41 zou hij op GLES op zijn kop staan');
    }
  });

  group('per schermritme, met een weg terug (Saber, 18-10-2026)', () {
    test('het budget: 85 % van een beeld, nooit krapper dan 7 ms', () {
      expect(glasBudgetVoor(60).inMicroseconds, 14167, reason: 'de Shield: 16,7 ms per beeld');
      expect(glasBudgetVoor(120).inMicroseconds, 7083, reason: 'gsm en iPad');
      expect(glasBudgetVoor(144), kGlasBudget, reason: 'de pc: de ondergrens');
      expect(glasBudgetVoor(0), kGlasBudget, reason: 'onbekend ritme');
    });

    testWidgets('op een scherm van 60 Hz is 12 ms per beeld op tijd', (t) async {
      // De Shield zakte zo binnen een halve minuut naar plat, bij 10 tot 14 ms (warmte.log, 18-10).
      await t.pumpWidget(_vlak());
      GlasKwaliteit.stand.value = GlasStand.vloeibaar;
      GlasKwaliteit.hzVoorToets = 60;
      for (var i = 0; i < 2 * kGlasTeZwaar; i++) {
        GlasKwaliteit.opBeelden(beelden(kGlasVenster, 12000));
      }
      expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
      GlasKwaliteit.hzVoorToets = 120;
      for (var i = 0; i < kGlasTeZwaar; i++) {
        GlasKwaliteit.opBeelden(beelden(kGlasVenster, 12000));
      }
      expect(GlasKwaliteit.stand.value, GlasStand.mat, reason: 'op 120 Hz is 12 ms te laat');
      GlasKwaliteit.vergeet(); // de klok voor opnieuw proberen mag niet blijven lopen
    });

    testWidgets('een terugval staat in Instellingen, met een knop die het opnieuw probeert', (t) async {
      GlasKwaliteit.hoogste = GlasStand.vloeibaar;
      GlasKwaliteit.stand.value = GlasStand.vloeibaar;
      GlasKwaliteit.hzVoorToets = 120;
      GlasKwaliteit.klok = () => DateTime(2026, 10, 18, 10, 42);
      await t.pumpWidget(const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [
            GlasVlak(kleur: Color(0xFF2B3142), child: SizedBox(width: 50, height: 50)),
            GlasRegel(),
          ])));
      expect(find.text('Glas: vloeibaar'), findsOneWidget);
      expect(find.byKey(const ValueKey('glas-opnieuw')), findsNothing);
      for (var i = 0; i < kGlasTeZwaar; i++) {
        GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9100));
      }
      await t.pump();
      expect(find.text('Glas: mat — te zwaar op dit toestel (10:42, 9,1 ms per beeld)'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('glas-opnieuw')));
      await t.pump();
      expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
      expect(find.text('Glas: vloeibaar'), findsOneWidget);
      GlasKwaliteit.stand.value = GlasStand.mat; // zodat de toets niet met een open klok eindigt
    });

    testWidgets('vanzelf opnieuw: bij een paginawissel na de wachttijd, of na tien minuten', (t) async {
      await t.pumpWidget(_vlak());
      var nu = DateTime(2026, 10, 18, 10);
      GlasKwaliteit.klok = () => nu;
      GlasKwaliteit.hoogste = GlasStand.vloeibaar;
      GlasKwaliteit.stand.value = GlasStand.vloeibaar;
      GlasKwaliteit.hzVoorToets = 120;
      void zwaar() {
        for (var i = 0; i < kGlasTeZwaar; i++) {
          GlasKwaliteit.opBeelden(beelden(kGlasVenster, 9000));
        }
      }

      zwaar();
      expect(GlasKwaliteit.stand.value, GlasStand.mat);
      nu = nu.add(const Duration(seconds: 30));
      GlasKwaliteit.paginaGewisseld();
      expect(GlasKwaliteit.stand.value, GlasStand.mat, reason: 'binnen de eerste minuut niet');
      nu = nu.add(const Duration(seconds: 31));
      GlasKwaliteit.paginaGewisseld();
      expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar, reason: 'na een minuut, bij een andere pagina');

      // Weer te zwaar: nu wacht hij twee minuten.
      zwaar();
      expect(GlasKwaliteit.stand.value, GlasStand.mat);
      nu = nu.add(const Duration(seconds: 90));
      GlasKwaliteit.paginaGewisseld();
      expect(GlasKwaliteit.stand.value, GlasStand.mat, reason: 'de wachttijd verdubbelde');
      nu = nu.add(const Duration(seconds: 31));
      GlasKwaliteit.paginaGewisseld();
      expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);

      // Zonder paginawissel: na tien minuten vanzelf.
      zwaar();
      expect(GlasKwaliteit.stand.value, GlasStand.mat);
      await t.pump(const Duration(minutes: 9));
      expect(GlasKwaliteit.stand.value, GlasStand.mat);
      await t.pump(const Duration(minutes: 1, seconds: 1));
      expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
    });

    test('aangesloten: paginawissels en meldingen in kop.log', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('    if (_view != id) GlasKwaliteit.paginaGewisseld();'));
      expect(main, contains('    Timer.run(() => kopLog.line(r));'));
      expect(main, contains('                    const GlasRegel(),'));
      expect(File('lib/navigatie.dart').readAsStringSync(), contains('    GlasKwaliteit.paginaGewisseld();'));
    });
  });


  group('korrel en dekking (Saber, 18-10-2026)', () {
    test('de korrel: 64 bij 64, elke korrel op 2 %, en elke keer dezelfde', () {
      final a = GlasKorrel.pixels();
      expect(a.length, 64 * 64 * 4);
      for (var i = 3; i < a.length; i += 4) {
        expect(a[i], 5, reason: '2 % van 255');
      }
      expect(GlasKorrel.pixels(), a, reason: 'een vaste zaadwaarde: overal en altijd dezelfde ruis');
      // Voorvermenigvuldigd: de grijswaarde is al maal de dekking (0 tot 5). Een waarde boven de
      // dekking tekende helder op (voorbeeld van 18-10-2026: vol ruis in plaats van 2 %).
      final grijs = <int, int>{};
      for (var i = 0; i < a.length; i += 4) {
        expect(a[i], lessThanOrEqualTo(a[i + 3]), reason: 'voorvermenigvuldigd: nooit lichter dan de dekking');
        grijs[a[i]] = (grijs[a[i]] ?? 0) + 1;
      }
      expect(grijs.keys.toSet(), {0, 1, 2, 3, 4, 5});
      expect(grijs.values.every((n) => n > 300), isTrue, reason: 'echte ruis over alle waarden, geen vlak');
    });

    testWidgets('in elk glasvlak en elke glasknop, niet op een tv', (t) async {
      await t.pumpWidget(_vlak());
      expect(find.byType(GlasKorrelLaag), findsOneWidget);
      setTvModeForTest(true);
      addTearDown(() => setTvModeForTest(false));
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_vlak());
      expect(find.byType(GlasKorrelLaag), findsNothing, reason: 'van drie meter zie je hem niet');
      setTvModeForTest(false);
      GlasKwaliteit.stand.value = GlasStand.mat;
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: glasRuit()));
      expect(find.byType(GlasKorrelLaag), findsOneWidget, reason: 'ook op de knoppen');
    });

    test('dichter boven een lijst, lichter boven een beeld', () {
      expect(glasDekking(GlasStand.mat), kGlasDekking);
      expect(kGlasDekking, inInclusiveRange(.80, .90), reason: '"80-90 % boven tekstlijsten"');
      expect(glasDekking(GlasStand.mat, ondergrond: GlasOndergrond.beeld), kGlasDekkingBeeld);
      expect(kGlasDekkingBeeld, closeTo(.60, .001));
      expect(glasDekking(GlasStand.plat, ondergrond: GlasOndergrond.beeld), 1.0, reason: 'plat blijft dicht');
    });
  });


  group('de glans volgt het licht (Saber, 18-10-2026)', () {
    tearDown(GlasLicht.vergeet);

    test('de vlek valt op het dichtste punt van de rand, en is feller naarmate het licht dichterbij is', () {
      const vak = Rect.fromLTWH(0, 0, 400, 80);
      final boven = glansOp(vak, const Offset(100, -50));
      expect(boven.plek, const Offset(100, 0));
      final erin = glansOp(vak, const Offset(200, 40));
      expect(erin.plek, const Offset(200, 40));
      expect(erin.sterkte, kGlansVol, reason: 'de muis op het glas: op zijn felst');
      final ver = glansOp(vak, const Offset(1400, 900));
      expect(ver.plek, const Offset(400, 80), reason: 'rechtsonder: de hoek die het dichtst bij is');
      expect(ver.sterkte, kGlansZacht, reason: 'ver weg: zacht, maar nooit weg');
      expect(boven.sterkte, lessThan(erin.sterkte));
      expect(boven.sterkte, greaterThan(ver.sterkte));
    });

    testWidgets('elk glasvlak tekent opnieuw als het licht beweegt, en bij Minder beweging niet', (t) async {
      await t.pumpWidget(_vlak());
      final r = t.renderObject<RenderGlasGlans>(find.byType(GlasGlans));
      expect(r.debugNeedsPaint, isFalse);
      GlasLicht.muis(const Offset(30, 30));
      expect(r.debugNeedsPaint, isTrue, reason: 'de vlek schuift mee met de muis');
      await t.pump();
      expect(r.debugNeedsPaint, isFalse);
    });

    test('aangesloten: de muis op de pc, de selectie op een tv, en op de knoppen', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('onPointerHover: (e) => GlasLicht.muis(e.position),'));
      expect(main, contains('  if (isTv) {\n    GlasLicht.volgSelectie();'));
      expect(File('lib/ui/vlak.dart').readAsStringSync(), contains('const RepaintBoundary(child: GlasGlans(vorm: hoek)),'));
    });
  });


  group('nooit glas op glas (Saber, 18-10-2026: "onderste wordt dicht")', () {
    Widget vlak({Widget? kind, bool bovenop = false}) => GlasVlak(
        kleur: const Color(0xFF2B3142), bovenop: bovenop, child: kind ?? const SizedBox(width: 100, height: 60));

    testWidgets('glas in glas: alleen het buitenste vervaagt', (t) async {
      GlasKwaliteit.stand.value = GlasStand.mat;
      await t.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: vlak(kind: vlak())));
      expect(find.byType(GlasVlak), findsNWidgets(2));
      expect(find.byType(BackdropFilter), findsOneWidget, reason: 'het knopje in de balk is een vulling, geen tweede glas');
    });

    testWidgets('een menu bovenop: het glas eronder is zolang dicht, en daarna weer glas', (t) async {
      GlasKwaliteit.stand.value = GlasStand.mat;
      Widget scherm({required bool menu}) => Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(children: [
              vlak(),
              Positioned(left: 0, top: 0, width: 80, height: 40, child: glasRuit()),
              if (menu) Positioned(left: 0, top: 100, child: vlak(bovenop: true)),
            ]),
          );
      await t.pumpWidget(scherm(menu: false));
      expect(find.byType(BackdropFilter), findsNWidgets(2), reason: 'de balk en de knop');
      await t.pumpWidget(scherm(menu: true));
      await t.pump();
      expect(find.byType(BackdropFilter), findsOneWidget, reason: 'alleen het menu zelf');
      await t.pumpWidget(scherm(menu: false));
      await t.pump();
      await t.pump();
      expect(GlasKwaliteit.bovenop.value, 0);
      expect(find.byType(BackdropFilter), findsNWidgets(2), reason: 'menu dicht: weer glas');
    });

    test('aangesloten: het menu bij lang indrukken en het blad Verder liggen bovenop', () {
      expect(File('lib/ui/itemmenu.dart').readAsStringSync(), contains('          bovenop: true,'));
      expect(File('lib/main.dart').readAsStringSync(), contains('        bovenop: true,'));
    });
  });


  group('nep-glas op de tv, zoals Windows Mica (Saber, 18-10-2026)', () {
    tearDown(() => setTvModeForTest(false));

    testWidgets('geen live vervaging meer, ook niet onder menu en balk; wel de vlekken van wat er speelt', (t) async {
      setTvModeForTest(true);
      await GlasKwaliteit.inrichten();
      expect(GlasKwaliteit.tvBalk.value, GlasStand.plat, reason: 'de Shield haalde 17-20 ms per beeld met glas');
      expect(GlasKwaliteit.hoogste, GlasStand.plat, reason: 'en dus ook nooit opnieuw proberen');
      GlasKwaliteit.micaVlekken.value = const [HoesVlek(.3, .5, 0xFFCC3322, 1)];
      await t.pumpWidget(const Directionality(
          textDirection: TextDirection.ltr,
          child: GlasVlak(kleur: Color(0xFF1A1D27), balk: true, child: SizedBox(width: 300, height: 56))));
      expect(find.byType(BackdropFilter), findsNothing);
      final laag = t.widget<HoesVlekkenLaag>(find.byType(HoesVlekkenLaag));
      expect(laag.vlekken, hasLength(1));
      expect(laag.sterkte, kMicaSterkte);
    });

    testWidgets('buiten de tv geen nep-glas: daar is het echte glas', (t) async {
      GlasKwaliteit.stand.value = GlasStand.mat;
      GlasKwaliteit.micaVlekken.value = const [HoesVlek(.3, .5, 0xFFCC3322, 1)];
      await t.pumpWidget(const Directionality(
          textDirection: TextDirection.ltr,
          child: GlasVlak(kleur: Color(0xFF1A1D27), balk: true, child: SizedBox(width: 300, height: 56))));
      expect(find.byType(HoesVlekkenLaag), findsNothing);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    test('aangesloten: de speler geeft zijn vlekken door op een tv', () {
      expect(File('lib/main.dart').readAsStringSync(), contains('GlasKwaliteit.micaVlekken.value = player.hoesVlekken;'));
    });
  });

}
