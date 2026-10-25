/// Een hoes die je met twee tikken omdraait, en twee tikken herkennen zonder een gewone tik op te houden.
///
/// **Waarom.** Saber, 16-10-2026: *"Ik wil ook de achterkant van de cd weg, en ik wil het vervangen
/// door als ik dubbel tab of dubbel klik op de front hoes dat hij draait met een leuke animatie die
/// dan de achterkant toont. Let op performance moet heel snel en instant werken overal."* Hij koos:
/// geen achterkant → een korte wiebel; op tegels mag een gewone tik 0,2 s wachten.
///
/// **Waarom niet `GestureDetector.onDoubleTap`.** Die wacht vast 300 ms (`kDoubleTapTimeout`) en houdt
/// in die tijd elke gewone tik van een ouder of kind tegen — ook waar er helemaal geen gewone tik is.
/// [TweeTikken] luistert met een [Listener] mee, doet niet mee in de gebarenarena, en laat alleen een
/// gewone tik wachten als je hem dat vraagt ([TweeTikken.enkel]).
///
/// **Goedkoop.** Het draaien is een transform op twee al getekende beelden: geen opbouw per beeld,
/// geen nieuwe decodering. De achterkant wordt vooraf gedecodeerd door wie hem aanlevert.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../booklet.dart' show imageSize;

/// Hoe lang er na een tik op een tweede gewacht wordt (van loslaten tot opnieuw neerdrukken).
const kTweedeTik = Duration(milliseconds: 200);

/// Hoe ver de tweede tik van de eerste mag liggen.
const double _tweedeTikAfstand = 48;

/// Herkent een dubbeltik, en laat een gewone tik pas door als er geen tweede kwam.
///
/// Gebruik: zet [DubbelTikVlak] om de hoes, en geef een gewone tik (als die er is) door via [enkel].
/// Komt er binnen [kTweedeTik] na het loslaten een tweede neerdruk op dezelfde plek, dan vervalt de
/// gewone tik en volgt de dubbeltik bij het loslaten van de tweede.
class TweeTikken {
  TweeTikken({this.wacht = kTweedeTik, DateTime Function()? klok}) : _klok = klok ?? DateTime.now;

  final Duration wacht;
  final DateTime Function() _klok;

  Timer? _enkel;
  DateTime? _laatsteOp;
  Offset? _plek;
  bool _tweede = false;
  DateTime? _dubbelOp;

  /// Is er net een dubbeltik geweest of loopt de tweede nog? Dan hoort een gewone tik niet te komen.
  bool get _slik {
    final d = _dubbelOp;
    return _tweede || (d != null && _klok().difference(d) < const Duration(milliseconds: 80));
  }

  /// Een gewone tik, die wacht tot zeker is dat er geen tweede komt.
  void enkel(VoidCallback doe) {
    if (_slik) return;
    _enkel?.cancel();
    _enkel = Timer(wacht, () {
      _enkel = null;
      if (!_tweede) doe();
    });
  }

  @visibleForTesting
  void neer(Offset plek) {
    final op = _laatsteOp;
    if (op != null &&
        _klok().difference(op) <= wacht &&
        (_plek == null || (plek - _plek!).distance <= _tweedeTikAfstand)) {
      _enkel?.cancel();
      _enkel = null;
      _tweede = true;
    }
  }

  /// Geeft true als dit loslaten een dubbeltik afmaakte.
  @visibleForTesting
  bool op(Offset plek) {
    if (_tweede) {
      _tweede = false;
      _laatsteOp = null;
      _dubbelOp = _klok();
      return true;
    }
    _laatsteOp = _klok();
    _plek = plek;
    return false;
  }

  /// Een vinger die gleed of werd afgebroken telt niet als tik.
  @visibleForTesting
  void weg() {
    _tweede = false;
    _laatsteOp = null;
  }

  void dispose() => _enkel?.cancel();
}

/// Luistert mee naar twee tikken op [child], zonder andere gebaren in de weg te zitten.
class DubbelTikVlak extends StatefulWidget {
  const DubbelTikVlak({super.key, required this.onDubbel, required this.child, this.tikken});

  final VoidCallback onDubbel;
  final Widget child;

  /// Gedeeld met wie de gewone tik afhandelt ([TweeTikken.enkel]); anders een eigen.
  final TweeTikken? tikken;

  @override
  State<DubbelTikVlak> createState() => _DubbelTikVlakState();
}

