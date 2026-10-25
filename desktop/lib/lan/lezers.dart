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

/// Per pad hoeveel lezingen er lopen, en wanneer de laatste ophield — per lezer ([wie]: het adres van het toestel).
/// Paden zonder onderscheid in hoofdletters of schuine strepen, zoals Windows ze ziet.
///
/// **Per lezer** (25-10-2026): Saber luisterde op een toestel met A/B naar Rockin' en koos daar "Deze houden". Dat
/// toestel las het nummer zelf, dus bleef het tien minuten "in gebruik" — en na elke mislukte poging opende het
/// het nummer opnieuw (stroom.log 21:12:50, 21:13:01, 21:13:34): houden lukte nooit. Wie vraagt, telt nu niet mee
/// ([leest] met `behalve`).
class Lezers {
  Lezers({DateTime Function()? klok}) : _klok = klok ?? DateTime.now;
  final DateTime Function() _klok;
  final Map<String, Map<String, int>> _nu = {};
  final Map<String, Map<String, DateTime>> _tot = {};

  static String _sleutel(String pad) => pad.replaceAll('\\', '/').toLowerCase();

  void begin(String pad, {String wie = ''}) =>
      (_nu[_sleutel(pad)] ??= {}).update(wie, (n) => n + 1, ifAbsent: () => 1);

  void einde(String pad, {String wie = ''}) {
    final k = _sleutel(pad);
    final per = _nu[k];
    if (per != null) {
      final over = (per[wie] ?? 1) - 1;
      if (over <= 0) {
        per.remove(wie);
      } else {
        per[wie] = over;
      }
      if (per.isEmpty) _nu.remove(k);
    }
    (_tot[k] ??= {})[wie] = _klok();
    if (_tot.length > 2000) {
      final grens = _klok().subtract(kNaLezen);
      _tot.removeWhere((_, m) => m.values.every((t) => t.isBefore(grens)));
    }
  }

  /// Leest iemand [pad] nu, of deed die dat in de laatste [kNaLezen]? [behalve]: wat die lezer leest, telt niet.
  bool leest(String pad, {String? behalve}) {
    final k = _sleutel(pad);
    if ((_nu[k] ?? const {}).entries.any((e) => e.key != behalve && e.value > 0)) return true;
    final nu = _klok();
    return (_tot[k] ?? const {}).entries.any((e) => e.key != behalve && nu.difference(e.value) < kNaLezen);
  }

  /// De paden die [leest] nu noemt (in de vorm van [_sleutel]: kleine letters, voorwaartse strepen).
  Iterable<String> get inGebruik {
    final grens = _klok().subtract(kNaLezen);
    return {
      for (final e in _nu.entries) if (e.value.values.any((n) => n > 0)) e.key,
      for (final e in _tot.entries) if (e.value.values.any((t) => t.isAfter(grens))) e.key,
    };
  }

  /// Is [pad] een van [paden]? Voor de huidige nummers van de zones.
  static bool eenVan(String pad, Iterable<String> paden) {
    final k = _sleutel(pad);
    return paden.any((p) => _sleutel(p) == k);
  }
}
