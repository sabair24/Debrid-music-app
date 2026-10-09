/// Een radio die begint met wat je hebt en de rest ophaalt terwijl je luistert.
///
/// **Wat de radio hiervóór was, en dat is iets anders dan het leek.** Een radio werd gezaaid met één
/// artiestnaam; nummers die je niet had werden niet gehaald maar als torrent gezocht en via TorBox
/// GESTREAMD — een tijdelijke link, geen bestand, geen hoes, niet meegeteld in je luistercijfers. En
/// op een gekoppeld toestel gebeurde zelfs dat niet, want `RemoteOnlineService.resolveRadio` gaf
/// onvoorwaardelijk null: op de telefoon wás de radio al niets anders dan "alleen wat ik zelf heb".
///
/// Hier worden ze opgehaald, via Soulseek, als echt bestand in je bibliotheek. En dan geldt de regel
/// waar alles aan hangt:
///
/// > Een nummer komt pas in de speelrij als het bestand er werkelijk staat.
///
/// Wat nog onderweg is zit in het PLAN, niet in de rij. De rekensom die beslist wat er wanneer bij mag
/// staat apart in `radiovoorraad.dart`, zonder IO, zodat juist dat stuk te toetsen valt: een fout daar
/// is stilte tussen twee nummers, en dat is precies wat er niet mag gebeuren.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'library.dart';
import 'models.dart';
import 'online.dart';
import 'paths.dart';
import 'settings.dart';
import 'player.dart';
import 'radiokeuze.dart' show artiestSleutel, basisTitel, kArtiestAfstand, kMaxPerArtiest;
import 'radioladder.dart';
import 'radiosessie.dart';
import 'radiovoorraad.dart';

/// Eén plek in het radioplan: wat er zou moeten spelen, en hoe ver het daarmee is.
class Radioplek {
  Radioplek({
    required this.artiest,
    required this.titel,
    this.seconden,
    this.jaar,
    this.eigen,
    this.zaad = false,
    this.bron = 'start',
    this.deezerArtiest = 0,
    this.reserve = false,
    this.herhaling = false,
  }) : teHalen = eigen == null {
    // Wat je al hebt is meteen klaar: het bestand staat er, er valt niets aan te halen. Dat is de
    // enige plek waar het onderscheid tussen "eigen muziek" en "moet nog komen" gemaakt wordt.
    if (eigen != null) stand = Haalstand.klaar;
  }

  /// Moest deze plek gehaald worden (geen eigen nummer bij het maken)? Voor de opbrengst: alleen
  /// zulke plekken tellen mee in "hoeveel van wat wacht, klinkt straks".
  final bool teHalen;

  /// Waar de plek vandaan kwam — "start", "buren", "reserve", "herhaling" — voor het logboek.
  final String bron;

  /// Deezers id voor de artiest, als de bron hem gaf (0: onbekend).
  final int deezerArtiest;

  /// Eigen muziek die de bijvuller als vangnet klaarzette: speelt alleen mee als het krap wordt — zie
  /// [kReserveVooruit] — en staat altijd achteraan het plan.
  final bool reserve;

  /// Een nummer dat deze radio al speelde en nu herhaalt — zie [RadioBesturing.voegHerhalingBij].
  final bool herhaling;

  /// Waarom de plek [Haalstand.mislukt] werd, als dat zo is.
  Weerreden? weer;

  /// Het jaar waarom het tijdvak deze plek weerde — voor een ruimer venster later.
  int? buitenJaar;

  /// Wanneer de plek niet te vinden bleek, en of hij al een herkansing kreeg.
  DateTime? mislukteOp;
  bool herkansd = false;

  /// De stand van de voorbij-teller toen deze plek voorbij kwam (gespeeld of overgeslagen), of null.
  /// Zie [RadioBesturing._stempel].
  int? voorbijOp;

  /// Werkelijk beluisterd (de luistertelling van de app), niet alleen voorbij gekomen. Alleen wat je
  /// hoorde wordt herhaald — wat je oversloeg niet (beoordeling van 08-10-2026).
  bool gehoord = false;

  final String artiest;
  final String titel;

  /// Het nummer waar de radio vanaf begon. Afstemmen ([stemPlanAf]) laat het staan, ook als het nog
  /// wacht: het nieuwe plan weert het zaadnummer met opzet, dus zonder dit verdween het voorgoed
  /// (tweede beoordeling van 26-09-2026 — een pauze zette de plek terug op wachten, en een tik op
  /// "Ontdekken" gooide hem weg).
  final bool zaad;

  /// Hoe vaak de keuring deze plek al liet wachten omdat er nog geen antwoord was — zie
  /// [RadioKeuringLater]. De keuring houdt het bij en geeft na een paar keer toch een oordeel.
  int keurUitstel = 0;

  /// Hoe lang het volgens de catalogus duurt, en uit welk jaar het is.
  ///
  /// Allebei gaan ze mee als GEZAG naar de download, en allebei doen ze er om een eigen reden toe —
  /// zie [DownloadManager.haalVoorRadio]: het jaar is wat de tags gezaghebbend maakt (zonder dat
  /// schrijft `stampTags` niets), de looptijd is de Sting-val.
  final int? seconden;
  int? jaar;

  /// Het bestand. Vanaf het begin gevuld als je het al had, anders zodra het geland is.
  Track? eigen;

  /// Door DEZE radio opgehaald.
  ///
  /// Het verschil tussen "stond er al" en "is er net bijgekomen", en straks het enige onderscheid dat
  /// het opruimen mag maken. Alleen wat hier op true staat mag ooit weer weg.
  bool doorRadio = false;

  Haalstand stand = Haalstand.wacht;
}

/// Waar een radio zijn nummers vandaan haalt.
///
/// Twee uitvoeringen, en het verschil is één ding: doet deze machine het zelf, of laat hij het aan de
/// pc over? Al het andere — hoeveel er vooruit moet staan, wanneer er iets bij mag, wat er gebeurt als
/// een haal mislukt — staat in [RadioBesturing] en is aan beide kanten hetzelfde.
abstract class Radiobron {
  /// Klaarmaken om te halen. Null als het kan; anders de reden waarom niet, in gewone taal.
  ///
  /// De radio WEIGERT dan te starten in plaats van stilletjes alleen eigen muziek te spelen. Dat is
  /// met zoveel woorden gevraagd, en het is ook het enige eerlijke: een radio die zegt dat hij
  /// ophaalt en dat niet doet, is een radio die liegt.
  ///
  /// Hier hoort ook het NEMEN van wat open moet blijven: de ene Soulseek-aanmelding waar de hele
  /// radio op draait. Vier aanmeldingen per tien minuten en een sessie die na 120 seconden stilte
  /// dichtgaat — zonder die ene leen valt elk haaltje op een verse aanmelding en is het account na
  /// een half uur geblokkeerd.
  Future<String?> begin();

  /// Loslaten wat [begin] genomen heeft. Mag vaker dan één keer.
  void einde();

  /// Alles wat nu opgehaald wordt onmiddellijk afbreken. Mag vaker dan één keer.
  ///
  /// **Los van [einde], want het gebeurt ook zonder dat.** Start je een nieuwe radio, dan houdt de
  /// vorige op maar blijft de Soulseek-aanmelding staan — die is net opnieuw genomen voor de radio
  /// die begint. De haaltjes van de vorige radio horen dan wél weg.
  ///
  /// Zonder dit liepen ze door: acht haaltjes die minuten na het afsluiten alsnog op je schijf
  /// landen, van een radio die niet meer bestaat en die ze dus ook nooit meer opruimt of in een rij
  /// zet. "Vanaf de radio stopt moeten de downloads ook stoppen, want nu zinderen er nog een paar
  /// achter."
  void staak();

  /// Eén nummer halen. Geeft het nummer terug zoals het in de bibliotheek staat, of null.
  ///
  /// Gooit [RadioLaterOpnieuw] als het nu niet kan maar straks wel, en [AlVanJou] als het nummer er
  /// is maar van jou — dan klinkt het, maar wordt het nooit door de radio opgeruimd.
  Future<Track?> haal(Radioplek plek);

