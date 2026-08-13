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
  pijlPoortTests();
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

    testWidgets('a cover tile answers by growing, not by wearing a frame', (tester) async {
      // A record sleeve is the one thing on the screen you are actually looking at, and a ring
      // around it is a frame around the artwork. Those tiles say "this one" by growing instead, so
      // they ask for the ring to be left off — and then it really must be off, or you get both.
      await tester.pumpWidget(_app(Pressable(
        autofocus: true,
        onPressed: () {},
        ringOnFocus: false,
        scaleOnFocus: false,
        child: const SizedBox(width: 140, height: 140),
      )));
      await tester.pumpAndSettle();

      final box = tester.widget<DecoratedBox>(find
          .descendant(of: find.byType(Pressable), matching: find.byType(DecoratedBox))
          .first);
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.border?.top.color, Colors.transparent,
          reason: 'geen kader rond de hoes');
      expect(decoration.boxShadow, anyOf(isNull, isEmpty),
          reason: 'ook de gloed hoort bij het kader — anders staat het kader er alsnog, waziger');
    });

    test('growing is visible from the couch, gentle under a pointer', () {
      // The whole cue on a television, so it has to survive three metres. 1.06 does not.
      setTvModeForTest(true);
      expect(tileFocusScale, greaterThanOrEqualTo(1.12));
      setTvModeForTest(false);
      expect(tileFocusScale, lessThan(1.12),
          reason: 'met een muis zegt de aanwijzer het al; een tegel die opspringt is dan onrustig');
    });
  });

  group('BACK laat het tekstveld los voordat het het scherm sluit', () {
    /// What Android does when the remote's BACK is pressed.
    Future<void> pressBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    testWidgets('a focused field is left, and the screen stays', (tester) async {
      final node = FocusNode();
      var popped = false;
      await tester.pumpWidget(TvTextFieldEscape(
        child: MaterialApp(
          home: PopScope(
            canPop: false,
            onPopInvokedWithResult: (_, __) => popped = true,
            child: Scaffold(body: TextField(focusNode: node, autofocus: true)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue, reason: 'de opzet klopt niet als het veld de focus niet heeft');

      await pressBack(tester);

      expect(node.hasFocus, isFalse, reason: 'BACK hoort je uit het veld te halen');
      expect(popped, isFalse,
          reason: 'en niet ook meteen het scherm te sluiten — daar gaat je getypte sleutel');
    });

    testWidgets('with the highlight anywhere else, BACK is BACK again', (tester) async {
      // The escape must not swallow every back press, or a remote could never leave a screen.
      var reached = false;
      await tester.pumpWidget(TvTextFieldEscape(
        child: MaterialApp(
          home: _BackSpy(
            onBack: () => reached = true,
            child: Scaffold(body: Pressable(autofocus: true, onPressed: () {}, child: const Text('Start'))),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await pressBack(tester);
      expect(reached, isTrue, reason: 'BACK moet gewoon doorgaan als er geen veld in de weg staat');
    });

    testWidgets('off a television nothing is intercepted', (tester) async {
      setTvModeForTest(false);
      final node = FocusNode();
      var reached = false;
      await tester.pumpWidget(TvTextFieldEscape(
        child: MaterialApp(
          home: _BackSpy(
            onBack: () => reached = true,
            child: Scaffold(body: TextField(focusNode: node, autofocus: true)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await pressBack(tester);
      expect(reached, isTrue,
          reason: 'op een telefoon en een pc bestaat dit probleem niet; daar is BACK gewoon BACK');
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

      // GEEN GROEI BIJ FOCUS. Dat is wat hier stond, en dat blijft: een tegel die opzwelt omdat de
      // aanwijzer erop staat is voor een bank op vijf meter, niet voor een duim.
      //
      // De regel was eerst "geen AnimatedScale op een telefoon, punt". Dat gooide twee dingen op één
      // hoop. Er is nu wél een AnimatedScale, maar die staat op 1.0 tot je hem indrukt — zie de
      // toets hieronder. Zonder dat onderscheid had de app op een telefoon nergens een reactie op
      // een aanraking, en dat was het grootste gebrek dat een beoordeling van de telefoonkant
      // opleverde: je tikt een album aan, er gebeurt drie tienden van een seconde niets, en dan
      // verschijnt de pagina.
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0,
          reason: 'focus alleen mag niets laten groeien');

      final box = tester.widget<DecoratedBox>(find
          .descendant(of: find.byType(Pressable), matching: find.byType(DecoratedBox))
          .first);
      expect((box.decoration as BoxDecoration).border?.top.width, 2);
    });

    testWidgets('maar onder een duim veert hij wél even in', (tester) async {
      // Aanraakfeedback. Alles wat je in deze app kunt aantikken loopt door Pressable, en er was
      // geen enkele zichtbare reactie op een vinger: de bestaande animaties hingen aan `hover` en
      // `focus`, en die vuren op een telefoon nooit.
      setTvModeForTest(false);
      await tester.pumpWidget(_app(Pressable(onPressed: () {}, child: const Text('Afspelen'))));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);

      final gebaar = await tester.startGesture(tester.getCenter(find.text('Afspelen')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, lessThan(1.0),
          reason: 'ingedrukt hoort te voelen');

      await gebaar.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0,
          reason: 'en weer terug als je loslaat');
    });

    testWidgets('een afgebroken tik laat hem niet ingedrukt staan', (tester) async {
      // Wie met zijn vinger op een tegel begint te scrollen moet die tegel zien opveren. Zonder
      // onTapCancel blijft hij ingedrukt staan terwijl de lijst onder je vinger wegschuift.
      setTvModeForTest(false);
      await tester.pumpWidget(_app(Pressable(onPressed: () {}, child: const Text('Afspelen'))));
      final gebaar = await tester.startGesture(tester.getCenter(find.text('Afspelen')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, lessThan(1.0));
      await gebaar.cancel();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    });

    testWidgets('overscan margin is a TV thing only', (tester) async {
      setTvModeForTest(true);
      expect(tvOverscan, isNot(EdgeInsets.zero),
          reason: 'een tv snijdt de rand van het beeld weg, en per toestel anders');
      setTvModeForTest(false);
      expect(tvOverscan, EdgeInsets.zero);
    });
  });

  group('OK ingedrukt houden', () {
    // adb cannot simulate a held key — `input keyevent --longpress` sets a flag and releases
    // immediately — so this is where the hold path is proven. It matters: on a television, holding
    // OK on a track row is the ONLY way to reach "move" and "delete", because Flutter's directional
    // traversal can never select a node whose rectangle lies inside the focused one's.
    testWidgets('a short press is a press, a held one is a long press', (tester) async {
      var pressed = 0, held = 0;
      await tester.pumpWidget(_app(Pressable(
        autofocus: true,
        onPressed: () => pressed++,
        onLongPress: () => held++,
        child: const Text('Nummer'),
      )));
      await tester.pumpAndSettle();

      // Down and straight up: a press.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(pressed, 1);
      expect(held, 0);

      // Down, Android repeats because it is still held, then up: a long press.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(held, 1, reason: 'de herhaling is hoe Android zegt dat de knop nog ingedrukt is');
      expect(pressed, 1, reason: 'vasthouden mag niet OOK het nummer starten');
    });

    testWidgets('without a long press to reach, nothing changes', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_app(Pressable(
        autofocus: true,
        onPressed: () => pressed++,
        child: const Text('Alleen drukken'),
      )));
      await tester.pumpAndSettle();

      // Still the ordinary path: ActivateIntent on key down, which is what every other control in
      // the app relies on.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(pressed, 1);
    });

    testWidgets('a phone keeps the pointer long-press and not the key one', (tester) async {
      setTvModeForTest(false);
      var pressed = 0, held = 0;
      await tester.pumpWidget(_app(Pressable(
        autofocus: true,
        onPressed: () => pressed++,
        onLongPress: () => held++,
        child: const SizedBox(width: 120, height: 40, child: Text('Nummer')),
      )));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Nummer'));
      await tester.pumpAndSettle();
      expect(held, 1, reason: 'een vinger of muis houdt gewoon vast zoals altijd');

      // And the key path is NOT installed off a television, so OK is still a plain press.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(pressed, greaterThan(0));
      expect(held, 1, reason: 'een toetsenbord dat herhaalt is geen lang indrukken op een pc');
    });
  });
}

/// Stands in for whatever would otherwise handle BACK — the Navigator in the real app.
///
/// Registered as a binding observer like [TvTextFieldEscape] is, but from OUTSIDE it, so the
/// binding asks the escape first. If the escape declines, this one hears it.
class _BackSpy extends StatefulWidget {
  const _BackSpy({required this.onBack, required this.child});
  final VoidCallback onBack;
  final Widget child;
  @override
  State<_BackSpy> createState() => _BackSpyState();
}

class _BackSpyState extends State<_BackSpy> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    widget.onBack();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// De pijltjes op het "Nu speelt"-scherm.
///
/// Links en rechts zijn op een televisie óók hoe de markering tussen knoppen loopt. Ze afvangen
/// voor vorige/volgende mag dus alleen daar waar ze niets anders doen — op de hoes. Deze test pint
/// de poort die dat regelt: staat de markering ergens anders, dan moeten de pijlen ongemoeid door.
void pijlPoortTests() {
  group('links en rechts alleen vanaf de hoes', () {
    testWidgets('op een knop verplaatsen de pijlen gewoon de markering', (tester) async {
      final links = FocusNode(debugLabel: 'links');
      final rechts = FocusNode(debugLabel: 'rechts');
      var afgevangen = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            // Dezelfde vorm als op het echte scherm: een poort die alleen sluit wanneer de
            // markering op de hoes staat. Hier staat hij op een knop, dus hij moet openblijven.
            onKeyEvent: (_, e) {
              if (e is! KeyDownEvent) return KeyEventResult.ignored;
              if (e.logicalKey == LogicalKeyboardKey.arrowRight ||
                  e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                afgevangen++;
                return KeyEventResult.ignored; // poort dicht: markering mag door
              }
              return KeyEventResult.ignored;
            },
            child: Row(children: [
              Pressable(focusNode: links, autofocus: true, onPressed: () {}, child: const Text('vorige')),
              Pressable(focusNode: rechts, onPressed: () {}, child: const Text('volgende')),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(links.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(rechts.hasFocus, isTrue,
          reason: 'een handler die `ignored` teruggeeft mag de markering niet tegenhouden');
      expect(afgevangen, 1, reason: 'de handler zag de toets wél — hij liet hem alleen door');
    });

    testWidgets('afgevangen met `handled` blijft de markering staan', (tester) async {
      final een = FocusNode(debugLabel: 'een');
      final twee = FocusNode(debugLabel: 'twee');
      var volgende = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, e) {
              if (e is! KeyDownEvent) return KeyEventResult.ignored;
              if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                volgende++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Row(children: [
              Pressable(focusNode: een, autofocus: true, onPressed: () {}, child: const Text('hoes')),
              Pressable(focusNode: twee, onPressed: () {}, child: const Text('knop')),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(volgende, 1);
      expect(een.hasFocus, isTrue,
          reason: 'dit is de kern: op de hoes gaat de pijl naar het volgende NUMMER, '
              'niet naar de volgende knop');
    });

    testWidgets('een ingedrukt gehouden pijl telt maar één keer', (tester) async {
      var keer = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Focus(
            autofocus: true,
            onKeyEvent: (_, e) {
              // Precies de poort van het echte scherm: alleen KeyDownEvent.
              if (e is! KeyDownEvent) return KeyEventResult.ignored;
              if (e.logicalKey != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
              keer++;
              return KeyEventResult.handled;
            },
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(keer, 1,
          reason: 'anders raast één lange druk door de hele wachtrij');
    });
  });
}
