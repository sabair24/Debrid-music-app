/// MEETTAK (18-10-2026), niet uitgeven: woorden uit proef.txt in de logmap zetten nieuwe effecten
/// apart uit, en een meter schrijft per seconde wat het scherm haalde naar proef.log. Zo is per effect
/// te meten wat een tab- of paginawissel kost, zonder een bouw per vermoeden.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

/// De schakelaars uit proef.txt. Zonder bestand leeg.
Set<String> gProef = const {};

/// Leest proef.txt en start de meter. Eén keer, bij het opstarten.
void proefInrichten(String logMap, void Function(String) log) {
  try {
    final p = File('$logMap${Platform.pathSeparator}proef.txt');
    if (p.existsSync()) gProef = p.readAsStringSync().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
  } catch (_) {}
  log('proef: schakelaars ${gProef.isEmpty ? '(geen)' : gProef.join(' ')}');
  var beelden = 0, teLaat = 0, bouwMax = 0, rasterMax = 0;
  var begin = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((List<ui.FrameTiming> t) {
    for (final f in t) {
      beelden++;
      final b = f.buildDuration.inMicroseconds, r = f.rasterDuration.inMicroseconds;
      if (b > bouwMax) bouwMax = b;
      if (r > rasterMax) rasterMax = r;
      if (b > 6900 || r > 6900) teLaat++;
    }
    final nu = DateTime.now();
    if (nu.difference(begin).inMilliseconds < 1000) return;
    log('beelden $beelden, te laat $teLaat, bouwen max ${(bouwMax / 1000).toStringAsFixed(1)} ms, '
        'rasteren max ${(rasterMax / 1000).toStringAsFixed(1)} ms');
    beelden = teLaat = bouwMax = rasterMax = 0;
    begin = nu;
  });
}