  /// Dit nummer weg: van de schijf, uit de bibliotheek, en van de verlanglijst.
  ///
  /// **Ook van de verlanglijst**, en dat is geen bijzaak. Landde de haal als mp3, dan staat het nummer
  /// op de lijst voor een betere versie; zonder deze regel haalt `sweepLosslessWants` twintig minuten
  /// later alsnog de FLAC — van een nummer dat je zojuist hebt weggegooid.
  ///
  /// Geeft terug of het bestand werkelijk van zijn plek is. Kon het niet naar de prullenbak (een
  /// netwerkschijf, een bestand dat openstaat), dan staat het er nog — en dan mag de radio het niet
  /// vergeten (review van 26-09-2026).
  Future<bool> vergeet({required String pad, required String artiest, required String titel});
}

/// Deze machine haalt zelf: de pc, of een losse installatie zonder koppeling.
/// Wat [Radiobron.haal] gooit als het nummer er nu is, maar niet van de radio: het landde op muziek
/// die je al had (zie [RadioAlGehad]). Het klinkt gewoon, maar telt niet als "door de radio gehaald"
/// — geen duim die het weggooit, geen plek in het opruimoverzicht.
class AlVanJou implements Exception {
  const AlVanJou(this.nummer);
  final Track nummer;
  @override
  String toString() => 'al van jou: ${nummer.path}';
}

class EigenRadiobron implements Radiobron {
  EigenRadiobron({
    required this.downloads,
    required this.soulseek,
    required this.library,
    required this.instellingen,
  });

  final DownloadManager downloads;
  final SoulseekService soulseek;
  final LibraryStore library;

  /// Nodig om een HOES op te halen voor wat er net geland is.
  ///
  /// Zonder dit blijft een opgehaald nummer met een grijs notenbalkje staan tot de volgende
  /// volledige scan: het verrijken van hoezen hangt aan `scan()`, en de radio scant met opzet niet.
  final AppSettings instellingen;

  void Function()? _los;

  @override
  Future<String?> begin() async {
    if (!soulseek.available) {
      return 'Vul eerst je Soulseek-login in bij Instellingen. Zonder die kan de radio niets ophalen '
          'wat je nog niet hebt.';
    }
    final waarom = soulseek.whyNotLogin;
    if (waarom != null) return 'Soulseek doet even niet mee: $waarom';
    _los ??= soulseek.leaseVoorRadio();
    return null;
  }

  @override
  void einde() {
    final los = _los;
    _los = null;
    los?.call();
  }

  @override
  void staak() => downloads.staakRadiohalen();

  @override
  Future<Track?> haal(Radioplek plek) async {
    final String? pad;
    try {
      pad = await downloads.haalVoorRadio(
        artiest: plek.artiest,
        titel: plek.titel,
        seconden: plek.seconden,
        jaar: plek.jaar,
      );
    } on RadioAlGehad catch (e) {
      // Geland op muziek die je al had: laten klinken, maar als JOUW nummer — zie [AlVanJou].
      final t = await library.voegBestandToe(e.pad);
      if (t == null) return null;
      throw AlVanJou(t);
    }
    if (pad == null) return null;
    // Eén bestand erbij, en niet de hele muziekmap opnieuw lezen. Zie [LibraryStore.voegBestandToe]:
    // bij acht landingen per kwartier zou een volledige scan vrijwel permanent draaien, en dat merk
    // je precies terwijl je naar muziek luistert.
    final t = await library.voegBestandToe(pad);
    // En dan alsnog een hoes erbij. Dit hing aan `scan()`, en die draait hier juist niet — dus stond
    // elk opgehaald nummer met een grijs notenbalkje in de rij. De sweep is van zichzelf al begrensd
    // (één tegelijk, en een album dat al vergeefs gezocht is wordt overgeslagen), dus hem na elke
    // landing aantikken kost niets als er niets te doen is.
    if (t != null) unawaited(library.enrichFromWeb(instellingen).catchError((_) {}));
    return t;
  }

  @override
  Future<bool> vergeet(
      {required String pad, required String artiest, required String titel}) async {
    // Naar de prullenbak, niet definitief: een duim is één tik, en een misgetikte tik hoort terug te
    // draaien te zijn. Zie `prullenbak.dart` voor de dertien nummers van 26-09-2026.
    final weg = await library.removeTracks([pad], fromDisk: true, naarPrullenbak: true) > 0 ||
        !File(pad).existsSync();
    if (weg) await downloads.vergeetWens(artiest, titel);
    return weg;
  }
}

/// De radio die vooruit meeloopt.
///
/// Houdt drie dingen bij elkaar: het PLAN (wat er zou moeten spelen), de SPEELRIJ (wat er werkelijk
/// kan klinken) en de haaltjes die onderweg zijn. Eén klok van vijf seconden plus een aanroep na elke
/// landing zijn genoeg om die drie gelijk te houden.
/// Welke nakomers er werkelijk bij het plan mogen.
///
/// Los van [RadioBesturing.voegBij] zodat het zonder speler en zonder Soulseek te beproeven is —
/// en dit is precies de plek waar het stil fout kan gaan: een dubbel nummer in de rij is niet iets
/// wat een foutmelding oplevert, je hoort het gewoon twee keer.
List<Radioplek> nieuweNakomers(List<Radioplek> plan, List<Radioplek> extra) {
  // Op het LIEDJE en niet op de letterlijke titel: "X" en "X (Radio Edit)" uit twee ladingen zijn
  // hetzelfde nummer, en dat speelde zo twee keer (review van 26-09-2026).
  String sleutel(Radioplek p) => '${artiestSleutel(p.artiest)}|${basisTitel(p.titel)}';
  final bekend = <String>{for (final p in plan) sleutel(p)};
  return [
    for (final p in extra)
      if (p.artiest.trim().isNotEmpty && p.titel.trim().isNotEmpty && bekend.add(sleutel(p))) p
  ];
}

/// De artiesten die meetellen voor het plafond per artiest (zie `spreidArtiesten`).
///
/// **Wat er nog komt, plus de laatste [venster] die voorbij kwamen.** Eerst ging hier het hele plan
/// in, ook wat geweerd of niet te vinden was: drie afgekeurde Clouseau-nummers en Clouseau kwam er
/// nooit meer in (beoordeling van 08-10-2026). En zonder venster vraagt een radio van driehonderd
/// nummers met hoogstens drie per artiest honderd artiesten — zoveel heeft Vlaamse pop er niet.
///
/// "Wat nog komt" is: wachten, onderweg, klaar (zonder de reserve), geland, en in de rij maar nog
/// niet voorbij. Een nummer dat je oversloeg telt alleen binnen het venster mee.
List<String> artiestenVoorPlafond(List<Radioplek> plan, {required int voorbijteller, int venster = 40}) => [
      for (final p in plan)
        if (p.stand != Haalstand.mislukt &&
            !(p.stand == Haalstand.klaar && p.reserve) &&
            (p.voorbijOp == null || voorbijteller - p.voorbijOp! < venster))
          p.artiest
    ];

/// Artiesten die deze radio al minstens drie keer weerde om tijdvak of stijl: niet steeds opnieuw
/// laten keuren. Een besparing op de keuring (de rij van Discogs is 1,1 s per vraag), geen
/// smaakregel.
Set<String> steedsGeweigerd(List<Radioplek> plan) {
  final tel = <String, int>{};
  for (final p in plan) {
    if (p.stand == Haalstand.mislukt && (p.weer == Weerreden.tijdvak || p.weer == Weerreden.stijl)) {
      final k = artiestSleutel(p.artiest);
      tel[k] = (tel[k] ?? 0) + 1;
    }
  }
  return {for (final e in tel.entries) if (e.value >= 3) e.key};
}

/// Wat er bij een radio onder de titel staat — of null: niets bijzonders, toon de artiest.
///
/// **Zolang de radio loopt nooit "Radio klaar".** Dat zei de speler zodra zijn rij op was, en dan
/// stond het er terwijl er nog acht nummers onderweg waren (08-10-2026, "0 hierna" en "Radio klaar"
/// na dertien nummers). Een lege rij is wachten, geen einde.
///
/// [spelerStatus] is wat de speler zelf meldt (`PlayerStore.radioStatus`), [stand] wat het
/// bijvullen zegt ([RadioBesturing.bijvulStand]). [aantal] is het genoemde aantal van een radio uit
/// een zin, als dat bereikt is ([aantalBereikt]).
String? radioStatusTekst({
  required String spelerStatus,
  required bool droog,
  required bool wilVerder,
  required bool loopt,
  String? stand,
  bool aantalBereikt = false,
  int? aantal,
}) {
  final wacht = droog || wilVerder;
  if (wacht && aantalBereikt && aantal != null) return 'Je vroeg $aantal nummers — de radio stopt hier';
  if (wacht && loopt) return stand ?? 'Zoekt het volgende nummer…';
  if (loopt && spelerStatus == 'Radio klaar') return stand;
  if (spelerStatus.isNotEmpty) return spelerStatus;
  return null;
}

