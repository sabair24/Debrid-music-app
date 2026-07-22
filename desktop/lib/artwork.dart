import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// What a scan of a release actually shows.
///
/// Discogs says only "primary" or "secondary". A CD release's secondaries are the back of the
/// sleeve, the disc itself, the inlay and the booklet, in no fixed order and with no labels — so
/// the app has to work it out from the pixels, and the user gets the last word in the picker.
enum ArtKind { front, back, disc, other }

/// Is this a scan of a disc?
///
/// A disc scan has three things a sleeve scan doesn't: pale corners (the scanner bed or a white
/// backdrop showing around the circle), a pale spot dead centre (the hole), and something much
/// darker in between (the disc face). Michael Jackson's *Dangerous* CD is the case this was written
/// against: black disc, gold print, white surround, white hole.
///
/// Deliberately conservative. Calling a back cover a disc would spin the wrong picture out from
/// behind the sleeve, which looks broken; failing to spot a disc just means no animation.
bool looksLikeDisc(Uint8List bytes) {
  final s = _sample(bytes);
  if (s == null) return false;
  // A dark-sleeved back cover has dark corners; a disc scan's surround is nearly white.
  if (s.corners < 190) return false;
  // The centre hole is the same white as the surround, and close to it.
  if (s.centre < 175 || (s.centre - s.corners).abs() > 60) return false;
  // And there has to be a disc between them. Without this, a plain white inlay would qualify.
  return s.corners - s.ring > 45;
}

/// A back cover, as opposed to a front cover.
///
/// There is no reliable pixel-level tell — plenty of back covers are as busy as the front. What
/// there IS: Discogs marks exactly one image primary, and for a CD release the first secondary is
/// the back of the sleeve far more often than not. So this is an ordering convention, not a
/// measurement, and the picker exists because conventions are wrong sometimes.
ArtKind guessKind(int index, bool primary, Uint8List? bytes) {
  if (primary) return ArtKind.front;
  if (bytes != null && looksLikeDisc(bytes)) return ArtKind.disc;
  return index == 1 ? ArtKind.back : ArtKind.other;
}

/// Which scan is the front, the back and the disc, across a whole release.
///
/// Deciding image by image was not enough on real data: *Dangerous* has 31 scans, and three of them
/// read as a disc — the CD itself and two booklet pages with pale margins. Only one can slide out
/// from behind the sleeve, so the first wins.
///
/// The back cover gets a better signal than "second in the list": a CD's rear inlay wraps around
/// the spine of the jewel case, so it is measurably WIDER than tall where everything else on a CD
/// release is square. Dangerous's is 600×474 among a stack of 600×598s.
///
/// [ratios] and [datas] are parallel to the release's own image order. A null entry in [datas] is
/// an image that couldn't be fetched; it simply can't be the disc.
({int? front, int? back, int? disc}) assignRoles(
  List<bool> primary,
  List<double> ratios,
  List<Uint8List?> datas,
) {
  int? front, back, disc;
  for (var i = 0; i < primary.length; i++) {
    if (front == null && primary[i]) front = i;
  }
  for (var i = 0; i < primary.length; i++) {
    if (i == front) continue;
    final d = datas.length > i ? datas[i] : null;
    if (disc == null && d != null && looksLikeDisc(d)) {
      disc = i;
      continue;
    }
    if (back == null && ratios.length > i && ratios[i] > 1.1) back = i;
  }
  // No inlay-shaped scan: fall back to the convention, skipping anything already spoken for.
  if (back == null) {
    for (var i = 0; i < primary.length; i++) {
      if (i != front && i != disc) {
        back = i;
        break;
      }
    }
  }
  front ??= primary.isEmpty ? null : 0;
  return (front: front, back: back, disc: disc);
}

class _Sample {
  final double corners, centre, ring;
  const _Sample(this.corners, this.centre, this.ring);
}

/// Average brightness at the corners, at the dead centre, and around a mid-radius ring.
_Sample? _sample(Uint8List bytes) {
  img.Image? im;
  try {
    im = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (im == null || im.width < 32 || im.height < 32) return null;
  // Small enough that this costs nothing, big enough that a 12%-radius hole is several pixels.
  final t = img.copyResize(im, width: 64, height: 64);

  double lum(int x, int y) {
    final p = t.getPixel(x.clamp(0, 63), y.clamp(0, 63));
    return .299 * p.r + .587 * p.g + .114 * p.b;
  }

  double patch(int cx, int cy, int r) {
    var sum = 0.0;
    var n = 0;
    for (var y = cy - r; y <= cy + r; y++) {
      for (var x = cx - r; x <= cx + r; x++) {
        sum += lum(x, y);
        n++;
      }
    }
    return sum / n;
  }

  final corners = (patch(3, 3, 2) + patch(60, 3, 2) + patch(3, 60, 2) + patch(60, 60, 2)) / 4;
  final centre = patch(32, 32, 2);
  // Eight points at 40% of the width from the middle — on the printed face of a disc, and well
  // inside the frame of anything rectangular.
  var ring = 0.0;
  const r = 26;
  for (var i = 0; i < 8; i++) {
    final a = i * 3.14159 / 4;
    ring += lum((32 + r * _cos(a)).round(), (32 + r * _sin(a)).round());
  }
  return _Sample(corners, centre, ring / 8);
}

// Tiny local trig so this file doesn't drag in dart:math for two calls.
double _cos(double a) => _sin(a + 1.5707963);
double _sin(double a) {
  // Bhaskara-style approximation, plenty accurate for picking sample points.
  var x = a % 6.2831853;
  if (x > 3.1415927) return -_sin(x - 3.1415927);
  return 16 * x * (3.1415927 - x) / (49.348022 - 4 * x * (3.1415927 - x));
}
