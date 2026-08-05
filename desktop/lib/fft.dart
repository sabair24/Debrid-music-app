/// Het stukje wiskunde dat nodig is om te horen of een FLAC echt een FLAC is.
///
/// Bewust geen pakket. Een radix-2 FFT is zestig regels die met bekende signalen exact vast te leggen
/// zijn — een sinus op bin 100 hoort een piek op bin 100 te geven, en niets anders. Een afhankelijkheid
/// zou meer risico zijn dan deze code, en slechter te toetsen.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// FFT ter plekke. [re] en [im] moeten even lang zijn en een macht van twee.
///
/// Iteratief met bitomkering vooraf, zodat er geen recursie en geen tussenruimte nodig is.
void fft(Float64List re, Float64List im) {
  final n = re.length;
  if (n <= 1) return;
  assert(im.length == n, 'reëel en imaginair moeten even lang zijn');
  assert(n & (n - 1) == 0, 'lengte moet een macht van twee zijn');

  // Bitomkering: breng elk element op de plaats waar de vlinders het verwachten.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }

  for (var lengte = 2; lengte <= n; lengte <<= 1) {
    final hoek = -2 * math.pi / lengte;
    final wr = math.cos(hoek), wi = math.sin(hoek);
    for (var i = 0; i < n; i += lengte) {
      var cr = 1.0, ci = 0.0;
      for (var j = 0; j < lengte ~/ 2; j++) {
        final ar = re[i + j], ai = im[i + j];
        final br = re[i + j + lengte ~/ 2], bi = im[i + j + lengte ~/ 2];
        final tr = br * cr - bi * ci, ti = br * ci + bi * cr;
        re[i + j] = ar + tr;
        im[i + j] = ai + ti;
        re[i + j + lengte ~/ 2] = ar - tr;
        im[i + j + lengte ~/ 2] = ai - ti;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}

/// Blackman-Harris met vier termen, en niet Hann.
///
/// We zoeken een vloer die zestig tot negentig dB onder de piek ligt. Hann's eerste zijlob zit op −31 dB
/// en zou daar dwars doorheen smeren: een luide toon op 3 kHz zou dan energie op 20 kHz voorwenden en de
/// afkap onvindbaar maken. Blackman-Harris zit op −92 dB en kost vier regels.
Float64List blackmanHarris(int n) {
  const a0 = 0.35875, a1 = 0.48829, a2 = 0.14128, a3 = 0.01168;
  final w = Float64List(n);
  for (var i = 0; i < n; i++) {
    final x = 2 * math.pi * i / (n - 1);
    w[i] = a0 - a1 * math.cos(x) + a2 * math.cos(2 * x) - a3 * math.cos(3 * x);
  }
  return w;
}

/// Het gemiddelde vermogensspectrum over een reeks vensters.
///
/// Middelen over meerdere vensters is wat een afkap zichtbaar maakt: één venster is ruis, dertig
/// vensters is een vloer. Alleen de eerste helft van de bins wordt teruggegeven — de tweede is bij een
/// reëel signaal het spiegelbeeld.
Float64List gemiddeldVermogensspectrum(List<Float64List> vensters, Float64List venster) {
  final n = venster.length;
  final uit = Float64List(n ~/ 2);
  if (vensters.isEmpty) return uit;
  final re = Float64List(n), im = Float64List(n);
  for (final blok in vensters) {
    for (var i = 0; i < n; i++) {
      re[i] = (i < blok.length ? blok[i] : 0) * venster[i];
      im[i] = 0;
    }
    fft(re, im);
    for (var k = 0; k < uit.length; k++) {
      uit[k] += re[k] * re[k] + im[k] * im[k];
    }
  }
  for (var k = 0; k < uit.length; k++) {
    uit[k] /= vensters.length;
  }
  return uit;
}

/// Vermogen naar decibel, met een bodem zodat een lege bin niet oneindig diep wordt.
double dB(double vermogen) => vermogen <= 0 ? -300.0 : 10 * (math.log(vermogen) / math.ln10);
