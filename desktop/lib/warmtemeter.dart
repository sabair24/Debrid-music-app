/// Wat een toestel tekent en doet terwijl je het gebruikt — gemeten op het toestel zelf, en
/// opgeschreven op de pc.
///
/// **Waarom dit bestaat.** Saber, 10-10-2026: *"de ipad wordt nog altijd extreem warm heet zelf, bij
/// album detailscreen ook en now playing, eigenlijk overal"*. Twee dagen eerder was er een oorzaak
/// gevonden en gerepareerd (3.9.454: Nu speelt stond op `opaque: false`), op redenering en een toets —
/// want een iPad hangt niet aan adb en stuurt geen logboeken naar de pc. Hij bleef heet. Een tweede
/// gok zonder meting zou hetzelfde lot hebben; dit is de meetlat.
///
/// Per venster van tien seconden één regel: hoeveel beelden er getekend werden en wat ze kostten
/// (bouwen op de UI-draad, rasteren op de GPU-draad), hoe lang de UI-draad BUITEN het tekenen
/// bezig was, hoeveel tikkers er liepen, en WELKE animaties dat zijn en in welk scherm. Op de iPad
/// erbij: de warmtestand van iOS en de batterij. Elke halve minuut gaan de regels naar de pc, die ze
/// in `warmte.log` zet.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'cloud/device_identity.dart';
import 'ui/langzame_draai.dart';

/// Wat er in één venster gemeten is.
class Warmtestaal {
  const Warmtestaal({
    required this.ms,
    required this.beelden,
    required this.buildGemUs,
    required this.buildMaxUs,
    required this.rasterGemUs,
    required this.rasterMaxUs,
    required this.draadVertraagdMs,
    required this.tikkers,
    required this.animaties,
    required this.glas,
    this.extra = '',
    this.toestel,
  });

  final int ms;
  final int beelden;
  final int buildGemUs, buildMaxUs;
  final int rasterGemUs, rasterMaxUs;

  /// Hoeveel later dan gepland een klok van 100 ms afging, opgeteld over het venster. Dat is tijd
  /// dat de UI-draad met iets anders bezig was — tekenen, maar ook alles wat geen beeld oplevert.
  final int draadVertraagdMs;

  /// [SchedulerBinding.transientCallbackCount] op het einde van het venster: elke lopende tikker
  /// (AnimationController, Ticker) vraagt elk schermbeeld om een nieuw beeld.
  final int tikkers;

  /// Lopende animaties, per soort en plek. Zie [lopendeAnimaties].
  final Map<String, int> animaties;

  /// Hoeveel glasvlakken (BackdropFilter) er in de boom staan. Elk kost bij elk beeld een vervaging
  /// van wat eronder ligt.
  final int glas;

  /// Wat de app erbij vertelt: speelt er iets, welk scherm.
  final String extra;

  /// Warmte en batterij van het toestel zelf, als het die geeft. Zie [Warmtemeter.toestelstand].
  final String? toestel;
}

String _ms(int us) => (us / 1000).toStringAsFixed(1);

/// De regel voor `warmte.log`.
String warmteRegel(Warmtestaal s) {
  final sec = s.ms / 1000;
  final bps = sec <= 0 ? 0.0 : s.beelden / sec;
  final anim = s.animaties.isEmpty
      ? 'geen'
      : (s.animaties.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => e.value == 1 ? e.key : '${e.key} ×${e.value}')
          .join(', ');
  return '${bps.toStringAsFixed(1)} beelden/s (${s.beelden} in ${sec.toStringAsFixed(1)} s) | '
      'bouwen ${_ms(s.buildGemUs)}/${_ms(s.buildMaxUs)} ms | '
      'rasteren ${_ms(s.rasterGemUs)}/${_ms(s.rasterMaxUs)} ms | '
      'draad vertraagd ${s.draadVertraagdMs} ms | '
      'tikkers ${s.tikkers} | glas ${s.glas} | '
      'animaties: $anim'
      '${s.extra.isEmpty ? '' : ' | ${s.extra}'}'
      '${s.toestel == null ? '' : ' | ${s.toestel}'}';
}

