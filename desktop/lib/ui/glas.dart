/// Vloeibaar glas (16-10-2026), en de bewaker die het terugzet als het te veel kost.
///
/// **Waarom.** Saber: *"Glas is gewoon doorzichtig, daar moet iets meer blur op, dat de achtergrond
/// beetje vervormd zoals echt glas."* Op een toestel was het glas sinds 3.9.459 een donkere laag
/// zonder vervaging, omdat 10 tot 14 vervagingen boven een draaiende cd de iPad heet maakten (zie
/// [glasZonderVervaging]). Hij koos vloeibaar glas, overal, en "waar het te veel kost, valt het
/// vanzelf terug op matglas".
///
/// **Drie standen ([GlasStand]):**
/// - **plat** — de vulling zonder vervaging. Op een tv altijd; elders als de bewaker het zegt.
/// - **mat** — echte vervaging met wat meer verzadiging en een lichtrand. Alle matte vlakken op een
///   scherm hebben HETZELFDE filter ([glasMat]) en hangen aan één `BackdropGroup` bovenaan de app: de
///   engine leest het scherm dan één keer terug voor allemaal, in plaats van één keer per vlak. Dat
///   laatste was de warme iPad.
/// - **vloeibaar** — mat, plus een lensrand die de achtergrond buigt ([GlasLens], een shader). Elke
///   lens kost een eigen pass, dus alleen op glas dat stil staat: de spelerbalk, de onderbalk, de
///   bovenknoppen van een albumpagina. Alleen onder Impeller (gsm, iPad, Mac).
///
/// **De bewaker ([GlasKwaliteit.bewaak])** leest de tekentijd van elk beeld zolang er glas op het
/// scherm staat. Is het 90e percentiel van [kGlasTeZwaar] meetvensters op rij hoger dan [kGlasBudget],
/// dan gaat het glas één stand omlaag, tot het einde van de sessie. Liever minder glas dan haperen. De
/// eerste [kGlasAanloop] na het opstarten telt hij niet mee.
///
/// **Dicht, zoals Somati (16-10-2026, 3.9.499).** Saber, met twee schermafdrukken van het menu naast
/// twee van zijn Somati-app: *"Alles is veel te transparant."* Onder het menu stond de lijst
/// haarscherp — "Eyes Closed", "FLAC · 24/48" — door een vulling van 74 % en zonder enige vervaging.
/// Somati's regel (zijn CLAUDE.md, "Glas-effect & sheets"): leesbaarheid gaat vóór alles, zware
/// vervaging, een vulling waar je geen tekst meer door leest, en een heldere glasrand. Vandaar
/// [glasVulling] met [kGlasDekking], en [kGlasDekkingPlat] als de vervaging er niet is.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../tv.dart';

enum GlasStand { plat, mat, vloeibaar }

/// De ondergrens van wat een beeld mag kosten om te tekenen (het 90e percentiel), voor het glas
/// terugschakelt. Een scherm van 120 Hz heeft 8,3 ms per beeld; dit laat ruimte voor de rest.
const kGlasBudget = Duration(microseconds: 7000);

/// Welk deel van één beeld het tekenen mag kosten (zie [glasBudgetVoor]).
const kGlasBudgetDeel = .85;

/// Het budget voor een scherm van [hz] beelden per seconde: [kGlasBudgetDeel] van één beeld, nooit
/// krapper dan [kGlasBudget].
///
/// **Waarom per scherm (Saber, 18-10-2026: "per schermritme").** Het budget stond overal op 7 ms,
/// gemaakt voor 120 Hz. De Shield heeft op 60 Hz 16,7 ms per beeld, en zakte zo binnen een halve
/// minuut naar plat glas bij 10 tot 14 ms per beeld — ruim op tijd voor zijn eigen scherm (warmte.log,
/// 18-10). Een onbekend ritme (0) houdt de ondergrens.
Duration glasBudgetVoor(double hz) {
  if (hz <= 0) return kGlasBudget;
  final deel = (1e6 / hz * kGlasBudgetDeel).round();
  return Duration(microseconds: math.max(kGlasBudget.inMicroseconds, deel));
}

/// Hoe lang het glas na de eerste terugval minstens wacht voor het opnieuw probeert; elke volgende
/// terugval verdubbelt dit, tot [kGlasWachtHoogstens].
const kGlasWachtEerst = Duration(minutes: 1);
const kGlasWachtHoogstens = Duration(minutes: 30);

/// Na hoe lang hij het hoe dan ook opnieuw probeert, ook zonder paginawissel (minstens de wachttijd).
const kGlasProbeerNa = Duration(minutes: 10);

