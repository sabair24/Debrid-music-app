/// De knoppen die bewegen (Saber, 17-10-2026): afspelen vervormt tot pauze, het hart klopt met
/// deeltjes, shuffle en herhalen bewegen als je ze aanzet, vorige en volgende schieten even opzij, en
/// de titel in de spelerbalk schuift weg voor de nieuwe.
///
/// **Waarom losse widgets.** Ze staan op drie plekken (de spelerbalk van de pc, de balk van de gsm en
/// Nu speelt), en die zijn zonder toestand gebouwd: een beweging heeft een klok nodig, en die hoort bij
/// de knop zelf. Elke widget kijkt alleen naar zijn eigen stand ([didUpdateWidget]) en speelt als die
/// verandert; de schermen eromheen hoeven niets bij te houden.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'menu_iconen.dart';

/// Het driehoekje dat vloeiend overgaat in de twee streepjes, en terug.
class SpeelPauzeIcoon extends StatefulWidget {
  const SpeelPauzeIcoon({super.key, required this.speelt, this.maat = 24, this.kleur});

  final bool speelt;
  final double maat;
  final Color? kleur;

  @override
  State<SpeelPauzeIcoon> createState() => _SpeelPauzeIcoonState();
}

class _SpeelPauzeIcoonState extends State<SpeelPauzeIcoon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.speelt ? 1 : 0,
  );

  @override
  void didUpdateWidget(SpeelPauzeIcoon oud) {
    super.didUpdateWidget(oud);
    if (widget.speelt != oud.speelt) widget.speelt ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedIcon(
        icon: AnimatedIcons.play_pause,
        progress: CurvedAnimation(parent: _c, curve: Curves.easeInOut),
        size: widget.maat,
        color: widget.kleur,
        semanticLabel: widget.speelt ? 'Pauzeren' : 'Afspelen',
      );
}

/// Het hart: vol als het een favoriet is. Wordt het er een, dan klopt het twee keer en springen er
/// kleine deeltjes uit.
class HartIcoon extends StatefulWidget {
  const HartIcoon({super.key, required this.aan, this.maat = 22, this.kleurAan = kHartKleur, this.kleurUit});

  final bool aan;
  final double maat;
  final Color kleurAan;
  final Color? kleurUit;

  @override
  State<HartIcoon> createState() => _HartIcoonState();
}

/// Het rood van een favoriet.
const kHartKleur = Color(0xFFFF5C8A);

class _HartIcoonState extends State<HartIcoon> with SingleTickerProviderStateMixin {
  late final AnimationController _vonk =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 560), value: 1);

  @override
  void didUpdateWidget(HartIcoon oud) {
    super.didUpdateWidget(oud);
    if (widget.aan && !oud.aan) _vonk.forward(from: 0);
  }

  @override
  void dispose() {
    _vonk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uit = widget.kleurUit ?? IconTheme.of(context).color ?? const Color(0xFF8A8FA3);
    return SizedBox.square(
      dimension: widget.maat,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _vonk,
                builder: (_, __) => CustomPaint(
                  painter: _Vonken(t: _vonk.value, kleur: widget.kleurAan),
                ),
              ),
            ),
          ),
          MenuIcoon(
            soort: MenuIcoonSoort.favorieten,
            kleur: widget.aan ? widget.kleurAan : uit,
            gekozen: widget.aan,
            maat: widget.maat,
          ),
        ],
      ),
    );
  }
}

/// Acht deeltjes die uit het hart springen en uitdoven. Op [t] = 1 is er niets meer.
class _Vonken extends CustomPainter {
  _Vonken({required this.t, required this.kleur});

  final double t;
  final Color kleur;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final midden = size.center(Offset.zero);
    final ver = size.width * (.35 + .55 * Curves.easeOutCubic.transform(t));
    final dek = (1 - t).clamp(0.0, 1.0);
    final straal = size.width * .07 * (1 - t * .6);
    for (var i = 0; i < 8; i++) {
      final hoek = i * math.pi / 4 - math.pi / 2;
      final p = midden + Offset(math.cos(hoek), math.sin(hoek)) * ver;
      canvas.drawCircle(
          p,
          straal * (i.isEven ? 1 : .7),
          Paint()..color = (i.isEven ? kleur : const Color(0xFFFFC2D4)).withValues(alpha: dek));
    }
  }

  @override
  bool shouldRepaint(_Vonken oud) => oud.t != t || oud.kleur != kleur;
}

