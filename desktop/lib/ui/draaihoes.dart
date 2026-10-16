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

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

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

  /// Staat de achterkant voor?
  bool get omgedraaid => _omgedraaid;

  /// Telt op bij elke wiebel, zodat de hoes weet dat hij er een moet spelen.
  int get wiebels => _wiebels;

  /// Omdraaien als [heeftAchterkant], anders wiebelen.
  void draai({required bool heeftAchterkant}) {
    if (heeftAchterkant || _omgedraaid) {
      _omgedraaid = !_omgedraaid;
    } else {
      _wiebels++;
    }
    notifyListeners();
  }

  /// Terug naar de voorkant, zonder animatie-eisen (bij een andere plaat).
  void voorkant() {
    if (!_omgedraaid) return;
    _omgedraaid = false;
    notifyListeners();
  }
}

/// De voor- en achterkant van een hoes, met een 3D-draai ertussen.
class DraaiHoes extends StatefulWidget {
  const DraaiHoes({super.key, required this.controller, required this.voor, this.achter});

  final DraaiHoesController controller;
  final Widget voor;

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

/// De transform van de draai op moment [t] (0 = voorkant, 1 = achterkant).
@visibleForTesting
Matrix4 draaiMatrix(double t) {
  final hoek = math.pi * t;
  // Even optillen halverwege, alsof je hem oppakt om te draaien.
  final til = 1 + .06 * math.sin(math.pi * t.clamp(0.0, 1.0));
  return Matrix4.identity()
    ..setEntry(3, 2, .0014)
    ..rotateY(hoek)
    ..scaleByDouble(til, til, 1, 1);
}

class _DraaiHoesState extends State<DraaiHoes> with TickerProviderStateMixin {
  late final AnimationController _draai;
  late final AnimationController _wiebel;

  /// Hoeveel wiebels er al gespeeld zijn. NIET lui: een luie waarde werd pas gelezen in het seintje
  /// van de eerste wiebel, nam dan al het nieuwe getal aan, en dan wiebelde er nooit iets.
  late int _wiebels;

  @override
  void initState() {
    super.initState();
    _draai = AnimationController(vsync: this, duration: kDraaiDuur, value: widget.controller.omgedraaid ? 1 : 0);
    _wiebel = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _wiebels = widget.controller.wiebels;
    widget.controller.addListener(_opController);
  }

  @override
  void didUpdateWidget(DraaiHoes oud) {
    super.didUpdateWidget(oud);
    if (oud.controller != widget.controller) {
      oud.controller.removeListener(_opController);
      widget.controller.addListener(_opController);
      _wiebels = widget.controller.wiebels;
      _draai.value = widget.controller.omgedraaid ? 1 : 0;
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
    return AnimatedBuilder(
      animation: Listenable.merge([_draai, _wiebel]),
      builder: (context, _) {
        final t = _draai.value;
        final w = _wiebel.isAnimating ? wiebelHoek(_wiebel.value) : 0.0;
        final rust = t == 0 && w == 0;
        if (rust) return voor;
        final kant = (t < .5 || achter == null) ? voor : achter;
        return Transform(
          alignment: Alignment.center,
          transform: draaiMatrix(t)..rotateY(w),
          child: kant,
        );
      },
    );
  }
}