/// De laatste keer dat het glas lichter werd: van welke stand naar welke, wanneer, en waarom.
class GlasTerugval {
  const GlasTerugval({required this.van, required this.naar, required this.om, required this.p90Ms, required this.vlakken});
  final GlasStand van, naar;
  final DateTime om;
  final double p90Ms;
  final int vlakken;

  /// Voor Instellingen: "Glas: mat — te zwaar op dit toestel (10:42, 9,1 ms per beeld)".
  String get zin {
    String twee(int n) => n.toString().padLeft(2, '0');
    final ms = p90Ms.toStringAsFixed(1).replaceAll('.', ',');
    return 'Glas: ${naar.name} — te zwaar op dit toestel (${twee(om.hour)}:${twee(om.minute)}, $ms ms per beeld)';
  }
}

/// Hoeveel beelden één meetvenster telt.
const kGlasVenster = 90;

/// Hoeveel te zware meetvensters op rij voor het glas een stand zakt. Drie vensters zijn ruim twee
/// seconden aan beelden: een pagina die opengaat en zijn hoezen binnenkrijgt, haalt dat niet.
const kGlasTeZwaar = 3;

/// Hoe lang na het opstarten de bewaker niet meetelt.
///
/// De eerste seconden zijn zwaar om redenen die niets met glas te maken hebben: shaders die voor het
/// eerst gebouwd worden, hoezen die binnenkomen, de catalogus. Met twee vensters op rij en zonder
/// aanloop kon het glas zo binnen drie seconden van vloeibaar naar plat zakken, voor de hele sessie —
/// en een menu zonder enige vervaging is precies wat de schermafdrukken van 16-10-2026 tonen.
const kGlasAanloop = Duration(seconds: 10);

/// Hoe dicht een donker glasvlak is (menu, minispeler, onderbalk, wachtrij), mét vervaging: de
/// achtergrond wordt een gekleurde waas, er valt niets meer door te lezen. Zie de uitleg bovenaan.
///
/// 85 % sinds 18-10-2026 (was 80): Saber koos "aanpassend" — dichter boven lijsten met tekst, lichter
/// boven een beeld ([kGlasDekkingBeeld]).
const kGlasDekking = .85;

/// Hoe dicht glas is boven een beeld (een hoes, een foto): daar mag de kleur doorkomen, er staat
/// geen tekst onder om dwars doorheen te lezen.
const kGlasDekkingBeeld = .60;

/// Wat er onder een glasvlak ligt. Zie [kGlasDekking] en [kGlasDekkingBeeld].
enum GlasOndergrond { lijst, beeld }

/// Hoe dicht hetzelfde vlak is als de vervaging er niet is ([GlasStand.plat]): helemaal. Dan is de
/// vulling het enige wat tegenhoudt; 74 % liet de lijst eronder gewoon leesbaar, en zelfs bij 96 %
/// schemerde witte tekst op zwart nog door (getekend op 16-10-2026).
const kGlasDekkingPlat = 1.0;

/// De dekking voor deze stand, boven deze [ondergrond].
double glasDekking(GlasStand stand, {GlasOndergrond ondergrond = GlasOndergrond.lijst}) => stand == GlasStand.plat
    ? kGlasDekkingPlat
    : ondergrond == GlasOndergrond.beeld
        ? kGlasDekkingBeeld
        : kGlasDekking;

/// De vulling van een donker glasvlak in [kleur], naar het voorbeeld van Somati's `GlassSheet`: een
/// diagonaal verloop, linksboven een tikje lichter en dichter (waar glas het licht vangt), in het
/// midden het dunst. Gemiddeld [glasDekking].
BoxDecoration glasVulling(Color kleur, GlasStand stand, {GlasOndergrond ondergrond = GlasOndergrond.lijst}) {
  final a = glasDekking(stand, ondergrond: ondergrond);
  // Plat: overal dicht, alleen het licht verloopt nog.
  final speling = stand == GlasStand.plat ? 0.0 : .04;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0, .55, 1],
      colors: [
        Color.lerp(kleur, const Color(0xFFFFFFFF), .05)!.withValues(alpha: (a + speling).clamp(0.0, 1.0)),
        kleur.withValues(alpha: a - speling),
        Color.lerp(kleur, const Color(0xFF000000), .12)!.withValues(alpha: a),
      ],
    ),
  );
}

