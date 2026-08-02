/// Wat het scherm werkelijk haalt, gemeten in plaats van aangenomen.
library;

import 'package:flutter/scheduler.dart';

import 'warm_log.dart';

/// Telt frames en schrijft op waar de tijd heen gaat, zolang er iets draait.
///
/// Bestaat omdat "het is een AnimationController, dus hij loopt op schermtempo" geen meting is. Een
/// [AnimationController] VRAAGT elk frame aan; of dat frame op tijd klaar is zegt hij niet. Vanaf de
/// buitenkant is haperen niet te onderscheiden van traag, en een release-build strijkt [print] weg —
/// dezelfde reden dat [WarmLog] bestaat.
///
/// Twee getallen, en ze wijzen naar verschillende reparaties. `build` is de UI-draad: te veel widgets
/// die per frame opnieuw gemaakt worden. `raster` is de GPU-draad: te veel pixels, een saveLayer, een
/// blur. Ze samen optellen verbergt precies het onderscheid dat je nodig hebt.
///
/// Het budget is NIET 16,7 ms. Flutter tekent op schermtempo, en dit scherm loopt op 143 Hz — dan is
/// een frame 7,0 ms. Daarom wordt de gemeten frameafstand gebruikt en geen vast getal.
class FpsProbe {
  FpsProbe(this._log);
  final WarmLog _log;

  /// Eén tegelijk. Twee draaiende platen op één scherm zouden elkaars cijfers vervuilen, en de
  /// vraag is wat HET SCHERM haalt, niet wat één widget kost.
  static FpsProbe? _actief;

  TimingsCallback? _hook;
  String _wat = '';
  int _frames = 0;
  int _buildUs = 0, _rasterUs = 0;
  int _buildMaxUs = 0, _rasterMaxUs = 0;
  int _traagsteAfstandUs = 0;
  int _beginMs = 0;

  /// Hoe lang er wordt opgeteld voor er een regel valt. Twee seconden is lang genoeg om een
  /// incidentele hapering te laten uitmiddelen en kort genoeg om te zien of het beter wordt.
  static const _vensterMs = 2000;

  void start(String wat) {
    if (_actief != null && _actief != this) return;
    if (_hook != null) return;
    _actief = this;
    _wat = wat;
    _reset();
    _hook = (List<FrameTiming> t) {
      for (final f in t) {
        _frames++;
        final b = f.buildDuration.inMicroseconds;
        final r = f.rasterDuration.inMicroseconds;
        _buildUs += b;
        _rasterUs += r;
        if (b > _buildMaxUs) _buildMaxUs = b;
        if (r > _rasterMaxUs) _rasterMaxUs = r;
        // De afstand tussen twee vsyncs is het echte budget; hij verraadt ook of er een frame is
        // OVERGESLAGEN, wat je aan build en raster los niet ziet.
        final afstand = f.totalSpan.inMicroseconds;
        if (afstand > _traagsteAfstandUs) _traagsteAfstandUs = afstand;
      }
      final nu = DateTime.now().millisecondsSinceEpoch;
      if (nu - _beginMs >= _vensterMs) _schrijf(nu);
    };
    SchedulerBinding.instance.addTimingsCallback(_hook!);
    _log.line('fps: meting begint — $wat');
  }

  void stop() {
    final h = _hook;
    if (h == null) return;
    SchedulerBinding.instance.removeTimingsCallback(h);
    _hook = null;
    if (_actief == this) _actief = null;
    if (_frames > 0) _schrijf(DateTime.now().millisecondsSinceEpoch);
    _log.line('fps: meting stopt — $_wat');
  }

  void _reset() {
    _frames = 0;
    _buildUs = 0;
    _rasterUs = 0;
    _buildMaxUs = 0;
    _rasterMaxUs = 0;
    _traagsteAfstandUs = 0;
    _beginMs = DateTime.now().millisecondsSinceEpoch;
  }

  void _schrijf(int nu) {
    final ms = nu - _beginMs;
    if (ms <= 0 || _frames == 0) return _reset();
    final fps = _frames * 1000 / ms;
    String d(int us) => (us / 1000).toStringAsFixed(1);
    _log.line('fps: $_wat — ${fps.toStringAsFixed(1)}/s '
        '($_frames frames in ${ms}ms) | '
        'build gem ${d(_buildUs ~/ _frames)}ms max ${d(_buildMaxUs)}ms | '
        'raster gem ${d(_rasterUs ~/ _frames)}ms max ${d(_rasterMaxUs)}ms | '
        'traagste frame ${d(_traagsteAfstandUs)}ms');
    _reset();
  }
}
