/// The widget that makes the app usable with a remote.
///
/// Worth testing rather than eyeballing, because it is about to be used in forty places: a mistake
/// here is not one broken button but a broken app, and half of what it does — taking focus, drawing
/// a ring, answering the OK key — is invisible in a screenshot until you press something.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/tv.dart';

/// A [Pressable] alone on a screen, with the focus highlight forced on as it is on a television.
Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  setUp(() {
    setTvModeForTest(true);
    // What initTvMode does on a TV. Without it Flutter draws no highlight at all, which is exactly
    // the bug this was written after.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });

  tearDown(() {
    setTvModeForTest(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  group('the remote can press it', () {
    testWidgets('OK on a remote fires the same callback the mouse does', (tester) async {
      var presses = 0;
      await tester.pumpWidget(_app(Pressable(
        autofocus: true,
        onPressed: () => presses++,
        child: const Text('Afspelen'),
      )));
      await tester.pumpAndSettle();

      // KEYCODE_DPAD_CENTER arrives as this. Enter and Space are what Flutter maps by default; a
      // remote sends neither, which is why they are not enough on their own.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(presses, 1, reason: 'de OK-knop van de afstandsbediening');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(presses, 2, reason: 'een toetsenbord moet ook blijven werken');

      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await tester.pumpAndSettle();
      expect(presses, 3, reason: 'een gamepad is op een Shield het andere invoerapparaat');
    });

    testWidgets('a tap still works, so mouse and finger are unchanged', (tester) async {
      var presses = 0;
      await tester.pumpWidget(_app(Pressable(
        onPressed: () => presses++,
        child: const SizedBox(width: 120, height: 40, child: Text('Afspelen')),
      )));

      await tester.tap(find.text('Afspelen'));
      await tester.pumpAndSettle();
      expect(presses, 1,
          reason: 'dit vervangt 40 InkWells op Windows, Mac en iPad — daar mag niets veranderen');
    });

    testWidgets('a long press keeps its own meaning', (tester) async {
      var pressed = 0, longPressed = 0;
      await tester.pumpWidget(_app(Pressable(
        onPressed: () => pressed++,
        onLongPress: () => longPressed++,
        child: const SizedBox(width: 120, height: 40, child: Text('Album')),
      )));

      await tester.longPress(find.text('Album'));
      await tester.pumpAndSettle();
      expect(longPressed, 1);
      expect(pressed, 0, reason: 'lang drukken is een andere handeling, geen gewone druk');
    });
  });

  group('you can see where you are', () {
    /// The ring is a border on the DecoratedBox this widget wraps its child in.
    Color? ringColour(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(find
          .descendant(of: find.byType(Pressable), matching: find.byType(DecoratedBox))
          .first);
      final side = (box.decoration as BoxDecoration).border?.top;
      return side?.color;
    }

    testWidgets('focused draws the accent, unfocused draws nothing', (tester) async {
      await tester.pumpWidget(_app(Row(children: [
        Pressable(autofocus: true, onPressed: () {}, child: const Text('Start')),
        Pressable(onPressed: () {}, child: const Text('Albums')),
      ])));
      await tester.pumpAndSettle();

      final rings = tester
          .widgetList<DecoratedBox>(find
              .descendant(of: find.byType(Pressable), matching: find.byType(DecoratedBox)))
          .map((b) => (b.decoration as BoxDecoration).border?.top.color)
          .toList();

      // The app's own accent, not Flutter's grey default: on a dark panel from three metres away
      // a thin grey outline is not visible, and "where am I" is the only question a remote asks.
      expect(rings.first, const Color(0xFF7C5CFF));
      expect(rings.last, Colors.transparent,
          reason: 'transparant, niet afwezig — een rand die verschijnt zou alles verschuiven');
    });

    testWidgets('the ring never changes the size of what it wraps', (tester) async {
      await tester.pumpWidget(_app(Pressable(
        autofocus: true,
        scaleOnFocus: false,
        onPressed: () {},
        child: const SizedBox(width: 200, height: 60),
      )));
      await tester.pumpAndSettle();
      final focused = tester.getSize(find.byType(Pressable));

      await tester.pumpWidget(_app(Pressable(
        onPressed: () {},
        scaleOnFocus: false,
        child: const SizedBox(width: 200, height: 60),
      )));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(Pressable)), focused,
          reason: 'anders schuift de hele rij op zodra de markering erlangs gaat');
    });
  });

  group('what cannot be pressed cannot be reached', () {
    testWidgets('without a callback it does not take focus', (tester) async {
      await tester.pumpWidget(_app(Column(children: [
        const Pressable(child: Text('Alleen tekst')),
        Pressable(autofocus: true, onPressed: () {}, child: const Text('Knop')),
      ])));
      await tester.pumpAndSettle();

      // Otherwise the highlight stops on things that do nothing, and a remote user presses OK on
      // them wondering why the app ignores them.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      final decorated = tester
          .widgetList<DecoratedBox>(find
              .descendant(of: find.byType(Pressable), matching: find.byType(DecoratedBox)))
          .map((b) => (b.decoration as BoxDecoration).border?.top.color)
          .toList();
      expect(decorated.first, Colors.transparent);
    });
  });

  group('a phone is not a television', () {
    testWidgets('no lift and a thinner ring when this is not a TV', (tester) async {
      setTvModeForTest(false);
      await tester.pumpWidget(_app(Pressable(
        autofocus: true,
        onPressed: () {},
        child: const Text('Afspelen'),
      )));
      await tester.pumpAndSettle();

      // The scale animation exists to be seen from a sofa. Under a thumb it would just wobble.
      expect(find.byType(AnimatedScale), findsNothing);

      final box = tester.widget<DecoratedBox>(find
          .descendant(of: find.byType(Pressable), matching: find.byType(DecoratedBox))
          .first);
      expect((box.decoration as BoxDecoration).border?.top.width, 2);
    });

    testWidgets('overscan margin is a TV thing only', (tester) async {
      setTvModeForTest(true);
      expect(tvOverscan, isNot(EdgeInsets.zero),
          reason: 'een tv snijdt de rand van het beeld weg, en per toestel anders');
      setTvModeForTest(false);
      expect(tvOverscan, EdgeInsets.zero);
    });
  });
}
