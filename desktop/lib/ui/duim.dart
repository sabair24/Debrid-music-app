/// De duim: houden of weg.
///
/// **De eerste geanimeerde schakelaar in deze app.** Het hartje is een kale `IconButton` — aan of uit,
/// en verder gebeurt er niets. Bij een duim mag dat niet, en dat is geen smaakkwestie: rood is de enige
/// knop in deze app die een bestand van je schijf haalt. Een knop met dat gevolg hoort te BEVESTIGEN
/// dat hij geraakt is, anders tik je nog eens omdat je niet zeker weet of het aankwam.
///
/// Wat er in 170 milliseconden gebeurt — [kGebaar], dezelfde duur als elk ander gebaar in de app:
///
/// * de knop krimpt naar 0,94 zodra je vinger neerkomt (dat deel loopt op [kSnel], want indrukken
///   hoort onmiddellijk te voelen);
/// * bij het loslaten springt hij naar 1,18 en kantelt een graad of negen mee met de duim, en zakt
///   dan terug — één boog (`sin` over de duur, met de piek vroeg door `Curves.easeOut`), zodat het
///   voelt als een tik en niet als een schuif die op en neer gaat;
/// * de kleur vult van omtrek naar vlak;
/// * de ándere duim dooft naar 26 procent, zodat te zien is dat er gekozen is en niet alleen dat er
///   iets aan staat.
///
/// De maten zijn twee: groot op het speelscherm, klein in de radiorij. Eén widget met een maat als
/// parameter en geen twee widgets — dan zou er één achterblijven zodra de beweging bijgesteld wordt.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kleuren.dart';
import 'maten.dart';

/// Welke kant deze duim op wijst.
enum Duimkant { omhoog, omlaag }

/// Rood en groen, en waarom ze hier staan en niet in `kleuren.dart`.
///
/// Ze zijn geen laag in de kleurenladder — die gaat over hoe ver iets van de achtergrond af ligt, en
/// dat is hier niet aan de orde. Dit zijn OORDEELkleuren: ze betekenen iets, net als het amber van een
/// mislukte download. Zusjes van [kAccent2] in dezelfde chroma, zodat ze bij de app horen in plaats van
/// eruit te springen als de standaardkleuren van een systeem.
const Color kHouden = Color(0xFF00D48C);
const Color kWeg = Color(0xFFFF4E63);

class Duim extends StatefulWidget {
  const Duim({
    super.key,
    required this.kant,
    required this.aan,
    required this.opTik,
    this.gedempt = false,
    this.maat = 62,
    this.bijschrift,
  });

  final Duimkant kant;

  /// Staat deze duim aan? Dan is hij gevuld in plaats van omlijnd.
  final bool aan;

  /// Is er voor de ANDERE duim gekozen? Dan dooft deze.
  final bool gedempt;

  final VoidCallback opTik;

  /// 62 op het speelscherm, 28 in de rij. Alles daartussen schaalt mee.
  final double maat;

  /// Wat eronder staat. Alleen op het speelscherm; in een rij is daar geen plek voor.
  final String? bijschrift;

  Color get kleur => kant == Duimkant.omhoog ? kHouden : kWeg;

  @override
  State<Duim> createState() => _DuimState();
}

class _DuimState extends State<Duim> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: kGebaar);
  bool _ingedrukt = false;

  @override
  void didUpdateWidget(covariant Duim oud) {
    super.didUpdateWidget(oud);
    // Alleen bij AANgaan. Uitzetten is een correctie — "ik vond er toch niets van" — en die hoort
    // niet gevierd te worden met dezelfde sprong als het kiezen zelf.
    if (widget.aan && !oud.aan) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kleur = widget.kleur;
    final m = widget.maat;
    final knop = AnimatedBuilder(
      animation: _c,
      builder: (context, kind) {
        // Eén boog omhoog en weer terug: sin(pi·t) is 0 aan het begin, 1 halverwege en 0 aan het
        // eind. Zo is er geen tweede controller nodig voor de terugweg. De `easeOut` eronder trekt de
        // piek naar voren, waardoor het als een TIK voelt en niet als een schuif die op en neer gaat.
        final boog = _c.value == 0 ? 0.0 : math.sin(math.pi * Curves.easeOut.transform(_c.value));
        final schaal = (_ingedrukt ? .94 : 1.0) + boog * .18;
        final draai = boog * (widget.kant == Duimkant.omhoog ? .16 : -.16);
        return Transform.rotate(
          angle: draai,
          child: Transform.scale(scale: schaal, child: kind),
        );
      },
      child: AnimatedOpacity(
        duration: kGebaar,
        opacity: widget.gedempt ? .26 : 1,
        child: AnimatedContainer(
          duration: kSnel,
          width: m,
          height: m,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.aan ? kleur : (_ingedrukt ? kVerzonken : kPaneel),
            border: Border.all(
              color: widget.aan ? kleur : kleur.withValues(alpha: .34),
              width: m >= 40 ? 1.5 : 1,
            ),
            boxShadow: widget.aan && m >= 40
                ? [BoxShadow(color: kleur.withValues(alpha: .30), blurRadius: 26, offset: const Offset(0, 10))]
                : kGeenSchaduw,
          ),
          child: Icon(
            widget.kant == Duimkant.omhoog
                ? (widget.aan ? Icons.thumb_up_rounded : Icons.thumb_up_outlined)
                : (widget.aan ? Icons.thumb_down_rounded : Icons.thumb_down_outlined),
            size: m * .44,
            // Op een gevulde knop moet het teken van de ACHTERGROND afsteken, niet van de kleur.
            color: widget.aan ? kAchtergrond : kleur,
          ),
        ),
      ),
    );

    final bijschrift = widget.bijschrift;
    return Semantics(
      button: true,
      selected: widget.aan,
      label: bijschrift ?? (widget.kant == Duimkant.omhoog ? 'Houden' : 'Weg'),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _ingedrukt = true),
        onTapCancel: () => setState(() => _ingedrukt = false),
        onTap: () {
          setState(() => _ingedrukt = false);
          widget.opTik();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            knop,
            if (bijschrift != null) ...[
              const SizedBox(height: kRuimte6),
              Text(bijschrift,
                  style: TextStyle(
                      fontSize: 11, color: widget.aan ? kleur : kGedempt, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
