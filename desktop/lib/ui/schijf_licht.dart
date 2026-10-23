/// Licht en schaduw van een draaiende schijf, met een shader (Saber, 19-10-2026: "de draaiende cd meer
/// effect geven met schaduw, zo dat het realistisch wordt. Gebruik daarvoor shaders"; hij koos het
/// niveau "Echt, licht stil", echte scans alleen de schaduwen, vinyl een eigen versie).
///
/// **Eén keer bakken, dan alleen leggen.** Wat hier getekend wordt is rond (verandert niet als de schijf
/// draait) of hangt aan het licht (staat stil, zoals de regenboog op een echte cd). Dus rekent de shader
/// één keer per maat, en wordt de uitkomst een afbeelding die per beeld alleen gelegd wordt. Waarom niet
/// gewoon een CustomPaint met de shader: onder Impeller (gsm, iPad, Shield) is er geen rastergeheugen,
/// en dan rekent een shader in een vaste tekening alsnog elk beeld opnieuw — zolang de cd draait, 60 keer
/// per seconde over het hele vlak. De iPad werd al eens heet van wat per beeld rekent (10-10-2026).
///
/// **Geen menging met wat eronder ligt.** De afbeeldingen liggen gewoon doorzichtig over de schijf; een
/// menging als "screen" leest de draaiende schijf elk beeld terug (Shield, 18-10-2026: 16,8 → 7,3 ms).
///
/// Laadt de shader niet (een oud toestel, een fout), dan blijft het zoals het was: [CdGlans].
library;

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../meetronde.dart' show zonderVoorMeting;
import 'getekende_schijf.dart';
import 'kleuren.dart' show Thema;

/// Wat voor schijf: een getekende cd, een getekende vinylplaat, of een echte scan (alleen schaduw).
enum SchijfSoort { cd, vinyl, scan }

/// De richting NAAR het licht, met y omlaag: linksboven, zoals de lichtrand van het glas.
const Offset kSchijfLichtRichting = Offset(-.6, -.8);

/// Hoeveel groter dan de schijf het vlak van de grondschaduw is.
const double kGrondschaduwVlak = 1.3;

/// De shader en het geheugen met gebakken lagen.
class SchijfLicht {
  SchijfLicht._();

  static ui.FragmentProgram? _programma;

  /// Gebakken lagen, op soort, laag, pixelmaat en thema. Hoogstens [_max]; de oudste gaat eruit.
  static final _bak = LinkedHashMap<String, ui.Image>();
  static const _max = 24;

  /// Hoe vaak er gebakken is — voor de toetsen: draaien mag dit nooit ophogen.
  @visibleForTesting
  static int gebakken = 0;

  static bool get klaar => _programma != null;

  /// Gaat aan zodra de shader geladen is. Het laden wacht niet op het eerste beeld: tot dan tekenen de
  /// lagen de oude glans, en daarna vanzelf de nieuwe.
  static final geladen = ValueNotifier<bool>(false);

  /// Eén keer bij het opstarten. Bakt meteen een klein voorbeeld: Skia (de pc) vertaalt een shader pas bij
  /// het eerste gebruik, en dan haperde de eerste cd die uitschoof.
  static Future<void> laad() async {
    if (_programma != null) return;
    try {
      _programma = await ui.FragmentProgram.fromAsset('shaders/schijf_licht.frag');
      beeld(px: 32, soort: SchijfSoort.cd, laag: 0, donker: true);
      geladen.value = true;
    } catch (e) {
      debugPrint('schijf_licht: shader niet geladen ($e) — de glans blijft zoals hij was');
      _programma = null;
    }
  }

  /// Leeg het geheugen; voor toetsen. [ookShader]: alsof hij nooit geladen is (de terugval).
  @visibleForTesting
  static void vergeet({bool ookShader = false}) {
    _bak.clear();
    gebakken = 0;
    if (ookShader) {
      _programma = null;
      geladen.value = false;
    }
  }

