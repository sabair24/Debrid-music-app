/// Toestellen samen laten spelen (groeperen, stap 3.2 — Saber, 21-10-2026: "gsm/iPad/Mac/pc samen",
/// "hoorbaar gelijk in één kamer", met een vertraging per toestel die je op het oor zet).
///
/// **Leider en volgers.** De zone waarmee je de groep maakt, is de leider: die speelt gewoon, en meldt wat
/// hij speelt aan de pc zoals altijd. De pc stuurt bij elke melding een [SamenAnker] naar de volgers: welk
/// nummer, welke plek, op welk moment (op de klok van de pc). Elke volger speelt dezelfde wachtrij en
/// rekent uit waar hij nu hoort te zijn ([verwachtePlek]); wijkt hij af, dan spoelt hij (veel) of speelt
/// hij heel even iets sneller of trager (weinig, onhoorbaar: mpv houdt de toonhoogte) — [bijsturing].
///
/// **De klok.** Elk toestel meet hoe zijn klok afwijkt van die van de pc ([KlokIjk]): een paar korte vragen
/// naar `/api/tijd`, en de snelste telt (daar zit het minst wachten in). Op wifi scheelt dat een paar ms.
///
/// **Wat er overblijft.** Hoe lang een toestel doet over het geluid uit zijn speaker krijgen, verschilt
/// (Bluetooth: 100–300 ms). Dat zet je per toestel bij met "Vertraging bij samen spelen".
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;

import 'models.dart';
import 'player.dart' show VolgSpeler;

/// Waar de leider was, op een moment op de klok van de pc.
class SamenAnker {
  const SamenAnker({
    required this.groep,
    required this.trackId,
    required this.rij,
    required this.index,
    required this.positieMs,
    required this.pcMs,
    required this.speelt,
  });

  /// De groep (de zone van de leider).
  final String groep;
  final String trackId;
  final List<String> rij;
  final int index;
  final int positieMs;

  /// Wanneer de leider op [positieMs] stond, op de klok van de pc.
  final int pcMs;
  final bool speelt;

  Map<String, dynamic> toJson() => {
        'groep': groep,
        'trackId': trackId,
        'rij': rij,
        'index': index,
        'positieMs': positieMs,
        'pcMs': pcMs,
        'speelt': speelt,
      };

  static SamenAnker? fromJson(Map<String, dynamic>? m) {
    if (m == null || '${m['trackId'] ?? ''}'.isEmpty) return null;
    return SamenAnker(
      groep: '${m['groep'] ?? ''}',
      trackId: '${m['trackId']}',
      rij: [for (final x in (m['rij'] as List? ?? const [])) '$x'],
      index: (m['index'] as num?)?.toInt() ?? 0,
      positieMs: (m['positieMs'] as num?)?.toInt() ?? 0,
      pcMs: (m['pcMs'] as num?)?.toInt() ?? 0,
      speelt: m['speelt'] == true,
    );
  }
}

/// Waar een volger nu hoort te zijn: de plek van de leider plus de tijd sindsdien (als hij speelt), min
/// de [vertragingMs] van dit toestel (positief = dit toestel klinkt later).
Duration verwachtePlek(SamenAnker a, {required int nuPcMs, int vertragingMs = 0}) {
  final ms = a.positieMs + (a.speelt ? nuPcMs - a.pcMs : 0) - vertragingMs;
  return Duration(milliseconds: ms < 0 ? 0 : ms);
}

/// Verder dan dit weg: spoelen in plaats van bijsturen.
const kSamenSpoelVanaf = 400;

/// Binnen dit verschil is het goed (en houdt het bijsturen op).
const kSamenGoed = 8;

/// Vanaf dit verschil begint het bijsturen.
const kSamenBijsturenVanaf = 20;

/// Hoe ver de snelheid hoogstens van 1 afwijkt (3 %: niet te horen, mpv houdt de toonhoogte).
const kSamenMaxAfwijking = 0.03;

/// Wat een volger met zijn [afwijkingMs] doet (positief = hij loopt voor). [bezig]: stuurde hij al bij?
/// Dan pas ophouden binnen [kSamenGoed], anders pas beginnen vanaf [kSamenBijsturenVanaf] — zo blijft hij
/// niet heen en weer schakelen rond één grens.
({bool spoel, double snelheid}) bijsturing(int afwijkingMs, {bool bezig = false}) {
  final a = afwijkingMs.abs();
  if (a > kSamenSpoelVanaf) return (spoel: true, snelheid: 1.0);
  if (a <= kSamenGoed || (!bezig && a < kSamenBijsturenVanaf)) return (spoel: false, snelheid: 1.0);
  // Het verschil in ongeveer twee seconden wegwerken.
  final v = (1 - afwijkingMs / 2000).clamp(1 - kSamenMaxAfwijking, 1 + kSamenMaxAfwijking).toDouble();
  return (spoel: false, snelheid: v);
}