/// Verzadiging: kleur die door glas komt, wordt voller (wat echt glas met licht doet).
List<double> _verzadig(double s) {
  const r = .2126, g = .7152, b = .0722;
  final i = 1 - s;
  return [
    r * i + s, g * i, b * i, 0, 0, //
    r * i, g * i + s, b * i, 0, 0, //
    r * i, g * i, b * i + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// HET filter van matglas: vervaging (iets breder dan hoog, als een gebogen ruit), een tikje
/// `dilate` zodat het licht uitloopt, en meer verzadiging. Eén object voor de hele app — de engine
/// voegt alleen GELIJKE filters in een `BackdropGroup` samen.
///
/// Zwaar vervaagd (24 bij 20, was 16 bij 12): Somati's "zware blur — de drukke achtergrond wordt een
/// zachte waas". Impeller verkleint het beeld eerst naar de sterkte, dus zwaarder hoort nauwelijks
/// meer te kosten — nagelezen, niet gemeten; de bewaker meet het wel.
final ui.ImageFilter glasMat = ui.ImageFilter.compose(
  outer: ui.ColorFilter.matrix(_verzadig(1.35)),
  inner: ui.ImageFilter.compose(
    outer: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 20, tileMode: TileMode.clamp),
    inner: ui.ImageFilter.dilate(radiusX: 2, radiusY: 2),
  ),
);

/// De stand van het glas voor de hele app, en de bewaker.
class GlasKwaliteit {
  GlasKwaliteit._();

  /// Wat er nu getekend wordt. Glas luistert hiernaar en tekent opnieuw als het verandert.
  static final stand = ValueNotifier<GlasStand>(GlasStand.mat);

  /// Het glas van het menu en de spelerbalk op een tv ([GlasVlak.balk]).
  ///
  /// Op een tv is al het andere glas plat (de Shield is daar te zwak voor, en [glasZonderVervaging]
  /// hangt eraan), maar Saber koos op 17-10-2026 vloeibaar glas "overal, ook de Shield" voor het menu
  /// en de spelerbalk. Die twee volgen daarom deze stand, en op een tv bewaakt de bewaker deze in
  /// plaats van [stand]. Elders is hij gelijk aan [stand].
  static final tvBalk = ValueNotifier<GlasStand>(GlasStand.plat);

  /// De stand die de bewaker laat zakken.
  static ValueNotifier<GlasStand> get _bewaakte => isTv ? tvBalk : stand;

  /// De laatste terugval, of null zolang het glas op zijn hoogste stand staat. Voor Instellingen.
  static final terugval = ValueNotifier<GlasTerugval?>(null);

  /// De hoogste stand die dit toestel kan (vloeibaar met een lens, anders mat). Daar gaat
  /// [probeerOpnieuw] heen.
  static GlasStand hoogste = GlasStand.mat;

  /// Het schermritme voor [glasBudgetVoor]. Null = van het scherm zelf; een toets zet het vast.
  @visibleForTesting
  static double? hzVoorToets;

  static double get _hz {
    final vast = hzVoorToets;
    if (vast != null) return vast;
    final views = ui.PlatformDispatcher.instance.views;
    return views.isEmpty ? 0 : views.first.display.refreshRate;
  }

  /// De klok, voor toetsen.
  @visibleForTesting
  static DateTime Function() klok = DateTime.now;

  static Duration _wacht = Duration.zero;
  static Timer? _later;

  /// Vraagt het systeem om dicht glas ("Minder transparantie", batterijbesparing)? Zie
  /// `systeem_glas.dart`. Dan staat het glas plat tot het systeem het weer toestaat.
  static final systeemDicht = ValueNotifier<bool>(false);
  static GlasStand? _voorSysteem;

  static void zetSysteemDicht(bool dicht) {
    if (dicht == systeemDicht.value) return;
    systeemDicht.value = dicht;
    final doel = _bewaakte;
    if (dicht) {
      _voorSysteem = doel.value;
      doel.value = GlasStand.plat;
      _wissel = '${_voorSysteem!.name} → plat, het systeem vraagt dicht glas';
      meld?.call('glas: het systeem vraagt dicht glas (minder transparantie of batterijbesparing)');
    } else {
      doel.value = _voorSysteem ?? hoogste;
      _voorSysteem = null;
      _wissel = 'het systeem staat weer glas toe → ${doel.value.name}';
      meld?.call('glas: $_wissel');
    }
  }

  /// Probeer de hoogste stand opnieuw. Vanuit Instellingen ([handmatig]) begint de wachttijd weer
  /// klein; vanzelf (na de wachttijd) blijft hij staan, zodat een toestel dat het echt niet trekt
  /// niet elke minuut hapert.
  static void probeerOpnieuw({bool handmatig = false}) {
    _later?.cancel();
    _later = null;
    if (systeemDicht.value) return;
    if (handmatig) _wacht = Duration.zero;
    if (_bewaakte.value == hoogste) return;
    final van = _bewaakte.value;
    _bewaakte.value = hoogste;
    _tijden.clear();
    _teZwaar = 0;
    terugval.value = null;
    final waarom = '${van.name} → ${hoogste.name}, ${handmatig ? 'opnieuw geprobeerd' : 'na ${_wacht.inMinutes} min opnieuw'}';
    _wissel = waarom;
    meld?.call('glas: $waarom');
  }

  /// Een andere pagina: is de wachttijd na de laatste terugval voorbij, dan nog eens proberen.
  static void paginaGewisseld() {
    final t = terugval.value;
    if (t == null || _bewaakte.value == hoogste) return;
    if (klok().difference(t.om) >= _wacht) probeerOpnieuw();
  }

  /// Waarom de stand de laatste keer veranderde, voor de log (`ui.log`).
  static void Function(String regel)? meld;

  /// De shader van de lensrand, zodra hij geladen is. Null = (nog) geen lens.
  static ui.FragmentProgram? lens;

  static int _actief = 0;
  static final _tijden = <int>[];
  static int _teZwaar = 0;
  static bool _bewaakt = false;
  static Stopwatch? _sinds;
  static String? _wissel;

  /// Voor `warmte.log` (de gsm schrijft daar elke tien seconden een regel op de pc): de stand, en één
  /// keer waarom hij laatst zakte. Zo zie je ook zonder kabel of het glas nog vervaagt.
  static String verslag() {
    final w = _wissel;
    _wissel = null;
    return 'glasstand ${_bewaakte.value.name}${w == null ? '' : ' ($w)'}';
  }

  /// Hoeveel glasvlakken er nu op het scherm staan. Alleen dan meet de bewaker.
  static int get actief => _actief;
  static void _erbij() => _actief++;
  static void _eraf() => _actief = _actief > 0 ? _actief - 1 : 0;

  /// Kiest de beginstand voor dit toestel en start de bewaker. Eén keer, bij het opstarten.
  static Future<void> inrichten() async {
    if (!isTv) await GlasKorrel.maak();
    if (isTv) stand.value = GlasStand.plat;
    final doel = _bewaakte;
    doel.value = GlasStand.mat;
    hoogste = GlasStand.mat;
    if (ui.ImageFilter.isShaderFilterSupported) {
      try {
        lens = await ui.FragmentProgram.fromAsset('shaders/glas_lens.frag');
        doel.value = GlasStand.vloeibaar;
        hoogste = GlasStand.vloeibaar;
      } catch (e) {
        meld?.call('glas: lensshader niet geladen ($e) — matglas');
      }
    }
    bewaak();
  }

  /// Leest de tekentijd van elk beeld. Publiek voor de toets.
  static void bewaak() {
    if (_bewaakt) return;
    _bewaakt = true;
    _sinds = Stopwatch()..start();
    SchedulerBinding.instance.addTimingsCallback(opBeelden);
  }

  /// Wat de bewaker met een rij beelden doet. Publiek voor de toets; [verstreken] is de tijd sinds
  /// [bewaak] (in de app de klok, in een toets opgegeven — zonder telt alles mee).
  @visibleForTesting
  static void opBeelden(List<ui.FrameTiming> beelden, {Duration? verstreken}) {
    final sinds = verstreken ?? _sinds?.elapsed;
    final doel = _bewaakte;
    if (_actief == 0 || doel.value == GlasStand.plat || (sinds != null && sinds < kGlasAanloop)) {
      _tijden.clear();
      return;
    }
    for (final b in beelden) {
      _tijden.add(b.rasterDuration.inMicroseconds);
    }
    if (_tijden.length < kGlasVenster) return;
    final p90 = negentigste(_tijden);
    _tijden.clear();
    final budget = glasBudgetVoor(_hz);
    if (p90 <= budget.inMicroseconds) {
      _teZwaar = 0;
      return;
    }
    if (++_teZwaar < kGlasTeZwaar) return;
    _teZwaar = 0;
    final van = doel.value;
    final naar = van == GlasStand.vloeibaar ? GlasStand.mat : GlasStand.plat;
    doel.value = naar;
    final waarom = '${van.name} → ${naar.name}, 90e percentiel ${(p90 / 1000).toStringAsFixed(1)} ms '
        'per beeld met $_actief glasvlakken (budget ${(budget.inMicroseconds / 1000).toStringAsFixed(1)} ms)';
    _wissel = waarom;
    meld?.call('glas: $waarom');
    terugval.value = GlasTerugval(van: van, naar: naar, om: klok(), p90Ms: p90 / 1000, vlakken: _actief);
    // Elke terugval verdubbelt de wachttijd voor het opnieuw proberen.
    _wacht = _wacht == Duration.zero
        ? kGlasWachtEerst
        : Duration(microseconds: math.min(_wacht.inMicroseconds * 2, kGlasWachtHoogstens.inMicroseconds));
    _later?.cancel();
    _later = Timer(_wacht > kGlasProbeerNa ? _wacht : kGlasProbeerNa, probeerOpnieuw);
  }

  /// Het 90e percentiel van [microseconden].
  @visibleForTesting
  static int negentigste(List<int> microseconden) {
    final s = [...microseconden]..sort();
    return s[((s.length - 1) * .9).round()];
  }

  /// Terug naar de begintoestand, voor toetsen.
  @visibleForTesting
  static void vergeet() {
    _actief = 0;
    _tijden.clear();
    _teZwaar = 0;
    _wissel = null;
    stand.value = GlasStand.mat;
    hoogste = GlasStand.mat;
    terugval.value = null;
    _wacht = Duration.zero;
    _later?.cancel();
    _later = null;
    hzVoorToets = null;
    klok = DateTime.now;
    systeemDicht.value = false;
    _voorSysteem = null;
  }
}

/// Een glasvlak: vervaging (mat of vloeibaar), de kleur erover, een lichtrand, en [child] erop.
///
/// De vulling staat NAAST de vervaging en niet erin (zie [balkGlas]): laat een toestel de vervaging
/// vallen, dan blijft de kleur staan en is het nog leesbaar.
class GlasVlak extends StatefulWidget {
  const GlasVlak({
    super.key,
    this.vorm = BorderRadius.zero,
    this.vulling,
    this.kleur,
    this.lens = false,
    this.lichtrand = true,
    this.balk = false,
    this.ondergrond = GlasOndergrond.lijst,
    this.korrel = true,
    this.child,
  }) : assert(vulling != null || kleur != null, 'een glasvlak zonder vulling is een gat');

  /// De ronding van het vlak.
  final BorderRadius vorm;

  /// De kleur(en) over de vervaging, zoals ze zijn. In plat glas het hele vlak.
  final Decoration? vulling;

  /// Of: één kleur, en het vlak maakt er zelf [glasVulling] van — dicht volgens de stand. Gaat voor
  /// [vulling].
  final Color? kleur;

  /// Een lensrand erbij in de stand vloeibaar. Alleen voor glas dat stil staat — zie [GlasLens].
  final bool lens;

  /// De smalle heldere rand linksboven, zoals glas het licht vangt.
  final bool lichtrand;

  /// Het menu of de spelerbalk: op een tv volgt dit [GlasKwaliteit.tvBalk] in plaats van de platte
  /// stand van de rest.
  final bool balk;

  /// Wat eronder ligt: een lijst (dicht) of een beeld (de kleur mag door). Zie [glasDekking].
  final GlasOndergrond ondergrond;

  /// De fijne korrel van [GlasKorrel] erover (niet op een tv: daar zie je hem niet).
  final bool korrel;

  final Widget? child;

  @override
  State<GlasVlak> createState() => _GlasVlakState();
}

class _GlasVlakState extends State<GlasVlak> {
  @override
  void initState() {
    super.initState();
    GlasKwaliteit._erbij();
  }

  @override
  void dispose() {
    GlasKwaliteit._eraf();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GlasStand>(
        valueListenable: widget.balk && isTv ? GlasKwaliteit.tvBalk : GlasKwaliteit.stand,
        builder: (context, stand, _) {
          final k = widget.kleur;
          final vulling = DecoratedBox(
              decoration: k != null ? glasVulling(k, stand, ondergrond: widget.ondergrond) : widget.vulling!);
          final rand = widget.lichtrand ? RepaintBoundary(child: GlasGlans(vorm: widget.vorm)) : null;
          return ClipRRect(
            borderRadius: widget.vorm,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                if (stand != GlasStand.plat)
                  // Een LEEG kind: de vervaging hoeft niets te tekenen, alleen te vervagen wat
                  // erachter ligt. `.grouped`: één terugleesbeurt voor alle glas op het scherm.
                  Positioned.fill(child: BackdropFilter.grouped(filter: glasMat, child: const SizedBox.expand())),
                if (stand == GlasStand.vloeibaar && widget.lens)
                  Positioned.fill(child: GlasLens(hoek: widget.vorm.topLeft.x)),
                Positioned.fill(child: vulling),
                if (widget.korrel && !isTv) const Positioned.fill(child: GlasKorrelLaag()),
                if (rand != null) Positioned.fill(child: IgnorePointer(child: rand)),
                widget.child ?? const SizedBox.shrink(),
              ],
            ),
          );
        },
      );
}

