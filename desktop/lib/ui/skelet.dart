/// Grijze vlakken in de vorm van wat er komt, in plaats van een draaiend wieltje.
///
/// **Waarom.** De app had 48 spinners en nul skeletten, en overal hetzelfde patroon: een wieltje
/// midden in het inhoudsgebied, en dan in één beeld de volledige inhoud. Op het startscherm staan
/// vier rijen die elk op hun eigen moment binnenkomen, dus schuift alles eronder telkens omlaag —
/// je leest iets en het is weg. Een skelet dat al de goede hoogte heeft laat niets meer verspringen,
/// en het zegt bovendien wát er komt in plaats van alleen dát er iets komt.
///
/// De glans loopt met één controller per skelet en beweegt alleen de gradiënt, niet de layout. Bij
/// een blok van 150 punten is dat goedkoper dan de spinner die het vervangt: die tekent een
/// draaiende boog op elk beeld.
library;

import 'package:flutter/material.dart';

import 'kleuren.dart';

/// Eén grijs blok dat rustig oplicht.
class Skelet extends StatefulWidget {
  const Skelet({
    super.key,
    required this.breedte,
    required this.hoogte,
    this.radius = 10,
  });

  final double breedte;
  final double hoogte;
  final double radius;

  @override
  State<Skelet> createState() => _SkeletState();
}

class _SkeletState extends State<Skelet> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          // Van linksbuiten naar rechtsbuiten, zodat de glans er nooit "staat" maar doorloopt.
          final x = _c.value * 3 - 1.5;
          return Container(
            width: widget.breedte,
            height: widget.hoogte,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(x - .6, 0),
                end: Alignment(x + .6, 0),
                colors: const [kPaneel, kPaneelHoog, kPaneel],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Een tegel zoals in de rijen van het startscherm: hoes, titel, artiest.
class SkeletTegel extends StatelessWidget {
  const SkeletTegel({super.key, this.breedte = 140});

  final double breedte;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: breedte,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skelet(breedte: breedte, hoogte: breedte, radius: 12),
          const SizedBox(height: 9),
          // Niet alle regels even lang: een rij van gelijke blokjes leest als een tabel, niet als
          // een lijst die zo met namen gevuld wordt.
          Skelet(breedte: breedte * .8, hoogte: 11, radius: 4),
          const SizedBox(height: 6),
          Skelet(breedte: breedte * .55, hoogte: 9, radius: 4),
        ],
      ),
    );
  }
}

/// Een hele rij tegels, in de maat die de echte rij ook krijgt.
///
/// [hoogte] moet gelijk zijn aan wat de gevulde rij inneemt — dat is de hele reden dat dit bestaat:
/// als het skelet even hoog is als wat erna komt, verspringt er niets meer.
class SkeletRij extends StatelessWidget {
  const SkeletRij({super.key, this.hoogte = 204, this.tegels = 6, this.tegelbreedte = 140});

  final double hoogte;
  final int tegels;
  final double tegelbreedte;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: hoogte,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: tegels,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, __) => SkeletTegel(breedte: tegelbreedte),
      ),
    );
  }
}