/// Eén meting van de klok: wanneer de vraag vertrok ([t0]) en het antwoord aankwam ([t1]) op de klok van
/// dit toestel, en wat de pc op dat moment zei ([pc]) — alles in microseconden.
typedef KlokMeting = ({int t0, int pc, int t1});

/// Hoeveel de klok van de pc voorloopt op die van dit toestel (µs), uit de snelste [metingen].
int? klokVerschilUit(List<KlokMeting> metingen) {
  KlokMeting? beste;
  for (final m in metingen) {
    if (m.t1 < m.t0) continue;
    if (beste == null || m.t1 - m.t0 < beste.t1 - beste.t0) beste = m;
  }
  if (beste == null) return null;
  return beste.pc - (beste.t0 + beste.t1) ~/ 2;
}

/// De klok van de pc, op dit toestel. Zie de uitleg bovenaan.
class KlokIjk {
  KlokIjk({this.vraag});

  /// Vraag de pc hoe laat het is (µs), of null zonder pc. Null = dit IS de pc.
  final Future<int?> Function()? vraag;

  int _verschilUs = 0;
  int? _rttUs;
  DateTime? _gemeten;

  /// Hoe laat het nu op de pc is (ms).
  int nuPcMs() => (DateTime.now().microsecondsSinceEpoch + _verschilUs) ~/ 1000;

  /// De snelste rondgang van de laatste meting (µs), of null.
  int? get rttUs => _rttUs;

  /// Opnieuw meten, als het langer dan [geldig] geleden is.
  Future<void> ijk({Duration geldig = const Duration(seconds: 60), int keer = 7}) async {
    final v = vraag;
    if (v == null) return;
    if (_gemeten != null && DateTime.now().difference(_gemeten!) < geldig) return;
    final metingen = <KlokMeting>[];
    for (var i = 0; i < keer; i++) {
      final t0 = DateTime.now().microsecondsSinceEpoch;
      int? pc;
      try {
        pc = await v();
      } catch (_) {
        pc = null;
      }
      final t1 = DateTime.now().microsecondsSinceEpoch;
      if (pc != null) metingen.add((t0: t0, pc: pc, t1: t1));
    }
    final verschil = klokVerschilUit(metingen);
    if (verschil == null) return;
    _verschilUs = verschil;
    _rttUs = [for (final m in metingen) m.t1 - m.t0].reduce((a, b) => a < b ? a : b);
    _gemeten = DateTime.now();
  }
}

/// Volgt de leider van een groep op dit toestel. Eén per app.
class SamenVolger {
  SamenVolger({
    required this.speler,
    required this.nummer,
    required this.idVan,
    required this.klok,
    required this.vertragingMs,
    this.log,
  });

  final VolgSpeler speler;
  final Track? Function(String id) nummer;
  final String? Function(Track t) idVan;
  final KlokIjk klok;

  /// De vertraging van dit toestel (ms; positief = later), uit de instellingen.
  final int Function() vertragingMs;
  final void Function(String)? log;

  SamenAnker? _anker;

  /// De wachtrij (ids) van het laatste anker dat hier verwerkt is: alleen als die verandert, valt er iets over
  /// te nemen (een geschudde bibliotheek is dertigduizend ids).
  List<String> _rij = const [];
  Timer? _lus;
  bool _bezig = false;
  bool _opent = false;
  int _laatsteLog = 0;

  /// Volgt dit toestel nu een groep?
  bool get volgt => _anker != null;

  /// De groep die het volgt, of null.
  String? get groep => _anker?.groep;

  /// Een nieuw anker van de pc.
  Future<void> opAnker(SamenAnker a) async {
    final eerste = _anker == null;
    _anker = a;
    await klok.ijk();
    if (eerste) log?.call('samen: volgt ${a.groep} (klok ±${((klok.rttUs ?? 0) / 2000).toStringAsFixed(1)} ms)');
    final t = speler.current;
    final zelfde = t != null && idVan(t) == a.trackId;
    if (!a.speelt) {
      if (speler.playing) speler.pauzeer();
      if (zelfde) speler.seek(Duration(milliseconds: a.positieMs));
      await speler.zetSnelheid(1.0);
      _stopLus();
      return;
    }
    if (!zelfde) {
      await _open(a);
    } else {
      _volgRij(a);
    }
    if (zelfde && !speler.playing) {
      speler.seek(verwachtePlek(a, nuPcMs: klok.nuPcMs(), vertragingMs: vertragingMs()));
      speler.speelAf();
    }
    _startLus();
  }

