/// Een hoes die een tikje kantelt, met een glans erover, en een spiegeling eronder (Saber, 18-10-2026).
///
/// **Wanneer hij kantelt.** Op de pc en de Mac volgt hij de muis zolang die op de hoes staat; op een
/// tv staat de geselecteerde hoes schuin met het licht linksboven; op een gsm en een iPad alleen de
/// grote hoes in Nu speelt, met de beweging van het toestel. Nooit meer dan [kKantelHoek] (±6°): meer
/// wordt een kaartje dat wiebelt in plaats van een plaat die het licht vangt.
///
/// **Wat het kost.** In rust niets: geen transform, geen glans, geen luisteraar die om beelden vraagt.
/// Kantelt hij, dan beweegt er alleen een transform over een al getekende hoes ([RepaintBoundary]) en
/// een verloop erover. De bewegingsmelder van een telefoon luistert alleen zolang Nu speelt open is
/// en de app voor staat, en vraagt alleen een nieuw beeld als de hoek echt verandert.
///
/// **Minder beweging** (de systeeminstelling): dan kantelt er niets.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../meetronde.dart' show zonderVoorMeting;
import 'tegel_spiegel.dart' show TegelSpiegel;

/// Hoe ver een hoes hooguit kantelt, in radialen: zes graden.
const double kKantelHoek = 6 * math.pi / 180;

/// Hoe snel hij een nieuwe stand volgt.
const Duration kKantelVolg = Duration(milliseconds: 160);

/// Hoe lang er minstens tussen twee standen van het toestel zit: 33 ms, hooguit 30 per seconde.
const Duration kToestelStap = Duration(milliseconds: 33);

/// Hoe ver een telefoon moet kantelen (als deel van de zwaartekracht, ≈ sin van de hoek) voor de
/// volle zes graden van de hoes: tien graden toestel is zes graden hoes.
const double kToestelVol = .17;

/// De zwaartekracht zoals het toestel hem voelt, in g (x naar rechts, y naar boven), ongeveer zestig
/// keer per seconde. Op een pc of tv zonder bewegingsmelder: een fout, en wie luistert stopt dan.
Stream<Offset> toestelZwaartekracht() =>
    accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).map((e) => Offset(e.x / 9.81, e.y / 9.81));

/// Waar de kanteling vandaan komt.
enum KantelBron {
  /// De muis op de hoes (pc, Mac, een iPad met een muis).
  muis,

  /// De selectie op een tv: dan staat hij vast schuin.
  selectie,

  /// De beweging van het toestel (gsm, iPad): alleen de grote hoes in Nu speelt.
  toestel,
}

/// De stand van een tv-hoes met de selectie: licht naar rechtsonder gekanteld, het licht linksboven.
const Offset kKantelSelectie = Offset(-.55, -.45);

/// De transform voor een stand [o] (elk van -1 tot 1): de kant waar de muis staat wijkt een tikje
/// terug, zoals een plaat die je met je vinger aanraakt.
@visibleForTesting
Matrix4 kantelMatrix(Offset o) => Matrix4.identity()
  ..setEntry(3, 2, .0011)
  ..rotateX(-o.dy * kKantelHoek)
  ..rotateY(o.dx * kKantelHoek);

class KantelHoes extends StatefulWidget {
  const KantelHoes({
    super.key,
    required this.child,
    this.bron = KantelBron.muis,
    this.aan = false,
    this.vorm = BorderRadius.zero,
  });

  final Widget child;
  final KantelBron bron;

  /// Voor [KantelBron.selectie]: heeft hij de selectie?
  final bool aan;

  /// De ronding van de hoes: de glans blijft erbinnen.
  final BorderRadius vorm;

  /// In een toets: een eigen bewegingsmelder in plaats van die van het toestel (x, y in g).
  @visibleForTesting
  static Stream<Offset> Function()? toestelVoorToets;

  static final _staten = <_KantelHoesState>{};

  /// Waar de grootste kantelhoes nu staat (globaal), of null: de meetronde beweegt daar de muis over (zie
  /// `meetronde.dart`). In Nu speelt is dat de grote hoes.
  static Rect? grootsteVak() {
    Rect? beste;
    for (final s in _staten) {
      final box = s.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final vak = box.localToGlobal(Offset.zero) & box.size;
      if (beste == null || vak.width * vak.height > beste.width * beste.height) beste = vak;
    }
    return beste;
  }

  @override
  State<KantelHoes> createState() => _KantelHoesState();
}

