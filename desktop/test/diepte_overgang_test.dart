// Diepte tussen pagina's (Saber, 18-10-2026): de oude wijkt terug, de nieuwe komt naar voren. Niet
// op een tv en niet bij minder beweging.
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

double? _schaal(WidgetTester t, String tekst) {
  final s = find.ancestor(of: find.text(tekst), matching: find.byType(ScaleTransition));
  if (s.evaluate().isEmpty) return null;
  // Twee lagen per pagina: de binnenste voor het binnenkomen, de buitenste voor het terugwijken.
  return [for (final e in s.evaluate()) (e.widget as ScaleTransition).scale.value].reduce((a, b) => a < b ? a : b);
}

void main() {
  tearDown(() => setTvModeForTest(false));

  testWidgets('halverwege: de oude pagina is kleiner en stiller, de nieuwe groeit naar voren', (t) async {
    await t.pumpWidget(_app());
    await t.tap(find.text('start'));
    await t.pumpAndSettle();
    await t.tap(find.text('oud'));
    await t.pump();
    await t.pump(kOvergang ~/ 2);
    expect(_schaal(t, 'oud'), lessThan(1.0));
    expect(_schaal(t, 'oud'), greaterThanOrEqualTo(kDiepteTerug));
    final nieuw = find.ancestor(of: find.text('nieuw'), matching: find.byType(ScaleTransition));
    expect(t.widget<ScaleTransition>(nieuw.first).scale.value, inInclusiveRange(kDiepteVoor, 1.0));
    final fade = find.ancestor(of: find.text('oud'), matching: find.byType(FadeTransition));
    expect([for (final e in fade.evaluate()) (e.widget as FadeTransition).opacity.value].reduce((a, b) => a < b ? a : b),
        lessThan(1.0));
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
