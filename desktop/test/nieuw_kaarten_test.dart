// De uitgelichte rijen nieuwe releases (Saber, 19-10-2026): een grote kaart vooraan, brede kaarten twee
// boven elkaar, een datumlint op de hoes, en een kop met een teller en "Alles". Op een gsm van 360 en 411
// punten breed, ook met een grotere tekst: niets mag overlopen.
import 'dart:io';

import 'package:debridmusic/ui/nieuw_kaarten.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NieuwKaart _k(int i, {VoidCallback? knop}) => NieuwKaart(
      titel: 'Een heel lange titel van een nieuw nummer nummer $i',
      regel2: 'Een artiest met een lange naam $i',
      regel3: 'Van Een Album Met Een Lange Naam',
      opschrift: 'NIEUWE SINGLE · LIJKT OP DUA LIPA · VERSCHIJNT 6 NOV',
      hoes: (maat) => ColoredBox(color: Colors.teal, child: SizedBox.square(dimension: maat)),
      lint: i.isEven ? '3 dagen' : '6 nov',
      onTap: () {},
      onKnop: knop,
    );

Widget _scherm(double breedte, {double tekst = 1, required Widget kind}) => MediaQuery(
      data: MediaQueryData(size: Size(breedte, 800), textScaler: TextScaler.linear(tekst)),
      child: MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topLeft, child: kind))),
    );

void main() {
  test('maten: op een gsm blijft de volgende kolom zichtbaar; de kaart groeit mee met de tekst', () {
    final m360 = nieuwRijMaten(360, smal: true);
    final m411 = nieuwRijMaten(411, smal: true);
    expect(m360.kaartB, lessThan(360 - 2 * 24), reason: 'naast de kaart hoort een stukje van de volgende');
    expect(m411.kaartB, greaterThan(m360.kaartB));
    expect(m360.grootH, 2 * m360.kaartH + m360.tussen, reason: 'de grote kaart is precies twee kaarten hoog');
    expect(nieuwRijMaten(411, smal: true, schaal: const TextScaler.linear(1.4)).kaartH, greaterThan(m411.kaartH));
  });

  for (final breedte in [360.0, 411.0]) {
    for (final tekst in [1.0, 1.3]) {
      testWidgets('rij op $breedte punten, tekst ×$tekst: geen overloop', (t) async {
        await t.pumpWidget(_scherm(breedte,
            tekst: tekst,
            kind: Column(children: [
              NieuwKop('Nieuwe nummers', totaal: 124, nieuw: 5, onAlles: () {}),
              NieuwRij(aantal: 20, groot: () => _k(0, knop: () {}), kaart: _k),
            ])));
        expect(t.takeException(), isNull);
        expect(find.byType(GroteKaart), findsOneWidget);
        expect(find.byType(BredeKaart), findsWidgets);
        expect(find.text('Alles (124)'), findsOneWidget);
        expect(find.text('5 nieuw'), findsOneWidget);
        expect(find.text('3 dagen'), findsWidgets, reason: 'het datumlint op de hoes');
        expect(find.text('Afspelen'), findsOneWidget, reason: 'de knop op de grote kaart');
      });
    }
  }

  testWidgets('"Alles" staat rechts, ook op een breed scherm', (t) async {
    t.view.physicalSize = const Size(1440, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_scherm(1440, kind: NieuwKop('Nieuwe nummers', totaal: 7, onAlles: () {})));
    final alles = t.getTopRight(find.text('Alles (7)'));
    expect(alles.dx, greaterThan(1440 - 24 - 60), reason: 'tegen de rechtergoot, niet halverwege');
  });

  testWidgets('twee kaarten boven elkaar per kolom, en een oneven laatste kolom loopt niet uit de pas', (t) async {
    await t.pumpWidget(_scherm(1200,
        kind: NieuwRij(aantal: 4, groot: () => _k(0), kaart: _k)));
    // Kaart 1 en 2 in kolom één, kaart 3 alleen in kolom twee (met een lege plek eronder).
    final een = t.getTopLeft(find.text('Een heel lange titel van een nieuw nummer nummer 1'));
    final twee = t.getTopLeft(find.text('Een heel lange titel van een nieuw nummer nummer 2'));
    final drie = t.getTopLeft(find.text('Een heel lange titel van een nieuw nummer nummer 3'));
    expect(een.dx, twee.dx);
    expect(twee.dy, greaterThan(een.dy));
    expect(drie.dy, een.dy);
    expect(drie.dx, greaterThan(een.dx));
    expect(t.takeException(), isNull);
  });

  test('geen beweging die per beeld rekent (Saber: "geen extra beweging")', () {
    final bron = File('lib/ui/nieuw_kaarten.dart').readAsStringSync();
    for (final verboden in ['AnimationController', 'AnimatedBuilder', 'ImageFiltered(', 'BackdropFilter']) {
      expect(bron, isNot(contains(verboden)), reason: verboden);
    }
  });
}
