// Faithful probe: dialog pushed from inside the Settings dialog, opened with the remote's OK key.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _panel = Color(0xFF181B26);
const _accent = Color(0xFF7C5CFF);

final ButtonStyle _focusOutline = ButtonStyle(
  side: WidgetStateProperty.resolveWith((states) =>
      states.contains(WidgetState.focused) ? const BorderSide(color: _accent, width: 3) : null),
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

String _focused(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return '<none>';
  if (node is FocusScopeNode) return '<scope>';
  final ctx = node.context;
  if (ctx == null) return '<no ctx>';
  final texts = tester.widgetList<Text>(find.descendant(
    of: find.byElementPredicate((e) => identical(e, ctx)),
    matching: find.byType(Text),
    matchRoot: true,
  ));
  return texts.isEmpty ? '<${ctx.widget.runtimeType}>' : texts.map((t) => t.data).join('|');
}

void main() {
  testWidgets('remote-driven: gear -> settings -> unpair -> LEFT -> OK', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;

    var unpaired = 0;

    await tester.pumpWidget(MaterialApp(
      theme: _theme(),
      home: Scaffold(
        body: Builder(
          builder: (rootCtx) => Center(
            child: IconButton(
              icon: const Icon(Icons.settings_rounded),
              tooltip: 'Instellingen',
              onPressed: () => showDialog(
                context: rootCtx,
                builder: (_) => Dialog(
                  backgroundColor: _panel,
                  child: SizedBox(
                    width: 480,
                    child: Builder(
                      builder: (sctx) => SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(onPressed: () {}, child: const Text('Ververs')),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final yes = await showDialog<bool>(
                                context: sctx,
                                builder: (c) => AlertDialog(
                                  backgroundColor: _panel,
                                  title: const Text('Koppeling verbreken?'),
                                  content: const Text(
                                      'Dit apparaat vergeet je pc. Je muziek blijft gewoon op de pc staan.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(c, false),
                                        child: const Text('Annuleer')),
                                    FilledButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Verbreken')),
                                  ],
                                ),
                              );
                              if (yes == true) unpaired++;
                            },
                            icon: const Icon(Icons.link_off_rounded, size: 18),
                            label: const Text('Koppeling verbreken'),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Reach the gear with the remote and open Settings with OK.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    debugPrint('after DOWN on home: ${_focused(tester)}');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    debugPrint('settings open, focus: ${_focused(tester)}');

    // Arrow down to "Koppeling verbreken" and press OK.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    debugPrint('after DOWN in settings: ${_focused(tester)}');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    debugPrint('after 2nd DOWN in settings: ${_focused(tester)}');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    debugPrint('confirm dialog open? ${find.text('Koppeling verbreken?').evaluate().isNotEmpty} '
        'focus=${_focused(tester)}');

    // The reviewer's fatal press.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    debugPrint('after LEFT on confirm: ${_focused(tester)}');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    debugPrint('UNPAIRED=$unpaired');
  });
}
