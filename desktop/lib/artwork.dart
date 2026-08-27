import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// De kleur waar een hoes naar neigt, als ARGB — of null als er niets uitspringt.
///
/// Voor de was achter een albumpagina. Een plat gemiddelde over alle pixels is hiervoor onbruikbaar:
/// dat wordt bruin. Rood en groen naast elkaar middelen tot modder, en een hoes met veel wit of zwart
/// trekt het gemiddelde naar grijs — precies de kleuren waar je géén achtergrond van wil.
///
/// Dus niet middelen maar STEMMEN. Elke pixel die iets van een kleur is, stemt op zijn emmer in een
/// grof raster (4 bits per kanaal), en zijn stem weegt zo zwaar als hij verzadigd is. De zwaarste emmer
/// wint en geeft het gemiddelde van zijn eigen pixels terug — een echte kleur uit de hoes, niet een
/// mengsel dat er nergens in voorkomt.
///
/// Drie soorten pixels stemmen niet mee, en dat is waar de kleur vandaan blijft komen:
///  * bijna zwart — daar is elke kleurmeting ruis;
///  * bijna wit — hetzelfde, plus het is meestal papier of achtergrond;
///  * vrijwel grijs — dat is de definitie van "geen kleur".
///
/// Blijft er dan niets over, dan **null**: een zwart-witte hoes hoort geen gekleurde was te krijgen, en
/// een flauw grijsje is lelijker dan helemaal geen was.
///
/// Draait op 64×64 en niet op de volle hoes: kleur overleeft dat verkleinen ruimschoots, en dit wordt
/// per album gedaan terwijl iemand naar het scherm kijkt.
int? dominantColour(Uint8List bytes) {
  img.Image? im;
  try {
    im = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (im == null || im.width < 8 || im.height < 8) return null;
  const n = 64;
  final t = img.copyResize(im, width: n, height: n);

  final emmers = <int, _Emmer>{};
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final p = t.getPixel(x, y);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final hoog = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final laag = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (hoog < 40 || laag > 215) continue; // bijna zwart, of bijna wit
      final verzadiging = (hoog - laag) / hoog; // hoog > 0, want hoog >= 40
      if (verzadiging < .22) continue; // grijs
      final sleutel = ((r ~/ 16) << 8) | ((g ~/ 16) << 4) | (b ~/ 16);
      (emmers[sleutel] ??= _Emmer()).stem(r, g, b, verzadiging);
    }
  }

  _Emmer? beste;
  for (final e in emmers.values) {
    if (beste == null || e.gewicht > beste.gewicht) beste = e;
  }
  // Een handvol pixels is een compressie-artefact of een stofje op de scan, geen kleur van de hoes.
  if (beste == null || beste.aantal < 10) return null;
  return 0xFF000000 |
      ((beste.r / beste.aantal).round() << 16) |
      ((beste.g / beste.aantal).round() << 8) |
      (beste.b / beste.aantal).round();
}

/// Eén emmer van het kleurenraster: hoe zwaar er op gestemd is, en het gemiddelde eronder.
class _Emmer {
  double gewicht = 0, r = 0, g = 0, b = 0;
  int aantal = 0;

  void stem(double pr, double pg, double pb, double verzadiging) {
    gewicht += verzadiging;
    r += pr;
    g += pg;
    b += pb;
    aantal++;
  }
}

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

