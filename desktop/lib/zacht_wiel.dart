/// Vloeiend scrollen met het muiswiel op de pc (Saber, 17-10-2026: "vloeiender").
///
/// **Wat er mis was.** Flutter verwerkt een wieltik op Windows als één sprong: `pointerScroll` zet de
/// lijst in één beeld ~100 punten verder (`ScrollPositionWithSingleContext.pointerScroll`, zonder
/// animatie en zonder haak om dat te veranderen). Op een scherm van 144 Hz ziet dat eruit als
/// schokken, hoe snel elk beeld ook getekend wordt — dat is geen haperen maar de vorm van de
/// beweging.
///
/// **Waarom hier, aan de bron.** Elke lijst in de app een eigen controller geven raakt tientallen
/// plekken, en elke nieuwe lijst zou het weer vergeten. Hier wordt elke wieltik van de muis gesplitst
/// voordat Flutter hem ziet: een eerste stuk meteen (de lijst reageert in hetzelfde beeld), en de
/// rest loopt uit over de volgende beelden. Alles wat scrolt, scrolt daardoor vanzelf vloeiend.
///
/// **Wie per tik telt.** Het menu verspringt één sectie per tik. De vervolgstappen dragen daarom
/// [kZachtWielVervolg] als `embedderId`; het eerste stuk houdt dat van de echte tik. Wie tikken telt,
/// laat de vervolgstappen links liggen ([isZachtWielVervolg]).
///
/// Alleen een muis en alleen echte tikken: een touchpad stuurt op Windows gebaren (pan/zoom) en een
/// fijn wiel kleine stapjes, en die zijn al vloeiend.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

/// Het merk op de vervolgstappen van één wieltik.
const int kZachtWielVervolg = 0x5A57;

/// Is dit een vervolgstap van een gesplitste tik (en dus geen nieuwe tik)?
bool isZachtWielVervolg(PointerEvent e) => e.embedderId == kZachtWielVervolg;

/// Hoeveel van een tik meteen gaat: genoeg dat de lijst in hetzelfde beeld reageert.
const double kZachtWielMeteen = .35;

/// Hoe snel de rest uitloopt: na deze tijd is 63 % van wat overbleef gescrold, na drie keer 95 %.
const Duration kZachtWielTau = Duration(milliseconds: 38);

/// Tikken kleiner dan dit (een fijn of vrij draaiend wiel) gaan ongewijzigd door.
const double kZachtWielVanaf = 30;

/// Splitst wieltikken. [door] krijgt de pakketten die Flutter moet zien, [plan] vraagt een
/// terugroep bij het volgende beeld (in de app: de planner van Flutter; in een toets: met de hand).
class ZachtWiel {
  ZachtWiel({required this.door, required this.plan});

  final void Function(ui.PointerDataPacket pakket) door;
  final void Function(void Function(Duration tijd) terug) plan;

  final _lopend = <int, _Lopend>{};
  bool _gepland = false;
  Duration? _vorige;

  /// Zet hem voor de pakketverwerking van Flutter. Alleen op de pc aanroepen, na
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static void installeer() {
    final dispatcher = ui.PlatformDispatcher.instance;
    final flutter = dispatcher.onPointerDataPacket;
    if (flutter == null) return;
    final wiel = ZachtWiel(
      door: flutter,
      plan: (terug) {
        SchedulerBinding.instance.scheduleFrameCallback(terug);
        SchedulerBinding.instance.scheduleFrame();
      },
    );
    dispatcher.onPointerDataPacket = wiel.opPakket;
  }

  void opPakket(ui.PointerDataPacket pakket) {
    List<ui.PointerData>? anders;
    for (var i = 0; i < pakket.data.length; i++) {
      final d = pakket.data[i];
      if (!_isTik(d)) {
        anders?.add(d);
        continue;
      }
      anders ??= pakket.data.sublist(0, i);
      anders.add(_kopie(d, d.scrollDeltaX * kZachtWielMeteen, d.scrollDeltaY * kZachtWielMeteen, d.embedderId));
      final l = _lopend.putIfAbsent(d.device, () => _Lopend(d));
      l.basis = d;
      l.dx += d.scrollDeltaX * (1 - kZachtWielMeteen);
      l.dy += d.scrollDeltaY * (1 - kZachtWielMeteen);
      _volgende();
    }
    door(anders == null ? pakket : ui.PointerDataPacket(data: anders));
  }

  static bool _isTik(ui.PointerData d) =>
      d.signalKind == ui.PointerSignalKind.scroll &&
      d.kind == ui.PointerDeviceKind.mouse &&
      d.embedderId != kZachtWielVervolg &&
      (d.scrollDeltaY.abs() >= kZachtWielVanaf || d.scrollDeltaX.abs() >= kZachtWielVanaf);

  void _volgende() {
    if (_gepland) return;
    _gepland = true;
    plan(_stap);
  }

  void _stap(Duration nu) {
    _gepland = false;
    final dt = _vorige == null ? const Duration(milliseconds: 16) : nu - _vorige!;
    _vorige = nu;
    final deel = 1 - math.exp(-dt.inMicroseconds / kZachtWielTau.inMicroseconds);
    final stappen = <ui.PointerData>[];
    final klaar = <int>[];
    _lopend.forEach((apparaat, l) {
      var sx = l.dx * deel, sy = l.dy * deel;
      // Het laatste halve punt in één keer: anders sleept de staart nog tientallen beelden na.
      if ((l.dx - sx).abs() < .5) sx = l.dx;
      if ((l.dy - sy).abs() < .5) sy = l.dy;
      l.dx -= sx;
      l.dy -= sy;
      if (sx != 0 || sy != 0) stappen.add(_kopie(l.basis, sx, sy, kZachtWielVervolg));
      if (l.dx == 0 && l.dy == 0) klaar.add(apparaat);
    });
    klaar.forEach(_lopend.remove);
    if (stappen.isNotEmpty) {
      // Na de terugroepen van dit beeld en vóór het bouwen: dan ziet dit beeld de nieuwe stand al.
      scheduleMicrotask(() => door(ui.PointerDataPacket(data: stappen)));
    }
    if (_lopend.isEmpty) {
      _vorige = null;
    } else {
      _volgende();
    }
  }

  static ui.PointerData _kopie(ui.PointerData d, double sx, double sy, int merk) => ui.PointerData(
        viewId: d.viewId,
        embedderId: merk,
        timeStamp: d.timeStamp,
        change: d.change,
        kind: d.kind,
        signalKind: d.signalKind,
        device: d.device,
        pointerIdentifier: d.pointerIdentifier,
        physicalX: d.physicalX,
        physicalY: d.physicalY,
        buttons: d.buttons,
        obscured: d.obscured,
        synthesized: d.synthesized,
        platformData: d.platformData,
        scrollDeltaX: sx,
        scrollDeltaY: sy,
      );
}

class _Lopend {
  _Lopend(this.basis);
  ui.PointerData basis;
  double dx = 0, dy = 0;
}
