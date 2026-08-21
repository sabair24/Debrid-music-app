/// Driving the app with a remote control.
///
/// A television has no pointer. Everything you can do there you do by moving a highlight with four
/// arrows and pressing OK — so every control must be able to hold that highlight, must show that it
/// holds it, and must act on OK. Flutter gives focus to its own Material widgets and nothing else,
/// which is why the app's own tiles, pills and covers were unreachable on the Shield while the
/// text fields were fine.
///
/// One widget here does all three things, so it is done the same way in all forty places rather
/// than forty slightly different ways.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/kleuren.dart';

/// Is this a television? Read once at startup by [initTvMode].
///
/// A getter over a mutable field rather than a constant: the answer comes from the platform and is
/// therefore not known when the file is loaded, but it never changes afterwards.
bool get isTv => _isTv;
bool _isTv = false;

const _channel = MethodChannel('debridmusic/device');

/// Ask Android whether this is a TV. Call before `runApp`.
///
/// Retries, and that is not defensiveness — it is a race with a known cause. `audio_service` warms
/// a Flutter engine up front, so Dart's `main()` can start running before the activity has attached
/// and registered this channel. Ask once and a Shield answers "not a television", which is how the
/// focus rings came out invisible the first time.
///
/// Nothing has been drawn yet at this point, so waiting a few tens of milliseconds costs nothing,
/// and the loop is bounded: a device that never answers is not a television, which is the right
/// answer everywhere except Android TV.
Future<void> initTvMode() async {
  if (!Platform.isAndroid) return;
  for (var attempt = 0; attempt < 20; attempt++) {
    try {
      _isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
      debugPrint('Device is a television: $_isTv');
      if (_isTv) {
        // Flutter decides whether to DRAW a focus highlight from how the app is being used, and on
        // Android it starts at "touch" — no highlight — until a key arrives. A television is never
        // touched, so that default means the very first press moves an invisible highlight and the
        // screen appears not to react. Say it outright instead.
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      }
      return;
    } on MissingPluginException {
      // The activity has not attached yet. Give the platform thread a moment and ask again.
      await Future<void>.delayed(const Duration(milliseconds: 25));
    } catch (e) {
      debugPrint('TV detection unavailable: $e');
      return;
    }
  }
  debugPrint('TV detection did not answer; assuming not a television.');
}

/// Overrides the detected answer, for tests and for `flutter run` on a desktop while working on
/// the ten-foot layout.
@visibleForTesting
void setTvModeForTest(bool value) => _isTv = value;

/// Is the window narrow enough that things have to stack rather than sit side by side?
///
/// A phone in portrait is about 412 points wide. Until now the app had exactly one breakpoint, and
/// it only moved the wordmark in the top bar — everything else was either desktop-sized or
/// "touch"-sized, and `_isTouch` cannot tell a 412-point phone from an 834-point iPad. That is why
/// the album page gave its title column eight points and printed one letter per line.
///
/// 600 is where a layout designed side-by-side stops fitting side by side, not a device class: a
/// desktop window dragged narrow gets the same treatment, which is the honest test of whether the
/// narrow layout actually works.
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// How far the disc slides out from behind the sleeve, as a fraction of the sleeve's width.
///
/// This is reserved WIDTH: [AlbumArt] lays out `size * (1 + factor)`, so on a phone in portrait
/// every percent of it comes off the sleeve and off whatever shares the row. Sideways, and on a
/// television, there is width to spare and the disc gets its full stride.
double discTravelFactor(BuildContext context) => isCompact(context) ? .30 : .62;

/// The width a dialog may actually take.
///
/// Every dialog in this app asked for a fixed width between 460 and 860 points, chosen when the
/// only thing running it was a desktop window. On a phone each one of those overflows its own
/// screen. Ask for what you want; take what there is.
double dialogWidth(BuildContext context, double preferred) {
  final available = MediaQuery.sizeOf(context).width - 32;
  return preferred < available ? preferred : available;
}

/// The same for height, for the dialogs that fix both.
///
/// De marge is niet vast, en dat is op een LIGGENDE telefoon het verschil tussen bruikbaar en niet.
/// Honderdtwintig punten is op een staand scherm van 890 een randje; op datzelfde toestel gedraaid
/// is het scherm 411 hoog en is dezelfde marge bijna een derde ervan. De uitgavekiezer hield daar
/// negentig punten lijst over onder zijn eigen kop — twee halve rijen, en scrollen door acht
/// uitgaves in een spleet.
double dialogHeight(BuildContext context, double preferred) {
  final h = MediaQuery.sizeOf(context).height;
  final available = h - (h < 520 ? 24 : 120);
  return preferred < available ? preferred : available;
}

