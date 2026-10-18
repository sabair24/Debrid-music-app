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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'navigatie.dart' show BalkRuimte;
import 'ui/glas.dart';
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

/// Is dit een scherm dat wél naast elkaar past, maar géén bureaublad is?
///
/// **Het gat dat dit dicht.** Er was precies één drempel, en alles erboven kreeg dezelfde indeling:
/// een iPad in portret is 834 punten breed en kwam daarmee in dezelfde bak als een monitor van
/// 2560. Twee plekken hebben dat opgemerkt en er lokaal omheen gerekend — de spelerbalk
/// (`main.dart`, "twee blokken van 280 plus de knoppen passen niet op een iPad in portret") en de
/// bovenbalk — maar de rest van de app weet het niet.
///
/// **De grenzen, en waarom juist deze.** Een iPad is 834 (portret) of 1194 (liggend); een Shield
/// legt op 960 uit maar wordt door [isTv] al apart afgehandeld. Onder de 600 stapelt alles al
/// ([isCompact]); vanaf 1280 is er ruimte voor een bureaubladindeling met een kolom ernaast. Wat
/// daartussen zit is breed genoeg voor twee kolommen en te smal voor drie.
///
/// Gebruik dit voor RUIMTE — kleinere goten, minder diepe inspringing, minder kolommen — niet om
/// dingen te verbergen. Een iPad kan alles wat een pc kan; hij heeft alleen minder plek.
bool isTablet(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w >= 600 && w < 1280;
}

