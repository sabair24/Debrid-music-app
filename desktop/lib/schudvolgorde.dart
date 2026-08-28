/// In welke volgorde vijfduizend nummers klinken als je op shuffle drukt.
///
/// **Waarvoor dit bestaat.** Gevraagd op 28-08-2026: *"ik wil dat de app daar in uitblinkt… ik wil
/// per sessie dat ik op shuffle track klik elk liedje maar 1 keer afspeeld, zelf zijn het meer dan
/// 5000 liedjes. plus ik wil dat de app bij een volgende shuffle onthoud welke liedjes al veel zijn
/// afgespeeld."* Twee eisen, en ze bijten elkaar bijna: "elk nummer precies één keer" is een
/// permutatie, en "wat je vaak hoorde naar achteren" is een voorkeur. Allebei tegelijk kan, en dat
/// is precies wat hieronder staat.
///
/// **Waarom dit een eigen, zuiver bestand is.** Geen netwerk, geen schijf, geen Flutter: nummers en
/// getallen in, een volgorde uit. Een fout hier valt niet om maar doet stilletjes het verkeerde —
/// een nummer dat in de trekking verdwijnt, een blok dat in bibliotheekvolgorde blijft plakken, een
/// lievelingsnummer dat je nooit meer hoort. Geen daarvan gooit; alle drie merk je pas na een week
/// luisteren. Hier staat de som één keer, en de bouwstraat kan hem nameten
/// (`test/schudvolgorde_test.dart`).
library;

import 'dart:math';

import 'models.dart';
import 'organize.dart' show artistKey, normKey;

/// Hoe vaak en hoe lang geleden een nummer geklonken heeft.
///
/// Een eigen klasse en niet die uit `lan/state_store.dart`, zodat dit bestand niets van de LAN-laag
/// hoeft te weten en een toets hem met de hand kan vullen.
class Speelstand {
  const Speelstand({this.aantal = 0, this.laatstMs = 0});

  /// Hoe vaak dit nummer als beluisterd geteld is. Zie [telMeeAlsGespeeld] voor wat dat betekent.
  final int aantal;

  /// Wanneer voor het laatst, in millisyseconden sinds 1970. Nul = nooit.
  final int laatstMs;
}

/// Het gewicht van één nummer in de trekking. 1,0 is "nooit gehoord".
///
/// **De vorm, en waarom.** `vers = ½^(dagen/[halveringDagen])` maakt een oude beurt bijna gratis;
/// `druk = aantal × vers` is dus "hoe vaak, maar alleen voor zover het nog telt". Daaruit
/// `w = 1 / (1 + kracht × druk)`.
///
/// Wat dat doet, in getallen: één keer vandaag gehoord geeft 0,25 — gemiddeld vier keer zo diep in
/// de lijst. Vier keer vandaag geeft 0,077, dus dertien keer zo diep. Twintig keer maar een jaar
/// geleden geeft weer bijna 1, en dat is de bedoeling: bij vijfduizend nummers moet een hoek die je
/// een half jaar niet hoorde gewoon weer meedoen.
///
/// **[bodem] is er zodat een gewicht NOOIT nul wordt.** Een lievelingsnummer moet vooraan kúnnen
/// vallen. Zonder die bodem is dit geen shuffle meer maar een lijstje — en dat is precies wat er
/// niet gevraagd is.
double gewichtVan(
  Speelstand? s, {
  required int nuMs,
  double halveringDagen = 30,
  double kracht = 3,
  double bodem = .02,
}) {
  if (s == null || s.aantal <= 0) return 1;
  // Een toekomstige klok (een toestel dat verkeerd staat) is "zojuist", niet "over een jaar".
  final dagen = s.laatstMs <= 0
      ? halveringDagen * 12
      : max(0, (nuMs - s.laatstMs)) / Duration.millisecondsPerDay;
  final vers = pow(.5, dagen / halveringDagen).toDouble();
  final druk = s.aantal * vers;
  return (1 / (1 + kracht * druk)).clamp(bodem, 1.0).toDouble();
}

/// Telt dit als beluisterd? De helft van het nummer, of twee minuten — wat het eerst komt.
///
/// **[geluisterd] is opgetelde luistertijd, niet de stand van de teller.** Dat verschil is de hele
/// reparatie: naar de stand kijken telt een nummer mee dat je op 80% opendraaide en meteen wegklikte,
/// en telt een nummer níét mee dat je twee keer half hoorde.
///
/// Twee minuten als plafond, want anders zou een plaatkant van twintig minuten pas na tien minuten
/// meetellen — en wie tien minuten luistert heeft het nummer gehoord. Een duur van null of nul is
/// "onbekend": dan telt alleen de twee minuten.
bool telMeeAlsGespeeld({required Duration geluisterd, required Duration? duur}) {
  const plafond = Duration(minutes: 2);
  if (duur == null || duur <= Duration.zero) return geluisterd >= plafond;
  final helft = Duration(microseconds: duur.inMicroseconds ~/ 2);
  return geluisterd >= (helft < plafond ? helft : plafond);
}

