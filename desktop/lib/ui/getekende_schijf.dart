/// De plaat die uit de hoes komt als er geen scan van de schijf is (Saber, 18-10-2026).
///
/// **Vinyl alleen als de uitgave vinyl is.** Een zwarte plaat met groeven en de hoes als etiket. Voor
/// al het andere — en als het formaat niet bekend is — een zilveren cd met de hoes als bedrukking in
/// het midden. Een echte scan wordt nooit vervangen of overgeschilderd: dit is alleen de terugval.
///
/// **De glans van een cd draait niet mee.** Op een echte cd die draait staat de regenboog stil: hij
/// komt van het licht in de kamer, niet van de schijf. Daarom is [CdGlans] een eigen laag BOVEN de
/// draaiende schijf, die met het uitschuiven meeschuift maar niet meedraait. De schijf zelf is één
/// keer getekend (een vaste afbeelding in een [RepaintBoundary]) en draait als transform; de glans
/// is een verloop dat nooit opnieuw getekend hoeft te worden.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Hoe groot het etiket is, als deel van de schijf. Op een echte cd is het bedrukte vlak ongeveer 46
/// van de 120 mm; iets kleiner leest hier beter, want het is een hoes en geen ronde bedrukking.
const double kSchijfEtiket = .34;

/// Is dit formaat (zoals Discogs of MusicBrainz het noemt) vinyl? `Vinyl`, `12" Vinyl`, `LP`…
bool isVinylFormaat(String? formaat) {
  final f = (formaat ?? '').toLowerCase();
  if (f.isEmpty) return false;
  return f.contains('vinyl') || RegExp(r'\blp\b').hasMatch(f) || f.contains('shellac') || f.contains('lathe');
}

/// Een zilveren cd met de hoes als bedrukking in het midden.
class GetekendeCd extends StatelessWidget {
  const GetekendeCd({super.key, required this.label, required this.maat});
  final Uint8List label;
  final double maat;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: maat,
        child: Stack(alignment: Alignment.center, children: [
          const CustomPaint(size: Size.infinite, painter: _CdSchilder()),
          ClipOval(
            child: Image.memory(label,
                width: maat * kSchijfEtiket,
                height: maat * kSchijfEtiket,
                fit: BoxFit.cover,
                cacheWidth: (maat * kSchijfEtiket * 2).round().clamp(32, 800),
                errorBuilder: (_, __, ___) => const SizedBox()),
          ),
          // Het gat in het midden.
          Container(
            width: maat * .06,
            height: maat * .06,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0A0B0E)),
          ),
        ]),
      );
}

class _CdSchilder extends CustomPainter {
  const _CdSchilder();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final vak = Rect.fromCircle(center: c, radius: r);
    // Zilver: licht naar het midden, een tikje donkerder aan de rand.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFE9ECF1), Color(0xFFC9CED8), Color(0xFFAEB4C0)],
            stops: [0, .7, 1],
          ).createShader(vak));
    // De doorzichtige ring rond het gat, en de rand.
    canvas.drawCircle(c, r * .2, Paint()..color = const Color(0x33FFFFFF));
    canvas.drawCircle(
        c,
        r * .995,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.6, r * .012)
          ..color = const Color(0x55000000));
    // Fijne sporen: het oppervlak van een cd is niet glad.
    final spoor = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.4, r * .004);
    for (var i = 0; i < 14; i++) {
      spoor.color = Color.fromRGBO(255, 255, 255, i.isEven ? .10 : .05);
      canvas.drawCircle(c, r * (.38 + i * .043), spoor);
    }
  }

  @override
  bool shouldRepaint(_CdSchilder oud) => false;
}

/// De glans over een getekende schijf: staat stil terwijl de schijf eronder draait. Op een cd de
/// regenboog en een lichtveeg; op vinyl twee zachte wiggen licht in de groeven, zoals een plaat op
/// een draaitafel het licht van de lamp vangt.
class CdGlans extends StatelessWidget {
  const CdGlans({super.key, required this.maat, this.vinyl = false});
  final double maat;
  final bool vinyl;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: SizedBox.square(
            key: const ValueKey('cd-glans'),
            dimension: maat,
            child: CustomPaint(painter: vinyl ? const _VinylGlansSchilder() : const _GlansSchilder()),
          ),
        ),
      );
}