/// Een regel voor Instellingen: welk glas er staat, en als het lichter staat waarom, met een knop om
/// het opnieuw te proberen (Saber, 18-10-2026: "regel in Instellingen + opnieuw proberen").
class GlasRegel extends StatelessWidget {
  const GlasRegel({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge(
            [GlasKwaliteit.terugval, GlasKwaliteit.stand, GlasKwaliteit.tvBalk, GlasKwaliteit.systeemDicht]),
        builder: (context, _) {
          final systeem = GlasKwaliteit.systeemDicht.value;
          final t = systeem ? null : GlasKwaliteit.terugval.value;
          final stand = (isTv ? GlasKwaliteit.tvBalk : GlasKwaliteit.stand).value;
          final tekst = systeem
              ? 'Glas: dicht — minder transparantie of batterijbesparing staat aan op dit toestel'
              : t?.zin ?? 'Glas: ${stand.name}';
          final stijl = DefaultTextStyle.of(context).style;
          return Row(children: [
            Expanded(
              child: Text(tekst,
                  key: const ValueKey('glasregel'),
                  style: stijl.copyWith(fontSize: 12.5, color: stijl.color?.withValues(alpha: .75))),
            ),
            if (t != null)
              GestureDetector(
                key: const ValueKey('glas-opnieuw'),
                onTap: () => GlasKwaliteit.probeerOpnieuw(handmatig: true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('Opnieuw proberen',
                      style: stijl.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                ),
              ),
          ]);
        },
      );
}

/// De korrel van glas: een fijne ruis op 2 %, zoals Windows Acrylic (Saber, 18-10-2026: "ook op de
/// knoppen"). Zonder oogt glas als plastic; met ruis vangt het licht.
///
/// Eén tegel van 64 bij 64 voor de hele app, één keer gemaakt bij het inrichten en daarna alleen
/// herhaald: elke pixel een willekeurige grijswaarde op 2 % dekking. Vaste zaadwaarde, zodat hij
/// overal en elke keer hetzelfde is.
class GlasKorrel {
  GlasKorrel._();

  static const zijde = 64;

  /// Hoe sterk de korrel is (de dekking van elke korrel).
  static const sterkte = .02;

  static ui.Image? beeld;

  /// De pixels van de tegel (rgba). Publiek voor de toets.
  @visibleForTesting
  static Uint8List pixels() {
    final kans = math.Random(18102026);
    final p = Uint8List(zijde * zijde * 4);
    final a = (sterkte * 255).round();
    for (var i = 0; i < zijde * zijde; i++) {
      // Voorvermenigvuldigd: Flutter leest rgba8888 zo, dus de grijswaarde is al maal de dekking. Een
      // gewone waarde (tot 255 op een dekking van 5) telde helder op: het voorbeeld van 18-10-2026
      // stond vol ruis in plaats van 2 %.
      final v = (kans.nextInt(256) * a / 255).round();
      p[i * 4] = v;
      p[i * 4 + 1] = v;
      p[i * 4 + 2] = v;
      p[i * 4 + 3] = a;
    }
    return p;
  }

  static Future<void> maak() async {
    if (beeld != null) return;
    final klaar = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels(), zijde, zijde, ui.PixelFormat.rgba8888, klaar.complete);
    beeld = await klaar.future;
  }
}

/// [GlasKorrel] over een vlak. Tekent niets zolang de tegel er nog niet is.
class GlasKorrelLaag extends StatelessWidget {
  const GlasKorrelLaag({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _KorrelSchilder(MediaQuery.maybeDevicePixelRatioOf(context) ?? 1)),
      );
}

class _KorrelSchilder extends CustomPainter {
  _KorrelSchilder(this.dpr);
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final b = GlasKorrel.beeld;
    if (b == null || size.isEmpty) return;
    // Eén korrel per fysieke pixel: zo blijft het een fijne ruis en geen grove vlekken op een gsm.
    final schaal = Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1).storage;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ImageShader(b, TileMode.repeated, TileMode.repeated, schaal, filterQuality: FilterQuality.none),
    );
  }

  @override
  bool shouldRepaint(_KorrelSchilder oud) => oud.dpr != dpr;
}

