/// Wat je met een versie doet (versies.dart), op de pc — vanaf zijn eigen scherm of vanaf een toestel (`/api/versie`).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'library.dart';
import 'models.dart';
import 'prullenbak.dart';
import 'versies.dart';

/// Welke versie er voor [anker] speelt: [gekozen] (het pad van een versie, of van het nummer zelf), voor [bereik]. Null
/// als bereik: alleen nu, niets onthouden — dan wist dit een eerdere keuze voor dit nummer niet. Geeft de zin terug.
String kiesVersie(LibraryStore library, Track anker, String gekozen, VersieBereik? bereik) {
  final lijst = library.versiesVan(anker);
  final v = lijst.where((x) => x.track.path == gekozen).firstOrNull;
  if (v == null) return 'Die versie staat er niet meer';
  if (bereik == null) return 'Niet onthouden';
  versies.kies(anker.path, v.sleutel.isEmpty ? null : v.sleutel, bereik: bereik);
  // Het nummer zelf kiezen voor dit nummer: geen aparte keuze nodig, behalve als de plaat iets anders zegt.
  return switch (bereik) {
    VersieBereik.nummer => 'Onthouden voor dit nummer: ${v.label}',
    VersieBereik.plaat => 'Onthouden voor deze plaat: ${v.label}',
  };
}

/// Wie een versie naar de prullenbak brengt; een toets zet er een nep in, zodat hij nooit de echte prullenbak raakt.
@visibleForTesting
Future<Set<String>> Function(List<String> paden) versiePrullenbak = naarPrullenbak;

/// Versie [pad] van [anker] naar de prullenbak (Saber: alles bewaren — maar wat je zelf weggooit, gaat weg). Het nummer
/// zelf gooit dit niet weg: dat doet de gewone weg (Verwijderen). Geeft de zin terug.
Future<String> gooiVersieWeg(LibraryStore library, Track anker, String pad) async {
  final v = versies.versie(pad);
  if (v == null || versies.ankerVan(pad) == null) return 'Dat is geen versie (meer) van dit nummer';
  if (!heeftPrullenbak) return 'Op dit systeem is er geen prullenbak — de versie blijft staan';
  final weg = await versiePrullenbak([pad]);
  if (!weg.contains(pad) && File(pad).existsSync()) return 'Naar de prullenbak lukte niet — de versie blijft staan';
  versies.verwijder(pad);
  await library.scan();
  return 'Versie in de prullenbak: ${versieLabel(v.soort, v.persing)}';
}
