/// Wanneer de radio zijn voorraad aanvult, en wat hij herhaalt als er niets nieuws is — de rekensom,
/// zonder IO.
///
/// **Waarom dit bestaat.** Saber op 08-10-2026, radio vanaf "Niels Destadsbader — Vuur en vlam":
/// *"13 liedjes is weinig e !! het moet tot maximum kunnen zoveel mogelijk! als hij er dan geen meer
/// vindt dan mag hij ook niet stoppen."* De radio vroeg elke bron één keer, bij de start — Deezer, het
/// taalmodel — en vulde daarna nooit meer aan: `radioExtend` stond uit (`radio.dart`), en `_pas`
/// schoof alleen bestaande plekken door. Was het plan op, dan was de radio op, zonder iets te zeggen.
///
/// Hier staat het besluit (wanneer, en hoe dringend) en de keuze van herhalingen. Wat een bron
/// werkelijk vraagt staat in `radiobijvuller.dart`; dit stuk moet kloppen, want een fout hier is stilte.
library;

import 'dart:math' as math;

import 'radiokeuze.dart' show artiestSleutel, kArtiestAfstand, kMaxPerArtiest;

/// Onder hoeveel verwachte nummers vooruit er bijgevuld wordt.
///
/// Een ronde (Deezer, de keuring met 1,1 s per Discogs-vraag, en dan het halen van 30–90 s per
/// nummer) moet klaar zijn voordat de rij leeg is. Vijftien nummers is een uur muziek.
const double kBijvulOnder = 15;

/// Hoe lang er minstens tussen twee rondes zit, behalve bij nood.
const Duration kBijvulAdem = Duration(seconds: 90);

/// Onder hoeveel seconden muziek het nood is — als er dan niets geland of klaar is.
const int kNoodRest = 240;

/// Na hoeveel seconden een droge rij nood is, ook als er nog van alles onderweg is.
///
/// Acht haaltjes onderweg bij een opbrengst van 0,2 zijn samen 1,6 verwachte nummers: geen nood volgens
/// de som, en toch was het dan één tot twee minuten stil tot er iets landde (beoordeling van
/// 08-10-2026). De droogte wordt gezien bij de eerste tik (hoogstens vijf seconden na het stilvallen) en
/// is vijf seconden later nood: samen uiterlijk tien seconden stil.
const int kDroogTotNood = 5;

/// Hoe lang er bij nood minstens tussen twee bijvulrondes zit. De noodvulling zelf (reserve of herhalen)
/// wacht hier niet op; dit is alleen om niet elke tik van vijf seconden Deezer en het logboek te vullen
/// als er niets meer te vinden is.
const Duration kNoodAdem = Duration(seconds: 30);

/// Na hoe lang een buurt die op was opnieuw bekeken wordt: wat toen aangeboden maar niet genomen werd
/// (het plafond per artiest was vol), mag dan alsnog.
const Duration kTrapHerstel = Duration(minutes: 30);

/// Hoeveel eigen nummers er hoogstens als reserve klaarstaan.
const int kReserve = 6;

/// Hoe lang er zonder enige landing gewacht wordt voor de reserve toch begint.
const Duration kReserveZonderLanding = Duration(seconds: 60);

/// Hoeveel nummers er minstens tussen een nummer en zijn herhaling zitten, per niveau — zie
/// [kiesHerhaling].
const List<int> kHerhaalAfstanden = [25, 10, 3];

/// Hoeveel van de opbrengst over de laatste beslissingen gerekend wordt.
const int kOpbrengstVenster = 30;

/// Welk deel van de wachtende plekken straks werkelijk klinkt, over de laatste [kOpbrengstVenster]
/// beslissingen ([uitkomsten], oud naar nieuw: true = geland, false = mislukt of geweerd).
///
/// Met een zachte begin-aanname ((geland+1)/(beslist+4)) en een ondergrens van 2 %. **Niet 15 %**: op
/// 08-10-2026 keurde de Vlaamse radio 15 van de ruim vijftig voorstellen goed, en een radio waarvan
/// maar één op de twintig wachtende plekken landt, zou met een ondergrens van 15 % honderd wachtende
/// plekken voor vijftien nummers aanzien — en nooit bijvullen terwijl hij leegloopt.
double recenteOpbrengst(List<bool> uitkomsten, {int venster = kOpbrengstVenster}) {
  final recent = uitkomsten.length > venster ? uitkomsten.sublist(uitkomsten.length - venster) : uitkomsten;
  final geland = recent.where((u) => u).length;
  return math.max(0.02, (geland + 1) / (recent.length + 4));
}

