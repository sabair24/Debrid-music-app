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

import 'package:flutter/material.dart';

/// De diepste achtergrond — waar niets overheen ligt.
const kAchtergrond = Color(0xFF0C0D12);

/// Een paneel: kaartjes, rijen, alles wat van de achtergrond af komt.
const kPaneel = Color(0xFF181B26);

/// Een paneel dat aandacht heeft (aangewezen, geopend, actief).
const kPaneelHoog = Color(0xFF1F2331);

/// Scheidingslijnen en randen.
const kLijn = Color(0xFF272B3A);

/// Gewone tekst.
const kTekst = Color(0xFFE8EAF2);

/// Bijzaken: artiestnamen onder een titel, tellingen, tijden.
const kGedempt = Color(0xFF9AA0B4);

/// Het merkpaars. Knoppen die iets dóén, de actieve navigatiepil, de focusring.
const kAccent = Color(0xFF7C5CFF);

/// De tweede accentkleur, voor wat leeft: radiostatus, "nu bezig".
const kAccent2 = Color(0xFF00D4C8);
