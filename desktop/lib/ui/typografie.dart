/// De tekststijlen van de app, als rollen in plaats van als losse getallen.
///
/// **Waarom dit bestand er is.** Een telling over `main.dart`: 456 losse `TextStyle(`-constructies,
/// 25 verschillende `fontSize`-waarden, en `Theme.of(context).textTheme` dat nul keer gebruikt
/// wordt. 261 van die 369 groottes (71%) vallen in de band 11 tot 13,5 — verdeeld over zes
/// halvepunt-varianten die je op een scherm niet uit elkaar houdt. Binnen één widget wisselt het
/// tussen 12,5, 11,5 en 12 zonder aanwijsbare regel.
///
/// Dat is geen smaakkwestie. Het betekent dat "maak de bijschriften iets groter" een zoek-en-
/// vervangactie is over honderden plekken, en dat elke nieuwe widget zijn eigen maat verzint.
///
/// **De rollen.** Vier voor tekst die iets zegt, drie voor koppen. Meer heeft deze app niet nodig,
/// en minder zou de bijschriften onder een titel niet meer van de titel kunnen onderscheiden.
///
/// **Hoe dit binnenkomt.** Als `textTheme` op de `ThemeData`, zodat `Theme.of(context).textTheme`
/// vanaf nu iets zinnigs teruggeeft. De bestaande losse stijlen blijven werken en gaan er per scherm
/// naartoe — allemaal tegelijk omzetten is 456 kansen om iets stil te verschuiven, en dat is precies
/// het soort verandering waarvan je pas op het toestel merkt dat er iets scheef staat.
library;

import 'package:flutter/material.dart';

import 'kleuren.dart';

/// De naam van een artiest, paginabreed. Alleen daar, en alleen in hoofdletters.
///
/// **Waarom deze maat bestaat.** De ladder liep van 11 tot 25, en 71% van al het gebruik zat tussen
/// 11 en 13,5 — mooi voor een lijst, maar dan is er geen enkel moment van rust. Een artiestpagina
/// die opent met een naam van 25 punten opent met een tabelkop. Het contrast tussen deze maat en
/// [kOpschrift] van 11 ís de hiërarchie; alles daartussen blijft zoals het was.
///
/// De negatieve spatiëring hoort bij het gewicht: op deze grootte staan letters van 800 anders veel
/// te ruim. Schaalt mee met de breedte — zie `artiestNaamGrootte`.
TextStyle get kDisplay => TextStyle(
  fontSize: 112,
  fontWeight: FontWeight.w800,
  letterSpacing: -3,
  height: .88,
  color: kTekst,
);

/// De kop boven een sectie op een pagina die met [kDisplay] opent — DISCOGRAFIE, OVER.
TextStyle get kDisplayKlein => TextStyle(
  fontSize: 56,
  fontWeight: FontWeight.w800,
  letterSpacing: -1.5,
  height: 1,
  color: kTekst,
);

/// Hoe groot de artiestnaam op dít scherm mag zijn.
///
/// Eén plek in plaats van vier losse getallen. De maten komen uit de ontwerpschetsen: 132 op een
/// bureaublad, 84 op een iPad liggend, 76 staand, 46 op een telefoon of televisie. Alles daarbuiten
/// schaalt mee met de breedte, met een bodem zodat een heel smal venster niet in onleesbaarheid
/// eindigt.
///
/// Een televisie hoort hier niet in: een Shield is 960 punten breed en zou de maat van een iPad
/// krijgen. Die gebruikt [kTvArtiestNaam].
double artiestNaamGrootte(double breedte) {
  if (breedte >= 1280) return 132;
  if (breedte >= 1100) return 96;
  if (breedte >= 900) return 84;
  if (breedte >= 700) return 76;
  if (breedte >= 500) return 58;
  return (breedte * .118).clamp(34, 46);
}

