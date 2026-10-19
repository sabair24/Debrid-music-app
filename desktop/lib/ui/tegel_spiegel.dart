/// De spiegeling onder een albumtegel, en de schaduw erbij.
///
/// Saber, 19-10-2026: "ik wil volle spiegeling voor de album pagina" — overal waar albumtegels staan
/// (Albums, de artiestpagina, Ontdek, zoeken, de rijen op Start), en ook op de tv. Gekozen uit het
/// proefbord: variant B, 22 % van de hoes, van 20 % naar niets, een diepere schaduw ([kSchaduwTegel]),
/// en de titel staat gewoon óver de spiegeling.
///
/// **Getekend uit de hoes zelf, in stroken.** Onder de grote hoes op Nu speelt doet `HoesSpiegel`
/// (ui/kantel_hoes.dart) het met een `ShaderMask`: een eigen laag die in elk beeld opnieuw gemengd
/// wordt. Daar staat er één; in een raster staan er zestien tot dertig tegelijk te scrollen, en Impeller
/// bewaart zo'n laag niet tussen twee beelden. De eerste versie bakte daarom per hoes een klein beeld
/// (`toImageSync`): op de pc (Skia) kost elk gebakken beeld een eigen doel op de videokaart, en bij het
/// scrollen door Albums kwam een hele rij nieuwe tegels in één beeld binnen — rasteren tot 43 ms
/// (warmte.log, 19-10-2026). Nu tekent elke spiegeling de omgekeerde hoes rechtstreeks, als
/// [ImageShader], in [kTegelSpiegelStroken] stroken die elk wat doorzichtiger zijn. Geen laag, geen
/// masker, geen eigen beeld: alleen een handvol vlakjes uit een textuur die er al is.
///
/// **Geen tweede decodering.** De hoes is al gedecodeerd door `cover`/`_netCover`, met
/// `cacheWidth: decodeWidth(maat)`. Hier wordt precies dezelfde [ResizeImage] opgevraagd, dus komt het
/// beeld uit dezelfde plek in de `ImageCache` en wordt er niets extra van schijf of van het net gelezen.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../artwork.dart' show decodeWidth;
import 'maten.dart';

/// Hoe hoog de spiegeling is, als deel van de hoes: zoals onder de grote hoes op Nu speelt.
const double kTegelSpiegelHoogte = .22;

/// Hoe ver onder de hoes hij begint, in punten (het proefbord: 4).
const double kTegelSpiegelAfstand = 4;

/// De dekking bovenaan. Op [_kTegelSpiegelTot] van de hoogte is er niets meer van over.
const double kTegelSpiegelDekking = .2;
const double _kTegelSpiegelTot = .92;

/// In hoeveel stroken het verloop loopt: treden van 2 % dekking, en daaronder is geen trede te zien.
const int kTegelSpiegelStroken = 10;

/// De bron voor de spiegeling van een hoes uit je eigen bibliotheek (de bytes die `cover` tekent).
ImageProvider? spiegelVan(Uint8List? hoes) => hoes == null ? null : MemoryImage(hoes);

/// De bron voor de spiegeling van een hoes van het net (de url die `_netCover` tekent).
ImageProvider? spiegelVanUrl(String? url) => url == null || url.isEmpty ? null : NetworkImage(url);

/// Tekent de spiegeling van [hoes] — een vierkante hoes van [maat] — in een vlak van [maat] breed en
/// [hoogte] hoog dat vlak onder de hoes ligt: de onderrand van de hoes bovenaan, omgekeerd, van
/// [kTegelSpiegelDekking] naar niets. Bijgesneden zoals `BoxFit.cover` de hoes zelf bijsnijdt; [hoek] is
/// de afronding van de hoes.
void tekenSpiegel(Canvas c, ui.Image hoes, {required double maat, required double hoogte, double hoek = 0}) {
  final bronMaat = Size(hoes.width.toDouble(), hoes.height.toDouble());
  final pas = applyBoxFit(BoxFit.cover, bronMaat, Size(maat, maat));
  final uit = Alignment.center.inscribe(pas.source, Offset.zero & bronMaat);
  final kx = maat / uit.width, ky = maat / uit.height;
  // Beeldpunt (u, v) naar (x, y) in de spiegeling: x = kx·(u − links), y = ky·(onder − v). De onderrand
  // van de hoes komt zo op y = 0, en wat erboven lag loopt naar beneden.
  final naar = Float64List.fromList([kx, 0, 0, 0, 0, -ky, 0, 0, 0, 0, 1, 0, -kx * uit.left, ky * uit.bottom, 0, 1]);
  final beeld = ImageShader(hoes, TileMode.clamp, TileMode.clamp, naar, filterQuality: FilterQuality.low);
  final vlak = Rect.fromLTWH(0, 0, maat, hoogte);
  c.save();
  if (hoek > 0) {
    c.clipRRect(RRect.fromRectAndCorners(vlak, topLeft: Radius.circular(hoek), topRight: Radius.circular(hoek)));
  }
  for (var i = 0; i < kTegelSpiegelStroken; i++) {
    final boven = hoogte * i / kTegelSpiegelStroken, onder = hoogte * (i + 1) / kTegelSpiegelStroken;
    final dekking = kTegelSpiegelDekking * (1 - (boven + onder) / 2 / (hoogte * _kTegelSpiegelTot)).clamp(0.0, 1.0);
    if (dekking <= 0) break;
    // Met een shader telt van de kleur alleen de dekking: die maakt de strook doorzichtiger.
    c.drawRect(Rect.fromLTRB(0, boven, maat, onder),
        Paint()
          ..shader = beeld
          ..color = Color.fromRGBO(0, 0, 0, dekking));
  }
  c.restore();
}

