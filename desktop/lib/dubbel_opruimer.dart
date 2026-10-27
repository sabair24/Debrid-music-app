/// `_dubbel` opruimen: wat er langer dan [kDubbelBewaarDagen] dagen ligt, gaat naar de prullenbak.
///
/// Saber, 27-10-2026, bij de blijvende jacht: "Na 30 dagen naar prullenbak". In `_dubbel` belandt wat verloor — je eigen
/// vorige kopie als een betere hem verving, een twijfelkopie die je niet koos, wat "Opruimen" dubbel vond — en niets
/// ruimde het op: gemeten 20 GB, 338 bestanden, 163 erbij in een week.
///
/// **Geteld vanaf het moment dat de app het bestand daar voor het eerst ziet, niet op de datum van het bestand.** Een
/// verplaatst bestand houdt zijn oude datum: je kopie van 2019 die gisteren opzij ging, zou op de bestandsdatum meteen
/// weg zijn. Daarom onthoudt [DubbelGeheugen] per bestand (pad en grootte) wanneer het voor het eerst gezien werd; wat
/// er al lag toen dit begon, telt vanaf die eerste ronde.
///
/// **Naar de prullenbak, nooit definitief** ([naarPrullenbak]): lukt dat niet, dan blijft het staan.
library;

import 'dart:convert';
import 'dart:io';

/// Zo lang blijft iets in `_dubbel`, vanaf het moment dat de app het daar voor het eerst zag.
const kDubbelBewaarDagen = 30;

/// Zoveel bestanden hoogstens per keer naar de prullenbak: één PowerShell per bundel.
const kDubbelBundel = 50;

/// Wanneer elk bestand in `_dubbel` voor het eerst gezien werd, in `dubbel_gezien.json`.
class DubbelGeheugen {
  DubbelGeheugen(this._pad);
  final String _pad;
  final Map<String, int> _gezien = {};

  static String sleutel(String relatief, int grootte) => '${relatief.replaceAll('\\', '/').toLowerCase()}|$grootte';

  int? gezienOp(String sleutel) => _gezien[sleutel];
  int get aantal => _gezien.length;

  /// Het bestand is weg (naar de prullenbak).
  void vergeet(String relatief, int grootte) => _gezien.remove(sleutel(relatief, grootte));

  Future<void> laad() async {
    try {
      final f = File(_pad);
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      for (final e in j.entries) {
        if (e.value is num) _gezien['${e.key}'] = (e.value as num).toInt();
      }
    } catch (_) {/* een kapot geheugen begint opnieuw: dan telt alles vanaf nu, en gaat er niets te vroeg weg */}
  }

  Future<void> bewaar() async {
    try {
      final tmp = File('$_pad.tmp');
      await tmp.writeAsString(jsonEncode(_gezien));
      await tmp.rename(_pad);
    } catch (_) {/* volgende keer opnieuw */}
  }

  /// Eén ronde over [bestanden] (relatief pad → grootte) op [nuMs]: nieuwe krijgen [nuMs], verdwenen vallen weg. Geeft
  /// terug wat ouder is dan [kDubbelBewaarDagen] dagen.
  List<String> ronde(Map<String, int> bestanden, int nuMs) {
    final nu = <String>{};
    final oud = <String>[];
    for (final e in bestanden.entries) {
      final k = sleutel(e.key, e.value);
      nu.add(k);
      final op = _gezien.putIfAbsent(k, () => nuMs);
      if (nuMs - op >= const Duration(days: kDubbelBewaarDagen).inMilliseconds) oud.add(e.key);
    }
    _gezien.removeWhere((k, _) => !nu.contains(k));
    return oud;
  }
}

/// Eén opruimronde voor de map [map]: alle bestanden erin (ook in submappen), naar de prullenbak wat oud genoeg is.
/// [prullenbak] geeft de paden terug die echt weg zijn ([naarPrullenbak], of een nep in een toets). Geeft terug hoeveel
/// bestanden en bytes er weggingen.
Future<({int bestanden, int bytes})> ruimDubbelOp({
  required Directory map,
  required DubbelGeheugen geheugen,
  required Future<Set<String>> Function(List<String> paden) prullenbak,
  DateTime? nu,
}) async {
  if (!await map.exists()) return (bestanden: 0, bytes: 0);
  final sep = Platform.pathSeparator;
  final wortel = map.path.endsWith(sep) ? map.path : '${map.path}$sep';
  final groottes = <String, int>{};
  await for (final e in map.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    try {
      groottes[e.path.substring(wortel.length)] = await e.length();
    } catch (_) {/* net weg */}
  }
  final oud = geheugen.ronde(groottes, (nu ?? DateTime.now()).millisecondsSinceEpoch);
  var weg = 0, bytes = 0;
  for (var i = 0; i < oud.length; i += kDubbelBundel) {
    final bundel = [for (final r in oud.skip(i).take(kDubbelBundel)) '$wortel$r'];
    final gelukt = await prullenbak(bundel);
    for (final p in gelukt) {
      if (!p.startsWith(wortel)) continue;
      final r = p.substring(wortel.length);
      weg++;
      bytes += groottes[r] ?? 0;
      geheugen.vergeet(r, groottes[r] ?? 0);
    }
  }
  await geheugen.bewaar();
  return (bestanden: weg, bytes: bytes);
}
