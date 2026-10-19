/// De wachtrij als stapel op Nu speelt (Saber, 19-10-2026).
///
/// Wat hij koos, uit twee voorbeeldborden: een schakelaar in het ⋯-menu, per toestel onthouden; vijf
/// hoezen (de spelende vooraan, de volgende vier erachter); de stapel loopt **naar links** weg, zodat de
/// cd rechts vrij uitschuift; **ruim**. Bladeren door **omhoog te vegen**: de voorste hoes vliegt omhoog
/// en valt achteraan de rij, de volgende komt naar voren; omlaag vegen haalt hem terug. Een tik op de
/// voorste speelt dat nummer; zonder tik veert de stapel na een paar seconden terug. Geen label. Ook
/// tijdens de radio, en op gsm, iPad, pc en tv (daar links en rechts).
///
/// **Goedkoop.** De hoezen zijn al gedecodeerd op hun maat en worden alleen verschoven en geschaald; het
/// donkerder worden is een zwart vlak (geen filter, geen saveLayer). Per beeld wordt alleen de rij
/// transforms opnieuw gebouwd, en alleen zolang er geschoven wordt.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../paths.dart';

/// De keuze voor de stapel, per toestel (naast thema.json).
class StapelKeuze {
  StapelKeuze._();
  static final aan = ValueNotifier<bool>(false);
  static File get _bestand => appFile('nu_speelt.json');

  static void laad() {
    try {
      final j = jsonDecode(_bestand.readAsStringSync());
      if (j is Map && j['stapel'] is bool) aan.value = j['stapel'] as bool;
    } catch (_) {/* geen bestand: de gewone hoes */}
  }

  static Future<void> zet(bool ja) async {
    aan.value = ja;
    try {
      await _bestand.writeAsString(jsonEncode({'stapel': ja}));
    } catch (_) {/* niet bewaard: hij geldt nu wel */}
  }
}

/// Stap per hoes naar links en omhoog, en hoeveel elke hoes krimpt, als deel van de hoes ("ruim").
const double kStapelStapX = -.075, kStapelStapY = -.085, kStapelKrimp = .05;

/// Hoeveel hoezen er in beeld staan, de voorste meegeteld.
const int kStapelZichtbaar = 5;

/// Hoe ver de stapel links en boven buiten de voorste hoes uitsteekt, als deel van de hoes.
const double kStapelLinks = (kStapelZichtbaar - 1) * -kStapelStapX - (kStapelZichtbaar - 1) * kStapelKrimp / 2;
const double kStapelBoven = (kStapelZichtbaar - 1) * -kStapelStapY - (kStapelZichtbaar - 1) * kStapelKrimp / 2;

/// Waar een hoes staat. [voorop]: boven alles getekend (de hoes die net wegvliegt, op de heenweg).
typedef StapelPlek = ({double x, double y, double schaal, double dim, double zicht, bool voorop});

/// De plek van een hoes op afstand [d] van de voorste. Tussen -1 en 0 vliegt hij weg: omhoog, en dan
/// achteraan de rij, waar hij verdwijnt. Kleiner dan -1: achteraan, uit het zicht.
StapelPlek stapelPlek(double d, double maat) {
  const achter = kStapelZichtbaar - 1 + .6;
  if (d <= -1) {
    return (
      x: achter * kStapelStapX * maat,
      y: achter * kStapelStapY * maat,
      schaal: 1 - achter * kStapelKrimp,
      dim: .6,
      zicht: 0.0,
      voorop: false,
    );
  }
  if (d < 0) {
    final k = -d;
    return (
      x: k * achter * kStapelStapX * maat,
      y: -math.sin(k * math.pi) * maat * .95 + k * achter * kStapelStapY * maat,
      schaal: 1 - k * achter * kStapelKrimp,
      dim: k * .6,
      zicht: k > .8 ? (1 - k) / .2 : 1.0,
      voorop: k < .5,
    );
  }
  return (
    x: d * kStapelStapX * maat,
    y: d * kStapelStapY * maat,
    schaal: 1 - d * kStapelKrimp,
    dim: math.min(d * .13, .55),
    zicht: d > kStapelZichtbaar - .8 ? 0.0 : 1.0,
    voorop: false,
  );
}

/// Bedient de stapel van buitenaf: de pijltjes van een afstandsbediening.
class StapelBesturing extends ChangeNotifier {
  int _stap = 0;
  int _speel = 0;

  /// Eén stap verder (1) of terug (-1).
  void blader(int richting) {
    _stap += richting;
    notifyListeners();
  }

  /// Speel wat er nu vooraan staat (OK op de afstandsbediening).
  void speel() {
    _speel++;
    notifyListeners();
  }
}