/// Loopt deze animatie nu? Een [AnimationStatus] alleen zegt het niet: een stilgezette controller
/// blijft op `forward` staan, en [AlwaysStoppedAnimation] staat er zelfs altijd op. Dus terug naar
/// de controller eronder.
bool animatieLoopt(Listenable? l) {
  Object? a = l;
  for (var i = 0; i < 12 && a != null; i++) {
    if (a is AnimationController) return a.isAnimating;
    if (a is LangzameDraai) return a.isAnimating;
    if (a is CompoundAnimation) return animatieLoopt(a.first) || animatieLoopt(a.next);
    if (a is AnimationWithParentMixin) {
      a = a.parent;
    } else if (a is ReverseAnimation) {
      a = a.parent;
    } else if (a is ProxyAnimation) {
      a = a.parent;
    } else if (a is TrainHoppingAnimation) {
      a = a.currentTrain;
    } else {
      return false;
    }
  }
  return false;
}

/// Widgets die niets zeggen over WAAR iets staat: overslaan bij het noemen van de plek.
const _kaal = {
  'Padding', 'Align', 'Center', 'SizedBox', 'Container', 'DecoratedBox', 'ConstrainedBox',
  'Semantics', 'RepaintBoundary', 'KeyedSubtree', 'Builder', 'LayoutBuilder', 'Expanded',
  'Flexible', 'Row', 'Column', 'Stack', 'Positioned', 'ClipRRect', 'ClipOval', 'ClipRect',
  'ClipPath', 'Opacity', 'Transform', 'DefaultTextStyle', 'IconTheme', 'Material', 'InkWell',
  'GestureDetector', 'MouseRegion', 'Listener', 'AnimatedBuilder', 'ListenableBuilder',
  'FadeTransition', 'RotationTransition', 'ScaleTransition', 'SlideTransition', 'CustomPaint',
  'AspectRatio', 'FittedBox', 'IgnorePointer', 'AbsorbPointer', 'MediaQuery', 'Theme',
  'Directionality', 'NotificationListener', 'Focus', 'Actions', 'Shortcuts', 'Flex', 'Wrap',
  'ValueListenableBuilder', 'StreamBuilder', 'FutureBuilder', 'Tooltip', 'Hero', 'Offstage',
  'TickerMode', 'Visibility', 'SafeArea', 'ColoredBox', 'Card', 'Ink', 'Text', 'RichText',
  'Icon', 'Image', 'RawImage', 'BackdropFilter', 'ImageFiltered', 'ShaderMask',
  'MergeSemantics', 'ExcludeSemantics', 'IndexedSemantics', 'AutomaticKeepAlive',
  'SliverToBoxAdapter', 'KeepAlive', 'InkResponse', 'ElevatedButton', 'TextButton',
  'IconButton', 'OutlinedButton', 'FilledButton', 'PhysicalModel', 'AnimatedSwitcher',
  'AnimatedOpacity', 'AnimatedContainer', 'Consumer', 'Selector', 'ProgressIndicator',
  'CircularProgressIndicator', 'LinearProgressIndicator', 'UnconstrainedBox', 'LimitedBox',
  'OverflowBox', 'FractionallySizedBox', 'IntrinsicHeight', 'IntrinsicWidth', 'Spacer',
  'MaterialApp', 'WidgetsApp', 'CupertinoApp', 'View', 'RawView', 'RootWidget',
  'CustomMultiChildLayout', 'MultiProvider', 'Provider', 'ChangeNotifierProvider',
};

