/// De tijden naast een afspeelbalk verspringen niet, dus de balk ook niet.
///
/// Saber, 28-11-2026: *"Kijk ook eens naar de afspeel bar, die springt van plaats doordat de seconden veranderen ernaast,
/// dus wordt telkens hertekend ofzo denk ik"*. "3:16" en "3:19" zijn met gewone cijfers niet even breed; de balk
/// ertussen kreeg elke seconde een andere breedte.
library;

import 'dart:io';

import 'package:debridmusic/main.dart' show VasteTijd;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stijl = TextStyle(fontSize: 12);

  Future<double> breedte(WidgetTester tester, String tekst, String zoals, {bool rechts = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [VasteTijd(tekst, zoals: zoals, stijl: stijl, rechts: rechts, key: const Key('t'))]),
      ),
    ));
    return tester.getSize(find.byKey(const Key('t'))).width;
  }

  testWidgets('elke seconde even breed: de breedte hangt alleen af van hoe lang de tijd kan worden', (tester) async {
    final a = await breedte(tester, '1:11', '4:33');
    final b = await breedte(tester, '3:19', '4:33');
    final c = await breedte(tester, '0:00', '4:33');
    expect(a, b);
    expect(a, c);
  });

  testWidgets('van 9:59 naar 10:00 binnen een nummer van 12 minuten: geen sprong', (tester) async {
    final voor = await breedte(tester, '9:59', '12:04');
    final na = await breedte(tester, '10:00', '12:04');
    expect(voor, na);
  });

  testWidgets('de duur rechts houdt ook de ruimte van de plek (een nummer zonder duur, 12:34 ver)', (tester) async {
    final duur = await breedte(tester, '0:00', '12:34', rechts: true);
    final plek = await breedte(tester, '12:34', '0:00');
    expect(duur, plek);
  });

  testWidgets('met even brede cijfers', (tester) async {
    await breedte(tester, '3:16', '4:33');
    final teksten = tester.widgetList<Text>(find.byType(Text));
    expect(teksten.every((t) => t.style?.fontFeatures?.contains(const FontFeature.tabularFigures()) ?? false), isTrue);
  });

  test('de spelerbalk en Nu speelt gebruiken het allebei', () {
    final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    // Elk met de ruimte van de ander: de plek met die van de duur, de duur met die van de plek.
    expect(m, contains('VasteTijd(_fmt(x.position),\n                        zoals: _fmt(x.duration),'));
    expect(m, contains('VasteTijd(_fmt(x.duration),\n                        zoals: _fmt(x.position), rechts: true,'));
    expect(m, contains('VasteTijd(_fmt(position), zoals: _fmt(duration),'));
    expect(m, contains('VasteTijd(_fmt(duration),\n                zoals: _fmt(position), rechts: true,'));
  });
}
