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

/// De naam van een scherm, of van een album op zijn eigen pagina.
const kKopGroot = TextStyle(
  fontSize: 25,
  fontWeight: FontWeight.w800,
  letterSpacing: -.4,
  color: kTekst,
);

/// De kop boven een sectie of een lijst.
const kKop = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kTekst);

/// De kop boven een rij op het startscherm.
const kKopKlein = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kTekst);

/// Gewone tekst: de titel van een nummer in een lijst, een knoplabel.
const kTekstNormaal = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTekst);

/// Wat onder een titel staat: artiest, aantal, tijd.
///
/// 13,5 en niet 13 of 14: dit is de maat die het vaakst voorkwam van de zes varianten in die band,
/// dus zo verschuift er het minst.
const kTekstBij = TextStyle(fontSize: 13.5, color: kGedempt);

/// Kleine bijzaken: een telling naast een kop, een jaartal, een tijdsduur in een rij.
const kTekstKlein = TextStyle(fontSize: 12, color: kGedempt);

/// Het kleinste dat nog leesbaar hoort te zijn: labels op merkjes en badges.
const kLabel = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kGedempt);

/// Tekst zonder eigen stijl. Zie [kTekstThema] voor waarom deze apart bestaat.
const kTekstBasis = TextStyle(fontSize: 14, color: kTekst);

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
const kTekstThema = TextTheme(
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
