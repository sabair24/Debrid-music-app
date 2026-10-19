// Diepte tussen pagina's (Saber, 18-10-2026): de oude wijkt opzij en wordt stiller, de nieuwe schuift
// in. Zonder schalen (gemeten: dat kostte op pc en gsm de meeste te late beelden). Niet op een tv en
// niet bij minder beweging.
import 'package:debridmusic/navigatie.dart';
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/maten.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Twee pagina's van de app op elkaar: "oud" is zelf al een pagina, en daar komt "nieuw" overheen.
Widget _app() => MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(paginaRoute<void>((c) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      Navigator.of(c).push(paginaRoute<void>((_) => const Scaffold(body: Text('nieuw')))),
                  child: const Text('oud'),
                ),
              ))),
          child: const Text('start'),
        ),
      ),
    );

/// De laagste dekking boven een tekst (twee lagen per pagina: binnenkomen en wijken).
double _dekking(WidgetTester t, String tekst) => [
      for (final e in find.ancestor(of: find.text(tekst), matching: find.byType(FadeTransition)).evaluate())
        (e.widget as FadeTransition).opacity.value
    ].reduce((a, b) => a < b ? a : b);

void main() {
  tearDown(() => setTvModeForTest(false));

  testWidgets('halverwege: de oude pagina is stiller en schuift opzij, niets wordt geschaald', (t) async {
    await t.pumpWidget(_app());
    await t.tap(find.text('start'));
    await t.pumpAndSettle();
    final voor = t.getTopLeft(find.text('oud'));
    await t.tap(find.text('oud'));
    await t.pump();
    await t.pump(kOvergang ~/ 2);
    expect(_dekking(t, 'oud'), lessThan(1.0));
    expect(_dekking(t, 'oud'), greaterThanOrEqualTo(kDiepteStil));
    expect(t.getTopLeft(find.text('oud')).dx, lessThan(voor.dx), reason: 'de oude pagina wijkt naar links');
    // Schalen kostte elk beeld de hele pagina opnieuw (pc 47 tegen 11 te late beelden, 18-10-2026).
    expect(find.ancestor(of: find.text('oud'), matching: find.byType(ScaleTransition)), findsNothing);
    expect(find.ancestor(of: find.text('nieuw'), matching: find.byType(ScaleTransition)), findsNothing);
    expect(_dekking(t, 'nieuw'), inExclusiveRange(0.0, 1.0), reason: 'de nieuwe komt op');
    await t.pumpAndSettle();
    expect(find.text('nieuw'), findsOneWidget);
  });

  testWidgets('op een tv geen diepte: alleen het korte schuiven van altijd', (t) async {
    setTvModeForTest(true);
    await t.pumpWidget(_app());
    await t.tap(find.text('start'));
    await t.pumpAndSettle();
    await t.tap(find.text('oud'));
    await t.pump();
    await t.pump(kOvergang ~/ 2);
    expect(find.ancestor(of: find.text('nieuw'), matching: find.byType(ScaleTransition)), findsNothing);
    await t.pumpAndSettle();
  });
}
