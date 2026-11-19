// Iets wat vaak verandert, maar niet bij elke verandering weggeschreven hoeft te worden (19-11-2026).
//
// Saber, bij de wens voor slim shuffelen en een manuele radio: *"houdt rekening met performance, alles moet vlot
// gaan"*. De wachtrij schreef bij ELKE wijziging het hele `resume_queue.json` opnieuw (bij Shuffle alles 2000
// paden, 226 kB), ook bij elk nummer dat een ander toestel opende en dat hier naar achteren schoof. Met een
// slimme shuffle die onderweg voorstellen in de rij zet, wordt dat alleen maar vaker.
library;

import 'dart:async';

/// Doet [doe] hoogstens één keer per [rust]: de eerste [straks] zet een klok, wat er daarna binnen die tijd nog
/// bijkomt rijdt mee, en als de klok afgaat telt de stand van dat moment. [nu] doet het meteen en ruimt een
/// wachtende beurt op (bij het afsluiten).
class Naklok {
  Naklok(this.rust, this.doe);

  final Duration rust;
  final Future<void> Function() doe;

  Timer? _klok;

  /// Staat er een beurt klaar?
  bool get wacht => _klok != null;

  /// Straks doen; staat er al een beurt klaar, dan rijdt deze mee.
  void straks() {
    _klok ??= Timer(rust, () {
      _klok = null;
      unawaited(doe());
    });
  }

  /// Meteen doen, en een wachtende beurt vervalt.
  Future<void> nu() async {
    _klok?.cancel();
    _klok = null;
    await doe();
  }

  /// Een wachtende beurt laten vallen, zonder te doen.
  void stop() {
    _klok?.cancel();
    _klok = null;
  }
}
