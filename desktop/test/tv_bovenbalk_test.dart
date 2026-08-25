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

  test('elke sectie staat in de balk', () {
    // De balk loopt over NavSections.items. Zou daar ooit een deelverzameling van gemaakt worden,
    // dan is die sectie op een tv nergens meer te bereiken: daar is geen tweede navigatie, geen
    // hamburgerla en geen onderbalk.
    expect(balkBron(), contains('for (final (id, label, icoon) in NavSections.items)'));
    expect(balkBron(), contains("_item(Icons.search_rounded, 'Zoeken'"));
    expect(balkBron(), contains("_item(Icons.settings_rounded, 'Instellingen'"));
  });

  test('de sprong tussen menu en inhoud bestaat, in beide richtingen', () {
    // Zonder deze twee is de balk onbereikbaar, hoe mooi hij ook staat. Zie _tvSprong.
    expect(bron, contains('LogicalKeyboardKey.arrowUp, TraversalDirection.up, _tvBalk'));
    expect(bron, contains('LogicalKeyboardKey.arrowDown, TraversalDirection.down, _tvInhoud'));
  });

  test('de sprong laat de pagina eerst zelf proberen', () {
    // Anders spring je vanuit het midden van een lijst meteen naar de balk, en is bladeren stuk.
    final start = bron.indexOf('KeyEventResult _tvSprong');
    expect(start, greaterThan(-1));
    final body = bron.substring(start, start + 600);
    expect(body.indexOf('focusInDirection'), lessThan(body.indexOf('naar.requestFocus')));
  });
}
