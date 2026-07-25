// TEMPORARY probe used while reviewing; delete after running.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/tv.dart';

void main() {
  setUp(() => setTvModeForTest(true));
  tearDown(() => setTvModeForTest(false));

  testWidgets('holding OK on a remote: does onLongPress ever fire?', (tester) async {
    var pressed = 0, longPressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Pressable(
            autofocus: true,
            onPressed: () => pressed++,
            onLongPress: () => longPressed++,
            child: const SizedBox(width: 120, height: 40, child: Text('Foto')),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Hold the OK button: one down, auto-repeats for ~1.2s, then up.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 24; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    debugPrint('HELD-OK RESULT pressed=$pressed longPressed=$longPressed');
    expect(longPressed, greaterThan(0), reason: 'held OK should reach onLongPress');
  });
}
