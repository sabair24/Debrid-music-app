/// Ligt het scherm, of staat het — en welke achtergrond hoort daarbij.
///
/// **Waarom dit bestaat.** De app kende één achtergrond per artiest, en die is bijna altijd 16:9:
/// TheAudioDB's fanart. Op een breed venster klopt dat. Op een iPad die je rechtop houdt niet.
///
/// GEMETEN op 10-09-2026 door [EditorialeKop] op zes schermen te pompen met echte inhoud: de kop is
/// overal tussen 682 en 738 punten hoog, en de ondergrens `(breedte × .40).clamp(340, 620)` is
/// NERGENS bindend — de inhoud duwt hem altijd hoger. Op een iPad rechtop is de kop dus 834 × 738,
/// verhouding **1,13**, en een bron van 16:9 (1,78) die daar met `BoxFit.cover` in gaat verliest
/// **36% van zijn breedte**. Wat overblijft is een uitvergrote middenstrook zonder compositie.
///
/// Daarom twee keuzes in plaats van één, en een som die zegt welke er getekend wordt.
///
/// **Waarom hier en niet in `lib/ui/`.** De soortenlijst hieronder is niet alleen een
/// tekenbeslissing: het is de lijst die `lan/catalog.dart` naar elk toestel stuurt. Stond hij in
/// `ui/`, dan zou `lan/` als eerste die maplaag moeten binnenhalen — vandaag importeert `lan/` niets
/// uit `ui/`. Eén niveau hoger kunnen de kop, de kiezer én de catalogus er alle drie eerlijk bij, en
/// dat is precies wat moet: één plek, zodat de soortenlijst en de terugvalladder niet uit elkaar
/// kunnen lopen.
///
/// Puur, zonder `BuildContext` — naar het model van `ui/speelvlak.dart`, en om dezelfde reden:
/// `test/beeldvorm_test.dart` hoeft er geen widgetboom voor te bouwen.
library;

import 'dart:ui' show Size;

/// Liggend of staand. Geen derde stand: vierkant valt onder liggend, want de kop is nooit hoger
/// dan breed op een toestel dat je niet gedraaid hebt.
enum Beeldvorm { liggend, staand }

/// Vanaf welke verhouding (hoogte ÷ breedte) een scherm als STAAND telt.
///
/// **Waarom 1,15 en niet gewoon "hoger dan breed".** Een kale `h > w` klapt om op verhouding 1,000,
/// dus een venster dat je met de muis door het vierkant sleept wisselt bij elke trilling van
/// achtergrond — en elke wissel is een nieuwe afbeelding die opgehaald en gedecodeerd wordt.
///
/// Er zit niets echts in de dode band. GEMETEN aan de toestellen die deze app draait: iPad rechtop
/// 834×1194 = 1,43 · iPad liggend = 0,70 · telefoon rechtop 411×915 = 2,23 · telefoon liggend =
/// 0,45 · vensters op de pc 0,66 tot 0,77. Het dichtstbijzijnde is 0,87 aan de ene kant en 1,43 aan
/// de andere. Alleen een venster dat iemand met de hand versleept komt hier ooit, en daar blijft
/// gewoon de vorige stand staan.
const double kStaandVanaf = 1.15;

/// De liggende achtergrond. Blijft `'backdrop'` heten: dat staat al in ieders
/// `artist_art_choice.json` en in elke catalogus die al over het net ging.
const String kSoortLiggend = 'backdrop';

/// De staande achtergrond, voor een iPad die je rechtop houdt.
///
/// Niet `'backdrop_portrait'`: `'portrait'` betekent in deze app al iets ánders — het ronde
/// portret dat `ArtistHero` op de personenpagina tekent. Twee dingen die "portrait" heten en niet
/// hetzelfde zijn, is precies hoe een sleutel stil de verkeerde foto gaat aanwijzen.
const String kSoortStaand = 'backdrop_staand';

/// Elke soort die bewaard én gesynchroniseerd wordt.
///
/// **Dit is de lijst die `lan/catalog.dart` gebruikt**, in plaats van de letterlijke opsomming die
/// daar stond. Een soort toevoegen op één plek en op de andere vergeten is een storing die stil is
/// en pas dagen later op een tweede toestel bovenkomt: de iPad maakt de keuze, stuurt hem naar de
/// pc, die bewaart hem netjes — en bij de volgende catalogusduw is hij weg, omdat een cliënt uit de
/// doorgestuurde map leest en die soort daar niet in staat.
const List<String> kArtSoorten = <String>[
  'portrait',
  kSoortLiggend,
  kSoortStaand,
  'logo',
  // Hoe de kop per soort scherm is uitgesneden — zie [KopInstelling]. Geen url maar vier getallen.
  'kop_pc',
  'kop_tv',
  'kop_gsm',
  'kop_staand',
];

