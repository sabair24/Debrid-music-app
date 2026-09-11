/// De balk zweeft over de pagina's, en bij een paginawissel verspringt er niets.
///
/// **Waarom dit per route geregeld is, en waarom dat een toets verdient.** Op 11-09-2026 ging de
/// bovenbalk van de pc zweven, zodat de foto op de artiestpagina tot de bovenrand van het venster
/// loopt (Saber: "ik wil gewoon af van die bovenbalk"). De voor de hand liggende bouw — één inzet van
/// 64 punten rond de hele navigator, die wegvalt zolang de artiestpagina bovenop ligt — had bij élke
/// plaat die je vanaf een artiest opent de pagina die je nog ziet in één beeld 64 punten laten
/// zakken: een pagina schuift in 260 ms binnen terwijl die eronder zichtbaar blijft. Daarom houdt
/// elke route haar eigen ruimte, en legt deze toets vast dat die klopt, dat een pagina er onderdoor
/// mag, en dat haar strook zich op tijd terugtrekt.
///
/// De echte schil is hier niet te pompen (veertien providers en een libmpv), dus net als in
/// `binnen_navigator_test.dart` staat de navigator los, met een nepsectie en nep-pagina's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/navigatie.dart';
import 'package:debridmusic/ui/maten.dart';

class _Gewoon extends StatelessWidget {
  const _Gewoon(this.naam);

  final String naam;

  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.topLeft, child: Text(naam));
}

class _Onder extends StatelessWidget implements OnderDeBalk {
  const _Onder();

  @override
  Widget build(BuildContext context) =>
      const Align(alignment: Alignment.topLeft, child: Text('onder de balk'));
}

/// Telt hoe vaak zijn toestand opnieuw begint. Eén keer is de eis.
class _Teller extends StatefulWidget {
  const _Teller();

  static int begonnen = 0;

  @override
  State<_Teller> createState() => _TellerState();
}

class _TellerState extends State<_Teller> {
  @override
  void initState() {
    super.initState();
    _Teller.begonnen++;
  }

  @override
  Widget build(BuildContext context) =>
      const Align(alignment: Alignment.topLeft, child: Text('teller'));
}

void main() {
  late GlobalKey<NavigatorState> sleutel;
  late ValueNotifier<bool> kanTerug;

  setUp(() {
    sleutel = GlobalKey<NavigatorState>();
    kanTerug = ValueNotifier<bool>(false);
    _Teller.begonnen = 0;
  });

  tearDown(() => kanTerug.dispose());

  Widget schil({double ruimte = 64}) => MaterialApp(
        home: BalkRuimte(
          hoogte: ruimte,
          child: BinnenNavigator(
            navigatorKey: sleutel,
            kanTerug: kanTerug,
            wortel: const Align(alignment: Alignment.topLeft, child: Text('de sectie')),
          ),
        ),
      );

  Future<void> open(WidgetTester t, Widget pagina) async {
    sleutel.currentState!.push(paginaRoute<void>((_) => pagina));
    await t.pumpAndSettle();
  }

  double boven(WidgetTester t, String tekst) => t.getTopLeft(find.text(tekst)).dy;

  /// De afknipping boven een pagina die onder de balk door mag, of null als er niets geknipt wordt.
  Rect? knip(WidgetTester t, String tekst) {
    final clip = t.widget<ClipRect>(
        find.ancestor(of: find.text(tekst), matching: find.byType(ClipRect)).first);
    return clip.clipBehavior == Clip.none ? null : clip.clipper!.getClip(const Size(800, 600));
  }

  testWidgets('DE KERN: een gewone pagina begint onder de balk', (t) async {
    await t.pumpWidget(schil());
    await open(t, const _Gewoon('de plaat'));
    expect(boven(t, 'de plaat'), 64,
        reason: 'de pagina begint achter de zwevende balk, en haar bovenste regel is onleesbaar');
  });

  testWidgets('DE KERN: een pagina die onder de balk door wil, begint bovenaan', (t) async {
    await t.pumpWidget(schil());
    await open(t, const _Onder());
    expect(boven(t, 'onder de balk'), 0,
        reason: 'de foto van de artiest houdt op waar de balk begint — de strook die weg moest');
    expect(knip(t, 'onder de balk'), isNull, reason: 'in rust wordt er niets afgeknipt');
  });

  testWidgets('DE VAL: ook de sectie zelf blijft onder de balk', (t) async {
    // De wortel is geen `PaginaRoute`, en juist daar zou hij vergeten worden: dan schuift het
    // zoekveld van Albums onder de pillen.
    await t.pumpWidget(schil());
    expect(boven(t, 'de sectie'), 64);
  });

  testWidgets('DE VAL: wat eroverheen komt, laat de strook eronder op tijd verdwijnen', (t) async {
    await t.pumpWidget(schil());
    await open(t, const _Onder());

    sleutel.currentState!.push(paginaRoute<void>((_) => const _Gewoon('de plaat')));
    await t.pump();
    await t.pump(kOvergang ~/ 2);
    final half = knip(t, 'onder de balk');
    expect(half, isNotNull, reason: 'halverwege de overgang hoort de strook zich terug te trekken');
    expect(half!.top, inExclusiveRange(0, 64));

    // Vlak vóór het einde, zolang de navigator de pagina eronder nog tekent.
    await t.pump(kOvergang ~/ 2 - const Duration(milliseconds: 1));
    expect(knip(t, 'onder de balk')!.top, closeTo(64, 1),
        reason: 'staat de foto er aan het einde nog, dan verdwijnt hij in één beeld zodra de '
            'navigator de pagina eronder weglegt');
    await t.pumpAndSettle();

    // En terug: hij komt weer tevoorschijn, helemaal.
    sleutel.currentState!.pop();
    await t.pumpAndSettle();
    expect(knip(t, 'onder de balk'), isNull,
        reason: 'na teruggaan hoort de foto weer tot de bovenrand te lopen');
  });

  testWidgets('DE GRENS: zonder zwevende balk verandert er niets', (t) async {
    // Televisie, telefoon, en de schermen die zonder schil draaien.
    await t.pumpWidget(schil(ruimte: 0));
    expect(boven(t, 'de sectie'), 0);
    await open(t, const _Gewoon('de plaat'));
    expect(boven(t, 'de plaat'), 0);
    await open(t, const _Onder());
    expect(knip(t, 'onder de balk'), isNull);
  });

  testWidgets('DE GRENS: een andere ruimte bouwt de pagina niet opnieuw op', (t) async {
    // Een venster dat je smaller trekt tot onder de telefoongrens: de balk houdt op met zweven. De
    // pagina mag dan verschuiven, maar niet vergeten waar je was.
    await t.pumpWidget(schil());
    await open(t, const _Teller());
    expect(boven(t, 'teller'), 64);
    expect(_Teller.begonnen, 1);

    await t.pumpWidget(schil(ruimte: 0));
    await t.pump();
    expect(boven(t, 'teller'), 0);
    expect(_Teller.begonnen, 1, reason: 'de pagina begon opnieuw en was alles kwijt');
  });
}