/// De stapel. [voorste] is de hoes zoals Nu speelt hem al tekent (met de cd); [volgende] de hoezen van
/// wat hierna komt, in volgorde. [x]: hoe ver de hoes opzij geschoven is (de cd die uitschuift).
class WachtrijStapel extends StatefulWidget {
  const WachtrijStapel({
    super.key,
    required this.maat,
    required this.voorste,
    required this.volgende,
    required this.onSpeel,
    this.x,
    this.onWeg,
    this.besturing,
    this.terugNa = const Duration(seconds: 4),
    this.hoek = 16,
    double? blok,
  }) : blok = blok ?? maat;

  final double maat;
  final Widget voorste;
  final List<Uint8List?> volgende;

  /// Speel het nummer [stappen] verder in de wachtrij.
  final ValueChanged<int> onSpeel;
  final ValueListenable<double>? x;

  /// Omlaag geveegd terwijl de stapel vooraan stond: Nu speelt sluiten, zoals overal op dit scherm.
  final VoidCallback? onWeg;
  final StapelBesturing? besturing;
  final Duration terugNa;
  final double hoek;

  /// Hoe breed [voorste] is: de hoes plus de ruimte waarin de cd uitschuift.
  final double blok;

  /// Hoe ver je hoogstens bladert.
  static const int maxBladeren = 8;

  @override
  State<WachtrijStapel> createState() => WachtrijStapelState();
}

class WachtrijStapelState extends State<WachtrijStapel> with SingleTickerProviderStateMixin {
  late final AnimationController _blad = AnimationController.unbounded(vsync: this);
  Timer? _terug;
  double _start = 0;
  int _stapGezien = 0, _speelGezien = 0;

  /// Hoe ver er nu gebladerd is; 0 = het spelende nummer vooraan.
  double get blad => _blad.value;

  int get _max => math.min(widget.volgende.length, WachtrijStapel.maxBladeren);

  @override
  void initState() {
    super.initState();
    widget.besturing?.addListener(_opBesturing);
  }

  @override
  void didUpdateWidget(WachtrijStapel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oud = oldWidget;
    if (oud.besturing != widget.besturing) {
      oud.besturing?.removeListener(_opBesturing);
      widget.besturing?.addListener(_opBesturing);
    }
    // Er speelt iets anders (de wachtrij schoof door): weer vooraan beginnen.
    if (!identical(oud.volgende, widget.volgende) && _blad.value > _max) _naar(0, direct: true);
  }

  @override
  void dispose() {
    widget.besturing?.removeListener(_opBesturing);
    _terug?.cancel();
    _blad.dispose();
    super.dispose();
  }

  void _opBesturing() {
    final b = widget.besturing!;
    if (b._stap != _stapGezien) {
      final r = b._stap - _stapGezien;
      _stapGezien = b._stap;
      // Vanaf het DOEL: twee keer snel op de pijl is twee stappen, ook als de eerste nog onderweg is.
      _naar((_doel.round() + r).clamp(0, _max).toDouble());
    }
    if (b._speel != _speelGezien) {
      _speelGezien = b._speel;
      _speelGebladerd();
    }
  }

  /// Waar de stapel naartoe beweegt (of staat).
  double _doel = 0;

