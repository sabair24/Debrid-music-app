/// Het zwevende menu van pc, Mac en iPad: één capsule van vloeibaar glas met een pil die je kunt
/// slepen (Saber, 17-10-2026).
///
/// **Waarom het er zo uitziet.** Op de pc stond de navigatie als capsule in een balk, met links het
/// woordmerk en de telling en rechts het tandwiel, en elke pagina legde bij scrollen een strook
/// matglas over de volle breedte achter die balk: *"die staat op pc niet los zie je? er is een soort
/// van doorlopende balk dit wil ik niet"*. Hij wou het menu van de Shield: één capsule die los over de
/// pagina zweeft, met een pil die van woord naar woord schuift. Zijn keuzes:
///
/// - **Alles in de capsule:** Zoeken, de elf secties en Instellingen. Geen woordmerk, geen telling;
///   die laatste komt alleen bij nieuws, klein eronder.
/// - **Geen strook bij scrollen:** de pagina schuift er gewoon onderdoor.
/// - **Vloeibaar glas**, de pil helder glas zonder kleur, en **alleen de tekst paars** ([MenuTint]).
///   Eerst koos hij de kleur van de hoes voor de pil; bij het eerste voorbeeld werd het "doe enkel
///   de tekst paars".
/// - **Slepen:** de pil volgt de muis (op een iPad de vinger) en wordt een **lens die iets opzwelt**
///   en vergroot wat eronder ligt, zoals de tabbalk van iOS 26. Bij loslaten veert hij naar het
///   dichtstbijzijnde woord, en dán pas opent die sectie. Klikken werkt zoals altijd.
/// - **Muiswiel** boven de capsule: de pil schuift één sectie per tik, en na een halve tel stil opent
///   die. Past niet alles, dan schuift het wiel de capsule zelf opzij.
/// - **Krimpen** bij omlaag scrollen tot alleen de sectie waar je bent, met een los vergrootglas;
///   omhoog scrollen, de muis erop of een klik klapt hem weer open.
/// - **Zoeken** klapt de capsule open tot een zoekveld ([ZwevendMenu.zoekbalk]).
///
/// De tv heeft zijn eigen balk (`TvTopBar` in main.dart, met de afstandsbediening als enige
/// bediening), maar dezelfde onderdelen: [MenuGlas], [menuPilVorm], [MenuTint] en [MenuWoord].
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tv.dart';
import 'glas.dart';
import 'kleuren.dart';
import 'menu_iconen.dart';

/// Eén plek in het menu.
@immutable
class MenuPunt {
  const MenuPunt({
    required this.sleutel,
    required this.label,
    required this.icoon,
    this.sectie,
    this.badge = 0,
    this.bezig = false,
  });

  /// `zoeken`, `instellingen`, of `sectie-<id>`.
  final String sleutel;
  final String label;
  final MenuIcoonSoort icoon;

  /// Het `_view`-nummer, of null voor Zoeken en Instellingen.
  final int? sectie;

  /// Het getal naast het woord (Mijn downloads: wat er nu binnenkomt).
  final int badge;

  /// Het icoon blijft bewegen (de pijl van Mijn downloads valt zolang er iets binnenkomt).
  final bool bezig;

  static String voorSectie(int id) => 'sectie-$id';
}

/// De kleuren van de pil en van wat eronder staat.
///
/// **Alleen de tekst paars** (Saber, 17-10-2026, bij het eerste voorbeeld: "doe enkel de tekst paars").
/// De pil zelf is helder glas zonder kleur en zonder gekleurde gloed; het woord en het icoon eronder
/// zijn lichtpaars, met een zachte paarse gloed achter de letters.
@immutable
class MenuTint {
  const MenuTint._({required this.tekst, required this.gloed, required this.boven, required this.onder});

  /// Het woord en het icoon onder de pil.
  final Color tekst;

  /// De zachte gloed achter de letters onder de pil.
  final Color gloed;

