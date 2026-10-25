// Twijfelgevallen: een kopie die bewezen beter klinkt, maar waarvan de vingerafdruk twijfelt of het dezelfde opname is.
//
// Gemeten in de nacht van 24 op 25-10-2026 (scratchpad vingervergelijk.js, dezelfde som als `similarity()`): dezelfde
// plaat scoort soms ver onder de grens van 0,90 — Daft Punk, "Nightvision" als vinyl 0,72 en 0,86 tegen de cd, Michael
// Jackson, "Girl Don't Take Your Love From Me" als digitale 24/192 0,87 — terwijl een live-opname of een ander nummer op
// 0,52 tot 0,57 blijft. Tot dan werd zo'n kopie weggegooid als "een andere opname". Saber koos: niet vanzelf vervangen,
// niet weggooien, maar aanbieden — een label "twijfel" bij het nummer op de albumpagina, met beluisteren, vervangen of
// weggooien, en bewaren tot hij kiest, zonder einde.
//
// Op de pc staat de lijst in `twijfel.json`, de kopieën in de map [twijfelMap] onder de downloadmap (de bibliotheek slaat
// die over). Een toestel krijgt per nummer alleen [TwijfelInfo] mee met de catalogus, en luistert via `/kandidaat/<id>`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'fingerprint.dart' show maybeSameRecordingScore;

/// De map onder de downloadmap waar twijfelkopieën wachten. Geen deel van de bibliotheek.
const String twijfelMap = '_twijfel';

/// Vanaf hier is een kopie die bewezen beter klinkt een twijfelgeval in plaats van "een andere opname". De laagste
/// gemeten score van dezelfde plaat was 0,719 (Nightvision, vinyl); de hoogste van een live-opname 0,571.
const double kTwijfelVanaf = 0.70;

/// Wat de vingerafdruk zegt over twee kopieën.
enum Opnameoordeel {
  /// Dezelfde opname: [maybeSameRecordingScore] of hoger.
  zelfde,

  /// Tussen [kTwijfelVanaf] en [maybeSameRecordingScore]: misschien dezelfde, misschien niet.
  twijfel,

  /// Onder [kTwijfelVanaf]: een andere opname (live, een ander nummer).
  andere,

  /// Niet te zeggen (geen fpcalc, niet te lezen).
  onbekend,
}

Opnameoordeel opnameOordeel(double? score) => score == null
    ? Opnameoordeel.onbekend
    : score >= maybeSameRecordingScore
        ? Opnameoordeel.zelfde
        : score >= kTwijfelVanaf
            ? Opnameoordeel.twijfel
            : Opnameoordeel.andere;

/// Wat een toestel en de albumpagina over een twijfelgeval weten. Geen pad: dat blijft op de pc.
typedef TwijfelInfo = ({String id, String bron, double score, String kwaliteit, String ext});

/// Eén twijfelgeval.
class Twijfelgeval {
  /// Ondoorzichtig, voor `/kandidaat/<id>.<ext>` en de opdrachten van een toestel.
  final String id;

  /// Het nummer in de bibliotheek waar dit een kandidaat voor is.
  final String pad;

  /// Het bewaarde bestand in [twijfelMap].
  final String kandidaat;

  /// Waar hij vandaan kwam: "Soulseek emmaphore", "TIDAL 77686343", "torrent …".
  final String bron;

  /// De vingerafdruk tegen jouw kopie.
  final double score;

  /// "FLAC 24/96".
  final String kwaliteit;

  final int ms;

  /// Grootte in bytes: zo komt een weggegooide kandidaat niet terug ([Twijfellijst.afgewezen]).
  final int grootte;

  /// De tags waarmee hij wordt opgeborgen als je kiest voor vervangen (`TrackTags.toJson`).
  final Map<String, dynamic>? gezag;

  const Twijfelgeval({
    required this.id,
    required this.pad,
    required this.kandidaat,
    required this.bron,
    required this.score,
    required this.kwaliteit,
    required this.ms,
    required this.grootte,
    this.gezag,
  });

  String get ext {
    final naam = kandidaat.replaceAll('\\', '/').split('/').last;
    final punt = naam.lastIndexOf('.');
    return punt < 0 ? 'flac' : naam.substring(punt + 1).toLowerCase();
  }

  TwijfelInfo get info => (id: id, bron: bron, score: score, kwaliteit: kwaliteit, ext: ext);

  Map<String, dynamic> toJson() => {
        'id': id,
        'pad': pad,
        'kandidaat': kandidaat,
        'bron': bron,
        'score': score,
        'kwaliteit': kwaliteit,
        'ms': ms,
        'grootte': grootte,
        if (gezag != null) 'gezag': gezag,
      };