/// How many pixels wide this artwork actually needs to be decoded at.
///
/// Every Image in this file decoded at the source resolution, and the sources are big: the covers
/// this app stores are 1200x1200, some originals over 3000. Decoded, a 1200px sleeve is 1200 x 1200 x
/// 4 bytes — 5.8 MB of bitmap — and a 120px grid tile needs 57 KB of that. A hundred and twenty-five
/// albums on screen therefore ask for far more than Flutter's image cache holds, so it evicts and
/// re-decodes while you scroll: the work is done again and again for pictures that were already
/// there.
///
/// A hint, not a resize: `cacheWidth` tells the decoder how small it may go, and BoxFit still does
/// the layout. Multiplied by the screen's pixel ratio so a 2x display gets a sharp image rather than
/// a soft one, and clamped because a hint derived from a wrong ratio should cost a little sharpness,
/// never correctness.
int decodeWidth(double logicalSize) {
  var dpr = 1.0;
  try {
    dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  } catch (_) {/* no view yet — the default is fine for a hint */}
  if (!dpr.isFinite || dpr < 1) dpr = 1;
  if (dpr > 4) dpr = 4;
  // Never below 64: a hint smaller than that makes even a list thumbnail visibly mushy.
  final w = (logicalSize * dpr).round();
  return w < 64 ? 64 : w;
}

/// De vorige zware beeldberekening, wat voor eentje het ook was. Zie [_opDeRij].
Future<void> _vorigeBeeldberekening = Future<void>.value();

/// Eén zware beeldberekening tegelijk, over ALLE soorten heen.
///
/// **Waarom één gedeelde rij en niet één per soort.** De reden staat uitgeschreven bij
/// [kleurBuitenDeTekendraad]: verse isolates die tegelijk grote plaatjes kopiëren brachten de
/// Windows-engine zes keer om. Twee rijen naast elkaar zijn geen rij — dan lopen er alsnog twee
/// isolates tegelijk, en precies dat is wat vermeden moet worden. Dus zit de kleurberekening van een
/// hoes in dezelfde wachtrij als het herkennen van een schijf.
///
/// De staart van de rij is expres een `Future<void>` die NOOIT met een fout eindigt: een mislukte
/// berekening mag de volgende niet meeslepen, en een niet-afgevangen fout in een veld dat nergens
/// meer bekeken wordt is een melding in het log die niemand kan plaatsen.
Future<T> _opDeRij<T>(Future<T> Function() doen) {
  final volgende = _vorigeBeeldberekening.then((_) => doen());
  _vorigeBeeldberekening = volgende.then((_) {}, onError: (_) {});
  return volgende;
}

/// Welke van deze scans er als eerste als een schijf uitziet, of null als geen enkele dat doet.
///
/// De VOLGORDE beslist en niet wie het snelst klaar is — een plaat kan meer dan één ronde scan
/// hebben (een boekjespagina met een bleke kern haalt het soms), en dan is de eerste de juiste.
/// Precies wat de lus deed die hier stond; nu op één plek, zodat hij in één keer de isolate in kan.
int? eersteSchijf(List<Uint8List?> scans) {
  for (var i = 0; i < scans.length; i++) {
    final b = scans[i];
    if (b != null && looksLikeDisc(b)) return i;
  }
  return null;
}

/// [eersteSchijf], maar buiten de tekendraad.
///
/// **Waarom dit moest.** `looksLikeDisc` ontcijfert een plaatje met `package:image` — pure Dart —
/// en verkleint het daarna naar 128×128. Dat is tientallen milliseconden per scan, en het gebeurde
/// tot ZES keer per uitgave, voor élke rij die in beeld kwam, in een lus die doorloopt zolang de
/// uitgavekiezer openstaat. Op een telefoon stond de tekendraad daardoor vrijwel onafgebroken stil:
/// je tikte een scan aan om hem als hoes te kiezen en het paarse randje verscheen pas een tel later.
/// Gemeld op 27-08-2026: *"ik wil dit instant zien veranderen … nu zit er behoorlijk wat tijd
/// tussen waardoor ik soms twijfel of hij het wel heeft aangepast"*.
///
/// Alles in ÉÉN oversteek: zes miniaturen van een paar kilobyte kosten samen minder dan zes keer
/// een isolate opstarten, en de volgorde blijft binnen de isolate bewaard.
Future<int?> eersteSchijfBuitenDeTekendraad(List<Uint8List?> scans) =>
    _opDeRij(() => Isolate.run(() => eersteSchijf(scans)));

