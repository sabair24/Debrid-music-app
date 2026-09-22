/// Het volgende nummer alvast op de telefoon, voor de gaten in je mobiele verbinding.
///
/// **Waarom dit bestaat — gemeten op 22-09-2026.** In `speler.log` van de telefoon staan 267
/// time-outs naar de pc, en ze vallen in blokken. Op 21-09 in de sportschool zeven keer tussen 16:15
/// en 17:26: elk blok anderhalf tot vijf minuten, met acht tot achttien minuten ertussen waarin alles
/// gewoon speelde. Thuis op 4G, dezelfde telefoon en dezelfde tunnel: twintig pings zonder verlies,
/// en de muziekpoort van de pc tien van de tien keer bereikbaar in gemiddeld 64 ms. Tailscale liep
/// rechtstreeks over het IPv6-adres van de provider; wisselt de telefoon binnen van mast, dan zoekt
/// Tailscale opnieuw de weg, en zolang antwoordt er niemand. De pc zelf sliep niet: hij gaat alleen
/// 's nachts in slaap.
///
/// Midden in een nummer vangt het vooruitlezen dat op. Maar het vólgende nummer werd pas geopend
/// als het huidige afliep, en viel de wissel in zo'n gat, dan bleef de app op dat nummer staan: één
/// herkansing na vier tellen, en die haalt bij een time-out nul procent (zie `kHerkansingNa`).
///
/// Vandaar twee dingen. Zolang het huidige nummer speelt, het volgende al helemaal binnenhalen —
/// op wifi niet, daar zijn die gaten er niet, en een telefoon die een hele avond elk nummer twee keer
/// wegschrijft slijt voor niets. En lukt het openen toch niet, blijven proberen in plaats van stil
/// te blijven staan.
library;

/// Wat er nu vooruit gehaald hoort te worden, en wat er mag blijven staan.
///
/// [stroomt] zegt of een pad van de pc zou komen. Een nummer dat al op de telefoon staat — offline
/// bewaard, of al vooruitgehaald — hoeft niet nog eens.
///
/// [houden] is altijd wat speelt en wat erna komt, ook op wifi: zo ruimt elke wissel de rest op, en
/// blijft er na een avond sporten niets liggen.
({String? halen, Set<String> houden}) vooruitPlan({
  required String? huidig,
  required String? volgende,
  required bool opMobiel,
  required bool Function(String pad) stroomt,
}) {
  final houden = {if (huidig != null) huidig, if (volgende != null) volgende};
  if (!opMobiel || volgende == null || volgende == huidig || !stroomt(volgende)) {
    return (halen: null, houden: houden);
  }
  return (halen: volgende, houden: houden);
}

/// Hoe lang het huidige nummer moet spelen voordat het volgende gehaald wordt.
///
/// **Niet meteen bij het openen.** Op een zwakke lijn vecht dat met de buffer van het nummer dat je
/// hóórt — die heeft op mobiel negentig seconden vooruit nodig. En wie door een plaat heen klikt zou
/// anders bij elk nummer een download starten en meteen weer weggooien: dat is data die je betaalt
/// voor muziek die je niet hoorde.
const kVooruitNa = Duration(seconds: 20);

/// En daarna nog eens kijken, zolang het nummer speelt.
///
/// **Waarom herhalen.** Gemeten op 22-09-2026 op de telefoon: "VOORUIT MISLUKT — Beautiful —
/// afgebroken bij 13 MB van 27 MB", precies in een hapering van de verbinding. Zonder herhaling
/// blijft die helft liggen tot het nummer voorbij is, terwijl de lijn er tien seconden later weer
/// was. Het ophalen gaat verder waar het stopte (Range), dus een tweede poging kost alleen wat er
/// nog ontbreekt.
const kVooruitHerhaal = Duration(seconds: 30);

/// Hoe lang de app blijft proberen een nummer van de pc te openen als de pc niet antwoordt.
///
/// De blokken in de sportschool duurden tot vijf minuten. Tien is ruim, en daarna is het geen gat
/// meer maar een pc die uit staat.
const kNetGeduld = Duration(minutes: 10);

/// De tijd tussen twee pogingen.
///
/// ffmpeg probeert zelf al met oplopende tussenpozen: in de sportschool 5, 6, 8, 12, 20 en 36
/// seconden, samen anderhalve minuut, en pas daarna meldt mpv een fout. Twintig seconden daarna nog
/// eens openen is dus geen gehamer, en toch snel genoeg dat je het merkt als de pc terug is.
const kNetTussenpoos = Duration(seconds: 20);

/// Is dit een fout waar wachten iets aan kan doen?
///
/// Alleen wat over het NETWERK gaat. "Failed to recognize file format" of "Error decoding audio"
/// wordt over twintig seconden niet beter, en "Failed to open http" staat er ook bij een geweigerde
/// sleutel of een bestand dat de pc niet meer kent — de netwerkfout zelf komt altijd eerst als eigen
/// regel (`tcp: ... Connection timed out`), dus die volstaat.
bool isNetwerkfout(String fout) => RegExp(
      r'timed out|Connection refused|Network is unreachable|No route to host|Connection reset|'
      r'connection abort|Host is unreachable',
      caseSensitive: false,
    ).hasMatch(fout);

/// Wat er gebeurt als een nummer niet opengaat, per poging.
enum NaOpenfout {
  /// Het volgende nummer staat al op de telefoon: daarheen, muziek gaat voor de volgorde.
  naarVolgende,

  /// Over [kNetTussenpoos] opnieuw proberen.
  opnieuw,

  /// Na [kNetGeduld] zonder pc: stoppen en het zeggen.
  opgeven,
}

/// De regel achter een nummer dat niet opengaat.
NaOpenfout naOpenfout({required Duration sinds, required bool volgendeStaatHier}) {
  if (volgendeStaatHier) return NaOpenfout.naarVolgende;
  if (sinds >= kNetGeduld) return NaOpenfout.opgeven;
  return NaOpenfout.opnieuw;
}