/// Hoeveel nummers er naar verwachting nog vóór je staan.
///
/// Wat in de rij staat telt helemaal, wat geland is ook. Eigen muziek die klaarstaat ([klaarArtiesten],
/// zonder de reserve) telt per artiest hoogstens [kMaxPerArtiest] en voor de zaadartiest één keer: dertig
/// eigen nummers van de zaadartiest zijn geen dertig nummers vooruit, want de afstandsregel laat er maar
/// één op de tien door. Wat onderweg is of nog wacht telt naar de [opbrengst].
double verwachtVooruit({
  required int rijVooruit,
  required int geland,
  required List<String> klaarArtiesten,
  String? zaad,
  required int onderweg,
  required int wacht,
  required double opbrengst,
}) {
  final zaadSleutel = zaad == null ? '' : artiestSleutel(zaad);
  final perArtiest = <String, int>{};
  var klaar = 0;
  for (final a in klaarArtiesten) {
    final k = artiestSleutel(a);
    final max = k.isNotEmpty && k == zaadSleutel ? 1 : kMaxPerArtiest;
    final n = perArtiest[k] ?? 0;
    if (n >= max) continue;
    perArtiest[k] = n + 1;
    klaar++;
  }
  return rijVooruit + geland + klaar + (onderweg + wacht) * opbrengst;
}

/// Moet er nu bijgevuld worden, en is het nood?
typedef Bijvulbesluit = ({bool nu, bool nood, String waarom});

/// Het besluit, per tik van de radio.
///
/// **De poort:** de radio loopt en speelt — óf hij staat droog, óf je drukte op "volgende" bij het
/// laatste nummer ([wilVerder]). Eerst stond hier "alleen als er gespeeld wordt", en dat was precies
/// verkeerd: een droge rij speelt niet, dus werd er niet bijgevuld, dus landde er niets (beoordeling
/// van 08-10-2026). Een pauze midden in een nummer houdt de poort wél dicht: dan hoeft er niets.
///
/// **Nood:** er klinkt nog minder dan [kNoodRest] (of niets), er is niets geland of klaar, en wat er
/// onderweg is levert naar verwachting geen nummer op (`onderweg × opbrengst < 1`) — óf de rij staat
/// al [kDroogTotNood] seconden droog ([droogSeconden]). Acht kansloze haaltjes onderweg houden de nood
/// dus niet tegen, en acht kansrijke ook niet langer dan een paar tellen.
Bijvulbesluit bijvulBesluit({
  required bool loopt,
  required bool speelt,
  required bool droog,
  required bool wilVerder,
  required double verwacht,
  required int? restSeconden,
  required int gelandOfKlaar,
  required int onderweg,
  required double opbrengst,
  required bool bezig,
  int droogSeconden = 0,
  DateTime? vorige,
  required DateTime nu,
}) {
  if (!loopt || !(speelt || droog || wilVerder)) {
    return (nu: false, nood: false, waarom: 'de radio staat stil');
  }
  final rest = droog || wilVerder ? 0 : restSeconden;
  final krap = droog || wilVerder || (rest != null && rest < kNoodRest);
  final nood = krap && gelandOfKlaar == 0 && (onderweg * opbrengst < 1 || (droog && droogSeconden >= kDroogTotNood));
  if (bezig) return (nu: false, nood: nood, waarom: 'er loopt al een ronde');
  if (!nood && verwacht >= kBijvulOnder) return (nu: false, nood: false, waarom: 'genoeg vooruit');
  if (vorige != null && nu.difference(vorige) < (nood ? kNoodAdem : kBijvulAdem)) {
    return (nu: false, nood: nood, waarom: 'net een ronde gehad');
  }
  return (nu: true, nood: nood, waarom: nood ? 'nood' : 'minder dan ${kBijvulOnder.toInt()} vooruit');
}

/// Eén nummer dat herhaald zou kunnen worden.
///
/// [laatstVoorbij] is de stand van de voorbij-teller toen het voor het laatst voorbij kwam (null: nog
/// nooit), [gehoord] of je het werkelijk beluisterde (en niet oversloeg), [groen] een duim omhoog,
/// [eigen] jouw eigen bestand, [opSchijf] een download van deze radio die er nog staat, [zaadOfAnker]
/// een eigen nummer van de zaadartiest of een groen anker (het laatste vangnet, zonder stijlfilter),
/// [rood] een duim omlaag — die komt nooit terug.
typedef Herhaalkandidaat = ({
  String artiest,
  int? laatstVoorbij,
  bool gehoord,
  bool groen,
  bool eigen,
  bool opSchijf,
  bool zaadOfAnker,
  bool rood,
});

