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

// ── Glas voor knoppen ────────────────────────────────────────────────────────
//
// **Waarom hier en niet naast `glassSurface` in `main.dart`.** Dit is het bestand van de oppervlakken,
// en het deelt met [balkGlas] de les over de vulling naast de vervaging en de uitweg voor een
// televisie. Drie glasrecepten in drie bestanden is precies hoe hun getallen uit elkaar gaan lopen.

/// Wat het glas van een knop met de achtergrond doet: vervagen, en de lichte plekken eerst laten
/// uitlopen.
///
/// **Waarom `dilate` en geen lens.** Letterlijk "de achtergrond licht vervormd" (Saber, 11-09-2026)
/// is een lens: de achtergrond onder de knop een tikje vergroten met een `ImageFilter.matrix`. Maar
/// zo'n matrix vergroot de achtergrond zoals die in de scène ligt, en niet om het midden van de knop
/// — `BackdropFilterLayer` geeft hem geen eigen transformatie mee. Bij zes procent vergroting en een
/// knop op 650 punten schuift het beeld onder de ruit dan bijna veertig punten weg, en omdat die plek
/// bij elke scrollstap een andere is, drijft het mee. Niet gemeten; wel reden genoeg om het niet uit
/// te leveren voor een effect dat `dilate` zonder dat risico geeft.
///
/// `dilate` kent geen positie. Hij rekt elke pixel op naar de helderste in zijn straal: de lichte
/// plekken van de foto lopen uit vóór ze vervagen — wat glas met licht doet. En de vervaging is
/// scheef, 14 tegen 10: rond vervaagd leest als matglas, een veeg die meer opzij loopt dan omhoog als
/// een gebogen ruit.
///
/// **Waarom 14 en niet de 26 van `glassSurface`.** Die ruit ligt over een rustige strook. Deze knoppen
/// liggen over een foto waarvan er achter de knoppenrij nog maar een paar procent doorkomt, en sigma
/// 26 veegt over een pil van veertig punten élk detail weg dat kleiner is dan de pil zelf. Dan valt er
/// niets meer te vervormen en is het een duurdere manier om een grijs vlak te tekenen.
final ImageFilter glasVervorming = ImageFilter.compose(
  outer: ImageFilter.blur(sigmaX: 14, sigmaY: 10),
  inner: ImageFilter.dilate(radiusX: 2.5, radiusY: 2.5),
);

/// De ruit onder een [GlasKnop], zonder de knop: vervaging, vulling, rand en schaduw.
///
/// **Drie regels, en elk ervan faalt stil als je hem vergeet.**
/// * De vulling staat NAAST de vervaging, niet erin — de les van [balkGlas]. Laat een toestel de
///   vervaging vallen, dan gaat een vulling die er kind van is mee, en staat er een onleesbare knop.
/// * De schaduw valt alleen BUITEN de pil ([BlurStyle.outer]). Een gewone schaduw tekent ook ónder de
///   ruit, en dan vervaagt het glas een achtergrond die de schaduw al voor een kwart zwart gemaakt
///   heeft — precies wat het moest laten zien.
/// * [plat] is de uitweg voor een televisie, om de reden die bij [balkGlas] staat: geen vervaging, wel
///   meer dekking, met dezelfde ophogingen als `glassSurface` — anders lost de pil van drie meter
///   afstand op in het donker.
Widget glasRuit({bool? plat}) {
  final tv = plat ?? isTv;
  const hoek = BorderRadius.all(Radius.circular(kHoekRond));
  final vulling = DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: hoek,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // Drie stops en niet twee, om de reden die bij de actieve navigatiepil staat: een
        // `BoxDecoration` met een `borderRadius` eist een gelijke rand rondom, dus de lichte bovenzijde
        // — waar glas het licht vangt — moet uit het verloop komen. De getallen zijn die van die pil,
        // een tikje terug: dáár ligt glas op glas dat zelf al licht geeft.
        stops: const [0, .10, 1],
        colors: [
          Colors.white.withValues(alpha: tv ? .355 : .30),
          Colors.white.withValues(alpha: tv ? .20 : .17),
          Colors.white.withValues(alpha: tv ? .10 : .07),
        ],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: tv ? .32 : .20)),
    ),
  );
  return DecoratedBox(
    decoration: const BoxDecoration(
      borderRadius: hoek,
      boxShadow: [
        BoxShadow(
          color: Color(0x47000000),
          blurRadius: 10,
          offset: Offset(0, 3),
          blurStyle: BlurStyle.outer,
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: hoek,
      child: tv
          ? vulling
          : Stack(
              fit: StackFit.expand,
              children: [
                // Eerst de vervaging, met een LEEG kind: zij hoeft niets te tekenen, alleen te
                // vervormen wat erachter ligt.
                BackdropFilter(filter: glasVervorming, child: const SizedBox.expand()),
                vulling,
              ],
            ),
    ),
  );
}

/// Een knop van glas: de achtergrond vervaagd en licht vervormd, een lichte bovenrand, een haarfijne
/// rand, en een schaduw die hem van de foto tilt.
///
/// **De knop zelf blijft een `FilledButton` — of een `IconButton` voor [GlasKnop.rond].** Doorzichtig,
/// boven de ruit. Een eigen knop op `Pressable` zou de focusring kwijtraken die `_focusOutline` via
/// het thema op elke knop van dit soort zet, en daarmee ook de inkt, het toetsenbord en de
/// uitgeschakelde stand.
///
/// **En hij staat BUITEN de afknipping van de ruit.** Flutter tekent een focusring op de rand van de
/// knopvorm, voor de helft erbuiten; een afknipping op diezelfde rand halveert hem. Met een
/// afstandsbediening is die ring het enige dat zegt waar je staat.
///
/// **Even groot als zijn ruit, overal.** Op een telefoon en een iPad maakt Flutter een knop van 40
/// punten 48 hoog om hem raakbaar te houden, maar tekent hij zijn inkt op 40 — en dan licht er bij
/// aanwijzen een kleinere pil op binnen een grotere. Dus een vaste 44, zonder die opvulling: het
/// kleinste wat Apple een vinger laat raken, en ruit en knop vallen samen.
class GlasKnop extends StatelessWidget {
  const GlasKnop({
    super.key,
    required this.icoon,
    required String this.label,
    required this.onPressed,
  })  : tooltip = null,
        _rond = false;

  /// Alleen een pictogram, in een rond stukje glas: de terugpijl boven een foto.
  const GlasKnop.rond({super.key, required this.icoon, required this.onPressed, this.tooltip})
      : label = null,
        _rond = true;

  final IconData icoon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool _rond;

  @override
  Widget build(BuildContext context) {
    final knop = _rond
        ? IconButton(
            onPressed: onPressed,
            tooltip: tooltip,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(icoon),
          )
        : FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(64, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onPressed,
            icon: Icon(icoon, size: 18),
            label: Text(label!),
          );
    return Stack(
      children: [
        Positioned.fill(child: IgnorePointer(child: glasRuit())),
        knop,
      ],
    );
  }
}
