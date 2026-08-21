/// Eén paginaovergang, op elk toestel dezelfde.
///
/// **Waarom deze toets bestaat.** `paginaRoute` was een kale `MaterialPageRoute`, en die kiest zijn
/// overgang per platform: op Android de zoom van Material 3, op macOS en iOS de zijwaartse schuif
/// van Cupertino, op Windows een vervaging omhoog. Dezelfde tik gaf dus op de telefoon, de Mac en de
/// pc drie verschillende bewegingen — in één app, met één codebestand. Dat is precies het soort
/// verschil dat je nooit ziet doordat je nooit twee toestellen tegelijk voor je hebt.
library;

import 'package:debridmusic/navigatie.dart';
import 'package:debridmusic/ui/maten.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('de overgang duurt op élk platform even lang', () {
    final gemeten = <TargetPlatform, (Duration, Duration)>{};
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final route = paginaRoute<void>((_) => const SizedBox());
      gemeten[platform] = (route.transitionDuration, route.reverseTransitionDuration);
      debugDefaultTargetPlatformOverride = null;
    }

    for (final entry in gemeten.entries) {
      expect(entry.value.$1, kOvergang, reason: '${entry.key} schuift anders in');
      expect(entry.value.$2, kOvergang, reason: '${entry.key} schuift anders uit');
    }
  });

  test('de overgang duurt langer dan niets', () {
    // De vorm van een route zonder duur is een harde vervanging, en dat is wat de app deed op de
    // wortel van de binnennavigator. Voor een gewone pagina hoort dat niet.
    expect(paginaRoute<void>((_) => const SizedBox()).transitionDuration.inMilliseconds,
        greaterThan(0));
  });

  testWidgets('een pagina schuift in en is daarna gewoon te zien', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              paginaRoute<void>((_) => const Scaffold(body: Text('de nieuwe pagina'))),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await t.tap(find.text('open'));
    // Halverwege: de pagina is er al, maar staat nog niet stil.
    await t.pump();
    await t.pump(kOvergang ~/ 2);
    expect(find.text('de nieuwe pagina'), findsOneWidget);

    await t.pumpAndSettle();
    expect(find.text('de nieuwe pagina'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('wie animaties uitgezet heeft, krijgt ze uit', (t) async {
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                paginaRoute<void>((_) => const Scaffold(body: Text('stil'))),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('stil'), findsOneWidget);
    // Geen beweging betekent hier letterlijk: geen schuiflaag om de pagina heen.
    expect(
      find.descendant(of: find.text('stil'), matching: find.byType(SlideTransition)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('stil'), matching: find.byType(SlideTransition)),
      findsNothing,
    );
  });
}