/// Waar het licht vandaan komt dat over de glasranden glijdt (Saber, 18-10-2026: "een glans die
/// meebeweegt — muis op de pc, kanteling op gsm en iPad, selectie op de tv").
///
/// Eén bron voor de hele app, in logische punten op het scherm. Null = het vaste licht linksboven,
/// zoals vroeger. Wie het licht zet:
/// - de muis (pc, Mac): de builder van de app, bij elke beweging ([GlasLicht.muis]);
/// - de selectie op een tv: het midden van wat de selectie heeft ([GlasLicht.volgSelectie]);
/// - de kanteling van een gsm of iPad (stap 5 van het glasplan).
/// Bij "Minder beweging" van het systeem blijft het licht linksboven ([GlasGlans]).
class GlasLicht {
  GlasLicht._();

  static final bron = ValueNotifier<Offset?>(null);

  /// De muis bewoog naar [plek] (globale punten).
  static void muis(Offset plek) => bron.value = plek;

  static bool _volgt = false;

  /// Op een tv: het licht staat bij wat de selectie heeft.
  static void volgSelectie() {
    if (_volgt) return;
    _volgt = true;
    FocusManager.instance.addListener(() {
      final r = FocusManager.instance.primaryFocus?.rect;
      if (r != null && r.isFinite && !r.isEmpty) bron.value = r.center;
    });
  }