class _DubbelTikVlakState extends State<DubbelTikVlak> {
  final TweeTikken _eigen = TweeTikken();
  TweeTikken get _t => widget.tikken ?? _eigen;
  Offset? _start;

  @override
  void dispose() {
    _eigen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) return;
          _start = e.position;
          _t.neer(e.position);
        },
        onPointerMove: (e) {
          final s = _start;
          if (s != null && (e.position - s).distance > kTouchSlop) {
            _start = null;
            _t.weg();
          }
        },
        onPointerUp: (e) {
          if (_start == null) return;
          _start = null;
          if (_t.op(e.position)) widget.onDubbel();
        },
        onPointerCancel: (_) {
          _start = null;
          _t.weg();
        },
        child: widget.child,
      );
}

/// Bedient een [DraaiHoes] van buitenaf.
class DraaiHoesController extends ChangeNotifier {
  bool _omgedraaid = false;
  int _wiebels = 0;
  bool _weg = false;
  final _voorInRust = ValueNotifier<bool>(true);

  /// Staat de achterkant voor?
  bool get omgedraaid => _omgedraaid;

  /// Ligt de voorkant stil vooraan? Niet zolang de achterkant voor staat, en ook niet zolang hij nog
  /// TERUGdraait.
  ///
  /// **Waarom dat tweede.** Saber, 16-10-2026, over Nu speelt: *"van de achterkant terug flippen naar
  /// de voorkant, dan zie ik voor een seconde de cd er volledig door, dat mag niet, is niet realistisch
  /// en niet mooi."* De cd achter de hoes keek naar [omgedraaid], en dat gaat op onwaar zodra het
  /// terugdraaien BEGINT: halverwege, met de hoes op zijn kant, stond de hele cd in beeld. Wat achter de
  /// hoes zit, hoort pas weer te verschijnen als hij helemaal terug is — dit.
  ValueListenable<bool> get voorInRust => _voorInRust;

  /// Telt op bij elke wiebel, zodat de hoes weet dat hij er een moet spelen.
  int get wiebels => _wiebels;

  /// Omdraaien als [heeftAchterkant], anders wiebelen.
  void draai({required bool heeftAchterkant}) {
    if (heeftAchterkant || _omgedraaid) {
      _omgedraaid = !_omgedraaid;
      if (_omgedraaid) _voorInRust.value = false;
    } else {
      _wiebels++;
    }
    notifyListeners();
  }

  /// De [DraaiHoes] meldt dat hij weer helemaal op zijn voorkant ligt.
  void _terugOpVoorkant() {
    if (!_weg && !_omgedraaid) _voorInRust.value = true;
  }

  @override
  void dispose() {
    _weg = true;
    _voorInRust.dispose();
    super.dispose();
  }

  /// Terug naar de voorkant, zonder animatie-eisen (bij een andere plaat).
  void voorkant() {
    if (!_omgedraaid) return;
    _omgedraaid = false;
    notifyListeners();
  }
}

/// Onder dit verschil met 1 telt een achterkant als vierkant (vinyl, een single) en vult hij het vak.
const _bijnaVierkant = .04;

/// Waar een achterkant met [verhouding] (breedte gedeeld door hoogte) komt in het vak van de hoes,
/// [maat] bij [maat]: helemaal zichtbaar, in zijn eigen vorm, gecentreerd. Onbekend = het hele vak.
///
/// **Waarom niet gewoon vullen.** Saber, 16-10-2026: *"als ik de hoes flip voor de achterkant wordt
/// die teveel afgesneden (achterkant heeft ander formaat e) ten ware bij vinyl of single soms."*
/// Gemeten op zijn 485 bewaarde achterkanten: 283 hebben de verhouding van een cd-achterkant (1,22 tot
/// 1,35 — het inlegvel met de twee ruggen), 97 zijn breed, 15 heel breed, 85 vierkant en 5 staand.
/// Vullen in een vierkant sneed bij een gewone cd een vijfde van de breedte weg: precies de ruggen en
/// de randen met de tekst.
Size achterkantMaat(double maat, double? verhouding) {
  if (verhouding == null || !verhouding.isFinite || verhouding <= 0 || (verhouding - 1).abs() < _bijnaVierkant) {
    return Size.square(maat);
  }
  return verhouding > 1 ? Size(maat, maat / verhouding) : Size(maat * verhouding, maat);
}

