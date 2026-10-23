/// De meetronde: een toestel meet zichzelf, op afstand gestart (Saber, 23-10-2026: *"het is tijd om eens de
/// performance te meten, begin eens op men mac, als ik de nu spelend scherm naar boven en naar beneden doe, gaat
/// heel stroef, ook met de muis over de hoes tilt effect is niet vlot"* — en op "er is geen SSH of schermbediening
/// voor dat toestel": *"zorg er dan voor, zo kan je het beste meten"*).
///
/// **Waarom zo.** Een SSH-verbinding naar de Mac zegt niet wat Flutter per beeld doet. De app weet dat wel
/// ([ui.FrameTiming]: bouwen op de UI-draad, rasteren op de GPU-draad). Dus voert het toestel zelf een vast draaiboek
/// uit — Nu speelt openen en sluiten, met de muis over de hoes, stil laten staan — en dat telkens met een effect
/// uit. De pc stuurt het aan over de zonelijn (opdracht `meet`); de cijfers komen terug in `warmte.log` op de pc,
/// met `[meet]` ervoor. Niemand hoeft aan het toestel te zitten; de app moet alleen open en zichtbaar staan.
///
/// **De varianten.** Een variant is een lijst effecten die uit staan ([kMeetEffecten]). De effecten lezen
/// [zonderVoorMeting] bij het bouwen; Nu speelt gaat per scenario opnieuw open, dus elke variant tekent vers.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Welke effecten een meetronde nu uit heeft. Leeg buiten een meetronde.
final meetZonder = ValueNotifier<Set<String>>(const {});

/// Staat [effect] uit voor een meetronde? Buiten een meetronde altijd nee.
bool zonderVoorMeting(String effect) => meetZonder.value.contains(effect);

/// Wat een variant kan uitzetten (of, bij `foto`, aanzetten).
const kMeetEffecten = {
  'glas': 'glas plat: geen vervaging',
  'glasmat': 'glas mat in plaats van vloeibaar',
  'achter': 'Nu speelt zonder achtergrond (waas, vlekken, vervaagde hoes)',
  'schaduw': 'zonder de schaduw onder de hoes',
  'spiegel': 'zonder de spiegeling onder de hoes',
  'schijf': 'zonder de cd naast de hoes',
  'licht': 'cd zonder licht en schaduwen',
  'kantel': 'de hoes kantelt niet',
  'foto': 'Nu speelt schuift als één foto in en uit',
};

/// De scenario's van een meetronde.
const kMeetScenarios = {
  'open': 'Nu speelt drie keer openen en sluiten',
  'kantel': 'de muis vier seconden over de grote hoes in Nu speelt',
  'stil': 'Nu speelt drie seconden open laten staan',
  'bronnen': 'een albumpagina met "Bronnen voor album" open, twintig seconden (met `artiest` en `album`; alleen '
      'bij "alles aan")',
};

/// Wat een ronde zonder opgegeven scenario's doet: alles behalve `bronnen`, dat een album nodig heeft.
const kMeetStandaard = ['open', 'kantel', 'stil'];

/// De cijfers van een rij beelden: hoeveel, wat ze kostten, en hoeveel er te laat waren voor het scherm.
@immutable
class Beeldcijfers {
  const Beeldcijfers({
    required this.aantal,
    required this.rasterGemMs,
    required this.rasterP90Ms,
    required this.rasterMaxMs,
    required this.bouwGemMs,
    required this.bouwMaxMs,
    required this.teLaat,
    required this.budgetMs,
  });

  /// Uit [bouwUs] en [rasterUs] (per beeld, in microseconden) op een scherm van [hz].
  factory Beeldcijfers.uit(List<int> bouwUs, List<int> rasterUs, {required double hz}) {
    final budgetUs = 1e6 / (hz > 0 ? hz : 60);
    double gem(List<int> l) => l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length / 1000;
    double maxi(List<int> l) => l.isEmpty ? 0 : l.reduce(math.max) / 1000;
    final gesorteerd = [...rasterUs]..sort();
    final p90 = gesorteerd.isEmpty ? 0.0 : gesorteerd[((gesorteerd.length - 1) * .9).round()] / 1000;
    var laat = 0;
    for (var i = 0; i < rasterUs.length; i++) {
      if (math.max(rasterUs[i], i < bouwUs.length ? bouwUs[i] : 0) > budgetUs) laat++;
    }
    return Beeldcijfers(
      aantal: rasterUs.length,
      rasterGemMs: gem(rasterUs),
      rasterP90Ms: p90,
      rasterMaxMs: maxi(rasterUs),
      bouwGemMs: gem(bouwUs),
      bouwMaxMs: maxi(bouwUs),
      teLaat: laat,
      budgetMs: budgetUs / 1000,
    );
  }

  factory Beeldcijfers.van(List<ui.FrameTiming> t, {required double hz}) => Beeldcijfers.uit(
      [for (final b in t) b.buildDuration.inMicroseconds], [for (final b in t) b.rasterDuration.inMicroseconds],
      hz: hz);

