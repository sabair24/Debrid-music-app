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

import 'dart:ui' show ImageFilter;

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

// ── De kleurwas ──────────────────────────────────────────────────────────────
//
// **Waarom dit hier staat en niet op de albumpagina.** De was is twee keer nodig — op de
// albumpagina en op het speelscherm — en het zijn precies de getallen die uit elkaar lopen zodra ze
// op twee plekken staan: er wordt er één bijgesteld naar aanleiding van één schermafbeelding, en
// dan tekent dezelfde plaat op twee schermen een andere kleur.

/// De TINT van een hoes, klaargemaakt om achter een scherm te leggen.
///
/// **Niet de donkerte van de hoes, alleen zijn tint.** Gemeten op de eigen platen: No Strings
/// Attached geeft rgb(197,73,45) en dat werkt meteen, maar Thriller geeft rgb(25,37,43) en Adele's
/// 25 geeft rgb(52,44,36). Zulke kleuren op een achtergrond van #07080C leggen verandert niets
/// zichtbaars — je krijgt zwart op zwart en het lijkt alsof de was stuk is, terwijl hij precies doet
/// wat er staat.
///
/// Daarom wordt de helderheid gelijkgetrokken en blijven alleen tint en verzadiging over. Dan wordt
/// Thrillers donkerblauw een zichtbaar blauw en Adele's bruin een zichtbaar bruin, en houdt élke
/// hoes dezelfde kracht. De verzadiging krijgt een ondergrens (anders blijft het grijzig) en een
/// bovengrens (anders schreeuwt een felle hoes de tekst weg).
///
/// Null in, null uit: een zwart-witte hoes hoort géén was te krijgen. Zie `dominantColour` — geen
/// was is beter dan een grijze.
Color? wasBasis(int? kleur) {
  if (kleur == null) return null;
  final hsl = HSLColor.fromColor(Color(kleur));
  return hsl.withLightness(.42).withSaturation(hsl.saturation.clamp(.32, .78)).toColor();
}

/// Het verloop dat achter een scherm gaat: de tint bovenaan, de gewone achtergrond onderaan.
///
/// De drie getallen zijn afgestemd op de grijstrap van ronde 1. Toen [kAchtergrond] van #0C0D12 naar
/// #07080C ging, werd de top van de was er absoluut donkerder van — vandaar .38 en niet .34. En de
/// staart mag lang: het einde landt nu op een donkerdere vloer, en dan is de plek waar hij ophoudt
/// eerder een RAND dan een overgang.
///
/// Onder de 78% is er niets meer van over, en dat is met opzet: daaronder staan tracklijsten en
/// grijze regels, en alles wat daar nog kleur draagt gaat van hun leesbaarheid af.
LinearGradient? kleurWas(Color? basis) {
  if (basis == null) return null;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: const [0, .34, .78],
    colors: [
      Color.lerp(kAchtergrond, basis, .38)!,
      Color.lerp(kAchtergrond, basis, .15)!,
      kAchtergrond,
    ],
  );
}

/// De kleur van de spelerbalk: de vloer met een ZWEEM van wat er speelt.
///
/// **Waarom een zweem en niet de was.** De balk staat permanent onderaan het scherm, over elke
/// pagina heen, en hij is de enige plek die zegt wat er speelt terwijl je iets anders doet. Hem de
/// volle was geven maakt hem een gekleurde balk die met elk nummer van kleur springt en die overal
/// aandacht trekt waar je juist niet kijkt. Een tiende is genoeg om te merken dat hij bij deze plaat
/// hoort, en te weinig om hem te laten schreeuwen.
///
/// Geen kleur betekent gewoon [kVerzonken] — dat is de vloer waar hij altijd op stond.
Color balkKleur(int? kleur) {
  final basis = wasBasis(kleur);
  return basis == null ? kVerzonken : Color.lerp(kVerzonken, basis, .10)!;
}

