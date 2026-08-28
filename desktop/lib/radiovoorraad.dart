/// Hoeveel muziek er vóór je moet staan, en wanneer er iets bij gehaald wordt.
///
/// **Het probleem waar dit over gaat.** Een radio die nummers ophaalt terwijl je luistert kan
/// Soulseek niet vertrouwen: dat is peer-to-peer, en een peer die er is als je zoekt kan weg zijn als
/// je aanklopt. Toch mag je nooit een gat horen. De enige manier waarop dat allebei waar kan zijn is
/// de VOLGORDE:
///
/// > Een nummer komt pas in de speelrij als het bestand er werkelijk staat.
///
/// Wat nog opgehaald wordt zit in een voorportaal, niet in de rij. Deze functie beslist wat er uit
/// dat voorportaal de rij in mag en wat er aan haaltjes gestart wordt. Geen IO, geen tijd, geen
/// toeval — alleen tellen, want dit is precies het stuk dat kloppen moet.
library;

/// Wat er met één plek uit het radioplan aan de hand is.
enum Haalstand {
  /// Er is nog niets mee gedaan.
  wacht,

  /// Wordt nu opgehaald.
  onderweg,

  /// Het bestand staat er en je had het AL. Vulling: mag de speelrij in als er anders te weinig
  /// vooruit staat.
  klaar,

  /// Net OPGEHAALD door deze radio, en het bestand staat er.
  ///
  /// **Dit gaat meteen de rij in, en dat is het verschil met [klaar].** Zonder dat onderscheid bleef
  /// een net gehaald nummer in het plan hangen zolang er nog genoeg eigen muziek vooruit stond — en
  /// dat is bijna altijd. Gemeld op 28-08-2026: "de radio downloadt wel maar ze tonen niet op tijd in
  /// de queue, waardoor ik vol zit met gedownloade liedjes die ik niet zag." Precies dat. Je hebt er
  /// schijfruimte voor betaald en erop staan wachten; dan hoort het te klinken, niet in een lijst te
  /// liggen die niemand ziet.
  geland,

  /// Staat al in de speelrij.
  inRij,

  /// Niet te vinden. Slaat over, en telt nergens meer in mee.
  mislukt,
}

/// Wat er nu te doen valt.
///
/// [starten] en [inRij] zijn indexen in dezelfde lijst standen die erin ging, in planvolgorde.
/// [vooruit] is hoeveel er ná dit besluit vóór je staat — het getal waar het allemaal om draait.
typedef Voorraadbesluit = ({List<int> starten, List<int> inRij, int vooruit});

/// Standaard zes speelbare nummers vooruit.
///
/// Waarom zes en niet twee: een nummer duurt drie tot vier minuten, en een Soulseek-haal die goed
/// gaat duurt een halve tot twee minuten — maar een haal die op een trage peer wacht kan de volle
/// [kMaxWacht] opsouperen zonder iets op te leveren. Zes nummers is twintig minuten muziek, en dat
/// overleeft een handvol mislukte pogingen achter elkaar.
const int kMinVooruit = 6;

/// Hoogstens acht haaltjes tegelijk.
///
/// Niet hoger, want Soulseek doet er twaalf tegelijk (`_slskMaxParallel`) en de radio hoort JOUW
/// eigen downloads niet uit te hongeren. Vier plekken blijven dus vrij, wat er ook loopt.
const int kMaxOnderweg = 8;

/// Wat er nu bij mag en wat er nu gestart mag worden.
///
/// [vooruitNu] is hoeveel speelbare nummers er ná het lopende nummer in de rij staan.
///
/// **Twee soorten "klaar", en dat is de hele rekensom.**
///
/// Een net GELAND nummer gaat er onvoorwaardelijk in. Het is opgehaald omdat jij een radio vroeg, het
/// staat op je schijf, en het hoort te klinken — niet in een lijst te liggen die niemand ziet.
///
/// Een nummer dat je AL HAD is vulling. Dat gaat er alleen in als er anders te weinig vooruit staat,
/// en de lus stopt zodra dat opgelost is. Zou alles wat je al hebt er meteen in gaan, dan krijg je
/// eerst een uur eigen muziek en pas daarna het nieuwe — precies het omgekeerde van de bedoeling.
///
/// **De regel die de stilte weghoudt** zit in die tweede lus: hij stapt over een plek heen die nog
/// niet klaar is in plaats van erop te wachten. Zo schuift eigen muziek naar voren zodra een haal te
/// lang duurt. Een overgeslagen plek blijft staan; landt hij later alsnog, dan komt hij daar in de rij
/// waar de radio op dat moment is. De volgorde van een radio is geen belofte.
Voorraadbesluit voorraadPlan(
  List<Haalstand> standen, {
  required int vooruitNu,
  int minVooruit = kMinVooruit,
  int maxOnderweg = kMaxOnderweg,
}) {
  final inRij = <int>[];
  var vooruit = vooruitNu;
  // Eerst alles wat net binnengekomen is, ongeacht hoeveel er al vooruit staat.
  for (var i = 0; i < standen.length; i++) {
    if (standen[i] != Haalstand.geland) continue;
    inRij.add(i);
    vooruit++;
  }
  // En daarna eigen muziek, maar alleen zoveel als er nodig is om het gat te dichten.
  for (var i = 0; i < standen.length && vooruit < minVooruit; i++) {
    if (standen[i] != Haalstand.klaar) continue;
    inRij.add(i);
    vooruit++;
  }

  final onderweg = standen.where((s) => s == Haalstand.onderweg).length;
  final ruimte = maxOnderweg - onderweg;
  final starten = <int>[];
  if (ruimte > 0) {
    for (var i = 0; i < standen.length && starten.length < ruimte; i++) {
      if (standen[i] == Haalstand.wacht) starten.add(i);
    }
  }

  return (starten: starten, inRij: inRij, vooruit: vooruit);
}

/// Hoe lang een radiohaal hoogstens op één peer wacht.
///
/// **Waarom dit veel korter is dan elders in de app.** Een wens uit de verlanglijst mag een half uur
/// in de rij van een uploader blijven staan: er zit niemand op te wachten en de plek in die rij is
/// waardevol. Bij een radio is dat omgekeerd — je luistert NU, en een haal die er twintig minuten
/// over doet levert een nummer op waar de radio al lang voorbij is. Erger nog: hij houdt al die tijd
/// een van de twaalf Soulseek-plekken bezet, dus hij vertraagt ook alles daarachter.
///
/// Anderhalve minuut is ruim voor een peer die bedient en kort genoeg om er acht per kwartier te
/// kunnen proberen.
const Duration kMaxWacht = Duration(seconds: 90);