/// Eén gewogen trekking: elk nummer komt er **precies één keer** uit, zwaardere eerder.
///
/// **Efraimidis–Spirakis, in log-vorm.** Elk nummer krijgt de sleutel `-ln(u)/w` met `u` uniform in
/// (0,1]; oplopend gesorteerd is dat een gewogen permutatie zonder teruglegging.
///
/// **Met opzet niet `u^(1/w)`,** de vorm die overal als eerste genoemd wordt. Met een bodem van 0,02
/// is de exponent daar 50, en een ongelukkige trekking loopt dan onder naar exact `0.0`. Alle
/// ondergelopen sleutels zijn daarna aan elkaar gelijk, `List.sort` is in Dart niet stabiel, en je
/// krijgt een blok in bibliotheekvolgorde aan één kant van de lijst — een shuffle die alfabetisch
/// begint. De log-vorm heeft dezelfde verdeling, kan niet onderlopen, en kost één `log` in plaats
/// van één `pow`.
///
/// `u = 1 - nextDouble()` en niet `nextDouble()`: die laatste kan exact 0 zijn, en `ln(0)` is
/// min oneindig.
List<Track> gewogenVolgorde(
  List<Track> alles, {
  required double Function(Track) gewicht,
  required Random toeval,
}) {
  if (alles.length < 2) return List.of(alles);
  final sleutels = <double>[];
  for (final t in alles) {
    final w = gewicht(t);
    final u = 1 - toeval.nextDouble();
    sleutels.add(-log(u) / (w <= 0 ? 1e-9 : w));
  }
  final plekken = List<int>.generate(alles.length, (i) => i)
    ..sort((a, b) => sleutels[a].compareTo(sleutels[b]));
  return [for (final i in plekken) alles[i]];
}

/// Dezelfde artiest of plaat uit elkaar trekken, zonder de weging weg te gooien.
///
/// **Waarom dit nodig is bij écht toeval.** Een zuivere trekking geeft klonters: bij vijfduizend
/// nummers komen er onvermijdelijk drie van dezelfde plaat achter elkaar te staan. Dat is
/// wiskundig correct en leest als een kapotte shuffle — het is de reden dat Spotify hier ooit een
/// blogpost over schreef.
///
/// De ingreep is bewust klein: één keer vooruit lopen, en botst een nummer met de vorige [afstand]
/// buren, dan de eerste kandidaat binnen [zoek] plekken naar voren wisselen die dat niet doet. Vindt
/// hij niets, dan blijft het staan — bij een bibliotheek van drie artiesten is klonteren geen fout
/// maar onvermijdelijk. Niets verschuift verder dan [zoek], dus de volgorde die de weging opleverde
/// blijft in grote lijnen staan.
///
/// [vanaf] beschermt wat al geklonken heeft: daar mag niets meer bewegen.
List<Track> uitElkaar(
  List<Track> volgorde, {
  int vanaf = 0,
  int afstand = 5,
  int zoek = 30,
}) {
  final uit = List.of(volgorde);
  if (uit.length - vanaf < 3) return uit;
  // Eén keer uitrekenen. `artistKey` en `normKey` normaliseren tekst, en in de binnenlus zouden ze
  // n × zoek keer draaien — bij 5000 nummers is dat honderdvijftigduizend keer.
  final artiest = [for (final t in uit) artistKey(t.artist)];
  final plaat = [for (final t in uit) normKey(t.album)];

  bool botst(int kandidaat, int plek) {
    final van = max(vanaf, plek - afstand);
    for (var j = van; j < plek; j++) {
      if (artiest[j] == artiest[kandidaat] && artiest[kandidaat].isNotEmpty) return true;
      if (plaat[j] == plaat[kandidaat] && plaat[kandidaat].isNotEmpty) return true;
    }
    return false;
  }

  void wissel(int a, int b) {
    final t = uit[a];
    uit[a] = uit[b];
    uit[b] = t;
    final ar = artiest[a];
    artiest[a] = artiest[b];
    artiest[b] = ar;
    final pl = plaat[a];
    plaat[a] = plaat[b];
    plaat[b] = pl;
  }

  for (var i = vanaf + 1; i < uit.length; i++) {
    if (!botst(i, i)) continue;
    final tot = min(uit.length, i + zoek + 1);
    for (var j = i + 1; j < tot; j++) {
      if (botst(j, i)) continue;
      wissel(i, j);
      break;
    }
  }
  return uit;
}

/// Wat al geklonken heeft eruit halen — **per stuk**, niet per pad.
///
/// **Waarom dat onderscheid ertoe doet.** Hetzelfde nummer mag twee keer in de wachtrij staan; dat
/// is uitdrukkelijk toegestaan en er staat een toets op (`wachtrij_bewerken_test.dart`). Een
/// `removeWhere` op de paden zou bij het eerste exemplaar allebei weggooien, en dan klopt de lengte
/// van de wachtrij niet meer met de index die de speaker terugmeldt. Dezelfde regel als
/// [haalUitWachtrijLijst] gebruikt: eerst op identiteit, dan pas op pad.
List<Track> zonder(List<Track> alles, List<Track> eruit) {
  if (eruit.isEmpty) return List.of(alles);
  final over = List.of(alles);
  for (final weg in eruit) {
    var plek = over.indexWhere((t) => identical(t, weg));
    if (plek < 0) plek = over.indexWhere((t) => t.path == weg.path);
    if (plek >= 0) over.removeAt(plek);
  }
  return over;
}
