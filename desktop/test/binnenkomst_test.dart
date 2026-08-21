/// De binnenkomst mag alleen bij het VERSCHIJNEN van een scherm lopen.
///
/// **Waarom deze toets bestaat.** Een lijst bouwt zijn regels pas als je ze nadert. Een
/// binnenkomst-animatie op elke regel betekent daarom, als je niet oppast, dat elke regel die je
/// tijdens het SCROLLEN tegenkomt komt aanzweven — de lijst golft dan permanent terwijl je erdoorheen
/// veegt, en dat kost werk op elk beeld.
///
/// Dat is geen theoretisch risico: het is de standaardmanier waarop dit soort animaties gebouwd wordt,
/// en van buiten ziet het er tijdens het maken prima uit, want in een korte lijst scrol je niet.
library;

import 'package:debridmusic/ui/binnenkomst.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een kind dat opvalt in de boom, zodat de laag eromheen te vinden is.
const _kind = SizedBox(width: 40, height: 40, key: ValueKey('kind'));

/// De vervaging die [Binnenkomst] zélf zet.
///
/// **Binnen `Binnenkomst` zoeken en niet boven het kind.** Een `MaterialApp` hangt zijn eigen
/// route-overgangen in de boom, en dat zijn óók `FadeTransition`s — vier stuks, boven alles wat je
/// neerzet. Zoeken op "staat er een vervaging boven dit kind" vindt die dus altijd, met of zonder
/// animatie, en dan meet deze toets het raamwerk in plaats van deze widget.
Finder get _laag =>
    find.descendant(of: find.byType(Binnenkomst), matching: find.byType(FadeTransition));

void main() {
  testWidgets('zonder een groep eromheen gebeurt er niets', (t) async {
    // Met opzet zo: een regel die niet weet of hij bij het openen van een scherm hoort of tijdens
    // het scrollen gebouwd wordt, hoort niet te animeren.
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Binnenkomst(child: _kind))));
    await t.pump();
    expect(_laag, findsNothing);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kind')), findsOneWidget);
  });

  testWidgets('binnen een groep komt hij wél binnen, en staat hij daarna gewoon', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: BinnenkomstGroep(child: Binnenkomst(child: _kind))),
    ));
    // Twee beelden: het eerste roept de terugroep-na-het-beeld aan, die zet de animatie op en vraagt
    // een hertekening aan; het tweede is die hertekening.
    await t.pump();
    await t.pump();
    expect(_laag, findsOneWidget, reason: 'er hoort een overgang omheen te staan');

    await t.pumpAndSettle();
    // Volledig zichtbaar als hij klaar is — een animatie die halverwege blijft hangen is erger dan
    // geen animatie.
    final vervaging = t.widget<FadeTransition>(_laag);
    expect(vervaging.opacity.value, 1.0);
  });

  testWidgets('wat later gebouwd wordt animeert niet meer', (t) async {
    // Dit is de hele reden dat [BinnenkomstGroep] bestaat: het venster loopt af, en alles wat je
    // daarna zelf in beeld scrolt verschijnt gewoon.
    var toon = false;
    late StateSetter zet;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BinnenkomstGroep(
          child: StatefulBuilder(
            builder: (_, setState) {
              zet = setState;
              return toon ? const Binnenkomst(child: _kind) : const SizedBox();
            },
          ),
        ),
      ),
    ));

    // Ruim voorbij het venster.
    await t.pump(kBinnenkomstVenster + const Duration(milliseconds: 50));
    zet(() => toon = true);
    await t.pump();
    await t.pump();

    expect(_laag, findsNothing, reason: 'buiten het venster hoort er niets te bewegen');
    expect(find.byKey(const ValueKey('kind')), findsOneWidget);
  });

  test('het trapje loopt niet eindeloos op', () {
    // Bij veertig zichtbare tegels zou 40 × het trapje betekenen dat de laatste pas na ruim een
    // seconde staat — dan wacht je op een animatie in plaats van hem op te merken.
    expect(kTrapje * kTrapjeDak, lessThan(const Duration(milliseconds: 250)));
  });
}