class _KantelHoesState extends State<KantelHoes> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _c = AnimationController(vsync: this, duration: kKantelVolg);
  Offset _van = Offset.zero, _naar = Offset.zero;
  StreamSubscription<Offset>? _melder;

  /// Hoe je het toestel vasthoudt, langzaam bijgehouden: dat is de rust. Kantelen ERVAN kantelt de hoes.
  Offset? _rust;

  /// De melding glad gemaakt: een hand trilt, en zonder dit liep er in een stille hand elke melding
  /// een nieuwe beweging (en dus elk beeld een nieuw beeld).
  Offset? _glad;

  Offset get _stand => Offset.lerp(_van, _naar, Curves.easeOut.transform(_c.value))!;

  bool _mag(BuildContext context) => !MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    KantelHoes._staten.add(this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _zetMelder();
    _zetSelectie();
  }

  @override
  void didUpdateWidget(KantelHoes oud) {
    super.didUpdateWidget(oud);
    if (oud.bron != widget.bron) _zetMelder();
    if (oud.aan != widget.aan || oud.bron != widget.bron) _zetSelectie();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => _zetMelder();

  @override
  void dispose() {
    KantelHoes._staten.remove(this);
    WidgetsBinding.instance.removeObserver(this);
    _melder?.cancel();
    _wachtToestel?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _naarStand(Offset doel) {
    if (!_mag(context)) doel = Offset.zero;
    // Een kleine stap niet volgen: van het toestel pas vanaf ruim een vijfde graad, van de muis en de
    // selectie vanaf een honderdste.
    final drempel = widget.bron == KantelBron.toestel ? .035 : .01;
    if ((doel - _naar).distance < drempel && doel != Offset.zero) return;
    if (doel == _naar) return;
    _van = _stand;
    _naar = doel;
    _c.forward(from: 0);
  }

  void _zetSelectie() {
    if (widget.bron != KantelBron.selectie) return;
    _naarStand(widget.aan ? kKantelSelectie : Offset.zero);
  }

  void _zetMelder() {
    final wil = widget.bron == KantelBron.toestel &&
        _mag(context) &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden;
    if (!wil) {
      _melder?.cancel();
      _melder = null;
      _rust = _glad = null;
      if (widget.bron == KantelBron.toestel) _naarStand(Offset.zero);
      return;
    }
    if (_melder != null) return;
    final bron = KantelHoes.toestelVoorToets?.call() ?? toestelZwaartekracht();
    _melder = bron.listen(_opToestel, onError: (Object _) {
      // Geen bewegingsmelder (een pc, een tv, een toets): dan kantelt hij gewoon niet.
      _melder?.cancel();
      _melder = null;
    }, cancelOnError: true);
  }

  void _opToestel(Offset ruw) {
    final g = _glad = _glad == null ? ruw : Offset.lerp(_glad, ruw, .15)!;
    // De rust volgt traag (ongeveer een seconde): hoe je hem vasthoudt is geen kanteling.
    final r = _rust == null ? g : Offset.lerp(_rust, g, .03)!;
    _rust = r;
    final d = g - r;
    // Op een telefoon is x naar rechts en y naar boven; links kantelen = de linkerkant zakt.
    _zetToestel(Offset((-d.dx / kToestelVol).clamp(-1.0, 1.0), (d.dy / kToestelVol).clamp(-1.0, 1.0)));
  }

  /// Een nieuwe stand van het toestel: meteen, zonder animatie (de melding is al glad), en hooguit
  /// [kToestelStap] keer per seconde. Met een animatie per melding tekende Nu speelt 120 beelden per
  /// seconde zolang de gsm in de hand lag (fps.log, 18-10-2026) — de cd ernaast doet er 60.
  void _zetToestel(Offset doel) {
    if (!_mag(context)) doel = Offset.zero;
    if (_wachtToestel != null) {
      _volgendeToestel = doel;
      return;
    }
    if ((doel - _naar).distance < .035 && doel != Offset.zero) return;
    if (doel == _naar && _c.value == 1) return;
    _van = doel;
    _naar = doel;
    _c.value = 1;
    _wachtToestel = Timer(kToestelStap, () {
      _wachtToestel = null;
      final v = _volgendeToestel;
      _volgendeToestel = null;
      if (v != null && mounted) _zetToestel(v);
    });
  }

  Timer? _wachtToestel;
  Offset? _volgendeToestel;

  void _opMuis(PointerEvent e, Size maat) {
    if (maat.isEmpty) return;
    final p = e.localPosition;
    _naarStand(Offset(((p.dx / maat.width) * 2 - 1).clamp(-1.0, 1.0), ((p.dy / maat.height) * 2 - 1).clamp(-1.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    // Een meetronde zonder kantelen (zie `meetronde.dart`): de hoes zoals hij is.
    if (zonderVoorMeting('kantel')) return widget.child;
    final kind = RepaintBoundary(child: widget.child);
    final getekend = AnimatedBuilder(
      animation: _c,
      child: kind,
      builder: (context, kind) {
        final o = _stand;
        // In rust een rechte transform en geen glans — maar altijd DEZELFDE vorm: wisselde die tussen
        // "kaal" en "Transform met Stack", dan werd de hoes eronder (met zijn draai, zijn Hero en zijn
        // beeld) bij elke beweging van de gsm weggegooid en opnieuw gebouwd (18-10-2026).
        final rust = o.distance < .002;
        return Transform(
          alignment: Alignment.center,
          transform: rust ? Matrix4.identity() : kantelMatrix(o),
          child: Stack(fit: StackFit.passthrough, children: [
            kind!,
            if (!rust)
              Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: widget.vorm,
                  child: CustomPaint(key: const ValueKey('kantel-glans'), painter: KantelGlans(o)),
                ),
              ),
            ),
          ]),
        );
      },
    );
    if (widget.bron != KantelBron.muis) return getekend;
    return LayoutBuilder(builder: (context, c) {
      final maat = Size(c.maxWidth, c.maxHeight);
      return MouseRegion(
        onHover: (e) => _opMuis(e, context.size ?? maat),
        onExit: (_) => _naarStand(Offset.zero),
        child: getekend,
      );
    });
  }
}

/// De glans over een gekantelde hoes: een zachte vlek licht waar hij naar je toe kantelt, en een
/// smalle veeg erdoorheen. Hoe schuiner, hoe feller (tot 24 %).
class KantelGlans extends CustomPainter {
  KantelGlans(this.o);
  final Offset o;

  @override
  void paint(Canvas canvas, Size size) {
    final sterkte = (o.distance / math.sqrt2).clamp(0.0, 1.0);
    // Het licht staat tegenover de kant die wegzakt.
    final midden = Alignment(-o.dx * .9, -o.dy * .9);
    final vak = Offset.zero & size;
    canvas.drawRect(
        vak,
        Paint()
          ..shader = RadialGradient(
            center: midden,
            radius: .85,
            colors: [Color.fromRGBO(255, 255, 255, .24 * sterkte), const Color(0x00FFFFFF)],
          ).createShader(vak));
    canvas.drawRect(
        vak,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment(-1 + o.dx * .6, -1),
            end: Alignment(1 + o.dx * .6, 1),
            colors: [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, .10 * sterkte), const Color(0x00FFFFFF)],
            stops: const [.38, .5, .62],
          ).createShader(vak));
  }

  @override
  bool shouldRepaint(KantelGlans oud) => oud.o != o;
}