final _verhoudingen = Expando<double>('verhouding van een achterkant');

/// Breedte gedeeld door hoogte van een beeld, uit zijn kop (zonder te decoderen), één keer per beeld.
double? beeldVerhouding(Uint8List beeld) {
  final al = _verhoudingen[beeld];
  if (al != null) return al.isNaN ? null : al;
  final m = imageSize(beeld);
  final v = (m == null || m.w <= 0 || m.h <= 0) ? double.nan : m.w / m.h;
  _verhoudingen[beeld] = v;
  return v.isNaN ? null : v;
}

/// Een achterkant in het vak van de hoes: helemaal, in zijn eigen vorm ([achterkantMaat]).
class AchterkantBeeld extends StatelessWidget {
  const AchterkantBeeld({
    super.key,
    required this.beeld,
    required this.maat,
    required this.hoek,
    required this.decodeerBreedte,
    this.schaduw,
  });

  final Uint8List beeld;

  /// De zijde van het vak, gelijk aan die van de voorkant.
  final double maat;
  final double hoek;

  /// Zoals de voorlader hem decodeerde: dezelfde sleutel, dus geen tweede keer.
  final int decodeerBreedte;

  /// Een schaduw om de achterkant zelf, in ZIJN vorm. Wie de voorkant een schaduw geeft, haalt die weg
  /// zolang de achterkant voor staat ([DraaiHoesController.voorInRust]): een vierkante schaduw onder
  /// een brede achterkant is een donkere strook boven en onder.
  final List<BoxShadow>? schaduw;

  @override
  Widget build(BuildContext context) {
    final m = achterkantMaat(maat, beeldVerhouding(beeld));
    final vorm = BorderRadius.circular(hoek);
    Widget beeldje = ClipRRect(
      borderRadius: vorm,
      child: Image.memory(beeld,
          width: m.width, height: m.height, fit: BoxFit.cover, cacheWidth: decodeerBreedte, gaplessPlayback: true),
    );
    final s = schaduw;
    if (s != null) beeldje = DecoratedBox(decoration: BoxDecoration(borderRadius: vorm, boxShadow: s), child: beeldje);
    return SizedBox.square(dimension: maat, child: Center(child: beeldje));
  }
}

/// De voor- en achterkant van een hoes, met een 3D-draai ertussen.
class DraaiHoes extends StatefulWidget {
  const DraaiHoes({super.key, required this.controller, required this.voor, this.achter, this.breedte});

  final DraaiHoesController controller;
  final Widget voor;

  /// Hoe breed de hoes is, voor de diepte van de draai ([kDraaiDiepte]). Mee te geven door wie hem bouwt: in Nu speelt
  /// staat hij in een `Positioned` zonder breedte en op de albumpagina in een `Row`, en daar krijgt hij geen begrensde
  /// breedte mee — dan viel de draai terug op 200 punten en ballonde de grote hoes nog steeds (opgenomen op de pc, 3.9.626).
  /// Null: de breedte die hij krijgt, of 200.
  final double? breedte;

  /// Null = er is geen achterkant; [DraaiHoesController.draai] wiebelt dan.
  final Widget? achter;

  @override
  State<DraaiHoes> createState() => _DraaiHoesState();
}

/// Hoe lang het omdraaien duurt.
const kDraaiDuur = Duration(milliseconds: 460);

/// De draai met een lichte veer aan het eind: hij schiet een paar graden door en komt terug.
const _draaiCurve = Cubic(.3, .0, .2, 1.12);

/// De hoek (in radialen) van de wiebel op moment [t] (0..1): drie keer heen en weer, uitdempend.
@visibleForTesting
double wiebelHoek(double t) => math.sin(t * 3 * math.pi) * (1 - t) * .16;

/// Hoe diep de draai lijkt, als deel van de breedte van de hoes: de perspectief van iemand die een hoesje op een
/// paar keer zijn breedte voor zich omdraait. Op een tegel van 200 punten is dat de .0014 van altijd.
///
/// **Waarom gedeeld door de breedte (Saber, 25-10-2026: "het draaien van de album blijft niet realistisch genoeg",
/// "test ook draaien van de hoes op pc").** Opgenomen op de pc (30 beelden per seconde): de vaste .0014 was afgesteld
/// op een tegel. Bij de grote hoes van Nu speelt (zo'n 700 punten) werd de rand die naar je toe kwam halverwege twee
/// keer zo groot en stak hij ver boven en onder het vak uit — een hoesje dat naar je toe vliegt in plaats van
/// omdraait. Nu ziet de draai er op elke maat hetzelfde uit.
const double kDraaiDiepte = .28;

