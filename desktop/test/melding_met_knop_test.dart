// Saber, 24-10-2026, op de pc: "Nu spelen — wachtrij vervangen · Altijd zo … deze melding blijft ook altijd
// staan, na 5 seconden moet die weg." Een SnackBar met een knop blijft in Flutter 3.47 staan tot je tikt
// (`persist` volgt `action != null`); elke melding met een knop in de app zet daarom `persist: false`.
import 'dart:io';

import 'package:debridmusic/main.dart' show kMeldingMetKnop;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _toon(WidgetTester t, {bool? persist}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Nu spelen — wachtrij vervangen'),
            duration: kMeldingMetKnop,
            persist: persist,
            action: SnackBarAction(label: 'Altijd zo', onPressed: () {}),
          )),
          child: const Text('speel'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('speel'));
  await t.pumpAndSettle();
  expect(find.text('Altijd zo'), findsOneWidget);
}

void main() {
  test('de melding met "Altijd zo" staat er 5 seconden', () {
    expect(kMeldingMetKnop, const Duration(seconds: 5));
  });

  testWidgets('met persist: false is hij na 5 seconden weg', (t) async {
    await _toon(t, persist: false);
    await t.pump(const Duration(seconds: 4));
    expect(find.text('Altijd zo'), findsOneWidget, reason: 'na 4 s staat hij er nog');
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('Altijd zo'), findsNothing);
  });

  testWidgets('zonder persist blijft hij staan — daarom de regel hieronder', (t) async {
    await _toon(t);
    await t.pump(const Duration(seconds: 30));
    await t.pumpAndSettle();
    expect(find.text('Altijd zo'), findsOneWidget,
        reason: 'als Flutter dit ooit terugdraait, mag persist: false weg');
  });

  test('elke melding met een knop in de app verdwijnt vanzelf', () {
    final zonder = <String>[];
    var aantal = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final bron = f.readAsStringSync();
      for (var i = bron.indexOf('SnackBarAction('); i >= 0; i = bron.indexOf('SnackBarAction(', i + 1)) {
        aantal++;
        final begin = bron.lastIndexOf('SnackBar(', i);
        if (begin < 0 || !bron.substring(begin, i).contains('persist: false')) {
          zonder.add('${f.path}:${'\n'.allMatches(bron.substring(0, i)).length + 1}');
        }
      }
    }
    expect(aantal, greaterThanOrEqualTo(5));
    expect(zonder, isEmpty, reason: 'SnackBarAction zonder persist: false: $zonder');
  });
}
