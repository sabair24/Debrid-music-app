/// Vloeibaar glas (16-10-2026), en de bewaker die het terugzet als het te veel kost.
///
/// **Waarom.** Saber: *"Glas is gewoon doorzichtig, daar moet iets meer blur op, dat de achtergrond
/// beetje vervormd zoals echt glas."* Op een toestel was het glas sinds 3.9.459 een donkere laag
/// zonder vervaging, omdat 10 tot 14 vervagingen boven een draaiende cd de iPad heet maakten (zie
/// [glasZonderVervaging]). Hij koos vloeibaar glas, overal, en "waar het te veel kost, valt het
/// vanzelf terug op matglas".
///
/// **Drie standen ([GlasStand]):**
/// - **plat** — de vulling zonder vervaging. Op een tv altijd; elders als de bewaker het zegt.
/// - **mat** — echte vervaging met wat meer verzadiging en een lichtrand. Alle matte vlakken op een
///   scherm hebben HETZELFDE filter ([glasMat]) en hangen aan één `BackdropGroup` bovenaan de app: de
///   engine leest het scherm dan één keer terug voor allemaal, in plaats van één keer per vlak. Dat
///   laatste was de warme iPad.
/// - **vloeibaar** — mat, plus een lensrand die de achtergrond buigt ([GlasLens], een shader). Elke
///   lens kost een eigen pass, dus alleen op glas dat stil staat: de spelerbalk, de onderbalk, de
///   bovenknoppen van een albumpagina. Alleen onder Impeller (gsm, iPad, Mac).
///
/// **De bewaker ([GlasKwaliteit.bewaak])** leest de tekentijd van elk beeld zolang er glas op het
/// scherm staat. Is het 90e percentiel van twee meetvensters op rij hoger dan [kGlasBudget], dan gaat
/// het glas één stand omlaag, tot het einde van de sessie. Liever minder glas dan haperen.
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../tv.dart';

enum GlasStand { plat, mat, vloeibaar }

/// Hoeveel een beeld mag kosten om te tekenen (het 90e percentiel), voor het glas terugschakelt. Een
/// scherm van 120 Hz heeft 8,3 ms per beeld; dit laat ruimte voor de rest.
const kGlasBudget = Duration(microseconds: 7000);

/// Hoeveel beelden één meetvenster telt.
const kGlasVenster = 90;

