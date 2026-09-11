/// De kleur van een plaat blijft niet hangen boven de pagina die je erop opent.
///
/// **Waarom dit er is.** Op 11-09-2026, in 3.9.350, stond er boven de stijlpagina die je vanaf Back
/// To Bedlam opende een rode band van 64 punten (Saber: "fix de strook"). De albumpagina zet haar
/// hoeskleur in [PaginaWas], en de schil tekent die over het hele venster. Een pagina die je
/// erbovenop opent, ruimt de plaat niet op — die blijft eronder liggen — dus de kleur bleef staan.
/// En een gewone pagina begint onder de zwevende balk, met een doorzichtige strook erboven.
///
/// Dezelfde vergissing had een tweede gezicht dat niemand gemeld had: van plaat A naar plaat B en
/// terug, en A stond zonder kleur. B wiste bij het sluiten zijn kleur, en A zette de zijne nooit
/// opnieuw.
///
/// De echte albumpagina is hier niet te pompen (veertien providers en een libmpv), dus net als in
/// `balkruimte_test.dart` staat de navigator los, met nep-pagina's. De plaat hieronder doet wat de
/// echte doet: [WasHouder] erbij, en een kleur zodra de hoes uitgerekend is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/navigatie.dart';
import 'package:debridmusic/ui/paginawas.dart';

class _Gewoon extends StatelessWidget {
  const _Gewoon(this.naam);

  final String naam;

  @override
  Widget build(BuildContext context) => Center(child: Text(naam));
}

class _Plaat extends StatefulWidget {
  const _Plaat(this.naam);

  final String naam;

  @override
  State<_Plaat> createState() => _PlaatState();
}

class _PlaatState extends State<_Plaat> with WasHouder<_Plaat> {
  @override
  Widget build(BuildContext context) => Center(child: Text(widget.naam));
}

const _rood = 0xFFB0202A;
const _blauw = 0xFF2040B0;