/// De spiegeling van één hoes van [maat] punten. Tekent niets tot de hoes er is.
class TegelSpiegel extends StatefulWidget {
  const TegelSpiegel({super.key, required this.bron, required this.maat, this.hoek = kHoek12});

  /// Dezelfde bron als de hoes erboven: [spiegelVan] of [spiegelVanUrl].
  final ImageProvider bron;
  final double maat;

  /// De afronding van de hoes, in punten.
  final double hoek;

  @override
  State<TegelSpiegel> createState() => _TegelSpiegelState();
}

class _TegelSpiegelState extends State<TegelSpiegel> {
  ImageInfo? _info;
  ImageStream? _stroom;
  late final _luister = ImageStreamListener(_binnen, onError: (_, __) {});

  /// Loopt [_zoek] nog? Dan komt een hoes die al klaarligt meteen binnen, en is setState niet nodig.
  bool _inZoek = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _zoek();
  }

  @override
  void didUpdateWidget(TegelSpiegel oud) {
    super.didUpdateWidget(oud);
    if (oud.bron != widget.bron || oud.maat != widget.maat) _zoek();
  }

  void _zoek() {
    // Precies wat `cover`/`_netCover` vragen: hetzelfde beeld, geen tweede decodering.
    final stroom = ResizeImage(widget.bron, width: decodeWidth(widget.maat))
        .resolve(createLocalImageConfiguration(context));
    if (stroom.key == _stroom?.key) return;
    _stroom?.removeListener(_luister);
    _stroom = stroom;
    _inZoek = true;
    try {
      stroom.addListener(_luister);
    } finally {
      _inZoek = false;
    }
  }

  void _binnen(ImageInfo info, bool _) {
    if (!mounted) {
      info.dispose();
      return;
    }
    final oud = _info;
    if (_inZoek) {
      _info = info;
    } else {
      setState(() => _info = info);
    }
    oud?.dispose();
  }

  @override
  void dispose() {
    _stroom?.removeListener(_luister);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = _info?.image;
    if (b == null) return const SizedBox.shrink();
    return CustomPaint(
      key: const ValueKey('tegel-spiegel'),
      size: Size(widget.maat, widget.maat * kTegelSpiegelHoogte),
      painter: _Spiegelschilder(b, widget.maat, widget.hoek),
    );
  }
}

class _Spiegelschilder extends CustomPainter {
  _Spiegelschilder(this.beeld, this.maat, this.hoek);
  final ui.Image beeld;
  final double maat, hoek;

  @override
  void paint(Canvas canvas, Size size) => tekenSpiegel(canvas, beeld, maat: maat, hoogte: size.height, hoek: hoek);

  @override
  bool shouldRepaint(_Spiegelschilder oud) => !beeld.isCloneOf(oud.beeld) || maat != oud.maat || hoek != oud.hoek;
}

/// De plek van de spiegeling in een `Stack` met de hoes van [maat] bovenaan: eronder, over wat er onder
/// de hoes staat heen (de titel tekent daarna en staat er dus óver). Een lege [bron] of [zichtbaar]
/// onwaar = niets, maar dezelfde plek: zo blijft de boom gelijk en verliest de hoes ernaast zijn
/// staat niet (een draaiende hoes, een Hero).
Widget spiegelOnderHoes({required ImageProvider? bron, required double maat, double hoek = kHoek12, bool zichtbaar = true}) =>
    Positioned(
      left: 0,
      top: maat + kTegelSpiegelAfstand,
      width: maat,
      height: maat * kTegelSpiegelHoogte,
      child: IgnorePointer(
        child: bron == null || !zichtbaar ? const SizedBox.shrink() : TegelSpiegel(bron: bron, maat: maat, hoek: hoek),
      ),
    );

/// Een hoes met de schaduw en de spiegeling van een albumtegel, voor de tegels die (nog) geen
/// `AlbumTegel` zijn: de albums in zoeken, de discografie op de artiestpagina, een stijlpagina.
class TegelLicht extends StatelessWidget {
  const TegelLicht({super.key, required this.maat, required this.spiegel, required this.child, this.hoek = kHoek12});

  final double maat;
  final ImageProvider? spiegel;
  final double hoek;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        spiegelOnderHoes(bron: spiegel, maat: maat, hoek: hoek),
        DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(hoek), boxShadow: kSchaduwTegel),
          child: child,
        ),
      ]);
}
