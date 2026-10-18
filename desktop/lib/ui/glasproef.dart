/// De glasproef: alle effecten van 18-10-2026 tegelijk, twaalf seconden lang, met een meting erbij.
///
/// **Waarom dit bestaat.** Saber koos "proefpagina + metingen per toestel, strenge lat" vóór de
/// uitgave. Elk effect apart is op een toestel goedkoop; samen — glas over een bewegende kop, een
/// draaiende cd met glans, een hoes die kantelt en omdraait, het eiland in de wachtrij — is wat telt.
/// Deze pagina zet ze naast elkaar, laat de lijst eronder op en neer schuiven (zodat het glas iets te
/// vervagen heeft), en telt intussen elk getekend beeld.
///
/// **De lat.** Het budget is dat van de glasbewaker voor dít scherm ([glasBudgetVoor]): 85 % van een
/// beeld, nooit krapper dan 7 ms. De proef haalt hem als het 90e percentiel van bouwen én van
/// rasteren eronder blijft en hooguit 5 % van de beelden erboven komt. Het oordeel staat op het
/// scherm en gaat naar het logboek ([meld]); op een telefoon of iPad komt het via de warmtemeter ook
/// in `warmte.log` op de pc terecht.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../tv.dart';
import 'draaihoes.dart';
import 'getekende_schijf.dart';
import 'glas.dart';
import 'kantel_hoes.dart';
import 'kleuren.dart';
import 'langzame_draai.dart';
import 'typografie.dart';
import 'vlak.dart';
import 'wachtrij_eiland.dart';

/// Hoe lang de proef loopt.
const Duration kGlasproefDuur = Duration(seconds: 12);

/// Hoeveel beelden boven het budget mogen komen.
const double kGlasproefTeLaat = .05;

/// Wat de proef mat.
@immutable
class GlasproefUitslag {
  const GlasproefUitslag({
    required this.beelden,
    required this.bouwP90,
    required this.rasterP90,
    required this.slechtste,
    required this.teLaat,
    required this.budget,
    required this.hz,
  });

  final int beelden;
  final Duration bouwP90, rasterP90, slechtste, budget;

  /// Hoeveel beelden (bouwen of rasteren) boven het budget kwamen.
  final int teLaat;
  final double hz;

  bool get gehaald =>
      beelden > 0 && bouwP90 <= budget && rasterP90 <= budget && teLaat <= beelden * kGlasproefTeLaat;

  static String _ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1).replaceAll('.', ',');

  /// Eén regel, voor het scherm en het logboek.
  String get zin => beelden == 0
      ? 'Glasproef: geen beelden gemeten'
      : 'Glasproef ${gehaald ? 'gehaald' : 'te zwaar'}: $beelden beelden op ${hz.round()} Hz, '
          'p90 bouwen ${_ms(bouwP90)} ms, rasteren ${_ms(rasterP90)} ms, slechtste ${_ms(slechtste)} ms, '
          '$teLaat boven ${_ms(budget)} ms';

  /// Uit losse beeldtijden (in microseconden).
  static GlasproefUitslag uit(List<(int bouw, int raster)> tijden, {required double hz}) {
    final budget = glasBudgetVoor(hz);
    if (tijden.isEmpty) {
      return GlasproefUitslag(
          beelden: 0, bouwP90: Duration.zero, rasterP90: Duration.zero, slechtste: Duration.zero, teLaat: 0, budget: budget, hz: hz);
    }
    int p90(List<int> v) {
      final s = [...v]..sort();
      return s[((s.length - 1) * .9).round()];
    }

    final bouw = [for (final t in tijden) t.$1];
    final raster = [for (final t in tijden) t.$2];
    final grens = budget.inMicroseconds;
    return GlasproefUitslag(
      beelden: tijden.length,
      bouwP90: Duration(microseconds: p90(bouw)),
      rasterP90: Duration(microseconds: p90(raster)),
      slechtste: Duration(microseconds: [for (final t in tijden) math.max(t.$1, t.$2)].reduce(math.max)),
      teLaat: tijden.where((t) => t.$1 > grens || t.$2 > grens).length,
      budget: budget,
      hz: hz,
    );
  }
}

class Glasproef extends StatefulWidget {
  const Glasproef({super.key, this.hoes});

  /// Een hoes om mee te proeven (die van wat er speelt); zonder: een paars vlak.
  final Uint8List? hoes;

  /// Waar het oordeel heen gaat (kop.log en debugPrint in de app).
  static void Function(String regel)? meld;

  /// In een toets: het schermritme.
  @visibleForTesting
  static double? hzVoorToets;

  @override
  State<Glasproef> createState() => _GlasproefState();
}

class _GlasproefState extends State<Glasproef> with TickerProviderStateMixin {
  final _rol = ScrollController();
  final _draai = DraaiHoesController();
  late final LangzameDraai _cd = LangzameDraai(this, omwenteling: const Duration(seconds: 9), maxBeeldenPerSeconde: 1000);
  final _tijden = <(int, int)>[];
  Timer? _klok, _stap;
  int _tel = 0;
  bool _schuin = false;
  GlasproefUitslag? _uitslag;

  /// Staat [_haak] aangemeld? Afmelden zonder aanmelding is in Flutter een fout.
  bool _luistert = false;