/// De transform van de draai op moment [t] (0 = voorkant, 1 = achterkant), voor een hoes van [breedte] punten.
@visibleForTesting
Matrix4 draaiMatrix(double t, {double breedte = 200}) {
  final hoek = math.pi * t;
  // Even optillen halverwege, alsof je hem oppakt om te draaien.
  final til = 1 + .06 * math.sin(math.pi * t.clamp(0.0, 1.0));
  return Matrix4.identity()
    ..setEntry(3, 2, kDraaiDiepte / (breedte > 0 ? breedte : 200))
    ..rotateY(hoek)
    ..scaleByDouble(til, til, 1, 1);
}

/// Hoe dik een hoes is, als deel van zijn breedte: een cd-doosje of een plaathoes van karton.
const double kHoesDikte = .03;

/// De transform van de rand (de dikte) aan kant [kant] (-1 links, 1 rechts) van een hoes die
/// [breedte] breed is, op moment [t]: loodrecht op de hoes, aan zijn rand, en meegedraaid.
@visibleForTesting
Matrix4 randMatrix(double t, double breedte, int kant) =>
    draaiMatrix(t, breedte: breedte)
      ..translateByDouble(kant * breedte / 2, 0, 0, 1)
      ..rotateY(math.pi / 2);

/// Hoe fel de glansveeg is op moment [t]: niets in rust, het felst halverwege.
@visibleForTesting
double veegSterkte(double t) => .32 * math.sin(math.pi * t.clamp(0.0, 1.0));

class _DraaiHoesState extends State<DraaiHoes> with TickerProviderStateMixin {
  late final AnimationController _draai;
  late final AnimationController _wiebel;

  /// Hoeveel wiebels er al gespeeld zijn. NIET lui: een luie waarde werd pas gelezen in het seintje
  /// van de eerste wiebel, nam dan al het nieuwe getal aan, en dan wiebelde er nooit iets.
  late int _wiebels;

  @override
  void initState() {
    super.initState();
    _draai = AnimationController(vsync: this, duration: kDraaiDuur, value: widget.controller.omgedraaid ? 1 : 0)
      ..addStatusListener(_opStand);
    _wiebel = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _wiebels = widget.controller.wiebels;
    widget.controller.addListener(_opController);
  }

  /// Helemaal terug op de voorkant: zeg het de controller, zodat wat achter de hoes zit weer mag.
  void _opStand(AnimationStatus s) {
    if (s == AnimationStatus.dismissed) widget.controller._terugOpVoorkant();
  }

  @override
  void didUpdateWidget(DraaiHoes oud) {
    super.didUpdateWidget(oud);
    if (oud.controller != widget.controller) {
      oud.controller.removeListener(_opController);
      widget.controller.addListener(_opController);
      _wiebels = widget.controller.wiebels;
      _draai.value = widget.controller.omgedraaid ? 1 : 0;
      // Na dit beeld: wie meeluistert (de cd) zit boven deze hoes, en die mag niet tijdens de opbouw
      // opnieuw gemarkeerd worden.
      final c = widget.controller;
      if (_draai.value == 0) WidgetsBinding.instance.addPostFrameCallback((_) => c._terugOpVoorkant());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_opController);
    _draai.dispose();
    _wiebel.dispose();
    super.dispose();
  }