/// De vastgezette balk boven een pagina — glas dat er alleen is als er iets onder doorschuift.
///
/// **Waarom hij bijna altijd niets tekent.** Hij tekende altijd: een half-dekkende tint over de was,
/// van boven tot onder, met een harde rand waar hij ophield. En omdat die tint een DONKERE kleur is
/// (de bovenkant van de was, zie [kleurWas]) werd de strook donkerder dan wat erboven en eronder
/// lag. Zo lag er een baan dwars over het scherm met een lijn aan de onderkant — precies wat er niet
/// mag zijn: van de bovenrand van het venster tot in de pagina hoort één doorlopend geheel te zijn.
///
/// Die baan had ook geen reden om er te zijn. Wat een vastgezette balk moet doen is verhinderen dat
/// je de lijst dwars door de knoppen heen leest, en zolang die lijst bovenaan staat schuift er niets
/// onder. Dus: bij stilstand niets, en het glas komt op naarmate je scrolt.
///
/// **En de onderrand lost op.** De vulling loopt naar volledig doorzichtig in plaats van halverwege
/// op te houden, zodat er ook opgekomen geen streep staat waar de balk eindigt. Wat de leesbaarheid
/// draagt is niet die vulling maar de vervaging: die maakt letters onleesbaar over de hele hoogte,
/// ook waar de kleur al weg is.
///
/// Op een televisie zonder vervaging, om dezelfde reden die overal in dit bestand staat: een
/// `BackdropFilter` is de enige laag die Flutter niet kan bewaren, en op een Tegra X1 is dat het
/// duurste wat er op het scherm staat. Daar dus een dichtere vulling in plaats van glas.
///
/// [op] loopt van 0 (niets) tot 1 (volledig glas).
///
/// **De vulling staat NAAST de vervaging en niet erin, en dat is geen stijlkwestie.**
///
/// Ze stond als kind ván de `BackdropFilter`. Op een pc werkte dat: je zag glas. Op een Android-
/// telefoon liep de albumbeschrijving kraakhelder dwars door de knoppen heen — geen wazigheid en
/// geen kleur. Dat "en geen kleur" is de aanwijzing: een vulling is een gewoon gekleurd vlak en
/// tekent altijd, tenzij hij niet getekend WORDT. Als kind van een vervaging die het toestel laat
/// vallen — en dat gebeurt op Android met een `BackdropFilter` binnen de clip van een scrollende
/// lijst — verdwijnt hij mee.
///
/// Naast elkaar in een `Stack` overleeft de kleur het dus als de vervaging sneuvelt. Wat je dan
/// overhoudt is minder mooi maar wel leesbaar, en dat is precies de goede kant om op te falen.
/// `StackFit.expand` erbij: een `DecoratedBox` zonder kind neemt bij losse randvoorwaarden de
/// KLEINSTE maat aan, en dat is nul — dezelfde stille manier om niets te tekenen.
///
/// [dicht] maakt het glas sterker, en dat is voor de telefoon. Op een pc is deze balk 64 punten hoog
/// boven een breed venster; er schuift per keer weinig onderdoor. Op een telefoon staat de tekst van
/// rand tot rand en is de balk het enige tussen zes witte pictogrammen en een lopende alinea.
Widget balkGlas(Color tint, double op, {bool dicht = false}) {
  // Helemaal niets, en niet "een doorzichtig vlak": een BackdropFilter met sigma 0 is nog steeds een
  // laag die de achtergrond leest, en dat is op een Shield het duurste wat er op het scherm staat.
  if (op <= .01) return const SizedBox.shrink();
  final vol = isTv
      ? .96
      : dicht
          ? .78
          : .62;
  final vulling = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // Drie stops: bijna de hele hoogte draagt de kleur, en pas het laatste stuk lost op. Recht
        // van vol naar nul zou de knoppen zelf al halverwege hun contrast afnemen.
        stops: const [0, .66, 1],
        colors: [
          tint.withValues(alpha: vol * op),
          tint.withValues(alpha: vol * .82 * op),
          tint.withValues(alpha: 0),
        ],
      ),
    ),
  );
  if (isTv) return vulling;
  // Meer vervaging waar de balk krapper is. Zes punten meer kost niets extra — het is dezelfde ene
  // laag — en het is wat kleine letters van "vager" naar "onleesbaar" brengt.
  final wazig = (dicht ? 30 : 24) * op;
  return Stack(
    fit: StackFit.expand,
    children: [
      // Eerst de vervaging, met een LEEG kind: hij hoeft niets te tekenen, alleen te vervagen wat
      // erachter langs schuift.
      ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: wazig, sigmaY: wazig),
          child: const SizedBox.expand(),
        ),
      ),
      // En dan de kleur eroverheen, als eigen laag. Sneuvelt de vervaging op een toestel, dan staat
      // deze er nog steeds.
      vulling,
    ],
  );
}
