/// Een witte rand om wat de selectie heeft, op een tv — voor alles wat dat zelf niet laat zien.
///
/// **Waarom.** Saber op de Shield, 15-10-2026: *"ik weet nooit welke geselecteerde knoppen het zijn."*
/// Nagekeken met schermafdrukken via adb: op Start staat de selectie na één keer omlaag op de kaart
/// "Zeg wat je wil horen", en er verandert niets op het scherm. Dat is een `InkWell` om een `Container`
/// met een eigen achtergrond: de InkWell tekent zijn selectie op de laag ONDER die achtergrond, dus
/// nooit zichtbaar. In `main.dart` staan 31 InkWells; elk met een gekleurde inhoud heeft hetzelfde.
///
/// Dus tekent deze laag boven de hele app een witte rand om de InkWell die de selectie heeft. Een
/// knop (`TextButton`, `IconButton`, … — alles wat op [ButtonStyleButton] of [RawMaterialButton]
/// rust) tekent zijn rand al zelf via het thema, net als [Pressable]; die worden overgeslagen, anders
/// staan er twee.
///
/// Goedkoop: er rekent niets zolang de selectie stilstaat. Na een wissel of een scrolbeweging volgt
/// hij een halve seconde mee, zodat hij het in beeld schuiven bijhoudt, en dan stopt hij weer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../tv.dart';

/// Hoe ver boven de focus de InkWell mag zitten die hem bezit. Een InkWell bouwt
/// `_ParentInkResponseProvider → Actions → _ActionsScope → Focus`: vier stappen.
const _inktZoekdiepte = 6;

/// Hoe ver boven die InkWell een knop mag zitten die hem bezit. Een `TextButton` legt er
/// `Semantics → _InputPadding → ConstrainedBox → Material → …` tussen, rond de vijftien stappen.
const _knopZoekdiepte = 30;

/// Hoe lang hij na een wissel of een scrolbeweging meemeet.
const _volgDuur = Duration(milliseconds: 450);

/// Heeft dit focuselement een rand van deze laag nodig, en hoe rond? Publiek voor de toets.
@visibleForTesting
({bool nodig, double hoek}) haloVoor(BuildContext ctx) {
  InkResponse? inkt;
  var diepte = 0;
  ctx.visitAncestorElements((e) {
    final w = e.widget;
    if (w is InkResponse) {
      inkt = w;
      return false;
    }
    return ++diepte < _inktZoekdiepte;
  });
  final gevonden = inkt;
  if (gevonden == null) return (nodig: false, hoek: 0);
  var vanKnop = false;
  diepte = 0;
  ctx.visitAncestorElements((e) {
    final w = e.widget;
    if (w is ButtonStyleButton || w is RawMaterialButton) {
      vanKnop = true;
      return false;
    }
    return ++diepte < _knopZoekdiepte;
  });
  if (vanKnop) return (nodig: false, hoek: 0);
  final r = gevonden.borderRadius;
  return (nodig: true, hoek: r is BorderRadius ? r.topLeft.x : 6.0);
}

class TvFocusHalo extends StatefulWidget {
  const TvFocusHalo({super.key, required this.child});
  final Widget child;

  @override
  State<TvFocusHalo> createState() => _TvFocusHaloState();
}

class _TvFocusHaloState extends State<TvFocusHalo> with SingleTickerProviderStateMixin {
  Rect? _rect;
  double _hoek = 6;
  Duration _volgTot = Duration.zero, _laatst = Duration.zero;
  /// Pas aangemaakt bij de eerste wissel: buiten een tv nooit, en een klok die pas in dispose()
  /// ontstaat, vraagt een TickerMode op in een boom die al afgebroken wordt.
  Ticker? _volg;

  Ticker _klok() => _volg ??= createTicker((verlopen) {
        _laatst = verlopen;
        _meet();
        if (verlopen > _volgTot) _volg?.stop();
      });

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_volgEven);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_volgEven);
    _volg?.dispose();
    super.dispose();
  }

  /// Een halve seconde meten, beeld voor beeld. Nooit meteen: een focuswissel of een scrolmelding
  /// kan midden in een opbouw of een layout vallen, en dan is setState verboden en de maat oud.
  void _volgEven() {
    if (!isTv || !mounted) return;
    final klok = _klok();
    if (klok.isActive) {
      _volgTot = _laatst + _volgDuur;
      return;
    }
    _laatst = Duration.zero;
    _volgTot = _volgDuur;
    klok.start();
  }

  void _meet() {
    if (!mounted) return;
    Rect? nieuw;
    var hoek = _hoek;
    final ctx = FocusManager.instance.primaryFocus?.context;
    final ik = context.findRenderObject();
    if (ctx != null && ctx.mounted && ik is RenderBox && ik.hasSize) {
      final h = haloVoor(ctx);
      final doel = ctx.findRenderObject();
      if (h.nodig && doel is RenderBox && doel.attached && doel.hasSize) {
        hoek = h.hoek;
        var r = MatrixUtils.transformRect(doel.getTransformTo(ik), Offset.zero & doel.size);
        // Binnen elke lijst waar hij in staat, ook een rij in een rij: een rand die over de
        // spelerbalk of de bovenbalk heen tekent, wijst naar iets wat je niet ziet.
        var rol = Scrollable.maybeOf(ctx);
        while (rol != null) {
          final box = rol.context.findRenderObject();
          if (box is RenderBox && box.attached && box.hasSize) {
            r = r.intersect(MatrixUtils.transformRect(box.getTransformTo(ik), Offset.zero & box.size));
          }
          rol = Scrollable.maybeOf(rol.context);
        }
        if (r.width > 4 && r.height > 4) nieuw = r;
      }
    }
    if (nieuw != _rect || hoek != _hoek) {
      setState(() {
        _rect = nieuw;
        _hoek = hoek;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isTv) return widget.child;
    final r = _rect;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _volgEven();
        return false;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (r != null)
            Positioned.fromRect(
              rect: r.inflate(3),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_hoek + 3),
                    border: Border.all(color: kTvSelectie, width: 3),
                    // Alleen BUITEN de rand: een gewone schaduw is een gevuld vlak, en dat legt hier een
                    // witte waas over de kaart zelf.
                    boxShadow: [
                      BoxShadow(
                          color: kTvSelectie.withValues(alpha: .25), blurRadius: 18, blurStyle: BlurStyle.outer),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