/// Een bureaublad: Windows, macOS of Linux.
bool get isBureaublad =>
    bureaubladVoorToets ?? (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Zet [isBureaublad] vast, voor een toets die een iPad naspeelt. Null = het echte platform.
@visibleForTesting
bool? bureaubladVoorToets;

/// Glas zonder echte vervaging — alleen de vulling, de rand en de schaduw. Overal behalve op een
/// bureaublad.
///
/// **Gemeten, niet geraden.** Saber op 10-10-2026: *"de ipad wordt nog altijd extreem warm heet
/// zelf, bij album detailscreen ook en now playing, eigenlijk overal"*. De warmtemeter van 3.9.458
/// gaf in `warmte.log` van de iPad (120 Hz, 1668×2388 px), over 72 vensters van tien seconden:
/// steeds ~60 beelden per seconde zolang de cd draait, en per beeld 1,4 ms rasteren op een scherm
/// met 0–2 glasvlakken tegen gemiddeld 6,5 ms (tot 24 ms) met 8 of meer — de albumpagina en Nu
/// speelt, precies waar de cd draait. Een `BackdropFilter` is de enige laag die niet bewaard kan
/// worden: bij elk beeld leest hij het scherm terug en vervaagt het opnieuw, en dat tien tot veertien
/// keer. De GPU stond op die schermen tot 100 % bezet en de batterij zakte 10 % in elf minuten.
///
/// De telefoon kreeg zijn glas om dezelfde reden al zonder vervaging (`isCompact`), en de
/// televisie (`isTv`) ook. Breedte was de verkeerde maat: een iPad is breed, maar heeft net zo goed
/// een batterij en een GPU die warm wordt. Op een pc kost het niets wat telt.
///
/// **Sinds 16-10-2026 wél vervaging op een toestel, en die meting is precies waarom het nu kan.** Het
/// waren tien tot veertien vervagingen die elk apart het scherm teruglazen. Nu hebben alle matte
/// vlakken hetzelfde filter onder één `BackdropGroup`: één terugleesbeurt voor allemaal (zie
/// `ui/glas.dart`). En een bewaker meet de tekentijd: wordt het te zwaar, dan gaat het glas terug naar
/// mat en daarna naar plat — en dan geldt dit weer. Saber koos dat zo: vloeibaar glas, overal.
bool get glasZonderVervaging => isTv || GlasKwaliteit.stand.value == GlasStand.plat;

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
    this.focusScale,
    this.vastePlek = true,
    this.schuifInBeeld = true,
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

  /// Hoeveel hij groeit met de selectie op een tv. Null = [tileFocusScale], de maat van een hoes;
  /// een kaart over de volle breedte groeit minder, anders loopt hij het scherm uit.
  final double? focusScale;

  /// Op een tv: de selectie op een vaste plek houden ([tvVastePlek]) in plaats van in het midden.
  /// Uit voor wat zelf al beslist waar het hoort, zoals de bovenbalk.
  final bool vastePlek;

  /// Op een tv: de lijst eromheen laten schuiven als dit de selectie krijgt. Uit waar de omgeving
  /// dat zelf regelt — de kop van de artiestpagina gaat in zijn geheel naar boven zodra de selectie
  /// erin komt, en een link die zichzelf daarna nog naar zijn vaste plek trekt, schuift hem weer weg.
  final bool schuifInBeeld;

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
    if (!isTv || !widget.schuifInBeeld) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    // After the frame: the highlight often arrives during a build, and asking a scrollable to move
    // mid-layout throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Nog steeds de selectie? Een rij die je naar de onthouden hoes stuurt ([TvRij]), geeft de
      // selectie in dezelfde beurt door: de eerste landing mag de lijst dan niet meer verschuiven.
      if (!mounted || !_focused) return;
      if (widget.vastePlek) {
        tvVastePlek(context);
        return;
      }
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
      // 200 ms en zacht uitlopend, niet 130 ms (Saber, 18-10-2026: "te bruut"). Even lang als de lijst
      // erachter onderweg is naar de vaste plek ([tvVastePlek]), zodat groeien en schuiven samen landen.
      content = AnimatedScale(
        scale: _focused ? (widget.focusScale ?? tileFocusScale) : 1.0,
        duration: kTvFocusGroei,
        curve: Curves.easeOutCubic,
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
            // Op een tv GEEN rand en geen gloed, maar een zachte glazen pil (Saber, 16-10-2026: "te
            // veel witte schijn rond de knop, is lelijk" — en eerder "paars gekleurde tekst, geen
            // rand, glass look"). De letters worden paars waar ze zelf geen kleur zetten (zie
            // [_paarsBijSelectie]).
            color: isTv && _focused && widget.ringOnFocus ? kTvSelectieGlas : null,
            border: Border.all(
              // Transparent rather than absent, so the ring appearing does not change the widget's
              // size and shift everything around it by two pixels.
              color: _focused && widget.ringOnFocus && !isTv ? _ring : Colors.transparent,
              width: _ringWidth,
            ),
            boxShadow: !_focused
                ? null
                : widget.ringOnFocus
                    ? (isTv ? null : [BoxShadow(color: _ring.withValues(alpha: .45), blurRadius: 18, spreadRadius: 1)])
                    // Een hoes krijgt geen kader (zie [ringOnFocus]); op een tv tilt hij wél op: een
                    // schaduw eronder, zodat de groei leest als "naar je toe" en niet als een sprong.
                    : isTv && widget.scaleOnFocus
                        ? const [BoxShadow(color: Color(0x99000000), blurRadius: 26, offset: Offset(0, 10))]
                        : null,
          ),
          child: _paarsBijSelectie(content),
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

  /// Op een tv met de selectie: letters en pictogrammen paars, behalve waar ze zelf een kleur zetten.
  /// Alleen voor wat een rand zou krijgen ([Pressable.ringOnFocus]); een hoes houdt zijn kleuren.
  Widget _paarsBijSelectie(Widget kind) {
    if (!isTv || !_focused || !widget.ringOnFocus) return kind;
    return DefaultTextStyle.merge(
      style: TextStyle(color: kAccent),
      child: IconTheme.merge(data: IconThemeData(color: kAccent), child: kind),
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
      // **Het onderschrift telt niet mee voor de breedte.** Het stond als gewone regel in de kolom, en
      // dan werd de kolom zo breed als "10 seconden terug": op de Shield schoof bij elke stap door de
      // spelerbalk de hele rij knoppen opzij — de afspeelknop sprong 190 punten naar rechts
      // (16-10-2026). Nu ligt het ONDER de knop, gecentreerd, en mag het breder zijn dan de knop.
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.child,
              // De hoogte blijft gereserveerd, zichtbaar of niet: anders verspringt de rij in hoogte.
              SizedBox(height: (MediaQuery.textScalerOf(context).scale(16) * 1.1).ceilToDouble() + 2),
            ],
          ),
          // 16, not the 11 it started at: this label exists BECAUSE a tooltip cannot be read from a
          // couch, and 11 points on a 960-wide canvas cannot be read from a couch either. It would
          // have been the smallest text on the screen while being the only thing explaining what the
          // icon above it does.
          // En de hoogte in GESCHAALDE punten. Hier stond 20, en op de Shield staat de tekst op 1,35:
          // 16 × 1,35 × 1,1 is bijna 24 punten tekst in een vak van 20. Een Text met ellipsis knipt
          // dan af, precies onder de grondlijn -- "Wachtrij" werd "Wachtrii", en elk onderschrift met
          // een g, j, p of y verloor zijn staart. Gezien op 11-09-2026.
          if (_focused)
            Positioned(
              bottom: 0,
              child: SizedBox(
                height: (MediaQuery.textScalerOf(context).scale(16) * 1.1).ceilToDouble() + 2,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  // Paars, zoals de letters van elke geselecteerde knop op een tv (16-10-2026).
                  style: TextStyle(fontSize: 16, height: 1.1, color: kAccent),
                ),
              ),
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
///
/// **Op een tv wit, sinds 15-10-2026.** Saber, op de Shield: *"die paarse randen rond de selectie
/// zijn lelijk … ik weet nooit welke geselecteerde knoppen het zijn."* Nagekeken met schermafdrukken
/// via adb: de paarse rand viel weg op precies de knop die het meest gebruikt wordt ("Shuffle alles"
/// is zelf paars), en een geselecteerde nummerrij was een vierkante paarse balk over de volle breedte.
/// Wit is wat Google TV en Apple TV doen: het staat los van elke kleur in de app, ook van paars.
Color get kTvSelectie => isTv ? kFel : kAccent;
Color get _ring => kTvSelectie;

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

/// Hoe lang een hoes op een tv over het groeien doet. Zie [Pressable].
const kTvFocusGroei = Duration(milliseconds: 200);

/// Hoeveel een kaart over de volle breedte groeit met de selectie op een tv ("Zeg wat je wil
/// horen"). Een hoes groeit 14 %; een kaart van 860 punten zou dan 120 punten het scherm uit lopen.
const double kTvKaartGroei = 1.03;

/// De glazen pil onder wat op een tv de selectie heeft en niet groeit (een link, een chip, een
/// knop): wit op 14 %, geen rand, geen gloed. Op licht zwart op 8 %.
Color get kTvSelectieGlas => Thema.licht ? const Color(0x14000000) : const Color(0x24FFFFFF);

/// Een tekstlink: een naam onder "Ook in", "Toon alles", "Meer lezen".
///
/// Op een tv zonder vak en zonder paars: met de selectie worden de letters wit, met een witte lijn
/// eronder, net als een gekozen regel van "In mijn bibliotheek" (Saber, 16-10-2026: "witte tekst,
/// onderstreept"). Het grijze vak dat hij hiervoor kreeg stond soms scheef over de letters. Elders
/// verandert er niets: daar zegt de muis waar je bent.
///
/// [bouw] krijgt mee of de link nu de selectie heeft; [tvLinkStijl] maakt daar de letters bij.
class TekstLink extends StatefulWidget {
  const TekstLink({
    super.key,
    required this.onPressed,
    required this.bouw,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.schuifInBeeld = true,
  });

  final VoidCallback? onPressed;
  final Widget Function(bool gekozen) bouw;
  final BorderRadius borderRadius;

  /// Zie [Pressable.schuifInBeeld].
  final bool schuifInBeeld;

  @override
  State<TekstLink> createState() => _TekstLinkState();
}

class _TekstLinkState extends State<TekstLink> {
  bool _gekozen = false;

  @override
  Widget build(BuildContext context) => Pressable(
        onPressed: widget.onPressed,
        borderRadius: widget.borderRadius,
        // Op een tv is de lijn onder de letters de selectie; elders de ring, zoals altijd.
        ringOnFocus: !isTv,
        // Een tekstlink en geen tegel: uitvergroot duwt hij tegen zijn buurman en valt de rand scheef
        // over de letters. Gezien op de Shield, 11-09-2026.
        scaleOnFocus: false,
        schuifInBeeld: widget.schuifInBeeld,
        onFocusChange: (heeft) {
          if (isTv && heeft != _gekozen && mounted) setState(() => _gekozen = heeft);
        },
        child: widget.bouw(isTv && _gekozen),
      );
}

/// De letters van een [TekstLink]: gekozen wit met een witte lijn eronder, anders [basis].
TextStyle tvLinkStijl(TextStyle basis, bool gekozen) => gekozen
    ? basis.copyWith(
        color: kTekst,
        decoration: TextDecoration.underline,
        decorationColor: kTekst,
        decorationThickness: 2,
      )
    : basis;

/// Hoeveel ruimte er op een tv boven de selectie blijft in een lijst die omhoog en omlaag schuift:
/// genoeg voor de kop van een rij ("Recent toegevoegd") met wat lucht. Zie [tvVastePlek].
const double kTvBovenruimte = 56;

/// Waar een lijst heen moet om een element op de vaste plek te zetten.
///
/// [onthul] is de stand waarbij het element precies tegen de voorrand staat, [voorrand] hoeveel
/// ruimte ervoor moet blijven; [min] en [max] zijn de grenzen van de lijst. Zuiver, voor de toets.
///
/// **Blijf bovenaan als het maar een stukje is** ([bovenaanTot]). Zou de lijst voor de vaste plek
/// maar een klein eind van het begin af hoeven, dan blijft hij aan het begin: anders knipt die
/// verschuiving de kop van de pagina doormidden. Op Start stond "Goedemorgen" zo half onder de balk
/// zodra de selectie op "Zeg wat je wil horen" kwam — 64 punten verschoven, en de kop is 70 hoog
/// (Shield, 17-10-2026). De selectie staat aan het begin toch ruim in beeld.
///
/// **Maar niet onder de onderrand ([onthulEinde]).** Op Albums (Shield, 18-10-2026) stond de eerste
/// rij onder de paginatitel en de kop "#", en bleef hij dus bovenaan — met de artiestnamen onder de
/// spelerbalk. [onthulEinde] is de stand waarbij de onderkant van het element precies tegen de
/// onderrand staat, [eindmarge] wat hij daaronder nog nodig heeft (zijn groei met de selectie). Dan
/// schuift de lijst net zo ver als nodig, nooit verder dan de vaste plek, en blijft de kop zoveel
/// mogelijk staan.
double vastePlekDoel({
  required double onthul,
  required double voorrand,
  required double min,
  required double max,
  double bovenaanTot = 0,
  double? onthulEinde,
  double eindmarge = 0,
}) {
  final naar = (onthul - voorrand).clamp(min, max).toDouble();
  if (naar - min > bovenaanTot) return naar;
  if (onthulEinde == null) return min;
  return (onthulEinde + eindmarge).clamp(min, naar).toDouble();
}

/// Hoe ver een staande lijst hoogstens van zijn begin af hoeft voor de vaste plek, en dan toch aan
/// het begin blijft — zie [vastePlekDoel]. Anderhalve [kTvBovenruimte]: de kop van Start (begroeting
/// en onderregel) en de kop van Tracks (titel, telling, knoppen) vallen erbinnen, de derde rij van een
/// lijst niet meer — die schuift gewoon naar zijn vaste plek.
const double kTvBovenaanTot = kTvBovenruimte * 1.5;

/// Brengt wat de selectie heeft naar zijn vaste plek, in elke lijst eromheen.
///
/// **Waarom (Saber, 16-10-2026).** Hij koos "selectie op een vaste plek", zoals Netflix en Apple TV:
/// de rij waar je op staat blijft bovenaan in beeld en de pagina schuift eronder door, en in een rij
/// blijft de gekozen hoes links staan terwijl de andere schuiven. Het was het midden
/// (`ensureVisible` met 0,5): dan dwaalde de selectie over het scherm, en op Tracks viel de vierde
/// rij half onder de spelerbalk.
///
/// In een liggende lijst komt het element waar de eerste staat als de lijst in rust is (de
/// binnenmarge van de lijst); in een staande lijst [kTvBovenruimte] onder de bovenrand, zodat de kop
/// van de rij erboven nog leesbaar is. Een lijst die niet verder kan, blijft staan.
void tvVastePlek(BuildContext context, {Duration duur = const Duration(milliseconds: 220)}) {
  RenderObject? doel = context.findRenderObject();
  var lijst = Scrollable.maybeOf(context);
  while (lijst != null && doel != null && doel.attached) {
    final pos = lijst.position;
    final viewport = RenderAbstractViewport.maybeOf(doel);
    // De balk telt alleen voor de buitenste lijst, de pagina zelf. Een lijst ín de pagina (de albums
    // van "In mijn bibliotheek" op een tv) schuift tegelijk met de pagina, en waar die nu staat zegt
    // niets over waar hij zo meteen staat.
    final pagina = Scrollable.maybeOf(lijst.context) == null;
    if (viewport != null && pos.hasContentDimensions) {
      final liggend = pos.axis == Axis.horizontal;
      final naar = vastePlekDoel(
        onthul: viewport.getOffsetToReveal(doel, 0).offset,
        onthulEinde: liggend ? null : viewport.getOffsetToReveal(doel, 1).offset,
        eindmarge: liggend ? 0 : _groeiOnder(doel),
        voorrand: liggend
            ? _binnenmarge(viewport)
            : kTvBovenruimte + (pagina ? _onderDeBalk(context, viewport) : 0),
        min: pos.minScrollExtent,
        max: pos.maxScrollExtent,
        bovenaanTot: liggend ? 0 : kTvBovenaanTot,
      );
      if ((naar - pos.pixels).abs() > .5) pos.animateTo(naar, duration: duur, curve: Curves.easeOutCubic);
    }
    doel = lijst.context.findRenderObject();
    lijst = Scrollable.maybeOf(lijst.context);
  }
}

/// Het focusverzoek van een pijlstap op een tv: de selectie verhuist, en de lijst schuift ZACHT mee.
///
/// **Waarom (Saber, 18-10-2026: "bij het navigeren van links naar rechts springen de hoezen, is te
/// bruut").** Flutter schuift bij elke pijl eerst zelf: `ensureVisible` met duur nul, in één beeld.
/// Daarna schoof [Pressable] de lijst naar de vaste plek, in 220 ms. Op de Shield gefilmd (b12000):
/// een rij hoezen stond net te hoog voor het beeld, dus elke pijl naar rechts sprong de pagina 35
/// punten omhoog en gleed hij daarna terug. Een sprong en een terugweg voor een stap die niets hoefde.
///
/// Hier dus geen sprong. Een [Pressable] die zelf schuift ([Pressable.schuifInBeeld]) regelt het
/// helemaal; voor al het andere (een InkWell, een veld) schuift dezelfde `ensureVisible` als die van
/// Flutter, maar in 220 ms. Na het beeld: de selectie wordt pas in een microtaak doorgegeven, en pas
/// dan weet een [Pressable] dat hij hem heeft.
void tvFocusZonderSprong(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
  final ctx = node.context;
  if (ctx == null) return;
  // Een beeld vragen: zonder zichtbare verandering komt er geen, en dan schoof de lijst nooit.
  WidgetsBinding.instance.ensureVisualUpdate();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!ctx.mounted || !node.hasPrimaryFocus) return;
    if (schuiftZelf(ctx)) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: alignment ?? 1,
      alignmentPolicy: alignmentPolicy ?? ScrollPositionAlignmentPolicy.explicit,
      duration: duration ?? const Duration(milliseconds: 220),
      curve: curve ?? Curves.easeOutCubic,
    );
  });
}