class _GlansSchilder extends CustomPainter {
  const _GlansSchilder();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final vak = Rect.fromCircle(center: c, radius: r);
    // Alleen op het zilver: niet op het etiket en niet buiten de schijf.
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(vak)
      ..addOval(Rect.fromCircle(center: c, radius: r * kSchijfEtiket / 2 * 1.02));
    canvas.save();
    canvas.clipPath(ring);
    // De regenboog: twee keer rond, zacht, zoals licht in de sporen breekt. Gewoon erover gelegd en
    // niet met een menging als zachtlicht: zo'n menging leest de draaiende schijf eronder elk beeld
    // terug, en zonder framebuffer-fetch is dat een kopie van dat stuk scherm per beeld. Op de Shield
    // ging de glasproef van 16,8 naar 7,3 ms toen dit samen met twee andere dingen veranderde (18-10-2026).
    canvas.drawRect(
        vak,
        Paint()
          ..shader = const SweepGradient(
            startAngle: 0,
            endAngle: math.pi * 2,
            colors: [
              Color(0x00FF4D6D), Color(0x2EFF4D6D), Color(0x2EFFD23F), Color(0x2E45E08F),
              Color(0x2E35C8FF), Color(0x2E8A5CFF), Color(0x00FF4D6D),
              Color(0x2EFF4D6D), Color(0x2EFFD23F), Color(0x2E45E08F), Color(0x2E35C8FF), Color(0x2E8A5CFF),
              Color(0x00FF4D6D),
            ],
          ).createShader(vak));
    // Een smalle veeg wit licht schuin over de schijf.
    canvas.drawRect(
        vak,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment(-1, -1),
            end: Alignment(1, 1),
            colors: [Color(0x00FFFFFF), Color(0x59FFFFFF), Color(0x00FFFFFF)],
            stops: [.40, .48, .56],
          ).createShader(vak));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlansSchilder oud) => false;
}

class _VinylGlansSchilder extends CustomPainter {
  const _VinylGlansSchilder();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final vak = Rect.fromCircle(center: c, radius: r);
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(vak.deflate(r * .02))
      ..addOval(Rect.fromCircle(center: c, radius: r * kSchijfEtiket / 2 * 1.02));
    canvas.save();
    canvas.clipPath(ring);
    canvas.drawRect(
        vak,
        Paint()
          ..shader = const SweepGradient(
            startAngle: -math.pi / 4,
            endAngle: math.pi * 7 / 4,
            colors: [Color(0x00FFFFFF), Color(0x24FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x18FFFFFF), Color(0x00FFFFFF)],
            stops: [0, .06, .12, .5, .56, .62],
          ).createShader(vak));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VinylGlansSchilder oud) => false;
}

/// Een zwarte plaat met groeven en de hoes als etiket.
class GetekendVinyl extends StatelessWidget {
  const GetekendVinyl({super.key, required this.label, required this.maat});
  final Uint8List label;
  final double maat;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: maat,
        child: Stack(alignment: Alignment.center, children: [
          const CustomPaint(size: Size.infinite, painter: _VinylSchilder()),
          ClipOval(
            child: Image.memory(label,
                width: maat * kSchijfEtiket,
                height: maat * kSchijfEtiket,
                fit: BoxFit.cover,
                cacheWidth: (maat * kSchijfEtiket * 2).round().clamp(32, 800),
                errorBuilder: (_, __, ___) => const SizedBox()),
          ),
          Container(
            width: maat * .025,
            height: maat * .025,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF060607)),
          ),
        ]),
      );
}

class _VinylSchilder extends CustomPainter {
  const _VinylSchilder();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final vak = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-.24, -.36),
            radius: .92,
            colors: [Color(0xFF2B2E36), Color(0xFF111216), Color(0xFF060607)],
            stops: [0, .5, 1],
          ).createShader(vak));
    final groef = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.4, r * .006);
    for (var i = 0; i < 26; i++) {
      groef.color = Color.fromRGBO(255, 255, 255, i % 3 == 0 ? .07 : .03);
      canvas.drawCircle(c, r * (.36 + i * .024), groef);
    }
  }

  @override
  bool shouldRepaint(_VinylSchilder oud) => false;
}