/// Hoe hoog de spiegeling onder een grote hoes is, als deel van de hoes.
const double kSpiegelHoogte = .22;

/// Hoe ver hij onder de hoes begint.
const double kSpiegelAfstand = 6;


/// De spiegeling onder de grote hoes in Nu speelt en op de albumpagina: de onderkant van de hoes,
/// omgekeerd, van 20 % naar niets. Alleen de voorkant: een cd die draait wordt niet gespiegeld (dat
/// zou hem twee keer per beeld laten tekenen).
///
/// **Getekend zoals onder de tegels ([TegelSpiegel]), in stroken.** Hier stond een `ShaderMask` met
/// een verloop over het hele vak, en onderaan bleef een harde streep staan: de laag van het masker is
/// op de pixel afgerond groter dan het verloop, en die laatste rij hoes kreeg geen masker (Saber, gsm,
/// 19-10-2026: "die streep mag er niet zijn, moet mooi overvloeien zonder brute stop"). De stroken
/// zijn op 92 % van de hoogte al niets, dus de onderrand van het vak tekent nooit iets.
class HoesSpiegel extends StatelessWidget {
  const HoesSpiegel({super.key, required this.beeld, required this.maat});

  final Uint8List beeld;
  final double maat;

  @override
  Widget build(BuildContext context) => zonderVoorMeting('spiegel')
      ? const SizedBox.shrink()
      : IgnorePointer(
        // Een eigen laag: de cd die ernaast draait, tekent deze spiegeling niet opnieuw.
        child: RepaintBoundary(
          child: SizedBox(
            key: const ValueKey('hoes-spiegel'),
            width: maat,
            height: maat * kSpiegelHoogte,
            // Dezelfde bron als de hoes erboven (AlbumArt: `Image.memory(front, cacheWidth:
            // decodeWidth(s))`), dus geen tweede decodering. De afronding van de grote hoes is 10.
            child: TegelSpiegel(bron: MemoryImage(beeld), maat: maat, hoek: 10),
          ),
        ),
      );
}