/// Verzadiging: kleur die door glas komt, wordt voller (wat echt glas met licht doet).
List<double> _verzadig(double s) {
  const r = .2126, g = .7152, b = .0722;
  final i = 1 - s;
  return [
    r * i + s, g * i, b * i, 0, 0, //
    r * i, g * i + s, b * i, 0, 0, //
    r * i, g * i, b * i + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// HET filter van matglas: vervaging (iets breder dan hoog, als een gebogen ruit), een tikje
/// `dilate` zodat het licht uitloopt, en meer verzadiging. Eén object voor de hele app — de engine
/// voegt alleen GELIJKE filters in een `BackdropGroup` samen.
final ui.ImageFilter glasMat = ui.ImageFilter.compose(
  outer: ui.ColorFilter.matrix(_verzadig(1.35)),
  inner: ui.ImageFilter.compose(
    outer: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 12, tileMode: TileMode.clamp),
    inner: ui.ImageFilter.dilate(radiusX: 2, radiusY: 2),
  ),
);

/// De stand van het glas voor de hele app, en de bewaker.
class GlasKwaliteit {
  GlasKwaliteit._();

  /// Wat er nu getekend wordt. Glas luistert hiernaar en tekent opnieuw als het verandert.
  static final stand = ValueNotifier<GlasStand>(GlasStand.mat);

  /// Waarom de stand de laatste keer veranderde, voor de log (`ui.log`).
  static void Function(String regel)? meld;

  /// De shader van de lensrand, zodra hij geladen is. Null = (nog) geen lens.
  static ui.FragmentProgram? lens;

  static int _actief = 0;
  static final _tijden = <int>[];
  static int _teZwaar = 0;
  static bool _bewaakt = false;

  /// Hoeveel glasvlakken er nu op het scherm staan. Alleen dan meet de bewaker.
  static int get actief => _actief;
  static void _erbij() => _actief++;
  static void _eraf() => _actief = _actief > 0 ? _actief - 1 : 0;

  /// Kiest de beginstand voor dit toestel en start de bewaker. Eén keer, bij het opstarten.
  static Future<void> inrichten() async {
    if (isTv) {
      stand.value = GlasStand.plat;
      return;
    }
    stand.value = GlasStand.mat;
    if (ui.ImageFilter.isShaderFilterSupported) {
      try {
        lens = await ui.FragmentProgram.fromAsset('shaders/glas_lens.frag');
        stand.value = GlasStand.vloeibaar;
      } catch (e) {
        meld?.call('glas: lensshader niet geladen ($e) — matglas');
      }
    }
    bewaak();
  }

  /// Leest de tekentijd van elk beeld. Publiek voor de toets.
  static void bewaak() {
    if (_bewaakt) return;
    _bewaakt = true;
    SchedulerBinding.instance.addTimingsCallback(opBeelden);
  }

  /// Wat de bewaker met een rij beelden doet. Publiek voor de toets.
  @visibleForTesting
  static void opBeelden(List<ui.FrameTiming> beelden) {
    if (_actief == 0 || stand.value == GlasStand.plat) {
      _tijden.clear();
      return;
    }
    for (final b in beelden) {
      _tijden.add(b.rasterDuration.inMicroseconds);
    }
    if (_tijden.length < kGlasVenster) return;
    final p90 = negentigste(_tijden);
    _tijden.clear();
    if (p90 <= kGlasBudget.inMicroseconds) {
      _teZwaar = 0;
      return;
    }
    if (++_teZwaar < 2) return;
    _teZwaar = 0;
    final van = stand.value;
    final naar = van == GlasStand.vloeibaar ? GlasStand.mat : GlasStand.plat;
    stand.value = naar;
    meld?.call('glas: ${van.name} → ${naar.name}, 90e percentiel ${(p90 / 1000).toStringAsFixed(1)} ms '
        'per beeld met $_actief glasvlakken');
  }

  /// Het 90e percentiel van [microseconden].
  @visibleForTesting
  static int negentigste(List<int> microseconden) {
    final s = [...microseconden]..sort();
    return s[((s.length - 1) * .9).round()];
  }

  /// Terug naar de begintoestand, voor toetsen.
  @visibleForTesting
  static void vergeet() {
    _actief = 0;
    _tijden.clear();
    _teZwaar = 0;
    stand.value = GlasStand.mat;
  }
}

/// Een glasvlak: vervaging (mat of vloeibaar), de kleur erover, een lichtrand, en [child] erop.
///
/// De vulling staat NAAST de vervaging en niet erin (zie [balkGlas]): laat een toestel de vervaging
/// vallen, dan blijft de kleur staan en is het nog leesbaar.
class GlasVlak extends StatefulWidget {
  const GlasVlak({
    super.key,
    this.vorm = BorderRadius.zero,
    required this.vulling,
    this.lens = false,
    this.lichtrand = true,
    this.child,
  });

  /// De ronding van het vlak.
  final BorderRadius vorm;

  /// De kleur(en) over de vervaging. In plat glas het hele vlak.
  final Decoration vulling;

  /// Een lensrand erbij in de stand vloeibaar. Alleen voor glas dat stil staat — zie [GlasLens].
  final bool lens;

  /// De smalle heldere rand linksboven, zoals glas het licht vangt.
  final bool lichtrand;

  final Widget? child;

  @override
  State<GlasVlak> createState() => _GlasVlakState();
}

class _GlasVlakState extends State<GlasVlak> {
  @override
  void initState() {
    super.initState();
    GlasKwaliteit._erbij();
  }

  @override
  void dispose() {
    GlasKwaliteit._eraf();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GlasStand>(
        valueListenable: GlasKwaliteit.stand,
        builder: (context, stand, _) {
          final vulling = DecoratedBox(decoration: widget.vulling);
          final rand = widget.lichtrand ? CustomPaint(painter: _Lichtrand(widget.vorm)) : null;
          return ClipRRect(
            borderRadius: widget.vorm,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (stand != GlasStand.plat)
                  // Een LEEG kind: de vervaging hoeft niets te tekenen, alleen te vervagen wat
                  // erachter ligt. `.grouped`: één terugleesbeurt voor alle glas op het scherm.
                  Positioned.fill(child: BackdropFilter.grouped(filter: glasMat, child: const SizedBox.expand())),
                if (stand == GlasStand.vloeibaar && widget.lens)
                  Positioned.fill(child: GlasLens(hoek: widget.vorm.topLeft.x)),
                Positioned.fill(child: vulling),
                if (rand != null) Positioned.fill(child: IgnorePointer(child: rand)),
                widget.child ?? const SizedBox.shrink(),
              ],
            ),
          );
        },
      );
}

/// De lichtrand: een streep die linksboven helder is en naar rechtsonder uitdooft.
class _Lichtrand extends CustomPainter {
  _Lichtrand(this.vorm);
  final BorderRadius vorm;

