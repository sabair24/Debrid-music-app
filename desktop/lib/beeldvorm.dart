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