void main() {
  // Niet opgeruimd na elke toets, en dat is met opzet: zakt er een, dan blijft de boom staan tot de
  // volgende toets begint, en dan meldt de plaat die daar opgeruimd wordt zich bij een dienst die al
  // weg is — een tweede fout die de eerste verbergt.
  late PaginaWas was;
  late GlobalKey<NavigatorState> sleutel;
  late ValueNotifier<bool> kanTerug;

  setUp(() {
    was = PaginaWas();
    sleutel = GlobalKey<NavigatorState>();
    kanTerug = ValueNotifier<bool>(false);
  });

  tearDown(() => kanTerug.dispose());

  Widget schil() => ChangeNotifierProvider<PaginaWas>.value(
        value: was,
        child: MaterialApp(
          home: BinnenNavigator(
            navigatorKey: sleutel,
            kanTerug: kanTerug,
            wortel: const Center(child: Text('de sectie')),
          ),
        ),
      );

  NavigatorState nav() => sleutel.currentState!;

  Future<void> open(WidgetTester t, Widget pagina) async {
    nav().push(paginaRoute<void>((_) => pagina));
    await t.pumpAndSettle();
  }

  Future<void> terug(WidgetTester t) async {
    nav().pop();
    await t.pumpAndSettle();
  }

  /// De hoes van [naam] is uitgerekend — ook als de plaat al bedekt ligt, en dan staat ze offstage.
  void hoes(WidgetTester t, String naam, int kleur) => t
      .state<_PlaatState>(find.byWidgetPredicate((w) => w is _Plaat && w.naam == naam,
          skipOffstage: false))
      .zetWas(kleur);

  testWidgets('DE KERN: een pagina op de plaat neemt de kleur mee, en terug komt hij weer',
      (t) async {
    await t.pumpWidget(schil());
    await open(t, const _Plaat('Back To Bedlam'));
    hoes(t, 'Back To Bedlam', _rood);
    expect(was.kleur, _rood);

    await open(t, const _Gewoon('de stijl'));
    expect(was.kleur, isNull,
        reason: 'de rode strook boven de stijlpagina: de kleur van de plaat die eronder ligt');

    await terug(t);
    expect(was.kleur, _rood, reason: 'terug op de plaat, en die staat er grijs bij');
  });

  testWidgets('DE VAL: van plaat naar plaat en terug, en de eerste heeft zijn kleur weer',
      (t) async {
    await t.pumpWidget(schil());
    await open(t, const _Plaat('A'));
    hoes(t, 'A', _rood);
    await open(t, const _Plaat('B'));
    hoes(t, 'B', _blauw);
    expect(was.kleur, _blauw);

    await terug(t);
    expect(was.kleur, _rood,
        reason: 'B wiste bij het sluiten zijn kleur, en A zette de zijne nooit opnieuw');
  });

  testWidgets('DE VAL: twee platen met dezelfde hoes', (t) async {
    // Een tweede persing die je vanaf de eerste opent, heeft dezelfde tint. Toen wissen nog op
    // KLEUR ging, wiste de bovenste bij het sluiten de kleur van de onderste.
    await t.pumpWidget(schil());
    await open(t, const _Plaat('eerste persing'));
    hoes(t, 'eerste persing', _rood);
    await open(t, const _Plaat('tweede persing'));
    hoes(t, 'tweede persing', _rood);

    await terug(t);
    expect(was.kleur, _rood, reason: 'de plaat eronder verloor een kleur die toevallig gelijk was');
  });

  testWidgets('DE VAL: een hoes die klaar is terwijl je al verder bent, wacht', (t) async {
    // De kleur wordt in een isolate uitgerekend. Klik je door voordat die klaar is, dan komt hij
    // binnen terwijl de plaat al onder de volgende pagina ligt.
    await t.pumpWidget(schil());
    await open(t, const _Plaat('Back To Bedlam'));
    await open(t, const _Gewoon('de stijl'));
    hoes(t, 'Back To Bedlam', _rood);
    expect(was.kleur, isNull, reason: 'de strook kwam alsnog, alleen iets later');

    await terug(t);
    expect(was.kleur, _rood, reason: 'de kleur die binnenkwam toen de plaat bedekt lag, is kwijt');
  });

  testWidgets('DE GRENS: een menu is geen pagina', (t) async {
    await t.pumpWidget(schil());
    await open(t, const _Plaat('Back To Bedlam'));
    hoes(t, 'Back To Bedlam', _rood);

    nav().push(RawDialogRoute<void>(
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => const Text('het menu'),
    ));
    await t.pumpAndSettle();
    expect(find.text('het menu'), findsOneWidget);
    expect(was.kleur, _rood,
        reason: 'een menu ligt óp de plaat zonder dat je hem verlaat; de kleur knippert bij elk menu');

    await terug(t);
    expect(was.kleur, _rood);
  });

  testWidgets('DE GRENS: naar Start laat geen kleur achter, ook niet even', (t) async {
    // Wat de secties doen (`_gaNaar` in `main.dart`): alles tot de wortel dicht, in één keer.
    await t.pumpWidget(schil());
    await open(t, const _Plaat('Back To Bedlam'));
    hoes(t, 'Back To Bedlam', _rood);
    await open(t, const _Gewoon('de stijl'));

    nav().popUntil((r) => r.isFirst);
    // Vóór het eerste beeld. De plaat komt even boven als de stijlpagina dichtgaat, en gaat dan zelf
    // dicht; liet ze pas los bij het opruimen, dan kleurde Start een overgang lang in haar tint.
    expect(was.kleur, isNull, reason: 'Start kleurt een overgang lang in de tint van de plaat');
    await t.pumpAndSettle();
    expect(was.kleur, isNull);
  });

  testWidgets('DE GRENS: buiten de binnennavigator doet een plaat wat hij altijd deed', (t) async {
    // Het koppel- en aanmeldscherm draaien zonder schil. Daar hoort de plaat niets, en dan moet ze
    // nog steeds haar kleur zetten en bij het opruimen weer wissen.
    await t.pumpWidget(ChangeNotifierProvider<PaginaWas>.value(
      value: was,
      child: const MaterialApp(home: _Plaat('los')),
    ));
    hoes(t, 'los', _rood);
    expect(was.kleur, _rood);

    await t.pumpWidget(const SizedBox());
    expect(was.kleur, isNull, reason: 'Start blijft in de tint van het laatst bekeken album staan');
  });
}
