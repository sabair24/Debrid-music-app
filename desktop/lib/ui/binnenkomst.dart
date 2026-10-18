/// Wat er gebeurt op het moment dat er iets verschijnt.
///
/// **Waarom dit bestaat.** De app zet inhoud neer alsof hij er altijd al stond: het ene beeld is het
/// scherm leeg, het volgende staat er een raster van veertig hoezen. Er is geen moment waarop je ziet
/// dat er iets kwam, en dat is een van de dingen die "plat" oplevert — er beweegt niets, dus je hebt
/// geen idee of de app iets deed of dat het er gewoon stond.
///
/// **En waarom het zo weinig doet.** Acht punten omhoog en een vervaging, in [kOvergang]. Meer is op
/// een lijst van veertig regels geen sfeer maar een wachttijd, en op een televisie kost het beelden.
///
/// # De valkuil die dit bestand oplost
///
/// Een lijst bouwt zijn regels pas als je ze nadert. Zet je een binnenkomst-animatie op elke regel,
/// dan animeert elke regel die je tijdens het SCROLLEN tegenkomt — de lijst komt dan permanent van
/// onderen aanzweven terwijl je erdoorheen veegt, wat er kapot uitziet en op elk beeld werk kost.
///
/// Vandaar [BinnenkomstGroep]: die onthoudt wanneer een scherm verscheen. Regels die binnen dat
/// venster gebouwd worden animeren; alles wat daarna komt — en dat is alles wat je zelf in beeld
/// scrollt — verschijnt gewoon. Geen tijdklok per regel, één per scherm.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../tv.dart';
import 'maten.dart';

/// Hoe lang na het verschijnen van een scherm er nog geanimeerd wordt.
///
/// Ruim genoeg voor wat er in het eerste beeld staat plus het trapje eronder, en kort genoeg dat
/// niemand er tijdens het scrollen nog in valt.
const Duration kBinnenkomstVenster = Duration(milliseconds: 700);

/// Hoeveel later elke volgende regel binnenkomt.
///
/// Klein, en met een dak erop: bij veertig zichtbare tegels zou 40 × 30 ms betekenen dat de laatste
/// pas na ruim een seconde staat, en dan wacht je op een animatie in plaats van dat je hem opmerkt.
///
/// Sinds 18-10-2026 12 ms en niet 26: Saber koos "tegels één keer gespreid binnen, hooguit 250 ms" —
/// het hele trapje plus de laatste beweging ([kBinnenkomstDuur]) blijft daaronder.
const Duration kTrapje = Duration(milliseconds: 12);

/// Hoe lang één tegel over zijn stukje omhoog doet.
const Duration kBinnenkomstDuur = Duration(milliseconds: 150);

/// Na hoeveel regels het trapje ophoudt met oplopen.
const int kTrapjeDak = 8;

/// Onthoudt wanneer dit scherm verscheen.
///
/// Zet hem om de lijst of het raster heen. Zonder deze widget doet [Binnenkomst] niets — dat is met
/// opzet: een regel die niet weet of hij bij het openen van een scherm hoort of tijdens het scrollen
/// gebouwd wordt, hoort niet te animeren.
class BinnenkomstGroep extends StatefulWidget {
  const BinnenkomstGroep({super.key, required this.child});

  final Widget child;

  @override
  State<BinnenkomstGroep> createState() => _BinnenkomstGroepState();

  /// Mag er nu nog geanimeerd worden? Onwaar als er geen groep boven je staat.
  static bool magNog(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Groep>()?.poort.open ?? false;
}

/// Staat het venster nog open?
///
/// **Een object met een veld, en geen `Stopwatch`.** Een stopwatch loopt op de echte klok, en een
/// widgettoets draait op een nagebootste — dan zou "het venster is voorbij" in een toets nooit
/// gebeuren en zou juist de belangrijkste bewering niet te maken zijn. Een `Timer` wordt wél
/// nagebootst.
///
/// En een object en geen `bool` in de `State`: de waarde wordt in een `InheritedWidget` gedragen, en
/// die legt zijn velden vast bij het bouwen. Een verwijzing naar dít doosje blijft kloppen zonder dat
/// er ook maar iets hertekend hoeft te worden — wat het hele punt is, want hertekenen is precies het
/// werk dat hier vermeden moet worden.
class _Poort {
  bool open = true;
}

class _BinnenkomstGroepState extends State<BinnenkomstGroep> {
  final _poort = _Poort();
  Timer? _sluiter;

