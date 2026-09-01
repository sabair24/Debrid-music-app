/// De navigatie op een televisie: bovenaan, en bereikbaar met de afstandsbediening.
///
/// **Waarom dit bestaat.** Het menu was een rail links, en daar kwam je met de afstandsbediening
/// niet in: op de Shield gemeten deed vier keer LINKS vanaf de eerste albumtegel niets, de focus
/// verroerde zich niet. Een menu dat je niet kunt aanwijzen is geen menu.
///
/// Er waren twee oorzaken, en de tweede is de gemene.
///
/// 1. Om de rail zat een `FocusTraversalGroup`. Zo'n groep is een grens, en richtingsnavigatie
///    steekt die niet zomaar over.
/// 2. De inhoud zit sinds de binnennavigator in een eigen route, en een route is een focusscope.
///    Ook die grens laat pijlen niet door. Dat betekent dat het menu naar boven verhuizen op
///    zichzelf niets oploste — er moet een expliciete sprong tussen de twee scopes zijn.
///
/// Dit is een bronbewaker, net als device_name_test.dart. Het echte bewijs staat niet hier maar op
/// het toestel: een widgettest pumpt geen tweede route en zou juist die tweede oorzaak nooit zien.
/// Wat hier bewaakt wordt is dat de twee dingen die de fout veroorzaakten niet terugsluipen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String bron = File('lib/main.dart').readAsStringSync();

  /// De hele tv-navigatie: de widget én zijn State, want de lijst met secties staat in die tweede.
  String balkBron() {
    final start = bron.indexOf('class TvTopBar');
    expect(start, greaterThan(-1), reason: 'TvTopBar is hernoemd of verdwenen');
    final state = bron.indexOf('class _TvTopBarState', start);
    expect(state, greaterThan(-1), reason: '_TvTopBarState is hernoemd of verdwenen');
    final eind = bron.indexOf('\nclass ', state + 1);
    return bron.substring(start, eind == -1 ? bron.length : eind);
  }

  test('de tv-navigatie zit niet in een eigen traversalgroep', () {
    // Deze zat om de rail heen, en de rail was onbereikbaar. Die combinatie hoort niet terug.
    expect(balkBron(), isNot(contains('FocusTraversalGroup')));
  });

  test('de balk loopt over de tv-lijst, niet over alle secties', () {
    // Op een tv is de app een speler: Online zoeken, Mijn downloads en Kwaliteit horen daar niet.
    // De balk moet die keuze uit NavSections.voorTv halen en niet zelf een lijstje bijhouden --
    // anders lopen de twee uit elkaar zodra er een sectie bijkomt.
    expect(balkBron(), contains('for (final (id, label, icoon) in NavSections.voorTv)'));
    expect(balkBron(), contains("_item(Icons.search_rounded, 'Zoeken'"));
    expect(balkBron(), contains("_item(Icons.settings_rounded, 'Instellingen'"));
  });

  test('de tv-lijst laat ophalen en opruimen weg, en verder niets', () {
    final bron = File('lib/main.dart').readAsStringSync();
    // 2 = Online zoeken, 6 = Mijn downloads, 7 = Kwaliteit. Verandert deze verzameling, dan
    // verdwijnt of verschijnt er een sectie op de tv — dat hoort een bewuste stap te zijn.
    expect(bron, contains('static const _nietOpTv = {2, 6, 7};'));
    // En het blijft een FILTER op de gedeelde lijst: zo krijgt de tv een nieuwe sectie vanzelf.
    expect(bron, contains('items.where((s) => !_nietOpTv.contains(s.\$1))'));
  });

  test('de sprong tussen menu en inhoud bestaat, in beide richtingen', () {
    // Zonder deze twee is de balk onbereikbaar, hoe mooi hij ook staat. Zie _tvSprong.
    //
    // Het DOEL is sinds tv_melding_bereikbaar_test.dart een rijtje en geen enkele scope: er kan
    // een meldingsbalk tussen staan, en die moet als eerste aan de beurt zijn. Wat hier bewaakt
    // wordt is dat de bestemming er nog in zit, niet hoe het rijtje eruitziet.
    expect(bron, contains('TraversalDirection.up, [_tvMelding, _tvBalk]'),
        reason: 'omhoog vanuit de inhoud moet nog steeds bij de bovenbalk uitkomen');
    expect(bron, contains('TraversalDirection.down, [_tvMelding, _tvInhoud]'),
        reason: 'omlaag vanuit de bovenbalk moet nog steeds bij de inhoud uitkomen');
  });

  test('de sprong laat de pagina eerst zelf proberen', () {
    // Anders spring je vanuit het midden van een lijst meteen naar de balk, en is bladeren stuk.
    final start = bron.indexOf('KeyEventResult _tvSprong');
    expect(start, greaterThan(-1));
    final body = bron.substring(start, start + 600);
    expect(body.indexOf('focusInDirection'), lessThan(body.indexOf('scope.requestFocus')));
  });
}
