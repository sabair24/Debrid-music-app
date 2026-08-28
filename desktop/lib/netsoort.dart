/// Wifi of mobiele data, en wat de app daarmee doet.
///
/// **Waarom dit een eigen bestand is.** De keuze "welke stroomstand geldt nu" hangt van vier dingen
/// af — wat je thuis wilt, wat je onderweg wilt, of het automatisch mag, en waar je nu op zit — en
/// dat is precies het soort som dat je nergens tussen de schermcode wilt hebben staan. Hier staat
/// hij één keer, zuiver, en de bouwstraat kan hem nameten.
///
/// **Wat "adaptief" hier NIET is.** Er wordt geen bandbreedte gemeten en er wordt niet midden in een
/// nummer overgeschakeld — dat kan ook niet: het plafond staat in de URL en die wordt bij het openen
/// vastgelegd. Het zijn twee eenvoudige regels, en die staan hieronder uitgeschreven.
library;

import 'lan/stroomstand.dart';

/// Waar dit toestel nu op zit.
///
/// `onbekend` is een volwaardig antwoord en geen fout: op een pc, op een Mac, en op elk toestel
/// waar de vraag niet beantwoord kon worden. Zie [welkeStand] voor waarom dat naar THUIS valt en
/// niet naar onderweg.
enum Netsoort { wifi, mobiel, onbekend }

/// Regel A: de netsoort kiest de sport.
///
/// **`onbekend` valt naar [thuis], en dat is met opzet de dure kant.** Een mislukte meting — een
/// kanaal dat nog niet klaar is, een platform zonder antwoord — mag je thuis nooit stilletjes je
/// hi-res kosten. Andersom kost een gemiste meting onderweg hooguit een keer meer data dan je wilde,
/// en dát merk je; een stille terugval naar cd-kwaliteit thuis merk je niet en zoek je nooit.
///
/// Staat [adaptief] uit, dan geldt [thuis] altijd — dan is er één stand en verder niets.
///
/// [noodstand] is regel B: één sport lager voor de rest van deze sessie, nadat het hapert. Zie
/// [eenSportLager].
Stroomstand welkeStand({
  required Stroomstand thuis,
  required Stroomstand onderweg,
  required bool adaptief,
  required Netsoort net,
  bool noodstand = false,
}) {
  final gekozen = (adaptief && net == Netsoort.mobiel) ? onderweg : thuis;
  return noodstand ? eenSportLager(gekozen) : gekozen;
}

/// Regel B: één sport omlaag, en nooit onder de onderste.
///
/// **En nooit vanzelf terug omhoog.** Een ladder die na een geslaagd nummer weer opklimt lokt precies
/// de hapering uit die hij net heeft opgelost, en dan zit je in een lus die om de twee nummers
/// stottert. De grendel gaat pas los als er iets verandert waar de gebruiker bij was: een andere
/// netsoort, een aangeraakte instelling, of een herstart.
Stroomstand eenSportLager(Stroomstand s) => switch (s) {
      Stroomstand.max => Stroomstand.hoog,
      Stroomstand.hoog => Stroomstand.cd,
      Stroomstand.cd => Stroomstand.cd,
    };

/// Hoeveel seconden vooruit er gelezen mag worden.
///
/// **Op wifi verandert er niets, en dat is een eis.** De driehonderd seconden zijn de reparatie van
/// 15-08-2026 voor draadloos Android Auto: hi-res FLAC over een wifi die tegelijk de autoverbinding
/// draagt. Een heel nummer vooruit hebben maakt een dip onhoorbaar. Daar mag niet aan getornd worden.
///
/// **Op mobiel is vooruitlezen niet gratis meer.** Driehonderd seconden op de cd-stand is ruwweg
/// vierendertig megabyte per nummer; skip je na twintig seconden door, dan gooi je tweeëndertig
/// megabyte weg waar je voor betaald hebt. Negentig seconden is een kleine tien megabyte en nog
/// altijd veel langer dan elke realistische dip in een 4G-verbinding.
int vooruitleesSeconden(Netsoort net) => net == Netsoort.mobiel ? 90 : 300;