  void _opController() {
    final c = widget.controller;
    if (c.wiebels != _wiebels) {
      _wiebels = c.wiebels;
      _wiebel.forward(from: 0);
    }
    if (c.omgedraaid && _draai.status != AnimationStatus.forward && _draai.value < 1) {
      _draai.animateTo(1, curve: _draaiCurve);
    } else if (!c.omgedraaid && _draai.status != AnimationStatus.reverse && _draai.value > 0) {
      _draai.animateBack(0, curve: _draaiCurve.flipped);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Beide kanten één keer gebouwd en als kind doorgegeven: per beeld verandert alleen de transform.
    final voor = RepaintBoundary(child: widget.voor);
    final achter = widget.achter == null
        ? null
        : RepaintBoundary(
            // Gespiegeld, zodat hij na een halve slag leesbaar staat.
            child: Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: widget.achter),
          );
    // **Altijd dezelfde vorm**, in rust en tijdens het draaien. Eerst gaf dit in rust de kant zelf terug
    // en tijdens het draaien een Stack met de kant erin: dan verhuist de hoes bij elk begin en eind van
    // een draai naar een andere plek in de boom, en Flutter gooit hem dan weg en bouwt hem opnieuw — met
    // zijn Hero, zijn beeld en alles wat eronder hing (gsm 18-10-2026: "de hoes flipt niet om"). Nu
    // staan voor- en achterkant er allebei, met een sleutel, en wisselt alleen welke zichtbaar is.
    // De breedte voor de diepte van de draai ([kDraaiDiepte]). Altijd dezelfde vorm: de LayoutBuilder staat er ook in rust.
    return LayoutBuilder(
      builder: (context, maat) => AnimatedBuilder(
      animation: Listenable.merge([_draai, _wiebel]),
      builder: (context, _) {
        final breedte = widget.breedte ?? (maat.maxWidth.isFinite ? maat.maxWidth : 200.0);
        final t = _draai.value;
        final w = _wiebel.isAnimating ? wiebelHoek(_wiebel.value) : 0.0;
        final rust = t == 0 && w == 0;
        final achterOp = achter != null && t >= .5;
        // Dikte, schaduw en veeg alleen tijdens het omdraaien. Een wiebel blijft wat hij was, en een
        // achterkant in rust krijgt geen randen (die bleven anders als twee strepen naast een
        // cd-achterkant staan die breder is dan hoog, gsm 18-10-2026).
        final draait = t > 0 && t < 1;
        final dwars = math.cos(math.pi * t).abs();
        return Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
          if (draait)
            Positioned.fill(
              key: const ValueKey('draai-schaduw-laag'),
              child: IgnorePointer(
                child: Transform.scale(
                  scaleX: math.max(dwars, .08),
                  child: const DecoratedBox(
                    key: ValueKey('draai-schaduw'),
                    decoration: BoxDecoration(boxShadow: [
                      BoxShadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0, 10)),
                    ]),
                  ),
                ),
              ),
            ),
          // Beide randen vóór de hoes getekend: de rand die van je af staat, valt dan achter de hoes.
          if (draait)
            for (final k in const [-1, 1])
              Positioned.fill(
                key: ValueKey('draai-rand-laag-$k'),
                child: IgnorePointer(
                  child: LayoutBuilder(
                    builder: (_, c) => Transform(
                      alignment: Alignment.center,
                      transform: randMatrix(t, c.maxWidth, k),
                      child: Center(
                        child: SizedBox(
                          key: ValueKey('draai-rand-$k'),
                          width: c.maxWidth * kHoesDikte,
                          height: c.maxHeight,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [Color(0xFF2A2B30), Color(0xFF4A4C54), Color(0xFF2A2B30)]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          Transform(
            key: const ValueKey('draai-kant'),
            alignment: Alignment.center,
            // In rust de eenheid: een rechte hoes, niets te verrekenen.
            transform: rust ? Matrix4.identity() : (draaiMatrix(t, breedte: breedte)..rotateY(w)),
            child: Stack(fit: StackFit.passthrough, children: [
              Offstage(key: const ValueKey('draai-voor'), offstage: achterOp, child: voor),
              if (achter != null) Offstage(key: const ValueKey('draai-achter'), offstage: !achterOp, child: achter),
              if (draait)
                Positioned.fill(
                  key: const ValueKey('draai-veeg-laag'),
                  child: IgnorePointer(
                    child: CustomPaint(key: const ValueKey('draai-veeg'), painter: _Veeg(t)),
                  ),
                ),
            ]),
          ),
        ]);
      },
    ),
    );
  }
}

/// De glansveeg over een hoes die omdraait: een schuine band licht die in één keer van links naar
/// rechts over de voorkant gaat, en dan over de achterkant verder.
class _Veeg extends CustomPainter {
  _Veeg(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final a = veegSterkte(t);
    if (a <= 0) return;
    final x = -1.4 + 2.8 * t;
    final vak = Offset.zero & size;
    canvas.drawRect(
        vak,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment(x - .5, -1),
            end: Alignment(x + .5, 1),
            colors: [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, a), const Color(0x00FFFFFF)],
          ).createShader(vak));
  }

  @override
  bool shouldRepaint(_Veeg oud) => oud.t != t;
}
