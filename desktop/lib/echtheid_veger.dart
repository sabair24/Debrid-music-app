/// De echtheidsveger: meet op de pc elke FLAC één keer volledig door ([Echtheidsmeter]), en daarna
/// alleen wat er nieuw binnenkomt.
///
/// **Waarom een veger en niet de knop alleen** (20-10-2026). De volle meting vervangt de oude (drie
/// grepen van vier seconden), en wat die oude zei wordt bij het laden weggegooid ([echtheidsVersie]):
/// ~180 van zijn antwoorden waren fout. Zonder veger stond er na het bijwerken geen enkele badge meer tot
/// iemand op "meten" drukte. Nu meet de pc de bibliotheek in de achtergrond opnieuw — ~1 s per nummer,
/// één tegelijk, op de harde schijf achter elkaar — en vult de badges en de Kwaliteit-lijst vanzelf.
///
/// Zelfde gedrag als de luidheidsveger ([LuidheidVeger]): pas na een paar minuten, wachten zolang de
/// bibliotheek scant, de pc omzet of de luidheidsveger meet, en een lopende meting loslaten als een
/// bestand gewist of verplaatst wordt (Windows houdt een bestand vast zolang ffmpeg het open heeft).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'echtheid.dart';
import 'echtheid_meter.dart';
import 'echtheid_oordelen.dart';
import 'integriteit.dart';
import 'lan/transcode.dart' show Transcoder;
import 'library.dart';
import 'models.dart';
import 'warm_log.dart';

class EchtheidVeger {
  EchtheidVeger({
    required this.library,
    this.enabled = true,
    Echtheidsmeter? meter,
    this.bezigElders,
    this.startNa = const Duration(minutes: 6),
    this.rust = const Duration(seconds: 30),
    this.tussenpoos = const Duration(milliseconds: 300),
  }) : _meter = meter ?? Echtheidsmeter(cacheMap: '${library.configDir}${Platform.pathSeparator}echtheid');

  final LibraryStore library;
  final bool enabled;
  final bool Function()? bezigElders;
  final Duration startNa, rust, tussenpoos;
  final Echtheidsmeter _meter;

  /// Voor de hartslag: wat de veger nu doet.
  static final ValueNotifier<String> voortgang = ValueNotifier<String>('');

  late final WarmLog _log = WarmLog('${library.configDir}${Platform.pathSeparator}echtheid.log');

  bool _gestart = false, _gestopt = false, _bezig = false, _nogEens = false;
  Timer? _start, _herstart;
  int? _pid;
  String? _pidPad;
  final Map<String, DateTime> _geblokkeerd = {};

  Future<void> start() async {
    if (!enabled || library.isRemote || _gestart || !_meter.available) return;
    _gestart = true;
    library.addListener(_veranderd);
    _start = Timer(startNa, () => unawaited(ronde()));
  }

  void stop() {
    _gestopt = true;
    _start?.cancel();
    _herstart?.cancel();
    library.removeListener(_veranderd);
    final pid = _pid;
    if (pid != null) Process.killPid(pid);
  }

  void _veranderd() {
    if (_gestopt || !_gestart || (_start?.isActive ?? false)) return;
    _herstart?.cancel();
    _herstart = Timer(rust, () => unawaited(ronde()));
  }

  /// Breek een lopende meting op [paden] af en laat die paden ~10 s met rust.
  Future<void> laatLos(List<String> paden) async {
    final tot = DateTime.now().add(const Duration(seconds: 10));
    final weg = {for (final p in paden) p.toLowerCase()};
    for (final p in weg) {
      _geblokkeerd[p] = tot;
    }
    final pid = _pid, pad = _pidPad;
    if (pid != null && pad != null && weg.contains(pad.toLowerCase())) {
      Process.killPid(pid);
      // Even wachten tot Windows het bestand loslaat.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  bool _isGeblokkeerd(String pad) {
    final tot = _geblokkeerd[pad.toLowerCase()];
    return tot != null && DateTime.now().isBefore(tot);
  }

  Future<bool> _wachtOpRust() async {
    while (!_gestopt && (library.scanning || (bezigElders?.call() ?? false) || Transcoder.bezig)) {
      voortgang.value = library.scanning ? 'echtheid wacht: bibliotheek scant' : 'echtheid wacht';
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return !_gestopt;
  }

  /// De nog ongemeten FLAC's, nieuwste eerst: wat er net binnenkwam, wil je het eerst weten.
  List<Track> _teMeten() => [
        for (final t in library.tracks)
          if (t.isFlac && t.path.isNotEmpty && gemeten(t.path) == null && !_isGeblokkeerd(t.path)) t,
      ]..sort((a, b) => b.addedMs.compareTo(a.addedMs));

  Future<void> ronde() async {
    if (_gestopt) return;
    if (_bezig) {
      _nogEens = true;
      return;
    }
    _bezig = true;
    try {
      await laadEchtheid();
      var lijst = _teMeten();
      if (lijst.isEmpty) return;
      final start = DateTime.now();
      _log.line('ronde: ${lijst.length} te meten');
      var gedaan = 0, nep = 0, kapot = 0, vermoedelijk = 0, niets = 0;
      while (lijst.isNotEmpty && !_gestopt) {
        final t = lijst.removeAt(0);
        if (!await _wachtOpRust()) break;
        if (gemeten(t.path) != null || _isGeblokkeerd(t.path) || !File(t.path).existsSync()) continue;
        voortgang.value = 'echtheid ${gedaan + 1}/${gedaan + lijst.length + 1}';
        final o = await _meter.van(t.path,
            kopSampleRate: t.sampleRate,
            kopBits: t.bitsPerSample,
            duurSeconden: (t.duration?.inSeconds ?? 0).toDouble(), opStart: (pid) {
          _pid = pid;
          _pidPad = t.path;
        });
        _pid = null;
        _pidPad = null;
        gedaan++;
        if (o == null || o.isOnbekend) {
          niets++;
        } else {
          await onthoudOordeel(t.path, o);
          if (o.isNep) nep++;
          if (o.isVermoedelijk) vermoedelijk++;
          if (o.integriteit == Integriteit.fout) {
            kapot++;
            await onthoudHeelheid(t.path, (heel: false, reden: 'de controlesom van de samples klopt niet'));
            _log.line('KAPOT: ${t.path}');
          } else if (o.integriteit == Integriteit.klopt) {
            await onthoudHeelheid(t.path, (heel: true, reden: null));
          }
        }
        if (gedaan % 25 == 0) library.refreshFromCorrections();
        await Future<void>.delayed(tussenpoos);
      }
      library.refreshFromCorrections();
      final s = DateTime.now().difference(start).inSeconds;
      _log.line('klaar: $gedaan gemeten in $s s — $nep nep, $vermoedelijk vermoedelijk, $kapot kapot, $niets niet te beoordelen'
          '${Echtheidsmeter.laatsteFout == null ? '' : ' (laatste fout: ${Echtheidsmeter.laatsteFout})'}');
    } catch (e) {
      _log.line('ronde MISLUKT: $e');
    } finally {
      _bezig = false;
      voortgang.value = '';
      if (_nogEens && !_gestopt) {
        _nogEens = false;
        unawaited(ronde());
      }
    }
  }
}
