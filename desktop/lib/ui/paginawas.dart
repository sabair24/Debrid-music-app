import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../navigatie.dart';

/// De kleur van de plaat die je NU bekijkt, één laag hoger dan de pagina zelf.
///
/// **Waarom dit nodig is.** De was — de tint die uit de hoes komt en achter de albumpagina ligt —
/// werd door die pagina zelf getekend. Maar de bovenbalk met de secties staat BUITEN de navigator
/// waar die pagina in leeft (zie de opbouw in `main.dart`: bovenbalk, dan `Expanded`, dan pas
/// `BinnenNavigator`). Een kind kan niet achter zijn ouder schilderen, dus de kleur hield op waar de
/// balk begon, met een harde rand als resultaat.
///
/// Door de kleur hier neer te leggen kan de SCHIL hem over de volle hoogte tekenen — achter de
/// bovenbalk langs tot aan de schermrand — terwijl die balk van matglas blijft en de kleur er dus
/// doorheen laat zien.
///
/// Alleen de kleur reist, niet het verloop. Het recept staat in `ui/vlak.dart` en hoort op één plek
/// te blijven; dit is niet meer dan "welke plaat kijk je aan".
///
/// **En de plaat die je aankijkt, is de plaat die BOVENOP ligt.** Niet de laatste die iets zei: een
/// pagina die je vanaf een plaat opent, legt zich eroverheen zonder hem op te ruimen. Tot 11-09-2026
/// bleef de kleur dan gewoon staan, en omdat een gewone pagina onder de zwevende balk begint,
/// kleurde hij de doorzichtige strook daarboven — een rode band boven de stijlpagina die je vanaf
/// Back To Bedlam opende (Saber: "fix de strook"). Wie een kleur zet, doet dat daarom via
/// [WasHouder], en die laat los zolang er iets op zijn pagina ligt.
class PaginaWas extends ChangeNotifier {
  int? _kleur;

  /// Wie de kleur gezet heeft: een pagina, en niet een tint. Zie [wis].
  Object? _van;

  /// De hoeskleur van de pagina die bovenop ligt, of null als er geen pagina is die er een heeft.
  int? get kleur => _kleur;

  /// Zet de kleur, namens [van].
  void toon(int? nieuw, {required Object van}) {
    _van = van;
    if (nieuw == _kleur) return;
    _kleur = nieuw;
    notifyListeners();
  }

  /// Wissen, maar alleen als het nog steeds ván [van] is.
  ///
  /// Dat onderscheid is de hele reden dat dit een aparte methode is. Ga je van album A naar album B,
  /// dan zet B zijn kleur vóórdat A wordt opgeruimd — Flutter bouwt de nieuwe route op terwijl de
  /// oude nog leeft. Zou A bij het opruimen onvoorwaardelijk wissen, dan haalde hij de kleur van B
  /// weg en keek je tegen een grijze balk aan op een pagina die er wél een heeft.
  ///
  /// **Van wie, en niet welke kleur.** Tot 11-09-2026 vergeleek dit de tint: "wis, als het nog deze
  /// kleur is". Twee platen met dezelfde hoes — een tweede persing die je vanaf de eerste opent —
  /// hebben dezelfde tint, en dan wiste de bovenste bij het sluiten die van de onderste.
  void wis(Object van) {
    if (!identical(van, _van)) return;
    _van = null;
    if (_kleur == null) return;
    _kleur = null;
    notifyListeners();
  }
}

/// Een pagina die de was zet — en hem loslaat zolang er een andere pagina op haar ligt.
///
/// Zie [PaginaWas] voor waarom. Via [BinnenNavigator.kijkerVan] hoort de pagina wanneer er iets op
/// haar komt en weer afgaat, en daarmee:
///
/// * **komt er een pagina op, dan trekt ze haar kleur in.** De was vloeit weg terwijl de nieuwe
///   pagina binnenschuift;
/// * **gaat die pagina weer af, dan zet ze hem terug.** Dat deed vroeger niemand: van plaat A naar
///   plaat B en terug, en A stond zonder kleur — B wiste de zijne, en A zette de hare nooit opnieuw;
/// * **een kleur die binnenkomt terwijl er iets op haar ligt, wacht.** De hoes wordt in een isolate
///   uitgerekend, en wie snel doorklikt is al verder voordat die klaar is;
/// * **gaat ze zelf dicht, dan laat ze los zodra ze begint te verdwijnen**, en niet pas als ze weg
///   is. "Naar Start" vanaf een pagina óp een plaat sluit ze allebei in één keer; dan kwam de plaat
///   even boven, en kleurde Start een overgang lang in haar tint.
///
/// Alleen PAGINA'S tellen, geen menu's: een menu legt zich over een plaat zonder dat je die verlaat,
/// en dan knipperde de kleur bij elk menu weg en terug.
///
/// Buiten de binnennavigator — het koppel- en aanmeldscherm draaien zonder schil — hoort ze niets, en
/// doet ze wat een pagina altijd deed: kleur zetten, en bij het opruimen wissen.
mixin WasHouder<T extends StatefulWidget> on State<T> implements RouteAware {
  PaginaWas? _paginaWas;
  RouteObserver<PageRoute<dynamic>>? _kijker;

  /// De kleur van deze pagina, ook als die nu niet te zien is.
  int? _wasKleur;

  /// Onwaar zolang er een andere pagina op deze ligt, en vanaf het moment dat ze zelf dichtgaat.
  bool _bovenop = true;

  /// De kleur van deze pagina. Ligt er iets op haar, dan wacht hij tot ze weer bovenop ligt.
  void zetWas(int? kleur) {
    _wasKleur = kleur;
    if (_bovenop) _paginaWas?.toon(kleur, van: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hier en niet in `dispose`: bij het opruimen mag er niet meer in de boom gekeken worden.
    _paginaWas = context.read<PaginaWas>();
    final route = ModalRoute.of(context);
    if (_kijker == null && route is PageRoute) {
      _kijker = BinnenNavigator.kijkerVan(context)?..subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _kijker?.unsubscribe(this);
    _paginaWas?.wis(this);
    super.dispose();
  }

  @override
  void didPushNext() {
    _bovenop = false;
    _paginaWas?.wis(this);
  }

  @override
  void didPopNext() {
    _bovenop = true;
    _paginaWas?.toon(_wasKleur, van: this);
  }

  @override
  void didPop() {
    _bovenop = false;
    _paginaWas?.wis(this);
  }

  /// Valt al bij het inschrijven, midden in de bouw — en daar mag niets anders gaan hertekenen.
  @override
  void didPush() {}
}
