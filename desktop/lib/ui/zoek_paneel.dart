/// Het glazen paneel met suggesties onder een zoekveld, en wat er na een tik vliegt.
///
/// Saber koos op 08-11-2026 voorbeeld A: "een glazen paneel veert open onder het zoekveld", in ongeveer 0,3 s met een lichte
/// veer, en het typen wacht er nooit op. Op de Shield een raster van drie kolommen, bereikbaar met de pijltjes. Wat erin staat,
/// staat in `zoek_suggesties.dart`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../zoek_suggesties.dart';
import 'glas.dart';
import 'kleuren.dart';

/// De veer van het paneel: gaat even voorbij zijn eindstand en komt terug.
const kPaneelVeer = Cubic(.2, 1.3, .38, 1);
const kPaneelOpen = Duration(milliseconds: 300);
const kPaneelDicht = Duration(milliseconds: 120);
const kRijIn = Duration(milliseconds: 180);
const kWoordVlucht = Duration(milliseconds: 420);
const kBeeldVlucht = Duration(milliseconds: 360);

/// Open of dicht, van buitenaf. [groep] hoort ook op het tekstveld (`TextField.groupId`): een tik op het paneel telt dan niet
/// als "ernaast", en het veld houdt zijn focus tot de rij zijn werk gedaan heeft.
class ZoekPaneelStuur extends ChangeNotifier {
  final Object groep = Object();
  bool dicht = false;

  /// Het paneel dat nu open staat en wat er dan moet gebeuren bij Terug. De terugknop van Android en de Shield komt niet als
  /// toets binnen maar bij de schil ([sluitOpenPaneel]).
  static VoidCallback? _sluitOpen;

  /// Staat er een paneel open? Dan gaat dat dicht, en is dat de hele stap terug.
  static bool sluitOpenPaneel() {
    final s = _sluitOpen;
    if (s == null) return false;
    s();
    return true;
  }

  bool Function()? _naarEerste;

  void sluit() {
    if (dicht) return;
    dicht = true;
    notifyListeners();
  }

  void open() {
    if (!dicht) return;
    dicht = false;
    notifyListeners();
  }

  /// De eerste rij aanwijzen (de Shield, na OK op het toetsenbord). Onwaar als er geen rij is.
  bool naarEerste() => _naarEerste?.call() ?? false;
}

/// Een rij in het paneel, voor de pijltjes.
class _Regel {
  const _Regel.suggestie(Suggestie this.suggestie, this.groep)
      : tekst = null,
        recent = false,
        zoek = false;
  const _Regel.zoek(String this.tekst)
      : suggestie = null,
        groep = null,
        recent = false,
        zoek = true;
  const _Regel.recent(String this.tekst)
      : suggestie = null,
        groep = null,
        recent = true,
        zoek = false;
  final Suggestie? suggestie;
  final String? groep;
  final String? tekst;
  final bool recent;
  final bool zoek;

  String get sleutel => suggestie?.sleutel ?? (zoek ? 'zoek' : 'recent:$tekst');
}

