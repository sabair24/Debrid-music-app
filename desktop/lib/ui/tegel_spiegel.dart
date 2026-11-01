/// De spiegeling onder een albumtegel, en de schaduw erbij.
///
/// Saber, 19-10-2026: "ik wil volle spiegeling voor de album pagina" — overal waar albumtegels staan
/// (Albums, de artiestpagina, Ontdek, zoeken, de rijen op Start), en ook op de tv. Gekozen uit het
/// proefbord: variant B, 22 % van de hoes, van 20 % naar niets, een diepere schaduw ([kSchaduwTegel]),
/// en de titel staat gewoon óver de spiegeling.
///
/// **Getekend uit de hoes zelf.** Onder de grote hoes op Nu speelt doet `HoesSpiegel`
/// (ui/kantel_hoes.dart) het met een `ShaderMask`: een eigen laag die in elk beeld opnieuw gemengd
/// wordt. Daar staat er één; in een raster staan er zestien tot dertig tegelijk te scrollen, en Impeller
/// bewaart zo'n laag niet tussen twee beelden. De eerste versie bakte daarom per hoes een klein beeld
/// (`toImageSync`): op de pc (Skia) kost elk gebakken beeld een eigen doel op de videokaart, en bij het
/// scrollen door Albums kwam een hele rij nieuwe tegels in één beeld binnen — rasteren tot 43 ms
/// (warmte.log, 19-10-2026). Nu tekent elke spiegeling de omgekeerde hoes rechtstreeks, als
/// [ImageShader], met de dekking per hoekpunt (één `drawVertices`; tot 01-11-2026 in stroken, die strepen gaven — zie
/// [tekenSpiegel]). Geen laag, geen masker, geen eigen beeld: één tekenopdracht uit een textuur die er al is.
///
/// **Geen tweede decodering.** De hoes is al gedecodeerd door `cover`/`_netCover`, met
/// `cacheWidth: decodeWidth(maat)`. Hier wordt precies dezelfde [ResizeImage] opgevraagd, dus komt het
/// beeld uit dezelfde plek in de `ImageCache` en wordt er niets extra van schijf of van het net gelezen.
library;

import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../artwork.dart' show decodeWidth;
import '../meetronde.dart' show zonderVoorMeting;
import 'maten.dart';

/// Hoe hoog de spiegeling is, als deel van de hoes: zoals onder de grote hoes op Nu speelt.
const double kTegelSpiegelHoogte = .22;

/// Hoe ver onder de hoes hij begint, in punten (het proefbord: 4).
const double kTegelSpiegelAfstand = 4;

/// De dekking bovenaan. Op [_kTegelSpiegelTot] van de hoogte is er niets meer van over.
const double kTegelSpiegelDekking = .2;
const double _kTegelSpiegelTot = .92;

/// De bron voor de spiegeling van een hoes uit je eigen bibliotheek (de bytes die `cover` tekent).
ImageProvider? spiegelVan(Uint8List? hoes) => hoes == null ? null : MemoryImage(hoes);

/// De bron voor de spiegeling van een hoes van het net (de url die `_netCover` tekent).
ImageProvider? spiegelVanUrl(String? url) => url == null || url.isEmpty ? null : NetworkImage(url);

/// Tekent de spiegeling van [hoes] — een vierkante hoes van [maat] — in een vlak van [maat] breed en
/// [hoogte] hoog dat vlak onder de hoes ligt: de onderrand van de hoes bovenaan, omgekeerd, van
/// [kTegelSpiegelDekking] naar niets. Bijgesneden zoals `BoxFit.cover` de hoes zelf bijsnijdt; [hoek] is
/// de afronding van de hoes.
///
/// **Een glad verloop, geen treden (Saber, 01-11-2026: "zit er in de reflectie altijd lijk strepen in").** Hier stonden
/// tien tot tweeëndertig stroken van elk één dekking: gemeten (test/spiegel_zonder_strepen_test.dart) onder de grote hoes op de
/// gsm treden van 8 à 9 pixelrijen met sprongen van 2 à 3 op 255 (50, 48, 45, 42 …), onder een tegel op de pc sprongen
/// van 5 — op een lichte achtergrond elke trede een streep. Nu:
/// * [gebakken] (één keer, [bakSpiegel]): de omgekeerde hoes in een laag, met een echt verloop als masker erover;
/// * anders (elk beeld, de tegels op pc, gsm en tv): één [Canvas.drawVertices] met de dekking per hoekpunt, die de
///   videokaart over elke pixelrij verloopt. Eén tekenopdracht in plaats van tien tot tweeëndertig, en geen laag.
void tekenSpiegel(Canvas c, ui.Image hoes,
    {required double maat, required double hoogte, double hoek = 0, bool gebakken = false}) {
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
  // Van [kTegelSpiegelDekking] bovenaan naar niets op [_kTegelSpiegelTot] van de hoogte; daaronder niets.
  final tot = hoogte * _kTegelSpiegelTot;
  const boven = Color.fromRGBO(255, 255, 255, kTegelSpiegelDekking), onder = Color(0x00FFFFFF);
  if (gebakken) {
    c.saveLayer(vlak, Paint());
    c.drawRect(vlak, Paint()..shader = beeld);
    // Het masker ruimer dan het vlak: de laag is op de pixel afgerond groter, en een rij die het masker maar half
    // bedekt, liet de hoes erdoor — gemeten: de laatste rij op 41 van 255 (de oude "streep onderaan", 19-10-2026).
    c.drawRect(
        vlak.inflate(1),
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, tot), const [boven, onder]));
    c.restore();
  } else {
    // modulate: de kleur van de hoes keer die van het hoekpunt — wit met de dekking, dus alleen doorzichtiger.
    final hoeken = ui.Vertices(
      VertexMode.triangles,
      [Offset.zero, Offset(maat, 0), Offset(0, tot), Offset(maat, 0), Offset(maat, tot), Offset(0, tot)],
      colors: const [boven, boven, onder, boven, onder, onder],
    );
    c.drawVertices(hoeken, BlendMode.modulate, Paint()..shader = beeld);
  }
  c.restore();
}

