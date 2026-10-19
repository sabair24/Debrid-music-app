/// Het systeem vraagt dicht glas (Saber, 18-10-2026: "Minder transparantie en batterijbesparing:
/// volgen, dan dicht glas").
library;

import 'dart:io';

import 'package:debridmusic/systeem_glas.dart';
import 'package:debridmusic/ui/glas.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const kanaal = MethodChannel('debridmusic/systeem');

  setUp(GlasKwaliteit.vergeet);
  tearDown(() {
    SysteemGlas.stop();
    GlasKwaliteit.vergeet();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(kanaal, null);
  });

  void systeemZegt(bool? dicht) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(kanaal, (call) async {
        if (call.method != 'dichtGlas') return null;
        if (dicht == null) throw PlatformException(code: 'kapot');
        return dicht;
      });

  test('de vraag: ja, nee, en een kapot of ontbrekend kanaal is nee', () async {
    systeemZegt(true);
    expect(await SysteemGlas.vraag(), isTrue);
    systeemZegt(false);
    expect(await SysteemGlas.vraag(), isFalse);
    systeemZegt(null);
    expect(await SysteemGlas.vraag(), isFalse, reason: 'een fout is geen verzoek om dicht glas');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(kanaal, null);
    expect(await SysteemGlas.vraag(), isFalse, reason: 'een oudere bouw zonder het kanaal');
  });

  testWidgets('dicht zolang het systeem het vraagt, daarna terug naar wat er stond', (t) async {
    GlasKwaliteit.hoogste = GlasStand.vloeibaar;
    GlasKwaliteit.stand.value = GlasStand.vloeibaar;
    await t.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: GlasRegel()));
    GlasKwaliteit.zetSysteemDicht(true);
    await t.pump();
    expect(GlasKwaliteit.stand.value, GlasStand.plat);
    expect(find.text('Glas: dicht — minder transparantie of batterijbesparing staat aan op dit toestel'), findsOneWidget);
    expect(find.byKey(const ValueKey('glas-opnieuw')), findsNothing, reason: 'opnieuw proberen gaat tegen het systeem in');
    GlasKwaliteit.probeerOpnieuw(handmatig: true);
    expect(GlasKwaliteit.stand.value, GlasStand.plat);
    GlasKwaliteit.zetSysteemDicht(false);
    await t.pump();
    expect(GlasKwaliteit.stand.value, GlasStand.vloeibaar);
    expect(find.text('Glas: vloeibaar'), findsOneWidget);
  });

  testWidgets('de start vraagt het meteen', (t) async {
    GlasKwaliteit.stand.value = GlasStand.mat;
    systeemZegt(true);
    SysteemGlas.start();
    await t.pump();
    expect(GlasKwaliteit.systeemDicht.value, isTrue);
    expect(GlasKwaliteit.stand.value, GlasStand.plat);
    SysteemGlas.stop();
  });

  test('elk platform beantwoordt het kanaal', () {
    final android = File('android/app/src/main/kotlin/com/debridmusic/app/MainActivity.kt').readAsStringSync();
    expect(android, contains('"debridmusic/systeem"'));
    expect(android, contains('stroom.isPowerSaveMode'));
    expect(android, contains('"accessibility_reduce_transparency"'));
    final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(ios, contains('"debridmusic/systeem"'));
    expect(ios, contains('UIAccessibility.isReduceTransparencyEnabled'));
    final mac = File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();
    expect(mac, contains('"debridmusic/systeem"'));
    expect(mac, contains('accessibilityDisplayShouldReduceTransparency'));
    final win = File('windows/runner/flutter_window.cpp').readAsStringSync();
    expect(win, contains('"debridmusic/systeem"'));
    expect(win, contains('L"EnableTransparency"'));
    expect(win, contains('stroom.SystemStatusFlag & 1'));
    expect(File('lib/main.dart').readAsStringSync(),
        contains('unawaited(GlasKwaliteit.inrichten().then((_) => SysteemGlas.start()));'));
  });
}
