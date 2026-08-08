import 'dart:async';

import 'package:flutter/foundation.dart';

import 'lan/state_store.dart';

/// De weg naar de gedeelde staat, één keer.
///
/// Favorieten en afspeellijsten wonen allebei in [LanStateStore] en worden allebei gewijzigd met
/// dezelfde ops. Op de pc gaan die rechtstreeks in de winkel; op een iPad of gsm staat die winkel
/// niet, en gaan dezelfde ops over de lijn naar `/api/state/ops` — het pad dat de andere toestellen
/// al gebruiken.
///
/// Deze klasse bestaat zodat er van dat onderscheid precies één kopie is. Twee klassen die elk hun
/// eigen weg naar dezelfde lijst kennen worden vroeg of laat twee lijsten die niet meer gelijk lopen,
/// en dat merk je pas op het toestel waar je níét zat.
abstract class GedeeldeOps extends ChangeNotifier {
  /// Op de pc: de echte winkel. Op een client: null, en dan loopt alles via [duwOps].
  LanStateStore? winkel;

  /// Op een client: de weg naar de pc.
  Future<void> Function(List<Map<String, dynamic>> ops)? duwOps;

  bool get isClient => winkel == null;

  int get nu => DateTime.now().millisecondsSinceEpoch;

  /// Pas [ops] toe. Op de pc meteen; op een client gaat het over de lijn.
  ///
  /// [vooruit] en [terug] zijn wat een client op het scherm doet vóór en na een weigering. Een knop
  /// die wacht tot de pc geantwoord heeft leest als een knop die niets deed — en dan drukt iemand
  /// nog eens. Maar een scherm dat iets toont wat nergens bewaard is, is erger: dat ontdek je pas op
  /// een ander toestel.
  Future<void> pasToe(
    List<Map<String, dynamic>> ops, {
    VoidCallback? vooruit,
    VoidCallback? terug,
  }) async {
    if (!isClient) {
      winkel!.applyOps(ops);
      notifyListeners();
      return;
    }
    vooruit?.call();
    notifyListeners();
    try {
      await duwOps?.call(ops);
    } catch (_) {
      terug?.call();
      notifyListeners();
      rethrow;
    }
  }
}
