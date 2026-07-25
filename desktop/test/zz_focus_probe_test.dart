import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  testWidgets('initial focus in a two-action AlertDialog, and where arrows land', (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    final key = GlobalKey();
    await tester.pumpWidget(_app(Builder(builder: (ctx) {
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            key: key,
            onPressed: () => showDialog<bool>(
              context: ctx,
              builder: (c) => AlertDialog(
                title: const Text('Koppeling verbreken?'),
                content: const Text('body'),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Annuleer')),
                  FilledButton(onPressed: () {}, child: const Text('Verbreken')),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    debugPrint('PRIMARY AFTER OPEN: ${FocusManager.instance.primaryFocus}');

    // press LEFT
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    debugPrint('PRIMARY AFTER LEFT: ${FocusManager.instance.primaryFocus?.context?.widget}');
  });

  testWidgets('same, but pressing DOWN first', (tester) async {
    await tester.pumpWidget(_app(Builder(builder: (ctx) {
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog<bool>(
              context: ctx,
              builder: (c) => AlertDialog(
                title: const Text('t'),
                content: const Text('body'),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Annuleer')),
                  FilledButton(onPressed: () {}, child: const Text('Verbreken')),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    debugPrint('DOWN LANDS ON: ${FocusManager.instance.primaryFocus?.context?.widget}');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    debugPrint('after select, dialog still up: ${find.text('Verbreken').evaluate().isNotEmpty}');
  });
}
