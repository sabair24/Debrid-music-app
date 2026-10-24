// Wat een toestel of speaker nu van deze pc leest.
//
// Saber, 24-10-2026: "dit nummer die ik net downloadde … nu kan ik het niet spelen". De Mac begon "Mademoiselle chante
// le blues" (24/192, 151,5 MB) te streamen om 15:15:50 (stroom.log); om 15:15:58.965 schreef de hoesveger de hoes in
// datzelfde bestand (hoes_in_bestand.log), en de Mac gaf op: "Kan dit nummer niet openen — Failed to open". Een
// bestand dat herschreven of vervangen wordt, verschuift onder een speler die het half gelezen heeft. De vegers keken
// alleen naar wat op de pc zelf speelde.

/// Zo lang na de laatste lezing geldt een bestand nog als in gebruik: een toestel haalt een nummer vaak in een paar
/// seconden binnen en speelt het daarna minutenlang uit zijn buffer; spoelt het, dan vraagt het opnieuw.
const Duration kNaLezen = Duration(minutes: 10);

/// Per pad hoeveel lezingen er lopen, en wanneer de laatste ophield. Paden zonder onderscheid in hoofdletters of
/// schuine strepen, zoals Windows ze ziet.
class Lezers {
  Lezers({DateTime Function()? klok}) : _klok = klok ?? DateTime.now;
  final DateTime Function() _klok;
  final Map<String, int> _nu = {};
  final Map<String, DateTime> _tot = {};

  static String _sleutel(String pad) => pad.replaceAll('\\', '/').toLowerCase();

  void begin(String pad) => _nu.update(_sleutel(pad), (n) => n + 1, ifAbsent: () => 1);

  void einde(String pad) {
    final k = _sleutel(pad);
    final over = (_nu[k] ?? 1) - 1;
    if (over <= 0) {
      _nu.remove(k);
    } else {
      _nu[k] = over;
    }
    _tot[k] = _klok();
    if (_tot.length > 2000) {
      final grens = _klok().subtract(kNaLezen);
      _tot.removeWhere((_, t) => t.isBefore(grens));
    }
  }

  /// Leest iemand [pad] nu, of deed die dat in de laatste [kNaLezen]?
  bool leest(String pad) {
    final k = _sleutel(pad);
    if ((_nu[k] ?? 0) > 0) return true;
    final tot = _tot[k];
    return tot != null && _klok().difference(tot) < kNaLezen;
  }

  /// De paden die [leest] nu noemt (in de vorm van [_sleutel]: kleine letters, voorwaartse strepen).
  Iterable<String> get inGebruik {
    final grens = _klok().subtract(kNaLezen);
    return {..._nu.keys, for (final e in _tot.entries) if (e.value.isAfter(grens)) e.key};
  }

  /// Is [pad] een van [paden]? Voor de huidige nummers van de zones.
  static bool eenVan(String pad, Iterable<String> paden) {
    final k = _sleutel(pad);
    return paden.any((p) => _sleutel(p) == k);
  }
}
