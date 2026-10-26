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
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase, Ticker;
import 'package:sensors_plus/sensors_plus.dart';

import '../meetronde.dart' show zonderVoorMeting;
import '../paths.dart' show appFile;
import 'tegel_spiegel.dart' show TegelSpiegel;

/// De hoes stilzetten: dan beweegt hij niet meer met het toestel (Saber, 26-10-2026: "de tilt van de album kunnen
/// lokken, want zeker met de gsm en ik rijd met de auto of camionette, beweegt die hoes constant"). Per toestel, in
/// `kantelen.json`; alleen voor [KantelBron.toestel] — de muis en de tv-selectie kantelen alleen als jij het doet.
/// Vast = ook geen bewegingsmelder meer.
class KantelKeuze {
  KantelKeuze._();
  static final vast = ValueNotifier<bool>(false);
  static File get _bestand => appFile('kantelen.json');

  static void laad() {
    try {
      final j = jsonDecode(_bestand.readAsStringSync());
      if (j is Map && j['vast'] is bool) vast.value = j['vast'] as bool;
    } catch (_) {/* geen bestand: hij beweegt mee */}
  }

  static Future<void> zet(bool ja) async {
    vast.value = ja;
    try {
      await _bestand.writeAsString(jsonEncode({'vast': ja}));
    } catch (_) {/* niet bewaard: hij geldt nu wel */}
  }
}

/// Hoe ver een hoes hooguit kantelt, in radialen: zes graden.
const double kKantelHoek = 6 * math.pi / 180;

/// Hoe snel hij een nieuwe stand volgt: na deze tijd is hij er (op een honderdste na).
const Duration kKantelVolg = Duration(milliseconds: 160);

/// De muis volgen ([KantelBron.muis]): bij elk beeld een vast deel van de rest, met deze tijdconstante — een vijfde van
/// [kKantelVolg], dus na [kKantelVolg] is er minder dan een procent over.
///
/// **Waarom geen animatie per muisbeweging meer (Saber, 23-10-2026: "de cover tilt op pc is trouwens ook niet
/// vloeiend").** Elke beweging startte een animatie van [kKantelVolg] opnieuw vanaf nul. Een muis meldt zich 125 tot
/// 1000 keer per seconde, dus vóór bijna elk beeld: dan stond de animatie bij elk beeld weer op nul en kroop de hoes
/// nauwelijks mee zolang je bewoog — om bij te springen zodra je stilhield. De pc tekende het in 1,4 ms per beeld
/// (meetronde, 23-10-2026); het haperen zat in de beweging, niet in het tekenen. Nu volgt hij per beeld, op de tijd die
/// verstreek, hoe vaak de muis zich ook meldt.
double get kKantelMuisTauUs => kKantelVolg.inMicroseconds / 5;

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

/// De transform voor een stand [o] (elk van -1 tot 1): de kant in de richting van [o] komt een tikje naar je toe, de
/// overkant zakt weg. Nagerekend op 26-10-2026 (de hoeken van een hoes van 300 bij o = (1, 0)): de rechterrand wordt 305
/// punten hoog, de linker 295 — hier stond dat de kant van de muis terugwijkt. Ook voor de cd die in de hoes zit
/// ([KantelHoes.deel]).
///
/// **Eerst plat** (de laatste vermenigvuldiging, die als eerste op de hoes werkt): Flutter maakt een transform niet plat,
/// dus de diepte van een hoes die erin omdraait ([DraaiHoes]) kwam onder deze perspectief van .0011 terecht — bij de
/// grote hoes van Nu speelt vier keer de diepte van de draai zelf. Opgenomen op de pc met 3.9.627 (Saber, 25-10-2026:
/// "test ook draaien van de hoes op pc"): wie dubbelklikt heeft de muis op de hoes, en de rand die naar je toe kwam werd
/// 1,7 keer zo hoog als de andere. Een platte hoes verandert er niets door.
///
/// **Bijna plat, niet helemaal** ([kKantelPlat]): met z op nul is de determinant 0, en dan tekent Flutter het kind niet
/// (RenderTransform.paint). Zo was de grote hoes in 3.9.628 zwart zodra de muis erop stond — de toets keek alleen naar
/// de matrix. Een honderdste laat van de diepte van de draai een honderdste over, en de hoes wordt getekend.
Matrix4 kantelMatrix(Offset o) => Matrix4.identity()
  ..setEntry(3, 2, .0011)
  ..rotateX(-o.dy * kKantelHoek)
  ..rotateY(o.dx * kKantelHoek)
  ..multiply(Matrix4.diagonal3Values(1, 1, kKantelPlat));