  final int aantal;
  final double rasterGemMs, rasterP90Ms, rasterMaxMs, bouwGemMs, bouwMaxMs;

  /// Beelden waarvan bouwen of rasteren langer duurde dan één schermtik ([budgetMs]).
  final int teLaat;
  final double budgetMs;

  static String _f(double v) => v.toStringAsFixed(1);

  /// De regel voor `warmte.log`.
  String regel(String scenario, List<String> zonder) => '[meet] $scenario | '
      '${zonder.isEmpty ? 'alles aan' : 'zonder ${zonder.join('+')}'} | '
      '$aantal beelden | rasteren gem ${_f(rasterGemMs)} · p90 ${_f(rasterP90Ms)} · max ${_f(rasterMaxMs)} ms | '
      'bouwen gem ${_f(bouwGemMs)} · max ${_f(bouwMaxMs)} ms | te laat $teLaat (>${_f(budgetMs)} ms)';
}

/// Wat een meetronde van de app nodig heeft.
class MeetHaken {
  const MeetHaken({
    required this.openNuSpeelt,
    required this.sluitNuSpeelt,
    required this.meld,
    required this.zetGlas,
    this.bereid,
    this.hoesVak,
    this.openAlbum,
    this.sluitAlbum,
    this.klaar,
  });

  /// Nu speelt openen (niet wachten tot het klaar is).
  final void Function() openNuSpeelt;
  final void Function() sluitNuSpeelt;

  /// Regels naar de pc (`warmte.log`).
  final Future<void> Function(List<String> regels) meld;

  /// Het glas op een stand zetten voor een variant: 'plat', 'mat', of null = terug naar wat het was. De bewaker
  /// moet zolang stilstaan: anders zet hij het midden in een meting zelf om. Met [klaar] is de ronde voorbij en mag
  /// hij weer.
  final void Function(String? stand, {bool klaar}) zetGlas;

  /// Zorgt dat er iets in Nu speelt staat ([spelen]: ook spelen, zonder geluid). Geeft een opmerking voor de kop.
  final Future<String> Function({required bool spelen})? bereid;

  /// Waar de grote hoes in Nu speelt nu staat (globaal), voor het scenario `kantel`.
  final Rect? Function()? hoesVak;

  /// Een albumpagina openen met de bronnen open (scenario `bronnen`). False als het album niet te vinden was.
  final Future<bool> Function(String artiest, String album)? openAlbum;
  final void Function()? sluitAlbum;

  /// Na de ronde: zet terug wat [bereid] veranderde.
  final Future<void> Function()? klaar;
}

/// Hoe vaak een synthetische muis per seconde beweegt in het scenario `kantel`.
const kMeetMuisHz = 120;

/// Het apparaatnummer van de synthetische muis: een eigen nummer, los van de echte.
const kMeetMuis = 7117;

/// Loopt er een meetronde? Dan wordt een tweede genegeerd.
bool get meetrondeLoopt => _loopt;
bool _loopt = false;

/// Voer een meetronde uit ([op] uit de opdracht `meet`):
/// - `scenarios`: welke uit [kMeetScenarios] (standaard [kMeetStandaard]);
/// - `artiest` en `album`: voor het scenario `bronnen`;
/// - `varianten`: een lijst van lijsten effecten ([kMeetEffecten]); standaard één per effect, plus "alles aan";
/// - `spelen`: ook laten spelen (zonder geluid), zodat de cd draait.
Future<void> voerMeetrondeUit(Map<String, dynamic> op, MeetHaken h, {double? hz}) async {
  if (_loopt) return;
  _loopt = true;
  final scherm = hz ?? _hz();
  final scenarios = [
    for (final s in (op['scenarios'] as List? ?? kMeetStandaard))
      if (kMeetScenarios.containsKey('$s')) '$s',
  ];
  final varianten = [
    for (final v in (op['varianten'] as List? ?? [const <String>[], for (final e in kMeetEffecten.keys) [e]]))
      [for (final e in (v as List)) if (kMeetEffecten.containsKey('$e')) '$e'],
  ];
  final artiest = '${op['artiest'] ?? ''}', album = '${op['album'] ?? ''}';
  try {
    final opmerking = await h.bereid?.call(spelen: op['spelen'] == true) ?? '';
    await h.meld([
      '[meet] begin: ${scenarios.join(', ')} × ${varianten.length} varianten, ${scherm.round()} Hz'
          '${opmerking.isEmpty ? '' : ' — $opmerking'}',
    ]);
    for (final zonder in varianten) {
      meetZonder.value = {...zonder};
      h.zetGlas(zonder.contains('glas')
          ? 'plat'
          : zonder.contains('glasmat')
              ? 'mat'
              : null);
      // Even laten bezinken: het glas tekent opnieuw, en een eerste beeld met nieuwe shaders is altijd traag.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final regels = <String>[];
      for (final s in scenarios) {
        // De bronnen gaan niet over de effecten van Nu speelt: één keer, bij "alles aan".
        if (s == 'bronnen' && zonder.isNotEmpty) continue;
        final beelden = await _scenario(s, h, artiest: artiest, album: album);
        regels.add(Beeldcijfers.van(beelden, hz: scherm).regel(s, zonder));
      }
      await h.meld(regels);
    }
  } catch (e) {
    await h.meld(['[meet] gestopt: $e']);
  } finally {
    meetZonder.value = const {};
    h.zetGlas(null, klaar: true);
    try {
      await h.klaar?.call();
    } catch (_) {}
    _loopt = false;
  }
  await h.meld(['[meet] klaar']);
}