/// How far the safe area sits in from the panel edge.
///
/// Televisions overscan: a part of the picture falls off the edge of the screen, and how much
/// differs per set. Every TV interface leaves a margin for it, and one that does not gets its
/// top row of covers cut in half on somebody's screen.
///
/// 48 by 27 is Google's 5% on the canvas this app actually gets: the Shield reports 1920x1080 at
/// density 320, so Flutter lays out on 960x540 points. The 32 by 20 it used to be is 3.3%, which
/// is inside the 5% an older set can swallow — and the back arrow of every pushed page sits in
/// exactly that strip.
///
/// [SafeArea] is not an alternative here. A television reports no display cutout and no system
/// insets, so its padding is zero and it does nothing at all on this device.
EdgeInsets get tvOverscan =>
    isTv ? const EdgeInsets.symmetric(horizontal: 48, vertical: 27) : EdgeInsets.zero;

/// A control that can be reached with a remote, clicked with a mouse and tapped with a finger.
///
/// Wraps whatever it is given rather than replacing it, so applying this to an existing tile does
/// not change how that tile looks — until it holds the highlight, and then it says so.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.onSecondaryTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.autofocus = false,
    this.focusNode,
    this.scaleOnFocus = true,
    this.ringOnFocus = true,
    this.cursor = SystemMouseCursors.click,
    this.onFocusChange,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// Right-click, met de plek waar de muis stond.
  ///
  /// Kept because a mouse has one and dropping it here would quietly take a feature away from
  /// Windows, Mac and iPad to give one to the remote — where the same action is reached by holding
  /// OK, which is [onLongPress].
  ///
  /// **Waarom er een positie in zit.** Een menu hoort te verschijnen waar je klikte. Dit was een
  /// kale `VoidCallback`, en dus hing elk contextmenu aan de rand van de RIJ — op de derde rij
  /// klikken en het menu ergens anders zien opengaan leest als een fout.
  final void Function(Offset globaal)? onSecondaryTap;

  /// Matched to the shape of what is being wrapped, so the ring hugs a cover's corners instead of
  /// drawing a rectangle around a rounded card.
  final BorderRadius borderRadius;

  final bool autofocus;
  final FocusNode? focusNode;

  /// The gentle lift a focused tile gets. Off for things that sit in a tight row, where a growing
  /// neighbour would push the row around.
  final bool scaleOnFocus;

  /// Whether to draw the ring at all.
  ///
  /// Off for anything that answers "where am I" by growing instead — a cover tile. A ring around an
  /// album is a frame around the artwork, and it competes with the very thing you are looking at.
  /// On for everything that cannot grow: buttons, list rows, chips in a tight row.
  final bool ringOnFocus;

  final MouseCursor cursor;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _focused = false;
  bool _hovered = false;

  /// Ligt er nu een vinger op? Voedt de indrukbeweging; zie [build].
  bool _ingedrukt = false;

  void _zetIngedrukt(bool v) {
    if (_ingedrukt == v || !mounted) return;
    setState(() => _ingedrukt = v);
  }

  void _activate() {
    final action = widget.onPressed;
    if (action != null) action();
  }

  /// Put the thing that just took the highlight in the middle of the list, not against its edge.
  ///
  /// Flutter's own focus scrolling brings an item just far enough to be technically visible, which
  /// leaves it flush against the top or bottom of the viewport. In this app the top of a scroll
  /// area sits under the search bar and the bottom under the player bar, so "just visible" means
  /// half-hidden — with the ring and its glow clipped, which is exactly the part that answers
  /// "where am I".
  ///
  /// Here rather than at forty call sites, and only on a television: with a mouse the pointer is
  /// already the answer, and a list that scrolls itself under the cursor would be maddening.
  void _bringIntoView() {
    if (!isTv) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    // After the frame: the highlight often arrives during a build, and asking a scrollable to move
    // mid-layout throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null || widget.onLongPress != null;

    Widget content = widget.child;

    // Only on a TV. Under a mouse the hover state already says where you are, and a ring around
    // everything the pointer touches is noise.
    // `scaleOnFocus` in the condition, not only inside it: without that every Pressable that has
    // explicitly opted OUT of growing still built an AnimatedScale, which carries its own
    // AnimationController and Ticker. They never animate, so they cost no frame time — but they are
    // created and disposed for every tile you scroll past, and that is most of the app.
    if (isTv && widget.scaleOnFocus) {
      content = AnimatedScale(
        scale: _focused ? tileFocusScale : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: content,
      );
    } else if (!isTv && widget.onPressed != null) {
      // **Aanraakfeedback, en dit was het grootste gat op een telefoon.**
      //
      // Alles wat je kunt aantikken loopt door deze widget: elke albumtegel, elke nummerrij, elke
      // starttegel. De enige zichtbare reactie zat op `hover` (een `MouseRegion`) en op `focus` —
      // en die vuren op een telefoon nooit. Je tikte een album aan, er gebeurde twee tot vier
      // tienden van een seconde niets, en dan verscheen de pagina. Dat is de reden dat de app traag
      // aanvoelde terwijl hij dat niet was.
      //
      // Bewust een indrukbeweging en geen inktvlek: deze app tekent tegels met eigen hoeken en
      // schaduwen, en een ripple die daar overheen loopt ziet er verkeerd uit. Klein en kort — je
      // moet het voelen, niet zien.
      content = AnimatedScale(
        scale: _ingedrukt ? .97 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: content,
      );
    }

    // Holding OK is a real gesture on a remote, and Flutter does not give it to you.
    //
    // ActivateIntent fires on key DOWN, so a hold had already run onPressed before anything could
    // notice it was a hold — which meant "hold OK to set the backdrop" silently overwrote the
    // portrait instead. When there is a long press to reach, the keys are handled here on the way
    // UP: short is a press, long is a long press. Nothing changes for a mouse, or when a widget has
    // no long press to offer.
    final holdable = isTv && widget.onLongPress != null && widget.onPressed != null;

    Widget detector = FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: enabled,
      mouseCursor: enabled ? widget.cursor : MouseCursor.defer,
      onShowFocusHighlight: (v) {
        if (v == _focused) return;
        setState(() => _focused = v);
        widget.onFocusChange?.call(v);
        if (v) _bringIntoView();
      },
      onShowHoverHighlight: (v) => v == _hovered ? null : setState(() => _hovered = v),
      shortcuts: holdable ? const <ShortcutActivator, Intent>{} : _activateShortcuts,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          _activate();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onLongPress: widget.onLongPress,
        // `onSecondaryTapDown` en niet `onSecondaryTap`: alleen de eerste draagt een coördinaat.
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (d) => widget.onSecondaryTap!(d.globalPosition),
        // De drie haken die de indrukbeweging hierboven voeden. `onTapCancel` hoort erbij: wie
        // begint te scrollen met zijn vinger op een tegel moet die tegel weer zien opveren, anders
        // blijft hij ingedrukt staan terwijl de lijst wegschuift.
        onTapDown: isTv || widget.onPressed == null ? null : (_) => _zetIngedrukt(true),
        onTapUp: isTv || widget.onPressed == null ? null : (_) => _zetIngedrukt(false),
        onTapCancel: isTv || widget.onPressed == null ? null : () => _zetIngedrukt(false),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              // Transparent rather than absent, so the ring appearing does not change the widget's
              // size and shift everything around it by two pixels.
              color: _focused && widget.ringOnFocus ? _ring : Colors.transparent,
              width: _ringWidth,
            ),
            boxShadow: _focused && widget.ringOnFocus
                ? [BoxShadow(color: _ring.withValues(alpha: .45), blurRadius: 18, spreadRadius: 1)]
                : null,
          ),
          child: content,
        ),
      ),
    );

    if (!holdable) return detector;

    // Wrapped, not focusable: key events bubble from the focused node up through its ancestors, so
    // this sees OK without adding a second stop in front of every control that has a long press.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onHoldKey,
      child: detector,
    );
  }

  /// When OK went down, so the way up can tell a press from a hold.
  DateTime? _downAt;

  /// Set when the key started auto-repeating, which is Android's own way of saying "still held".
  ///
  /// Checked as well as the clock, not instead of it: a remote that repeats quickly would beat a
  /// wall-clock threshold, and one that does not repeat at all still gets caught by the clock.
  bool _repeated = false;

  static const _holdFor = Duration(milliseconds: 500);

  KeyEventResult _onHoldKey(FocusNode _, KeyEvent e) {
    final k = e.logicalKey;
    final ours = k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space;
    if (!ours) return KeyEventResult.ignored;
    // Repeats are what a held button produces; they are not extra presses.
    if (e is KeyRepeatEvent) {
      _repeated = true;
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent) {
      _downAt = DateTime.now();
      _repeated = false;
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) {
      final down = _downAt;
      final held = _repeated;
      _downAt = null;
      _repeated = false;
      if (down == null) return KeyEventResult.ignored;
      if (held || DateTime.now().difference(down) >= _holdFor) {
        widget.onLongPress?.call();
      } else {
        _activate();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// An icon that says what it does, once the highlight is on it.
///
/// Icon buttons carry their meaning in a tooltip, and a tooltip appears on mouse hover or on a
/// long press. A remote produces neither — so a row of four near-identical glyphs carries no
/// meaning at all from three metres, and the only thing on screen is a ring around a picture.
///
/// Not solvable by configuring [Tooltip]: it has no focus trigger. So the label is drawn here,
/// under the icon, while the icon holds the focus. Off a television this is the child untouched,
/// tooltip and all.
class TvLabelled extends StatefulWidget {
  const TvLabelled({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  State<TvLabelled> createState() => _TvLabelledState();
}

class _TvLabelledState extends State<TvLabelled> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!isTv) return widget.child;
    return Focus(
      // Watching, not taking: the button inside is what holds the highlight. A Focus that could
      // take it itself would add a second stop in front of every icon.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) => v == _focused ? null : setState(() => _focused = v),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.child,
          // Reserved whether or not it is shown, so a row of icons does not jump in height as the
          // highlight runs along it.
          SizedBox(
            // 16, not the 11 it started at: this label exists BECAUSE a tooltip cannot be read from
            // a couch, and 11 points on a 960-wide canvas cannot be read from a couch either. It
            // would have been the smallest text on the screen while being the only thing explaining
            // what the icon above it does.
            height: 20,
            child: _focused
                ? Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, height: 1.1, color: _ring),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// A [Pressable] on a television and nothing at all anywhere else.
///
/// For the handful of places where the remote needs a step that a mouse must not get. Written as a
/// widget rather than an `if` at each call site so the child is built once and reads the same in
/// both cases — a conditional tree there would mean the field is rebuilt from scratch whenever the
/// condition is touched, losing what you were typing.
class MaybePressable extends StatelessWidget {
  const MaybePressable({
    super.key,
    required this.enabled,
    required this.child,
    this.onPressed,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  final bool enabled;
  final Widget child;
  final VoidCallback? onPressed;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Pressable(
      onPressed: onPressed,
      borderRadius: borderRadius,
      scaleOnFocus: false,
      child: child,
    );
  }
}

/// The app's own accent, not Flutter's default focus colour. From three metres away a thin grey
/// outline on a dark panel is invisible, and "where am I" is the only question a remote asks.
const _ring = kAccent;

double get _ringWidth => isTv ? 3 : 2;

/// How much a cover tile grows while it holds the highlight.
///
/// On a television this IS the answer to "which one is selected": there is no pointer, and a tile
/// that carries artwork gets no ring, because a frame around a record sleeve competes with the
/// sleeve. From three metres 1.06 reads as a rendering artefact; 1.14 reads as a choice. With a
/// mouse the pointer already answers the question, so hovering keeps the gentle lift it had.
///
/// Anything that uses this must leave room for it — a horizontal list hands its children a tight
/// height and clips whatever grows past it. See the row height in `_section`.
double get tileFocusScale => isTv ? 1.14 : 1.06;

/// What counts as "press this".
///
/// Flutter maps Enter and Space by default. A remote sends neither: the OK button is
/// [LogicalKeyboardKey.select], and a game controller sends `gameButtonA`. Without these the
/// highlight moves perfectly and pressing OK does nothing, which is the worst of both worlds.
const Map<ShortcutActivator, Intent> _activateShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
};

/// BACK leaves the text field first, and only then the screen.
///
/// A television has no Escape key and no way to tap somewhere else, and a focused text field claims
/// all four arrows: `DirectionalFocusAction.forTextField` deliberately ignores directional intents
/// so that the arrows can move the caret. So once the highlight is inside a field, BACK is the only
/// key left — and BACK popped the whole route. Type a TorBox key into Settings, press BACK to get
/// out of the field, and the dialog closes with the key unsaved. The app never called `unfocus()`
/// anywhere, so there was no way out that kept your typing.
///
/// One listener at the root rather than a PopScope in every dialog: this is a property of the
/// remote, not of any one screen. Off a television it does nothing at all — there Escape and the
/// pointer both already work, and swallowing a back gesture would be wrong.
class TvTextFieldEscape extends StatefulWidget {
  const TvTextFieldEscape({super.key, required this.child});

  final Widget child;

  /// True when the highlight is inside something that edits text.
  ///
  /// Asked of the focused node's own context rather than of a flag, because `SelectableText` builds
  /// an `EditableText` too — and that one is the worse trap of the two: it takes the arrows without
  /// even opening a keyboard to explain why nothing moves.
  static bool editingText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  State<TvTextFieldEscape> createState() => _TvTextFieldEscapeState();
}

/// Not [BackButtonListener], which needs a [Router] ancestor — this app is built on `MaterialApp`
/// with a `home:` and a plain [Navigator], so that widget throws here. A binding observer is the
/// mechanism that matches: [WidgetsBinding.handlePopRoute] walks its observers in reverse
/// registration order, and this one registers inside the app, hence after `WidgetsApp`'s — so it is
/// asked first and can decline by returning false.
class _TvTextFieldEscapeState extends State<TvTextFieldEscape> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (isTv) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (isTv) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (!isTv || !TvTextFieldEscape.editingText()) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
