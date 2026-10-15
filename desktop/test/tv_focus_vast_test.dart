// Op de Shield vast op een lege pagina (15-10-2026): na OK op "Op dit toestel" hield de lege scope van
// de inhoud zelf de focus, en dan deed geen enkele pijl nog iets.
import 'dart:io';

import 'package:debridmusic/main.dart' show focusZonderDoel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('focusZonderDoel', () {
    testWidgets('een lege scope die zelf de focus heeft, is een plek zonder doel', (tester) async {
      final scope = FocusScopeNode(debugLabel: 'lege inhoud');
      addTearDown(scope.dispose);
      await tester.pumpWidget(MaterialApp(home: FocusScope(node: scope, child: const SizedBox())));
      scope.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(scope));
      expect(focusZonderDoel(FocusManager.instance.primaryFocus), isTrue);
    });

    testWidgets('een scope met iets om op te staan niet', (tester) async {
      final scope = FocusScopeNode(debugLabel: 'inhoud');
      addTearDown(scope.dispose);
      await tester.pumpWidget(MaterialApp(
          home: FocusScope(node: scope, child: TextButton(onPressed: () {}, child: const Text('Albums')))));
      expect(focusZonderDoel(scope), isFalse);
    });

    testWidgets('een gewone knop met de focus niet', (tester) async {
      final knop = FocusNode(debugLabel: 'knop');
      addTearDown(knop.dispose);
      await tester.pumpWidget(MaterialApp(
          home: TextButton(focusNode: knop, onPressed: () {}, child: const Text('Speel alles'))));
      knop.requestFocus();
      await tester.pump();
      expect(focusZonderDoel(FocusManager.instance.primaryFocus), isFalse);
    });

    testWidgets('geen focus, of de wortel van de app, wel — ook als er elders knoppen staan', (tester) async {
      await tester.pumpWidget(MaterialApp(home: TextButton(onPressed: () {}, child: const Text('Start'))));
      final wortel = FocusManager.instance.rootScope;
      expect(focusZonderDoel(null), isTrue);
      expect(focusZonderDoel(wortel), isFalse, reason: 'als scope heeft de wortel wel iets om op te staan');
      expect(focusZonderDoel(wortel, wortel: wortel), isTrue,
          reason: 'maar staat de focus OP de wortel, dan vangt geen enkele scope de pijl op');
    });
  });

  test('aangesloten: de sprong slaat een lege scope over, en het vangnet hangt aan het toetsenbord', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('if (!focusZonderDoel(hier) && (hier?.focusInDirection(richting) ?? false)) {'));
    expect(main, contains('if (isTv) HardwareKeyboard.instance.addHandler(_tvVangnet);'));
    expect(main, contains('if (isTv) HardwareKeyboard.instance.removeHandler(_tvVangnet);'));
  });
}
