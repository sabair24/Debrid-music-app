import 'dart:async';

/// Een wachtrij die er hoogstens [maxTegelijk] tegelijk laat lopen.
///
/// Bestaat omdat de opwaardeerjachten strikt één voor één liepen, en dat de staart van elk album
/// uitrekte. Gemeten op het Sade-album van 14:44: negen nummers binnen na twee minuten, en daarna
/// nog vijf minuten seriële jachten, met "er loopt al een jacht, 2 wachtend" in het logboek.
///
/// Apart bestand omdat dit het soort code is dat stil kapotgaat. Een teller die één keer niet zakt,
/// en de rij loopt nooit meer leeg — zonder foutmelding, zonder crash, gewoon een app die niets meer
/// opwaardeert. Dat hoort een test te bewaken en geen zorgvuldigheid.
class Werkrij {
  Werkrij(this.maxTegelijk) : assert(maxTegelijk > 0);

  final int maxTegelijk;
  final List<Future<void> Function()> _rij = [];
  int _lopend = 0;

  int get lopend => _lopend;
  int get wachtend => _rij.length;

  /// Zet werk in de rij en trek meteen aan als er plaats is.
  void voegToe(Future<void> Function() werk) {
    _rij.add(werk);
    unawaited(_trek());
  }

  /// Start hoogstens ÉÉN loper en keer terug. De teller regelt de rest.
  ///
  /// De hervatting staat in de `finally` en wordt bewust niet ge-await: dat zou de lopers aan elkaar
  /// rijgen en precies het serieel-zijn terugbrengen dat hier weg moest.
  ///
  /// Een werkstuk dat gooit mag de rij niet vergiftigen. Zou de teller dan blijven staan, dan zakt
  /// het aantal lopers bij elke fout met één tot er niets meer beweegt — het soort storing dat je pas
  /// dagen later merkt. Vandaar `finally` en niet `then`.
  Future<void> _trek() async {
    if (_lopend >= maxTegelijk || _rij.isEmpty) return;
    _lopend++;
    final werk = _rij.removeAt(0);
    try {
      await werk();
    } catch (_) {
      // De aanroeper logt zijn eigen fouten; hier telt alleen dat de rij blijft lopen.
    } finally {
      _lopend--;
      if (_rij.isNotEmpty) unawaited(_trek());
    }
  }
}