  /// Het glas van de pil, boven en onder: wit, geen kleur.
  final Color boven, onder;

  /// De enige: lichtpaars op helder glas.
  static const paars = MenuTint._(
    tekst: Color(0xFFB3A2FF),
    gloed: Color(0x737C5CFF),
    boven: Color(0x3DFFFFFF),
    onder: Color(0x14FFFFFF),
  );
}

/// Het glas van de pil: helder, zonder kleur. [lens]: terwijl je sleept — helderder rand en een
/// schaduw eronder, zodat hij boven de capsule zweeft.
BoxDecoration menuPilVorm(MenuTint t, {bool lens = false}) => BoxDecoration(
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .12, 1],
        colors: [
          Color.lerp(t.boven, const Color(0xFFFFFFFF), lens ? .25 : .10)!,
          t.boven,
          t.onder,
        ],
      ),
      border: Border.all(color: Color.fromRGBO(255, 255, 255, lens ? .50 : .22), width: lens ? 1.3 : 1),
      boxShadow: [
        if (lens) const BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 6)),
      ],
    );

/// De capsule zelf: vloeibaar glas, donker, met een schaduw die hem van de pagina tilt.
///
/// Op een tv met [tv] het glas van de balk ([GlasKwaliteit.tvBalk]) — Saber koos glas ook daar.
class MenuGlas extends StatelessWidget {
  const MenuGlas({super.key, required this.child, this.vorm = const BorderRadius.all(Radius.circular(999))});

  final Widget child;
  final BorderRadius vorm;

  /// De kleur onder het glas.
  static const kleur = Color(0xFF12121A);

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: vorm,
          boxShadow: const [
            BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 8), blurStyle: BlurStyle.outer),
          ],
        ),
        child: GlasVlak(vorm: vorm, kleur: kleur, lens: true, balk: true, child: child),
      );
}

/// De maten van het menu op dit toestel.
@immutable
class MenuMaten {
  const MenuMaten({required this.hoogte, required this.lettergrootte, required this.icoon, required this.opzij});

  /// Hoe hoog de pil is: 34 onder een muis, 44 onder een vinger (de kleinste maat die Apple een vinger
  /// toevertrouwt).
  final double hoogte;
  final double lettergrootte;
  final double icoon;

  /// Ruimte links en rechts van icoon en woord, binnen de pil.
  final double opzij;

  static const muis = MenuMaten(hoogte: 34, lettergrootte: 13, icoon: 17, opzij: 11);
  static const vinger = MenuMaten(hoogte: 44, lettergrootte: 14, icoon: 19, opzij: 13);

  /// De rand van de capsule rond de pil.
  static const rand = 4.0;
}

/// Icoon en woord, zoals ze in de capsule staan. Ook de tv gebruikt dit.
class MenuWoord extends StatelessWidget {
  const MenuWoord({
    super.key,
    required this.punt,
    required this.tint,
    required this.maten,
    this.onderPil = false,
    this.aangewezen = false,
    this.statisch = false,
  });

  final MenuPunt punt;
  final MenuTint tint;
  final MenuMaten maten;
  final bool onderPil, aangewezen;

  /// Zonder beweging, voor de vergrote kopie onder de lens: die hoeft niets te spelen.
  final bool statisch;

