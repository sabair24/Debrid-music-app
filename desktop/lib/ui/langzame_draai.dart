/// Een draaiing die op een snel scherm niet elke schermtik om een nieuw beeld vraagt — gelijkmatig.
///
/// **Gemeten op 05-10-2026, op Sabers S26 aan de kabel.** "Now playing" met een spelende plaat
/// tekende 14.403 beelden in twee minuten — 120 per seconde, onafgebroken — terwijl de cd één keer
/// per NEGEN seconden ronddraait: 0,3 graad per beeld, beelden die vrijwel gelijk zijn. De
/// tekendraad van de app nam 31 % van een kern, en de batterij ging van +0,33 A (opladen, gepauzeerd)
/// naar −0,41 tot −0,86 A — leeglopen ondanks de lader — en van 29 naar 36 °C. Saber merkte het als
/// haperen: het notificatiescherm en het draaien naar liggend moesten de grafische chip delen met
/// een app die hem vol hield.
///
/// Een `AnimationController` vraagt ELK schermbeeld aan, en op een scherm van 120 Hz is dat 120 keer
/// per seconde; Flutter heeft geen knop om één animatie trager te laten tikken. Dit doet het zelf:
/// één tik, dan de [Ticker] uit en een korte [Timer] tot de volgende. De tik blijft op het
/// schermritme vallen (geen schokken), en als de app niet zichtbaar is of de pagina erachter ligt,
/// komt er geen tik — een [Ticker] tikt dan niet, en de [Timer] zet hem alleen maar weer klaar.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

class LangzameDraai extends ChangeNotifier {
  LangzameDraai(TickerProvider vsync,
      {required this.omwenteling, this.maxBeeldenPerSeconde = 60, double Function()? schermHz})
      : _schermHz = schermHz ?? _verversingVanHetScherm {
    _ticker = vsync.createTicker(_tik);
  }

  /// Hoelang één volle draai duurt.
  final Duration omwenteling;

  /// Hoe vaak er hooguit om een nieuw beeld gevraagd wordt. Het werkelijke ritme is een HEEL aantal
  /// schermtikken — zie [tikkenPerBeeld] — en dus nooit om en om kort en lang.
  final int maxBeeldenPerSeconde;

  /// Hoe vaak het scherm ververst. Op de S26 120 Hz.
  final double Function() _schermHz;

  static double _verversingVanHetScherm() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final hz = views.isEmpty ? 0.0 : views.first.display.refreshRate;
    return hz >= 24 ? hz : 60;
  }

  late final Ticker _ticker;
  Timer? _wacht;
  /// Het schermbeeld van de vorige tik (`currentFrameTimeStamp`), of null vlak na [start].
  Duration? _vorige;
  double _waarde = 0;
  bool _loopt = false;
  bool _weg = false;

  /// De stand in omwentelingen, van 0 tot 1 — zoals [AnimationController.value] bij `repeat()`.
  double get value => _waarde;

  bool get isAnimating => _loopt;

  /// Om de hoeveel schermtikken de plaat een nieuw beeld krijgt: het kleinste hele aantal waarmee
  /// het onder [maxBeeldenPerSeconde] blijft.
  ///
  /// **Een heel aantal, en dat is het punt.** Saber, 05-10-2026: *"meet dan ook eens op pc de now
  /// playing screen. ik heb een refresh rate beeld van msi die tot 144ghz gaat"*. Met een vast doel
  /// van 60 per seconde valt dat op 144 Hz om en om op 2 en 3 schermtikken (13,9 en 20,8 ms) — het
  /// fps-logboek van de pc gaf 49 tot 53 per seconde, af en toe 80. Nu: 120 Hz → elke 2e (60/s),
  /// 144 Hz → elke 2e (72/s), 90 en 60 Hz → elke tik. Op de pc staat de grens zo hoog dat het altijd
  /// elke tik is: daar kost een beeld 2 ms en is er geen batterij.
  int get tikkenPerBeeld {
    final k = (_schermHz() / maxBeeldenPerSeconde).floor();
    return k < 1 ? 1 : k;
  }

  /// Hoe lang er na een tik gewacht wordt voor de [Ticker] weer aan gaat.
  ///
  /// **Een halve schermtik vóór het gewenste moment**, zodat de volgende tik precies op het juiste
  /// schermbeeld valt. In 3.9.441 stond hier een vaste marge van 4 ms, en op het toestel gemeten
  /// kwamen de beelden daardoor om en om na 8, 29, 33 en 42 ms — 42 per seconde, maar schokkerig.
  /// Saber: *"de staande is nu de cd niet vloeiend"*. Met 60 per seconde op 120 Hz is het nu elke
  /// tweede schermtik, gelijkmatig 16,7 ms.
  Duration get _tussen {
    final tik = 1e6 / _schermHz();
    final wacht = tik * tikkenPerBeeld - tik / 2;
    return Duration(microseconds: wacht < 0 ? 0 : wacht.round());
  }

  void start() {
    if (_loopt || _weg) return;
    _loopt = true;
    _vorige = null;
    if (!_ticker.isActive) _ticker.start();
  }

  void stop() {
    _loopt = false;
    _wacht?.cancel();
    _wacht = null;
    if (_ticker.isActive) _ticker.stop();
  }

  void _tik(Duration _) {
    if (!_loopt) {
      _ticker.stop();
      return;
    }
    // De tijd van het schermbeeld zelf, niet van een eigen klok: zo draait de plaat precies even ver
    // als er tijd tussen twee getoonde beelden zat.
    final nu = SchedulerBinding.instance.currentFrameTimeStamp;
    // Ten hoogste een halve seconde per tik: kwam de app net terug uit de achtergrond, dan springt
    // de plaat niet een eind verder alsof hij al die tijd doorgedraaid had.
    var stap = _vorige == null ? Duration.zero : nu - _vorige!;
    if (stap.isNegative) stap = Duration.zero;
    if (stap > const Duration(milliseconds: 500)) stap = const Duration(milliseconds: 500);
    _vorige = nu;
    _waarde = (_waarde + stap.inMicroseconds / omwenteling.inMicroseconds) % 1.0;
    notifyListeners();
    // Elke tik een beeld: dan gewoon de Ticker laten lopen, zoals een AnimationController — geen
    // klok ertussen die een tik kan missen.
    if (tikkenPerBeeld <= 1) return;
    _ticker.stop();
    _wacht = Timer(_tussen, () {
      _wacht = null;
      if (_loopt && !_weg && !_ticker.isActive) _ticker.start();
    });
  }

  @override
  void dispose() {
    _weg = true;
    stop();
    _ticker.dispose();
    super.dispose();
  }
}