  /// De leider kreeg een andere wachtrij (iets "hierna", verplaatst, weg): die overnemen rond het nummer dat
  /// hier al klinkt. Anders speelde de volger bij de volgende wissel zijn oude volgende nummer, tot het anker
  /// van de leider hem een seconde later naar het goede liet springen.
  void _volgRij(SamenAnker a) {
    if (a.rij.isEmpty || listEquals(a.rij, _rij)) return;
    final rij = <Track>[];
    var plek = -1;
    for (var i = 0; i < a.rij.length; i++) {
      final t = nummer(a.rij[i]);
      if (t == null) continue;
      if (i == a.index) plek = rij.length;
      rij.add(t);
    }
    if (plek < 0) return;
    final hier = speler.queueTracks;
    final gelijk = hier.length == rij.length && [for (var i = 0; i < rij.length; i++) hier[i].path == rij[i].path].every((x) => x);
    if (gelijk || speler.zetRijRondHuidig(rij, plek)) {
      if (!gelijk) log?.call('samen: wachtrij van de leider overgenomen (${rij.length} nummers)');
      _rij = a.rij;
    }
  }

  /// Het nummer van de leider openen, en op het juiste moment beginnen.
  Future<void> _open(SamenAnker a) async {
    if (_opent) return;
    _opent = true;
    try {
      final rij = <Track>[];
      var plek = 0;
      for (var i = 0; i < a.rij.length; i++) {
        final t = nummer(a.rij[i]);
        if (t == null) continue;
        if (i == a.index) plek = rij.length;
        rij.add(t);
      }
      if (rij.isEmpty) {
        final t = nummer(a.trackId);
        if (t == null) {
          log?.call('samen: nummer ${a.trackId} staat hier niet');
          return;
        }
        rij.add(t);
      }
      // Een seconde vooruit openen, en pas beginnen als de leider daar is: openen kost tijd.
      final doel = verwachtePlek(a, nuPcMs: klok.nuPcMs(), vertragingMs: vertragingMs()) + const Duration(seconds: 1);
      await speler.neemOver(rij, plek, doel, spelen: false);
      _rij = a.rij;
      final wacht = doel - verwachtePlek(a, nuPcMs: klok.nuPcMs(), vertragingMs: vertragingMs());
      if (wacht > Duration.zero) await Future<void>.delayed(wacht);
      if (identical(_anker, a) || _anker?.trackId == a.trackId) speler.speelAf();
    } finally {
      _opent = false;
    }
  }

  void _startLus() {
    _lus ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _stuurBij());
  }

  void _stopLus() {
    _lus?.cancel();
    _lus = null;
    _bezig = false;
  }

  void _stuurBij() {
    final a = _anker;
    if (a == null || !a.speelt || _opent || !speler.playing) return;
    final t = speler.current;
    if (t == null || idVan(t) != a.trackId) return;
    final moet = verwachtePlek(a, nuPcMs: klok.nuPcMs(), vertragingMs: vertragingMs());
    final afwijking = (speler.positieNauwkeurig - moet).inMilliseconds;
    final b = bijsturing(afwijking, bezig: _bezig);
    final nu = DateTime.now().millisecondsSinceEpoch;
    if (nu - _laatsteLog > 2000) {
      _laatsteLog = nu;
      log?.call('samen: afwijking ${afwijking >= 0 ? '+' : ''}$afwijking ms → '
          '${b.spoel ? 'spoelen' : 'snelheid ${b.snelheid.toStringAsFixed(3)}'}');
    }
    if (b.spoel) {
      speler.seek(moet + const Duration(milliseconds: 60));
      unawaited(speler.zetSnelheid(1.0));
      _bezig = false;
      return;
    }
    _bezig = b.snelheid != 1.0;
    unawaited(speler.zetSnelheid(b.snelheid));
  }

  /// Uit de groep: niet meer volgen, gewoon weer op dit toestel.
  Future<void> stop({bool pauzeer = true}) async {
    if (_anker == null) return;
    log?.call('samen: volgt ${_anker!.groep} niet meer');
    _anker = null;
    _stopLus();
    await speler.zetSnelheid(1.0);
    if (pauzeer && speler.playing) speler.pauzeer();
  }
}
