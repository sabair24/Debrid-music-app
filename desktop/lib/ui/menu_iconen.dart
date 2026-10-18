/// De iconen van het menu: lijniconen die vollopen onder de pil, elk met een eigen beweging
/// (Saber, 17-10-2026: "in de menu mag naast de tekst mooie animated iconen komen").
///
/// **Wat hij koos.** Dunne lijnen met ronde hoeken; komt de pil erop, dan loopt het icoon vloeiend vol
/// en speelt het zijn beweging één keer. Wijs je het met de muis aan, dan een kleinere versie. De
/// kleur is die van het woord ernaast. Ze bewegen altijd, ook als Windows de animaties uit heeft
/// staan (zijn keuze). Per sectie:
///
/// | Sectie          | Beweging                                  |
/// |-----------------|-------------------------------------------|
/// | Zoeken          | vergrootglas wiebelt kort                 |
/// | Start           | het deurtje gaat open en dicht            |
/// | Albums          | de cd draait een slag en veert terug      |
/// | Tracks          | de noot maakt een sprongetje              |
/// | Artiesten       | de microfoon kantelt heen en weer         |
/// | Online zoeken   | de wereldbol draait een slag              |
/// | Ontdek          | de kompasnaald zwiept en komt tot rust    |
/// | Mijn downloads  | de pijl valt in het bakje (blijft vallen zolang er iets binnenkomt) |
/// | Op dit toestel  | het vinkje tekent zich                    |
/// | Favorieten      | het hart klopt twee keer                  |
/// | Afspeellijsten  | de regels schuiven één voor één binnen    |
/// | Kwaliteit       | het sterretje fonkelt                     |
/// | Instellingen    | het tandwiel draait een halve slag        |
///
/// **Waarom getekend en geen lettertype.** Een icoon uit een lettertype is één vorm: het deurtje kan
/// niet apart open, de naald niet apart zwiepen, het vinkje zich niet tekenen. Hier is elk icoon een
/// paar paden op een raster van 24 bij 24, en de beweging verplaatst alleen het deel dat beweegt.
///
/// **Elke beweging eindigt waar hij begon.** Zo springt er nooit iets aan het eind terug: de cd draait
/// precies een hele slag, het tandwiel een veelvoud van één tand, de wereldbol een veelvoud van de
/// afstand tussen twee meridianen.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

/// Welk icoon.
enum MenuIcoonSoort {
  zoeken,
  start,
  albums,
  tracks,
  artiesten,
  online,
  ontdek,
  downloads,
  toestel,
  favorieten,
  afspeellijsten,
  kwaliteit,
  instellingen,
}

/// Het icoon voor sectie [id] van `NavSections.items` (dezelfde nummers als `_view`).
MenuIcoonSoort? menuIcoonVoorSectie(int id) => switch (id) {
      5 => MenuIcoonSoort.start,
      0 => MenuIcoonSoort.albums,
      4 => MenuIcoonSoort.tracks,
      1 => MenuIcoonSoort.artiesten,
      2 => MenuIcoonSoort.online,
      3 => MenuIcoonSoort.ontdek,
      6 => MenuIcoonSoort.downloads,
      10 => MenuIcoonSoort.toestel,
      8 => MenuIcoonSoort.favorieten,
      9 => MenuIcoonSoort.afspeellijsten,
      7 => MenuIcoonSoort.kwaliteit,
      _ => null,
    };

/// Hoe lang de beweging van [soort] duurt bij het kiezen. Bij aanwijzen is hij korter (×0,7).
Duration menuBewegingDuur(MenuIcoonSoort soort) => switch (soort) {
      MenuIcoonSoort.albums => const Duration(milliseconds: 900),
      MenuIcoonSoort.ontdek => const Duration(milliseconds: 1100),
      MenuIcoonSoort.favorieten => const Duration(milliseconds: 800),
      MenuIcoonSoort.downloads => const Duration(milliseconds: 750),
      MenuIcoonSoort.instellingen => const Duration(milliseconds: 800),
      MenuIcoonSoort.online => const Duration(milliseconds: 900),
      MenuIcoonSoort.afspeellijsten => const Duration(milliseconds: 700),
      _ => const Duration(milliseconds: 650),
    };

