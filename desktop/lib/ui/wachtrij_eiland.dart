/// Het nummer dat nu speelt, in de wachtrij: een glazen eiland (Saber, 18-10-2026: "spelend nummer =
/// glazen eiland met een licht gekantelde hoes en een kleine draaiende plaat").
///
/// **Waarom een eiland.** De wachtrij heeft drie zones — wat al speelde, wat nu speelt, wat komt — en
/// het middelste stuk was een paars getint kaartje dat er net zo uitzag als een geselecteerde regel.
/// Een eiland van glas dat een tikje boven het paneel ligt, met een hoes die naar je toe kantelt en
/// een plaatje dat erachter vandaan draait, is in één oogopslag "dit hoor je nu".
///
/// **Wat het kost.** Het plaatje draait met [LangzameDraai], dezelfde draai als de cd in Nu speelt:
/// op een telefoon hooguit 60 beelden per seconde, gemeten zuinig. Het draait alleen als er muziek
/// speelt, niet op een tv (de Shield betaalt elke lus), en niet als het toestel om minder beweging
/// vraagt. Glas in het glazen paneel is een vulling, geen tweede vervaging ([GlasVlak]).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../tv.dart';
import 'getekende_schijf.dart';
import 'glas.dart';
import 'kleuren.dart';
import 'langzame_draai.dart';

/// Hoeveel de hoes kantelt, in radialen: zes graden (Saber: "kantelen ±6°").
const double kEilandKanteling = 6 * math.pi / 180;

/// Hoe lang één omwenteling van het plaatje duurt: als de cd in Nu speelt.
const Duration kEilandOmwenteling = Duration(seconds: 9);

class WachtrijEiland extends StatefulWidget {
  const WachtrijEiland({
    super.key,
    required this.hoes,
    required this.speelt,
    required this.child,
    this.maat = 52,
  });

  /// De hoes, of null: dan een leeg vak met een noot.
  final Uint8List? hoes;

  /// Speelt er muziek? Dan draait het plaatje.
  final bool speelt;

  /// Titel, artiest en de balkjes: rechts van de hoes.
  final Widget child;

  /// Hoe groot de hoes is.
  final double maat;

  @override
  State<WachtrijEiland> createState() => _WachtrijEilandState();
}

class _WachtrijEilandState extends State<WachtrijEiland> with SingleTickerProviderStateMixin {
  late final LangzameDraai _draai = LangzameDraai(this,
      omwenteling: kEilandOmwenteling,
      maxBeeldenPerSeconde: Platform.isWindows || Platform.isMacOS || Platform.isLinux ? 1000 : 60);

  bool _magDraaien(BuildContext context) => widget.speelt && !isTv && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _zet();
  }

  @override
  void didUpdateWidget(WachtrijEiland oud) {
    super.didUpdateWidget(oud);
    _zet();
  }

  void _zet() => _magDraaien(context) ? _draai.start() : _draai.stop();

  @override
  void dispose() {
    _draai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.maat;
    final plaat = m * .88;
    final hoes = widget.hoes;
    final beeld = hoes != null
        ? Image.memory(hoes, width: m, height: m, cacheWidth: (m * 3).round(), fit: BoxFit.cover, gaplessPlayback: true)
        : ColoredBox(
            color: kPaneelHoog,
            child: SizedBox(width: m, height: m, child: Icon(Icons.music_note_rounded, size: m * .38, color: kGedempt)),
          );
    return Container(
      key: const ValueKey('wachtrij-eiland'),
      margin: const EdgeInsets.symmetric(horizontal: 10),
      // Een haarfijne paarse rand: het eiland hoort bij wat er nu klinkt, zoals de pil in het menu.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAccent.withValues(alpha: .30)),
      ),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: Thema.licht ? .10 : .30), blurRadius: 14, offset: const Offset(0, 4)),
      ]),
      child: GlasVlak(
        vorm: const BorderRadius.all(Radius.circular(14)),
        kleur: kBovenop,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            SizedBox(
              width: m + plaat * .42,
              height: m,
              child: Stack(clipBehavior: Clip.none, children: [
                // Het plaatje, half achter de hoes vandaan.
                Positioned(
                  left: m - plaat * .56,
                  top: (m - plaat) / 2,
                  // Twee grenzen: de buitenste houdt het draaien binnen dit vakje, de binnenste bewaart
                  // de getekende plaat, zodat elke tik hem alleen draait en niet opnieuw tekent.
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      key: const ValueKey('wachtrij-plaatje'),
                      animation: _draai,
                      builder: (_, kind) => Transform.rotate(angle: _draai.value * 2 * math.pi, child: kind),
                      child: RepaintBoundary(
                        child: SizedBox.square(dimension: plaat, child: const CustomPaint(painter: EilandPlaat())),
                      ),
                    ),
                  ),
                ),
                // De glans erover draait niet mee: het licht komt uit de kamer, niet van de plaat.
                Positioned(
                  left: m - plaat * .56,
                  top: (m - plaat) / 2,
                  child: CdGlans(maat: plaat, vinyl: true),
                ),
                // De hoes, licht naar je toe gekanteld: de linkerkant komt naar voren.
                Transform(
                  key: const ValueKey('wachtrij-hoes'),
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .0016)
                    ..rotateY(kEilandKanteling),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 8, offset: Offset(2, 3))],
                    ),
                    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: beeld),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(child: widget.child),
          ]),
        ),
      ),
    );
  }
}

/// Een zwart plaatje met groeven (de glans ligt erboven en staat stil, [CdGlans]). Het etiket is het paars van de app:
/// het hoesje ligt er al naast, twee keer dezelfde hoes zou druk zijn.
class EilandPlaat extends CustomPainter {
  const EilandPlaat();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-.3, -.35),
            radius: .95,
            colors: [Color(0xFF2B2E36), Color(0xFF111216), Color(0xFF060607)],
            stops: [0, .5, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)));
    // Groeven: dunne ringen, om en om een fractie lichter.
    final groef = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.5, r * .012);
    for (var i = 0; i < 9; i++) {
      final rr = r * (.42 + i * .062);
      groef.color = Color.fromRGBO(255, 255, 255, i.isEven ? .07 : .035);
      canvas.drawCircle(c, rr, groef);
    }
    // Het etiket en het gat.
    canvas.drawCircle(c, r * .34, Paint()..color = const Color(0xFF7C5CFF));
    canvas.drawCircle(c, r * .34, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.5, r * .02)
      ..color = const Color(0x33000000));
    canvas.drawCircle(c, r * .05, Paint()..color = const Color(0xFF060607));
  }

  @override
  bool shouldRepaint(EilandPlaat oud) => false;
}
