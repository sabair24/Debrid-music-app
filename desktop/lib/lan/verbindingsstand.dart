/// Wat de regel bovenin zegt over de weg naar je pc — en, als die er niet is, waarom niet.
///
/// **Waarom.** Stap 4 van "verbinden zoals Roon ARC" (plan 14-10-2026). Bij het verlaten van het huis
/// zag Saber niets: de bibliotheek bleef staan zoals ze thuis geladen was, en de melding bovenin kwam
/// alleen als het scherm een kopie toonde. Of de app de pc zocht, hem via Tailscale vond, of hem niet
/// vond omdat de pc sliep — dat was van buitenaf niet te onderscheiden. Nu staat er "Zoekt je pc… 3 s",
/// en daarna de weg of de reden.
///
/// **De reden komt uit de hartslag van de pc.** De pc schrijft in je account (`servers/{id}`) dat hij
/// aan staat: meteen bij elke verandering, anders elke minuut (`kHartslagRitme` in `zuinig.dart`, op
/// een klok van dertig seconden), en `online: false` bij het afsluiten. Hoe oud die regel is, rekent deze klasse met
/// de klok van Firestore aan béide kanten: `updateTime` van het document en de `Date`-kop van
/// hetzelfde antwoord. Een gsm waarvan de klok een uur verkeerd staat, zegt dus nog steeds het goede.
library;

import 'dart:io' show InternetAddress;

import 'tokens.dart' show toestelWeg;

/// Langs welke weg dit toestel nu met de pc praat.
enum Verbindingsweg { thuis, tailscale, rechtstreeks }

/// De weg naar dit adres. Een IP-adres via [toestelWeg] (dezelfde indeling als in de toestellenlijst
/// op de pc); een naam: `*.ts.net` is Tailscale, een naam zonder punt of op `.local` is thuis, de rest
/// is rechtstreeks.
Verbindingsweg wegNaar(Uri adres) {
  final host = adres.host;
  final ip = InternetAddress.tryParse(host);
  if (ip == null) {
    final h = host.toLowerCase();
    if (h.endsWith('.ts.net')) return Verbindingsweg.tailscale;
    if (!h.contains('.') || h.endsWith('.local')) return Verbindingsweg.thuis;
    return Verbindingsweg.rechtstreeks;
  }
  return switch (toestelWeg(ip)) {
    'Tailscale' => Verbindingsweg.tailscale,
    'thuis' || 'deze pc' => Verbindingsweg.thuis,
    _ => Verbindingsweg.rechtstreeks,
  };
}

/// Waarom de pc niet te bereiken is.
enum Waarom {
  /// `online: false`: de app op de pc is netjes afgesloten (of de pc uitgezet).
  pcUit,

  /// De pc schreef minder dan drie minuten geleden dat hij aan staat, maar van hier komt er niets
  /// door: de weg naar binnen ontbreekt.
  pcAanMaarDicht,

  /// Drie tot vijf minuten oud: een gemiste slag of een pc die net in slaap viel. Nog geen oordeel.
  twijfel,

  /// Meer dan vijf minuten niets: de pc slaapt, staat uit zonder af te sluiten, of heeft zelf geen
  /// internet.
  pcStil,

  /// Dit toestel heeft zelf geen netwerk.
  geenInternet,

  /// Geen account op dit toestel, of de hartslag was niet te lezen.
  onbekend,
}

/// Wat de pc het laatst over zichzelf in je account schreef.
class Hartslag {
  const Hartslag({required this.online, this.bijgewerkt, this.serverNu});

  final bool online;

  /// `updateTime` van het document: wanneer de pc het laatst schreef, volgens Firestore.
  final DateTime? bijgewerkt;

  /// De `Date`-kop van hetzelfde antwoord: "nu", volgens Firestore.
  final DateTime? serverNu;
}

/// De hartslag kon niet gelezen worden omdat Firestore helemaal niet bereikbaar was (geen antwoord,
/// geen statuscode) — vrijwel altijd: geen internet op dit toestel.
class HartslagOnbereikbaar implements Exception {
  const HartslagOnbereikbaar();
}

const Duration kHartslagVers = Duration(minutes: 3);
const Duration kHartslagOud = Duration(minutes: 5);