/// De spiegeling van één hoes van [maat] punten. Tekent niets tot de hoes er is.
class TegelSpiegel extends StatefulWidget {
  const TegelSpiegel({super.key, required this.bron, required this.maat, this.hoek = kHoek12, this.gebakken = false});

  /// Eén keer in een beeld tekenen en daarna alleen dat beeld ([bakSpiegel]) — voor de grote hoes, niet voor de tegels.
  ///
  /// **Waarom (gemeten op de Mac, 23-10-2026).** Onder de grote hoes in Nu speelt kostte de spiegeling in stroken ruim
  /// 7 ms per beeld: met de spiegeling 9,0 ms rasteren bij het kantelen (516 van de 532 beelden te laat op 120 Hz),
  /// zonder 1,3 ms (geen enkel). Impeller tekent elke strook met zijn eigen doorzichtigheid opnieuw uit de hele hoes,
  /// en dat elk beeld, want het bewaart niets. Eén gebakken beeld kost hetzelfde als de hoes zelf. Onder de tegels
  /// blijven de stroken: daar kostte één gebakken beeld per tegel op de pc juist te veel (zie hierboven).
  final bool gebakken;

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
    _bak?.beeld.dispose();
    super.dispose();
  }

  /// Het gebakken beeld ([TegelSpiegel.gebakken]) en waarvoor het gebakken is.
  ({ui.Image beeld, ui.Image van, double maat, double hoek, double dpr})? _bak;

  @override
  Widget build(BuildContext context) {
    final b = _info?.image;
    if (b == null) return const SizedBox.shrink();
    // Een meetronde zonder de spiegeling onder de tegels (meetronde.dart).
    if (!widget.gebakken && zonderVoorMeting('tegelspiegel')) return const SizedBox.shrink();
    if (widget.gebakken || bakTegelSpiegels) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final k = _bak;
      if (k == null || !k.van.isCloneOf(b) || k.maat != widget.maat || k.hoek != widget.hoek || k.dpr != dpr) {
        k?.beeld.dispose();
        _bak = (beeld: bakSpiegel(b, maat: widget.maat, hoek: widget.hoek, dpr: dpr), van: b, maat: widget.maat, hoek: widget.hoek, dpr: dpr);
      }
      return RawImage(
        key: const ValueKey('tegel-spiegel-gebakken'),
        image: _bak!.beeld,
        width: widget.maat,
        height: widget.maat * kTegelSpiegelHoogte,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.low,
      );
    }
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

/// Bakken ook de tegels hun spiegeling ([TegelSpiegel.gebakken])? Op de Mac en de iPad wel, elders niet.
///
/// **Waarom per platform (meetronde, 23-10-2026).** Op de Mac kostte de spiegeling in stroken onder de albumtegels
/// meer dan 30 ms per beeld: Albums scrollen 36,1 ms rasteren met elk beeld te laat, zonder tegelspiegeling 4,4 ms en
/// geen enkel (Saber: "navigeren tussen vensters is soms stroef ook, vooral tussen start, albums, tracks"). Impeller
/// op Metal tekent elke strook opnieuw uit de hele hoes. Op de gsm (Impeller op Vulkan) en de pc (Skia) maakte de
/// tegelspiegeling nauwelijks verschil, en op de pc kostte één gebakken beeld per tegel juist te veel (43 ms bij het
/// scrollen, 19-10-2026). Een meetronde vergelijkt met `tegelstroken` (de Mac zoals vroeger) en `tegelbak` (elders
/// gebakken).
bool get bakTegelSpiegels =>
    zonderVoorMeting('tegelbak') || ((Platform.isMacOS || Platform.isIOS) && !zonderVoorMeting('tegelstroken'));

/// De spiegeling van [hoes] als één beeld van [maat] × [maat]·[kTegelSpiegelHoogte] punten, op [dpr] pixels per punt:
/// precies wat [tekenSpiegel] tekent, één keer.
ui.Image bakSpiegel(ui.Image hoes, {required double maat, double hoek = 0, double dpr = 1}) {
  final hoogte = maat * kTegelSpiegelHoogte;
  final opname = ui.PictureRecorder();
  final c = Canvas(opname)..scale(dpr);
  tekenSpiegel(c, hoes, maat: maat, hoogte: hoogte, hoek: hoek, gebakken: true);
  final plaat = opname.endRecording();
  try {
    return plaat.toImageSync((maat * dpr).ceil().clamp(1, 8192), (hoogte * dpr).ceil().clamp(1, 8192));
  } finally {
    plaat.dispose();
  }
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
