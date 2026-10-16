// Kleine fouten die Saber op 16-10-2026 op zijn schermafdrukken liet zien of die onderweg opvielen:
// "Arranged By [Strings" zonder haakje, 2006 bovenaan en 2007 eronder, en Engelse beschrijvingen.
import 'dart:io';

import 'package:debridmusic/ai.dart';
import 'package:debridmusic/credits.dart';
import 'package:debridmusic/main.dart' show BioText;
import 'package:debridmusic/vertaler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _engels = 'V is the fifth album by the band Live, released in 2001. It featured the singles '
    '"Simple Creed" and "Overcome", the latter of which received significant airplay.';
const _nederlands = 'V is het vijfde album van de band Live, uitgebracht in 2001. Het bevat de singles '
    '"Simple Creed" en "Overcome", waarvan de laatste veel op de radio werd gedraaid.';

void main() {
  group('creditrollen', () {
    test('de eerste rol, maar nooit binnen haakjes geknipt', () {
      expect(hoofdRol('Recorded By, Mixed By'), 'Recorded By');
      expect(hoofdRol('Arranged By [Strings, Horns]'), 'Arranged By [Strings, Horns]');
      expect(hoofdRol('Arranged By [Strings], Conductor'), 'Arranged By [Strings]');
      expect(hoofdRol('Producer'), 'Producer');
      expect(hoofdRol('  Written-By  '), 'Written-By');
    });
  });

  group('vertalen', () {
    test('Engels en Nederlands uit elkaar houden', () {
      expect(lijktNederlands(_engels), isFalse);
      expect(lijktNederlands(_nederlands), isTrue);
    });

    test('de sleutel hangt aan de tekst', () {
      expect(vertaalSleutel(_engels), vertaalSleutel('  $_engels  '));
      expect(vertaalSleutel(_engels), isNot(vertaalSleutel(_nederlands)));
      expect(vertaalSleutel(_engels), matches(RegExp(r'^v1-[0-9a-f]{16}$')));
    });

    test('de vraag aan het model: het snelle model, alleen de vertaling', () {
      final b = vertaalBody(_engels);
      expect(b['model'], kVertaalModel);
      expect(kVertaalModel, 'claude-haiku-5-5');
      expect(b['system'], contains('Nederlands'));
      expect((b['messages'] as List).single, {'role': 'user', 'content': _engels});
      expect(
          tekstUitAntwoord({
            'content': [
              {'type': 'text', 'text': 'V is het '},
              {'type': 'text', 'text': 'vijfde album.'},
            ]
          }),
          'V is het vijfde album.');
    });

    test('één keer vragen, ook als twee schermen het tegelijk willen, en daarna van schijf', () async {
      final map = Directory.systemTemp.createTempSync('dm_vertaal_');
      addTearDown(() => map.deleteSync(recursive: true));
      final v = Vertaler.instantie;
      var gevraagd = 0;
      v
        ..map = map.path
        ..vraag = (t) async {
          gevraagd++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _nederlands;
        };
      final uit = await Future.wait([v.naarNederlands(_engels), v.naarNederlands(_engels)]);
      expect(uit, [_nederlands, _nederlands]);
      expect(gevraagd, 1);
      expect(v.alKlaar(_engels), _nederlands);
      expect(File('${map.path}${Platform.pathSeparator}${vertaalSleutel(_engels)}.txt').readAsStringSync(), _nederlands);
      // Een Nederlandse tekst wordt niet vertaald.
      expect(await v.naarNederlands(_nederlands), _nederlands);
      expect(gevraagd, 1);
      v.vraag = null;
      v.map = null;
    });

    testWidgets('de beschrijving wordt Nederlands, en zegt dat ze vertaald is', (t) async {
      final v = Vertaler.instantie;
      v
        ..map = null
        ..vraag = (_) async => 'Dit is de vertaalde tekst van het album, met de nummers erbij.';
      addTearDown(() => v.vraag = null);
      const engels = 'This is the original text of the album, with the songs that were on it.';
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: BioText('Live — V', engels))));
      expect(find.text(engels), findsOneWidget);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
      expect(find.text('Dit is de vertaalde tekst van het album, met de nummers erbij.'), findsOneWidget);
      expect(find.textContaining('· vertaald', findRichText: true), findsOneWidget);
    });
  });

  test('aangesloten: jaar van de eerste uitgave, vertaaleindpunt', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains("if ((_officialYear ?? album.year) != null) '\${_officialYear ?? album.year}',"));
    expect(main, contains("if ((_officialYear ?? al.year) != null) '\${_officialYear ?? al.year}',"));
    expect(main, contains('final year = widget.eersteJaar ?? ed?.albumYear ?? info?.year ?? ed?.year;'));
    expect('eersteJaar: _officialYear,'.allMatches(main).length, 2);
    expect(main, contains("final j = await c.ask('/api/vertaal', {'tekst': t});"));
    final server = File('lib/lan/server.dart').readAsStringSync();
    expect(server, contains("case '/api/vertaal':"));
    final credits = File('lib/credits.dart').readAsStringSync();
    expect(credits, contains('final lead = hoofdRol(role);'));
  });
}
