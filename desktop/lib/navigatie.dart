/// De navigatie die blijft staan.
///
/// **Waarom dit bestaat.** De secties van deze app zijn geen routes maar een getal (`_view` in
/// `_HomeShellState`), en alle navigatie-oppervlakken — de onderbalk op een telefoon, de pillen op
/// een pc, de rail op een tv — hangen aan de ene `Scaffold` van de schil. Elke pagina die je opende
/// werd echter op de HOOFDnavigator gezet met een eigen `Scaffold`, en die legde zich over de hele
/// schil heen: balken inbegrepen. Open een album en de navigatie was weg; terug naar Start kon
/// alleen nog met de terugknop, en die is onzichtbaar.
///
/// Hier staat de navigator die BINNEN de schil leeft. Pagina's komen daarmee niet meer óver de schil
/// maar erin, en dan blijft op elk toestel staan waar dat toestel mee navigeert — zonder dat tien
/// pagina's afzonderlijk een balk moeten nabouwen.
///
/// Dit bestand is met opzet vrij van de rest van de app: geen stores, geen `AlbumSort`, geen
/// providers. Daardoor is het te toetsen zonder de veertien providers en de libmpv die in een
/// toetsrun niet bestaan — zie `test/terug_test.dart` en `test/binnen_navigator_test.dart`.
library;

import 'package:flutter/material.dart';

/// De navigator binnen de schil. De chrome staat erbuiten en blijft dus staan.
///
/// Een globale sleutel en geen provider, om dezelfde reden als `appNavigator`: een menu of een blad
/// dat op de hoofdnavigator geopend is, heeft geen `BuildContext` meer die hier langskomt.
final binnenNav = GlobalKey<NavigatorState>();

/// De route van een gewone pagina. Eén vorm, zodat ze allemaal hetzelfde in- en uitschuiven.
MaterialPageRoute<T> paginaRoute<T>(WidgetBuilder bouw) => MaterialPageRoute<T>(builder: bouw);

/// Open een pagina die de navigatie moet laten staan.
///
/// De terugval op `Navigator.of(c)` is geen beleefdheid: het koppelscherm en het aanmeldscherm
/// draaien zónder schil, en een toets ook. Zonder die terugval zou daar niets meer opengaan.
Future<T?> openPagina<T>(BuildContext c, WidgetBuilder bouw) =>
    (binnenNav.currentState ?? Navigator.of(c)).push<T>(paginaRoute<T>(bouw));

/// Zoals [openPagina], maar met een navigator die eerder is vastgelegd in plaats van een context.
///
/// Nodig waar het menu al dicht is tegen de tijd dat er iets opengaat: dan is de `BuildContext` van
/// de regel waarop je tikte dood, en is een vooraf vastgelegde `NavigatorState` het enige wat er nog
/// van over is.
///
/// **En daarom gaat er soms eerst iets dicht.** Zo'n menu kan geopend zijn vanaf een laag BOVEN de
/// schil: de wachtrij als blad, of het menu op "nu speelt". De pagina hoort binnen de schil te
/// landen — anders staat hij er zonder balken bij — maar dan komt hij ónder die laag terecht, en dan
/// lijkt het alsof je tik niets deed. Ligt [vanaf] dus buiten de binnennavigator en heeft hij iets te
/// sluiten, dan gaat dat eerst dicht.
///
/// Een gewone nummerregel binnen een sectie legt de binnennavigator zelf vast; daar wordt niets
/// gesloten, en dat is precies goed — je wilt de albumpagina waar je op stond niet kwijt.
Future<T?> openOp<T>(NavigatorState vanaf, WidgetBuilder bouw) {
  final binnen = binnenNav.currentState;
  if (binnen != null && vanaf != binnen && vanaf.canPop()) vanaf.pop();
  return (binnen ?? vanaf).push<T>(paginaRoute<T>(bouw));
}

