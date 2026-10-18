/// Escape en de terugknop van de muis zijn op de pc een stap terug (17-10-2026: Escape deed niets op
/// Nu speelt of een albumpagina).
library;

import 'dart:io';

import 'package:debridmusic/main.dart' show appNavigator, stapTerug;
import 'package:debridmusic/navigatie.dart' show binnenNav;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('eerst wat bovenop de app ligt, dan binnen de sectie', (t) async {
    await t.pumpWidget(MaterialApp(
      navigatorKey: appNavigator,
      home: Navigator(
        key: binnenNav,
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const Text('sectie')),
      ),
    ));
    binnenNav.currentState!.push(MaterialPageRoute(builder: (_) => const Text('albumpagina')));
    await t.pumpAndSettle();
    appNavigator.currentState!.push(MaterialPageRoute(builder: (_) => const Text('nu speelt')));
    await t.pumpAndSettle();
    expect(find.text('nu speelt'), findsOneWidget);

    stapTerug();
    await t.pumpAndSettle();
    expect(find.text('nu speelt'), findsNothing);
    expect(find.text('albumpagina'), findsOneWidget);

    stapTerug();
    await t.pumpAndSettle();
    expect(find.text('albumpagina'), findsNothing);
    expect(find.text('sectie'), findsOneWidget);

    // Niets meer om terug te gaan: dan gebeurt er niets.
    stapTerug();
    await t.pumpAndSettle();
    expect(find.text('sectie'), findsOneWidget);
  });

  test('Escape en de terugknop van de muis zijn aangesloten, niet op een tv', () {
    final hoofd = File('lib/main.dart').readAsStringSync();
    final escape = hoofd.indexOf('const SingleActivator(LogicalKeyboardKey.escape): const TerugIntent(),');
    expect(escape, greaterThan(-1));
    expect(hoofd.lastIndexOf('if (!isTv) ...{', escape), greaterThan(-1));
    expect(hoofd, contains('TerugIntent: AlsNietTypend<TerugIntent>(stapTerug),'),
        reason: 'tijdens het typen laat hij Escape aan het veld');
    expect(hoofd, contains('e.buttons & kBackMouseButton != 0) stapTerug();'));
  });
}