/// Hoe lang het vollopen duurt.
const kMenuIcoonVullen = Duration(milliseconds: 260);

/// Een icoon van het menu.
///
/// - [gekozen]: onder de pil. Wordt hij waar, dan loopt het icoon vol en speelt de beweging.
/// - [aangewezen]: de muis staat erop. Wordt hij waar, dan een kleinere beweging.
/// - [bezig]: de beweging loopt door zolang dit waar is (Mijn downloads terwijl er iets binnenkomt).
class MenuIcoon extends StatefulWidget {
  const MenuIcoon({
    super.key,
    required this.soort,
    required this.kleur,
    this.gekozen = false,
    this.aangewezen = false,
    this.bezig = false,
    this.maat = 18,
  });

  final MenuIcoonSoort soort;
  final Color kleur;
  final bool gekozen;
  final bool aangewezen;
  final bool bezig;
  final double maat;

  @override
  State<MenuIcoon> createState() => _MenuIcoonState();
}

class _MenuIcoonState extends State<MenuIcoon> with TickerProviderStateMixin {
  late final AnimationController _vul = AnimationController(
    vsync: this,
    duration: kMenuIcoonVullen,
    value: widget.gekozen ? 1 : 0,
  );
  late final AnimationController _beweging = AnimationController(
    vsync: this,
    duration: menuBewegingDuur(widget.soort),
    value: 1,
  );

  /// 1 bij kiezen, kleiner bij aanwijzen.
  double _sterk = 1;

  @override
  void initState() {
    super.initState();
    if (widget.bezig) _beweging.repeat();
  }

  @override
  void didUpdateWidget(MenuIcoon oud) {
    super.didUpdateWidget(oud);
    if (widget.gekozen != oud.gekozen) {
      if (widget.gekozen) {
        _vul.forward();
        _speel(1);
      } else {
        _vul.reverse();
      }
    } else if (widget.aangewezen && !oud.aangewezen && !widget.gekozen) {
      _speel(.5);
    }
    if (widget.bezig != oud.bezig) {
      if (widget.bezig) {
        _sterk = 1;
        _beweging.repeat();
      } else if (_beweging.isAnimating) {
        // De lopende ronde afmaken in plaats van halverwege stil te vallen.
        _beweging.forward();
      }
    }
  }

  void _speel(double sterk) {
    if (widget.bezig) return;
    _sterk = sterk;
    _beweging.duration = menuBewegingDuur(widget.soort) * (sterk < 1 ? .7 : 1);
    _beweging.forward(from: 0);
  }

  @override
  void dispose() {
    _vul.dispose();
    _beweging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.maat,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_vul, _beweging]),
            builder: (_, __) => CustomPaint(
              painter: MenuIcoonSchilder(
                soort: widget.soort,
                kleur: widget.kleur,
                vul: Curves.easeOut.transform(_vul.value),
                t: _beweging.value,
                sterk: _sterk,
                doorlopend: widget.bezig,
              ),
            ),
          ),
        ),
      );
}

/// Tekent [soort] op een raster van 24 bij 24, geschaald naar het vak.
///
/// - [vul] 0 = alleen lijnen, 1 = vol (met de details eruit gesneden).
/// - [t] de stand van de beweging, 0 tot 1; op 1 staat alles in rust.
/// - [sterk] 1 voor de volle beweging, kleiner voor de beweging bij aanwijzen.
/// - [doorlopend] de lus van Mijn downloads (de pijl valt telkens opnieuw in het bakje).
///
/// Publiek voor de toets, die nagaat dat elke beweging op t = 0 en t = 1 hetzelfde beeld geeft.
class MenuIcoonSchilder extends CustomPainter {
  MenuIcoonSchilder({
    required this.soort,
    required this.kleur,
    this.vul = 0,
    this.t = 1,
    this.sterk = 1,
    this.doorlopend = false,
  });

  final MenuIcoonSoort soort;
  final Color kleur;
  final double vul, t, sterk;
  final bool doorlopend;