/// De kop van het radiopaneel: hoeveel er nog komt, en of hij nog zoekt.
///
/// "0 hierna" alleen klonk als het einde, ook als er acht onderweg waren. [zoekt] is onwaar als hij
/// niet zoekt: het genoemde aantal is er, of het ophalen staat even stil — dan geen "zoekt verder".
String radioKop({required int hierna, required int onderweg, required bool loopt, bool zoekt = true}) {
  final h = hierna < 0 ? 0 : hierna;
  if (!loopt) return '$h hierna';
  if (onderweg > 0) return '$h hierna · $onderweg onderweg';
  return h == 0 && zoekt ? '0 hierna · zoekt verder' : '$h hierna';
}

/// Waar de nakomers in het plan terechtkomen.
///
/// **Waarom niet gewoon achteraan.** Gemeten op 12-09-2026: het model leverde 41 nummers uit twaalf
/// van de twaalf gekozen namen — Toto, Rockwell, Shalamar, The S.O.S. Band, Cheryl Lynn, Paul
/// McCartney, Jam & Lewis. Achter de veertig die Deezer al had aangedragen betekent dat: pas na
/// ruim twee uur luisteren hoor je de eerste. Technisch geland, praktisch onzichtbaar.
///
/// Dus schuiven ze om en om tussen de plekken die nog niet aan de beurt zijn geweest. Alles wat al
/// speelt, in de rij staat of onderweg is blijft onaangeroerd staan — daar mag een nakomer niet
/// tussen springen, want dat is de volgorde die je op dit moment hoort.
List<Radioplek> mengNakomers(List<Radioplek> plan, List<Radioplek> nieuw) {
  if (nieuw.isEmpty) return plan;
  var grens = 0;
  for (var i = 0; i < plan.length; i++) {
    // Eigen muziek die nog niet in de rij staat ([Haalstand.klaar]) is nog niet aan de beurt geweest:
    // die telde eerst mee, en dan kwamen nakomers achter het hele blok terecht.
    if (plan[i].stand != Haalstand.wacht && plan[i].stand != Haalstand.klaar) grens = i + 1;
  }
  // De reserve blijft achteraan: dat is het vangnet, geen mengmuziek (zie [kReserveVooruit]).
  final rest = [for (final p in plan.sublist(grens)) if (!p.reserve) p];
  final reserve = [for (final p in plan.sublist(grens)) if (p.reserve) p];
  final uit = [...plan.take(grens)];
  for (var i = 0; i < rest.length || i < nieuw.length; i++) {
    // De nakomer EERST. Gemeten op 12-09-2026: met de plek van Deezer vooraan kwam er in zeven
    // minuten radio precies EEN van de twaalf namen van het model voorbij (Patrice Rushen) — je
    // werkt eerst het hele blok af dat al in de rij stond. Op deze nieuwe namen heb je gewacht;
    // die horen niet achter de bekende aan te sluiten.
    if (i < nieuw.length) uit.add(nieuw[i]);
    if (i < rest.length) uit.add(rest[i]);
  }
  return [...uit, ...reserve];
}

/// Het plan na het afstemmen: wat al in gang is blijft, de rest wordt vervangen door [nieuw].
///
/// **Wat blijft.** Wat speelt of in de rij staat ([Haalstand.inRij]), wat onderweg is of net
/// geland — daar is al voor betaald, en het hoort bij wat je nu hoort. En wat mislukte, want dat
/// hoeft niet opnieuw geprobeerd te worden. **Wat weg gaat.** Wat nog wacht en de eigen muziek die
/// nog niet in de rij stond ([Haalstand.klaar]): die zijn gekozen onder de vorige stand.
///
/// Los van [RadioBesturing.stemAf], zodat het zonder speler te beproeven is — net als
/// [mengNakomers].
List<Radioplek> stemPlanAf(List<Radioplek> plan, List<Radioplek> nieuw) {
  final blijft = [
    for (final p in plan)
      if (p.zaad || p.reserve || (p.stand != Haalstand.wacht && p.stand != Haalstand.klaar)) p
  ];
  return [...blijft, ...nieuweNakomers(blijft, nieuw)];
}

/// Wat de radio de bijvuller meegeeft bij een ronde. [reserveNodig]: hoeveel eigen nummers er als
/// reserve bij mogen (0: nog niet, of genoeg); [reserveKlaar]: hoeveel er al klaarstaan.
typedef Bijvulvraag = ({bool nood, double verwacht, int reserveNodig, int reserveKlaar});

/// Een ronde van de bijvuller: geeft terug hoeveel plekken er bij kwamen. Zie `radiobijvuller.dart`.
typedef Bijvuller = Future<int> Function(int sessie, int ronde, Bijvulvraag vraag);

class RadioBesturing extends ChangeNotifier {
  /// [klok] is er voor de toetsen: de reserve na een minuut zonder landing, en een herkansing na een
  /// half uur, zijn anders niet na te spelen.
  RadioBesturing({required this.speler, required this.bron, DateTime Function()? klok})
      : _klok = klok ?? DateTime.now;

  final DateTime Function() _klok;

  /// Eén tik van de radio, nu — voor de toetsen, die niet vijf seconden willen wachten.
  @visibleForTesting
  void tikVoorToets() => _pas(_sessie);

  final PlayerStore speler;
  final Radiobron bron;

  List<Radioplek> _plan = const [];

  /// Het plan van de radio die nu loopt, of van de radio die net gestopt is.
  ///
  /// Blijft na [stop] staan: wie erover wil vertellen — een overzicht bij het afsluiten — moet er dan
  /// nog bij kunnen. Zonder dat is de vraag "wat heb je zojuist opgehaald" onbeantwoordbaar.
  List<Radioplek> get plan => _plan;

  /// Waarmee de radio zichzelf omschrijft, voor op het scherm.
  String naam = '';

  /// De artiest waar deze radio omheen gebouwd is, of null bij een radio uit een getypte zin — die
  /// heeft geen artiest om opnieuw op te vragen, en is dus ook niet af te stemmen.
  String? zaadArtiest;

  /// Het nummer waar de radio vanaf begon, als dat er was. Voor het afstemmen: dat liedje hoort er
  /// daarna evenmin nog een keer in.
  Track? zaad;

  /// Van een pad naar het gedeelde id, om een oordeel te kunnen terugvinden als het bestand er niet
  /// meer is. Ingehangen vanuit main.dart.
  String? Function(String pad)? idVanPad;

  /// Je eigen nummers van de zaadartiest, voor het laatste vangnet van het herhalen. Ingehangen vanuit
  /// main.dart.
  List<Track> Function()? eigenVanZaad;

  /// Heeft dit nummer een duim omhoog? Voor het herhalen (groen gaat eerst). Ingehangen vanuit main.dart.
  bool Function(Track t)? isGroen;

  /// Het bijvullen van deze radio, of null (dan vult hij niet bij). Zie [start].
  Bijvuller? _bijvul;
  void Function(String regel)? _spoor;

  /// Bij een radio uit een zin met een genoemd aantal ("300 nummers"): daar stopt het bijvullen.
  int? _aantal;

  bool _bijvulBezig = false;
  int _bijvulRonde = 0;
  DateTime? _vorigeRonde;
  bool _noodVorige = false;
  DateTime? _laatsteNood;
  DateTime? _startTijd;
  bool _eersteLanding = false;
  DateTime? _droogSinds;

  /// Telt elke stap waarin er iets voorbij kwam — zie [_stempel].
  int _voorbijteller = 0;
  int get voorbijteller => _voorbijteller;

  /// Bij welke plek een rij-item hoort. Op identiteit: weghalen uit de rij verschuift het niet.
  final Expando<Radioplek> _plekVan = Expando<Radioplek>('plek');

  /// De afloop van elke plek die gehaald moest worden, oud naar nieuw: true = geland, false = mislukt
  /// of geweerd. Voor [recenteOpbrengst].
  final List<bool> _uitkomsten = [];

  int _gehoordTeller = 0;

  /// Wat het bijvullen nu doet, voor het paneel — of null als er niets bijzonders is.
  String? bijvulStand;

  /// De bijvuller zegt wat hij doet. Alleen bij een verandering.
  void zetBijvulStand(String? stand) {
    if (stand == bijvulStand) return;
    bijvulStand = stand;
    notifyListeners();
  }

