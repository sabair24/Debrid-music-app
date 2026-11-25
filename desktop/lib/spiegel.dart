/// De spiegeltest: is een 24/48 opgeschaald vanaf 44,1 kHz? Puur, zonder `dart:io` — de meting voedt hem
/// (echtheid_meter.dart), het oordeel leest hem ([oordeelVol], echtheid.dart).
///
/// **Waarom dit bestaat.** Saber, 25-11-2026: *"Kan je deze 2 eens controleren op de echtheid van de resolutie of het
/// 100 procent klopt ?"* — Chris Isaak "Blue Hotel" en Modjo "Lady (Hear Me Tonight)", allebei "FLAC · 24/48 · studio".
/// Geen van beide was echt. Blue Hotel liep in het spectrum gewoon door tot 24 kHz, en dat leek bewijs van een echte
/// 48 kHz-bron. Maar wat er boven 22,05 kHz zat, was het SPIEGELBEELD van wat er tussen 20 en 22 kHz zat: wie een 44,1
/// kHz-bestand naar 48 kHz omrekent met een onvolmaakt filter, laat de spiegeling van de oude bemonstering staan
/// (44 100 − f). De proef "is er iets boven 24,5 kHz" draait pas boven 48 kHz, en de muur rond 20 kHz zegt bij 48 kHz
/// niets (28-10-2026: steilste val gelijk verspreid over 19–22,85 kHz bij 168 bestanden).
///
/// **De proef.** Per venster de lijnen k in 22,2–23,9 kHz tegen hun spiegelbeeld 44 100 − f. Bij een 44,1-bron hangen die
/// vast aan elkaar: lijn k = c · conj(lijn 4704 − k) · e^{2πi·44100·n0/48000}, met een vaste c per lijn (het filter van
/// wie opschaalde). Bij echte inhoud boven 22 kHz hangt niets vast. De samenhang γ² per lijn, over alle vensters, en
/// daarvan het gemiddelde: [Spiegelmeter.uitslag].
///
/// Venster van 5120 monsters (2^10 · 5): de lijnen liggen 9,375 Hz uit elkaar, en 44 100 Hz is precies lijn 4704 —
/// het spiegelbeeld valt dus op een lijn. De DFT van 5120 = vijf FFT's van 1024 en de vijf bijeen ([_lijnen]).
///
/// Geijkt op 25-11-2026 (scratchpad spiegel5120.js, dezelfde rekenwijze): de cd zelf opgeschaald met ffmpeg 0,64, met
/// lineaire interpolatie 0,83; Blue Hotel 0,96, Missy Elliott "Get Ur Freak On" 0,96; een echte 24/48 (Céline Dion,
/// "Bonjour, Pardon, Merci", tot op −69 dB gelijk aan zijn cd) 0,006. Zie [kSpiegelOpgeschaald] voor de bibliotheek.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

/// Vensterlengte van de spiegeltest (2^10 · 5).
const int kSpiegelN = 5120;

/// 44 100 Hz in lijnen van 48 000 / [kSpiegelN] = 9,375 Hz.
const int _spiegelLijn = 4704;

/// De lijnen boven 22,05 kHz die gemeten worden: 22,2–23,9 kHz (onder 24 kHz blijft ruimte voor het filter van de
/// encoder; boven 22,05 kHz begint pas wat een 44,1-bron niet kan dragen).
final int _van = (22200 / 9.375).ceil(), _tot = (23900 / 9.375).floor();

class Spiegelmeter {
  Spiegelmeter() {
    final n = _tot - _van + 1;
    _sxx = Float64List(n);
    _smm = Float64List(n);
    _sr = Float64List(n);
    _si = Float64List(n);
  }

  late final Float64List _sxx, _smm, _sr, _si;
  int _vensters = 0;

  static final Float64List _hann = Float64List.fromList(
      [for (var i = 0; i < kSpiegelN; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / (kSpiegelN - 1))]);
  static final Float64List _wr = Float64List.fromList([for (var k = 0; k < kSpiegelN; k++) math.cos(-2 * math.pi * k / kSpiegelN)]);
  static final Float64List _wi = Float64List.fromList([for (var k = 0; k < kSpiegelN; k++) math.sin(-2 * math.pi * k / kSpiegelN)]);

