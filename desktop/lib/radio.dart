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

import 'package:flutter/foundation.dart';

import 'library.dart';
import 'models.dart';
import 'online.dart';
import 'player.dart';
import 'radiovoorraad.dart';

/// Eén plek in het radioplan: wat er zou moeten spelen, en hoe ver het daarmee is.
class Radioplek {
  Radioplek({
    required this.artiest,
    required this.titel,
    this.seconden,
    this.jaar,
    this.eigen,
  }) {
    // Wat je al hebt is meteen klaar: het bestand staat er, er valt niets aan te halen. Dat is de
    // enige plek waar het onderscheid tussen "eigen muziek" en "moet nog komen" gemaakt wordt.
    if (eigen != null) stand = Haalstand.klaar;
  }

  final String artiest;
  final String titel;

  /// Hoe lang het volgens de catalogus duurt, en uit welk jaar het is.
  ///
  /// Allebei gaan ze mee als GEZAG naar de download, en allebei doen ze er om een eigen reden toe —
  /// zie [DownloadManager.haalVoorRadio]: het jaar is wat de tags gezaghebbend maakt (zonder dat
  /// schrijft `stampTags` niets), de looptijd is de Sting-val.
  final int? seconden;
  final int? jaar;

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

  /// Eén nummer halen. Geeft het nummer terug zoals het in de bibliotheek staat, of null.
  Future<Track?> haal(Radioplek plek);
}

/// Deze machine haalt zelf: de pc, of een losse installatie zonder koppeling.
class EigenRadiobron implements Radiobron {
  EigenRadiobron({required this.downloads, required this.soulseek, required this.library});

  final DownloadManager downloads;
  final SoulseekService soulseek;
  final LibraryStore library;

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
  Future<Track?> haal(Radioplek plek) async {
    final pad = await downloads.haalVoorRadio(
      artiest: plek.artiest,
      titel: plek.titel,
      seconden: plek.seconden,
      jaar: plek.jaar,
    );
    if (pad == null) return null;
    // Eén bestand erbij, en niet de hele muziekmap opnieuw lezen. Zie [LibraryStore.voegBestandToe]:
    // bij acht landingen per kwartier zou een volledige scan vrijwel permanent draaien, en dat merk
    // je precies terwijl je naar muziek luistert.
    return library.voegBestandToe(pad);
  }
}

/// De radio die vooruit meeloopt.
///
/// Houdt drie dingen bij elkaar: het PLAN (wat er zou moeten spelen), de SPEELRIJ (wat er werkelijk
/// kan klinken) en de haaltjes die onderweg zijn. Eén klok van vijf seconden plus een aanroep na elke
/// landing zijn genoeg om die drie gelijk te houden.
class RadioBesturing extends ChangeNotifier {
  RadioBesturing({required this.speler, required this.bron});

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

  Timer? _tik;
  int _sessie = 0;
  bool _loopt = false;

  bool get loopt => _loopt;

  /// Hoeveel er nog opgehaald wordt, en hoeveel er door deze radio binnengekomen is.
  int get onderweg => _plan.where((p) => p.stand == Haalstand.onderweg).length;
  int get gehaald => _plan.where((p) => p.doorRadio).length;

  /// Starten. Geeft null terug als het gelukt is, of de reden waarom niet — in gewone taal.
  Future<String?> start(List<Radioplek> nieuw, {String naam = ''}) async {
    if (nieuw.isEmpty) return 'Er viel niets te vinden om een radio van te maken.';

    // Eerst vragen of het KAN, en pas daarna de lopende radio verlaten. Andersom zou een radio die
    // niet blijkt te kunnen starten — Soulseek uit, pc niet bereikbaar — de radio die wél liep
    // meenemen in zijn val, en dan sta je met niets.
    final tegen = await bron.begin();
    if (tegen != null) return tegen;

    // De haak weg vóór `playRadio`: die verlaat de oude radio óók, en de haak zou dan de radio
    // afbreken die we net aan het starten zijn. En niet loslaten wat [Radiobron.begin] zojuist
    // genomen heeft — die leen is voor de radio die nu begint.
    _stop(laatLos: false);
    speler.bijRadioEinde = null;

    final sessie = ++_sessie;
    _plan = nieuw;
    this.naam = naam;
    _loopt = true;

    // De eerste ronde met de hand, want [PlayerStore.voegToeAanRadio] doet niets zolang er nog geen
    // radio loopt.
    final besluit = voorraadPlan([for (final p in nieuw) p.stand], vooruitNu: 0);
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

  /// Stoppen. Laat het plan staan, want daar valt straks nog over te vertellen.
  void stop() => _stop(laatLos: true);

  void _stop({required bool laatLos}) {
    _tik?.cancel();
    _tik = null;
    _sessie++; // alles wat nog onderweg is hoort nergens meer bij
    final liep = _loopt;
    _loopt = false;
    if (laatLos) bron.einde();
    if (liep) notifyListeners();
  }

  @override
  void dispose() {
    _tik?.cancel();
    bron.einde();
    super.dispose();
  }

  RadioItem _itemVan(Radioplek p) => RadioItem(artist: p.artiest, title: p.titel, local: p.eigen);

  /// Kijken wat er nu te doen valt, en het doen.
  void _pas(int sessie) {
    if (sessie != _sessie) return;
    final vooruit = speler.radioQueue.length - speler.radioIndex - 1;
    final besluit = voorraadPlan(
      [for (final p in _plan) p.stand],
      vooruitNu: vooruit < 0 ? 0 : vooruit,
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
  }

  Future<void> _haal(int sessie, Radioplek p) async {
    Track? t;
    try {
      t = await bron.haal(p);
    } catch (_) {
      t = null;
    }
    if (sessie != _sessie) return; // een andere radio; deze landing hoort daar niet bij
    if (t == null) {
      // Geen foutmelding en geen gat: deze plek slaat over en het plan schuift door. Een radio die
      // bij elke peer die niet thuis geeft iets op het scherm zet, is onbruikbaar.
      p.stand = Haalstand.mislukt;
    } else {
      p.eigen = t;
      p.doorRadio = true;
      p.stand = Haalstand.klaar;
    }
    notifyListeners();
    _pas(sessie);
  }
}