/// Brengt de [Pressable] rond [ctx] zichzelf in beeld? Alleen als HIJ de selectie heeft: een knop
/// ín een tegel die zelf niet geselecteerd is, schuift niets.
@visibleForTesting
bool schuiftZelf(BuildContext ctx) {
  final p = ctx.findAncestorStateOfType<_PressableState>();
  return p != null && p._focused && p.widget.schuifInBeeld;
}

/// Hoeveel een element met de selectie onder zijn eigen onderkant uitgroeit: de helft van wat
/// [tileFocusScale] erbij doet (hij groeit om het midden), plus wat lucht voor de schaduw.
double _groeiOnder(RenderObject doel) =>
    doel is RenderBox && doel.hasSize ? doel.size.height * (tileFocusScale - 1) / 2 + 8 : 0;

/// [tvVastePlek] voor iets dat geen [Pressable] is (een InkWell, een rij met een eigen achtergrond):
/// `onFocusChange: tvVolgFocus(context)`, met de context van het element zelf of van een Builder er
/// net boven. Alleen op een tv, en na het beeld alleen als de selectie er nog binnen staat.
ValueChanged<bool> tvVolgFocus(BuildContext context) => (heeft) {
      if (!isTv || !heeft) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final hier = FocusManager.instance.primaryFocus?.context;
        if (hier == null) return;
        var binnen = identical(hier, context);
        if (!binnen) {
          hier.visitAncestorElements((e) {
            if (identical(e, context)) binnen = true;
            return !binnen;
          });
        }
        if (binnen) tvVastePlek(context);
      });
    };