  static Twijfelgeval? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], pad = j['pad'], kandidaat = j['kandidaat'];
    if (id is! String || pad is! String || kandidaat is! String) return null;
    return Twijfelgeval(
      id: id,
      pad: pad,
      kandidaat: kandidaat,
      bron: '${j['bron'] ?? ''}',
      score: (j['score'] as num?)?.toDouble() ?? 0,
      kwaliteit: '${j['kwaliteit'] ?? ''}',
      ms: (j['ms'] as num?)?.toInt() ?? 0,
      grootte: (j['grootte'] as num?)?.toInt() ?? 0,
      gezag: j['gezag'] is Map ? Map<String, dynamic>.from(j['gezag'] as Map) : null,
    );
  }
}

String _sleutel(String pad) => pad.replaceAll('\\', '/').toLowerCase();

// ── Wat de albumpagina leest ────────────────────────────────────────────────────────────────────
// Op de pc gevuld door [Twijfellijst], op een toestel door de catalogus ([zetTwijfelVanPc]) — zoals `gemeten()`.

final Map<String, TwijfelInfo> _info = {};

/// Gaat omhoog bij elke wijziging: de catalogus luistert ernaar (een twijfelgeval verandert geen enkel nummer), en de
/// albumpagina ook.
final ValueNotifier<int> twijfelUitgave = ValueNotifier<int>(0);

/// Het twijfelgeval voor het nummer op [pad], of null.
TwijfelInfo? twijfelVoor(String pad) => _info[_sleutel(pad)];

/// Wat de pc over [pad] zegt, op een toestel. Null wist.
void zetTwijfelVanPc(String pad, TwijfelInfo? info) {
  final k = _sleutel(pad);
  final oud = _info[k];
  if (info == null) {
    if (_info.remove(k) != null) twijfelUitgave.value++;
    return;
  }
  if (oud?.id == info.id) return;
  _info[k] = info;
  twijfelUitgave.value++;
}

/// De twijfelgevallen van de pc, op schijf.
class Twijfellijst {
  Twijfellijst(this._bestand);
  final String _bestand;

  final Map<String, Twijfelgeval> _perPad = {};

  /// Per nummer de groottes van kandidaten die je weggooide: die komen niet terug.
  final Map<String, Set<int>> _nee = {};

  Iterable<Twijfelgeval> get alle => _perPad.values;

  Twijfelgeval? van(String pad) => _perPad[_sleutel(pad)];

  Twijfelgeval? metId(String id) => _perPad.values.where((g) => g.id == id).firstOrNull;

  bool afgewezen(String pad, int grootte) => _nee[_sleutel(pad)]?.contains(grootte) ?? false;

  void zet(Twijfelgeval g) {
    _perPad[_sleutel(g.pad)] = g;
    _info[_sleutel(g.pad)] = g.info;
    twijfelUitgave.value++;
  }

  /// Weg uit de lijst; met [nee] komt een kandidaat van dezelfde grootte niet terug.
  Twijfelgeval? verwijder(String pad, {bool nee = false}) {
    final g = _perPad.remove(_sleutel(pad));
    if (g == null) return null;
    _info.remove(_sleutel(pad));
    if (nee) (_nee[_sleutel(pad)] ??= {}).add(g.grootte);
    twijfelUitgave.value++;
    return g;
  }

  Future<void> laad() async {
    try {
      final f = File(_bestand);
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      for (final x in (j['gevallen'] as List? ?? const [])) {
        final g = Twijfelgeval.fromJson(x);
        if (g == null) continue;
        _perPad[_sleutel(g.pad)] = g;
        _info[_sleutel(g.pad)] = g.info;
      }
      final nee = j['nee'];
      if (nee is Map) {
        for (final e in nee.entries) {
          _nee['${e.key}'] = {for (final x in (e.value is List ? e.value as List : const [])) if (x is num) x.toInt()};
        }
      }
      twijfelUitgave.value++;
    } catch (_) {/* een kapotte lijst begint leeg; de kopieën blijven in de map staan */}
  }

  Future<void> bewaar() async {
    try {
      final tmp = File('$_bestand.tmp');
      await tmp.writeAsString(jsonEncode({
        'versie': 1,
        'gevallen': [for (final g in _perPad.values) g.toJson()],
        'nee': {for (final e in _nee.entries) e.key: e.value.toList()},
      }));
      await tmp.rename(_bestand);
    } catch (_) {/* volgende keer opnieuw */}
  }
}
