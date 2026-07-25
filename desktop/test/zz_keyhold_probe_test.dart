import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/tv.dart';

void main() {
  setUp(() {
    setTvModeForTest(true);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    setTvModeForTest(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<List<String>> hold(WidgetTester tester, LogicalKeyboardKey key) async {
    final log = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Pressable(
            autofocus: true,
            onPressed: () => log.add('portrait'),
            onLongPress: () => log.add('backdrop'),
            child: const SizedBox(width: 120, height: 120, child: Text('foto')),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue,
        reason: 'the Pressable must actually hold the highlight');

    await simulateKeyDownEvent(key);
    // Hold well past any plausible long-press threshold.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await simulateKeyUpEvent(key);
    await tester.pumpAndSettle();
    return log;
  }

  testWidgets('hold OK (select)', (tester) async {
    final log = await hold(tester, LogicalKeyboardKey.select);
    debugPrint('SELECT HOLD LOG: $log');
  });

  testWidgets('hold gameButtonA', (tester) async {
    final log = await hold(tester, LogicalKeyboardKey.gameButtonA);
    debugPrint('GAMEBUTTONA HOLD LOG: $log');
  });

  testWidgets('hold OK with repeat events (what Android actually sends)', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Pressable(
            autofocus: true,
            onPressed: () => log.add('portrait'),
            onLongPress: () => log.add('backdrop'),
            child: const SizedBox(width: 120, height: 120, child: Text('foto')),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await simulateKeyDownEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 10; i++) {
      await simulateKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    debugPrint('SELECT REPEAT LOG: $log');
  });

  testWidgets('pointer long press for comparison', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Pressable(
            onPressed: () => log.add('portrait'),
            onLongPress: () => log.add('backdrop'),
            child: const SizedBox(width: 120, height: 120, child: Text('foto')),
          ),
        ),
      ),
    ));
    await tester.longPress(find.text('foto'));
    await tester.pumpAndSettle();
    debugPrint('POINTER LONGPRESS LOG: $log');
  });
}