  /// Voor toetsen.
  @visibleForTesting
  static void vergeet() => bron.value = null;
}

/// De rand van glas met de glans erop: een dunne lijn rondom (wit 14 %) en een heldere vlek op de
/// plek van de rand die het dichtst bij het licht ligt ([GlasLicht.bron]). Hoe verder het licht, hoe
/// zachter de vlek. Zonder bron, of bij "Minder beweging", staat het licht linksboven buiten het vlak
/// — de oude lichtrand.
class GlasGlans extends LeafRenderObjectWidget {
  const GlasGlans({super.key, required this.vorm});
  final BorderRadius vorm;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderGlasGlans(vorm, stil: MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  void updateRenderObject(BuildContext context, RenderGlasGlans renderObject) => renderObject
    ..vorm = vorm
    ..stil = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Hoe licht de lijn rondom is, en de vlek op zijn felst (vlak bij het licht) en op zijn zachtst.
const double kGlansRand = .14;
const double kGlansVol = .80;
const double kGlansZacht = .32;

/// Hoe licht de vlek in het glas is waar het licht valt (op zijn felst).
const double kGlansVlek = .16;

/// Waar de glans op de rand van [vak] valt voor een licht op [licht] (beide lokaal), en hoe fel: de
/// plek is het dichtstbijzijnde punt van het vak, de sterkte loopt van [kGlansVol] (licht erop of
/// erin) naar [kGlansZacht] (400 punten of verder weg). Zuiver, voor de toets.
@visibleForTesting
({Offset plek, double sterkte}) glansOp(Rect vak, Offset licht) {
  final plek = Offset(licht.dx.clamp(vak.left, vak.right), licht.dy.clamp(vak.top, vak.bottom));
  final afstand = (licht - plek).distance;
  final t = (afstand / 400).clamp(0.0, 1.0);
  return (plek: plek, sterkte: kGlansVol + (kGlansZacht - kGlansVol) * t);
}

class RenderGlasGlans extends RenderBox {
  RenderGlasGlans(this._vorm, {required bool stil}) : _stil = stil;

  BorderRadius _vorm;
  set vorm(BorderRadius v) {
    if (v == _vorm) return;
    _vorm = v;
    markNeedsPaint();
  }

  bool _stil;
  set stil(bool v) {
    if (v == _stil) return;
    _stil = v;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    GlasLicht.bron.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    GlasLicht.bron.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final canvas = context.canvas;
    final vak = offset & size;
    final r = _vorm.toRRect(vak).deflate(.6);
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFFFFF).withValues(alpha: kGlansRand),
    );
    // Het licht in de coördinaten van dit vak: de bron op het scherm, terug naar hier.
    final bron = _stil ? null : GlasLicht.bron.value;
    final licht = bron == null ? vak.topLeft - const Offset(120, 120) : globalToLocal(bron) + offset;
    final g = glansOp(vak, licht);
    final straal = math.max(48.0, math.min(220.0, math.max(size.width, size.height) * .45));
    // De vlek IN het glas: een zachte lichtplek waar het licht valt. Zonder bleef het bij een lijntje
    // van anderhalve punt, en dat zag je op een voorbeeld van 18-10-2026 niet bewegen.
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(
      vak,
      Paint()
        ..shader = ui.Gradient.radial(g.plek, straal * 1.3, [
          const Color(0xFFFFFFFF).withValues(alpha: kGlansVlek * g.sterkte / kGlansVol),
          const Color(0x00FFFFFF),
        ]),
    );
    canvas.restore();
    // En de rand zelf licht daar op.
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = ui.Gradient.radial(g.plek, straal, [
          const Color(0xFFFFFFFF).withValues(alpha: g.sterkte),
          const Color(0x00FFFFFF),
        ]),
    );
  }
}