/// Na hoe lang ingedrukt houden een pijl gaat spoelen in plaats van een nummer verder te gaan.
const kSpoelNa = Duration(milliseconds: 350);

/// Hoe vaak er gespoeld wordt zolang je hem vasthoudt. Een afstandsbediening herhaalt een toets
/// twintig keer per seconde; zoveel sprongen naar de pc zou de stroom laten haperen.
const kSpoelTussen = Duration(milliseconds: 250);

/// Na hoeveel sprongen spoelen uit zichzelf ophoudt (30 seconden vasthouden).
const kSpoelHoogstens = 120;

/// Hoeveel seconden één sprong is, na zo lang vasthouden: eerst fijn, dan steeds sneller.
int spoelStap(Duration ingedrukt) => ingedrukt < const Duration(seconds: 2)
    ? 5
    : ingedrukt < const Duration(seconds: 5)
        ? 10
        : 20;

/// Links en rechts op de hoes van Nu speelt op een tv: even tikken = vorige of volgende, ingedrukt
/// houden = spoelen (Saber, 16-10-2026: "die vooruit en achteruitspoelen knoppen mogen weg, is te
/// druk, ik wil dit doen met de afstandsbediening door blijven drukken").
///
/// Het nummer wisselt daarom bij het LOSLATEN en niet meer bij het neerdrukken: pas dan weet je dat
/// het geen vasthouden was.
///
/// **Op een eigen klok, niet op de herhaling van de toets.** Eerst spoelde hij bij elke herhaling die
/// de afstandsbediening stuurt. Een ingedrukte toets via adb stuurt alleen neer en los, zonder
/// herhalingen, en dan sprong hij op de Shield naar het volgende nummer in plaats van te spoelen. Nu
/// loopt er een klok zolang de toets neer is; herhalingen tellen niet. Na [kSpoelHoogstens] sprongen
/// houdt hij uit zichzelf op, voor het geval het loslaten nooit aankomt.
class SpoelPijlen {
  SpoelPijlen({required this.vorige, required this.volgende, required this.spoel});

