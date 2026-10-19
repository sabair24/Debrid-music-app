// Licht en schaduw van de draaiende schijf met een shader (Saber, 19-10-2026: "Echt, licht stil").
// De kern is de kosten: één keer bakken per maat, en draaien bakt nooit opnieuw.
import 'dart:io';
import 'dart:math' as math;

import 'package:debridmusic/ui/getekende_schijf.dart';
import 'package:debridmusic/ui/schijf_licht.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => SchijfLicht.vergeet());

  testWidgets('de shader laadt, en het seintje gaat aan', (t) async {
    await t.runAsync(SchijfLicht.laad);
    expect(SchijfLicht.klaar, isTrue);
    expect(SchijfLicht.geladen.value, isTrue);
  });

  testWidgets('één keer bakken per maat: twee lagen van dezelfde maat delen één afbeelding', (t) async {
    await t.runAsync(SchijfLicht.laad);
    SchijfLicht.vergeet();
    await t.pumpWidget(const MaterialApp(
      home: Row(children: [
        SchijfLichtLaag(maat: 200, soort: SchijfSoort.cd),
        SchijfLichtLaag(maat: 200, soort: SchijfSoort.cd),
        SchijfGrondschaduw(maat: 200),
      ]),
    ));
    expect(SchijfLicht.gebakken, 2, reason: 'het licht één keer, de grondschaduw één keer');
    expect(find.byKey(const ValueKey('schijf-licht')), findsNWidgets(2));
  });

  testWidgets('DE KERN: een draaiende schijf bakt nooit opnieuw', (t) async {
    await t.runAsync(SchijfLicht.laad);
    SchijfLicht.vergeet();
    final hoek = ValueNotifier(0.0);
    await t.pumpWidget(MaterialApp(
      home: Center(
        child: Stack(alignment: Alignment.center, children: [
          const SchijfGrondschaduw(maat: 240),
          ValueListenableBuilder<double>(
            valueListenable: hoek,
            builder: (_, a, kind) => Transform.rotate(angle: a, child: kind),
            child: const SizedBox.square(dimension: 240, child: ColoredBox(color: Colors.grey)),
          ),
          const SchijfLichtLaag(maat: 240, soort: SchijfSoort.cd),
          const MouwSchaduw(maat: 240, rand: 100),
        ]),
      ),
    ));
    final na = SchijfLicht.gebakken;
    for (var i = 0; i < 90; i++) {
      hoek.value = i * math.pi / 30;
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(SchijfLicht.gebakken, na, reason: 'anderhalve toer draaien: geen enkele keer opnieuw bakken');
  });

  testWidgets('cd, vinyl en scan zijn elk een eigen laag, en het thema telt mee', (t) async {
    await t.runAsync(SchijfLicht.laad);
    SchijfLicht.vergeet();
    final cd = SchijfLicht.beeld(px: 300, soort: SchijfSoort.cd, laag: 0, donker: true);
    final vinyl = SchijfLicht.beeld(px: 300, soort: SchijfSoort.vinyl, laag: 0, donker: true);
    final scan = SchijfLicht.beeld(px: 300, soort: SchijfSoort.scan, laag: 0, donker: true);
    final licht = SchijfLicht.beeld(px: 300, soort: SchijfSoort.cd, laag: 0, donker: false);
    expect({cd, vinyl, scan, licht}.length, 4);
    expect(identical(SchijfLicht.beeld(px: 300, soort: SchijfSoort.cd, laag: 0, donker: true), cd), isTrue);
    expect(SchijfLicht.beeld(px: 300, soort: SchijfSoort.cd, laag: 1, donker: true)!.width,
        (300 * kGrondschaduwVlak).round(), reason: 'de grondschaduw is groter dan de schijf');
  });

  testWidgets('zonder shader de oude glans, en op een scan niets', (t) async {
    SchijfLicht.vergeet(ookShader: true);
    addTearDown(() => t.runAsync(SchijfLicht.laad));
    await t.pumpWidget(const MaterialApp(
      home: Row(children: [
        SchijfLichtLaag(maat: 200, soort: SchijfSoort.cd),
        SchijfLichtLaag(maat: 200, soort: SchijfSoort.scan),
      ]),
    ));
    expect(find.byType(CdGlans), findsOneWidget);
    expect(find.byKey(const ValueKey('schijf-licht')), findsNothing);
  });

  testWidgets('de schaduw van de hoes ligt naast zijn rand, en is er niet als de schijf er nog onder ligt', (t) async {
    await t.pumpWidget(const MaterialApp(home: Center(child: MouwSchaduw(maat: 200, rand: 80))));
    final band = t.getRect(find.byKey(const ValueKey('mouw-schaduw')));
    final schijf = t.getRect(find.byType(MouwSchaduw));
    expect(band.left - schijf.left, 80);
    expect(band.width, closeTo(200 * MouwSchaduw.breedte, .01));
    await t.pumpWidget(const MaterialApp(home: Center(child: MouwSchaduw(maat: 200, rand: 200))));
    expect(find.byKey(const ValueKey('mouw-schaduw')), findsNothing);
  });

  test('geen menging met wat eronder ligt (die leest de draaiende schijf elk beeld terug)', () {
    expect(File('lib/ui/schijf_licht.dart').readAsStringSync(), isNot(contains('BlendMode.')));
    expect(File('lib/ui/schijf_licht.dart').readAsStringSync(), contains('toImageSync'),
        reason: 'gebakken, niet per beeld met de shader getekend');
  });

  test('aangesloten: geladen bij het opstarten, in AlbumArt, op de tegel, in het eiland en de Glasproef', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('unawaited(SchijfLicht.laad());'));
    expect(main, contains('SchijfGrondschaduw(maat: s * .92),\n                spinningDisc,\n                SchijfLichtLaag('));
    expect(main, contains('MouwSchaduw(key: const ValueKey(\'albumart-mouwschaduw\'), maat: s * .92, rand: x.hoes + s - x.schijf)'));
    expect(main, contains('soort: disc != null\n                        ? SchijfSoort.scan'),
        reason: 'een echte scan krijgt alleen de schaduwen');
    expect(File('lib/ui/tegel.dart').readAsStringSync(), contains('SchijfLichtLaag(maat: maat, soort: SchijfSoort.cd, etiket: .36)'));
    expect(File('lib/ui/wachtrij_eiland.dart').readAsStringSync(), contains('child: MouwSchaduw(maat: plaat, rand: plaat * .56)'));
    expect(File('lib/ui/glasproef.dart').readAsStringSync(), contains('SchijfLichtLaag(maat: 170, soort: SchijfSoort.cd)'));
    expect(File('pubspec.yaml').readAsStringSync(), contains('    - shaders/schijf_licht.frag'));
  });

  testWidgets('het grotere etiket van een tegel krijgt een eigen laag', (t) async {
    await t.runAsync(SchijfLicht.laad);
    SchijfLicht.vergeet();
    final gewoon = SchijfLicht.beeld(px: 120, soort: SchijfSoort.cd, laag: 0, donker: true);
    final tegel = SchijfLicht.beeld(px: 120, soort: SchijfSoort.cd, laag: 0, donker: true, etiket: .36);
    expect(identical(gewoon, tegel), isFalse);
    expect(SchijfLicht.gebakken, 2);
  });
}
