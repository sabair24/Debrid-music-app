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

/// Licht of donker (Saber, 18-10-2026: "licht thema als keuze — Licht, Donker of Volgens systeem").
///
/// **Waarom getters en geen constanten meer.** Een kleur die tijdens het draaien kan wisselen kan geen
/// `const` zijn. De keuze zelf staat in `ui/thema.dart`; hier alleen of het NU licht is
/// (`thema.dart` bouwt bij een wissel het hele scherm opnieuw op, met de pagina's, de scrollstand en
/// de speler gewoon waar ze waren).
class Thema {
  Thema._();

  /// Is het nu licht?
  static bool licht = false;
}

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
Color get kAchtergrond => Thema.licht ? const Color(0xFFF3EFE7) : const Color(0xFF07080C);

/// Een vlak dat juist NAAR BINNEN ligt: een zoekveld, een voortgangsbaan, de goot achter een lijst.
///
/// Nieuw. Deze bestond niet, en daardoor werd een tekstveld getekend als een paneel — iets wat van
/// de pagina af komt terwijl je erin typt.
Color get kVerzonken => Thema.licht ? const Color(0xFFE9E4DA) : const Color(0xFF101219);

/// Een paneel: kaartjes, rijen, alles wat van de achtergrond af komt.
Color get kPaneel => Thema.licht ? const Color(0xFFFBF9F5) : const Color(0xFF171A24);

/// Een paneel dat aandacht heeft (aangewezen, geopend, actief).
Color get kPaneelHoog => Thema.licht ? const Color(0xFFE6E0D3) : const Color(0xFF222736);

/// Wat óver de app heen ligt: een menu, een blad, een dialoog.
///
/// Nieuw. Menu's stonden op [kPaneelHoog], dus een menu boven een aangewezen rij had exact de kleur
/// van die rij.
Color get kBovenop => Thema.licht ? const Color(0xFFFFFFFF) : const Color(0xFF2B3142);

/// Scheidingslijnen en randen.
Color get kLijn => Thema.licht ? const Color(0xFFD6CEC0) : const Color(0xFF2A2F3F);

/// Een scheiding die er hoort te zijn zonder dat je hem opmerkt: tussen twee regels in een lijst.
Color get kLijnZacht => Thema.licht ? const Color(0xFFE4DDD1) : const Color(0xFF1E222E);

/// Gewone tekst.
Color get kTekst => Thema.licht ? const Color(0xFF1E1B16) : const Color(0xFFE8EAF2);

/// Bijzaken: artiestnamen onder een titel, tellingen, tijden.
Color get kGedempt => Thema.licht ? const Color(0xFF655E53) : const Color(0xFF9AA0B4);

/// Wat er wél staat maar niet kan: een menuregel die voor dít ding niets betekent.
///
/// Lichter dan [kGedempt], want gedempt is nog steeds tekst die je hoort te lezen — dit is tekst
/// die je hoort over te slaan. Zie [MenuRegel.uit]: bij een ontbrekend nummer werkt de helft van het
/// menu niet, en die regels weglaten zou het menu elke keer een andere vorm geven.
Color get kUitgezet => Thema.licht ? const Color(0xFFA39B8E) : const Color(0xFF5A6076);

/// Het merkpaars. Knoppen die iets dóén, de actieve navigatiepil, de focusring.
Color get kAccent => Thema.licht ? const Color(0xFF5B3CE0) : const Color(0xFF7C5CFF);

/// De tweede accentkleur, voor wat leeft: radiostatus, "nu bezig".
Color get kAccent2 => Thema.licht ? const Color(0xFF00796F) : const Color(0xFF00D4C8);

/// De kleur van een waas of een oplichtend randje bovenop een paneel: wit op donker, zwart op licht.
///
/// **Waarom dit er sinds het lichte thema bij moest.** Overal stond `Colors.white.withValues(alpha:
/// .06)` voor "dit vlak licht een tikje op". Op een gebroken witte pagina is dat wit op wit: niets.
/// Wat bedoeld is, is "een tikje meer contrast met de laag eronder", en dat is op licht zwart.
///
/// Niet voor tekst of iconen bovenop een hoes of een paarse knop — daar blijft het wit.
Color get kInkt => Thema.licht ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

/// Het felste wat er op een laag kan: wit op donker, de tekstkleur op licht.
///
/// Voor alles wat op donker wit was OMDAT wit daar het meest opvalt: een tekst die oplicht bij
/// aanwijzen, de titel van een geselecteerde regel, de ronde speelknop, de knop op een grijs vlak.
/// Op licht valt juist donker het meest op. Tekst op paars of op een hoes blijft gewoon wit.
Color get kFel => Thema.licht ? const Color(0xFF1E1B16) : const Color(0xFFFFFFFF);

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

// ── Kleuren die voor donker gekozen zijn ─────────────────────────────────────
//
// In de schermen staan tientallen losse kleuren voor waarschuwingen, fouten, "gelukt" en zachte
// tekst: amber #E8913A, rood #FF6B6B, groen #6BCB8B, lichtgrijs #C7CBDA. Allemaal gekozen om op
// zwart te lezen, en op gebroken wit haalt amber nauwelijks 2:1. Veertig lichte tegenhangers met de
// hand kiezen is veertig kansen om er één te vergeten; deze drie regels doen het voor allemaal
// (18-10-2026, licht thema). Op donker geven ze precies terug wat erin gaat.

/// Op donker [donker], op licht [licht].
Color perThema(Color donker, Color licht) => Thema.licht ? licht : donker;

/// Tekst of een teken in een kleur die voor donker gekozen is: op donker ongewijzigd, op licht
/// dezelfde tint zo ver donkerder dat hij 4,5:1 haalt op het donkerste lichte vlak ([kPaneelHoog]).
Color leesbaar(Color c) {
  if (!Thema.licht) return c;
  return _leesbaar.putIfAbsent(c.toARGB32(), () {
    const op = Color(0xFFE6E0D3);
    var h = HSLColor.fromColor(c.withValues(alpha: 1));
    while (contrast(h.toColor(), op) < 4.5 && h.lightness > .02) {
      h = h.withLightness((h.lightness - .02).clamp(0.0, 1.0));
    }
    return h.toColor().withValues(alpha: c.a);
  });
}

final _leesbaar = <int, Color>{};

/// Een vlak in een kleur die voor donker gekozen is (de donkerrode grond van een foutmelding, het
/// donkergouden randje van een hi-res-merkje): op licht dezelfde tint, heel licht. [rand]: voor een
/// randje, dat iets donkerder moet blijven dan het vlak dat het omringt.
Color vlakOpThema(Color c, {bool rand = false}) {
  if (!Thema.licht) return c;
  final h = HSLColor.fromColor(c);
  return h.withLightness(((rand ? .80 : .94) - h.lightness * .25).clamp(0.0, 1.0)).toColor();
}

/// Een waas in de kleur van de pagina, voor de verlopen waarmee een foto in de pagina oplost: op
/// donker zoals hij altijd was ([donker], #07080C of zwart), op licht gebroken wit met dezelfde dekking.
Color paginaWaas(int alpha, {Color donker = const Color(0xFF07080C)}) =>
    (Thema.licht ? kAchtergrond : donker).withAlpha(alpha);

/// Hetzelfde als [paginaWaas], met de dekking als getal van 0 tot 1.
Color paginaWaasOp(double dekking, {Color donker = const Color(0xFF07080C)}) =>
    (Thema.licht ? kAchtergrond : donker).withValues(alpha: dekking);
