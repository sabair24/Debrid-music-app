// Throwaway probe: where does the highlight land on the "Koppeling verbreken?" dialog?
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _panel = Color(0xFF181B26);
const _accent = Color(0xFF7C5CFF);

final ButtonStyle _focusOutline = ButtonStyle(
  side: WidgetStateProperty.resolveWith((states) =>
      states.contains(WidgetState.focused) ? const BorderSide(color: _accent, width: 3) : null),
  overlayColor: WidgetStateProperty.resolveWith((states) =>
      states.contains(WidgetState.focused) ? _accent.withValues(alpha: .22) : null),
);

ThemeData _theme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(primary: _accent, surface: _panel),
      focusColor: _accent.withValues(alpha: .34),
      filledButtonTheme: FilledButtonThemeData(style: _focusOutline),
      textButtonTheme: TextButtonThemeData(style: _focusOutline),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _focusOutline),
      iconButtonTheme: IconButtonThemeData(style: _focusOutline),
    );

String _focusedLabel(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return '<none>';
  final ctx = node.context;
  if (ctx == null) return '<no context>';
  if (node is FocusScopeNode) return '<scope:${node.debugLabel}>';
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byElementPredicate((e) => identical(e, ctx)),
      matching: find.byType(Text),
      matchRoot: true,
    ),
  );
  if (texts.isEmpty) return '<node:${node.debugLabel} ctx:${ctx.widget.runtimeType}>';
  return texts.map((t) => t.data).join('|');
}

Widget _harness({required bool autofocusCancel}) {
  return MaterialApp(
    theme: _theme(),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: OutlinedButton.icon(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                backgroundColor: _panel,
                title: const Text('Koppeling verbreken?'),
                content: const Text(
                    'Dit apparaat vergeet je pc. Je muziek blijft gewoon op de pc staan.'),
                actions: [
                  TextButton(
                      autofocus: autofocusCancel,
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Annuleer')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Verbreken')),
                ],
              ),
            ),
            icon: const Icon(Icons.link_off_rounded, size: 18),
            label: const Text('Koppeling verbreken'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final auto in [false, true]) {
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ]) {
      testWidgets('autofocus=$auto first press ${key.keyLabel}', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_harness(autofocusCancel: auto));
        await tester.tap(find.text('Koppeling verbreken'));
        await tester.pumpAndSettle();

        debugPrint('AUTO=$auto KEY=${key.keyLabel} '
            'BEFORE=${_focusedLabel(tester)}');

        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        debugPrint('AUTO=$auto KEY=${key.keyLabel} AFTER=${_focusedLabel(tester)}');
      });
    }
  }
}