/// [assignRoles], maar buiten de tekendraad. Zelfde reden als hierboven — en hier weegt het zwaarder,
/// want een boekje van een plaat kan dertig scans hebben en die gingen er allemaal doorheen.
Future<({int? front, int? back, int? disc})> rollenBuitenDeTekendraad(
  List<bool> primary,
  List<double> ratios,
  List<Uint8List?> datas,
) =>
    _opDeRij(() => Isolate.run(() => assignRoles(primary, ratios, datas)));

/// De hoeskleur uitrekenen in een isolate — en dit MOET buiten elke klasse staan.
///
/// Een closure neemt zijn hele omgeving mee, en de omgeving van een instantiemethode bevat `this`. Zet
/// je `Isolate.run(() => dominantColour(bytes))` in een State, dan gaat die State mee de isolate in, en
/// daaraan hangt de complete widgetboom. Dart weigert dat terecht:
///
///     object is unsendable - Class: _AsyncCompleter
///      <- Instance of '_AlbumDetailPageState'
///      <- _AlbumDetailPageState._kleurUitHoes.<anonymous closure>
///
/// Het venijnige is dat het van buiten niet te zien is: er verschijnt geen melding, de achtergrond
/// blijft gewoon zwart, en de reparatie lijkt niet te werken terwijl elk onderdeel los wél werkt. Ik heb
/// hem in een los Dart-programma getest — daar zit geen `this` omheen en daar wérkte het. Pas een
/// logregel in de app zelf gaf de uitzondering te zien.
///
/// Hier omheen zit geen klasse, dus vangt de closure alleen [bytes], en dat is een Uint8List: verzendbaar.
///
/// **En hier, in artwork.dart, en niet in main.dart.** Er zijn inmiddels drie plekken die dit nodig
/// hebben — de albumpagina, het speelscherm en de spelerbalk — en de rij hieronder werkt alleen als
/// ze hem ALLEMAAL delen: drie eigen rijen zijn geen rij.
///
/// De hoofdkleur van een hoes, buiten de tekendraad — maar ÉÉN TEGELIJK.
///
/// **Waarom die rij, en niet gewoon `Isolate.run` per hoes.** De pc-app crashte deze week zes keer
/// uit zichzelf. Windows noteert elke keer hetzelfde:
///
///     Naam van foutmodule: flutter_windows.dll
///     Uitzonderingscode: 0xc0000005      (toegangsfout)
///     Foutoffset: 0x1cda0
///
/// Geen Dart-uitzondering dus, maar de engine zelf. En het laatste wat de app opschreef, telkens
/// binnen een minuut voor de klap, was een reeks van deze berekeningen:
///
///     21:54:20  was "James Blunt - Back To Bedlam": 5021648 bytes → #685539
///     21:55:19  was "Notre-Dame De Paris": 85817 bytes → #471716
///
/// Elke aanroep startte een verse isolate en kopieerde de hele hoes erin — vijf megabyte per stuk,
/// meerdere per seconde als je door een album bladert of als de verrijker hoezen binnenhaalt. Ze op
/// een rij zetten haalt die piek weg: hooguit één isolate tegelijk, en de kopie van de vorige is
/// opgeruimd voor de volgende begint.
///
/// **Eerlijk over wat dit is:** de correlatie is sterk (zes crashes, alle zes vlak na zo'n reeks) en
/// het mechanisme past, maar bewezen is het niet — de engine valt om zonder te zeggen waaróm. Blijft
/// hij crashen, dan staat in `ui.log` opnieuw wat er vlak daarvoor gebeurde, en is de volgende
/// verdachte niet meer deze.
Future<int?> kleurBuitenDeTekendraad(Uint8List bytes) =>
    _opDeRij(() => Isolate.run(() => dominantColour(bytes)));
