import 'package:flutter/foundation.dart';

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
class PaginaWas extends ChangeNotifier {
  int? _kleur;

  /// De hoeskleur van de pagina die bovenop ligt, of null als er geen pagina is die er een heeft.
  int? get kleur => _kleur;

  void toon(int? nieuw) {
    if (nieuw == _kleur) return;
    _kleur = nieuw;
    notifyListeners();
  }

  /// Wissen, maar alleen als het nog steeds ván jou is.
  ///
  /// Dat onderscheid is de hele reden dat dit een aparte methode is. Ga je van album A naar album B,
  /// dan zet B zijn kleur vóórdat A wordt opgeruimd — Flutter bouwt de nieuwe route op terwijl de
  /// oude nog leeft. Zou A bij het opruimen onvoorwaardelijk wissen, dan haalde hij de kleur van B
  /// weg en keek je tegen een grijze balk aan op een pagina die er wél een heeft.
  void wis(int? vanMij) {
    if (_kleur == vanMij) toon(null);
  }
}
