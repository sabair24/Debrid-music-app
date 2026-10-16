// De hoes omdraaien met twee tikken (Saber, 16-10-2026): "dubbel tab of dubbel klik op de front hoes
// dat hij draait met een leuke animatie die dan de achterkant toont" — geen achterkant: een korte
// wiebel; een gewone tik op een tegel mag 0,2 s wachten.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/draaihoes.dart';
import 'package:debridmusic/ui/tegel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een geldige PNG van 1×1 pixel, als achterkant.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, //
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, //
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  tearDown(() => setTvModeForTest(false));

  group('TweeTikken', () {
    test('twee tikken vlak na elkaar zijn een dubbeltik, en de gewone tik vervalt', () async {
      var nu = DateTime(2026, 10, 16, 12);
      final t = TweeTikken(klok: () => nu);
      var enkel = 0;
      t.neer(const Offset(10, 10));
      expect(t.op(const Offset(10, 10)), isFalse);
      t.enkel(() => enkel++);
      nu = nu.add(const Duration(milliseconds: 120));
      t.neer(const Offset(14, 12));
      expect(t.op(const Offset(14, 12)), isTrue, reason: 'tweede tik binnen 0,2 s, dicht bij de eerste');
      t.enkel(() => enkel++); // de tik van de tweede druk zelf
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(enkel, 0);
      t.dispose();
    });

    test('een tweede tik te laat, of te ver weg, is gewoon een nieuwe tik', () {
      var nu = DateTime(2026, 10, 16, 12);
      final t = TweeTikken(klok: () => nu);
      t.neer(Offset.zero);
      t.op(Offset.zero);
      nu = nu.add(const Duration(milliseconds: 260));
      t.neer(Offset.zero);
      expect(t.op(Offset.zero), isFalse, reason: 'na 0,26 s');
      nu = nu.add(const Duration(milliseconds: 50));
      t.neer(const Offset(120, 0));
      expect(t.op(const Offset(120, 0)), isFalse, reason: '120 punten verderop');
    });

    test('een enkele tik komt na 0,2 s, niet eerder', () async {
      final t = TweeTikken();
      var enkel = 0;
      t.neer(Offset.zero);
      t.op(Offset.zero);
      t.enkel(() => enkel++);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(enkel, 0);
      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(enkel, 1);
      expect(kTweedeTik, const Duration(milliseconds: 200), reason: 'Sabers keuze');
    });
  });

  group('DraaiHoes', () {
    Widget hoes(DraaiHoesController c, {bool metAchter = true}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: DraaiHoes(
              controller: c,
              voor: const SizedBox(width: 100, height: 100, child: Text('voor')),
              achter: metAchter ? const SizedBox(width: 100, height: 100, child: Text('achter')) : null,
            ),
          ),
        );

    testWidgets('omdraaien toont de achterkant, en terug de voorkant', (t) async {
      final c = DraaiHoesController();
      await t.pumpWidget(hoes(c));
      expect(find.text('voor'), findsOneWidget);
      expect(find.text('achter'), findsNothing);
      c.draai(heeftAchterkant: true);
      await t.pump();
      await t.pump(kDraaiDuur ~/ 4);
      expect(find.text('voor'), findsOneWidget, reason: 'het eerste kwart staat de voorkant nog');
      await t.pumpAndSettle();
      expect(find.text('achter'), findsOneWidget);
      expect(find.text('voor'), findsNothing);
      expect(c.omgedraaid, isTrue);
      c.draai(heeftAchterkant: true);
      await t.pumpAndSettle();
      expect(find.text('voor'), findsOneWidget);
    });

    testWidgets('zonder achterkant wiebelt hij en blijft de voorkant staan', (t) async {
      final c = DraaiHoesController();
      await t.pumpWidget(hoes(c, metAchter: false));
      c.draai(heeftAchterkant: false);
      expect(c.omgedraaid, isFalse);
      expect(c.wiebels, 1);
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      final tr = t.widget<Transform>(find.ancestor(of: find.text('voor'), matching: find.byType(Transform)).first);
      expect(tr.transform.isIdentity(), isFalse, reason: 'hij beweegt');
      await t.pumpAndSettle();
      expect(find.text('voor'), findsOneWidget);
      expect(find.byType(Transform), findsNothing, reason: 'in rust geen transform: niets te tekenen per beeld');
    });

    test('de wiebel dempt uit en eindigt recht', () {
      expect(wiebelHoek(0), 0);
      expect(wiebelHoek(1).abs(), lessThan(1e-9));
      expect(wiebelHoek(1 / 6), greaterThan(.1));
      expect(wiebelHoek(5 / 6).abs(), lessThan(wiebelHoek(1 / 6).abs()));
    });

    test('de draai: een halve slag, met perspectief, opgetild in het midden', () {
      final m = draaiMatrix(1);
      expect(m.getRotation().entry(0, 0), closeTo(math.cos(math.pi), 1e-6));
      // Perspectief: aan het begin staat het er, na een kwartslag is die waarde 0,0014 × cos 45°.
      expect(draaiMatrix(0).entry(3, 2), closeTo(.0014, 1e-9));
      expect(draaiMatrix(.25).entry(3, 2), closeTo(.0014 * math.cos(math.pi / 4), 1e-9));
    });
  });

  group('tegel', () {
    Widget tegel({required VoidCallback onTap, Future<Uint8List?> Function()? achterkant, bool draaibaar = true}) =>
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: AlbumTegel(
                hoes: (m) => Container(width: m, height: m, color: const Color(0xFF334455)),
                breedte: kTegelHoes,
                titel: 'Wonderwall',
                ondertitel: 'Oasis',
                onTap: onTap,
                draaibaar: draaibaar,
                achterkant: achterkant,
              ),
            ),
          ),
        );

    testWidgets('één tik opent na 0,2 s', (t) async {
      var open = 0;
      await t.pumpWidget(tegel(onTap: () => open++));
      await t.tap(find.text('Wonderwall'));
      await t.pump(const Duration(milliseconds: 100));
      expect(open, 0);
      await t.pump(const Duration(milliseconds: 150));
      expect(open, 1);
    });

    testWidgets('twee tikken openen niets en halen de achterkant één keer op', (t) async {
      var open = 0, gehaald = 0;
      await t.pumpWidget(tegel(onTap: () => open++, achterkant: () async {
        gehaald++;
        return _png;
      }));
      await t.tap(find.text('Wonderwall'));
      await t.pump(const Duration(milliseconds: 80));
      await t.tap(find.text('Wonderwall'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(open, 0);
      expect(gehaald, 1);
      expect(find.byType(DraaiHoes), findsOneWidget);
    });

    testWidgets('zonder draaien opent een tik meteen, zoals altijd', (t) async {
      var open = 0;
      await t.pumpWidget(tegel(onTap: () => open++, draaibaar: false));
      await t.tap(find.text('Wonderwall'));
      await t.pump();
      expect(open, 1);
      expect(find.byType(DubbelTikVlak), findsNothing);
    });

    testWidgets('op een tv draait er niets en opent een tik meteen', (t) async {
      setTvModeForTest(true);
      var open = 0;
      await t.pumpWidget(tegel(onTap: () => open++));
      await t.tap(find.text('Wonderwall'));
      await t.pump();
      expect(open, 1);
      expect(find.byType(DubbelTikVlak), findsNothing);
    });
  });

  test('aangesloten: albumpagina, online album, Nu speelt, tegels; het losse achterkantbeeld is weg', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    // De bibliotheekpagina en Nu speelt draaien de hoes met cd (AlbumArt).
    expect('draai: isTv ? null : _draai,'.allMatches(main).length, 2);
    expect(main, contains('final hoes = isTv ? art : DubbelTikVlak(onDubbel: () => _draai.draai(heeftAchterkant: _heeftAchter), child: art);'));
    expect(main, contains('onDubbel: () => _draai.draai(heeftAchterkant: _achterNu != null),'));
    // Eén tik in Nu speelt wacht op een mogelijke tweede, en vergroot wat er voor staat.
    expect(main, contains('_tikken.enkel(() {'));
    expect(main, contains('final achter = _draai.omgedraaid ? _achterNu : null;'));
    // Het online album draait naar de achterkant die het infoblok vond.
    expect(main, contains('onDubbel: () => _draai.draai(heeftAchterkant: _achter != null),'));
    expect(main, contains('onAchterkant: (b) {'));
    // De tegels op Albums en Start.
    expect('draaibaar: true,'.allMatches(main).length, greaterThanOrEqualTo(2));
    expect(main, contains('achterkant: () => achterkantVan(context, a),'));
    // Geen los plaatje van de achterkant meer in het infoblok.
    expect(main, isNot(contains('height: 116, fit: BoxFit.contain')));
    // Omgedraaid staat de cd stil en schuift hij terug.
    expect(main, contains('if (widget.draai?.omgedraaid ?? false) {\n      _slide.reverse();\n      _spin.stop();'));
  });
}
