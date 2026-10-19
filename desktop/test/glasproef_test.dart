// De glasproef (Saber, 18-10-2026: "proefpagina + metingen per toestel, strenge lat").
import 'dart:io';

import 'package:debridmusic/ui/glas.dart';
import 'package:debridmusic/ui/glasproef.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    Glasproef.meld = null;
    Glasproef.hzVoorToets = null;
    GlasKwaliteit.vergeet();
  });

  test('de lat: p90 van bouwen en rasteren onder het budget, hooguit 5 % te laat', () {
    // 120 Hz: budget 7,08 ms.
    final goed = GlasproefUitslag.uit([for (var i = 0; i < 100; i++) (3000, i < 4 ? 9000 : 5000)], hz: 120);
    expect(goed.gehaald, isTrue);
    expect(goed.teLaat, 4);
    final traag = GlasproefUitslag.uit([for (var i = 0; i < 100; i++) (3000, 7500)], hz: 120);
    expect(traag.gehaald, isFalse, reason: 'elk beeld boven 7,1 ms rasteren');
    final pieken = GlasproefUitslag.uit([for (var i = 0; i < 100; i++) (3000, i < 8 ? 20000 : 4000)], hz: 120);
    expect(pieken.gehaald, isFalse, reason: '8 % te laat, ook al is de p90 goed');
    expect(GlasproefUitslag.uit(const [], hz: 60).gehaald, isFalse, reason: 'niets gemeten is niets gehaald');
  });

  test('op een tv van 60 Hz is het budget ruimer: 14,2 ms', () {
    final shield = GlasproefUitslag.uit([for (var i = 0; i < 100; i++) (6000, 12000)], hz: 60);
    expect(shield.budget.inMicroseconds, 14167);
    expect(shield.gehaald, isTrue);
  });

  test('de zin noemt het oordeel, de beelden en de tijden', () {
    final u = GlasproefUitslag.uit([for (var i = 0; i < 50; i++) (2500, 4100)], hz: 144);
    expect(u.zin, startsWith('Glasproef gehaald: 50 beelden op 144 Hz, p90 bouwen 2,5 ms, rasteren 4,1 ms'));
  });

  testWidgets('loopt twaalf seconden, meldt dan zijn oordeel en blijft staan', (t) async {
    Glasproef.hzVoorToets = 120;
    final regels = <String>[];
    Glasproef.meld = regels.add;
    await t.pumpWidget(const MaterialApp(home: Glasproef()));
    await t.pump();
    expect(find.textContaining('Glasproef loopt'), findsOneWidget);
    for (var i = 0; i < 13; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(regels, hasLength(1));
    // In een toets komen er geen echte beeldtijden: dan zegt hij dat eerlijk.
    expect(regels.single, startsWith('Glasproef: geen beelden gemeten'));
    expect(find.byKey(const ValueKey('glasproef-opnieuw')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  test('aangesloten: een knop in Instellingen, en het oordeel in kop.log', () {
    final bron = File('lib/main.dart').readAsStringSync();
    expect(bron, contains("key: const ValueKey('glasproef-knop'),"));
    expect(bron, contains('Glasproef.meld = (r) {'));
  });
}
