/// Eén oppervlak, overal hetzelfde.
///
/// **Waarom dit bestand er is.** Een telling: 94 vlakken in de app, negen met een schaduw, waarvan
/// vijf alleen bij muisaanwijzing. In rúst heeft dus vrijwel niets in deze app diepte — een kaart
/// ligt niet op de pagina, hij ís de pagina. En op een bijna zwarte achtergrond helpt "er een
/// zwarte schaduw onder zetten" ook maar half: zwart op zwart is niets.
///
/// Diepte moet daar uit het oppervlak zelf komen: een vulling die bovenaan lichter is dan onderaan
/// (zo vangt een vlak licht), plus een haarfijne lichte bovenrand, plus een schaduw die het optilt.
///
/// **De app bewijst dat zelf al.** `glassSurface` in `main.dart` is het enige element met echte
/// diepte, en het recept is precies dat — het eigen commentaar daar zegt: *"Laat er één van weg en
/// het wordt een grijze rechthoek met ronde hoeken."* Dit bestand maakt dat recept algemeen, met
/// dezelfde tv-uitweg die `glassSurface` al documenteert.
library;

import 'package:flutter/material.dart';

import '../tv.dart';
import 'kleuren.dart';
import 'maten.dart';

/// Hoe ver iets van de achtergrond af ligt.
enum Niveau {
  /// Naar binnen: een zoekveld, een voortgangsbaan, de goot achter een lijst.
  verzonken,

  /// De gewone kaart, rij of paneel.
  paneel,

  /// Aangewezen, gemarkeerd, geopend, actief.
  hoog,

  /// Wat óver de app heen ligt: een menu, een blad, een dialoog.
  bovenop,
}

/// De kale kleur van een niveau, zonder verloop of rand.
Color kleurVan(Niveau niveau) => switch (niveau) {
      Niveau.verzonken => kVerzonken,
      Niveau.paneel => kPaneel,
      Niveau.hoog => kPaneelHoog,
      Niveau.bovenop => kBovenop,
    };

/// De schaduw die bij een niveau hoort als er niets anders gevraagd wordt.
List<BoxShadow> schaduwVan(Niveau niveau) => switch (niveau) {
      Niveau.verzonken => kGeenSchaduw,
      Niveau.paneel => kSchaduw1,
      Niveau.hoog => kSchaduw2,
      Niveau.bovenop => kSchaduw3,
    };

/// Het oppervlak van een paneel: verloop, rand, schaduw.
///
/// [plat] is de tv-uitweg, en hij staat er om dezelfde reden als in `glassSurface`: een verloop plus
/// twee schaduwlagen op élke tegel van een liggende rij kost beelden op de Tegra X1 van een Shield,
/// en van drie meter afstand is het verschil met een platte vulling er toch niet. Standaard volgt
/// hij [isTv]; een toets kan hem los zetten en hoeft daarvoor geen televisie te simuleren.
///
/// **De lichte bovenrand zit in het verloop en niet in de rand.** Flutter weigert een `Border` met
/// verschillende zijden zodra er een `borderRadius` bij staat ("A borderRadius can only be given for
/// a uniform Border") — dus is de eerste stop van het verloop een tikje wit in plaats van de
/// bovenzijde van de rand. Het oog ziet hetzelfde; het is alleen niet de plek waar je het zou zoeken.
BoxDecoration paneelDecoratie(
  Niveau niveau, {
  double radius = kHoek12,
  bool rand = true,
  List<BoxShadow>? schaduw,
  Color? rondom,
  bool? plat,
}) {
  final basis = kleurVan(niveau);
  final randkleur = rondom ?? (niveau == Niveau.verzonken ? kLijnZacht : kLijn);
  final border = rand ? Border.all(color: randkleur) : null;
  final hoeken = BorderRadius.circular(radius);

  if (plat ?? isTv) {
    return BoxDecoration(color: basis, borderRadius: hoeken, border: border);
  }

  // Verzonken loopt andersom: donkerder bovenaan is wat een gat een gat maakt.
  final omhoog = niveau == Niveau.verzonken;
  return BoxDecoration(
    borderRadius: hoeken,
    border: border,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: omhoog
          ? [_meng(basis, Colors.black, .22), basis]
          : [_meng(basis, Colors.white, .045), basis, _meng(basis, Colors.black, .12)],
      stops: omhoog ? const [0, 1] : const [0, .55, 1],
    ),
    boxShadow: schaduw ?? schaduwVan(niveau),
  );
}

/// Zoals [paneelDecoratie], maar in een widget die zijn kind omvat en netjes afknipt.
class Vlak extends StatelessWidget {
  const Vlak({
    super.key,
    required this.child,
    this.niveau = Niveau.paneel,
    this.radius = kHoek12,
    this.vulling = const EdgeInsets.all(kRuimte12),
    this.rand = true,
    this.schaduw,
    this.plat,
  });

  final Widget child;
  final Niveau niveau;
  final double radius;
  final EdgeInsetsGeometry vulling;
  final bool rand;
  final List<BoxShadow>? schaduw;
  final bool? plat;

  @override
  Widget build(BuildContext context) => Container(
        padding: vulling,
        decoration: paneelDecoratie(
          niveau,
          radius: radius,
          rand: rand,
          schaduw: schaduw,
          plat: plat,
        ),
        child: child,
      );
}

Color _meng(Color onder, Color boven, double hoeveel) =>
    Color.lerp(onder, boven, hoeveel)!;