  @override
  void initState() {
    super.initState();
    _sluiter = Timer(kBinnenkomstVenster, () => _poort.open = false);
  }

  @override
  void dispose() {
    _sluiter?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Groep(poort: _poort, child: widget.child);
}

class _Groep extends InheritedWidget {
  const _Groep({required this.poort, required super.child});

  final _Poort poort;

  // Nooit: het doosje wisselt niet van identiteit, en de waarde erin wordt alleen bij het BOUWEN van
  // een regel afgelezen. Een melding zou elke regel opnieuw laten tekenen zodra het venster sluit.
  @override
  bool updateShouldNotify(_Groep oud) => false;
}

/// Laat zijn kind één keer binnenkomen: een klein stukje omhoog, en vanaf het eerste beeld zichtbaar.
///
/// [index] bepaalt hoeveel later hij begint dan zijn buren, zodat een rij niet als één blok
/// verschijnt maar als een rij.
class Binnenkomst extends StatefulWidget {
  const Binnenkomst({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<Binnenkomst> createState() => _BinnenkomstState();
}

class _BinnenkomstState extends State<Binnenkomst> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  CurvedAnimation? _curve;
  Animation<Offset>? _schuif;
  bool _beslist = false;

  /// Het trapje: wachten tot deze tegel aan de beurt is.
  ///
  /// Bewaard, en niet als losse `Future.delayed`. Zo'n future is niet af te zeggen, dus na het
  /// opruimen van de tegel bleef er een wekker lopen die straks in het niets afgaat. In de app viel
  /// dat niet op -- er staat een `mounted`-controle onder -- maar in een toets is het fataal: die
  /// eindigt met "Pending timers" en valt om. Precies daarop stond albumraster_ingebed_test.dart
  /// stuk, en omdat die toets niet in de bouwstraat stond bleef de bouw al die tijd groen.
  Timer? _wekker;

  /// Hier en niet na het eerste beeld, en zonder vervaging.
  ///
  /// Tot 17-10-2026 viel de beslissing in een terugroep NA het eerste beeld, met de vervaging op 0:
  /// het eerste beeld toonde de tegel vol, het tweede niets, en daarna vaagde hij in 260 ms in, met
  /// tot 208 ms trapje ervoor. Bij elke tabwissel een flits en een halve tel wachten op de hoezen,
  /// terwijl Saber vroeg om "direct tonen van alle covers". `didChangeDependencies` mag de groep wél
  /// lezen en loopt vóór de eerste `build`, dus het eerste beeld staat al in de beginstand; en de
  /// hoes is er vanaf dat beeld, hij schuift alleen nog een klein stukje op zijn plek.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_beslist) return;
    _beslist = true;
    // Op een televisie niets: daar staat de markering al voor "waar ben ik", en veertig tegels die
    // tegelijk bewegen kost beelden op een Tegra X1 — dezelfde afweging als bij de matglas-balk en
    // bij `paneelDecoratie`.
    if (isTv || !BinnenkomstGroep.magNog(context)) return;
    final c = AnimationController(vsync: this, duration: kBinnenkomstDuur);
    final curve = CurvedAnimation(parent: c, curve: Curves.easeOutCubic);
    _c = c;
    _curve = curve;
    // Als BREUK van de eigen hoogte en niet in punten: een tegel van 180 komt zo een stukje
    // verder van beneden dan een regel van 42, en dat leest natuurlijker dan wanneer allebei
    // exact evenveel bewegen.
    _schuif = Tween(begin: const Offset(0, .05), end: Offset.zero).animate(curve);
    final wacht = kTrapje * (widget.index < kTrapjeDak ? widget.index : kTrapjeDak);
    _wekker = Timer(wacht, () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    // De wekker eerst: die zou anders na het opruimen nog afgaan.
    _wekker?.cancel();
    // En de curve vóór de controller: die hangt eraan.
    _curve?.dispose();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schuif = _schuif;
    // Geen animatie: gewoon zichtbaar. Dit is het pad voor alles wat je zelf in beeld scrollt, en
    // het kost precies niets — geen controller, geen laag, geen extra widget.
    if (schuif == null) return widget.child;
    // Alleen schuiven: een `SlideTransition` is een verschuiving bij het tekenen, geen laag.
    return SlideTransition(position: schuif, child: widget.child);
  }
}
