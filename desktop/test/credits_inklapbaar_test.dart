// De credits op de albumpagina standaard ingeklapt (Saber, 24-10-2026: "die mogen standaard ingeklapt zitten, en zeker
// ook op de gsm, als er veel zijn wordt dit een heel lange lijst onder elkaar moet ik veel te veel scrollen").
import 'package:debridmusic/credits.dart';
import 'package:debridmusic/main.dart' show CreditsInklapbaar;
import 'package:debridmusic/tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _scherm(List<Credit> c, {double breed = 390}) => MediaQuery(
      data: MediaQueryData(size: Size(breed, 800)),
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CreditsInklapbaar(credits: c)))),
    );

const _twee = [Credit('Producer', 'Danja'), Credit('Producer', 'Timbaland')];

void main() {
  tearDown(() => setTvModeForTest(false));

  testWidgets('ingeklapt: alleen "CREDITS 2", geen namen', (t) async {
    await t.pumpWidget(_scherm(_twee));
    expect(find.text('CREDITS'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Danja'), findsNothing);
    expect(find.text('Timbaland'), findsNothing);
  });

  testWidgets('een tik klapt open, nog een tik weer dicht', (t) async {
    await t.pumpWidget(_scherm(_twee));
    await t.tap(find.byKey(const ValueKey('credits-kop')));
    await t.pumpAndSettle();
    expect(find.text('Danja'), findsOneWidget);
    expect(find.text('Timbaland'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('credits-kop')));
    await t.pumpAndSettle();
    expect(find.text('Danja'), findsNothing);
  });

  testWidgets('op de gsm met veel credits: ingeklapt één regel hoog, open hoogstens veertien', (t) async {
    final veel = [for (var i = 0; i < 30; i++) Credit('Rol $i', 'Naam $i')];
    await t.pumpWidget(_scherm(veel));
    final dicht = t.getSize(find.byType(CreditsInklapbaar)).height;
    expect(dicht, lessThan(60), reason: 'één kopregel, geen lange lijst');
    expect(find.text('14'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('credits-kop')));
    await t.pumpAndSettle();
    expect(find.textContaining('Naam '), findsNWidgets(CreditsInklapbaar.kHoogstens));
  });

  testWidgets('op de tv: de kop is te kiezen en OK klapt open', (t) async {
    setTvModeForTest(true);
    await t.pumpWidget(_scherm(_twee, breed: 960));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Danja'), findsOneWidget);
  });
}