/// Het raderwerk van routes, overgangen en focus boven een pagina. Geen plek, dus ook geen scherm.
final _raderwerk = RegExp(r'(Transition|Focus|Scroll|PageStorage|Restoration|Hero|Overlay|'
    r'Navigator|Actions|Shortcuts|Scope|Builder|Trap|LayoutId|Layout$|Scaffold|Ticker|Offstage|'
    r'Semantics|Listener|Notification|Lookup|Banner|Title|Localizations|Theme|Media|Directionality|'
    r'^Animated|Snapshot|PhysicalModel|DefaultTextStyle)');

/// Waar een element staat: de dichtstbijzijnde twee eigen widgets, en tussen rechte haken het
/// scherm — de verste eigen widget binnen dezelfde route, dus de pagina.
String plekVan(Element e) {
  final namen = <String>[];
  var stappen = 0;
  e.visitAncestorElements((a) {
    final naam = a.widget.runtimeType.toString().split('<').first;
    // De grens van de route: wat erboven staat hoort bij de app, niet bij dit scherm.
    if (naam == '_ModalScopeStatus' || naam == 'Navigator') return false;
    final kaal = _kaal.contains(naam) ||
        (naam.startsWith('_') && _kaderPrive.hasMatch(naam)) ||
        _raderwerk.hasMatch(naam);
    if (!kaal && !namen.contains(naam)) namen.add(naam);
    return ++stappen < 400;
  });
  if (namen.isEmpty) return '';
  final dicht = namen.take(2).toList();
  final scherm = namen.last;
  return dicht.contains(scherm) ? ' in ${dicht.join(' ← ')}' : ' in ${dicht.join(' ← ')} ← [$scherm]';
}

/// Privéwidgets van Flutter zelf, op hun naam herkend. Niet volledig — dit is voor het lezen.
final _kaderPrive = RegExp(
    r'^_(Inherited|Effective|Modal|Overlay|Theater|Ink|Semantics|Gesture|Pointer|Focus|Shortcuts|'
    r'Actions|Scroll|Viewport|Sliver|Snapshot|Keep|Localizations|Media|Selection|Default|Lookup|'
    r'Change|Provider|Notifier|Listener|Mouse|Raw|Material|Animated|Fade|Zoom|Cupertino|Page|'
    r'Hero|Tooltip|Text|Icon|Button|Nested|Value|Stream|Future|Build|Shared|Single|Theme|Route|'
    r'Restoration|Pop|Window|Shortcut|Action|Draggable|Gl|Platform|Visibility|Render|Inkwell|'
    r'Ticker|Positioned|Primary|Adaptive|Layout|Interactive|Indicator|Progress|Circular|Linear)');

/// De lopende animaties in de boom, per soort en plek, en het aantal glasvlakken.
///
/// Drie soorten: een [AnimatedWidget] (RotationTransition, FadeTransition, AnimatedBuilder…) waarvan
/// de animatie loopt — ook de draaiende cd ([LangzameDraai]) en de skeletglans; een
/// voortgangsindicator zonder waarde (die draait eindeloos); en niets wat onder een uitgezette
/// [TickerMode] staat, want die tikt niet.
({Map<String, int> animaties, int glas}) lopendeAnimaties(Element wortel) {
  final uit = <String, int>{};
  var glas = 0;
  var bezocht = 0;
  void bezoek(Element e) {
    if (++bezocht > 60000) return;
    final w = e.widget;
    if (w is BackdropFilter) glas++;
    String? soort;
    if (w is AnimatedWidget) {
      final l = w.listenable;
      if (animatieLoopt(l)) {
        soort = l is LangzameDraai ? 'cd (LangzameDraai)' : w.runtimeType.toString().split('<').first;
      }
    } else if (w is ProgressIndicator && w.value == null) {
      soort = '${w.runtimeType} (eindeloos)';
    }
    if (soort != null && TickerMode.getNotifier(e).value) {
      final sleutel = '$soort${plekVan(e)}';
      uit[sleutel] = (uit[sleutel] ?? 0) + 1;
    }
    // Een draaier bouwt zelf een AnimatedBuilder op zijn eigen controller: niet twee keer tellen.
    if (w is ProgressIndicator && soort != null) return;
    e.visitChildElements(bezoek);
  }

  bezoek(wortel);
  return (animaties: uit, glas: glas);
}