/// De artiestnaam op een televisie: de 46 uit de ontwerpschets. Met de 1,35 waarmee een tv alle
/// tekst vergroot, zijn de letters 62 punten — ongeveer de helft van de 113 die er stonden (Saber,
/// 16-10-2026: "naam text is veel te groot").
const double kTvArtiestNaam = 46;

/// De naam van een scherm, of van een album op zijn eigen pagina.
TextStyle get kKopGroot => TextStyle(
  fontSize: 25,
  fontWeight: FontWeight.w800,
  letterSpacing: -.4,
  color: kTekst,
);

/// De kop boven een sectie of een lijst.
TextStyle get kKop => TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kTekst);

/// De kop boven een rij op het startscherm.
TextStyle get kKopKlein => TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kTekst);

/// Gewone tekst: de titel van een nummer in een lijst, een knoplabel.
TextStyle get kTekstNormaal => TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTekst);

/// Wat onder een titel staat: artiest, aantal, tijd.
///
/// 13,5 en niet 13 of 14: dit is de maat die het vaakst voorkwam van de zes varianten in die band,
/// dus zo verschuift er het minst.
TextStyle get kTekstBij => TextStyle(fontSize: 13.5, color: kGedempt);

/// Kleine bijzaken: een telling naast een kop, een jaartal, een tijdsduur in een rij.
TextStyle get kTekstKlein => TextStyle(fontSize: 12, color: kGedempt);

/// Het kleinste dat nog leesbaar hoort te zijn: labels op merkjes en badges.
TextStyle get kLabel => TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kGedempt);

/// Het kleine kapitaal boven een blok: DOWNLOADS, CREDITS, ARTIESTEN.
///
/// **Waarom dit een eigen rol is en geen [kLabel] met wat erbij.** Het is niet hetzelfde ding. Een
/// label zit óp iets — een merkje, een badge — en een opschrift staat erbóven en zegt wat er volgt.
/// Dat verschil zit in de spatiëring: kapitalen zonder extra ruimte ertussen lezen als een woord dat
/// per ongeluk hard staat, mét die ruimte als een kopje.
///
/// En het stond er al drie keer, in twee maten (11 en 11,5) met steeds dezelfde bedoeling. Dat is
/// precies het patroon waar dit bestand voor gemaakt is: één ding, één plek.
TextStyle get kOpschrift => TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: .6,
  color: kGedempt,
);

/// Tekst zonder eigen stijl. Zie [kTekstThema] voor waarom deze apart bestaat.
TextStyle get kTekstBasis => TextStyle(fontSize: 14, color: kTekst);

/// De rollen als `TextTheme`, zodat `Theme.of(context).textTheme` ze teruggeeft.
///
/// **`bodyMedium` is de gevaarlijke.** Dat is wat Flutter pakt voor élke `Text` die geen stijl
/// meekrijgt, en daar staan er honderden van in deze app. De eerste versie hiervan zette die op de
/// gedempte bijschriftstijl (13,5 grijs) — dan verschuift in één klap alle ongestileerde tekst in
/// de hele app naar kleiner en grijzer, zonder dat er ergens iets rood wordt. Precies het soort
/// verandering waarvan je pas op het toestel merkt dat er iets scheef staat.
///
/// Daarom [kTekstBasis]: 14 punten in de tekstkleur van het palet, wat Material zelf ook als maat
/// aanhoudt. Er verschuift dus niets; wat er verandert is dat er vanaf nu íets zinnigs terugkomt
/// waar een widget om vraagt, in plaats van een kleur die niet in dit palet staat.
TextTheme get kTekstThema => TextTheme(
  headlineLarge: kKopGroot,
  headlineMedium: kKop,
  headlineSmall: kKopKlein,
  titleMedium: kTekstNormaal,
  bodyLarge: kTekstNormaal,
  bodyMedium: kTekstBasis,
  bodySmall: kTekstKlein,
  labelMedium: kTekstBij,
  labelSmall: kLabel,
);
