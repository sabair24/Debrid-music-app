/// De kleuren van de app, op één plek.
///
/// **Waarom dit bestand er is.** Deze acht kleuren stonden als privéconstanten in `main.dart`, en
/// omdat ze privé zijn kon geen enkel ander schermbestand erbij. Het gevolg is niet dat die
/// bestanden het zonder deden, maar dat ze allemaal hun eigen kopie declareerden:
/// `login_screen.dart`, `pairing_screen.dart`, `booklet_view.dart`, `speakers.dart` en `tv.dart`
/// hadden elk hun eigen `_accent` — het merkpaars stond op **zes** plekken. Wie er één verandert,
/// verandert de app half.
///
/// Daarnaast staan er nog tientallen losse hexwaarden in de schermen zelf: twaalf tinten oranje voor
/// waarschuwingen, acht roden voor fouten, vier keer dezelfde vulkleur voor een tekstveld. Die
/// wachten op een volgende ronde; dit bestand is de plek waar ze heen gaan.
///
/// Nederlandse namen met opzet: dit is nieuwe code, en de rest van wat er de laatste tijd bij kwam
/// is ook Nederlands. De bestaande `_bg`/`_panel`-namen in main.dart blijven staan en wijzen
/// hierheen, zodat er niets in één keer omgezet hoeft te worden.
library;

import 'dart:math' as wiskunde;

import 'package:flutter/material.dart';

// ── De grijstrap ─────────────────────────────────────────────────────────────
//
// **Waarom hij verschoven is.** Gemeten in CIE Lab lagen de drie lagen op ΔL* 6,3 en **4,0** uit
// elkaar. Die tweede is de "dit is actief"-melding — aangewezen, geopend, geselecteerd — en 4,0
// ligt onder wat een oog op een donker scherm nog als verschil ziet. Een kaart verschilde daardoor
// ongeveer evenveel van de achtergrond als van zijn eigen randje. Dát is wat "plat" betekent als je
// het meet.
//
// De reflex is de panelen lichter maken. Dat is precies wat een donkere app grijs maakt, en het
// dooft bovendien de hoezen — het helderste op het scherm, in een muziekapp. Dus andersom: **de
// vloer gaat omlaag.** Zelfde afstand tussen de lagen, niets aan donkerte verloren, en de hoezen
// springen er harder uit.
//
// Alles blijft in dezelfde blauwviolette familie (H≈225°); dit is geen nieuw merk. De hele winst
// zit in [kPaneelHoog]: die stap gaat van 4,0 naar 6,5 en kost één hexcijfer.
//
// `test/kleurenladder_test.dart` bewaakt dat L* strikt oploopt, dat elke stap ≥ 4 blijft, en dat
// [kTekst] tegen élke laag 4,5:1 haalt. "Even het paneel wat lichter" is vanaf nu een gezakte toets.

/// De diepste achtergrond — waar niets overheen ligt.
const kAchtergrond = Color(0xFF07080C);

/// Een vlak dat juist NAAR BINNEN ligt: een zoekveld, een voortgangsbaan, de goot achter een lijst.
///
/// Nieuw. Deze bestond niet, en daardoor werd een tekstveld getekend als een paneel — iets wat van
/// de pagina af komt terwijl je erin typt.
const kVerzonken = Color(0xFF101219);

/// Een paneel: kaartjes, rijen, alles wat van de achtergrond af komt.
const kPaneel = Color(0xFF171A24);

/// Een paneel dat aandacht heeft (aangewezen, geopend, actief).
const kPaneelHoog = Color(0xFF222736);

/// Wat óver de app heen ligt: een menu, een blad, een dialoog.
///
/// Nieuw. Menu's stonden op [kPaneelHoog], dus een menu boven een aangewezen rij had exact de kleur
/// van die rij.
const kBovenop = Color(0xFF2B3142);

/// Scheidingslijnen en randen.
const kLijn = Color(0xFF2A2F3F);

/// Een scheiding die er hoort te zijn zonder dat je hem opmerkt: tussen twee regels in een lijst.
const kLijnZacht = Color(0xFF1E222E);

/// Gewone tekst.
const kTekst = Color(0xFFE8EAF2);

/// Bijzaken: artiestnamen onder een titel, tellingen, tijden.
const kGedempt = Color(0xFF9AA0B4);

/// Het merkpaars. Knoppen die iets dóén, de actieve navigatiepil, de focusring.
const kAccent = Color(0xFF7C5CFF);

/// De tweede accentkleur, voor wat leeft: radiostatus, "nu bezig".
const kAccent2 = Color(0xFF00D4C8);

/// De helderheid van een kleur volgens CIE Lab — L*, van 0 (zwart) tot 100 (wit).
///
/// **Waarom L\* en niet de WCAG-verhouding.** Die laatste is gemaakt voor tekst op een vlak en zegt
/// over twee náást elkaar liggende donkere vlakken vrijwel niets: tussen de oude `#181B26` en
/// `#1F2331` zat een verhouding van 1,2:1 — dat heet "gezakt" terwijl het verschil met het oog
/// gewoon te zien hoort te zijn. L\* is wél ontworpen om te zeggen hoeveel LICHTER het ene vlak
/// lijkt dan het andere, en dat is precies de vraag bij een grijstrap.
///
/// Gebruikt door `test/kleurenladder_test.dart` en door de stijlpagina, die het getal naast elke
/// trede zet.
double sterrenL(Color kleur) {
  double lineair(double kanaal) => kanaal <= .04045
      ? kanaal / 12.92
      : wiskunde.pow((kanaal + .055) / 1.055, 2.4).toDouble();
  final r = lineair(kleur.r);
  final g = lineair(kleur.g);
  final b = lineair(kleur.b);
  final y = .2126 * r + .7152 * g + .0722 * b;
  return y > 0.008856 ? 116 * wiskunde.pow(y, 1 / 3).toDouble() - 16 : 903.3 * y;
}

/// De contrastverhouding tussen twee kleuren, zoals WCAG hem rekent (1:1 tot 21:1).
///
/// Hier wél op zijn plaats: dit gaat over TEKST op een vlak, en daar is het getal voor gemaakt.
double contrast(Color voor, Color achter) {
  double licht(Color c) {
    double k(double x) => x <= .04045
        ? x / 12.92
        : wiskunde.pow((x + .055) / 1.055, 2.4).toDouble();
    return .2126 * k(c.r) + .7152 * k(c.g) + .0722 * k(c.b);
  }

  final a = licht(voor), b = licht(achter);
  final hoog = a > b ? a : b, laag = a > b ? b : a;
  return (hoog + .05) / (laag + .05);
}