  /// Het bijvullen van een radio uit een zin staat stil omdat het genoemde aantal er is.
  bool get aantalBereikt {
    final a = _aantal;
    return a != null &&
        _plan.where((p) => p.stand != Haalstand.mislukt && !p.reserve && !p.herhaling).length >= a;
  }

  /// Het genoemde aantal is er én er komt niets meer: niets onderweg, wachtend of klaar. Dan pas zegt
  /// het scherm het, met "Ga door".
  bool get aantalOp =>
      aantalBereikt &&
      !_plan.any((p) =>
          !p.reserve &&
          (p.stand == Haalstand.wacht ||
              p.stand == Haalstand.onderweg ||
              p.stand == Haalstand.klaar ||
              p.stand == Haalstand.geland));

  /// Het genoemde aantal van een radio uit een zin, zolang het geldt.
  int? get aantal => _aantal;

  /// "Ga door" na een bereikt aantal: vanaf nu zonder grens.
  void gaDoor() {
    if (_aantal == null || !_loopt) return;
    _aantal = null;
    _spoor?.call('radio: het genoemde aantal is er — gaat door op verzoek');
    notifyListeners();
    _pas(_sessie);
  }

  /// Hoe lang een bijvulronde mag duren voor hij niet meer telt. Instelbaar voor de toetsen.
  @visibleForTesting
  Duration bijvulGeduld = const Duration(minutes: 3);

  /// Welke bijvulronde nu geldt. Wat een oudere ronde nog toevoegt, valt weg.
  int get bijvulRonde => _bijvulRonde;

  Timer? _tik;
  int _sessie = 0;

  /// Tot wanneer er niets nieuws gehaald wordt, na een Soulseek-storing. Zie [RadioLaterOpnieuw].
  DateTime? _rustTot;
  String? _rustWaarom;
  bool _pauzeGemeld = false;

  /// Waarom er nu even niets nieuws gehaald wordt, of null als het ophalen gewoon loopt. Voor het
  /// radiopaneel: een pauze die niemand ziet, lijkt op een radio die stil ophoudt.
  String? get pauze {
    final tot = _rustTot;
    return tot != null && DateTime.now().isBefore(tot) ? _rustWaarom : null;
  }

  /// De keuring vóór het halen: past deze plek in stijl en tijdvak? Zie `radiostijl.dart`.
  ///
  /// Vóór en niet ná, want een haal kost een Soulseek-plek en een minuut, en wat daarna in je
  /// bibliotheek staat moet je weer opruimen. Null: geen keuring, zoals een radio uit een getypte zin.
  Future<bool> Function(Radioplek plek)? _keur;
  bool _loopt = false;

  bool get loopt => _loopt;

  /// De paden die DEZE radio heeft opgehaald.
  ///
  /// Alleen hier mag een duim bij staan. Bij muziek die je zelf al had valt er niets weg te gooien, en
  /// een knop die dat suggereert is precies de knop die je een keer per ongeluk raakt.
  final Set<String> _doorRadio = {};

  bool doorDezeRadio(String pad) => _doorRadio.contains(pad);

  /// De radio die gestopt is en nog nagekeken moet worden, of null.
  ///
  /// Dit is wat het overzicht bij het afsluiten toont. Het overleeft een herstart, want anders is na
  /// een telefoon die je weglegt niet meer te achterhalen wélke bestanden er van die radio kwamen —
  /// en blijven ze voor altijd staan zonder dat iemand weet waar ze vandaan komen.
  RadioSessie? openstaand;

  RadioSessie? _lopend;

  File get _bestand => File('$appDir${Platform.pathSeparator}radio_sessie.json');

  /// De notitie van de vorige keer. Eén keer bij het opstarten.
  Future<void> laadOpenstaand() async {
    try {
      final f = _bestand;
      if (!await f.exists()) return;
      final s = RadioSessie.fromJson(jsonDecode(await f.readAsString()));
      if (s == null || s.leeg) return;
      openstaand = s;
      notifyListeners();
    } catch (_) {/* een half geschreven notitie is geen reden om niet op te starten */}
  }

  /// Het overzicht is afgehandeld. Weg ermee.
  Future<void> vergeetOpenstaand() async {
    openstaand = null;
    notifyListeners();
    // Via dezelfde rij als het schrijven, en niet als er een radio loopt: dan staat in dit bestand de
    // notitie van DIE radio, en die hoort niet weg omdat een oud overzicht is afgehandeld.
    final beurt = _schrijfBeurt.then((_) async {
      if (_lopend != null) return;
      try {
        final f = _bestand;
        if (await f.exists()) await f.delete();
      } catch (_) {}
    });
    _schrijfBeurt = beurt;
    await beurt;
  }

  /// Een deel van de notitie is afgehandeld: houd alleen wat [houd] zegt, en is er niets meer over,
  /// dan weg ermee.
  ///
  /// Voor het overzicht: wat bleef en wat werkelijk in de prullenbak ging is beslist; wat daar NIET
  /// heen kon staat er nog, en hoort de volgende keer terug te komen in plaats van voorgoed uit beeld
  /// te raken. Gevonden in de review van 26-09-2026: de hele notitie ging weg vóór het opruimen
  /// bevestigd was.
  ///
  /// Begon er intussen een nieuwe radio — het opruimen naar de prullenbak kan seconden duren — dan zit
  /// deze notitie al in die radio (zie [start]). Wat hier beslist is, gaat er dan ook daar uit, en het
  /// is DIE notitie die geschreven wordt; anders kwamen je geredde nummers bij de volgende stop terug
  /// onder "Deze gaan weg" (review van 26-09-2026).
  Future<void> houdAlleen(RadioSessie s, bool Function(Gehaald g) houd) async {
    final beslist = {
      for (final g in s.gehaald)
        if (!houd(g)) g.pad
    };
    s.gehaald.retainWhere(houd);
    final lopend = _lopend;
    if (lopend != null) {
      if (!identical(lopend, s)) lopend.gehaald.removeWhere((g) => beslist.contains(g.pad));
      if (identical(openstaand, s)) openstaand = s.leeg ? null : s;
      notifyListeners();
      await _bewaar(lopend);
      return;
    }
    if (s.leeg) {
      if (identical(openstaand, s)) await vergeetOpenstaand();
      return;
    }
    notifyListeners();
    await _bewaar(s);
  }

  // Eén schrijver tegelijk: elke landing schrijft de notitie, en twee schrijvers op hetzelfde
  // `.tmp`-bestand is een race die je niet ziet.
  Future<void> _schrijfBeurt = Future<void>.value();

  Future<void> _bewaar(RadioSessie? s) {
    if (s == null) return Future<void>.value();
    final beurt = _schrijfBeurt.then((_) async {
      try {
        await Directory(appDir).create(recursive: true);
        final tmp = File('${_bestand.path}.tmp');
        await tmp.writeAsString(jsonEncode(s.toJson()));
        await tmp.rename(_bestand.path);
      } catch (_) {/* de radio speelt door; de notitie is een vangnet, geen voorwaarde */}
    });
    _schrijfBeurt = beurt;
    return beurt;
  }

  /// Hoeveel er nog opgehaald wordt, en hoeveel er door deze radio binnengekomen is.
  int get onderweg => _plan.where((p) => p.stand == Haalstand.onderweg).length;
  int get gehaald => _plan.where((p) => p.doorRadio).length;