  /// De gebakken laag: 0 = het licht op de schijf ([px] is de doorsnede), 1 = de grondschaduw (het vlak
  /// is [kGrondschaduwVlak] keer zo groot). Null zonder shader.
  ///
  /// [etiket] is de straal van het etiket als deel van de straal van de schijf: daar komt geen regenboog.
  static ui.Image? beeld(
      {required int px,
      required SchijfSoort soort,
      required int laag,
      required bool donker,
      double etiket = kSchijfEtiket}) {
    final programma = _programma;
    if (programma == null || px < 8) return null;
    final zijde = laag == 1 ? (px * kGrondschaduwVlak).round() : px;
    // Begrensd: boven 1400 pixels is er geen detail meer dat dit vraagt, en het geheugen telt.
    final z = zijde.clamp(8, 1400);
    final sleutel = '${soort.index}|$laag|$z|${donker ? 1 : 0}|${(etiket * 100).round()}';
    final al = _bak.remove(sleutel);
    if (al != null) {
      _bak[sleutel] = al; // achteraan: het laatst gebruikt
      return al;
    }
    final shader = programma.fragmentShader()
      ..setFloat(0, z.toDouble())
      ..setFloat(1, z.toDouble())
      ..setFloat(2, soort.index.toDouble())
      ..setFloat(3, etiket)
      ..setFloat(4, donker ? 1 : 0)
      ..setFloat(5, laag.toDouble())
      ..setFloat(6, kSchijfLichtRichting.dx)
      ..setFloat(7, kSchijfLichtRichting.dy)
      ..setFloat(8, laag == 1 ? 1 / kGrondschaduwVlak : 1)
      ..setFloat(9, 0);
    final opname = ui.PictureRecorder();
    Canvas(opname).drawRect(Rect.fromLTWH(0, 0, z.toDouble(), z.toDouble()), Paint()..shader = shader);
    final plaat = opname.endRecording();
    final uit = plaat.toImageSync(z, z);
    plaat.dispose();
    shader.dispose();
    gebakken++;
    _bak[sleutel] = uit;
    // Niet zelf weggooien wat eruit valt: een RawImage kan hem nog tekenen. De afbeelding ruimt zichzelf
    // op zodra niemand hem meer vasthoudt.
    while (_bak.length > _max) {
      _bak.remove(_bak.keys.first);
    }
    return uit;
  }
}

/// Het licht op een schijf van [maat] punten: legt over de draaiende schijf, draait zelf niet mee.
///
/// Zonder shader de oude [CdGlans] (en op een echte scan niets).
class SchijfLichtLaag extends StatelessWidget {
  const SchijfLichtLaag({super.key, required this.maat, required this.soort, this.etiket = kSchijfEtiket});
  final double maat;
  final SchijfSoort soort;
  final double etiket;

  @override
  Widget build(BuildContext context) => zonderVoorMeting('licht')
      ? const SizedBox.shrink()
      : ValueListenableBuilder<bool>(
      valueListenable: SchijfLicht.geladen, builder: (context, _, __) => _bouw(context));

  Widget _bouw(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final b = SchijfLicht.beeld(
        px: (maat * dpr).round(), soort: soort, laag: 0, donker: !Thema.licht, etiket: etiket);
    if (b == null) {
      return soort == SchijfSoort.scan
          ? SizedBox.square(dimension: maat)
          : CdGlans(maat: maat, vinyl: soort == SchijfSoort.vinyl);
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: RawImage(
          key: const ValueKey('schijf-licht'),
          image: b,
          width: maat,
          height: maat,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// De schaduw van een schijf van [maat] punten op de grond eronder: een zachte schijf, iets van het
/// licht af. Groter dan de schijf zelf, gecentreerd erop; neemt zelf alleen [maat] aan ruimte in.
class SchijfGrondschaduw extends StatelessWidget {
  const SchijfGrondschaduw({super.key, required this.maat});
  final double maat;

  @override
  Widget build(BuildContext context) => zonderVoorMeting('licht')
      ? const SizedBox.shrink()
      : ValueListenableBuilder<bool>(
      valueListenable: SchijfLicht.geladen, builder: (context, _, __) => _bouw(context));

  Widget _bouw(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final b = SchijfLicht.beeld(px: (maat * dpr).round(), soort: SchijfSoort.cd, laag: 1, donker: !Thema.licht);
    if (b == null) return SizedBox.square(dimension: maat);
    final vlak = maat * kGrondschaduwVlak;
    return IgnorePointer(
      child: SizedBox.square(
        dimension: maat,
        child: OverflowBox(
          maxWidth: vlak,
          maxHeight: vlak,
          child: RepaintBoundary(
            child: RawImage(
              key: const ValueKey('schijf-grondschaduw'),
              image: b,
              width: vlak,
              height: vlak,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}

/// De schaduw die de hoes op de schijf werpt, vlak naast zijn rand: waar de schijf onder de hoes
/// vandaan komt, ligt hij in de schaduw van de hoes. [rand] is waar de rand van de hoes ligt, gemeten
/// vanaf de linkerkant van de schijf; die verandert alleen tijdens het uitschuiven.
class MouwSchaduw extends StatelessWidget {
  const MouwSchaduw({super.key, required this.maat, required this.rand});
  final double maat, rand;

  /// Hoe breed de schaduw is, als deel van de schijf.
  static const double breedte = .17;

  @override
  Widget build(BuildContext context) {
    if (rand >= maat || zonderVoorMeting('licht')) return SizedBox.square(dimension: maat);
    final sterk = Thema.licht ? .30 : .46;
    return IgnorePointer(
      child: ClipOval(
        child: SizedBox.square(
          dimension: maat,
          child: Stack(children: [
            Positioned(
              key: const ValueKey('mouw-schaduw'),
              left: rand,
              top: 0,
              bottom: 0,
              width: maat * breedte,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.black.withValues(alpha: sterk),
                    Colors.black.withValues(alpha: sterk * .35),
                    Colors.black.withValues(alpha: 0),
                  ], stops: const [0, .45, 1]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
