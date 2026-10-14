/// Hoeveel duur werk één sleutel van buiten (47821) mag laten doen, per uur en per dag.
///
/// Stap 5.2 van "verbinden zoals Roon ARC" (plan 14-10-2026). Een gestolen gsm of een gelekte sleutel
/// kan via de deur naar buiten niets wat thuis niet ook kan, maar zonder grens wel heel veel ervan: de
/// AI-sleutel leegtrekken, de schijf volladen, de bibliotheek naar de prullenbak sturen of de pc een
/// nacht laten omzetten. Daarom hier een plafond, per sleutel, en alleen van buiten — thuis en via
/// Tailscale telt niets.
///
/// **Nooit op afspelen, hoezen of omzetten voor 5G.** Wat bij afspelen hoort, wordt nooit geweigerd:
/// raakt een sleutel het plafond voor omzetten of verkleinen, dan krijgt hij het origineel (groter,
/// maar het speelt). Alleen wat geen afspelen is — downloads, een radioplan van het model, iets naar
/// de prullenbak — krijgt een nee, met wat en tot wanneer.
///
/// Geijkt op de logboeken van de pc (14-10-2026), met ruime marge: hoogstens 72 geleverde downloads
/// in één uur (`downloads.log`), 86 nieuwe omzettingen in één uur (`stroom.log`, thuis en speakers
/// samen), 3 radiostarts in één uur (`radio.log`).
library;

/// Eén soort duur werk, met zijn plafond.
class Quotumsoort {
  const Quotumsoort(this.naam, {required this.perUur, required this.perDag, required this.wat});

  /// Voor het logboek.
  final String naam;
  final int perUur;
  final int perDag;

  /// Wat er geteld wordt, in de zin die het toestel te zien krijgt ("downloads starten").
  final String wat;
}

const kQuotumDownloads = Quotumsoort('downloads', perUur: 250, perDag: 1000, wat: 'downloads starten');
const kQuotumRadioplan = Quotumsoort('radioplan', perUur: 20, perDag: 60, wat: 'een radio uit een zin laten maken');
const kQuotumPrullenbak =
    Quotumsoort('prullenbak', perUur: 150, perDag: 500, wat: 'nummers naar de prullenbak op je pc sturen');
const kQuotumOmzetten = Quotumsoort('omzetten', perUur: 400, perDag: 2000, wat: 'nummers laten omzetten');
const kQuotumHoezen = Quotumsoort('hoezen', perUur: 3000, perDag: 10000, wat: 'hoezen laten verkleinen');

/// Het tellen zelf. Alleen in het geheugen: een herstart van de pc zet alles op nul, en dat kan wie
/// van buiten komt niet afdwingen.
class Quota {
  Quota({DateTime Function()? klok, this.maxSleutels = 200}) : _klok = klok ?? DateTime.now;

  final DateTime Function() _klok;

  /// Begrensd geheugen, zoals bij de remming: er zijn maar een handvol toestellen, en elke sleutel
  /// die hier komt is al geldig.
  final int maxSleutels;
  final _boekingen = <String, List<(DateTime, int)>>{};

  /// Boekt [aantal] keer [soort] voor [sleutel]. Null = mag, en is geboekt. Anders de zin voor het
  /// toestel: wat, hoeveel, en vanaf hoe laat het weer kan. Een weigering boekt niets.
  String? boek(String sleutel, Quotumsoort soort, [int aantal = 1]) {
    if (aantal <= 0) return null;
    // Meer in één keer dan er ooit in een uur past (een album van 300 nummers): wachten helpt niet.
    if (aantal > soort.perUur || aantal > soort.perDag) {
      return 'Van buitenaf kan dit toestel ${soort.perUur} per uur ${soort.wat}; dit zijn er $aantal. '
          'Doe het in delen, of thuis.';
    }
    final nu = _klok();
    final k = '${soort.naam}|$sleutel';
    final rij = _boekingen.remove(k) ?? <(DateTime, int)>[];
    rij.removeWhere((b) => nu.difference(b.$1) >= const Duration(days: 1));
    _boekingen[k] = rij; // achteraan: op volgorde van laatste gebruik
    while (_boekingen.length > maxSleutels) {
      _boekingen.remove(_boekingen.keys.first);
    }
    final uur = _weerVrij(rij, nu, const Duration(hours: 1), soort.perUur, aantal);
    final dag = _weerVrij(rij, nu, const Duration(days: 1), soort.perDag, aantal);
    if (uur == null && dag == null) {
      rij.add((nu, aantal));
      return null;
    }
    final perUur = uur != null;
    final tot = [uur, dag].whereType<DateTime>().reduce((a, b) => a.isAfter(b) ? a : b);
    final grens = perUur ? '${soort.perUur} per uur' : '${soort.perDag} per dag';
    return 'Van buitenaf kan dit toestel $grens ${soort.wat}. Weer mogelijk ${_wanneer(tot, nu)}.';
  }

  /// Hoeveel er in het laatste uur geboekt is. Voor de toetsen.
  int inLaatsteUur(String sleutel, Quotumsoort soort) {
    final nu = _klok();
    return [
      for (final b in _boekingen['${soort.naam}|$sleutel'] ?? const <(DateTime, int)>[])
        if (nu.difference(b.$1) < const Duration(hours: 1)) b.$2
    ].fold(0, (a, b) => a + b);
  }

  /// Null als [aantal] er binnen [venster] nog bij past; anders het moment waarop wel.
  static DateTime? _weerVrij(List<(DateTime, int)> rij, DateTime nu, Duration venster, int plafond, int aantal) {
    final binnen = [for (final b in rij) if (nu.difference(b.$1) < venster) b];
    var som = binnen.fold(0, (a, b) => a + b.$2);
    if (som + aantal <= plafond) return null;
    for (final b in binnen) {
      som -= b.$2;
      if (som + aantal <= plafond) return b.$1.add(venster);
    }
    return nu.add(venster);
  }

  static String _wanneer(DateTime vrij, DateTime nu) {
    // Naar boven afgerond: "om 14:32" terwijl het pas om 14:32:40 kan, is een minuut te vroeg.
    final tot = vrij.second > 0 || vrij.millisecond > 0 || vrij.microsecond > 0
        ? DateTime(vrij.year, vrij.month, vrij.day, vrij.hour, vrij.minute + 1)
        : vrij;
    final uu = tot.hour.toString().padLeft(2, '0');
    final mm = tot.minute.toString().padLeft(2, '0');
    final zelfdeDag = tot.year == nu.year && tot.month == nu.month && tot.day == nu.day;
    return zelfdeDag ? 'om $uu:$mm' : 'morgen om $uu:$mm';
  }
}