  final VoidCallback vorige, volgende;

  /// Spoel zoveel seconden (negatief = terug).
  final void Function(int seconden) spoel;

  LogicalKeyboardKey? _neer;
  Timer? _wacht, _herhaal;
  int _sprongen = 0;

  KeyEventResult opToets(KeyEvent e) {
    final k = e.logicalKey;
    if (k != LogicalKeyboardKey.arrowLeft && k != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    final vooruit = k == LogicalKeyboardKey.arrowRight;
    if (e is KeyDownEvent) {
      vergeet();
      _neer = k;
      _wacht = Timer(kSpoelNa, () {
        _spring(vooruit);
        _herhaal = Timer.periodic(kSpoelTussen, (_) => _spring(vooruit));
      });
      return KeyEventResult.handled;
    }
    if (_neer != k) return KeyEventResult.ignored;
    if (e is KeyRepeatEvent) return KeyEventResult.handled;
    if (e is KeyUpEvent) {
      final gespoeld = _sprongen > 0;
      vergeet();
      if (!gespoeld) (vooruit ? volgende : vorige)();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _spring(bool vooruit) {
    if (_sprongen >= kSpoelHoogstens) return vergeet();
    final ingedrukt = kSpoelNa + kSpoelTussen * _sprongen;
    _sprongen++;
    final stap = spoelStap(ingedrukt);
    spoel(vooruit ? stap : -stap);
  }

  /// Een toets die nog neer was, telt niet meer (de selectie ging van de hoes af, of het scherm sluit).
  void vergeet() {
    _wacht?.cancel();
    _herhaal?.cancel();
    _wacht = _herhaal = null;
    _neer = null;
    _sprongen = 0;
  }
}

/// Eén stap met een pijl, maar alleen naar iets dat werkelijk een plek op de pagina heeft.
///
/// **Waarom niet gewoon `focusInDirection`.** Gemeten op de Shield (17-10-2026, meetversie b11975):
/// alles in een sliver die verder dan het voorraadstuk onder (of boven) het beeld ligt, wordt niet
/// opgemaakt — maar een `SliverToBoxAdapter` bouwt zijn kind wél, en die knop bestaat dus, met als
/// plek de ONDERRAND van het beeld. Op de artiestpagina stonden zo "Toon alle 29", de albums en heel
/// "Klinkt als" op y = 436, vlak onder Radio; de eerste plaat van "In mijn bibliotheek" echt op 444.
/// Op het midden gemeten lag "Toon alle 29" vijf punten dichterbij, en omlaag sprong daarheen.
///
/// Zulke knoppen tellen voor deze ene stap niet mee (even `skipTraversal`, daarna meteen terug). Wie
/// echt dichtbij ligt, staat binnen het voorraadstuk en heeft zijn ware plek; verder dan dat ga je
/// met een pijl nooit in één stap.
bool tvPijlStap(FocusNode hier, TraversalDirection richting) {
  final weg = <FocusNode>[
    for (final n in hier.nearestScope?.traversalDescendants ?? const <FocusNode>[])
      if (!identical(n, hier) && nietOpgemaakt(n)) n,
  ];
  for (final n in weg) {
    n.skipTraversal = true;
  }
  try {
    return hier.focusInDirection(richting);
  } finally {
    for (final n in weg) {
      n.skipTraversal = false;
    }
  }
}

/// Staat [n] in een sliver die in deze opmaak niet aan de beurt kwam (buiten beeld én buiten het
/// voorraadstuk)? Dan is zijn plek op het scherm verzonnen: zie [tvPijlStap].
@visibleForTesting
bool nietOpgemaakt(FocusNode n) {
  RenderObject? r = n.context?.findRenderObject();
  while (r != null) {
    if (r is RenderSliver) {
      final g = r.geometry;
      if (g == null || (g.cacheExtent <= 0 && g.paintExtent <= 0)) return true;
    }
    r = r.parent;
  }
  return false;
}

/// Hoeveel ruimte er in de staande lijst rond [context] boven de selectie blijft: [kTvBovenruimte],
/// plus wat er van die lijst achter de zwevende balk ligt. Voor wie zelf zijn lijst laat schuiven, zoals
/// "In mijn bibliotheek" op de artiestpagina.
double tvBovenruimteIn(BuildContext context) {
  final ro = context.findRenderObject();
  final vp = ro == null ? null : RenderAbstractViewport.maybeOf(ro);
  return kTvBovenruimte + (vp == null ? 0 : _onderDeBalk(context, vp));
}

/// Hoeveel van een staande lijst achter de zwevende balk ligt.
///
/// Op een pagina die onder de balk door tekent (de artiestpagina, sinds de balk ook op een tv zweeft)
/// begint de lijst bovenaan het venster. Zonder dit kwam de vaste plek van de selectie 56 punten onder
/// de bovenrand — achter de capsule. Elke andere pagina begint al onder de balk, en daar is dit nul.
double _onderDeBalk(BuildContext context, RenderAbstractViewport viewport) {
  final ruimte = BalkRuimte.van(context);
  if (ruimte <= 0 || viewport is! RenderBox) return 0;
  final vak = viewport as RenderBox;
  if (!vak.hasSize) return 0;
  final boven = vak.localToGlobal(Offset.zero).dy;
  return boven >= ruimte ? 0 : ruimte - boven;
}

/// De marge aan het begin van een lijst (`ListView(padding: …)` wordt een [RenderSliverPadding]).
double _binnenmarge(RenderAbstractViewport viewport) {
  if (viewport is RenderViewportBase) {
    final eerste = viewport.firstChild;
    if (eerste is RenderSliverPadding) {
      final p = eerste.resolvedPadding;
      if (p != null) return viewport.axis == Axis.horizontal ? p.left : p.top;
    }
  }
  return 0;
}

/// De kleur van een pictogramknop met een eigen vaste kleur, die op een tv paars wordt als hij de
/// selectie heeft (Saber, 16-10-2026: "paars gekleurde tekst, geen rand, glass look").
///
/// Nodig omdat `IconButton(color: …)` een vaste kleur is voor élke stand: de themaregel die een
/// geselecteerde knop paars maakt, komt daar nooit doorheen. Een `style` gaat wél boven `color`.
ButtonStyle tvIcoonStijl(Color kleur) => ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled)
          ? null
          : (isTv && s.contains(WidgetState.focused) ? kAccent : kleur)),
    );

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