/// De lensrand: buigt de (al vervaagde) achtergrond aan de rand van het vlak.
///
/// **Alleen voor glas dat stil staat.** De shader krijgt zijn plek op het scherm bij het tekenen
/// mee; een vlak dat met een lijst meeschuift tekent niet opnieuw bij elke scrolstap, en dan ligt de
/// buiging naast het glas. En uit zolang zijn pagina in- of uitschuift: daar ligt een laag met
/// doorzichtigheid boven, en dan is de achtergrond voor de shader leeg (Flutter 3.41.9, nagelezen).
class GlasLens extends StatefulWidget {
  const GlasLens({super.key, required this.hoek, this.rand = 9, this.buiging = 7, this.licht = .55});

  /// Hoekstraal, randbreedte en verschuiving in logische punten; [licht] van 0 tot 1.
  final double hoek, rand, buiging, licht;

  @override
  State<GlasLens> createState() => _GlasLensState();
}

class _GlasLensState extends State<GlasLens> {
  Animation<double>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = ModalRoute.of(context)?.animation;
    if (a != _route) {
      _route?.removeStatusListener(_opRoute);
      _route = a?..addStatusListener(_opRoute);
    }
  }

  void _opRoute(AnimationStatus _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_opRoute);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _route;
    final rust = r == null || r.status == AnimationStatus.completed;
    final p = GlasKwaliteit.lens;
    if (!rust || p == null || !ui.ImageFilter.isShaderFilterSupported) return const SizedBox.expand();
    return _Lens(
      programma: p,
      dpr: MediaQuery.devicePixelRatioOf(context),
      hoek: widget.hoek,
      rand: widget.rand,
      buiging: widget.buiging,
      licht: widget.licht,
    );
  }
}