/// Zet het paneel onder [child], een zoekveld dat [controller] en [focus] gebruikt.
class ZoekSuggesties extends StatefulWidget {
  const ZoekSuggesties({
    super.key,
    required this.controller,
    required this.focus,
    required this.bron,
    required this.recent,
    required this.stuur,
    required this.beeld,
    required this.opKies,
    required this.opZoek,
    required this.zoekTekst,
    required this.opRecent,
    required this.child,
    this.tv = false,
    this.inline = false,
    this.klein = false,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final SuggestieBron bron;
  final ZoekRecent recent;
  final ZoekPaneelStuur stuur;

  /// De foto of hoes van een rij, zo groot als gevraagd.
  final Widget Function(BuildContext context, Suggestie s, double maat) beeld;

  /// Een rij gekozen. [van]: waar zijn beeld nu staat, voor [vliegBeeld]; [beeld]: dat beeld.
  final void Function(Suggestie s, Rect? van, Widget beeld) opKies;

  /// De rij "Zoek … op": gewoon zoeken op wat er staat.
  final void Function(String tekst) opZoek;

  /// Wat er op die rij staat: "Zoek online op “khalid”".
  final String Function(String tekst) zoekTekst;

  /// Een oude zoekopdracht gekozen.
  final void Function(String tekst) opRecent;

  /// De Shield: raster van drie kolommen, en de zoekrij vooraan, zodat OK op het toetsenbord en dan nog eens OK gewoon zoekt.
  final bool tv;

  /// Niet zwevend maar eronder in de pagina (de zoekdialoog van de Shield, waar het anders over de knoppen zou liggen).
  final bool inline;

  /// Een smal scherm: onder het paneel staan de minispeler en de tabbalk, en die blijven zichtbaar.
  final bool klein;

  final Widget child;

  @override
  State<ZoekSuggesties> createState() => _ZoekSuggestiesState();
}

class _ZoekSuggestiesState extends State<ZoekSuggesties> with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final AnimationController _open = AnimationController(vsync: this, duration: kPaneelOpen, reverseDuration: kPaneelDicht);
  late final _eersteRij = FocusNode(debugLabel: 'eerste suggestie');
  final _lijst = ScrollController();
  final _paneelSleutel = GlobalKey();
  final _actiefSleutel = GlobalKey();
  bool _inPaneel = false;
  bool _terugUitPaneel = false;
  Rect? _veldRect;
  int _actief = -1;
  String _tekstWas = '';

  bool get _rustig => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _tekstWas = widget.controller.text;
    widget.controller.addListener(_opTekst);
    widget.focus.addListener(_opFocus);
    widget.bron.addListener(_ververs);
    widget.recent.addListener(_ververs);
    widget.stuur.addListener(_ververs);
    widget.stuur._naarEerste = _naarEerste;
    _open.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && _portal.isShowing && mounted) _portal.hide();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pasZichtbaarheidAan();
    });
  }

  @override
  void didUpdateWidget(ZoekSuggesties oud) {
    super.didUpdateWidget(oud);
    if (oud.controller != widget.controller) {
      oud.controller.removeListener(_opTekst);
      widget.controller.addListener(_opTekst);
    }
    if (oud.focus != widget.focus) {
      oud.focus.removeListener(_opFocus);
      widget.focus.addListener(_opFocus);
    }
    if (oud.bron != widget.bron) {
      oud.bron.removeListener(_ververs);
      widget.bron.addListener(_ververs);
    }
    if (oud.recent != widget.recent) {
      oud.recent.removeListener(_ververs);
      widget.recent.addListener(_ververs);
    }
    if (oud.stuur != widget.stuur) {
      oud.stuur.removeListener(_ververs);
      if (oud.stuur._naarEerste == _naarEerste) oud.stuur._naarEerste = null;
      widget.stuur.addListener(_ververs);
    }
    widget.stuur._naarEerste = _naarEerste;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_opTekst);
    widget.focus.removeListener(_opFocus);
    widget.bron.removeListener(_ververs);
    widget.recent.removeListener(_ververs);
    widget.stuur.removeListener(_ververs);
    if (widget.stuur._naarEerste == _naarEerste) widget.stuur._naarEerste = null;
    if (ZoekPaneelStuur._sluitOpen == _sluitBijTerug) ZoekPaneelStuur._sluitOpen = null;
    _open.dispose();
    _eersteRij.dispose();
    _lijst.dispose();
    super.dispose();
  }

  void _opTekst() {
    final t = widget.controller.text;
    if (t == _tekstWas) return;
    _tekstWas = t;
    _actief = -1;
    widget.bron.zet(t);
    if (widget.focus.hasFocus) widget.stuur.open();
    _ververs();
  }

  void _opFocus() {
    if (widget.focus.hasFocus) {
      widget.bron.warmOp();
      widget.bron.zet(widget.controller.text);
      // Terug uit het paneel: het veld krijgt de focus, en het paneel blijft dicht tot je typt.
      if (!_terugUitPaneel) widget.stuur.open();
      _terugUitPaneel = false;
    }
    _ververs();
  }

  void _ververs() {
    if (!mounted) return;
    _pasZichtbaarheidAan();
    if (_portal.isShowing || widget.inline) setState(() {});
  }

  List<_Regel> get _regels {
    final tekst = widget.controller.text.trim();
    if (tekst.isEmpty) return [for (final r in widget.recent.lijst) _Regel.recent(r)];
    final rijen = <_Regel>[
      for (final g in widget.bron.groepen)
        for (final s in g.rijen) _Regel.suggestie(s, g.naam),
    ];
    return widget.tv ? [_Regel.zoek(tekst), ...rijen] : [...rijen, _Regel.zoek(tekst)];
  }

  bool get _hoortOpen =>
      !widget.stuur.dicht && (widget.focus.hasFocus || _inPaneel) && _regels.isNotEmpty;

  void _pasZichtbaarheidAan() {
    if (widget.inline) return;
    if (_hoortOpen) {
      ZoekPaneelStuur._sluitOpen = _sluitBijTerug;
      _meetVeld();
      if (!_portal.isShowing) _portal.show();
      if (_rustig) {
        _open.value = 1;
      } else if (_open.status != AnimationStatus.forward && _open.status != AnimationStatus.completed) {
        _open.forward();
      }
    } else if (_portal.isShowing) {
      if (ZoekPaneelStuur._sluitOpen == _sluitBijTerug) ZoekPaneelStuur._sluitOpen = null;
      if (_rustig) {
        _open.value = 0;
      } else if (_open.status != AnimationStatus.reverse && _open.status != AnimationStatus.dismissed) {
        _open.reverse();
      }
      _actief = -1;
    }
  }

  void _sluitBijTerug() {
    final opRij = _inPaneel;
    widget.stuur.sluit();
    if (opRij && !widget.focus.hasFocus) {
      _terugUitPaneel = true;
      widget.focus.requestFocus();
    }
  }

  bool _naarEerste() {
    if (_regels.isEmpty) return false;
    widget.stuur.open();
    _ververs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _eersteRij.context != null) _eersteRij.requestFocus();
    });
    return true;
  }

  KeyEventResult _toets(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final regels = _regels;
    final open = _hoortOpen;
    if (k == LogicalKeyboardKey.escape && open) {
      widget.stuur.sluit();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (regels.isEmpty) return KeyEventResult.ignored;
      if (widget.tv) return _naarEerste() ? KeyEventResult.handled : KeyEventResult.ignored;
      widget.stuur.open();
      setState(() => _actief = math.min(_actief + 1, regels.length - 1));
      _toonActief();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && open && !widget.tv) {
      setState(() => _actief = math.max(_actief - 1, -1));
      _toonActief();
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && open && _actief >= 0 && _actief < regels.length) {
      _kies(regels[_actief], null, null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toonActief() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _actiefSleutel.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 120), alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 120), alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    });
  }

  void _kies(_Regel r, Rect? van, Widget? beeld) {
    if (r.suggestie != null) {
      widget.opKies(r.suggestie!, van, beeld ?? const SizedBox.shrink());
    } else if (r.zoek) {
      widget.opZoek(r.tekst!);
    } else {
      widget.opRecent(r.tekst!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final veld = Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _toets, child: widget.child);
    if (_portal.isShowing) WidgetsBinding.instance.addPostFrameCallback((_) => _meetVeld());
    if (widget.inline) {
      final regels = _regels;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        veld,
        if (!widget.stuur.dicht && regels.isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: _inhoud(regels, MediaQuery.sizeOf(context).width),
          ),
        ],
      ]);
    }
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _bouwPaneel,
      child: CompositedTransformTarget(link: _link, child: TapRegion(groupId: widget.stuur.groep, child: veld)),
    );
  }

  /// Waar het veld staat. Buiten het bouwen van het paneel gemeten: tijdens het bouwen na een draai zijn de lagen erboven nog
  /// niet opgemaakt, en dan valt `localToGlobal` om (gezien in tidal_smal_scherm_test).
  void _meetVeld() {
    if (!mounted) return;
    final d = context.findRenderObject();
    if (d is! RenderBox || !d.attached || !d.hasSize) return;
    final r = d.localToGlobal(Offset.zero) & d.size;
    if (r == _veldRect) return;
    _veldRect = r;
    if (_portal.isShowing) setState(() {});
  }

  Widget _bouwPaneel(BuildContext ctx) {
    final veldRect = _veldRect;
    if (veldRect == null) return const SizedBox.shrink();
    final scherm = MediaQuery.sizeOf(ctx);
    final toetsenbord = MediaQuery.viewInsetsOf(ctx).bottom;
    final plek = veldRect.topLeft;
    final minBreed = math.min(340.0, scherm.width - 16);
    final maxBreed = widget.tv ? scherm.width - 80 : math.min(640.0, scherm.width - 16);
    final breed = widget.tv ? maxBreed : veldRect.width.clamp(minBreed, maxBreed);
    var dx = 0.0;
    if (plek.dx + breed > scherm.width - 8) dx = scherm.width - 8 - plek.dx - breed;
    if (plek.dx + dx < 8) dx = 8 - plek.dx;
    final onderVeld = veldRect.bottom + 6;
    final onderRuimte = toetsenbord > 0 ? toetsenbord + 8 : (widget.klein ? 122.0 : 16.0);
    final maxHoog = math.max(120.0, scherm.height - onderVeld - onderRuimte);
    final regels = _regels;
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: Offset(dx, 6),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: breed,
          child: TapRegion(
            groupId: widget.stuur.groep,
            onTapOutside: (_) => widget.stuur.sluit(),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (f) {
                _inPaneel = f;
                _ververs();
              },
              onKeyEvent: (_, e) {
                if (e is KeyUpEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.escape || e.logicalKey == LogicalKeyboardKey.goBack) {
                  _sluitBijTerug();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: AnimatedBuilder(
                animation: _open,
                builder: (_, kind) {
                  final t = _open.status == AnimationStatus.reverse ? _open.value : kPaneelVeer.transform(_open.value.clamp(0.0, 1.0));
                  final schaal = .95 + .05 * t;
                  return Transform(
                    alignment: Alignment.topCenter,
                    transform: Matrix4.identity()
                      ..translateByDouble(0.0, -10.0 * (1 - t), 0.0, 1.0)
                      ..scaleByDouble(schaal, schaal, 1.0, 1.0),
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: math.min(1.0, math.max(0.0, t * 1.5)),
                        child: kind,
                      ),
                    ),
                  );
                },
                child: GlasVlak(
                  key: _paneelSleutel,
                  vorm: const BorderRadius.all(Radius.circular(20)),
                  kleur: kPaneel,
                  bovenop: true,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHoog),
                    child: AnimatedSize(
                      duration: _rustig ? Duration.zero : const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _inhoud(regels, breed),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _inhoud(List<_Regel> regels, double breed) {
    final kinderen = <Widget>[];
    final tekst = widget.controller.text.trim();
    var i = 0;
    String? groepWas;
    final raster = widget.tv;
    final tvBreed = (breed - 12 - 2 * 6) / 3;
    final rijen = <Widget>[];

    void leegRijen() {
      if (rijen.isEmpty) return;
      kinderen.add(raster
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: List.of(rijen)),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: List.of(rijen)));
      rijen.clear();
    }

    for (final r in regels) {
      final kop = r.recent ? 'Laatst gezocht' : r.groep;
      if (kop != null && kop != groepWas) {
        leegRijen();
        kinderen.add(_Kop(kop, tv: widget.tv));
        groepWas = kop;
      }
      final ik = i;
      final actief = ik == _actief;
      Widget rij = _Rij(
        key: ValueKey(r.sleutel),
        regel: r,
        getypt: tekst,
        volgorde: ik,
        actief: actief,
        tv: widget.tv,
        tvBreed: tvBreed,
        focusNode: ik == 0 ? _eersteRij : null,
        paneel: _paneelSleutel,
        rustig: _rustig,
        beeld: widget.beeld,
        tekstVanZoek: widget.zoekTekst,
        bezig: r.zoek && widget.bron.onlineBezig,
        opTik: (van, beeld) => _kies(r, van, beeld),
        opWis: r.recent ? () => widget.recent.wis(r.tekst!) : null,
        terugNaarVeld: widget.tv && ik < 3 ? () => widget.focus.requestFocus() : null,
      );
      if (actief) rij = KeyedSubtree(key: _actiefSleutel, child: rij);
      rijen.add(rij);
      i++;
    }
    leegRijen();
    return ListView(
      controller: _lijst,
      shrinkWrap: true,
      padding: const EdgeInsets.all(6),
      physics: const ClampingScrollPhysics(),
      children: kinderen,
    );
  }
}

class _Kop extends StatelessWidget {
  const _Kop(this.tekst, {required this.tv});
  final String tekst;
  final bool tv;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Text(tekst.toUpperCase(),
            style: TextStyle(fontSize: tv ? 13 : 10.5, fontWeight: FontWeight.w700, letterSpacing: .8, color: kGedempt)),
      );
}

