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
/// It looks for the one thing only a disc has: **the hole**. Dead centre there is a punched circle
/// of nothing, so it scans as a small patch of pure backing — flat, even, with no detail at all —
/// and the printed face around it is plainly different.
///
/// The earlier version tested brightness instead: pale surround, pale centre, and a much darker
/// face between them. That worked on a black disc and failed on every light one. Measured on the
/// real scans, Enrique's *Escape* CD is white on a white scanner bed — corners 250, centre 244,
/// face 231 — while a blank booklet page from the very same release reads 198/201/186. The two
/// shapes are indistinguishable by brightness, so no threshold could ever separate them.
///
/// The hole separates them cleanly. Sampled around a small circle at the centre, the spread of
/// brightness is 0–1 for every disc measured and 8–23 for every sleeve, tray, obi and booklet page:
/// paper and print always carry texture, a hole never does. The second test — that the hole differs
/// from the face around it — rejects an image that is simply flat all over.
///
/// Deliberately conservative still. Calling a back cover a disc would spin the wrong picture out
/// from behind the sleeve, which looks broken; failing to spot one only costs the animation.
bool looksLikeDisc(Uint8List bytes) {
  final s = _sample(bytes);
  if (s == null) return false;
  // A hole has no detail. Print always does.
  if (s.holeSpread > 4) return false;
  // A disc is round: its four corners are all the same backing. A rectangular scan runs artwork
  // into them, and a booklet page with a pale middle used to pass the two tests above on that
  // alone. Generous — a scanner lid vignettes, and a shadow down one side is still backing.
  if (s.cornerSpread > 45) return false;
  // And it has to stand apart from the printed face, or this is just a flat image.
  final apart = (s.hole - s.faceInner).abs();
  final apartOuter = (s.hole - s.faceOuter).abs();
  return (apart > apartOuter ? apart : apartOuter) > 25;
}

/// Is this shape a plausible rear inlay, given the sleeve it belongs to?
///
/// Wider than tall, because a CD's rear inlay wraps around the spine of the jewel case. But not
/// ANY width: two booklet pages photographed side by side come out near double, and that is a
/// spread, not a back cover. Measured on Random Access Memories (Discogs release 28622347): the
/// sleeve is 1.33, the inlay 1.30, and four of the fourteen scans sit at about 2.0.
///
/// The upper bound is the only thing being added here. Ordering still decides between the
/// candidates that pass, because on real releases the back cover is listed early and no measurement
/// separates it from a single booklet page of the same shape. That is what the picker is for.
bool _couldBeInlay(double ratio, double sleeve) => ratio > 1.1 && ratio <= sleeve * 1.5;

/// A back cover, as opposed to a front cover.
///
/// There is no reliable pixel-level tell — plenty of back covers are as busy as the front. What
/// there IS: Discogs marks exactly one image primary, and the rear inlay is shaped almost like the
/// sleeve. So this is a measurement of shape, not a certainty, and the picker exists because
/// measurements are wrong sometimes.
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
  // The sleeve's own shape, which is what a rear inlay is measured against.
  final sleeve = (front != null && front < ratios.length) ? ratios[front] : 1.0;
  for (var i = 0; i < primary.length; i++) {
    if (i == front) continue;
    final d = datas.length > i ? datas[i] : null;
    if (disc == null && d != null && looksLikeDisc(d)) {
      disc = i;
      continue;
    }
    if (back == null && ratios.length > i && _couldBeInlay(ratios[i], sleeve)) back = i;
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
  /// Brightness at the very centre, and how much it varies around that little circle.
  final double hole, holeSpread;

  /// Brightness of the face at two radii — a CD's clear hub reaches further out on some pressings,
  /// so one sample alone can land on backing rather than print.
  final double faceInner, faceOuter;

  /// How much the four corners differ from each other. Around a round disc they are all the same
  /// backing; on a rectangular scan they are four different bits of artwork.
  final double cornerSpread;
  const _Sample(
      this.hole, this.holeSpread, this.faceInner, this.faceOuter, this.cornerSpread);
}

/// Brightness around three concentric circles: the hole, and the face at two radii.
_Sample? _sample(Uint8List bytes) {
  img.Image? im;
  try {
    im = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (im == null || im.width < 32 || im.height < 32) return null;
  // 128 wide so the hole — about an eighth of the radius on a CD — is still several pixels across.
  const n = 128;
  final t = img.copyResize(im, width: n, height: n);

  double lum(double x, double y) {
    final p = t.getPixel(x.round().clamp(0, n - 1), y.round().clamp(0, n - 1));
    return .299 * p.r + .587 * p.g + .114 * p.b;
  }

  /// Mean and spread of brightness around a circle at [fraction] of the half-width.
  (double, double) ring(double fraction) {
    const steps = 36;
    final r = fraction * n / 2;
    final vals = <double>[];
    for (var i = 0; i < steps; i++) {
      final a = i * 6.2831853 / steps;
      vals.add(lum(n / 2 + r * _cos(a), n / 2 + r * _sin(a)));
    }
    var mean = 0.0;
    for (final v in vals) {
      mean += v;
    }
    mean /= vals.length;
    var varSum = 0.0;
    for (final v in vals) {
      varSum += (v - mean) * (v - mean);
    }
    return (mean, _sqrt(varSum / vals.length));
  }

  final (hole, spread) = ring(0.06); // inside the hole
  final (inner, _) = ring(0.20); // hub / inner label
  final (outer, _) = ring(0.45); // printed face

  // The four corners. A disc is round, so whatever is behind it shows in all four the same —
  // scanner lid, white backdrop, black cloth. A rectangular scan carries printed artwork right into
  // its corners, and those rarely agree.
  const m = 6.0, far = n - 6.0;
  final corners = [lum(m, m), lum(far, m), lum(m, far), lum(far, far)];
  var cMean = 0.0;
  for (final v in corners) {
    cMean += v;
  }
  cMean /= corners.length;
  var cVar = 0.0;
  for (final v in corners) {
    cVar += (v - cMean) * (v - cMean);
  }
  return _Sample(hole, spread, inner, outer, _sqrt(cVar / corners.length));
}

/// Newton's method — this file deliberately avoids dragging in dart:math for a handful of calls.
double _sqrt(double v) {
  if (v <= 0) return 0;
  var x = v;
  for (var i = 0; i < 20; i++) {
    x = (x + v / x) / 2;
  }
  return x;
}

// Tiny local trig so this file doesn't drag in dart:math for two calls.
double _cos(double a) => _sin(a + 1.5707963);
double _sin(double a) {
  // Bhaskara-style approximation, plenty accurate for picking sample points.
  var x = a % 6.2831853;
  if (x > 3.1415927) return -_sin(x - 3.1415927);
  return 16 * x * (3.1415927 - x) / (49.348022 - 4 * x * (3.1415927 - x));
}