/// De meetlat zelf. Eén per app; [start] na het koppelen, [stop] bij het afsluiten.
class Warmtemeter {
  Warmtemeter({
    required this.stuur,
    this.extra,
    this.venster = const Duration(seconds: 10),
    this.perZending = 3,
    this.toestelstand = iosToestelstand,
  });

  /// Stuurt een bundel regels naar de pc. Gooit bij een fout; de regels blijven dan bewaard.
  final Future<void> Function(List<String> regels) stuur;

  /// Wat de app erbij wil zeggen, zoals "speelt" — bij elk venster gevraagd.
  final String Function()? extra;

  final Duration venster;

  /// Na hoeveel vensters er verstuurd wordt.
  final int perZending;

  /// Warmte en batterij, of null als het toestel die niet geeft.
  final Future<String?> Function() toestelstand;

  /// Hoeveel regels er hoogstens wachten als de pc even weg is.
  static const int kBewaar = 60;

  final List<String> _wachtrij = [];
  Timer? _vensterKlok, _draadKlok;
  TimingsCallback? _haak;
  int _beelden = 0, _buildUs = 0, _buildMaxUs = 0, _rasterUs = 0, _rasterMaxUs = 0;
  int _vertraagdUs = 0;
  int _beginMs = 0;
  int _vensters = 0;
  bool _bezig = false;
  final Stopwatch _draad = Stopwatch();

  bool get loopt => _vensterKlok != null;

  /// De regels die nog niet verstuurd zijn. Voor de toets.
  List<String> get wachtend => List.unmodifiable(_wachtrij);

  void start() {
    if (loopt) return;
    _haak = _tel;
    SchedulerBinding.instance.addTimingsCallback(_haak!);
    _nieuwVenster();
    _draad
      ..reset()
      ..start();
    // Een klok van 100 ms die meet hoe laat hij afgaat. Te laat = de draad was bezig.
    _draadKlok = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final us = _draad.elapsedMicroseconds;
      _draad
        ..reset()
        ..start();
      final te = us - 100000;
      if (te > 0) _vertraagdUs += te > 2000000 ? 2000000 : te;
    });
    _vensterKlok = Timer.periodic(venster, (_) => unawaited(sluitVenster()));
  }

  void stop() {
    _vensterKlok?.cancel();
    _vensterKlok = null;
    _draadKlok?.cancel();
    _draadKlok = null;
    final h = _haak;
    if (h != null) SchedulerBinding.instance.removeTimingsCallback(h);
    _haak = null;
  }

  void _nieuwVenster() {
    _beelden = 0;
    _buildUs = 0;
    _buildMaxUs = 0;
    _rasterUs = 0;
    _rasterMaxUs = 0;
    _vertraagdUs = 0;
    _beginMs = DateTime.now().millisecondsSinceEpoch;
  }

  void _tel(List<FrameTiming> t) {
    for (final f in t) {
      _beelden++;
      final b = f.buildDuration.inMicroseconds;
      final r = f.rasterDuration.inMicroseconds;
      _buildUs += b;
      _rasterUs += r;
      if (b > _buildMaxUs) _buildMaxUs = b;
      if (r > _rasterMaxUs) _rasterMaxUs = r;
    }
  }

  /// Sluit het venster: één regel erbij, en na [perZending] vensters naar de pc. Openbaar voor de
  /// toets; normaal roept de klok hem aan.
  Future<void> sluitVenster({Element? wortel}) async {
    final nu = DateTime.now().millisecondsSinceEpoch;
    final ms = nu - _beginMs;
    final beelden = _beelden;
    final staal = (
      beelden: beelden,
      buildGem: beelden == 0 ? 0 : _buildUs ~/ beelden,
      buildMax: _buildMaxUs,
      rasterGem: beelden == 0 ? 0 : _rasterUs ~/ beelden,
      rasterMax: _rasterMaxUs,
      vertraagd: _vertraagdUs ~/ 1000,
    );
    _nieuwVenster();
    final w = wortel ?? WidgetsBinding.instance.rootElement;
    final telling = w == null ? (animaties: const <String, int>{}, glas: 0) : lopendeAnimaties(w);
    String? stand;
    try {
      stand = await toestelstand();
    } catch (_) {/* een toestel zonder warmtestand is geen fout */}
    _wachtrij.add(warmteRegel(Warmtestaal(
      ms: ms,
      beelden: staal.beelden,
      buildGemUs: staal.buildGem,
      buildMaxUs: staal.buildMax,
      rasterGemUs: staal.rasterGem,
      rasterMaxUs: staal.rasterMax,
      draadVertraagdMs: staal.vertraagd,
      tikkers: SchedulerBinding.instance.transientCallbackCount,
      animaties: telling.animaties,
      glas: telling.glas,
      extra: extra?.call() ?? '',
      toestel: stand,
    )));
    if (_wachtrij.length > kBewaar) _wachtrij.removeRange(0, _wachtrij.length - kBewaar);
    if (++_vensters % perZending == 0) await verstuur();
  }

  /// Alles wat wacht naar de pc. Lukt het niet, dan blijft het staan voor de volgende keer.
  Future<void> verstuur() async {
    if (_bezig || _wachtrij.isEmpty) return;
    _bezig = true;
    final bundel = List<String>.of(_wachtrij);
    try {
      await stuur(bundel);
      _wachtrij.removeRange(0, bundel.length);
    } catch (_) {
      // De pc slaapt of is te oud (404): bewaren tot [kBewaar], de oudste eerst eruit.
    } finally {
      _bezig = false;
    }
  }
}