/// Wat de terugknop hoort te doen.
///
/// Zuiver, en dat is het punt. Zowel `canPop` als de afhandelaar van de `PopScope` leidt hieruit af,
/// zodat "de app sluit af terwijl er een album openstaat" een gezakte toets is in plaats van iets
/// wat je op het toestel ontdekt.
enum TerugActie {
  /// Er ligt een pagina over de sectie heen; die gaat eerst dicht.
  paginaSluiten,

  /// Geen pagina meer, maar je staat niet op Start. Dan naar Start.
  naarStart,

  /// Op Start, niets meer eroverheen. Pas dan mag de app dicht.
  appVerlaten,
}

/// De sectie die "thuis" is. Zie `NavSections.items` — daar is 5 de Start-sectie.
const int startSectie = 5;

/// Drie lagen, één knop.
///
/// Op een afstandsbediening is TERUG de knop die je constant gebruikt; hem meteen de app laten
/// verlaten voelde als een app die crasht. Maar een app waar je niet uit komt is de andere helft van
/// diezelfde fout — vandaar dat de laatste laag wél afsluit.
TerugActie terugVanaf({required bool paginaOpen, required int sectie}) => paginaOpen
    ? TerugActie.paginaSluiten
    : sectie != startSectie
        ? TerugActie.naarStart
        : TerugActie.appVerlaten;

/// Houdt bij of de binnenste stapel nog iets te sluiten heeft.
///
/// **Waarom een observer en geen `canPop()` in de bouw.** `PopScope` legt zijn `canPop` vast op het
/// moment dat hij gebouwd wordt. Een push in de binnennavigator hertekent de schil niet, dus die
/// waarde zou op Start `true` blijven staan — en dan verlaat de terugknop de app terwijl er een
/// albumpagina openstaat. Dat is de fout die anders meegaat naar het toestel.
///
/// Een `NavigationNotification` zou hetzelfde kunnen, maar die arriveert middenin een bouw- of
/// opmaakfase, en dan mag er niets hertekend worden. De terugroepen van een observer vallen daar
/// buiten.
class StapelDiepte extends NavigatorObserver {
  StapelDiepte(this.kanTerug);

  /// Waar of de binnenste stapel nog een route boven de wortel heeft.
  final ValueNotifier<bool> kanTerug;

  void _meet() {
    final n = navigator;
    // Een `ValueNotifier` meldt niets bij een gelijke waarde, en dat is hier geen detail: `didPush`
    // van de WORTELroute valt tijdens de bouw van de navigator, en een melding daar zou een
    // hertekening tijdens het bouwen aanvragen. De wortel kan niet terug, de beginwaarde is onwaar,
    // dus die eerste meting is stil.
    kanTerug.value = n != null && n.canPop();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _meet();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _meet();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _meet();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _meet();
}

/// De navigator binnen de schil, met [wortel] als enige route eronder.
///
/// [wortel] hoort een widget te zijn die zijn gegevens uit een `InheritedWidget` boven deze
/// navigator haalt, en niet uit constructorvelden. De reden staat in de klasse zelf: de pagina van
/// een route wordt één keer gebouwd en bewaard, dus een nieuwe [wortel]-instantie bereikt het scherm
/// niet. Een `InheritedWidget` werkt daar wél doorheen, want die dirtyt zijn afhankelijken
/// rechtstreeks.
class BinnenNavigator extends StatefulWidget {
  const BinnenNavigator({
    super.key,
    required this.navigatorKey,
    required this.kanTerug,
    required this.wortel,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final ValueNotifier<bool> kanTerug;
  final Widget wortel;

  @override
  State<BinnenNavigator> createState() => _BinnenNavigatorState();
}

class _BinnenNavigatorState extends State<BinnenNavigator> {
  late final StapelDiepte _diepte = StapelDiepte(widget.kanTerug);

  @override
  Widget build(BuildContext context) => Navigator(
        key: widget.navigatorKey,
        observers: [_diepte],
        // Geen overgang voor de wortel: de sectiewissel heeft zijn eigen overvloeier, en twee
        // animaties over elkaar leest als een aarzeling.
        onGenerateRoute: (instellingen) => PageRouteBuilder<void>(
          settings: instellingen,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => widget.wortel,
        ),
      );
}