  /// Starten. Geeft null terug als het gelukt is, of de reden waarom niet — in gewone taal.
  Future<String?> start(List<Radioplek> nieuw,
      {String naam = '',
      String? zaadArtiest,
      Track? zaad,
      Future<bool> Function(Radioplek plek)? keur,
      void Function(int sessie)? bijStart,
      Bijvuller? bijvul,
      void Function(String regel)? spoor,
      int? aantal}) async {
    if (nieuw.isEmpty) return 'Er viel niets te vinden om een radio van te maken.';

    // Eerst vragen of het KAN, en pas daarna de lopende radio verlaten. Andersom zou een radio die
    // niet blijkt te kunnen starten — Soulseek uit, pc niet bereikbaar — de radio die wél liep
    // meenemen in zijn val, en dan sta je met niets.
    final tegen = await bron.begin();
    if (tegen != null) return tegen;

    // De haak weg vóór `playRadio`: die verlaat de oude radio óók, en de haak zou dan de radio
    // afbreken die we net aan het starten zijn. En niet loslaten wat [Radiobron.begin] zojuist
    // genomen heeft — die leen is voor de radio die nu begint.
    final nogLopend = _stop(laatLos: false, naarOverzicht: false);
    speler.bijRadioEinde = null;

    final sessie = ++_sessie;
    _rustTot = null;
    _rustWaarom = null;
    _pauzeGemeld = false;
    _keur = keur;
    _bijvul = bijvul;
    _spoor = spoor;
    _aantal = aantal;
    _bijvulBezig = false;
    _bijvulRonde = 0;
    _vorigeRonde = null;
    _noodVorige = false;
    _laatsteNood = null;
    _startTijd = _klok();
    _eersteLanding = false;
    _droogSinds = null;
    _voorbijteller = 0;
    _uitkomsten.clear();
    _gehoordTeller = 0;
    bijvulStand = null;
    _plan = nieuw;
    this.naam = naam;
    this.zaadArtiest = zaadArtiest;
    this.zaad = zaad;
    _loopt = true;
    _doorRadio.clear();
    _lopend = RadioSessie(naam: naam, begonnenMs: DateTime.now().millisecondsSinceEpoch);
    // Stond er nog een overzicht open ("Later beslissen"), dan gaat dat MEE in deze radio. Er is één
    // notitie op schijf, en de eerste landing van deze radio zou hem anders overschrijven — waarna die
    // bestanden voor altijd blijven staan zonder dat iemand nog weet dat ze van een radio kwamen.
    // Het overzicht verschijnt dan ook niet meer over een radio die net begint.
    // En net zo wat de radio ophaalde die nog liep toen deze begon — die gaat niet eerst naar het
    // overzicht, zie [_stop].
    final vorige = openstaand;
    for (final v in [vorige, nogLopend]) {
      if (v != null) _lopend!.gehaald.addAll(v.gehaald);
    }
    if (vorige != null || nogLopend != null) {
      openstaand = null;
      unawaited(_bewaar(_lopend));
    }

    // De eerste ronde met de hand, want [PlayerStore.voegToeAanRadio] doet niets zolang er nog geen
    // radio loopt.
    // Met de tijd erbij: er klinkt nog niets, en wat er in gaat telt op — zie `kRuimeRest`. Zonder
    // dat kwam er bij de start meteen een tweede nummer van de zaadartiest achter het zaad.
    final besluit = voorraadPlan([for (final p in nieuw) p.stand],
        artiesten: [for (final p in nieuw) p.artiest],
        vooruitNu: 0,
        restSeconden: 0,
        seconden: [for (final p in nieuw) _lengte(p)],
        zaad: zaadArtiest);
    final eerste = <RadioItem>[];
    for (final i in besluit.inRij) {
      nieuw[i].stand = Haalstand.inRij;
      eerste.add(_itemVan(nieuw[i]));
    }
    // Geen `radioExtend`: dat is de oude weg, die er per lading verse AANBEVELINGEN bij haalde. Hier
    // is het plan al bekend en gaat het erom wat ervan geland is.
    speler.radioExtend = null;
    await speler.playRadio(eerste);
    if (sessie != _sessie) return null; // iemand was intussen sneller
    speler.bijRadioEinde = (_) {
      if (sessie == _sessie) stop();
    };
    // Een nummer dat de speler oversloeg: het bestand deugde niet, of het bleef onbereikbaar. Op de
    // plek, zodat het niet herhaald wordt — en een verdwenen bestand ook niet opnieuw gehaald.
    speler.bijRadioOverslaan = (it, {required bestand}) {
      if (sessie != _sessie) return;
      final p = _plekVan[it];
      if (p != null) p.weer = bestand ? Weerreden.verdwenen : Weerreden.nietGevonden;
    };
    // Alleen als DEZE start het werd. Een start die ingehaald is geeft ook null terug, en wie dan
    // [sessie] las, voegde zijn nummers toe aan de radio die hem inhaalde (review van 26-09-2026).
    bijStart?.call(sessie);

    for (final i in besluit.starten) {
      nieuw[i].stand = Haalstand.onderweg;
      unawaited(_haal(sessie, nieuw[i]));
    }
    // Vijf seconden, en bewust niet meeluisteren met de speler: die meldt zich vier keer per seconde
    // zolang er iets klinkt, en dan zou deze rekensom vier keer per seconde draaien om te ontdekken
    // dat er niets veranderd is.
    _tik = Timer.periodic(const Duration(seconds: 5), (_) => _pas(sessie));
    notifyListeners();
    return null;
  }

  /// Welke radio er nu loopt. Een nakomer die bij een ANDERE radio hoort mag er niet meer bij.
  int get sessie => _sessie;

  /// Namen die pas ná de start binnenkwamen er alsnog bij schuiven.
  ///
  /// **Waarom bijvoegen en niet wachten.** Gemeten op 12-09-2026: het taalmodel doet er 25 tot 30
  /// seconden over om vierentwintig artiesten met een reden erbij te noemen. De eerste opzet liet
  /// [RecommendService.mixRadio] daarop wachten met acht seconden geduld — en dat liep elke keer af
  /// voor het antwoord er was, dus kwam er geen énkele naam van het model in de rij terecht terwijl
  /// het logboek keurig meldde dat er vierentwintig waren. Langer wachten kan niet: een radio die
  /// een halve minuut zwijgt nadat je op de knop drukte is stuk.
  ///
  /// Dus begint de radio met wat Deezer meteen geeft, en schuiven deze erbij zodra ze er zijn.
  /// [_pas] loopt elke vijf seconden en pakt ze vanzelf op — er hoeft hier niets gestart te worden.
  ///
  /// Geeft terug hoeveel plekken er werkelijk bij kwamen. [ronde]: van welke bijvulronde ze komen —
  /// is die intussen voorbij (een time-out, een nieuwe radio), dan komt er niets meer bij.
  ///
  /// [achteraan]: na wat er al wacht, vóór de reserve, in plaats van ertussen gemengd. Voor het
  /// bijvullen: dat begon op de pc al na vijf seconden en zette zo vierentwintig ongekeurde buren
  /// tussen de startlijst die het model op sfeer gekeurd had (beoordeling van 08-10-2026).
  int voegBij(int sessie, List<Radioplek> extra, {int? ronde, bool achteraan = false}) {
    if (sessie != _sessie || !_loopt || extra.isEmpty) return 0;
    if (ronde != null && ronde != _bijvulRonde) return 0;
    final nieuw = nieuweNakomers(_plan, extra);
    if (nieuw.isEmpty) return 0;
    if (achteraan) {
      var k = _plan.length;
      while (k > 0 && _plan[k - 1].reserve) {
        k--;
      }
      _plan = [..._plan.take(k), ...nieuw, ..._plan.skip(k)];
    } else {
      _plan = mengNakomers(_plan, nieuw);
    }
    notifyListeners();
    return nieuw.length;
  }

  /// Eigen nummers als reserve erbij: achteraan, en ze spelen pas mee als het krap wordt (zie
  /// [kReserveVooruit]). [plekken] moeten [Radioplek.reserve] zijn.
  int voegReserveBij(int sessie, List<Radioplek> plekken) {
    if (sessie != _sessie || !_loopt || plekken.isEmpty) return 0;
    final nieuw = nieuweNakomers(_plan, [for (final p in plekken) if (p.reserve && p.eigen != null) p]);
    if (nieuw.isEmpty) return 0;
    _plan = [..._plan, ...nieuw];
    _spoor?.call('radio-reserve: ${nieuw.length} eigen nummers klaar — '
        '${nieuw.map((p) => '${p.artiest} — ${p.titel}').join('; ')}');
    notifyListeners();
    return nieuw.length;
  }

  /// Wat niet te vinden was en minstens [na] oud is, nog één keer proberen: hoogstens [max].
  int herkans(int sessie, {required int ronde, int max = 8, Duration na = const Duration(minutes: 30)}) {
    if (sessie != _sessie || !_loopt || ronde != _bijvulRonde) return 0;
    final nu = _klok();
    var n = 0;
    for (final p in _plan) {
      if (n >= max) break;
      if (p.stand != Haalstand.mislukt || p.weer != Weerreden.nietGevonden || p.herkansd) continue;
      final op = p.mislukteOp;
      if (op == null || nu.difference(op) < na) continue;
      p.stand = Haalstand.wacht;
      p.weer = null;
      p.herkansd = true;
      n++;
    }
    if (n > 0) notifyListeners();
    return n;
  }

