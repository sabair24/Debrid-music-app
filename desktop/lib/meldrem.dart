/// Een stroom meldingen afremmen tot iets wat een scherm kan bijbenen.
///
/// **Waarom dit bestaat.** `DownloadManager` is één app-brede `ChangeNotifier` en op een telefoon
/// hangt de hele schil eraan — de la en de bovenbalk doen allebei een `context.watch` op de context
/// van de schil zelf. Elke gebeurtenis van elke lopende download meldde meteen: één bij de eerste
/// bytes, één per twee procent per bestand, één per peer die antwoordt. Met een paar downstreams
/// tegelijk is dat meerdere meldingen per seconde, en elke melding verklaart de hele schil vuil.
///
/// `PlayerStore` heeft precies deze rem al (zie `player.dart`, waar de positiestroom van mpv
/// teruggebracht wordt naar vier keer per seconde, met de uitleg dat elke watch anders hertekende).
/// Bij de downloads is hij nooit gekomen.
///
/// **Wat hier bewust NIET geremd wordt:** een eindtoestand. Klaar, mislukt en gestopt melden
/// rechtstreeks — die gebeuren één keer en je wil ze meteen zien. De rem is er voor voortgang, en
/// voortgang van tweehonderd milliseconden geleden is geen verkeerde informatie maar oude.
///
/// Apart bestand, want dit is het soort code dat stil kapotgaat: een tijdklok die nog afgaat nadat
/// alles opgeruimd is, of een vlag die blijft staan zodat er nooit meer iets gemeld wordt. Dat hoort
/// een toets te bewaken en geen zorgvuldigheid — zie [Werkrij], waar exact dezelfde afweging staat.
library;

import 'dart:async';

class Meldrem {
  Meldrem(this._meld, {this.tussenpoos = const Duration(milliseconds: 200)});

  /// Wat er gebeurt als de rem doorlaat. In de praktijk `notifyListeners`.
  final void Function() _meld;

  /// Hoogstens één melding per zoveel tijd.
  ///
  /// Tweehonderd milliseconden is vijf keer per seconde: ruim genoeg om een balk vloeiend te laten
  /// ogen (`player.dart` koos vier), en genoeg om het verschil te maken tussen "elk beeldje" en
  /// "af en toe".
  final Duration tussenpoos;

  Timer? _klok;
  bool _weg = false;

  /// Loopt er een melding te wachten? Alleen om te toetsen.
  bool get wacht => _klok != null;

  /// Vraag om een melding. De eerste vraag binnen een tussenpoos plant hem; de rest lift mee.
  void vraag() {
    if (_weg || _klok != null) return;
    _klok = Timer(tussenpoos, () {
      _klok = null;
      // De klok kan afgaan NADAT er opgeruimd is: dan is de melder weg en gooit hij. Dat is precies
      // de faalvorm waar dit bestand voor apart staat.
      if (_weg) return;
      _meld();
    });
  }

  /// Meteen melden, en een wachtende melding laten vervallen.
  ///
  /// Voor eindtoestanden: die mogen niet tweehonderd milliseconden achterlopen, en ze mogen ook niet
  /// direct gevolgd worden door een tweede melding die niets meer toevoegt.
  void nu() {
    _klok?.cancel();
    _klok = null;
    if (_weg) return;
    _meld();
  }

  /// Klaar. Een klok die hierna nog afgaat doet niets meer.
  void stop() {
    _weg = true;
    _klok?.cancel();
    _klok = null;
  }
}