  @override
  Widget build(BuildContext context) {
    final kleur = onderPil
        ? tint.tekst
        : aangewezen
            ? const Color(0xFFFFFFFF)
            : kGedempt;
    // Het icoon groeit mee met de letters: op een tv zijn die 1,35 keer zo groot, en zonder dit stond
    // er een klein icoontje naast een groot woord (voorbeeld van 17-10-2026).
    final maat = MediaQuery.textScalerOf(context).scale(maten.icoon);
    final icoon = statisch
        ? SizedBox.square(
            dimension: maat,
            child: CustomPaint(painter: MenuIcoonSchilder(soort: punt.icoon, kleur: kleur, vul: onderPil ? 1 : 0)),
          )
        : MenuIcoon(
            soort: punt.icoon,
            kleur: kleur,
            gekozen: onderPil,
            aangewezen: aangewezen,
            bezig: punt.bezig,
            maat: maat,
          );
    final stijl = DefaultTextStyle.of(context).style.merge(TextStyle(
          fontSize: maten.lettergrootte,
          fontWeight: FontWeight.w600,
          height: 1.2,
          leadingDistribution: TextLeadingDistribution.even,
          color: kleur,
          shadows: onderPil ? [Shadow(color: tint.gloed, blurRadius: 12)] : const [],
        ));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: maten.opzij),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icoon,
          SizedBox(width: maat * .38),
          statisch
              ? Text(punt.label, style: stijl, maxLines: 1)
              : AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: stijl,
                  child: Text(punt.label, maxLines: 1),
                ),
          if (punt.badge > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(9)),
              child: Text('${punt.badge}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFFFFFFF))),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hoe ver de pil voorbij zijn doel schiet en terugveert, en hoe lang hij erover doet: dezelfde veer
/// als op de Shield (Debrid Media: 0,32 s, cubic-bezier(.34, 1.2, .4, 1)).
const kMenuSchuif = Duration(milliseconds: 320);
const kMenuVeer = Cubic(.34, 1.2, .4, 1);

/// Hoe lang de pil na een tik van het muiswiel stil moet staan voor die sectie opent.
const kMenuWielWacht = Duration(milliseconds: 500);

/// Hoeveel de lens opzwelt terwijl je sleept, en hoeveel hij vergroot wat eronder ligt.
const kMenuLensZwel = 1.14;
const kMenuLensVergroot = 1.12;

/// Klapt het menu in bij deze scrolstap? [positie] is hoe ver de pagina gescrold staat, [stap] hoeveel
/// er deze keer bij kwam (positief = omlaag), [nu] of hij al ingeklapt is.
///
/// Bovenaan de pagina altijd open; een stap van een paar punten de andere kant op verandert niets,
/// zodat een trillend touchpad hem niet open en dicht laat flikkeren.
bool menuInklappen({required bool nu, required double positie, required double stap}) {
  if (positie <= kMenuInklapVanaf) return false;
  if (stap > 4) return true;
  if (stap < -4) return false;
  return nu;
}

/// Vanaf hoe ver gescrold het menu mag inklappen.
const kMenuInklapVanaf = 80.0;

/// Het menu voor muis en vinger.
class ZwevendMenu extends StatefulWidget {
  const ZwevendMenu({
    super.key,
    required this.punten,
    required this.actief,
    required this.onKies,
    this.tint = MenuTint.paars,
    this.maten = MenuMaten.muis,
    this.gekrompen = false,
    this.onUitklappen,
    this.zoekbalk,
    this.wielWacht = kMenuWielWacht,
  });

  final List<MenuPunt> punten;

  /// De sleutel van de sectie waar je bent: daar staat de pil in rust.
  final String actief;

  /// Er is gekozen: met een klik, na het slepen, of na het wiel.
  final ValueChanged<MenuPunt> onKies;

  final MenuTint tint;
  final MenuMaten maten;

  /// Ingeklapt tot de sectie waar je bent, plus een los vergrootglas.
  final bool gekrompen;

  /// Muis op de ingeklapte capsule, of een klik erop.
  final VoidCallback? onUitklappen;

  /// Staat er een zoekveld, dan staat dat in de capsule in plaats van de woorden.
  final Widget? zoekbalk;

  /// Zie [kMenuWielWacht]; korter in een toets.
  final Duration wielWacht;

  @override
  State<ZwevendMenu> createState() => ZwevendMenuState();
}

@visibleForTesting
class ZwevendMenuState extends State<ZwevendMenu> with SingleTickerProviderStateMixin {
  final _rol = ScrollController();
  final _rij = GlobalKey();
  final _sleutels = <String, GlobalKey>{};

  /// Waar elk woord staat, binnen de rij. Na elk beeld nagemeten ([_meet]).
  final Map<String, Rect> _vakken = {};

  /// Waar de pil heen gaat of staat (een sleutel), los van [ZwevendMenu.actief]: na een klik of het
  /// wiel staat hij er al voor de sectie gewisseld is.
  String? _doel;

  /// De beweging van de pil tussen twee plekken.
  late final AnimationController _schuif = AnimationController(vsync: this, duration: kMenuSchuif)
    ..addListener(() => setState(() {}));
  Rect? _van, _naar;

  /// Tijdens het slepen: waar de muis staat, in de rij. Null = niet aan het slepen.
  double? _sleep;

  /// Begon het slepen op de pil (de pil gaat mee), of ernaast (de capsule schuift).
  bool _sleeptPil = false;

  /// Wat de muis aanwijst.
  String? _aangewezen;

  /// Met de toetsenbordfocus.
  String? _gefocust;

  Timer? _wiel;
  MenuPunt? _naSchuif;

  @override
  void initState() {
    super.initState();
    _doel = widget.actief;
    _schuif.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      final p = _naSchuif;
      _naSchuif = null;
      if (p != null && mounted) widget.onKies(p);
    });
  }

  @override
  void didUpdateWidget(ZwevendMenu oud) {
    super.didUpdateWidget(oud);
    if (widget.actief != oud.actief && widget.actief != _doel && _sleep == null && _naSchuif == null && _wiel == null) {
      _schuifNaar(widget.actief);
    }
    // Verdwijnen de woorden (zoekveld, ingeklapt), dan komt er geen onExit: het woord onder de muis
    // bleef daarna wit staan alsof je het aanwees (op de proef gezien, 17-10-2026).
    if ((widget.zoekbalk != null) != (oud.zoekbalk != null) || widget.gekrompen != oud.gekrompen) {
      _aangewezen = null;
      _gefocust = null;
    }
  }

  @override
  void dispose() {
    _wiel?.cancel();
    _schuif.dispose();
    _rol.dispose();
    super.dispose();
  }

  List<MenuPunt> get _secties => [for (final p in widget.punten) if (p.sectie != null) p];

  /// De pil zoals hij nu getekend wordt, binnen de rij.
  Rect? get pilVak {
    final sleep = _sleep;
    if (sleep != null && _sleeptPil) return _sleepVak(sleep);
    final naar = _naar ?? _vakken[_doel];
    if (naar == null) return null;
    final van = _van;
    if (van == null || !_schuif.isAnimating) return naar;
    return Rect.lerp(van, naar, kMenuVeer.transform(_schuif.value));
  }

  /// De pil onder de muis: zijn midden volgt de muis tussen het eerste en het laatste woord, zijn
  /// breedte loopt mee van het ene woord naar het volgende.
  Rect? _sleepVak(double x) {
    final vakken = [for (final p in _secties) _vakken[p.sleutel]].whereType<Rect>().toList();
    if (vakken.isEmpty) return null;
    final midden = x.clamp(vakken.first.center.dx, vakken.last.center.dx).toDouble();
    var i = 0;
    while (i < vakken.length - 1 && vakken[i + 1].center.dx < midden) {
      i++;
    }
    final a = vakken[i];
    final b = vakken[math.min(i + 1, vakken.length - 1)];
    final deel = b.center.dx == a.center.dx ? 0.0 : (midden - a.center.dx) / (b.center.dx - a.center.dx);
    final breedte = a.width + (b.width - a.width) * deel;
    return Rect.fromCenter(center: Offset(midden, a.center.dy), width: breedte, height: a.height);
  }

  /// Het woord het dichtst bij [x] (alleen secties).
  MenuPunt? _dichtstBij(double x) {
    MenuPunt? beste;
    var afstand = double.infinity;
    for (final p in _secties) {
      final v = _vakken[p.sleutel];
      if (v == null) continue;
      final d = (v.center.dx - x).abs();
      if (d < afstand) {
        afstand = d;
        beste = p;
      }
    }
    return beste;
  }

  void _schuifNaar(String sleutel, {Rect? vanaf}) {
    final naar = _vakken[sleutel];
    final van = vanaf ?? pilVak;
    _doel = sleutel;
    if (naar == null || van == null) {
      _van = null;
      _naar = null;
      setState(() {});
      return;
    }
    _van = van;
    _naar = naar;
    _schuif.forward(from: 0);
  }

  void _meet() {
    if (!mounted) return;
    final rij = _rij.currentContext?.findRenderObject();
    if (rij is! RenderBox || !rij.attached || !rij.hasSize) return;
    var anders = false;
    for (final p in widget.punten) {
      final doos = _sleutels[p.sleutel]?.currentContext?.findRenderObject();
      if (doos is! RenderBox || !doos.attached || !doos.hasSize) continue;
      final v = doos.localToGlobal(Offset.zero, ancestor: rij) & doos.size;
      if (_vakken[p.sleutel] != v) {
        _vakken[p.sleutel] = v;
        anders = true;
      }
    }
    if (anders) {
      // Een woord dat van breedte veranderde (het getal bij Mijn downloads): de pil gaat mee, zonder
      // beweging.
      if (!_schuif.isAnimating) _naar = _vakken[_doel];
      setState(() {});
    }
  }

  // ── Bediening ─────────────────────────────────────────────────────────────────────────────────

  void _klik(MenuPunt p) {
    _wiel?.cancel();
    _wiel = null;
    if (p.sectie != null) _schuifNaar(p.sleutel);
    widget.onKies(p);
  }

  Offset? _inRij(Offset globaal) {
    final rij = _rij.currentContext?.findRenderObject();
    if (rij is! RenderBox || !rij.attached) return null;
    return rij.globalToLocal(globaal);
  }

  void _sleepBegin(DragStartDetails d) {
    final plek = _inRij(d.globalPosition);
    if (plek == null) return;
    final pil = pilVak;
    final kanSchuiven = _rol.hasClients && _rol.position.maxScrollExtent > 0;
    _sleeptPil = !kanSchuiven || (pil != null && pil.inflate(6).contains(plek));
    _wiel?.cancel();
    _wiel = null;
    _schuif.stop();
    setState(() => _sleep = plek.dx);
  }

  void _sleepVerder(DragUpdateDetails d) {
    if (_sleep == null) return;
    if (!_sleeptPil) {
      if (_rol.hasClients) {
        final p = _rol.position;
        _rol.jumpTo((p.pixels - d.delta.dx).clamp(p.minScrollExtent, p.maxScrollExtent).toDouble());
      }
      return;
    }
    final plek = _inRij(d.globalPosition);
    if (plek == null) return;
    // Bij de rand van een capsule die niet helemaal past: meeschuiven.
    if (_rol.hasClients && _rol.position.maxScrollExtent > 0) {
      final p = _rol.position;
      final inBeeld = plek.dx - p.pixels;
      final stap = inBeeld < 40
          ? -8.0
          : inBeeld > p.viewportDimension - 40
              ? 8.0
              : 0.0;
      if (stap != 0) _rol.jumpTo((p.pixels + stap).clamp(p.minScrollExtent, p.maxScrollExtent).toDouble());
    }
    setState(() => _sleep = plek.dx);
  }

  void _sleepEinde([DragEndDetails? _]) {
    final x = _sleep;
    if (x == null) return;
    final pil = _sleeptPil ? _sleepVak(x) : null;
    final doel = _sleeptPil ? _dichtstBij(pil?.center.dx ?? x) : null;
    setState(() {
      _sleep = null;
      _sleeptPil = false;
    });
    if (doel == null) return;
    _naSchuif = doel.sleutel == widget.actief ? null : doel;
    _schuifNaar(doel.sleutel, vanaf: pil);
  }

  /// Een tik van het muiswiel boven de capsule.
  void _opWiel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final dy = e.scrollDelta.dy != 0 ? e.scrollDelta.dy : e.scrollDelta.dx;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      final kanSchuiven = _rol.hasClients && _rol.position.maxScrollExtent > 0;
      if (kanSchuiven) {
        final p = _rol.position;
        _rol.jumpTo((p.pixels + dy).clamp(p.minScrollExtent, p.maxScrollExtent).toDouble());
        return;
      }
      final secties = _secties;
      final nu = secties.indexWhere((p) => p.sleutel == _doel);
      final volgende = (nu < 0 ? 0 : nu + (dy > 0 ? 1 : -1)).clamp(0, secties.length - 1);
      if (volgende == nu) return;
      final p = secties[volgende];
      _schuifNaar(p.sleutel);
      _wiel?.cancel();
      _wiel = Timer(widget.wielWacht, () {
        _wiel = null;
        if (mounted && p.sleutel != widget.actief) widget.onKies(p);
      });
    });
  }

  // ── Tekenen ───────────────────────────────────────────────────────────────────────────────────

  /// Welk woord nu onder de pil staat: tijdens het slepen het dichtstbijzijnde.
  String? get _onderPil {
    final x = _sleep;
    if (x != null && _sleeptPil) return _dichtstBij(_sleepVak(x)?.center.dx ?? x)?.sleutel;
    return _doel;
  }

  Widget _woord(MenuPunt p) {
    final sleutel = _sleutels.putIfAbsent(p.sleutel, () => GlobalKey(debugLabel: p.sleutel));
    final onder = _onderPil == p.sleutel;
    return MouseRegion(
      key: sleutel,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _aangewezen = p.sleutel),
      onExit: (_) => setState(() => _aangewezen = _aangewezen == p.sleutel ? null : _aangewezen),
      child: FocusableActionDetector(
        onShowFocusHighlight: (heeft) =>
            setState(() => _gefocust = heeft ? p.sleutel : (_gefocust == p.sleutel ? null : _gefocust)),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _klik(p);
            return null;
          }),
        },
        child: Semantics(
          button: true,
          selected: p.sleutel == widget.actief,
          label: p.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _klik(p),
            child: SizedBox(
              height: widget.maten.hoogte,
              child: Center(
                widthFactor: 1,
                child: MenuWoord(
                  punt: p,
                  tint: widget.tint,
                  maten: widget.maten,
                  onderPil: onder,
                  aangewezen: !onder && (_aangewezen == p.sleutel || _gefocust == p.sleutel),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// De vergrote kopie van de rij onder de lens.
  Widget _lensInhoud(Rect pil) {
    final onder = _onderPil;
    // Een dichte bodem onder de vergrote kopie: anders schemert het gewone woord erdoorheen en staat
    // het er twee keer, in twee maten.
    final glas = menuPilVorm(widget.tint, lens: true);
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: MenuGlas.kleur),
          DecoratedBox(decoration: BoxDecoration(gradient: glas.gradient)),
          OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          // Vergroot om het midden van de pil, en dan naar de hoek van de lens: een punt p van de rij
          // komt op s·(p − c) + c − hoek.
          child: Transform(
            transform: Matrix4.diagonal3Values(kMenuLensVergroot, kMenuLensVergroot, 1)
              ..setTranslationRaw(
                pil.center.dx * (1 - kMenuLensVergroot) - pil.left,
                pil.center.dy * (1 - kMenuLensVergroot) - pil.top,
                0,
              ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in widget.punten)
                  SizedBox(
                    width: _vakken[p.sleutel]?.width,
                    height: widget.maten.hoogte,
                    child: Center(
                      child: MenuWoord(
                        punt: p,
                        tint: widget.tint,
                        maten: widget.maten,
                        onderPil: p.sleutel == onder,
                        statisch: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
          // De rand van de lens boven de inhoud.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              border: glas.border,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _rijMetPil() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _meet());
    final pil = pilVak;
    final lens = _sleep != null && _sleeptPil && pil != null;
    final getekend = lens ? Rect.fromCenter(center: pil.center, width: pil.width * kMenuLensZwel, height: pil.height * kMenuLensZwel) : pil;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (getekend != null)
          Positioned.fromRect(
            key: const ValueKey('menu-pil'),
            rect: getekend,
            child: DecoratedBox(decoration: menuPilVorm(widget.tint, lens: lens)),
          ),
        Row(key: _rij, mainAxisSize: MainAxisSize.min, children: [for (final p in widget.punten) _woord(p)]),
        if (lens)
          Positioned.fromRect(
            key: const ValueKey('menu-lens'),
            rect: getekend!,
            child: _lensInhoud(getekend),
          ),
      ],
    );
  }

  Widget _volledig() => Listener(
        onPointerSignal: _opWiel,
        child: GestureDetector(
          onHorizontalDragStart: _sleepBegin,
          onHorizontalDragUpdate: _sleepVerder,
          onHorizontalDragEnd: _sleepEinde,
          onHorizontalDragCancel: _sleepEinde,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, dragDevices: const {}),
            child: SingleChildScrollView(
              controller: _rol,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              physics: const ClampingScrollPhysics(),
              child: _rijMetPil(),
            ),
          ),
        ),
      );

  /// Ingeklapt: alleen de sectie waar je bent.
  Widget _ingeklapt() {
    final p = widget.punten.firstWhere((p) => p.sleutel == widget.actief, orElse: () => widget.punten.first);
    return MouseRegion(
      key: const ValueKey('menu-ingeklapt'),
      cursor: SystemMouseCursors.click,
      onEnter: (_) => widget.onUitklappen?.call(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onUitklappen,
        child: SizedBox(
          height: widget.maten.hoogte,
          child: DecoratedBox(
            decoration: menuPilVorm(widget.tint),
            child: Center(
              widthFactor: 1,
              child: MenuWoord(punt: p, tint: widget.tint, maten: widget.maten, onderPil: true),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zoek = widget.zoekbalk;
    final Widget inhoud;
    if (zoek != null) {
      inhoud = KeyedSubtree(key: const ValueKey('menu-zoeken'), child: zoek);
    } else if (widget.gekrompen) {
      inhoud = _ingeklapt();
    } else {
      inhoud = KeyedSubtree(key: const ValueKey('menu-vol'), child: _volledig());
    }
    return MenuGlas(
      child: Padding(
        padding: const EdgeInsets.all(MenuMaten.rand),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            layoutBuilder: (nu, vorige) => Stack(alignment: Alignment.center, children: [...vorige, if (nu != null) nu]),
            child: inhoud,
          ),
        ),
      ),
    );
  }
}

/// De losse ronde glasknop naast het ingeklapte menu (het vergrootglas), en voor de vensterknoppen.
class MenuRondje extends StatefulWidget {
  const MenuRondje({super.key, required this.icoon, required this.onTap, this.tooltip, this.maten = MenuMaten.muis});

  final MenuIcoonSoort icoon;
  final VoidCallback onTap;
  final String? tooltip;
  final MenuMaten maten;

  @override
  State<MenuRondje> createState() => _MenuRondjeState();
}

class _MenuRondjeState extends State<MenuRondje> {
  bool _aangewezen = false;

  @override
  Widget build(BuildContext context) {
    final maat = widget.maten.hoogte + MenuMaten.rand * 2;
    Widget knop = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _aangewezen = true),
      onExit: (_) => setState(() => _aangewezen = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox.square(
          dimension: maat,
          child: MenuGlas(
            child: Center(
              child: MenuIcoon(
                soort: widget.icoon,
                kleur: _aangewezen ? const Color(0xFFFFFFFF) : kGedempt,
                aangewezen: _aangewezen,
                maat: widget.maten.icoon,
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null && !isTv) knop = Tooltip(message: widget.tooltip!, child: knop);
    return knop;
  }
}
