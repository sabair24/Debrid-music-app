/// Wat een zone doet met een opdracht van een ander toestel ("Speelt op: … ▾", Saber 21-10-2026). Op elk
/// toestel hetzelfde: de pc voor zijn eigen zone, een gsm of iPad voor de zijne.
///
/// Elke opdracht is een STAND en geen schakelaar (`play`, niet "wissel"): komen er twee tegelijk van twee
/// toestellen, dan wint de laatste, en iedereen ziet daarna dezelfde uitkomst. Een opdracht die al eens
/// aankwam (dezelfde `id`, bijvoorbeeld na een tweede lijn naar hetzelfde toestel), wordt niet nog eens
/// uitgevoerd.
library;

import 'models.dart';
import 'player.dart' show Rijbediening, Speelbron;
import 'zone_speler.dart' show herhaalUit;

/// Hoeveel opdracht-ids er onthouden worden om een dubbele te herkennen.
const kZoneOpdrachtGeheugen = 50;

/// De nummers uit [ids] die dit toestel kent, en waar [plek] daarin terechtkomt. Onbekende vallen weg;
/// valt het nummer op [plek] zelf weg, dan het eerstvolgende.
({List<Track> rij, int plek}) rijUitIds(List<String> ids, int plek, Track? Function(String id) nummer) {
  final rij = <Track>[];
  var nieuw = -1;
  for (var i = 0; i < ids.length; i++) {
    final t = nummer(ids[i]);
    if (t == null) continue;
    if (i >= plek && nieuw < 0) nieuw = rij.length;
    rij.add(t);
  }
  return (rij: rij, plek: nieuw < 0 ? 0 : nieuw);
}

/// Voert opdrachten uit op de speler van dit toestel.
class ZoneUitvoerder {
  ZoneUitvoerder({
    required this.speler,
    required this.rij,
    required this.nummer,
    this.radio,
    this.naUitvoeren,
    this.log,
  });

  final Speelbron speler;
  final Rijbediening rij;

  /// Een id van de pc als nummer hier.
  final Track? Function(String id) nummer;

  /// Een radio starten rond [artiest], met [zaad] (of het nummer [titel]) eerst.
  final Future<void> Function(String artiest, {Track? zaad, String? titel})? radio;

  /// Na elke opdracht: meld de nieuwe stand meteen, zodat wie bedient het ziet.
  final void Function()? naUitvoeren;
  final void Function(String)? log;

  final _gezien = <String>[];

  /// Voer [op] uit. Null als het lukte, anders waarom niet.
  Future<String?> voerUit(Map<String, dynamic> op) async {
    final id = '${op['id'] ?? ''}';
    if (id.isNotEmpty) {
      if (_gezien.contains(id)) return null;
      _gezien.add(id);
      if (_gezien.length > kZoneOpdrachtGeheugen) _gezien.removeAt(0);
    }
    final cmd = '${op['cmd'] ?? ''}';
    final ids = [for (final x in (op['ids'] as List? ?? const [])) '$x'];
    String? fout;
    try {
      switch (cmd) {
        case 'play':
          speler.speelAf();
        case 'pause':
          speler.pauzeer();
        case 'next':
          await speler.next();
        case 'previous':
          await speler.prev();
        case 'seek':
          speler.seek(Duration(milliseconds: (op['ms'] as num?)?.toInt() ?? 0));
        case 'shuffle':
          speler.zetShuffle(op['aan'] == true);
        case 'repeat':
          speler.zetHerhaal(herhaalUit('${op['stand'] ?? 'off'}'));
        case 'volume':
          speler.setVolume(((op['waarde'] as num?) ?? 100).toDouble());
        case 'jump':
          await speler.springNaar((op['plek'] as num?)?.toInt() ?? 0);
        case 'speel':
          final r = rijUitIds(ids, (op['plek'] as num?)?.toInt() ?? 0, nummer);
          if (r.rij.isEmpty) {
            fout = 'Die nummers staan hier niet in de bibliotheek';
          } else if (op['shuffle'] == true) {
            await rij.shuffleAll(r.rij);
          } else {
            await rij.playQueue(r.rij, r.plek);
          }
        case 'nu':
          final t = nummer('${op['id'] ?? ''}');
          if (t == null) {
            fout = 'Dat nummer staat hier niet in de bibliotheek';
          } else {
            await rij.speelNuMetRest(t);
          }
        case 'hierna' || 'achteraan':
          final ts = [for (final i in ids) if (nummer(i) case final t?) t];
          if (ts.isEmpty) {
            fout = 'Die nummers staan hier niet in de bibliotheek';
          } else if (cmd == 'hierna') {
            rij.speelHierna(ts);
          } else {
            rij.zetAchteraan(ts);
          }
        case 'radio':
          final artiest = '${op['artiest'] ?? ''}'.trim();
          final r = radio;
          if (artiest.isEmpty || r == null) {
            fout = 'Hier kan geen radio starten';
          } else {
            final zaad = op['zaad'] == null ? null : nummer('${op['zaad']}');
            final titel = '${op['titel'] ?? ''}'.trim();
            await r(artiest, zaad: zaad, titel: titel.isEmpty ? null : titel);
          }
        default:
          fout = 'Onbekende opdracht "$cmd"';
      }
    } catch (e) {
      fout = 'Mislukt: $e';
    }
    log?.call('opdracht $cmd${fout == null ? '' : ' — $fout'}  (van ${op['van'] ?? '?'})');
    naUitvoeren?.call();
    return fout;
  }
}
