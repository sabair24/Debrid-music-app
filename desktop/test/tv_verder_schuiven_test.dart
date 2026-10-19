/// Snel omlaag op de tv blijft in de pagina (Shield, 19-10-2026): vijf keer snel omlaag in Albums zette
/// de focus in de spelerbalk ("Kelis"), want de volgende rij was nog niet gebouwd. Nu schuift de pagina
/// eerst verder ([tvSchuifVerder]), en pas aan het eind mag de pijl naar de spelerbalk.
library;

import 'dart:io';

import 'package:debridmusic/tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een rij van 280 punten hoog met hoezen, zoals een letterrij op Albums.
Widget _rij(int r, {bool schuift = true}) => SizedBox(
      height: 280,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 8,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.all(10),
          child: Pressable(
            key: ValueKey('r$r-$i'),
            onPressed: () {},
            ringOnFocus: false,
            schuifInBeeld: schuift,
            child: const SizedBox(width: 140, height: 200),
          ),
        ),
      ),
    );

class _Proef {
  final inhoud = FocusScopeNode(debugLabel: 'inhoud');
  final speler = FocusScopeNode(debugLabel: 'speler');
  final pagina = ScrollController();

  /// Zoals `_tvSprong` in main.dart: eerst in de pagina, dan verder schuiven, dan pas de spelerbalk.
  void omlaag({bool verder = true}) {
    final hier = FocusManager.instance.primaryFocus!;
    if (tvPijlStap(hier, TraversalDirection.down)) return;
    if (verder && inhoud.hasFocus && tvSchuifVerder(hier, TraversalDirection.down)) return;
    speler.requestFocus();
  }

  Widget bouw({int rijen = 30, double boven = 0, bool schuift = true}) => MaterialApp(
        // Zoals in de app: het eigen focusverzoek, dat de lijst in 220 ms laat meeschuiven in plaats van in
        // één beeld. Dan moet een wachtende stap een paar beelden op zijn rij wachten.
        builder: (_, kind) => FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvFocusZonderSprong),
          child: kind!,
        ),
        home: Scaffold(
          body: Column(children: [
            SizedBox(
              height: 540,
              child: FocusScope(
                node: inhoud,
                child: ListView.builder(
                  controller: pagina,
                  itemCount: rijen + 1,
                  itemBuilder: (_, r) => r == 0 ? SizedBox(height: boven) : _rij(r - 1, schuift: schuift),
                ),
              ),
            ),
            FocusScope(
              node: speler,
              child: Pressable(key: const ValueKey('speler'), onPressed: () {}, child: const SizedBox(width: 200, height: 60)),
            ),
          ]),
        ),
      );
}

FocusNode _knoop(WidgetTester t, String sleutel) =>
    Focus.of(t.element(find.descendant(of: find.byKey(ValueKey(sleutel)), matching: find.byType(GestureDetector)).first));

/// In welke rij staat de focus (of -1 in de spelerbalk)?
int _rijMetFocus(_Proef p) {
  if (p.speler.hasFocus) return -1;
  final k = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Pressable>()?.key;
  final naam = (k as ValueKey<String>?)?.value ?? '';
  return int.tryParse(naam.substring(1, naam.indexOf('-'))) ?? -2;
}

void main() {
  setUp(() {
    setTvModeForTest(true);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    setTvModeForTest(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  testWidgets('tegenproef: zonder verder schuiven belandt snel omlaag in de spelerbalk', (t) async {
    final p = _Proef();
    await t.pumpWidget(p.bouw());
    _knoop(t, 'r0-0').requestFocus();
    await t.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      p.omlaag(verder: false);
      // Zoals vijf keer input keyevent op de Shield: de focus wisselt, maar er komt geen beeld tussen.
      FocusManager.instance.applyFocusChangesIfNeeded();
    }
    await t.pumpAndSettle();
    expect(_rijMetFocus(p), -1, reason: 'anders bewijst de toets hieronder niets');
  });

  testWidgets('DE KERN: vijf keer snel omlaag blijft in de pagina, en de pagina schuift mee', (t) async {
    final p = _Proef();
    await t.pumpWidget(p.bouw());
    _knoop(t, 'r0-0').requestFocus();
    await t.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      p.omlaag();
      FocusManager.instance.applyFocusChangesIfNeeded();
      expect(p.speler.hasFocus, isFalse, reason: 'stap ${i + 1}: niet de spelerbalk');
    }
    await t.pumpAndSettle();
    expect(_rijMetFocus(p), 5, reason: 'elke pijl telt: vijf pijlen, vijf rijen verder (op de Shield werden het er eerst twee)');
    expect(p.pagina.offset, greaterThan(0));
  });

  testWidgets('ook als de rijen zelf niet schuiven: dan schuift het focusverzoek, en elke pijl telt', (t) async {
    final p = _Proef();
    await t.pumpWidget(p.bouw(schuift: false));
    _knoop(t, 'r0-0').requestFocus();
    await t.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      p.omlaag();
      FocusManager.instance.applyFocusChangesIfNeeded();
    }
    await t.pumpAndSettle();
    expect(_rijMetFocus(p), 5);
    expect(p.speler.hasFocus, isFalse);
  });

  testWidgets('aan het eind van de pagina mag omlaag naar de spelerbalk', (t) async {
    final p = _Proef();
    await t.pumpWidget(p.bouw(rijen: 4));
    p.pagina.jumpTo(p.pagina.position.maxScrollExtent);
    await t.pump();
    _knoop(t, 'r3-0').requestFocus();
    await t.pumpAndSettle();
    p.omlaag();
    await t.pumpAndSettle();
    expect(p.speler.hasFocus, isTrue);
  });

  testWidgets('omhoog vlak onder de kop schuift niet: dan gaat de pijl naar de bovenbalk', (t) async {
    final p = _Proef();
    await t.pumpWidget(p.bouw(boven: 150));
    _knoop(t, 'r0-0').requestFocus();
    await t.pumpAndSettle();
    expect(p.pagina.offset, greaterThan(40), reason: 'de eerste rij staat op zijn vaste plek: de kop is half weg');
    final hier = FocusManager.instance.primaryFocus!;
    expect(tvPijlStap(hier, TraversalDirection.up), isFalse);
    expect(tvSchuifVerder(hier, TraversalDirection.up), isFalse,
        reason: 'boven de eerste rij staat alleen de kop (${p.pagina.offset.round()} punten)');
  });

  test('aangesloten: na de stap in de pagina en vóór de sprong naar een ander gebied', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final begin = main.indexOf('KeyEventResult _tvSprong(');
    final lijf = main.substring(begin, main.indexOf('for (final scope in naar)', begin));
    expect(lijf, contains('if (hier != null && _tvInhoud.hasFocus && tvSchuifVerder(hier, richting)) {'));
    expect(lijf.indexOf('tvPijlStap(hier, richting)'), lessThan(lijf.indexOf('tvSchuifVerder(')));
  });
}
