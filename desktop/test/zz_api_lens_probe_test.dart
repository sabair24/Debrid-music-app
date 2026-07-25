import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/tv.dart';

void main() {
  setUp(() => setTvModeForTest(true));
  tearDown(() => setTvModeForTest(false));

  testWidgets('A: reviewer scenario — TextField inside MaybePressable, field has primary focus',
      (tester) async {
    var pressed = 0;
    final node = FocusNode();
    final ctl = TextEditingController();
    var submitted = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MaybePressable(
          enabled: isTv,
          onPressed: () {
            pressed++;
            node.requestFocus();
          },
          child: TextField(
            controller: ctl,
            focusNode: node,
            onSubmitted: (_) => submitted++,
          ),
        ),
      ),
    ));
    node.requestFocus();
    await tester.pumpAndSettle();
    debugPrint('A primaryFocus is the field node: ${node.hasPrimaryFocus}');
    debugPrint('A primaryFocus debugLabel: ${FocusManager.instance.primaryFocus}');

    final spaceHandled = await simulateKeyDownEvent(LogicalKeyboardKey.space);
    await simulateKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    debugPrint('A space handled-by-framework=$spaceHandled pressed=$pressed');

    final enterHandled = await simulateKeyDownEvent(LogicalKeyboardKey.enter);
    await simulateKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    debugPrint('A enter handled-by-framework=$enterHandled pressed=$pressed submitted=$submitted');
    node.dispose();
  });

  testWidgets('B: control — bare TextField, no Pressable anywhere', (tester) async {
    final node = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(focusNode: node)),
    ));
    node.requestFocus();
    await tester.pumpAndSettle();
    final spaceHandled = await simulateKeyDownEvent(LogicalKeyboardKey.space);
    await simulateKeyUpEvent(LogicalKeyboardKey.space);
    final enterHandled = await simulateKeyDownEvent(LogicalKeyboardKey.enter);
    await simulateKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    debugPrint('B bare field: space handled=$spaceHandled enter handled=$enterHandled');
    node.dispose();
  });

  testWidgets('C: control — TextField inside a stock Material InkWell(onTap:)', (tester) async {
    var taps = 0;
    final node = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InkWell(
          onTap: () => taps++,
          child: TextField(focusNode: node),
        ),
      ),
    ));
    node.requestFocus();
    await tester.pumpAndSettle();
    final spaceHandled = await simulateKeyDownEvent(LogicalKeyboardKey.space);
    await simulateKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    debugPrint('C InkWell: space handled=$spaceHandled taps=$taps');
    node.dispose();
  });

  testWidgets('D: Pressable with NON-text child, field elsewhere — sanity that OK still works',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Pressable(
          autofocus: true,
          onPressed: () => pressed++,
          child: const SizedBox(width: 80, height: 80),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final handled = await simulateKeyDownEvent(LogicalKeyboardKey.select);
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    debugPrint('D plain Pressable: select handled=$handled pressed=$pressed');
  });

  testWidgets('E: does typed text still arrive through the IME path while wrapped?',
      (tester) async {
    var pressed = 0;
    final node = FocusNode();
    final ctl = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MaybePressable(
          enabled: isTv,
          onPressed: () {
            pressed++;
            node.requestFocus();
          },
          child: TextField(controller: ctl, focusNode: node),
        ),
      ),
    ));
    node.requestFocus();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pink floyd');
    await tester.pumpAndSettle();
    debugPrint('E text after IME entry: "${ctl.text}" pressed=$pressed');
    node.dispose();
  });
}
