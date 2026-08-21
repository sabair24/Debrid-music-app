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
import 'maten.dart';
import 'tegel.dart';

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
          Skelet(breedte: breedte, hoogte: breedte, radius: kHoek12),
          const SizedBox(height: kRuimte8),
          // Niet alle regels even lang: een rij van gelijke blokjes leest als een tabel, niet als
          // een lijst die zo met namen gevuld wordt.
          Skelet(breedte: breedte * .8, hoogte: 11, radius: kHoek4),
          const SizedBox(height: kRuimte6),
          Skelet(breedte: breedte * .55, hoogte: 9, radius: kHoek4),
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
  const SkeletRij({super.key, this.hoogte, this.tegels = 6, this.tegelbreedte = kTegelHoes});

  /// Leeg laten betekent: vul de hoogte die je krijgt.
  ///
  /// Dat is sinds ronde 1 het gewone geval — de sectie zet er `hoogteVanTegelrij()` omheen, en dan
  /// zou een eigen getal hier precies de verspringing terugbrengen die dit skelet moet voorkomen.
  final double? hoogte;
  final int tegels;
  final double tegelbreedte;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: hoogte,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: kGoot),
        itemCount: tegels,
        separatorBuilder: (_, __) => const SizedBox(width: kRuimte12),
        itemBuilder: (_, __) => SkeletTegel(breedte: tegelbreedte),
      ),
    );
  }
}

/// Een raster skelettegels, in de vorm van het albumraster.
///
/// **Waarom dit naast [SkeletRij] bestaat.** Albums en Artiesten toonden tijdens het inlezen één
/// wieltje midden op een leeg scherm. Dat zegt alleen DÁT er iets komt; het zegt niet dat er een
/// raster met hoezen komt, en het neemt een heel andere hoogte in dan wat erna verschijnt — dus
/// springt het scherm op het moment dat de bibliotheek binnen is.
///
/// De maten zijn dezelfde als die van het echte raster in `main.dart`: 190 breed, verhouding .78.
/// Loopt dat uiteen, dan verspringt het weer, en dan is dit een mooiere manier om hetzelfde
/// probleem te houden.
class SkeletRaster extends StatelessWidget {
  const SkeletRaster({super.key, this.tegels = 12});

  final int tegels;

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(kGoot, 0, kGoot, kGoot),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 20,
          crossAxisSpacing: 20,
          childAspectRatio: .78,
        ),
        itemCount: tegels,
        itemBuilder: (_, __) => LayoutBuilder(
          builder: (_, c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skelet(breedte: c.maxWidth, hoogte: c.maxWidth, radius: kHoek12),
              const SizedBox(height: kRuimte8),
              Skelet(breedte: c.maxWidth * .8, hoogte: 11, radius: kHoek4),
              const SizedBox(height: kRuimte6),
              Skelet(breedte: c.maxWidth * .55, hoogte: 9, radius: kHoek4),
            ],
          ),
        ),
      );
}

/// Een lijst skeletregels, in de vorm van een nummerlijst.
///
/// Dezelfde marges en dezelfde hoogte als `TrackRow`, om dezelfde reden als hierboven: wat erna komt
/// mag niet verspringen.
class SkeletLijst extends StatelessWidget {
  const SkeletLijst({super.key, this.regels = 10});

  final int regels;

  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: kRuimte8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: regels,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGoot, vertical: kRuimte2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kRuimte12, vertical: kRuimte12),
            child: Row(
              children: [
                const Skelet(breedte: 14, hoogte: 11, radius: kHoek4),
                const SizedBox(width: kRuimte12),
                // Niet alle regels even lang: gelijke blokjes lezen als een tabel in plaats van als
                // een lijst die zo met titels gevuld wordt. Het patroon herhaalt per vier, zodat
                // twee regels onder elkaar nooit toevallig dezelfde lengte krijgen.
                Skelet(breedte: 120 + (i % 4) * 46, hoogte: 12, radius: kHoek4),
                const Spacer(),
                const Skelet(breedte: 30, hoogte: 10, radius: kHoek4),
              ],
            ),
          ),
        ),
      );
}