/// Tekst met de getypte letters opgelicht ([oplichtDelen]).
class _Licht extends StatelessWidget {
  const _Licht(this.tekst, this.getypt, {required this.stijl, required this.licht});
  final String tekst, getypt;
  final TextStyle stijl, licht;

  @override
  Widget build(BuildContext context) {
    final delen = oplichtDelen(tekst, getypt);
    final spans = <TextSpan>[];
    var p = 0;
    for (final (a, z) in delen) {
      if (a < p) continue;
      if (a > p) spans.add(TextSpan(text: tekst.substring(p, a)));
      spans.add(TextSpan(text: tekst.substring(a, z), style: licht));
      p = z;
    }
    if (p < tekst.length) spans.add(TextSpan(text: tekst.substring(p)));
    return Text.rich(TextSpan(style: stijl, children: spans), maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

/// Eén rij. Komt zacht binnen, en schuift mee als hij door een nieuwe letter op een andere plek belandt.
class _Rij extends StatefulWidget {
  const _Rij({
    super.key,
    required this.regel,
    required this.getypt,
    required this.volgorde,
    required this.actief,
    required this.tv,
    required this.tvBreed,
    required this.paneel,
    required this.rustig,
    required this.beeld,
    required this.tekstVanZoek,
    required this.bezig,
    required this.opTik,
    this.focusNode,
    this.opWis,
    this.terugNaarVeld,
  });

  final _Regel regel;
  final String getypt;
  final int volgorde;
  final bool actief, tv, rustig, bezig;
  final double tvBreed;
  final GlobalKey paneel;
  final FocusNode? focusNode;
  final Widget Function(BuildContext, Suggestie, double) beeld;
  final String Function(String) tekstVanZoek;
  final void Function(Rect? van, Widget? beeld) opTik;
  final VoidCallback? opWis;
  final VoidCallback? terugNaarVeld;

  @override
  State<_Rij> createState() => _RijState();
}

class _RijState extends State<_Rij> with SingleTickerProviderStateMixin {
  late final AnimationController _klok = AnimationController(vsync: this, duration: kRijIn);
  final _beeldSleutel = GlobalKey();
  Offset? _plekWas;
  Offset _vanaf = Offset.zero;
  bool _focus = false;
  Timer? _wacht;

  @override
  void initState() {
    super.initState();
    if (widget.rustig) {
      _klok.value = 1;
    } else {
      // Een korte waterval, maar nooit zo lang dat je erop wacht.
      _wacht = Timer(Duration(milliseconds: math.min(widget.volgorde, 9) * 16), () {
        if (mounted) _klok.forward();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback(_meet);
  }

  @override
  void didUpdateWidget(_Rij oud) {
    super.didUpdateWidget(oud);
    if (!widget.rustig) WidgetsBinding.instance.addPostFrameCallback(_meet);
  }

  void _meet(Duration _) {
    if (!mounted) return;
    final ik = context.findRenderObject();
    final paneel = widget.paneel.currentContext?.findRenderObject();
    if (ik is! RenderBox || !ik.hasSize) return;
    final plek = paneel is RenderBox ? ik.localToGlobal(Offset.zero, ancestor: paneel) : null;
    if (plek == null) return;
    final was = _plekWas;
    _plekWas = plek;
    if (was == null || (was - plek).distance < 1 || widget.rustig) return;
    // Hij staat nu ergens anders: vertrek van de oude plek.
    _vanaf = was - plek;
    _klok
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
    _wacht?.cancel();
    _klok.dispose();
    super.dispose();
  }

  Rect? _beeldPlek() {
    final b = _beeldSleutel.currentContext?.findRenderObject();
    if (b is! RenderBox || !b.hasSize) return null;
    return b.localToGlobal(Offset.zero) & b.size;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.regel;
    final tv = widget.tv;
    final maat = tv ? 56.0 : 40.0;
    Widget? beeld;
    final Widget midden;
    Widget? rechts;
    if (r.suggestie != null) {
      final s = r.suggestie!;
      beeld = KeyedSubtree(key: _beeldSleutel, child: widget.beeld(context, s, maat));
      final titel = TextStyle(fontSize: tv ? 18 : 13.5, fontWeight: FontWeight.w500, color: kGedempt);
      final onder = TextStyle(fontSize: tv ? 14 : 11.5, color: kGedempt);
      final licht = TextStyle(fontWeight: FontWeight.w700, color: kTekst);
      midden = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _Licht(s.titel, widget.getypt, stijl: titel, licht: licht),
        _Licht(s.onder, widget.getypt, stijl: onder, licht: licht),
      ]);
      rechts = Icon(s.eigen ? Icons.check_circle_outline_rounded : Icons.download_rounded,
          size: tv ? 20 : 17, color: s.eigen ? kAccent2 : kGedempt);
    } else if (r.zoek) {
      beeld = SizedBox(width: maat, height: tv ? maat : 28, child: Icon(Icons.travel_explore_rounded, size: tv ? 26 : 19, color: kAccent));
      midden = Text(widget.tekstVanZoek(r.tekst!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: tv ? 18 : 13.5, fontWeight: FontWeight.w600, color: kAccent));
      if (widget.bezig) {
        rechts = SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent2));
      }
    } else {
      beeld = SizedBox(width: maat, height: tv ? maat : 28, child: Icon(Icons.history_rounded, size: tv ? 24 : 18, color: kGedempt));
      midden = Text(r.tekst!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: tv ? 18 : 13.5, fontWeight: FontWeight.w500, color: kTekst));
      if (widget.opWis != null) {
        rechts = IconButton(
          tooltip: 'Wissen',
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          icon: Icon(Icons.close_rounded, color: kGedempt),
          onPressed: widget.opWis,
        );
      }
    }
    final aangewezen = widget.actief || _focus;
    Widget inhoud = Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: tv ? 9 : 7),
      child: Row(children: [
        beeld,
        SizedBox(width: tv ? 12 : 10),
        Expanded(child: midden),
        if (rechts != null) ...[const SizedBox(width: 8), rechts],
      ]),
    );
    inhoud = Material(
      type: MaterialType.transparency,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) {
          if (e is! KeyUpEvent && e.logicalKey == LogicalKeyboardKey.arrowUp && widget.terugNaarVeld != null) {
            widget.terugNaarVeld!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: InkWell(
          focusNode: widget.focusNode,
          // De pijltjes op een pc lopen vanuit het tekstveld; alleen op de Shield staat de focus zelf op een rij.
          canRequestFocus: tv,
          borderRadius: BorderRadius.circular(tv ? 14 : 12),
          onFocusChange: (f) => setState(() => _focus = f),
          onTap: () => widget.opTik(_beeldPlek(), beeld),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tv ? 14 : 12),
              color: aangewezen ? kPaneelHoog.withValues(alpha: .86) : Colors.transparent,
              border: tv && _focus ? Border.all(color: kTekst, width: 3) : null,
            ),
            child: inhoud,
          ),
        ),
      ),
    );
    if (tv) inhoud = SizedBox(width: widget.tvBreed, child: AnimatedScale(scale: _focus ? 1.02 : 1, duration: const Duration(milliseconds: 120), child: inhoud));
    return AnimatedBuilder(
      animation: _klok,
      child: inhoud,
      builder: (_, kind) {
        final t = Curves.easeOutCubic.transform(_klok.value);
        final schuif = Offset.lerp(_vanaf, Offset.zero, t)!;
        // Binnenkomen: omhoog en invaden. Verschuiven: alleen de plek; hij stond er al.
        final nieuw = _vanaf == Offset.zero;
        return Transform.translate(
          offset: nieuw ? Offset(0, 6 * (1 - t)) : schuif,
          child: Opacity(opacity: nieuw ? t : 1, child: kind),
        );
      },
    );
  }
}