  /// Herhalen wat deze radio al speelde, als er niets nieuws is: hoogstens [hoeveel]. Zie
  /// [kiesHerhaling]. Gaat buiten [nieuweNakomers] om — die zou elke herhaling weren, want het nummer
  /// staat al in het plan — en meteen als [Haalstand.geland], zodat het de rij in gaat.
  int voegHerhalingBij(int sessie, int hoeveel) {
    if (sessie != _sessie || !_loopt || hoeveel <= 0) return 0;
    // Per bestand: de laatste keer dat het voorbij kwam, of je het hoorde, en of het nog komt (dan niet
    // nóg eens).
    final laatst = <String, int>{};
    final gehoordPad = <String>{};
    final komtNog = <String>{};
    final weg = <String>{};
    final eerste = <String, Radioplek>{};
    for (final p in _plan) {
      final t = p.eigen;
      if (t == null) continue;
      final pad = t.path;
      eerste.putIfAbsent(pad, () => p);
      // Weg, door je duim, of onbereikbaar gebleven: niet terug.
      if (p.weer == Weerreden.verdwenen || p.weer == Weerreden.duim || p.weer == Weerreden.nietGevonden) {
        weg.add(pad);
      }
      if (p.gehoord) gehoordPad.add(pad);
      // Een herhaling die je oversloeg: dat nummer wil je nu niet, ook al hoorde je het eerder wel.
      if (p.herhaling && p.voorbijOp != null && !p.gehoord) weg.add(pad);
      final v = p.voorbijOp;
      if (v != null) {
        final oud = laatst[pad];
        if (oud == null || oud < v) laatst[pad] = v;
      } else if (p.stand != Haalstand.mislukt) {
        komtNog.add(pad);
      }
    }
    final zaadEigen = eigenVanZaad?.call() ?? const <Track>[];
    final paden = <String>[
      for (final pad in eerste.keys)
        if (!weg.contains(pad) && !komtNog.contains(pad)) pad,
      for (final t in zaadEigen)
        if (!eerste.containsKey(t.path) && !weg.contains(t.path)) t.path,
    ];
    final zaadPaden = {for (final t in zaadEigen) t.path};
    final trackVan = {for (final t in zaadEigen) t.path: t, for (final e in eerste.entries) e.key: e.value.eigen!};
    final k = <Herhaalkandidaat>[
      for (final pad in paden)
        (
          artiest: eerste[pad]?.artiest ?? trackVan[pad]!.artist,
          laatstVoorbij: laatst[pad],
          gehoord: gehoordPad.contains(pad),
          groen: isGroen?.call(trackVan[pad]!) ?? false,
          eigen: !(eerste[pad]?.doorRadio ?? false),
          opSchijf: (eerste[pad]?.doorRadio ?? false) && (pad.startsWith('http') || File(pad).existsSync()),
          zaadOfAnker: zaadPaden.contains(pad),
          rood: false,
        )
    ];
    // Wie al aan zijn plafond zit (zie [artiestenVoorPlafond]) komt pas als er niemand anders is.
    final telling = <String, int>{};
    for (final a in artiestenVoorPlafond(_plan, voorbijteller: _voorbijteller)) {
      final sl = artiestSleutel(a);
      telling[sl] = (telling[sl] ?? 0) + 1;
    }
    final rij = speler.radioQueue;
    final zaadSleutel = zaadArtiest == null ? null : artiestSleutel(zaadArtiest!);
    final zaadNet = zaadSleutel != null &&
        rij
            .skip(rij.length > kZaadAfstand ? rij.length - kZaadAfstand : 0)
            .any((it) => artiestSleutel(it.artist) == zaadSleutel);
    final keuze = kiesHerhaling(k,
        teller: _voorbijteller,
        recenteArtiesten: [for (final it in rij.skip(rij.length > kArtiestAfstand ? rij.length - kArtiestAfstand : 0)) it.artist],
        vol: {
          for (final e in telling.entries) if (e.value >= kMaxPerArtiest) e.key,
          if (zaadNet) zaadSleutel,
        },
        hoeveel: hoeveel);
    if (keuze.keuze.isEmpty) return 0;
    final erbij = <Radioplek>[];
    for (final i in keuze.keuze) {
      final pad = paden[i];
      final t = trackVan[pad]!;
      final bron = eerste[pad];
      // Kwam het in deze radio al eens voorbij, dan is het een herhaling en zegt het scherm "opnieuw".
      // Een eigen nummer van de zaadartiest dat nog niet speelde is gewoon een eigen nummer.
      final opnieuw = laatst[pad] != null;
      final plek = Radioplek(
        artiest: bron?.artiest ?? t.artist,
        titel: bron?.titel ?? t.title,
        seconden: t.duration?.inSeconds,
        eigen: t,
        bron: opnieuw ? 'herhaling' : 'vangnet',
        herhaling: opnieuw,
      )
        ..doorRadio = bron?.doorRadio ?? false
        ..stand = Haalstand.geland;
      erbij.add(plek);
      _spoor?.call(opnieuw
          ? 'radio-herhaling: "${plek.artiest} — ${plek.titel}" (${_voorbijteller - laatst[pad]!} voorbij geleden, niveau ${keuze.niveau})'
          : 'radio-vangnet: "${plek.artiest} — ${plek.titel}" (van jou, nog niet in deze radio)');
    }
    _plan = [..._plan, ...erbij];
    notifyListeners();
    return erbij.length;
  }

  /// Een nummer is echt beluisterd (dezelfde maat als de luistertelling van de app). Voor het logboek:
  /// zo is na te tellen hoe lang een radio werkelijk liep.
  void gehoord(Track t) {
    if (!_loopt) return;
    Radioplek? p;
    for (final q in _plan) {
      if (q.eigen?.path == t.path) p = q;
    }
    if (p == null) return;
    p.gehoord = true;
    _gehoordTeller++;
    final soort = p.herhaling ? 'herhaling' : (p.doorRadio ? 'nieuw' : 'eigen');
    _spoor?.call('radio-gehoord #$_gehoordTeller: "${p.artiest} — ${p.titel}" ($soort)');
  }

  /// De radio opnieuw afstemmen — Bekend, Gemengd of Ontdekken — zonder hem te stoppen.
  ///
  /// Wat je nu hoort en wat al onderweg is blijft; de rest van het plan wordt [nieuw]. Zie
  /// [stemPlanAf]. Hoort [sessie] niet meer bij de radio die loopt, dan gebeurt er niets: dan was
  /// iemand intussen een andere radio begonnen.
  void stemAf(int sessie, List<Radioplek> nieuw) {
    if (sessie != _sessie || !_loopt) return;
    _plan = stemPlanAf(_plan, nieuw);
    notifyListeners();
    _pas(sessie);
  }

  /// Stoppen. Laat het plan staan, want daar valt straks nog over te vertellen.
  void stop() => _stop(laatLos: true);

  /// [naarOverzicht] onwaar bij een nieuwe start: dan gaat de notitie van deze radio niet naar het
  /// overzicht maar terug naar de aanroeper, die hem meeneemt in de radio die begint — zie [start].
  RadioSessie? _stop({required bool laatLos, bool naarOverzicht = true}) {
    _tik?.cancel();
    _tik = null;
    _sessie++; // alles wat nog onderweg is hoort nergens meer bij
    final liep = _loopt;
    _loopt = false;
    // En "hoort nergens meer bij" is niet genoeg: wat er loopt moet ook OPHOUDEN. Altijd, ook als de
    // aanmelding blijft staan omdat er een nieuwe radio begint — zie [Radiobron.staak].
    if (liep) bron.staak();
    if (laatLos) bron.einde();
    // Heeft deze radio iets opgehaald, dan is er iets na te kijken. Zo niet, dan is er niets te
    // vragen en hoort er ook geen overzicht te komen — dat zou een venster zijn dat alleen maar in
    // de weg staat.
    final s = _lopend;
    final teVertellen = liep && s != null && !s.leeg ? s : null;
    if (teVertellen != null && naarOverzicht) {
      openstaand = teVertellen;
      unawaited(_bewaar(teVertellen));
    }
    _lopend = null;
    // Niet seinen bij een nieuwe start: het scherm opende dan het overzicht van de vorige radio, en
    // een tel later was die notitie al meegenomen — maar het venster stond er (27-09-2026, van Sade
    // naar Zombie: "47 naar de prullenbak" over de radio die net begon). [start] seint zelf.
    if (liep && naarOverzicht) notifyListeners();
    return teVertellen;
  }

  @override
  void dispose() {
    _tik?.cancel();
    bron.staak();
    bron.einde();
    super.dispose();
  }

