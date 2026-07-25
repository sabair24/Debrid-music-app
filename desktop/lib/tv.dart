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
double dialogHeight(BuildContext context, double preferred) {
  final available = MediaQuery.sizeOf(context).height - 120;
  return preferred < available ? preferred : available;
}

/// How far the safe area sits in from the panel edge.
///
/// Televisions overscan: a part of the picture falls off the edge of the screen, and how much
/// differs per set. Every TV interface leaves a margin for it, and one that does not gets its
/// top row of covers cut in half on somebody's screen.
EdgeInsets get tvOverscan =>
    isTv ? const EdgeInsets.symmetric(horizontal: 32, vertical: 20) : EdgeInsets.zero;

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
    this.cursor = SystemMouseCursors.click,
    this.onFocusChange,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// Right-click. Kept because a mouse has one and dropping it here would quietly take a feature
  /// away from Windows, Mac and iPad to give one to the remote — where the same action is reached
  /// by holding OK, which is [onLongPress].
  final VoidCallback? onSecondaryTap;

  /// Matched to the shape of what is being wrapped, so the ring hugs a cover's corners instead of
  /// drawing a rectangle around a rounded card.
  final BorderRadius borderRadius;

  final bool autofocus;
  final FocusNode? focusNode;

  /// The gentle lift a focused tile gets. Off for things that sit in a tight row, where a growing
  /// neighbour would push the row around.
  final bool scaleOnFocus;

  final MouseCursor cursor;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _focused = false;
  bool _hovered = false;

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
    if (isTv) {
      content = AnimatedScale(
        scale: _focused && widget.scaleOnFocus ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 130),
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
        onSecondaryTap: widget.onSecondaryTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              // Transparent rather than absent, so the ring appearing does not change the widget's
              // size and shift everything around it by two pixels.
              color: _focused ? _ring : Colors.transparent,
              width: _ringWidth,
            ),
            boxShadow: _focused
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
            height: 14,
            child: _focused
                ? Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, height: 1.1, color: _ring),
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
const _ring = Color(0xFF7C5CFF);

double get _ringWidth => isTv ? 3 : 2;

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