/// De rechthoek van [sleutel] op het scherm, of null.
Rect? rechthoekVan(GlobalKey sleutel) {
  final b = sleutel.currentContext?.findRenderObject();
  if (b is! RenderBox || !b.hasSize || !b.attached) return null;
  return b.localToGlobal(Offset.zero) & b.size;
}

/// Saber koos op 08-11-2026 "Het woord vliegt mee": je woord vliegt van de bibliotheek naar het zoekveld van Online zoeken.
///
/// [naar] wordt een beeld later gelezen: het andere scherm moet eerst bestaan. Is er geen doel, dan vliegt er niets en roept
/// hij [klaar] meteen aan. Het zoeken wacht hier niet op.
void vliegWoord(BuildContext context, {required String woord, required Rect van, required Rect? Function() naar, VoidCallback? klaar}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
    klaar?.call();
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final doel = naar();
    if (doel == null) {
      klaar?.call();
      return;
    }
    late final OverlayEntry laag;
    laag = OverlayEntry(
      builder: (_) => _VliegendWoord(
        woord: woord,
        van: van,
        naar: doel,
        klaar: () {
          laag.remove();
          laag.dispose();
          klaar?.call();
        },
      ),
    );
    overlay.insert(laag);
  });
}

class _VliegendWoord extends StatefulWidget {
  const _VliegendWoord({required this.woord, required this.van, required this.naar, required this.klaar});
  final String woord;
  final Rect van, naar;
  final VoidCallback klaar;