  static const _lijnDikte = 1.8;

  late final Paint _lijn = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _lijnDikte
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..color = kleur;

  Paint get _vlak => Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..color = kleur.withValues(alpha: kleur.a * vul);

  /// Een detail: als lijn zolang het icoon leeg is, als uitsparing als het vol is.
  void _detail(Canvas c, Path p, {double dikte = 1.5, bool vullen = false}) {
    if (vul < 1) {
      c.drawPath(
          p,
          Paint()
            ..style = vullen ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = dikte
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = kleur.withValues(alpha: kleur.a * (1 - vul)));
    }
    if (vul > 0) {
      c.drawPath(
          p,
          Paint()
            ..style = vullen ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = dikte
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..blendMode = BlendMode.dstOut
            ..color = Color.fromRGBO(0, 0, 0, vul));
    }
  }

  /// Een uitsparing die er alleen is als het icoon vol is (het gat van de cd, de deuropening).
  void _snij(Canvas c, Path p) {
    if (vul <= 0) return;
    c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.fill
          ..blendMode = BlendMode.dstOut
          ..color = Color.fromRGBO(0, 0, 0, vul));
  }

  /// Een vorm: vol (met [vul]) en omlijnd.
  void _vorm(Canvas c, Path p, {bool vullen = true}) {
    if (vullen && vul > 0) c.drawPath(p, _vlak);
    c.drawPath(p, _lijn);
  }

  /// Een bult van 0 naar 1 en terug tussen [a] en [b].
  static double _bult(double t, double a, double b) {
    if (t <= a || t >= b) return 0;
    return math.sin(math.pi * (t - a) / (b - a));
  }

  /// Een gedempte slinger die op 0 begint en op t = 1 stilstaat.
  static double _slinger(double t, {double slagen = 2}) =>
      math.sin(t * math.pi * 2 * slagen) * math.pow(1 - t, 1.6).toDouble();

  void _draai(Canvas c, Offset om, double hoek) {
    if (hoek == 0) return;
    c.translate(om.dx, om.dy);
    c.rotate(hoek);
    c.translate(-om.dx, -om.dy);
  }

  void _schaal(Canvas c, Offset om, double sx, [double? sy]) {
    c.translate(om.dx, om.dy);
    c.scale(sx, sy ?? sx);
    c.translate(-om.dx, -om.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    // Eén laag, zodat de uitsparingen (BlendMode.dstOut) alleen dit icoon raken.
    canvas.saveLayer(const Rect.fromLTWH(-4, -6, 32, 34), Paint());
    final rust = t >= 1 && !doorlopend;
    final s = rust ? 0.0 : sterk;
    switch (soort) {
      case MenuIcoonSoort.zoeken:
        _zoeken(canvas, s);
      case MenuIcoonSoort.start:
        _start(canvas, s);
      case MenuIcoonSoort.albums:
        _albums(canvas, s);
      case MenuIcoonSoort.tracks:
        _tracks(canvas, s);
      case MenuIcoonSoort.artiesten:
        _artiesten(canvas, s);
      case MenuIcoonSoort.online:
        _online(canvas, s);
      case MenuIcoonSoort.ontdek:
        _ontdek(canvas, s);
      case MenuIcoonSoort.downloads:
        _downloads(canvas, s);
      case MenuIcoonSoort.toestel:
        _toestel(canvas, s);
      case MenuIcoonSoort.favorieten:
        _favorieten(canvas, s);
      case MenuIcoonSoort.afspeellijsten:
        _afspeellijsten(canvas, s);
      case MenuIcoonSoort.kwaliteit:
        _kwaliteit(canvas, s);
      case MenuIcoonSoort.instellingen:
        _instellingen(canvas, s);
    }
    canvas.restore();
    canvas.restore();
  }

  // ── De iconen ────────────────────────────────────────────────────────────────────────────────

  void _zoeken(Canvas c, double s) {
    const midden = Offset(10.6, 10.6);
    c.save();
    _draai(c, midden, s * .32 * _slinger(t, slagen: 1.5));
    final glas = Path()..addOval(Rect.fromCircle(center: midden, radius: 6.6));
    if (vul > 0) {
      c.drawPath(glas, Paint()..color = kleur.withValues(alpha: kleur.a * vul * .35));
    }
    c.drawPath(glas, _lijn);
    c.drawLine(const Offset(15.5, 15.5), const Offset(20.2, 20.2), _lijn..strokeWidth = 2.3);
    _lijn.strokeWidth = _lijnDikte;
    c.restore();
  }

  void _start(Canvas c, double s) {
    final huis = Path()
      ..moveTo(4, 10.4)
      ..lineTo(12, 3.9)
      ..lineTo(20, 10.4)
      ..lineTo(20, 18.9)
      ..quadraticBezierTo(20, 20.5, 18.4, 20.5)
      ..lineTo(5.6, 20.5)
      ..quadraticBezierTo(4, 20.5, 4, 18.9)
      ..close();
    _vorm(c, huis);
    // Het deurtje, met het scharnier links: open = smaller.
    const deur = Rect.fromLTRB(9.8, 14, 14.2, 20.5);
    final open = s * _bult(t, 0, 1) * .78;
    final paneel = Rect.fromLTRB(deur.left, deur.top, deur.left + deur.width * (1 - open), deur.bottom);
    if (open > 0) {
      // De opening achter het paneel: uitgespaard als het huis vol is, een lijn als het leeg is.
      final gat = Rect.fromLTRB(paneel.right, deur.top, deur.right, deur.bottom);
      _snij(c, Path()..addRect(gat));
    }
    _detail(c, Path()..addRect(paneel), dikte: 1.4);
  }

  void _albums(Canvas c, double s) {
    const midden = Offset(12, 12);
    final schijf = Path()..addOval(Rect.fromCircle(center: midden, radius: 8.8));
    _vorm(c, schijf);
    c.save();
    // Eén slag met een tikje voorbij, en terug: easeOutBack eindigt precies op een hele slag.
    // Bij aanwijzen een zwaai heen en terug; met ,6 was die op de filmstrook niet te zien.
    final hoek = s == 0 ? 0.0 : s >= 1 ? Curves.easeOutBack.transform(t) * math.pi * 2 : s * 1.5 * _slinger(t, slagen: 1);
    _draai(c, midden, hoek);
    final groef = Path()..addArc(Rect.fromCircle(center: midden, radius: 5.6), -2.2, 1.25);
    _detail(c, groef, dikte: 1.4);
    c.restore();
    final gat = Path()..addOval(Rect.fromCircle(center: midden, radius: 2.3));
    _snij(c, gat);
    _detail(c, gat, dikte: 1.4);
  }

  void _tracks(Canvas c, double s) {
    c.save();
    final sprong = s * _bult(t, 0, .7) * 3.6;
    // Een klein inveren bij het landen.
    final veer = s * _bult(t, .62, 1) * .12;
    c.translate(0, -sprong);
    _schaal(c, const Offset(11, 20.5), 1 + veer * .6, 1 - veer);
    final kop = Path()
      ..addOval(Rect.fromCenter(center: const Offset(8.6, 17.2), width: 6.2, height: 5));
    _vorm(c, kop.transform(Matrix4Waarden.draai(-.35, const Offset(8.6, 17.2))));
    c.drawLine(const Offset(11.5, 16.4), const Offset(11.5, 4), _lijn);
    final vlag = Path()
      ..moveTo(11.5, 4)
      ..cubicTo(14.6, 4.4, 17.3, 6.1, 17.3, 9.6);
    c.drawPath(vlag, _lijn);
    c.restore();
  }

  void _artiesten(Canvas c, double s) {
    c.save();
    _draai(c, const Offset(12, 20.5), s * .3 * _slinger(t, slagen: 1.5));
    final kop = Path()..addRRect(RRect.fromLTRBR(9, 2.8, 15, 13.2, const Radius.circular(3)));
    _vorm(c, kop);
    _detail(c, Path()..moveTo(10.6, 6.6)..lineTo(13.4, 6.6), dikte: 1.2);
    _detail(c, Path()..moveTo(10.6, 9.2)..lineTo(13.4, 9.2), dikte: 1.2);
    final houder = Path()..addArc(Rect.fromCircle(center: const Offset(12, 10.6), radius: 6.1), 0, math.pi);
    c.drawPath(houder, _lijn);
    c.drawLine(const Offset(12, 16.7), const Offset(12, 20.5), _lijn);
    c.drawLine(const Offset(8.6, 20.5), const Offset(15.4, 20.5), _lijn);
    c.restore();
  }

  void _online(Canvas c, double s) {
    const midden = Offset(12, 12);
    const r = 8.8;
    final bol = Path()..addOval(Rect.fromCircle(center: midden, radius: r));
    _vorm(c, bol);
    // Drie meridianen, zestig graden uit elkaar; een draai van zestig graden geeft hetzelfde beeld,
    // dus de slag eindigt precies waar hij begon.
    final fase = s == 0 ? 0.0 : Curves.easeInOutCubic.transform(t) * (math.pi / 3);
    c.save();
    c.clipPath(bol);
    for (var k = 0; k < 3; k++) {
      final l = fase + k * math.pi / 3;
      final rx = (r * math.sin(l)).abs();
      if (rx < .25) {
        _detail(c, Path()..moveTo(12, 12 - r)..lineTo(12, 12 + r), dikte: 1.3);
      } else {
        _detail(c, Path()..addOval(Rect.fromCenter(center: midden, width: rx * 2, height: r * 2)), dikte: 1.3);
      }
    }
    _detail(c, Path()..moveTo(12 - r + 1, 12)..lineTo(12 + r - 1, 12), dikte: 1.3);
    c.restore();
    if (vul < 1) c.drawPath(bol, _lijn);
  }

  void _ontdek(Canvas c, double s) {
    const midden = Offset(12, 12);
    final rand = Path()..addOval(Rect.fromCircle(center: midden, radius: 8.8));
    _vorm(c, rand);
    final hoek = math.pi / 4 + s * 1.1 * _slinger(t, slagen: 2.2);
    final naald = Path()
      ..moveTo(12, 6.2)
      ..lineTo(14, 12)
      ..lineTo(12, 17.8)
      ..lineTo(10, 12)
      ..close();
    final noord = Path()
      ..moveTo(12, 6.2)
      ..lineTo(14, 12)
      ..lineTo(10, 12)
      ..close();
    final m = Matrix4Waarden.draai(hoek, midden);
    _detail(c, naald.transform(m), dikte: 1.3);
    _detail(c, noord.transform(m), vullen: true, dikte: 0);
  }

  void _downloads(Canvas c, double s) {
    final bak = Path()
      ..moveTo(4.5, 14.6)
      ..lineTo(4.5, 18)
      ..quadraticBezierTo(4.5, 20, 6.5, 20)
      ..lineTo(17.5, 20)
      ..quadraticBezierTo(19.5, 20, 19.5, 18)
      ..lineTo(19.5, 14.6);
    if (vul > 0) {
      c.drawPath(
          Path()
            ..addPath(bak, Offset.zero)
            ..close(),
          _vlak);
    }
    c.drawPath(bak, _lijn);
    // De pijl valt van boven in het bakje. In de lus valt hij telkens opnieuw, en verdwijnt hij
    // in het bakje (knip op de bovenrand ervan).
    double val;
    double dek = 1;
    if (doorlopend) {
      val = -8 + t * 13;
      dek = (t < .15 ? t / .15 : 1).toDouble();
    } else if (s == 0) {
      val = 0;
    } else {
      // Van boven, met een klein stuitje op de bodem.
      final v = Curves.bounceOut.transform(t);
      val = -7 * s * (1 - v);
      // Niet vanaf niets: op 0 verdween de pijl een beeld lang helemaal, een knipper op het moment
      // van klikken (filmstrook 17-10-2026).
      dek = (t < .2 ? .3 + .7 * t / .2 : 1).toDouble();
    }
    c.save();
    if (doorlopend) c.clipRect(const Rect.fromLTRB(-4, -6, 28, 15.4));
    c.translate(0, val);
    final pijl = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lijnDikte + vul * .4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = kleur.withValues(alpha: kleur.a * dek);
    c.drawLine(const Offset(12, 3.8), const Offset(12, 14), pijl);
    c.drawPath(
        Path()
          ..moveTo(8.2, 10.4)
          ..lineTo(12, 14.2)
          ..lineTo(15.8, 10.4),
        pijl);
    c.restore();
  }

  void _toestel(Canvas c, double s) {
    final toestel = Path()..addRRect(RRect.fromLTRBR(6.8, 2.5, 17.2, 21.5, const Radius.circular(2.6)));
    _vorm(c, toestel);
    _detail(c, Path()..moveTo(10.6, 5.3)..lineTo(13.4, 5.3), dikte: 1.3);
    final vinkje = Path()
      ..moveTo(9.3, 12.7)
      ..lineTo(11.4, 14.8)
      ..lineTo(14.9, 10.9);
    // Het vinkje tekent zich bij het kiezen; in rust staat het er helemaal.
    final deel = s == 0 ? 1.0 : (1 - s) + s * Curves.easeOut.transform((t / .8).clamp(0.0, 1.0));
    final stuk = Path();
    for (final m in vinkje.computeMetrics()) {
      stuk.addPath(m.extractPath(0, m.length * deel), Offset.zero);
    }
    _detail(c, stuk, dikte: 1.7);
  }

  void _favorieten(Canvas c, double s) {
    final hart = Path()
      ..moveTo(12, 7.1)
      ..cubicTo(10.9, 5.3, 9.3, 4.5, 7.8, 4.5)
      ..cubicTo(5.3, 4.5, 3.5, 6.5, 3.5, 9)
      ..cubicTo(3.5, 13.3, 8.2, 16.7, 12, 19.8)
      ..cubicTo(15.8, 16.7, 20.5, 13.3, 20.5, 9)
      ..cubicTo(20.5, 6.5, 18.7, 4.5, 16.2, 4.5)
      ..cubicTo(14.7, 4.5, 13.1, 5.3, 12, 7.1)
      ..close();
    final klop = s * (.2 * _bult(t, 0, .36) + .14 * _bult(t, .42, .78));
    c.save();
    _schaal(c, const Offset(12, 12.5), 1 + klop);
    _vorm(c, hart);
    c.restore();
  }

  void _afspeellijsten(Canvas c, double s) {
    const regels = <(double, double)>[(6.5, 13.2), (11, 13.2), (15.5, 9.8)];
    for (var i = 0; i < regels.length; i++) {
      final (y, eind) = regels[i];
      double schuif = 0;
      double dek = 1;
      if (s > 0) {
        final e = Curves.easeOutCubic.transform(((t - i * .14) / .5).clamp(0.0, 1.0));
        schuif = -7 * s * (1 - e);
        // Hoogstens tot een kwart: helemaal weg was een knipper bij het klikken.
        dek = 1 - s * .75 * (1 - e);
      }
      c.drawLine(Offset(3.5 + schuif, y), Offset(eind + schuif, y),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _lijnDikte
            ..strokeCap = StrokeCap.round
            ..color = kleur.withValues(alpha: kleur.a * dek));
    }
    c.drawLine(const Offset(18.8, 16.2), const Offset(18.8, 5.2), _lijn);
    c.drawLine(const Offset(18.8, 5.2), const Offset(21, 6.4), _lijn);
    final kop = Path()..addOval(Rect.fromCircle(center: const Offset(16.7, 16.6), radius: 2.2));
    _vorm(c, kop);
  }

  Path _ster(Offset m, double r, double binnen) => Path()
    ..moveTo(m.dx, m.dy - r)
    ..quadraticBezierTo(m.dx + binnen, m.dy - binnen, m.dx + r, m.dy)
    ..quadraticBezierTo(m.dx + binnen, m.dy + binnen, m.dx, m.dy + r)
    ..quadraticBezierTo(m.dx - binnen, m.dy + binnen, m.dx - r, m.dy)
    ..quadraticBezierTo(m.dx - binnen, m.dy - binnen, m.dx, m.dy - r)
    ..close();

  void _kwaliteit(Canvas c, double s) {
    const midden = Offset(11, 13);
    const sterretje = Offset(18.8, 5.2);
    c.save();
    // Fonkelen: de grote ster zwelt even op en wiebelt, gedempt tot precies stil.
    //
    // Geen kwartslag meer. Die eindigde wel waar hij begon, maar halverwege (45°) las een vierpuntige
    // ster als een ingedeukt vierkant, en kwam zijn punt rechtsboven precies op het kleine sterretje:
    // één blok, op de filmstrook van 17-10-2026 van 250 tot 450 ms. Met hoogstens ~17° en 1,16 keer
    // blijft er een gat van zo'n 5 punten tussen de twee.
    final f = s * _bult(t, 0, .8);
    _schaal(c, midden, 1 + .16 * f);
    _draai(c, midden, s * .3 * _slinger(t, slagen: 1.2));
    _vorm(c, _ster(midden, 7.6, 1.5));
    c.restore();
    // Het kleine sterretje dooft even, springt dan op en maakt een kwartslag (klein en los genoeg).
    final klein = Path()..addPath(_ster(sterretje, 2.7, .6), Offset.zero);
    final knipper = 1 - s * .75 * _bult(t, .05, .4);
    c.save();
    _schaal(c, sterretje, 1 + s * .45 * _bult(t, .3, .9));
    _draai(c, sterretje, s == 0 ? 0 : Curves.easeInOutCubic.transform(((t - .25) / .65).clamp(0.0, 1.0)) * math.pi / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..color = kleur.withValues(alpha: kleur.a * knipper);
    if (vul > 0) {
      c.drawPath(klein, Paint()..color = kleur.withValues(alpha: kleur.a * vul * knipper));
    }
    c.drawPath(klein, p);
    c.restore();
  }

  void _instellingen(Canvas c, double s) {
    const midden = Offset(12, 12);
    final tand = math.pi / 4;
    // Een halve slag is vier tanden: precies hetzelfde beeld. Bij aanwijzen één tand.
    final hoek = s == 0 ? 0.0 : Curves.easeInOutCubic.transform(t) * (s >= 1 ? math.pi : tand);
    final wiel = Path();
    for (var k = 0; k < 8; k++) {
      final m = k * tand;
      final punten = [
        (m - .40, 6.9),
        (m - .2, 9.3),
        (m + .2, 9.3),
        (m + .40, 6.9),
      ];
      for (var i = 0; i < punten.length; i++) {
        final (a, r) = punten[i];
        final p = Offset(midden.dx + r * math.cos(a), midden.dy + r * math.sin(a));
        if (k == 0 && i == 0) {
          wiel.moveTo(p.dx, p.dy);
        } else {
          wiel.lineTo(p.dx, p.dy);
        }
      }
    }
    wiel.close();
    c.save();
    _draai(c, midden, hoek);
    _vorm(c, wiel);
    c.restore();
    final gat = Path()..addOval(Rect.fromCircle(center: midden, radius: 2.9));
    _snij(c, gat);
    _detail(c, gat, dikte: 1.5);
  }

  @override
  bool shouldRepaint(MenuIcoonSchilder oud) =>
      oud.soort != soort ||
      oud.kleur != kleur ||
      oud.vul != vul ||
      oud.t != t ||
      oud.sterk != sterk ||
      oud.doorlopend != doorlopend;
}

/// Kleine hulp voor een draaimatrix om een punt, als `Float64List` voor [Path.transform].
abstract final class Matrix4Waarden {
  static Float64List draai(double hoek, Offset om) {
    final c = math.cos(hoek), s = math.sin(hoek);
    // Kolom-groot, zoals Matrix4: x' = c·x − s·y + tx, y' = s·x + c·y + ty.
    final tx = om.dx - c * om.dx + s * om.dy;
    final ty = om.dy - s * om.dx - c * om.dy;
    return Float64List.fromList([
      c, s, 0, 0, //
      -s, c, 0, 0, //
      0, 0, 1, 0, //
      tx, ty, 0, 1,
    ]);
  }
}