  int get vensters => _vensters;

  /// Eén venster: [x] bevat minstens [kSpiegelN] monsters van één kanaal (−1..1) vanaf monster [n0] van het nummer.
  void venster(List<double> x, int n0) {
    final v = Float64List(kSpiegelN);
    for (var i = 0; i < kSpiegelN; i++) {
      v[i] = x[i] * _hann[i];
    }
    final f = _lijnen(v);
    // De draaiing die de plek in het nummer meebrengt: e^{+2πi · 44100 · n0 / 48000}, en 44100/48000 = 147/160.
    final th = 2 * math.pi * ((147 * n0) % 160) / 160;
    final c = math.cos(th), s = math.sin(th);
    final n = _tot - _van + 1;
    for (var j = 0; j < n; j++) {
      final k = _van + j, m = _spiegelLijn - k;
      final xr = f.re[k - _laag], xi = f.im[k - _laag];
      final yr = f.re[m - _laag], yi = f.im[m - _laag];
      // conj(Y) · e^{iθ}
      final mr = yr * c + yi * s, mi = yr * s - yi * c;
      _sxx[j] += xr * xr + xi * xi;
      _smm[j] += mr * mr + mi * mi;
      _sr[j] += xr * mr + xi * mi;
      _si[j] += xi * mr - xr * mi;
    }
    _vensters++;
  }

  /// Het gemiddelde van γ² over de lijnen, of null bij te weinig vensters. Bij een 44,1-bron dicht bij 1, bij echte
  /// inhoud (of niets) boven 22 kHz dicht bij 0 (de ondergrens is ongeveer 1 / [vensters]).
  double? get uitslag {
    if (_vensters < kSpiegelMinVensters) return null;
    var som = 0.0, n = 0;
    for (var j = 0; j < _sxx.length; j++) {
      if (_sxx[j] <= 0 || _smm[j] <= 0) continue;
      som += (_sr[j] * _sr[j] + _si[j] * _si[j]) / (_sxx[j] * _smm[j]);
      n++;
    }
    return n == 0 ? null : som / n;
  }

  /// De laagste lijn die [_lijnen] uitrekent: het spiegelbeeld van [_tot].
  static final int _laag = _spiegelLijn - _tot;

  /// De lijnen [_laag].. [_tot] van de DFT van [x] (lengte [kSpiegelN]): vijf FFT's van 1024 op x[5m + r], en
  /// X[k] = Σ_r W^{rk} · F_r[k mod 1024].
  static ({Float64List re, Float64List im}) _lijnen(Float64List x) {
    const m = kSpiegelN ~/ 5;
    final fr = <Float64List>[], fi = <Float64List>[];
    for (var r = 0; r < 5; r++) {
      final re = Float64List(m), im = Float64List(m);
      for (var i = 0; i < m; i++) {
        re[i] = x[5 * i + r];
      }
      fft(re, im);
      fr.add(re);
      fi.add(im);
    }
    final n = _tot - _laag + 1;
    final ore = Float64List(n), oim = Float64List(n);
    for (var j = 0; j < n; j++) {
      final k = _laag + j;
      var sr = 0.0, si = 0.0;
      for (var r = 0; r < 5; r++) {
        final w = (r * k) % kSpiegelN, a = fr[r][k % m], b = fi[r][k % m];
        sr += a * _wr[w] - b * _wi[w];
        si += a * _wi[w] + b * _wr[w];
      }
      ore[j] = sr;
      oim[j] = si;
    }
    return (re: ore, im: oim);
  }
}

/// Zoveel vensters minstens voor een uitspraak.
const int kSpiegelMinVensters = 100;

/// Vanaf deze samenhang is een 24/48 opgeschaald vanaf 44,1 kHz. Zie de inleiding voor de ijking.
const double kSpiegelOpgeschaald = 0.3;