/// Welke vorm dit scherm heeft.
///
/// **Een televisie is ALTIJD liggend**, hoe de maat ook binnenkomt — dezelfde uitweg als
/// `naastElkaar` in `ui/speelvlak.dart`, en om dezelfde soort reden: een toestel dat aan een muur
/// hangt draai je niet, en wat het over zichzelf meldt is van hieruit niet na te kijken.
///
/// **Geen platformcheck.** Een venster dat je op de pc smal trekt hoort dezelfde behandeling te
/// krijgen als een iPad rechtop; dat is precies wat `tv.dart` over de grens van 600 zegt — het is
/// geen toestelklasse maar een vorm.
Beeldvorm beeldvormVan({required Size scherm, required bool tv}) {
  if (tv) return Beeldvorm.liggend;
  final b = scherm.width;
  final h = scherm.height;
  // Een wacht en geen geval: `MediaQuery.sizeOf` is eindig, maar een toets die pompt vóór de eerste
  // frame geeft `Size.zero`, en dan mag hier geen deling omvallen.
  if (!b.isFinite || !h.isFinite || b <= 0 || h <= 0) return Beeldvorm.liggend;
  return h >= b * kStaandVanaf ? Beeldvorm.staand : Beeldvorm.liggend;
}

/// Welke bewaarde keuzes deze vorm mag gebruiken, op volgorde.
///
/// **Bewust ASYMMETRISCH, en dat is de hele beslissing.**
///
/// Staand mag terugvallen op de liggende keuze. Dat is een uitsnede, maar wél van de foto die de
/// gebruiker zélf heeft aangewezen — en een keuze van hem verslaat een gok van een database, ook
/// als hij niet perfect past.
///
/// Liggend valt NIET terug op de staande. Een staande 2:3 in een band van 2,5:1 is de "reep
/// voorhoofd" die elders in deze code al beschreven staat: hij lijstte Michael Jackson netjes in en
/// gaf Stromae een strook voorhoofd. Zonder liggende keuze is TheAudioDB's fanart de juiste
/// volgende stap — en dat is precies wat de app vandaag al doet, dus dan verandert er niets.
List<String> achtergrondSoorten(Beeldvorm vorm) => switch (vorm) {
      Beeldvorm.staand => const <String>[kSoortStaand, kSoortLiggend],
      Beeldvorm.liggend => const <String>[kSoortLiggend],
    };

/// Voor welk soort scherm een instelling van de artiestkop geldt.
///
/// Apart bewaard (Saber, 17-10-2026: "alles per toestel apart"): een tv-kop is ruim twee keer zo
/// breed als hoog, een gsm-kop bijna vierkant, dus wat op de tv goed staat, snijdt op de gsm de
/// helft van de groep weg. Op de pc kies je voor welk scherm je hem instelt.
///
/// [staand] is een iPad die je rechtop houdt (en een venster dat hoger is dan breed): daar is de kop
/// bijna vierkant, en Saber koos daar een eigen instelling voor (17-10-2026).
enum KopScherm { pc, tv, gsm, staand }

/// Onder welke soort de kopinstelling bij de artiest bewaard wordt: naast de gekozen foto's, in
/// `artist_art_choice.json`, en zo met de catalogus mee naar elk toestel (zie [kArtSoorten]).
String kopSoort(KopScherm s) => 'kop_${s.name}';