  static int? _lengte(Radioplek p) => p.eigen?.duration?.inSeconds ?? p.seconden;

  /// Hoeveel seconden muziek er nog klinkt voor de rij leeg is: de rest van het huidige nummer plus
  /// wat erachter staat. Null als de speler het niet weet (nog niets geladen).
  int? _restSeconden() {
    final rij = speler.radioQueue;
    final i = speler.radioIndex;
    final lengte = speler.duration.inSeconds;
    if (i < 0 || i >= rij.length || lengte <= 0) return null;
    var rest = lengte - speler.positieErgens.inSeconds;
    if (rest < 0) rest = 0;
    for (final it in rij.skip(i + 1)) {
      final s = it.local?.duration?.inSeconds;
      rest += s != null && s > 0 ? s : kOnbekendeLengte;
    }
    return rest;
  }

  RadioItem _itemVan(Radioplek p) {
    final it = RadioItem(artist: p.artiest, title: p.titel, local: p.eigen, herhaling: p.herhaling);
    _plekVan[it] = p;
    return it;
  }

  /// Wat er in de rij vóór het spelende nummer staat, is voorbij — gespeeld of overgeslagen. Alles
  /// wat in één beweging voorbij ging (een tik van regel 10 naar 30) krijgt dezelfde stempel: één stap.
  /// Wordt een nummer weer het spelende (terug met "vorige"), dan is het niet meer voorbij.
  void _stempel() {
    final rij = speler.radioQueue;
    final i = speler.radioIndex;
    final nieuw = <Radioplek>[];
    for (var k = 0; k < i && k < rij.length; k++) {
      final p = _plekVan[rij[k]];
      if (p != null && p.voorbijOp == null) nieuw.add(p);
    }
    if (nieuw.isNotEmpty) {
      final stap = ++_voorbijteller;
      for (final p in nieuw) {
        p.voorbijOp = stap;
      }
    }
    if (i >= 0 && i < rij.length) _plekVan[rij[i]]?.voorbijOp = null;
  }

  /// Moet er bijgevuld worden? Zie [bijvulBesluit].
  ({Bijvulbesluit besluit, double verwacht}) _bijvulNu() {
    final rij = speler.radioQueue;
    final vooruit = rij.length - speler.radioIndex - 1;
    final opbrengst = recenteOpbrengst(_uitkomsten);
    final klaar = [for (final p in _plan) if (p.stand == Haalstand.klaar && !p.reserve) p.artiest];
    final geland = _plan.where((p) => p.stand == Haalstand.geland).length;
    final onderweg = _plan.where((p) => p.stand == Haalstand.onderweg).length;
    final wacht = _plan.where((p) => p.stand == Haalstand.wacht).length;
    final verwacht = verwachtVooruit(
      rijVooruit: vooruit < 0 ? 0 : vooruit,
      geland: geland,
      klaarArtiesten: klaar,
      zaad: zaadArtiest,
      onderweg: onderweg,
      wacht: wacht,
      opbrengst: opbrengst,
    );
    final b = bijvulBesluit(
      loopt: _loopt,
      speelt: speler.playing,
      droog: speler.radioDroog,
      wilVerder: speler.wilVerder,
      verwacht: verwacht,
      restSeconden: _restSeconden(),
      gelandOfKlaar: geland + klaar.length,
      onderweg: onderweg,
      opbrengst: opbrengst,
      bezig: _bijvulBezig,
      // Afgerond, niet afgekapt: de droogte wordt aan het eind van een tik vastgelegd, en vijf seconden
      // later is het verschil 4,99 s — dat telde als 4, en dan kwam de nood pas een tik later.
      droogSeconden: _droogSinds == null ? 0 : (_klok().difference(_droogSinds!).inMilliseconds + 500) ~/ 1000,
      vorige: _vorigeRonde,
      nu: _klok(),
    );
    return (besluit: b, verwacht: verwacht);
  }

  /// Bijvullen als het besluit dat zegt, en nood flankgestuurd: bij de overgang, daarna hoogstens
  /// één keer per dertig seconden zolang de nood duurt.
  ///
  /// [reserveVoor] is wat er aan reserve klaarstond vóór [voorraadPlan] er bij nood twee van de rij in
  /// zette — anders leek de reserve bij nood altijd leeg, en kwamen er nog twee herhalingen bovenop.
  void _misschienBijvullen(int sessie, Bijvulbesluit b, double verwacht, int reserveVoor) {
    if (sessie != _sessie || !_loopt) return;
    final nu = _klok();
    final reserveKlaar = _plan.where((p) => p.reserve && p.stand == Haalstand.klaar).length;
    // Een radio uit een zin die zijn aantal heeft, stopt — met "Ga door" (Sabers keuze). Herhalen zou
    // hem eindeloos laten doorgaan, en dan kwam die knop nooit in beeld.
    if (b.nood &&
        !aantalBereikt &&
        (!_noodVorige || _laatsteNood == null || nu.difference(_laatsteNood!) >= const Duration(seconds: 30))) {
      _laatsteNood = nu;
      // Stond er reserve klaar, dan nam [voorraadPlan] die al mee. Zo niet: herhalen.
      if (reserveVoor == 0) {
        final n = voegHerhalingBij(sessie, 2);
        _spoor?.call('radio-nood: ${n == 0 ? 'niets om te herhalen' : '$n herhalingen'}');
        if (n > 0) {
          _noodVorige = b.nood;
          _pas(sessie);
          return;
        }
      } else {
        _spoor?.call('radio-nood: reserve speelt mee');
      }
    }
    _noodVorige = b.nood;
    final f = _bijvul;
    if (f == null || !b.nu || aantalBereikt) return;
    _bijvulBezig = true;
    final ronde = ++_bijvulRonde;
    _vorigeRonde = nu;
    // De reserve mag na de eerste landing, na een minuut zonder landing, of bij nood.
    final start = _startTijd;
    final reserveMag = _eersteLanding || b.nood || (start != null && nu.difference(start) >= kReserveZonderLanding);
    final vraag = (
      nood: b.nood,
      // Wat de reserve net de rij in bracht staat er nu: anders kwamen er in dezelfde nood nog twee
      // herhalingen bovenop de twee reservenummers.
      verwacht: verwacht + (reserveVoor - reserveKlaar).clamp(0, reserveVoor),
      reserveNodig: reserveMag ? (kReserve - reserveKlaar).clamp(0, kReserve) : 0,
      reserveKlaar: reserveKlaar,
    );
    f(sessie, ronde, vraag).timeout(bijvulGeduld).then((n) {
      if (sessie != _sessie || ronde != _bijvulRonde) return;
      _bijvulBezig = false;
      if (n > 0) _pas(sessie);
    }, onError: (Object e) {
      if (sessie != _sessie || ronde != _bijvulRonde) return;
      // Een ronde die niet afkomt: hij telt niet meer, en wat hij later nog toevoegt valt weg.
      _bijvulRonde++;
      _bijvulBezig = false;
      _spoor?.call('radio-bijvul #$ronde: ${e is TimeoutException ? 'na ${bijvulGeduld.inSeconds} s afgebroken' : 'fout — $e'}');
    });
  }

  /// Een regel in het logboek als de radio droog valt, en als hij weer speelt.
  void _droogSpoor() {
    final droog = speler.radioDroog;
    final since = _droogSinds;
    if (droog && since == null) {
      _droogSinds = _klok();
      final voorbij = _plan.where((p) => p.voorbijOp != null).length;
      final weg = _plan.where((p) => p.stand == Haalstand.mislukt).length;
      _spoor?.call('radio droog: rij leeg, $onderweg onderweg, plan ${_plan.length} '
          '($voorbij voorbij, $weg geweerd/mislukt)');
    } else if (!droog && since != null) {
      _droogSinds = null;
      _spoor?.call('radio hervat na ${_klok().difference(since).inSeconds} s');
    }
  }