/// Shuffle: gaat hij aan, dan klapt het icoon even om (de pijlen kruisen elkaar).
class ShuffleIcoon extends StatefulWidget {
  const ShuffleIcoon({super.key, required this.aan, this.maat = 22, this.kleur});

  final bool aan;
  final double maat;
  final Color? kleur;

  @override
  State<ShuffleIcoon> createState() => _ShuffleIcoonState();
}

class _ShuffleIcoonState extends State<ShuffleIcoon> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420), value: 1);

  @override
  void didUpdateWidget(ShuffleIcoon oud) {
    super.didUpdateWidget(oud);
    if (widget.aan != oud.aan) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, kind) {
          // Van 1 via -1 terug naar 1: het icoon klapt om zijn verticale as.
          final x = math.cos(Curves.easeInOut.transform(_c.value) * math.pi * 2);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(x.abs() < .08 ? .08 * x.sign : x, 1, 1),
            child: kind,
          );
        },
        child: Icon(Icons.shuffle_rounded, size: widget.maat, color: widget.kleur),
      );
}

/// Herhalen: elke wissel draait het icoon een slag.
class HerhaalIcoon extends StatefulWidget {
  const HerhaalIcoon({super.key, required this.stand, required this.icoon, this.maat = 22, this.kleur});

  /// Elke andere waarde is een wissel (uit, alles, één).
  final Object stand;
  final IconData icoon;
  final double maat;
  final Color? kleur;

  @override
  State<HerhaalIcoon> createState() => _HerhaalIcoonState();
}

class _HerhaalIcoonState extends State<HerhaalIcoon> {
  var _slagen = 0.0;

  @override
  void didUpdateWidget(HerhaalIcoon oud) {
    super.didUpdateWidget(oud);
    if (widget.stand != oud.stand) _slagen += 1;
  }

  @override
  Widget build(BuildContext context) => AnimatedRotation(
        turns: _slagen,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutBack,
        child: Icon(widget.icoon, size: widget.maat, color: widget.kleur),
      );
}

/// Een knop met een icoon dat even opzij schiet als je drukt: vorige naar links, volgende naar rechts.
class DuwKnop extends StatefulWidget {
  const DuwKnop({
    super.key,
    required this.icoon,
    required this.onPressed,
    this.richting = 1,
    this.maat,
    this.kleur,
    this.style,
    this.tooltip,
  });

  final IconData icoon;
  final VoidCallback? onPressed;

  /// 1 = naar rechts (volgende), -1 = naar links (vorige).
  final double richting;
  final double? maat;
  final Color? kleur;
  final ButtonStyle? style;
  final String? tooltip;

  @override
  State<DuwKnop> createState() => _DuwKnopState();
}

class _DuwKnopState extends State<DuwKnop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final druk = widget.onPressed;
    return IconButton(
      tooltip: widget.tooltip,
      iconSize: widget.maat,
      color: widget.kleur,
      style: widget.style,
      onPressed: druk == null
          ? null
          : () {
              _c.forward(from: 0);
              druk();
            },
      icon: AnimatedBuilder(
        animation: _c,
        builder: (_, kind) => Transform.translate(
          // Snel opzij en met een veer terug.
          offset: Offset(widget.richting * 6 * math.sin(math.pi * _c.value) * (1 - _c.value * .5), 0),
          child: kind,
        ),
        child: Icon(widget.icoon, size: widget.maat),
      ),
    );
  }
}

/// Tekst die wegschuift voor nieuwe tekst: de titel en de artiest in de spelerbalk bij een ander
/// nummer. [sleutel] is wat "een ander nummer" betekent (het pad).
class SchuifTekst extends StatelessWidget {
  const SchuifTekst({super.key, required this.sleutel, required this.child});

  final Object? sleutel;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (nu, vorige) => Stack(
          alignment: Alignment.centerLeft,
          children: [...vorige, if (nu != null) nu],
        ),
        transitionBuilder: (kind, a) {
          final binnen = kind.key == ValueKey(sleutel);
          return ClipRect(
            child: SlideTransition(
              position: Tween(begin: Offset(binnen ? .35 : -.35, 0), end: Offset.zero).animate(a),
              child: FadeTransition(opacity: a, child: kind),
            ),
          );
        },
        child: KeyedSubtree(key: ValueKey(sleutel), child: child),
      );
}