  void _luister(bool aan) {
    if (aan == _luistert) return;
    _luistert = aan;
    aan ? SchedulerBinding.instance.addTimingsCallback(_haak) : SchedulerBinding.instance.removeTimingsCallback(_haak);
  }
  void _haak(List<FrameTiming> lijst) {
    for (final t in lijst) {
      _tijden.add((t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  void _begin() {
    if (!mounted) return;
    _tijden.clear();
    _uitslag = null;
    _tel = 0;
    _luister(true);
    _cd.start();
    // Elke 1,5 s iets anders: omdraaien, kantelen, de lijst op en neer.
    _stap = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      _tel++;
      setState(() => _schuin = !_schuin);
      if (_tel % 2 == 0) _draai.draai(heeftAchterkant: true);
      if (_rol.hasClients) {
        final doel = _tel.isOdd ? _rol.position.maxScrollExtent : 0.0;
        _rol.animateTo(doel, duration: const Duration(milliseconds: 1200), curve: Curves.easeInOut);
      }
    });
    _klok = Timer(kGlasproefDuur, _klaar);
    setState(() {});
  }

  void _klaar() {
    _stap?.cancel();
    _cd.stop();
    _luister(false);
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final hz = Glasproef.hzVoorToets ?? (views.isEmpty ? 60.0 : views.first.display.refreshRate);
    final u = GlasproefUitslag.uit(_tijden, hz: hz <= 0 ? 60 : hz);
    final regel = '${u.zin} | glas ${GlasKwaliteit.stand.value.name} | thema ${Thema.licht ? 'licht' : 'donker'}'
        '${isTv ? ' | tv' : ''}';
    Glasproef.meld?.call(regel);
    if (mounted) setState(() => _uitslag = u);
  }

  @override
  void dispose() {
    _klok?.cancel();
    _stap?.cancel();
    _luister(false);
    _cd.dispose();
    _rol.dispose();
    _draai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hoes = widget.hoes;
    Widget beeld(double m) => hoes != null
        ? Image.memory(hoes, width: m, height: m, fit: BoxFit.cover, gaplessPlayback: true)
        : SizedBox.square(dimension: m, child: ColoredBox(color: kAccent));
    final u = _uitslag;
    return Scaffold(
      backgroundColor: kAchtergrond,
      body: BackdropGroup(
        child: Stack(children: [
          if (hoes != null) Positioned.fill(child: HoesAchtergrond(beeld: MemoryImage(hoes), hoogte: 420, rol: _rol)),
          ListView(
            controller: _rol,
            padding: const EdgeInsets.fromLTRB(24, 90, 24, 140),
            children: [
              Wrap(spacing: 28, runSpacing: 24, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox.square(
                  dimension: 180,
                  child: KantelHoes(
                    bron: KantelBron.selectie,
                    aan: _schuin,
                    vorm: BorderRadius.circular(10),
                    child: DraaiHoes(
                      controller: _draai,
                      voor: ClipRRect(borderRadius: BorderRadius.circular(10), child: beeld(180)),
                      achter: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ColoredBox(color: kPaneelHoog, child: Center(child: Text('Achterkant', style: kTekstBij))),
                      ),
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: 170,
                  child: Stack(alignment: Alignment.center, children: [
                    AnimatedBuilder(
                      animation: _cd,
                      builder: (_, kind) => Transform.rotate(angle: _cd.value * 2 * math.pi, child: kind),
                      child: RepaintBoundary(
                        child: hoes != null ? GetekendeCd(label: hoes, maat: 170) : const SizedBox.square(dimension: 170),
                      ),
                    ),
                    const CdGlans(maat: 170),
                  ]),
                ),
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GlasKnop(icoon: Icons.play_arrow_rounded, label: 'Afspelen', onPressed: () {}),
                  const SizedBox(height: 10),
                  GlasKnop(icoon: Icons.radio_rounded, label: 'Radio', onPressed: () {}),
                ]),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: 360,
                child: WachtrijEiland(
                  hoes: hoes,
                  speelt: true,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('Wat er nu speelt', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: kFel)),
                    Text('in de wachtrij', style: TextStyle(fontSize: 12, color: kGedempt)),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
              for (var i = 1; i <= 30; i++)
                Container(
                  height: 48,
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: kPaneel, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.centerLeft,
                  child: Text('Regel $i — iets om onder het glas door te schuiven', style: kTekstNormaal),
                ),
            ],
          ),
          // Bovenaan: wat de proef zegt. Onderaan: een spelerbalk van glas.
          Positioned(
            left: 16,
            right: 16,
            top: 16 + MediaQuery.paddingOf(context).top,
            child: GlasVlak(
              key: const ValueKey('glasproef-kop'),
              vorm: const BorderRadius.all(Radius.circular(18)),
              kleur: kBovenop,
              balk: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      u?.zin ?? 'Glasproef loopt — ${kGlasproefDuur.inSeconds} seconden…',
                      key: const ValueKey('glasproef-uitslag'),
                      style: kTekstNormaal.copyWith(
                          color: u == null ? kTekst : (u.gehaald ? leesbaar(const Color(0xFF6BCB8B)) : leesbaar(const Color(0xFFFF6B6B)))),
                    ),
                  ),
                  if (u != null)
                    TextButton(key: const ValueKey('glasproef-opnieuw'), onPressed: _begin, child: const Text('Opnieuw')),
                  IconButton(
                    tooltip: 'Sluiten',
                    icon: Icon(Icons.close_rounded, color: kGedempt),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ]),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            height: 72,
            child: GlasVlak(
              vorm: const BorderRadius.all(Radius.circular(22)),
              kleur: kBovenop,
              balk: true,
              child: Row(children: [
                const SizedBox(width: 12),
                ClipRRect(borderRadius: BorderRadius.circular(6), child: beeld(48)),
                const SizedBox(width: 12),
                Expanded(child: Text('Spelerbalk van glas', style: kTekstNormaal)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