  /// Duim omlaag: dit nummer NU weg. Uit de rij, uit het plan, van de schijf.
  ///
  /// **Waarom dit meteen gebeurt en niet bij het afsluiten.** Zo was het eerst wel: rood werd
  /// opgeschreven en pas bij "Radio afsluiten" uitgevoerd, met een overzicht en een kans om iets te
  /// redden. Op het toestel bleek dat het omgekeerde van wat er gevraagd is — "vanaf ik de duim
  /// omlaag doe, moet het direct verwijderd worden!" — en het is ook eerlijker: een knop met een
  /// prullenbakbetekenis die niets zichtbaars doet, druk je nog een keer in.
  ///
  /// Alleen wat DEZE radio ophaalde mag hier weg; bij muziek die je zelf al had staat er geen duim.
  /// Geeft terug of er werkelijk iets weggegooid is.
  ///
  /// Null als dit geen nummer van deze radio is (dan gebeurt er niets), false als het niet weg kon.
  Future<bool?> gooiWeg(Track t) async {
    final pad = t.path;
    if (!_doorRadio.remove(pad)) return null;

    // Eerst uit het plan, want anders zet de eerstvolgende tik van [_pas] hem gewoon weer in de rij.
    // `mislukt` en niet iets nieuws: die stand betekent precies dit — deze plek telt nergens meer in
    // mee en er gebeurt niets meer mee.
    var artiest = t.artist;
    var titel = t.title;
    for (final p in _plan) {
      if (p.eigen?.path != pad) continue;
      artiest = p.artiest;
      titel = p.titel;
      p.eigen = null;
      p.doorRadio = false;
      p.stand = Haalstand.mislukt;
      p.weer = Weerreden.duim;
    }

    // Dan uit de speelrij, en dat is ook wat het bestand loslaat als het net klonk.
    await speler.haalUitRadio(pad);

    notifyListeners();
    final weg = await bron.vergeet(pad: pad, artiest: artiest, titel: titel);
    // Kon het niet weg, dan blijft het in de notitie: het overzicht biedt het straks opnieuw aan, in
    // plaats van dat het bestand voorgoed op je schijf blijft staan zonder dat iemand weet waarvandaan.
    if (!weg) return false;
    // Wat weg is hoeft bij het afsluiten niet meer nagekeken te worden. Ook uit een notitie die al
    // klaarligt — een radio die net gestopt is maar waarvan het overzicht nog openstaat, hoort geen
    // bestand aan te bieden dat er niet meer is.
    _lopend?.gehaald.removeWhere((g) => g.pad == pad);
    openstaand?.gehaald.removeWhere((g) => g.pad == pad);
    // Eén schrijfbeurt, en die van de LOPENDE radio wint: zo doet [_haal] het ook, en twee keer naar
    // hetzelfde bestand schrijven is een race die je niet ziet en niet kunt navertellen.
    unawaited(_bewaar(_lopend ?? openstaand));
    notifyListeners();
    return true;
  }

  /// Kijken wat er nu te doen valt, en het doen.
  void _pas(int sessie) {
    if (sessie != _sessie) return;
    // Is de pauze voorbij, dan het paneel bijwerken: anders bleef "Ophalen staat even stil" staan tot
    // er toevallig iets anders veranderde — bij een leeg plan nooit.
    if (_pauzeGemeld && pauze == null) {
      _pauzeGemeld = false;
      notifyListeners();
    }
    _stempel();
    final bijvul = _bijvulNu();
    final reserveVoor = _plan.where((p) => p.reserve && p.stand == Haalstand.klaar).length;
    final vooruit = speler.radioQueue.length - speler.radioIndex - 1;
    final rij = speler.radioQueue;
    final besluit = voorraadPlan(
      [for (final p in _plan) p.stand],
      artiesten: [for (final p in _plan) p.artiest],
      // Wat er achteraan de rij staat, zodat een net geland nummer niet vlak achter zijn eigen
      // artiest belandt.
      // Tien, en niet acht: de zaadartiest moet tien plekken terug kunnen kijken ([kZaadAfstand]).
      staart: [for (final it in rij.skip(rij.length > kZaadAfstand ? rij.length - kZaadAfstand : 0)) it.artist],
      vooruitNu: vooruit < 0 ? 0 : vooruit,
      rust: _rustTot != null && DateTime.now().isBefore(_rustTot!),
      restSeconden: _restSeconden(),
      seconden: [for (final p in _plan) _lengte(p)],
      zaad: zaadArtiest,
      reserve: [for (final p in _plan) p.reserve],
      nood: bijvul.besluit.nood,
      // Het genoemde aantal is er: dan ook geen eigen nummers meer als vulling.
      reserveMag: !aantalBereikt,
    );

    if (besluit.inRij.isNotEmpty) {
      final erbij = <RadioItem>[];
      for (final i in besluit.inRij) {
        _plan[i].stand = Haalstand.inRij;
        erbij.add(_itemVan(_plan[i]));
      }
      speler.voegToeAanRadio(erbij);
    }
    for (final i in besluit.starten) {
      _plan[i].stand = Haalstand.onderweg;
      unawaited(_haal(sessie, _plan[i]));
    }
    if (besluit.inRij.isNotEmpty || besluit.starten.isNotEmpty) notifyListeners();
    _droogSpoor();
    _misschienBijvullen(sessie, bijvul.besluit, bijvul.verwacht, reserveVoor);
  }

  Future<void> _haal(int sessie, Radioplek p) async {
    final keur = _keur;
    if (keur != null) {
      var mag = true;
      try {
        mag = await keur(p);
      } on RadioKeuringLater {
        // Nog geen oordeel: terug bij wat nog gehaald moet worden. Geen rust voor de hele radio — de
        // vraag loopt door, en de volgende tik probeert deze plek opnieuw. Zie [RadioKeuringLater].
        if (sessie != _sessie) return;
        p.stand = Haalstand.wacht;
        notifyListeners();
        return;
      } catch (_) {/* een keuring die stukloopt is geen nee */}
      if (sessie != _sessie) return;
      if (!mag) {
        // Geweerd: telt nergens meer in mee, net als een plek die niet te vinden was. `??=`: de
        // keuring zette misschien al "tijdvak" of "sfeer", en dat moet blijven staan — anders vindt
        // een ruimer venster later geen enkele tijdvakweigering terug.
        p.stand = Haalstand.mislukt;
        p.weer ??= Weerreden.stijl;
        _uitkomsten.add(false);
        notifyListeners();
        _pas(sessie);
        return;
      }
    }
    Track? t;
    var later = false;
    var vanRadio = true;
    String? waarom;
    try {
      t = await bron.haal(p);
    } on RadioLaterOpnieuw catch (e) {
      later = true;
      waarom = e.waarom;
    } on AlVanJou catch (e) {
      t = e.nummer;
      vanRadio = false;
    } catch (_) {
      t = null;
    }
    if (sessie != _sessie) return; // een andere radio; deze landing hoort daar niet bij
    if (later) {
      // Geen mislukte plek: Soulseek deed even niet mee. Terug bij wat nog gehaald moet worden, en
      // een minuut niets nieuws beginnen — anders start de klok van vijf seconden er meteen weer
      // acht, die net zo snel stuklopen.
      p.stand = Haalstand.wacht;
      _rustTot = DateTime.now().add(kRadioRust);
      // Pas hier, ná de toets op de sessie: een late pauze van de vorige radio mag de reden van deze
      // niet overschrijven (tweede beoordeling van 26-09-2026).
      _rustWaarom = waarom;
      _pauzeGemeld = true;
      notifyListeners();
      return;
    }
    if (t == null) {
      // Geen foutmelding en geen gat: deze plek slaat over en het plan schuift door. Een radio die
      // bij elke peer die niet thuis geeft iets op het scherm zet, is onbruikbaar.
      p.stand = Haalstand.mislukt;
      p.weer = Weerreden.nietGevonden;
      p.mislukteOp = _klok();
      _uitkomsten.add(false);
    } else if (!vanRadio) {
      // Van jou: in de rij, maar niet in de notitie van deze radio — zie [AlVanJou].
      p.eigen = t;
      p.stand = Haalstand.geland;
      _uitkomsten.add(true);
      _eersteLanding = true;
    } else {
      _uitkomsten.add(true);
      _eersteLanding = true;
      p.eigen = t;
      p.doorRadio = true;
      // `geland` en niet `klaar`: dit gaat meteen de rij in. Zie [Haalstand.geland] — een net
      // opgehaald nummer dat blijft liggen tot de voorraad opdroogt is een nummer dat je nooit hoort.
      p.stand = Haalstand.geland;
      _doorRadio.add(t.path);
      _lopend?.gehaald.add(Gehaald(
        pad: t.path,
        artiest: p.artiest,
        titel: p.titel,
        id: idVanPad?.call(t.path),
        bytes: t.sizeBytes,
      ));
      // Meteen op schijf, niet pas bij het afsluiten. Een app die wordt weggehaald terwijl de radio
      // loopt is precies het geval waarvoor die notitie er is.
      unawaited(_bewaar(_lopend));
    }
    notifyListeners();
    _pas(sessie);
  }
}