double _hz() {
  final views = ui.PlatformDispatcher.instance.views;
  return views.isEmpty ? 60 : views.first.display.refreshRate;
}

Future<void> _wacht(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// De beelden die [doe] liet tekenen. De motor meldt ze in bundels (in een uitgave ongeveer elke seconde): daarom
/// achteraf nog even luisteren, en alleen wat er tijdens [doe] begon telt.
Future<List<ui.FrameTiming>> _beeldenVan(Future<void> Function() doe) async {
  final alle = <ui.FrameTiming>[];
  void opBeelden(List<ui.FrameTiming> t) => alle.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(opBeelden);
  late final int van, tot;
  try {
    van = await _merk();
    await doe();
    tot = await _merk();
    await _wacht(1200);
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(opBeelden);
  }
  return [for (final b in alle) if (binnen(b.timestampInMicroseconds(ui.FramePhase.buildStart), van, tot)) b];
}

/// Begon een beeld op [begin] (µs) tussen de merktekens [van] en [tot]? Het beeld van [van] zelf telt niet mee: dat
/// is het merkteken.
@visibleForTesting
bool binnen(int begin, int van, int tot) => begin > van && begin <= tot;

/// Een merkteken op de klok van [ui.FrameTiming]: het begin van het volgende beeld. De motor geeft
/// [SchedulerBinding.currentSystemFrameTimeStamp] precies als [ui.FramePhase.buildStart] van dat beeld door.
Future<int> _merk() {
  final c = Completer<int>();
  SchedulerBinding.instance.addPostFrameCallback(
      (_) => c.complete(SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds));
  SchedulerBinding.instance.scheduleFrame();
  return c.future;
}

Future<List<ui.FrameTiming>> _scenario(String s, MeetHaken h, {String artiest = '', String album = ''}) async {
  switch (s) {
    case 'bronnen':
      final open = h.openAlbum;
      if (open == null || artiest.isEmpty || album.isEmpty) return const [];
      final beelden = await _beeldenVan(() async {
        if (await open(artiest, album)) await _wacht(20000);
      });
      h.sluitAlbum?.call();
      await _wacht(900);
      return beelden;
    case 'open':
      return _beeldenVan(() async {
        for (var i = 0; i < 3; i++) {
          h.openNuSpeelt();
          await _wacht(900);
          h.sluitNuSpeelt();
          await _wacht(900);
        }
      });
    case 'kantel':
      h.openNuSpeelt();
      await _wacht(1200);
      final beelden = await _beeldenVan(() => _muisOver(h.hoesVak?.call()));
      h.sluitNuSpeelt();
      await _wacht(900);
      return beelden;
    case 'stil':
      h.openNuSpeelt();
      await _wacht(1200);
      final beelden = await _beeldenVan(() => _wacht(3000));
      h.sluitNuSpeelt();
      await _wacht(900);
      return beelden;
  }
  return const [];
}

/// Een muis die vier seconden in rondjes over [vak] beweegt, [kMeetMuisHz] keer per seconde — zoals een hand.
Future<void> _muisOver(Rect? vak) async {
  if (vak == null || vak.isEmpty) return;
  final binding = GestureBinding.instance;
  final midden = vak.center;
  final rx = vak.width * .4, ry = vak.height * .4;
  binding.handlePointerEvent(PointerAddedEvent(position: midden, kind: PointerDeviceKind.mouse, device: kMeetMuis));
  final stap = Duration(microseconds: 1000000 ~/ kMeetMuisHz);
  final stappen = kMeetMuisHz * 4;
  var p = midden;
  for (var i = 0; i < stappen; i++) {
    final hoek = i / kMeetMuisHz * 2 * math.pi * .75;
    final nieuw = midden + Offset(math.cos(hoek) * rx, math.sin(hoek * 1.3) * ry);
    binding.handlePointerEvent(
        PointerHoverEvent(position: nieuw, delta: nieuw - p, kind: PointerDeviceKind.mouse, device: kMeetMuis));
    p = nieuw;
    await Future<void>.delayed(stap);
  }
  binding.handlePointerEvent(PointerRemovedEvent(position: p, kind: PointerDeviceKind.mouse, device: kMeetMuis));
}