/// Hoeveel van de diepte van wat erin draait de kanteling overhoudt: genoeg om getekend te worden, te weinig om te zien.
const double kKantelPlat = .01;

/// Hoe hoog de hoes boven de wand zweeft, gemeten aan zijn schaduw: die valt 22 punten onder hem (de schaduw van de
/// grote hoes in Nu speelt).
const double kKantelSchaduwHoogte = 22;

/// Hoeveel die hoogte verschilt tussen de twee randen bij de volle kanteling, als deel ervan. Gerekend: zes graden over
/// een halve hoes van 175 punten is 18 punten dichterbij of verder, op 22 — ruim vier vijfde.
const double kKantelSchaduwDiepte = .8;

/// De schaduw van een gekantelde hoes op de wand erachter (Saber, 26-10-2026: "als ik tilt, gaat de schaduw en
/// reflectie niet mee. Moet realistisch zijn … een reflectie en schaduw die bewegen anders dan de hoes en cd").
///
/// De schaduw ligt OP de wand: hij kantelt niet mee in de diepte (geen perspectief). Hij schuift wel. Het licht komt van
/// boven, dus valt elke plek van de hoes zijn hoogte boven de wand naar onder. De kant die naar je toe komt (die in de
/// richting van [o], zie [kantelMatrix]) zweeft verder van de wand en werpt zijn schaduw verder; de kant die wegzakt komt
/// dichter bij de wand en zijn schaduw kruipt tegen de hoes aan. Links
/// en rechts kantelen scheert de schaduw dus schuin; voorover en achterover rekt of krimpt hij in de hoogte. [hoes] is
/// het vak van de hoes in de maat van wat er getekend wordt; [o] de stand van [kantelMatrix].
Matrix4 kantelSchaduwMatrix(Offset o, Rect hoes,
    {double hoogte = kKantelSchaduwHoogte, double diepte = kKantelSchaduwDiepte}) {
  final hw = hoes.width / 2, hh = hoes.height / 2;
  if (hw <= 0 || hh <= 0) return Matrix4.identity();
  final k = hoogte * diepte;
  // y' = y + k · (o.dx · x̂ + o.dy · ŷ), met x̂ en ŷ van −1 tot 1 over de hoes.
  return Matrix4.identity()
    ..setEntry(1, 0, k * o.dx / hw)
    ..setEntry(1, 1, 1 + k * o.dy / hh)
    ..setEntry(1, 3, -k * (o.dx * hoes.center.dx / hw + o.dy * hoes.center.dy / hh));
}

/// De spiegeling van een gekantelde hoes in de vloer eronder: dezelfde draai om de staande as, de omgekeerde om de
/// liggende — zo blijft de onderrand van de hoes op zijn spiegelbeeld staan. Rond het midden van de gespiegelde hoes,
/// die net onder de vloerlijn begint ([HoesSpiegel] toont er de bovenste [kSpiegelHoogte] van).
Matrix4 spiegelKantelMatrix(Offset o) => kantelMatrix(Offset(o.dx, -o.dy));

/// [child] onder een gekantelde hoes, die meebeweegt met [stand] zoals [kantelSchaduwMatrix] (een schaduw op de wand)
/// of [spiegelKantelMatrix] (een spiegeling in de vloer). Altijd dezelfde vorm, ook in rust: wisselde die, dan werd
/// [child] bij elke beweging opnieuw gebouwd (zie [KantelHoes]).
class VolgtKanteling extends StatelessWidget {
  /// Een schaduw van de hoes in [hoes] (in de maat van [child]).
  const VolgtKanteling.schaduw({super.key, required this.stand, required Rect this.hoes, required this.child})
      : midden = null;