/// Hoe jij de kop voor één soort scherm hebt ingesteld.
///
/// [fx] en [fy] zijn het punt in de foto (0..1) dat op de vaste plek in de kop komt — rechts van de
/// naam, onder het menu. [zoom] is hoeveel verder dan "net vullend" (1 = niet), en [hoogte] de
/// hoogte van de kop in punten (null = de gewone hoogte van dat scherm).
///
/// [fx] en [fy] mogen buiten 0..1 liggen: opzij schuift de foto ook voorbij de rand (Saber, 27-10-2026: "het
/// moet ook zijdelings verschoven kunnen worden"), en een verkleinde foto mag overal in de kop staan — dan
/// ligt de vaste plek naast de foto in plaats van erin. Hoe ver precies, zegt `kopPlek` (`kOpzijVrij`);
/// hier alleen een ruime grens tegen onzin.
///
/// [zoom] mag ook onder 1 (tot [kZoomVanaf]): kleiner dan vullend. Saber, 27-10-2026: "uitvergroten en
/// verkleinen hoe ik het wil, overal op alle platforms".
///
/// [naam]: de kop toont de naam in letters, ook als TheAudioDB een logo heeft (de keuze "Kop toont" in
/// de bewerker). Onwaar is het logo als dat er is.
class KopInstelling {
  const KopInstelling({required this.fx, required this.fy, this.zoom = 1, this.hoogte, this.naam = false});

  final double fx, fy, zoom;
  final double? hoogte;
  final bool naam;

  static const double kZoomVanaf = .3, kZoomTot = 4;

  /// Hoe ver [fx] en [fy] buiten de foto mogen: een ruime grens, de echte zit in `kopPlek`.
  static const double kPuntVanaf = -1, kPuntTot = 2;

  /// De laagste kop die je kunt maken. Lager en de naam en Radio passen er niet meer in, en dan duwt
  /// de inhoud hem toch weer op.
  static const double kHoogteVanaf = 180;
  static const double kHoogteTot = 1400;

  /// "0.620,0.310,1.250,380" — zo staat hij in de keuzelijst van de artiest. Ongeldig geeft null,
  /// zodat een kapotte regel in een bestand nooit een vreemde uitsnede wordt.
  ///
  /// Met de naam erbij een vijfde veld: "0.620,0.310,1.250,380,naam", of zonder eigen hoogte
  /// "0.620,0.310,1.250,,naam". Een oudere app leest dat als ongeldig en kiest dan zelf — geen vreemde uitsnede.
  static KopInstelling? lees(String? s) {
    if (s == null || s.isEmpty) return null;
    final d = s.split(',');
    if (d.length < 3 || d.length > 5) return null;
    final fx = double.tryParse(d[0]), fy = double.tryParse(d[1]), zoom = double.tryParse(d[2]);
    if (fx == null || fy == null || zoom == null) return null;
    if (!fx.isFinite || !fy.isFinite || !zoom.isFinite) return null;
    final metHoogte = d.length > 3 && !(d.length == 5 && d[3].isEmpty);
    final h = metHoogte ? double.tryParse(d[3]) : null;
    if (metHoogte && (h == null || !h.isFinite)) return null;
    if (d.length == 5 && d[4] != 'naam' && d[4] != 'logo') return null;
    return KopInstelling(
      fx: fx.clamp(kPuntVanaf, kPuntTot),
      fy: fy.clamp(kPuntVanaf, kPuntTot),
      zoom: zoom.clamp(kZoomVanaf, kZoomTot),
      hoogte: h?.clamp(kHoogteVanaf, kHoogteTot),
      naam: d.length == 5 && d[4] == 'naam',
    );
  }

  String schrijf() => [
        fx.toStringAsFixed(3),
        fy.toStringAsFixed(3),
        zoom.toStringAsFixed(3),
        if (hoogte != null) hoogte!.round().toString() else if (naam) '',
        if (naam) 'naam',
      ].join(',');

  KopInstelling met({double? fx, double? fy, double? zoom, double? hoogte, bool geenHoogte = false, bool? naam}) =>
      KopInstelling(
        fx: (fx ?? this.fx).clamp(kPuntVanaf, kPuntTot),
        fy: (fy ?? this.fy).clamp(kPuntVanaf, kPuntTot),
        zoom: (zoom ?? this.zoom).clamp(kZoomVanaf, kZoomTot),
        hoogte: geenHoogte ? null : (hoogte ?? this.hoogte)?.clamp(kHoogteVanaf, kHoogteTot),
        naam: naam ?? this.naam,
      );

  @override
  bool operator ==(Object other) =>
      other is KopInstelling &&
      other.fx == fx &&
      other.fy == fy &&
      other.zoom == zoom &&
      other.hoogte == hoogte &&
      other.naam == naam;

  @override
  int get hashCode => Object.hash(fx, fy, zoom, hoogte, naam);

  @override
  String toString() => 'KopInstelling(${schrijf()})';
}
