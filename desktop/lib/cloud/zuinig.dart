/// Hoe vaak de app de accountdatabase mag aanspreken.
///
/// **Waarvoor dit bestaat.** Op 31-08-2026 kwam er op het inlogscherm "Quota exceeded" te staan: de
/// gratis daglimiet van Firestore was op. Niet door iets bijzonders, maar door de klok:
///
/// * de pc schreef zijn eigen serverregel **elke 30 seconden** volledig opnieuw weg. Onvoorwaardelijk,
///   want er stond `lastSeenAt: nu` in en die verschilt altijd — dus ook een pc die de hele dag niets
///   doet schreef 2880 keer. De gratis grens ligt op 20 000 schrijfbeurten per dag;
///   en hij vroeg er telkens de koppelverzoeken bij op: nog eens 2880 leesbeurten;
/// * de wachtrijwerker vroeg **elke 20 seconden** de hele wachtrij op, ook als er dagenlang niets in
///   stond: 4320 leesbeurten per dag, per pc.
///
/// Bij elkaar is dat een flink deel van de daglimiet voor een app die stilstaat, en dat is precies
/// de fout die deze app al eens eerder maakte — twee klokken die te snel liepen, gerepareerd op
/// 28-08-2026. Deze twee waren over het hoofd gezien omdat ze niets kósten op de pc zelf.
///
/// **Zuiver**, en daarom hier en niet in de klokken zelf: het gaat om twee beslissingen die je
/// zonder netwerk en zonder database kunt nameten.
library;

/// Moet de serverregel nu echt geschreven worden?
///
/// Twee redenen om te schrijven, en verder geen:
///
/// 1. er is werkelijk iets veranderd — een ander adres, een andere poort, een ander aantal nummers.
///    Dat moet meteen naar buiten, want een toestel dat het oude adres leest komt er niet in;
/// 2. het is lang genoeg geleden dat de vorige regel geschreven is. Dat is de hartslag: andere
///    toestellen lezen `lastSeenAt` om te zien of deze pc nog aan staat.
///
/// [ritme] hoort ruim ONDER het venster te liggen waarin een pc als "online" telt — anders valt hij
/// tussen twee slagen door even offline. Zie [kHartslagRitme].
bool moetServerSchrijven({
  required bool veranderd,
  required Duration sindsLaatsteSchrijf,
  Duration ritme = kHartslagRitme,
}) =>
    veranderd || sindsLaatsteSchrijf >= ritme;

/// Hoe vaak de pc zijn aanwezigheid bevestigt als er verder niets verandert.
///
/// **Zestig seconden, en dat getal volgt uit een som.** De klok tikt elke 30 seconden en een pc
/// telt als online zolang hij binnen 2 minuten iets van zich liet horen. Eén mislukte slag mag geen
/// pc offline laten lijken, dus: ritme + één tik moet ONDER dat venster blijven. Bij 60 s is dat
/// 90 tegen 120 — een halve minuut speling.
///
/// Hier stond eerst 90 seconden, wat op 90 + 30 = precies 120 uitkwam: geen speling, en dus een pc
/// die na één gemiste slag op het koppelscherm zou gaan flikkeren. De toets ving dat, en het is de
/// reden dat dit getal niet naar boven mag zonder het venster mee te verruimen.
///
/// De helft van de 2880 schrijfbeurten per dag die de oude dertig seconden kostten. Nog zuiniger
/// kan alleen door dat venster op te rekken, en dan gaat "staat mijn pc aan?" er trager uitzien —
/// dat is de verkeerde ruil voor een app waar dat juist de vraag is.
const Duration kHartslagRitme = Duration(seconds: 60);

/// Hoe vaak de klok tikt. De hartslag kan alleen op een tik geschreven worden, dus dit hoort in de
/// som hierboven thuis.
const Duration kHartslagTik = Duration(seconds: 30);

/// Het venster waarbinnen een pc als online telt. Zie `CloudServer.isFresh`.
const Duration kOnlineVenster = Duration(minutes: 2);

/// Alles wat NIET meetelt bij "is er iets veranderd".
///
/// De tijdstempel is precies het veld dat altijd verschilt; hem meenemen zou de hele vergelijking
/// zinloos maken.
const Set<String> kTijdVelden = {'lastSeenAt', 'updatedAt', 'grantedAt'};

/// Verschillen deze twee regels ergens anders in dan in hun tijdstempel?
///
/// Een ontbrekende oude regel telt als veranderd: dan staat er nog niets, en dat moet er komen.
bool serverRegelVeranderd(Map<String, dynamic>? oud, Map<String, dynamic> nieuw) {
  if (oud == null) return true;
  for (final sleutel in {...oud.keys, ...nieuw.keys}) {
    if (kTijdVelden.contains(sleutel)) continue;
    if (!_gelijk(oud[sleutel], nieuw[sleutel])) return true;
  }
  return false;
}

/// Waardegelijkheid, ook voor de lijst met adressen — `==` op twee lijsten vergelijkt identiteit en
/// zou dus élke keer "veranderd" zeggen.
bool _gelijk(dynamic a, dynamic b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_gelijk(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Hoe vaak de wachtrij nagekeken wordt.
///
/// Snel zolang er iets gebeurt, traag als het al een tijd stil is. Een wachtrij die dagenlang leeg
/// is hoeft niet elke twintig seconden opgevraagd te worden; een wachtrij waar zojuist iets in is
/// gezet wél, want daar staat iemand op te wachten.
///
/// De prijs staat hier eerlijk bij: is het langer dan [kStilteVoorTraag] stil geweest, dan kan het
/// tot [kTraagRitme] duren voor een nieuwe opdracht wordt opgepikt. Eén minuut op een download die
/// toch minuten duurt, tegenover twee derde minder leesbeurten.
Duration wachtrijRitme(Duration sindsLaatsteWerk) =>
    sindsLaatsteWerk >= kStilteVoorTraag ? kTraagRitme : kSnelRitme;

const Duration kSnelRitme = Duration(seconds: 20);
const Duration kTraagRitme = Duration(seconds: 60);
const Duration kStilteVoorTraag = Duration(minutes: 5);
