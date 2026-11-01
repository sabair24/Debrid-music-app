/// Speakers van verschillende merken samen (Saber, 01-11-2026: de Nest Minis "in group met andere zones"; gekozen:
/// "via de app met Sonos/KEF/Shield/toestellen, ongeveer gelijk, met de schuif zoals bij Sonos").
///
/// Sonossen onderling spelen zelf op de seconde gelijk (een groep in de Sonos). Tussen merken kan dat niet: daar laat de
/// pc de VOLGER hetzelfde nummer spelen en zet hem bij op de plek van de LEIDER, door te spoelen.
///
/// **Gemeten op de echte Nest Mini "Kantoor" (01-11-2026, volume 0):** na een SEEK staat zijn plek 0,2–0,4 s stil en
/// loopt hij daarna gewoon mee — maar achter: 650 ms (het stuk stond nog niet in zijn buffer, BUFFERING), 200 ms en
/// 145 ms (wel). Hoeveel hij achterloopt hangt dus af van zijn buffer: daarom leert de volger het ([leerVoorsprong]) en
/// spoelt hij hoogstens [kVolgPogingen] keer per nummer, niet eindeloos (elke keer is een hikje op die speaker).
library;

import 'google_cast.dart';
import 'kef.dart';
import 'upnp.dart';

/// Wie in een groep van merken leidt: wie het minst precies te sturen is. Een Sonos meldt zijn plek per seconde en
/// spoelt op hele seconden; een KEF meldt in blokjes van 48 ms; een Nest meldt en spoelt tot op de ms. Dus leidt de
/// Sonos en volgt de Nest. Lager = eerder leider.
int leiderRang(Renderer r) => r.isSonos ? 0 : (isKef(r) ? 1 : (isCast(r) ? 3 : 2));

/// De leider van [r] (bij gelijke rang de eerste: wie je koos).
Renderer besteLeider(List<Renderer> r) {
  var beste = r.first;
  for (final x in r.skip(1)) {
    if (leiderRang(x) < leiderRang(beste)) beste = x;
  }
  return beste;
}

/// Speelt [lid] in de eigen groep van de Sonos [leider] mee (op de seconde gelijk, door de Sonossen zelf), in plaats van
/// via de pc?
bool speeltVanzelfMee(Renderer leider, Renderer lid) =>
    leider.isSonos && leider.udn.isNotEmpty && lid.isSonos && lid.udn.isNotEmpty;

/// Hoe ver de volger ernaast mag zitten (ms) voor hij bijgezet wordt. Twee speakers in andere kamers: onder de ~60 ms
/// hoor je geen echo; de plek van een Sonos-leider is ±15 ms bekend (speakerklok-sonos-meting).
const kVolgMarge = 60;

/// Hoe vaak per nummer de volger gespoeld wordt. Daarna laat de pc hem: liever een vaste afstand dan een hik om de paar
/// seconden. Een nieuw nummer begint weer bij nul.
const kVolgPogingen = 4;

/// Hoe lang na het spoelen de volger met rust gelaten wordt (ms): zijn plek staat 0,2–0,4 s stil en zijn klok moet de
/// nieuwe plek eerst weer zien.
const kVolgRust = 2500;

/// Waarmee de volger begint te spoelen vóór de plek van de leider (ms): de 145–200 ms die de Nest meestal achterliep.
const kVoorsprongStart = 200;

/// Hoogstens zoveel vooruit (ms).
const kVoorsprongMax = 2000;

/// In de laatste zoveel ms van het nummer niet meer spoelen: de volger kan dan al naadloos naar het volgende zijn, en zijn
/// plek hoort bij een ander nummer dan die van de leider.
const kVolgEindRust = 5000;

enum VolgStap { niets, pauze, verder, spoel }

/// Wat de volger nu moet doen, met [leider] en [volger] zoals ze NU zijn (de plek in ms, op dezelfde klok).
///
/// - De leider staat stil en de volger speelt: pauze.
/// - De leider speelt en de volger staat stil (gepauzeerd met de leider): verder.
/// - Allebei aan het spelen, en de volger zit meer dan [kVolgMarge] naast `leider + vertraging`: spoelen naar die plek
///   plus [voorsprongMs], want daar is de leider tegen de tijd dat de volger weer speelt. Niet vaker dan
///   [kVolgPogingen] keer per nummer, niet binnen [kVolgRust] na de vorige keer, en niet als de leider nog minder dan
///   [kVolgEindRust] te gaan heeft ([leiderRestMs]; null = onbekend).
///
/// [vertragingMs] is de schuif: positief = de volger later (hij klinkt anders vóór de leider).
({VolgStap stap, int doelMs}) volgBesluit({
  required ({bool speelt, int positieMs})? leider,
  required ({bool speelt, int positieMs})? volger,
  required int vertragingMs,
  required int voorsprongMs,
  required int pogingen,
  required int sindsSpoelenMs,
  int? leiderRestMs,
}) {
  const niets = (stap: VolgStap.niets, doelMs: 0);
  if (leider == null || volger == null) return niets;
  if (!leider.speelt) return volger.speelt ? (stap: VolgStap.pauze, doelMs: 0) : niets;
  if (!volger.speelt) return (stap: VolgStap.verder, doelMs: 0);
  final doel = leider.positieMs + vertragingMs;
  if ((volger.positieMs - doel).abs() <= kVolgMarge) return niets;
  if (pogingen >= kVolgPogingen || sindsSpoelenMs < kVolgRust) return niets;
  if (leiderRestMs != null && leiderRestMs < kVolgEindRust) return niets;
  final naar = doel + voorsprongMs;
  return (stap: VolgStap.spoel, doelMs: naar < 0 ? 0 : naar);
}

/// De voorsprong na een keer spoelen: liep de volger daarna [foutMs] voor (positief) of achter (negatief), dan de
/// volgende keer zoveel minder of meer.
int leerVoorsprong(int voorsprongMs, int foutMs) => (voorsprongMs - foutMs).clamp(0, kVoorsprongMax);