/// Hoe een toestel in `warmte.log` heet: zijn naam en platform, en het scherm — pixels en
/// verversing, want daarin verschilt een iPad (120 Hz, veel pixels, glas aan) van de telefoon.
String warmteToestel(DeviceIdentity ik) {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return '${ik.name} (${ik.platform})';
  final v = views.first;
  final s = v.physicalSize;
  return '${ik.name} (${ik.platform}, ${s.width.round()}×${s.height.round()} px, '
      '${v.display.refreshRate.round()} Hz)';
}

const _warmteKanaal = MethodChannel('debridmusic/warmte');

/// De warmtestand van iOS (`ProcessInfo.thermalState`) en de batterij. Op elk ander toestel null.
///
/// iOS kent vier standen: normaal, licht (fair), ernstig (serious: het systeem remt al af) en
/// kritiek. Dat is wat "heet" op een iPad meetbaar maakt zonder kabel.
Future<String?> iosToestelstand() async {
  if (!Platform.isIOS) return null;
  final m = await _warmteKanaal.invokeMapMethod<String, Object?>('stand');
  if (m == null) return null;
  return toestelstandTekst(
    warmte: (m['warmte'] as num?)?.toInt(),
    batterij: (m['batterij'] as num?)?.toDouble(),
    laden: (m['laden'] as num?)?.toInt(),
  );
}

/// [iosToestelstand] als tekst; los, zodat een toets hem kan nalopen.
String toestelstandTekst({int? warmte, double? batterij, int? laden}) {
  const standen = ['normaal', 'licht warm', 'WARM (iOS remt af)', 'HEET (kritiek)'];
  final w = warmte == null || warmte < 0 || warmte >= standen.length ? '?' : standen[warmte];
  final b = batterij == null || batterij < 0 ? '?' : '${(batterij * 100).round()} %';
  const ladenTekst = {1: 'op batterij', 2: 'laadt', 3: 'vol aan de lader'};
  return 'warmte $w, batterij $b${ladenTekst[laden] == null ? '' : ' ${ladenTekst[laden]}'}';
}