  void _naar(double doel, {bool direct = false}) {
    _terug?.cancel();
    _doel = doel;
    if (direct) {
      _blad.value = doel;
    } else {
      _blad.animateTo(doel, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
    if (doel > 0) _terug = Timer(widget.terugNa, () => _naar(0));
  }

  /// Speelt wat er vooraan staat; geeft terug of er iets te spelen viel.
  bool _speelGebladerd() {
    final n = _blad.value.round();
    if (n <= 0) return false;
    _naar(0, direct: true);
    widget.onSpeel(n);
    return true;
  }

  void _sleepBegin(DragStartDetails _) {
    _terug?.cancel();
    _blad.stop();
    _start = _doel = _blad.value;
  }

  void _sleep(DragUpdateDetails d) {
    // Omhoog (een negatieve dy) is verder.
    _blad.value = (_blad.value - d.delta.dy / (widget.maat * .7)).clamp(0.0, _max.toDouble());
  }

  void _sleepEind(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_start == 0 && _blad.value < .15 && v > 320) {
      _naar(0, direct: true);
      widget.onWeg?.call();
      return;
    }
    // Een besliste veeg telt als een hele stap, ook als hij kort was.
    final doel = v < -400
        ? _blad.value.floorToDouble() + 1
        : v > 400
            ? _blad.value.ceilToDouble() - 1
            : _blad.value.roundToDouble();
    _naar(doel.clamp(0, _max).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.maat;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final cache = (m * dpr).round();
    final hoezen = [
      for (var i = 0; i < math.min(widget.volgende.length, WachtrijStapel.maxBladeren + kStapelZichtbaar); i++)
        _Achterhoes(key: ValueKey('stapel-$i'), beeld: widget.volgende[i], maat: m, hoek: widget.hoek, cache: cache),
    ];
    final x = widget.x;
    final stapel = AnimatedBuilder(
      animation: x == null ? _blad : Listenable.merge([_blad, x]),
      builder: (context, _) {
        final b = _blad.value;
        // De hoezen erachter schuiven mee met de voorste hoes, die opzij gaat voor de cd.
        final dx = x?.value ?? 0;
        // Elke laag met zijn afstand tot vooraan: -1 is de spelende hoes (met de cd).
        final lagen = <({int i, double d, StapelPlek p, Widget kind})>[
          (i: -1, d: -b, p: stapelPlek(-b, m), kind: widget.voorste),
          for (var i = 0; i < hoezen.length; i++)
            (i: i, d: i + 1 - b, p: stapelPlek(i + 1 - b, m), kind: hoezen[i]),
        ];
        // Van achter naar voor. Wie wegvliegt staat op de heenweg vooraan en daarna achteraan.
        int diepte(({int i, double d, StapelPlek p, Widget kind}) l) =>
            l.p.voorop ? -1000 : (l.d < 0 ? 1000 : (l.d * 10).round());
        lagen.sort((a, z) => diepte(z).compareTo(diepte(a)));
        return Stack(clipBehavior: Clip.none, children: [
          for (final l in lagen)
            Positioned(
              key: ValueKey('laag-${l.i}'),
              left: 0,
              top: 0,
              child: IgnorePointer(
                // Alleen de spelende hoes vooraan krijgt tikken (omdraaien, uitvergroten); staat er
                // iets anders vooraan, dan is een tik "speel dit" (zie onTap hieronder).
                ignoring: l.i >= 0 || b > .02,
                child: Transform(
                  alignment: Alignment.topLeft,
                  // Schalen rond het midden van de HOES; de voorste is breder (de cd).
                  origin: Offset(m / 2 + (l.i < 0 ? 0 : dx), m / 2),
                  transform: Matrix4.identity()
                    ..translateByDouble(l.p.x + (l.i < 0 ? 0 : dx), l.p.y, 0, 1)
                    ..scaleByDouble(l.p.schaal, l.p.schaal, 1, 1),
                  // Onzichtbaar maar niet weg: de spelende hoes houdt zo zijn draaiende cd. Opacity 0
                  // tekent niets; tussen 0 en 1 komt dat alleen voor tijdens het wegvliegen.
                  child: Opacity(
                    opacity: l.p.zicht.clamp(0.0, 1.0),
                    child: l.i < 0 ? l.kind : _Gedimd(dim: l.p.dim, hoek: widget.hoek, child: l.kind),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
    return GestureDetector(
      key: const ValueKey('wachtrij-stapel'),
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _sleepBegin,
      onVerticalDragUpdate: _sleep,
      onVerticalDragEnd: _sleepEind,
      onTap: _speelGebladerd,
      child: Padding(
        // Ruimte voor wat links en boven uitsteekt.
        padding: EdgeInsets.only(left: m * kStapelLinks, top: m * kStapelBoven),
        child: SizedBox(width: widget.blok, height: m, child: stapel),
      ),
    );
  }
}

/// Een hoes achter de voorste: al gedecodeerd op zijn maat, met afgeronde hoeken.
class _Achterhoes extends StatelessWidget {
  const _Achterhoes({super.key, required this.beeld, required this.maat, required this.hoek, required this.cache});
  final Uint8List? beeld;
  final double maat, hoek;
  final int cache;

  @override
  Widget build(BuildContext context) {
    final b = beeld;
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(hoek),
        child: SizedBox.square(
          dimension: maat,
          child: b == null
              ? const ColoredBox(color: Color(0xFF2A2F3F))
              : Image.memory(b, width: maat, height: maat, fit: BoxFit.cover, cacheWidth: cache, gaplessPlayback: true),
        ),
      ),
    );
  }
}

/// Donkerder naarmate een hoes verder naar achteren staat: een zwart vlak erover, geen filter.
class _Gedimd extends StatelessWidget {
  const _Gedimd({required this.dim, required this.hoek, required this.child});
  final double dim, hoek;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(children: [
        child,
        if (dim > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: dim),
                  borderRadius: BorderRadius.circular(hoek),
                ),
              ),
            ),
          ),
      ]);
}