  /// Een spiegeling, rond [midden]: het midden van de gespiegelde hoes in de maat van [child].
  const VolgtKanteling.spiegel({super.key, required this.stand, required Offset this.midden, required this.child})
      : hoes = null;

  final ValueListenable<Offset> stand;
  final Rect? hoes;
  final Offset? midden;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: stand,
        child: child,
        builder: (context, kind) {
          final o = stand.value;
          final rust = o.distance < .002;
          final m = rust
              ? Matrix4.identity()
              : hoes != null
                  ? kantelSchaduwMatrix(o, hoes!)
                  : spiegelKantelMatrix(o);
          return Transform(transform: m, origin: hoes != null ? null : midden, child: kind);
        },
      );
}

class KantelHoes extends StatefulWidget {
  const KantelHoes({
    super.key,
    required this.child,
    this.bron = KantelBron.muis,
    this.aan = false,
    this.vorm = BorderRadius.zero,
    this.deel,
  });

  final Widget child;
  final KantelBron bron;

  /// Voor [KantelBron.selectie]: heeft hij de selectie?
  final bool aan;

  /// De ronding van de hoes: de glans blijft erbinnen.
  final BorderRadius vorm;

  /// Hier zet hij zijn stand in, voor wat in hetzelfde vlak hoort: de cd die uit de hoes steekt kantelt mee, met zijn
  /// schaduw en de glans (Saber, 25-10-2026: "bij het tilten van de hoes, zie je een verschil in kleur/licht"). Kantelde
  /// alleen de hoes, dan schoof zijn rand weg van de schaduw die hij op de cd werpt, en lag de cd plat achter een hoes
  /// in 3D.
  final ValueNotifier<Offset>? deel;

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

class _KantelHoesState extends State<KantelHoes> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _c = AnimationController(vsync: this, duration: kKantelVolg);

  /// De stand met de muis ([kKantelMuisTauUs]): waar hij nu staat, waar hij heen wil, en de klok die hem daarheen
  /// brengt.
  final _muis = ValueNotifier<Offset>(Offset.zero);
  Offset _muisDoel = Offset.zero;
  late final Ticker _volger = createTicker(_volg);
  Duration? _vorigBeeld;

  void _volg(Duration nu) {
    final vorig = _vorigBeeld;
    _vorigBeeld = nu;
    if (vorig == null) return;
    final rest = math.exp(-(nu - vorig).inMicroseconds / kKantelMuisTauUs);
    var stand = _muisDoel + (_muis.value - _muisDoel) * rest;
    if ((stand - _muisDoel).distance < .01) {
      stand = _muisDoel;
      _volger.stop();
      _vorigBeeld = null;
    }
    _muis.value = stand;
  }

