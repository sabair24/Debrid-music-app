// Het glas onthoudt dat vloeibaar op dit toestel te zwaar was (Saber, 19-10-2026: "onthouden"). Gemeten
// op de S26: vloeibaar 5,8 ms rasteren per beeld en tien beelden te laat, mat 3,0 ms en geen enkel;
// en elke start begon weer vloeibaar.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:debridmusic/ui/glas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<ui.FrameTiming> _beelden(int n, int rasterUs) => [
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
  late Directory map;
  late File bestand;
  var nu = DateTime(2026, 10, 19, 17, 18);

  /// Zoals het opstarten op een toestel met lensshader: vloeibaar is de hoogste stand.
  void start() {
    GlasKwaliteit.hoogste = GlasStand.vloeibaar;
    GlasKwaliteit.stand.value = GlasStand.vloeibaar;
    GlasKwaliteit.pasBesluitToe();
  }

  /// Drie te zware vensters: de bewaker zakt een stand.
  void teZwaar(int rasterUs) {
    for (var i = 0; i < kGlasTeZwaar; i++) {
      GlasKwaliteit.opBeelden(_beelden(kGlasVenster, rasterUs));
    }
  }

  setUp(() {
    GlasKwaliteit.vergeet();
    GlasKwaliteit.hzVoorToets = 120;
    nu = DateTime(2026, 10, 19, 17, 18);
    GlasKwaliteit.klok = () => nu;
    map = Directory.systemTemp.createTempSync('dm_glas_');
    bestand = File('${map.path}${Platform.pathSeparator}glas_besluit.json');
    GlasKwaliteit.besluitBestand = () => bestand;
  });
  tearDown(() {
    GlasKwaliteit.vergeet();
    if (map.existsSync()) map.deleteSync(recursive: true);
  });

  testWidgets('te zwaar gebleken: het besluit staat op schijf, met het tijdstip en hoe zwaar', (t) async {
    await t.pumpWidget(_vlak());
    start();
    teZwaar(8100);
    expect(GlasKwaliteit.stand.value, GlasStand.mat);
    expect(GlasKwaliteit.onthouden, isTrue);
    final j = jsonDecode(bestand.readAsStringSync()) as Map<String, dynamic>;
    expect(DateTime.parse(j['vloeibaarTeZwaar'] as String), nu);
    expect(j['p90Ms'], closeTo(8.1, .01));
    GlasKwaliteit.vergeet(); // de timer voor de volgende poging
  });

  testWidgets('DE KERN: de volgende start begint in mat, met de regel en de knop in Instellingen', (t) async {
    await t.pumpWidget(_vlak());
    start();
    teZwaar(8100);
    // Een nieuwe sessie, een uur later.
    GlasKwaliteit.vergeet();
    GlasKwaliteit.besluitBestand = () => bestand;
    nu = nu.add(const Duration(hours: 1));
    GlasKwaliteit.klok = () => nu;
    start();
    expect(GlasKwaliteit.stand.value, GlasStand.mat, reason: 'niet eerst nog eens haperen');
    expect(GlasKwaliteit.onthouden, isTrue);
    expect(GlasKwaliteit.terugval.value?.zin, contains('te zwaar op dit toestel (17:18, 8,1 ms per beeld)'));
    GlasKwaliteit.vergeet();
  });

  test('na een dag probeert de start het weer vloeibaar', () {
    bestand.writeAsStringSync(jsonEncode({'vloeibaarTeZwaar': nu.toIso8601String(), 'p90Ms': 8.1}));
    nu = nu.add(kGlasOnthoud + const Duration(minutes: 1));
    start();
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
    expect(GlasKwaliteit.onthouden, isFalse);
  });

  testWidgets('vanzelf opnieuw proberen blijft binnen de dag bij mat; van plat wel terug naar mat', (t) async {
    await t.pumpWidget(_vlak());
    start();
    teZwaar(8100);
    nu = nu.add(const Duration(hours: 2));
    GlasKwaliteit.probeerOpnieuw();
    expect(GlasKwaliteit.stand.value, GlasStand.mat, reason: 'niet terug naar vloeibaar');
    GlasKwaliteit.stand.value = GlasStand.plat;
    GlasKwaliteit.probeerOpnieuw();
    expect(GlasKwaliteit.stand.value, GlasStand.mat);
    expect(GlasKwaliteit.terugval.value, isNotNull, reason: 'de regel "te zwaar" en de knop blijven staan');
    GlasKwaliteit.vergeet();
  });

  testWidgets('"Opnieuw proberen" in Instellingen: vloeibaar, en het besluit vervalt', (t) async {
    await t.pumpWidget(_vlak());
    start();
    teZwaar(8100);
    GlasKwaliteit.probeerOpnieuw(handmatig: true);
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
    expect(GlasKwaliteit.onthouden, isFalse);
    expect(bestand.existsSync(), isFalse);
    GlasKwaliteit.vergeet();
  });

  testWidgets('lag het niet aan het glas (mat niet sneller), dan wordt er ook niets onthouden', (t) async {
    await t.pumpWidget(_vlak());
    start();
    teZwaar(9000);
    expect(GlasKwaliteit.stand.value, GlasStand.mat);
    // Mat even zwaar: de terugval hielp niet.
    GlasKwaliteit.opBeelden(_beelden(kGlasVenster, 9000));
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
    expect(GlasKwaliteit.onthouden, isFalse);
    expect(bestand.existsSync(), isFalse);
    GlasKwaliteit.vergeet();
  });

  testWidgets('in een toets wordt niets bewaard, tenzij de toets zelf een bestand opgeeft', (t) async {
    GlasKwaliteit.vergeet();
    GlasKwaliteit.hzVoorToets = 120;
    GlasKwaliteit.klok = () => nu;
    expect(GlasKwaliteit.besluitBestand(), isNull);
    await t.pumpWidget(_vlak());
    start();
    teZwaar(8100);
    expect(GlasKwaliteit.stand.value, GlasStand.mat);
    expect(bestand.existsSync(), isFalse);
    GlasKwaliteit.vergeet();
  });

  test('aangesloten: het opstarten past het besluit toe', () {
    final glas = File('lib/ui/glas.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(glas, contains('        doel.value = GlasStand.vloeibaar;\n        hoogste = GlasStand.vloeibaar;\n        pasBesluitToe();'));
  });
}