/// Ouder dan dit, en de hartslag zegt niets meer: de pc schrijft hem niet bij (niet aangemeld bij je
/// account). Gemeten 14-10-2026: een regel van 31 dagen oud met `online: false` gaf "DebridMusic staat
/// uit op je pc" terwijl de pc gewoon draaide — alleen niet aangemeld.
const Duration kHartslagVergeten = Duration(days: 1);

/// De reden, uit wat er bekend is. [toestelNu] telt alleen als de `Date`-kop ontbrak.
Waarom waaromNiet({Hartslag? hartslag, bool geenNetwerk = false, DateTime? toestelNu}) {
  if (geenNetwerk) return Waarom.geenInternet;
  final h = hartslag;
  if (h == null) return Waarom.onbekend;
  final bij = h.bijgewerkt;
  if (bij == null) return Waarom.onbekend;
  final leeftijd = (h.serverNu ?? toestelNu ?? DateTime.now()).difference(bij);
  if (leeftijd > kHartslagVergeten) return Waarom.onbekend;
  // Gaat voor de rest van de leeftijd: afsluiten schrijft `online: false`, en dat maakt het document
  // juist vers. Een dag oud mag nog: de app is dan afgesloten en sindsdien niet meer gestart.
  if (!h.online) return Waarom.pcUit;
  if (leeftijd <= kHartslagVers) return Waarom.pcAanMaarDicht;
  if (leeftijd > kHartslagOud) return Waarom.pcStil;
  return Waarom.twijfel;
}

enum Verbindingssoort { verbonden, zoekt, weg }

/// Eén stand van de verbinding: verbonden langs een weg, aan het zoeken sinds een tijdstip, of weg met
/// een reden.
class Verbindingsstand {
  const Verbindingsstand.verbonden(Verbindingsweg this.weg)
      : soort = Verbindingssoort.verbonden,
        sinds = null,
        waarom = null;

  const Verbindingsstand.zoekt(DateTime this.sinds)
      : soort = Verbindingssoort.zoekt,
        weg = null,
        waarom = null;

  const Verbindingsstand.weg(Waarom this.waarom)
      : soort = Verbindingssoort.weg,
        weg = null,
        sinds = null;

  final Verbindingssoort soort;
  final Verbindingsweg? weg;
  final DateTime? sinds;
  final Waarom? waarom;

  /// Zelfde stand voor het scherm: een nieuwe zoektocht met een ander begin telt niet als wissel.
  bool zelfde(Verbindingsstand o) => soort == o.soort && weg == o.weg && waarom == o.waarom;

  @override
  String toString() => verbindingsTekst(this, nu: sinds ?? DateTime.now());
}

/// Wat er bovenin staat. [kort] voor een telefoon (hoogstens twee regels naast een knop). [eigenDeur]
/// is vanaf uitlevering B waar: dan heeft de pc een eigen weg naar buiten en ligt een verse hartslag
/// zonder verbinding aan de modem. Tot dan is Tailscale de enige weg van buitenaf, en dat zegt de
/// tekst ook.
String verbindingsTekst(
  Verbindingsstand s, {
  required DateTime nu,
  bool kort = false,
  bool eigenDeur = false,
  String toestel = 'dit toestel',
}) {
  switch (s.soort) {
    case Verbindingssoort.verbonden:
      return switch (s.weg!) {
        Verbindingsweg.thuis => 'Thuis',
        Verbindingsweg.tailscale => 'Onderweg — via Tailscale',
        Verbindingsweg.rechtstreeks => 'Onderweg — rechtstreeks',
      };
    case Verbindingssoort.zoekt:
      final sec = nu.difference(s.sinds!).inSeconds;
      return 'Zoekt je pc… ${sec < 0 ? 0 : sec} s';
    case Verbindingssoort.weg:
      return switch (s.waarom!) {
        Waarom.pcUit => 'DebridMusic staat uit op je pc',
        Waarom.pcAanMaarDicht => eigenDeur
            ? 'Je modem laat de verbinding niet door'
            : kort
                ? 'Je pc staat aan, maar is van hier niet bereikbaar — staat Tailscale aan?'
                : 'Je pc staat aan, maar is van hier niet bereikbaar. Buitenshuis gaat dat voorlopig '
                    'alleen via Tailscale — staat die aan op $toestel?',
        Waarom.twijfel => 'Zoekt je pc…',
        Waarom.pcStil => 'Je pc antwoordt niet (staat hij aan of slaapt hij?)',
        Waarom.geenInternet => 'Geen internet op $toestel',
        Waarom.onbekend => 'Je pc reageert niet',
      };
  }
}