  void _naarMuis(Offset doel) {
    if (!_mag(context)) doel = Offset.zero;
    _muisDoel = doel;
    if (_muis.value == doel || _volger.isActive) return;
    _vorigBeeld = null;
    _volger.start();
  }
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
    _c.addListener(_deel);
    _muis.addListener(_deel);
    KantelKeuze.vast.addListener(_zetMelder);
  }

  /// De stand doorgeven aan [KantelHoes.deel]. Niet midden in het bouwen (een stand die dan wijzigt, zou een ander deel
  /// van het scherm laten herbouwen terwijl dat al gebouwd wordt): dan net daarna.
  void _deel() {
    final d = widget.deel;
    if (d == null) return;
    final o = widget.bron == KantelBron.muis ? _muis.value : _stand;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) d.value = widget.bron == KantelBron.muis ? _muis.value : _stand;
      });
      return;
    }
    d.value = o;
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
    KantelKeuze.vast.removeListener(_zetMelder);
    _melder?.cancel();
    _wachtToestel?.cancel();
    _c.dispose();
    _volger.dispose();
    _muis.dispose();
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
    if (!mounted) return;
    // Stilgezet ([KantelKeuze]): geen melder, en de hoes gaat recht staan.
    final wil = widget.bron == KantelBron.toestel &&
        !KantelKeuze.vast.value &&
        _mag(context) &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden;
    if (!wil) {
      _melder?.cancel();
      _melder = null;
      _rust = _glad = null;
      // Een stand die nog wachtte ([kToestelStap]) zou hem anders na het stilzetten nog één keer laten kantelen.
      _wachtToestel?.cancel();
      _wachtToestel = null;
      _volgendeToestel = null;
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
    _naarMuis(Offset(((p.dx / maat.width) * 2 - 1).clamp(-1.0, 1.0), ((p.dy / maat.height) * 2 - 1).clamp(-1.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    // Een meetronde zonder kantelen (zie `meetronde.dart`): de hoes zoals hij is.
    if (zonderVoorMeting('kantel')) return widget.child;
    final kind = RepaintBoundary(child: widget.child);
    final muis = widget.bron == KantelBron.muis;
    final getekend = AnimatedBuilder(
      animation: muis ? _muis : _c,
      child: kind,
      builder: (context, kind) {
        final o = muis ? _muis.value : _stand;
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
        onExit: (_) => _naarMuis(Offset.zero),
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
  void paint(Canvas canvas, Size size) => tekenKantelGlans(canvas, Offset.zero & size, Offset.zero & size, o);

  @override
  bool shouldRepaint(KantelGlans oud) => oud.o != o;
}

/// De glans van [KantelGlans] in [teken], met het licht gemeten over de hoes [hoes]. Voor de hoes zelf zijn die gelijk;
/// voor de cd die eruit steekt is [hoes] het vak van de hoes in de maat van de cd, zodat één en dezelfde lichtvlek over
/// hoes en cd doorloopt.
void tekenKantelGlans(Canvas canvas, Rect teken, Rect hoes, Offset o) {
  final sterkte = (o.distance / math.sqrt2).clamp(0.0, 1.0);
  if (sterkte <= 0) return;
  // Het licht staat tegenover de kant die wegzakt.
  final midden = Alignment(-o.dx * .9, -o.dy * .9);
  canvas.drawRect(
      teken,
      Paint()
        ..shader = RadialGradient(
          center: midden,
          radius: .85,
          colors: [Color.fromRGBO(255, 255, 255, .24 * sterkte), const Color(0x00FFFFFF)],
        ).createShader(hoes));
  canvas.drawRect(
      teken,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1 + o.dx * .6, -1),
          end: Alignment(1 + o.dx * .6, 1),
          colors: [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, .10 * sterkte), const Color(0x00FFFFFF)],
          stops: const [.38, .5, .62],
        ).createShader(hoes));
}

/// De glans van een gekantelde hoes, op de cd die eruit steekt: binnen de schijf, met het licht van de hoes
/// ([tekenKantelGlans]). [hoes] is het vak van de hoes, gemeten vanaf de linkerbovenhoek van de schijf.
class SchijfKantelGlans extends CustomPainter {
  SchijfKantelGlans(this.o, {required this.hoes});
  final Offset o;
  final Rect hoes;

  @override
  void paint(Canvas canvas, Size size) {
    if (o.distance < .002) return;
    final vak = Offset.zero & size;
    canvas.save();
    canvas.clipPath(Path()..addOval(vak));
    tekenKantelGlans(canvas, vak, hoes, o);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SchijfKantelGlans oud) => oud.o != o || oud.hoes != hoes;
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
            // Gebakken: in stroken kostte hij op de Mac 7 ms per beeld (zie [TegelSpiegel.gebakken]). In een meetronde
            // met `stroken` zoals vroeger, om te vergelijken.
            child: TegelSpiegel(bron: MemoryImage(beeld), maat: maat, hoek: 10, gebakken: !zonderVoorMeting('stroken')),
          ),
        ),
      );
}