  @override
  void paint(Canvas canvas, Size size) {
    final r = vorm.toRRect(Offset.zero & size).deflate(.5);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), const [
        Color(0x8CFFFFFF),
        Color(0x1FFFFFFF),
        Color(0x0AFFFFFF),
      ], const [0, .45, 1]);
    canvas.drawRRect(r, p);
  }

  @override
  bool shouldRepaint(_Lichtrand oud) => oud.vorm != vorm;
}

/// De lensrand: buigt de (al vervaagde) achtergrond aan de rand van het vlak.
///
/// **Alleen voor glas dat stil staat.** De shader krijgt zijn plek op het scherm bij het tekenen
/// mee; een vlak dat met een lijst meeschuift tekent niet opnieuw bij elke scrolstap, en dan ligt de
/// buiging naast het glas. En uit zolang zijn pagina in- of uitschuift: daar ligt een laag met
/// doorzichtigheid boven, en dan is de achtergrond voor de shader leeg (Flutter 3.41.9, nagelezen).
class GlasLens extends StatefulWidget {
  const GlasLens({super.key, required this.hoek, this.rand = 9, this.buiging = 7, this.licht = .55});

  /// Hoekstraal, randbreedte en verschuiving in logische punten; [licht] van 0 tot 1.
  final double hoek, rand, buiging, licht;

  @override
  State<GlasLens> createState() => _GlasLensState();
}

class _GlasLensState extends State<GlasLens> {
  Animation<double>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = ModalRoute.of(context)?.animation;
    if (a != _route) {
      _route?.removeStatusListener(_opRoute);
      _route = a?..addStatusListener(_opRoute);
    }
  }

  void _opRoute(AnimationStatus _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_opRoute);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _route;
    final rust = r == null || r.status == AnimationStatus.completed;
    final p = GlasKwaliteit.lens;
    if (!rust || p == null || !ui.ImageFilter.isShaderFilterSupported) return const SizedBox.expand();
    return _Lens(
      programma: p,
      dpr: MediaQuery.devicePixelRatioOf(context),
      hoek: widget.hoek,
      rand: widget.rand,
      buiging: widget.buiging,
      licht: widget.licht,
    );
  }
}

class _Lens extends LeafRenderObjectWidget {
  const _Lens({
    required this.programma,
    required this.dpr,
    required this.hoek,
    required this.rand,
    required this.buiging,
    required this.licht,
  });
  final ui.FragmentProgram programma;
  final double dpr, hoek, rand, buiging, licht;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLens(programma.fragmentShader(), dpr, hoek, rand, buiging, licht);

  @override
  void updateRenderObject(BuildContext context, _RenderLens r) => r
    ..dpr = dpr
    ..hoek = hoek
    ..rand = rand
    ..buiging = buiging
    ..licht = licht
    ..markNeedsPaint();
}

/// De uniforms van [glas_lens.frag] voor een vlak op [rect] (logische punten op het scherm), in de
/// volgorde van de shader: 0–1 zet de engine zelf, dan het vlak en de vier instellingen. Publiek voor
/// de toets: een verkeerde volgorde geeft in 3.41.9 geen fout, alleen een leeg vlak.
@visibleForTesting
List<double> lensWaarden(Rect rect, double dpr,
        {required double hoek, required double rand, required double buiging, required double licht}) =>
    [
      rect.left * dpr, rect.top * dpr, rect.width * dpr, rect.height * dpr, //
      hoek * dpr, rand * dpr, buiging * dpr, licht,
    ];

class _RenderLens extends RenderBox {
  _RenderLens(this._shader, this.dpr, this.hoek, this.rand, this.buiging, this.licht);

  final ui.FragmentShader _shader;
  double dpr, hoek, rand, buiging, licht;
  final _laag = LayerHandle<BackdropFilterLayer>();

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final opScherm = MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);
    final w = lensWaarden(opScherm, dpr, hoek: hoek, rand: rand, buiging: buiging, licht: licht);
    for (var i = 0; i < w.length; i++) {
      _shader.setFloat(2 + i, w[i]);
    }
    // Een NIEUW filter na elke wijziging: de engine kopieert de waarden bij het maken ervan.
    final laag = _laag.layer ??= BackdropFilterLayer();
    laag.filter = ui.ImageFilter.shader(_shader);
    context.pushLayer(laag, (_, __) {}, offset);
  }

  @override
  void dispose() {
    _laag.layer = null;
    _shader.dispose();
    super.dispose();
  }
}