  @override
  State<_VliegendWoord> createState() => _VliegendWoordState();
}

class _VliegendWoordState extends State<_VliegendWoord> with SingleTickerProviderStateMixin {
  late final AnimationController _k = AnimationController(vsync: this, duration: kWoordVlucht + const Duration(milliseconds: 140))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.klaar();
    })
    ..forward();

  @override
  void dispose() {
    _k.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vlucht = kWoordVlucht.inMilliseconds / _k.duration!.inMilliseconds;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _k,
        builder: (_, __) {
          final t = Cubic(.22, .9, .24, 1).transform((_k.value / vlucht).clamp(0.0, 1.0));
          final weg = ((_k.value - vlucht) / (1 - vlucht)).clamp(0.0, 1.0);
          final van = widget.van.centerLeft, naar = widget.naar.centerLeft;
          final plek = Offset.lerp(van, naar, t)!;
          return Stack(children: [
            Positioned(
              left: plek.dx - 11,
              top: plek.dy - 14,
              child: Opacity(
                opacity: 1 - weg,
                child: Material(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                    child: Text(widget.woord,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3)),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// De foto vliegt mee naar de pagina die opengaat. Staat er op die pagina een `Hero` met [heroTag], dan landt hij daarop;
/// anders groeit hij naar de bovenkant van het scherm en lost hij op in de pagina.
void vliegBeeld(BuildContext context, {required Rect van, required Widget beeld, String? heroTag, BuildContext? zoekIn}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return;
  final scherm = MediaQuery.sizeOf(context);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Rect? doel;
    if (heroTag != null && zoekIn != null && zoekIn.mounted) {
      void kijk(Element e) {
        if (doel != null) return;
        final w = e.widget;
        if (w is Hero && w.tag == heroTag) {
          final b = e.findRenderObject();
          if (b is RenderBox && b.hasSize) doel = b.localToGlobal(Offset.zero) & b.size;
          return;
        }
        e.visitChildren(kijk);
      }

      zoekIn.visitChildElements(kijk);
    }
    final maat = math.min(scherm.width * .5, 220.0);
    final eind = doel ?? Rect.fromLTWH((scherm.width - maat) / 2, scherm.height * .12, maat, maat);
    late final OverlayEntry laag;
    laag = OverlayEntry(
      builder: (_) => _VliegendBeeld(
        beeld: beeld,
        van: van,
        naar: eind,
        oplossen: doel == null,
        klaar: () {
          laag.remove();
          laag.dispose();
        },
      ),
    );
    overlay.insert(laag);
  });
}

class _VliegendBeeld extends StatefulWidget {
  const _VliegendBeeld({required this.beeld, required this.van, required this.naar, required this.oplossen, required this.klaar});
  final Widget beeld;
  final Rect van, naar;
  final bool oplossen;
  final VoidCallback klaar;

  @override
  State<_VliegendBeeld> createState() => _VliegendBeeldState();
}

class _VliegendBeeldState extends State<_VliegendBeeld> with SingleTickerProviderStateMixin {
  late final AnimationController _k = AnimationController(vsync: this, duration: kBeeldVlucht)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.klaar();
    })
    ..forward();

  @override
  void dispose() {
    _k.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _k,
          builder: (_, __) {
            final t = Cubic(.22, .9, .24, 1).transform(_k.value);
            final r = Rect.lerp(widget.van, widget.naar, t)!;
            final schaal = r.width / widget.van.width;
            // Zonder doel lost hij op; mét doel staat de pagina er al onder, en verdwijnt hij pas op het laatst.
            final dek = widget.oplossen ? 1 - ((_k.value - .55) / .45).clamp(0.0, 1.0) : (_k.value > .92 ? (1 - _k.value) / .08 : 1.0);
            return Stack(children: [
              Positioned(
                left: r.left,
                top: r.top,
                child: Opacity(
                  opacity: dek.clamp(0.0, 1.0),
                  child: Transform.scale(
                    alignment: Alignment.topLeft,
                    scale: schaal,
                    child: SizedBox(width: widget.van.width, height: widget.van.height, child: widget.beeld),
                  ),
                ),
              ),
            ]);
          },
        ),
      );
}