/// Wat de radio herhaalt als er niets nieuws is: [hoeveel] indexen in [k], en op welk niveau.
///
/// Stap voor stap dichterbij, want "nooit stoppen" mag niet afhangen van hoeveel groen je gaf — Saber
/// gaf er in totaal negentien (state.json, 08-10-2026). Herhaald wordt wat deze radio speelde en je
/// werkelijk HOORDE (of groen gaf): wat je oversloeg komt niet terug — op 08-10 sloeg Saber er tien
/// over in een kwartier, en dat zijn precies de nummers die hij niet nog eens wil.
/// 1. minstens [kHerhaalAfstanden][0] (25) nummers geleden;
/// 2. minstens 10;
/// 3. wat je één keer oversloeg, als het er nog staat en minstens tien nummers geleden is;
/// 4. het vangnet: een eigen nummer van de zaadartiest of een groen anker dat nog niet speelde (dan is
///    het geen herhaling maar een eigen nummer — zie `voegHerhalingBij`), of dat je hoorde, minstens 3
///    geleden — hoogstens één per keer, en staat die artiest al in [vol] (hij klonk net), dan pas na 5;
/// 5. pas als laatste: wat je hoorde, minstens 3 geleden.
///
/// Waarom deze volgorde (tweede en derde beoordeling van 08-10-2026): een herhaling die je oversloeg
/// komt niet nog eens, dus de voorraad van wat je hoorde krimpt bij elke ronde. Stond "gehoord, 3
/// geleden" vóór "overgeslagen, 10 geleden", dan draaide een uitgeputte radio een kringetje van drie
/// nummers; en stond het vangnet vóór "overgeslagen", dan bestond dat niveau in die fase alleen uit de
/// zaadartiest, en kwam hij 40 tot 70 % van de tijd terug in plaats van één op de tien.
///
/// Eigen nummers en downloads die er nog staan op hetzelfde niveau: eerst stond eigen met drie
/// tussenstappen vóór een download van vijfentwintig geleden, en dan draaiden zes eigen nummers in een
/// kring van zeven (beoordeling van 08-10-2026). Binnen een niveau groen eerst en dan het langst niet
/// gehoorde; en niet de artiesten van [recenteArtiesten] (de laatste in de rij) of [vol] (al aan hun
/// plafond, zie `artiestenVoorPlafond`) zolang er iets anders is. Nooit [Herhaalkandidaat.rood].
({List<int> keuze, int niveau}) kiesHerhaling(
  List<Herhaalkandidaat> k, {
  required int teller,
  List<String> recenteArtiesten = const [],
  Set<String> vol = const {},
  int hoeveel = 2,
}) {
  int afstand(Herhaalkandidaat c) => c.laatstVoorbij == null ? 1 << 30 : teller - c.laatstVoorbij!;
  bool herhaalbaar(Herhaalkandidaat c) =>
      (c.gehoord || c.groen) && (c.eigen || c.groen || c.opSchijf) && c.laatstVoorbij != null;
  bool niveau(Herhaalkandidaat c, int n) {
    if (c.rood) return false;
    return switch (n) {
      1 || 2 => herhaalbaar(c) && afstand(c) >= kHerhaalAfstanden[n - 1],
      3 => (c.eigen || c.groen || c.opSchijf) && c.laatstVoorbij != null && afstand(c) >= kHerhaalAfstanden[1],
      4 => c.zaadOfAnker &&
          (c.laatstVoorbij == null || ((c.gehoord || c.groen) && afstand(c) >= kHerhaalAfstanden[2])),
      _ => herhaalbaar(c) && afstand(c) >= kHerhaalAfstanden[2],
    };
  }

  final recent = {
    for (final a in recenteArtiesten.skip(math.max(0, recenteArtiesten.length - (kArtiestAfstand - 1))))
      artiestSleutel(a)
  };
  List<int> poolVan(int n) => [for (var i = 0; i < k.length; i++) if (niveau(k[i], n)) i]
    ..sort((a, b) {
      final g = (k[b].groen ? 1 : 0).compareTo(k[a].groen ? 1 : 0);
      return g != 0 ? g : afstand(k[b]).compareTo(afstand(k[a]));
    });

  ({List<int> keuze, int niveau}) kies(List<int> pool, int n) {
    final keuze = <int>[];
    final gekozen = <String>{};
    final max = n == 4 ? 1 : hoeveel;
    // Eerst artiesten die niet net klonken, niet aan hun plafond zitten en nog niet gekozen zijn; dan
    // wat er over is — liever een herhaling te dicht bij zijn artiest dan stilte.
    for (final ronde in [0, 1]) {
      for (final i in pool) {
        if (keuze.length >= max) break;
        if (keuze.contains(i)) continue;
        final a = artiestSleutel(k[i].artiest);
        if (ronde == 0 && (recent.contains(a) || vol.contains(a) || gekozen.contains(a))) continue;
        keuze.add(i);
        gekozen.add(a);
      }
    }
    return (keuze: keuze, niveau: n);
  }

  var vangnetUitgesteld = false;
  for (var n = 1; n <= 5; n++) {
    final pool = poolVan(n);
    if (pool.isEmpty) continue;
    // Het vangnet bestaat uit één artiest: klonk die net, dan eerst kijken of er nog iets anders is.
    if (n == 4 && pool.every((i) => vol.contains(artiestSleutel(k[i].artiest)))) {
      vangnetUitgesteld = true;
      continue;
    }
    return kies(pool, n);
  }
  if (vangnetUitgesteld) return kies(poolVan(4), 4);
  return (keuze: const <int>[], niveau: 0);
}