class _Lens extends LeafRenderObjectWidget {
  const _Lens({
    required this.programma,
    required this.dpr,
    required this.hoek,
    required this.rand,
    required this.buiging,
    required this.licht,
  });
  final ui.FragmentProgram programma;
  final double dpr, hoek, rand, buiging, licht;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLens(programma.fragmentShader(), dpr, hoek, rand, buiging, licht);

  @override
  void updateRenderObject(BuildContext context, _RenderLens r) => r
    ..dpr = dpr
    ..hoek = hoek
    ..rand = rand
    ..buiging = buiging
    ..licht = licht
    ..markNeedsPaint();
}

/// De uniforms van [glas_lens.frag] voor een vlak op [rect] (logische punten op het scherm), in de
/// volgorde van de shader: 0–1 zet de engine zelf, dan het vlak en de vier instellingen. Publiek voor
/// de toets: een verkeerde volgorde geeft in 3.41.9 geen fout, alleen een leeg vlak.
@visibleForTesting
List<double> lensWaarden(Rect rect, double dpr,
        {required double hoek, required double rand, required double buiging, required double licht}) =>
    [
      rect.left * dpr, rect.top * dpr, rect.width * dpr, rect.height * dpr, //
      hoek * dpr, rand * dpr, buiging * dpr, licht,
    ];

class _RenderLens extends RenderBox {
  _RenderLens(this._shader, this.dpr, this.hoek, this.rand, this.buiging, this.licht);

  final ui.FragmentShader _shader;
  double dpr, hoek, rand, buiging, licht;
  final _laag = LayerHandle<BackdropFilterLayer>();

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final opScherm = MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);
    final w = lensWaarden(opScherm, dpr, hoek: hoek, rand: rand, buiging: buiging, licht: licht);
    for (var i = 0; i < w.length; i++) {
      _shader.setFloat(2 + i, w[i]);
    }
    // Een NIEUW filter na elke wijziging: de engine kopieert de waarden bij het maken ervan.
    final laag = _laag.layer ??= BackdropFilterLayer();
    laag.filter = ui.ImageFilter.shader(_shader);
    context.pushLayer(laag, (_, __) {}, offset);
  }

  @override
  void dispose() {
    _laag.layer = null;
    _shader.dispose();
    super.dispose();
  }
}
