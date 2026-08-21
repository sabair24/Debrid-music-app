/// De navigatie blijft staan als je een pagina opent.
///
/// **Dit ís de vraag, als toets.** Gevraagd werd: "van elk scherm gemakkelijk naar mijn Start
/// kunnen", en het antwoord daarop was: laat de balk staan. Vandaag kan dat niet, omdat elke pagina
/// op de HOOFDnavigator wordt gezet met een eigen `Scaffold` — en die legt zich over de hele schil
/// heen, balken inbegrepen.
///
/// De bewering hieronder is dus letterlijk de eis: push een pagina, en de balk staat er nog.
///
/// De echte schil is hier niet te pompen — veertien providers en een libmpv die in een toetsrun niet
/// bestaat. Daarom staat de navigator los van de schil, net als `Onderbalk`, en wordt hij hier met
/// een nepsectie en een nepbalk nagemeten.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/navigatie.dart';

/// De schil in het klein: chrome buiten de navigator, inhoud erbinnen.
Widget schil(GlobalKey<NavigatorState> sleutel, ValueNotifier<bool> kanTerug) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: BinnenNavigator(
                navigatorKey: sleutel,
                kanTerug: kanTerug,
                wortel: const Center(child: Text('de sectie')),
              ),
            ),
            // Waar in het echt de spelerbalk en de onderbalk staan.
            const Text('de balk'),
          ],
        ),
      ),
    );

void main() {
  late GlobalKey<NavigatorState> sleutel;
  late ValueNotifier<bool> kanTerug;

  setUp(() {
    sleutel = GlobalKey<NavigatorState>();
    kanTerug = ValueNotifier<bool>(false);
  });

  tearDown(() => kanTerug.dispose());

  Future<void> openPagina(WidgetTester tester) async {
    sleutel.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('de albumpagina'))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('de balk blijft staan als er een pagina overheen komt', (tester) async {
    await tester.pumpWidget(schil(sleutel, kanTerug));
    expect(find.text('de sectie'), findsOneWidget);
    expect(find.text('de balk'), findsOneWidget);

    await openPagina(tester);

    expect(find.text('de albumpagina'), findsOneWidget);
    // DE regel. Vandaag zou de balk hier weg zijn, want de pagina lag over de hele schil.
    expect(find.text('de balk'), findsOneWidget,
        reason: 'de navigatie hoort te blijven staan — dat is de hele wijziging');
  });

  testWidgets('de schil weet wanneer er iets te sluiten valt', (tester) async {
    await tester.pumpWidget(schil(sleutel, kanTerug));
    // De wortelroute telt niet: daar valt niets te sluiten, en de terugknop hoort dan naar Start te
    // gaan in plaats van een pagina te sluiten die er niet is.
    expect(kanTerug.value, isFalse);

    await openPagina(tester);
    expect(kanTerug.value, isTrue,
        reason: 'zonder dit blijft canPop achterlopen en sluit TERUG de app met een pagina open');

    sleutel.currentState!.pop();
    await tester.pumpAndSettle();
    expect(kanTerug.value, isFalse);
  });

  testWidgets('twee pagina\'s diep blijft het één stapel, en de balk blijft', (tester) async {
    // Album → artiest → album is een gewone route hier, en elke laag hoort apart te sluiten.
    await tester.pumpWidget(schil(sleutel, kanTerug));
    await openPagina(tester);
    await openPagina(tester);

    expect(kanTerug.value, isTrue);
    expect(find.text('de balk'), findsOneWidget);

    sleutel.currentState!.pop();
    await tester.pumpAndSettle();
    expect(kanTerug.value, isTrue, reason: 'er ligt er nog één');

    sleutel.currentState!.pop();
    await tester.pumpAndSettle();
    expect(kanTerug.value, isFalse);
    expect(find.text('de sectie'), findsOneWidget);
  });

  testWidgets('de sectie eronder blijft leven, dus je plek in de lijst gaat niet verloren',
      (tester) async {
    await tester.pumpWidget(schil(sleutel, kanTerug));
    await openPagina(tester);
    // `maintainState` staat standaard aan; zonder dat zou de albumlijst bij terugkomst weer bovenaan
    // beginnen en opnieuw ophalen.
    expect(find.text('de sectie', skipOffstage: false), findsOneWidget);
  });
}
