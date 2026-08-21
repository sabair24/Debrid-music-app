/// Wat de terugknop doet, in vier gevallen.
///
/// **Waarom dit zo klein is en toch de moeite waard.** De fout die deze toets tegenhoudt is stil: de
/// `canPop` van een `PopScope` wordt vastgelegd op het moment dat hij gebouwd wordt, en een pagina
/// die in de binnennavigator geopend wordt hertekent de schil niet. Zonder tegenmaatregel blijft die
/// waarde op Start `true` staan — en dan verlaat één druk op TERUG de app terwijl er een albumpagina
/// openstaat. Op een afstandsbediening, waar TERUG de knop is die je constant gebruikt, leest dat als
/// een app die crasht.
///
/// De regel staat daarom als zuivere functie apart, en zowel `canPop` als de afhandelaar leidt
/// eruit af. Dan is dit een gezakte toets in plaats van iets wat je op het toestel ontdekt.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/navigatie.dart';

void main() {
  group('drie lagen, één knop', () {
    test('een pagina over de sectie heen gaat als eerste dicht', () {
      // Ook op Start: open je vanaf Start een album, dan hoort TERUG dat album te sluiten en niet
      // de app. Dit is het geval dat het meest voorkomt en dat zonder deze regel misgaat.
      expect(terugVanaf(paginaOpen: true, sectie: startSectie), TerugActie.paginaSluiten);
      expect(terugVanaf(paginaOpen: true, sectie: 0), TerugActie.paginaSluiten);
    });

    test('daarna brengt hij je naar Start', () {
      // De secties zijn geen routes maar een getal, dus Flutter heeft hier niets te sluiten. Zonder
      // deze regel viel je vanaf Albums meteen de app uit.
      expect(terugVanaf(paginaOpen: false, sectie: 0), TerugActie.naarStart);
      expect(terugVanaf(paginaOpen: false, sectie: 9), TerugActie.naarStart);
    });

    test('en pas op Start, met niets eroverheen, mag de app dicht', () {
      // De andere helft van dezelfde fout: een app waar je niet uit komt.
      expect(terugVanaf(paginaOpen: false, sectie: startSectie), TerugActie.appVerlaten);
    });

    test('Start is sectie 5, en dat staat op één plek', () {
      // Het getal komt uit NavSections.items; staat het hier anders, dan brengt de terugknop je naar
      // een andere sectie dan de knop "Start".
      expect(startSectie, 5);
    });
  });
}
