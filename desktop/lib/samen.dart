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
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;

import 'models.dart';
import 'player.dart' show VolgSpeler;

/// Waar de leider was, op een moment op de klok van de pc.
class SamenAnker {
  const SamenAnker({
    required this.groep,
    required this.trackId,
    this.speelId = '',
    required this.rij,
    required this.index,
    required this.positieMs,
    required this.pcMs,
    required this.speelt,
    this.onzekerMs = 0,
  });

  /// Hoe zeker [positieMs] is (ms), of 0: precies, of onbekend (een toestel als leider, een oudere pc).
  final int onzekerMs;

  /// De groep (de zone van de leider).
  final String groep;
  final String trackId;

  /// De versie die de leider van [trackId] echt speelt (een gekozen versie, of de standaard). Leeg: een oudere pc.
  final String speelId;
  final List<String> rij;
  final int index;
  final int positieMs;

  /// Wanneer de leider op [positieMs] stond, op de klok van de pc.
  final int pcMs;
  final bool speelt;

  Map<String, dynamic> toJson() => {
        'groep': groep,
        'trackId': trackId,
        if (speelId.isNotEmpty) 'speelId': speelId,
        'rij': rij,
        'index': index,
        'positieMs': positieMs,
        'pcMs': pcMs,
        'speelt': speelt,
        if (onzekerMs > 0) 'onzekerMs': onzekerMs,
      };

  static SamenAnker? fromJson(Map<String, dynamic>? m) {
    if (m == null || '${m['trackId'] ?? ''}'.isEmpty) return null;
    return SamenAnker(
      groep: '${m['groep'] ?? ''}',
      trackId: '${m['trackId']}',
      speelId: '${m['speelId'] ?? ''}',
      rij: [for (final x in (m['rij'] as List? ?? const [])) '$x'],
      index: (m['index'] as num?)?.toInt() ?? 0,
      positieMs: (m['positieMs'] as num?)?.toInt() ?? 0,
      pcMs: (m['pcMs'] as num?)?.toInt() ?? 0,
      speelt: m['speelt'] == true,
      onzekerMs: (m['onzekerMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Waar een volger nu hoort te zijn: de plek van de leider plus de tijd sindsdien (als hij speelt), min
/// de [vertragingMs] van dit toestel (positief = dit toestel klinkt later).
Duration verwachtePlek(SamenAnker a, {required int nuPcMs, int vertragingMs = 0}) {
  final ms = a.positieMs + (a.speelt ? nuPcMs - a.pcMs : 0) - vertragingMs;
  return Duration(milliseconds: ms < 0 ? 0 : ms);
}

/// Verder dan dit weg: spoelen in plaats van bijsturen. 400 tot 27-11-2026; maar wat daaronder lag, werkte de volger weg
/// door seconden lang 3 % trager of sneller te spelen, en dat hoorde Saber: *"tijdens het liedje zelf alsof het
/// vertraagd en weer op tempo komt"*. Eén kort sprongetje is minder erg dan zes seconden slepen.
const kSamenSpoelVanaf = 150;

/// In de eerste [kSamenBeginTot] van een nummer al spoelen vanaf dit verschil. Bij elke overgang liep de Shield ±200 ms
/// voor op de Sonos Move (die neemt tussen twee nummers meer tijd), en haalde dat in met 0,970 — zes seconden trager,
/// aan het begin van elk nummer (samen.log, 27-11-2026). Eén keer per nummer: zie [SamenVolger].
const kSamenSpoelBegin = 40;

/// Zo zeker moet het anker zijn voor een precieze sprong (ms). Vlak na een wissel meet de pc de Sonos op ±70 ms; viel de
/// vroege sprong op zo'n grove meting, dan mag er nog één zodra de meting precies is (27-11-2026: na de sprong bleef er
/// 70 à 90 ms over, die de volger met 1 % pas na seconden wegwerkte).
const kSamenPreciesMs = 25;

/// Een anker dat onzekerder is dan dit (ms), laat de volger liggen: niet spoelen, niet bijsturen, gewoon doorspelen tot
/// er een betere meting is. Live gezien op 27-11-2026: na een hik van de Sonos mat de pc hem op ±545 en ±2500 ms, en de
/// Shield joeg die ruis na (−129, +149, +499 ms); na een wissel sprong hij op een meting van ±600 ms en landde 440 ms
/// naast de Sonos.
const kSamenNegeerVanaf = 100;

/// Zo lang heet een nummer "net begonnen" ([kSamenSpoelBegin]).
const kSamenBeginTot = Duration(seconds: 10);

/// Waar de sprongmarge begint ([SamenVolger.spoelMarge]): 60 tot 27-11-2026, maar op de Shield landde een sprong dan
/// gemiddeld ±50 ms te vroeg.
const kSamenSpoelMarge = 20;

/// Binnen dit verschil is het goed (en houdt het bijsturen op).
const kSamenGoed = 8;

/// Vanaf dit verschil begint het bijsturen.
const kSamenBijsturenVanaf = 20;

/// Over hoeveel ankers van de leider de volger zijn plek bepaalt: de middelste ([mediaan]) van de laatste zoveel, van
/// hetzelfde nummer ([SamenVolger.leiderStart]).
const kSamenVenster = 5;

/// Waarin de volger een verschil wegwerkt (ms): 20 ms is dan 0,2 % sneller of trager, en pas vanaf 100 ms de volle
/// [kSamenMaxAfwijking]. Was 2000 — dan was elk verschil vanaf 20 ms meteen 1 %, en met de ruis van een KEF sprong de
/// Shield in 70 s veertien keer tussen 0,990 en 1,010 (28-11-2026).
const kSamenBijsturingTijd = 10000;

/// In welke stappen de volger zijn snelheid zet: 0,25 %. Fijner betekent vaker een nieuwe snelheid voor de speler, en
/// elke nieuwe snelheid kan een tikje geven (Saber, 28-11-2026 met 3.9.768: "haperingen, sprongen eigenlijk").
const kSamenSnelheidStap = 0.0025;

/// Hoe lang een gezette snelheid minstens blijft staan (behalve bij een sprong of een onzekere meting).
const kSamenSnelheidHoud = Duration(seconds: 5);

/// [v] afgerond op een stap van [kSamenSnelheidStap] rond 1.
double snelheidsstap(double v) =>
    double.parse((1 + ((v - 1) / kSamenSnelheidStap).round() * kSamenSnelheidStap).toStringAsFixed(4));

/// Hoe ver de drempel hoogstens meegroeit met de ruis van de leider ([ruisUit]).
const kSamenDrempelHoogstens = 80;

/// De middelste van [xs] (bij een even aantal de hoogste van de twee middelste). [xs] mag niet leeg zijn.
int mediaan(List<int> xs) => ([...xs]..sort())[xs.length ~/ 2];

/// De ruis van de leider (ms, één meting): uit de [verschillen] tussen twee opeenvolgende ankers van hetzelfde nummer,
/// elk doorgerekend naar hetzelfde moment. Twee metingen met elk ruis σ verschillen gemiddeld σ·√2. 0 met minder dan
/// twee verschillen.
///
/// **Waarom (Saber, 28-11-2026, Shield met de KEF LS50: "ik hoor een zakking in tempo").** De KEF meldt zijn plek met
/// ±24 ms ruis (de pc dacht ±2 ms): tussen twee ankers tot 47 ms verschil. De volger stuurde op elke meting vanaf 20 ms
/// bij en sprong in 70 s veertien keer tussen 0,990 en 1,010 — dat golvende tempo hoorde hij. Bij de Sonos was de ruis
/// een paar ms.
int ruisUit(List<int> verschillen) {
  if (verschillen.length < 2) return 0;
  final kwadraat = verschillen.fold<double>(0, (s, d) => s + d * d) / verschillen.length;
  return math.sqrt(kwadraat / 2).round();
}

/// Hoe ver de snelheid hoogstens van 1 afwijkt. Was 3 % ("niet te horen, mpv houdt de toonhoogte") — maar het tempo
/// hoor je wel (Saber, 27-11-2026). 1 % niet; wat meer is, wordt gespoeld ([kSamenSpoelVanaf]).
const kSamenMaxAfwijking = 0.01;

/// Wat een volger met zijn [afwijkingMs] doet (positief = hij loopt voor). [bezig]: stuurde hij al bij?
/// Dan pas ophouden binnen [kSamenGoed], anders pas beginnen vanaf [kSamenBijsturenVanaf] — zo blijft hij
/// niet heen en weer schakelen rond één grens.
///
/// [begin]: het nummer is net begonnen en er is in dit nummer nog niet gespoeld — dan al vanaf [kSamenSpoelBegin].
///
/// [drempel], [goed] en [spoelBegin]: dezelfde grenzen, opgerekt voor een leider met ruis ([ruisUit]).
({bool spoel, double snelheid}) bijsturing(int afwijkingMs,
    {bool bezig = false,
    bool begin = false,
    int drempel = kSamenBijsturenVanaf,
    int goed = kSamenGoed,
    int spoelBegin = kSamenSpoelBegin}) {
  final a = afwijkingMs.abs();
  if (a > (begin ? spoelBegin : kSamenSpoelVanaf)) return (spoel: true, snelheid: 1.0);
  if (a <= goed || (!bezig && a < drempel)) return (spoel: false, snelheid: 1.0);
  // Het verschil zacht wegwerken ([kSamenBijsturingTijd]): een paar promille hoor je niet.
  final v = (1 - afwijkingMs / kSamenBijsturingTijd).clamp(1 - kSamenMaxAfwijking, 1 + kSamenMaxAfwijking).toDouble();
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
    this.speelPad,
    this.kiesVersie,
    this.log,
    int Function()? nuMs,
  }) : _nuMs = nuMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// De klok van dit toestel in ms, voor de rust tussen twee sprongen ([_spoelRust]); een toets zet hem.
  final int Function() _nuMs;

  final VolgSpeler speler;
  final Track? Function(String id) nummer;
  final String? Function(Track t) idVan;
  final KlokIjk klok;

  /// De vertraging van dit toestel (ms; positief = later), uit de instellingen.
  final int Function() vertragingMs;

  /// Het bestand dat hier nu klinkt voor het spelende nummer (een versie ervan, of het nummer zelf), en een andere
  /// versie daarvan laten klinken op dezelfde plek. Null: de versie van de leider niet volgen.
  final String? Function()? speelPad;
  final Future<void> Function(String pad)? kiesVersie;
  bool _versieBezig = false;
  final void Function(String)? log;

  SamenAnker? _anker;

  /// De wachtrij (ids) van het laatste anker dat hier verwerkt is: alleen als die verandert, valt er iets over
  /// te nemen (een geschudde bibliotheek is dertigduizend ids).
  List<String> _rij = const [];
  Timer? _lus;
  bool _bezig = false;

  /// De snelheid die de volger het laatst aan de speler gaf, en wanneer ([kSamenSnelheidHoud]).
  double _gezetteSnelheid = 1.0;
  int _snelheidOp = 0;

  /// De speler op [v] zetten, alleen als dat iets anders is dan wat hij al kreeg.
  void _zetSnelheid(double v, int nu) {
    if (v == _gezetteSnelheid) return;
    _gezetteSnelheid = v;
    _snelheidOp = nu;
    unawaited(speler.zetSnelheid(v));
  }
  bool _opent = false;
  int _laatsteLog = 0;

  /// Het nummer waarin al vroeg gespoeld is ([kSamenSpoelBegin]): één keer per nummer, anders kon een sprong die net
  /// verkeerd uitkomt (de vertraging van het spoelen zelf) de volgende uitlokken, en stotterde het begin.
  String? _beginGespoeld;

  /// Wanneer deze volger het laatst zelf begon te spelen (ms): na een pauze of het openen geldt het begin opnieuw — één
  /// vroege sprong, zoals bij een nieuw nummer. Om 09:16 (27-11-2026) hervatte de Shield na een pauze 120 ms voor de
  /// Sonos, en dat was met 1 % twaalf seconden echo geweest.
  int _herstartOp = -1 << 40;

  /// Of de vroege sprong van [_beginGespoeld] op een precies anker viel ([kSamenPreciesMs]).
  bool _beginPrecies = false;

  /// Hoeveel verder dan het doel er gespoeld wordt: de tijd die het spoelen zelf kost. Begint op [kSamenSpoelMarge] en leert
  /// bij uit wat er na een precieze sprong overblijft. Op de Shield bleef er na een sprong met 60 ms gemiddeld ±50 ms
  /// voorsprong over (27-11-2026).
  int _spoelMarge = kSamenSpoelMarge;

  /// Per anker van dit nummer: wanneer het bij de leider op 0 stond (pc-klok, ms) — [kSamenVenster] stuks. Hun mediaan
  /// is de plek van de leider zonder de ruis van één meting ([leiderStart]).
  final List<int> _starts = [];
  String _startsVan = '';

  /// Wanneer het nummer bij de leider op 0 stond (pc-klok, ms), uit de mediaan van de laatste ankers; null met minder dan
  /// drie (net begonnen, of net gesprongen bij de leider).
  @visibleForTesting
  int? get leiderStart => _starts.length >= 3 ? mediaan(_starts) : null;

  /// De verschillen tussen opeenvolgende ankers van de leider ([ruisUit]); blijft over nummers heen (het is de speaker).
  final List<int> _ankerVerschillen = [];

  /// De ruis van de leider (ms), zoals de volger hem nu schat.
  @visibleForTesting
  int get ruisMs => ruisUit(_ankerVerschillen);
  bool _leerNaSprong = false;

  /// De huidige marge ([_spoelMarge]), voor de toetsen.
  @visibleForTesting
  int get spoelMarge => _spoelMarge;

  /// Wanneer er het laatst gespoeld is (ms): niet vaker dan om de [_spoelRust].
  int _gespoeldOp = 0;
  static const _spoelRust = Duration(seconds: 4);

  /// Volgt dit toestel nu een groep?
  bool get volgt => _anker != null;

  /// De groep die het volgt, of null.
  String? get groep => _anker?.groep;

  /// Hoe lang (ms) de volger bij een gewone wissel wacht voor hij het volgende nummer begint, per leider ([groep]).
  ///
  /// **Waarom (Saber, 28-11-2026: "ja dat stoort").** Een KEF heeft geen klaargezet volgend nummer: de pc start het
  /// pas als het vorige afgelopen is, en de KEF begint 0,2–0,35 s later dan de Shield, die zelf meteen doorging. De
  /// Shield sprong dan terug (+251, +358, +215, +309 ms gemeten) en je hoorde een stukje dubbel. Geleerd uit de eerste
  /// precieze meting na een wissel ([_leerWissel]); bij een naadloze leider (Sonos) blijft het rond 0.
  final Map<String, int> _wisselWacht = {};
  bool _wisselLeren = false;
  int _wisselOp = 0;
  String? _wisselNummer;

  /// Voor de speler (`PlayerStore.wisselWacht`), bij een nummer dat gewoon afliep: zoveel gepauzeerd wachten voor het
  /// volgende begint (of tot het anker van de leider er is: [opAnker] start dan op de juiste plek). Zonder groep 0.
  Duration wisselWacht() {
    final a = _anker;
    if (a == null || !a.speelt) return Duration.zero;
    _wisselLeren = true;
    _wisselOp = _nuMs();
    // Het nummer dat nu opent: alleen een meting van dát nummer zegt iets over deze wissel.
    final t = speler.current;
    _wisselNummer = t == null ? null : idVan(t);
    return Duration(milliseconds: _wisselWacht[a.groep] ?? 0);
  }

  /// De geleerde wachttijd bij een wissel voor [groep] (ms), voor de toetsen.
  @visibleForTesting
  int wisselWachtVoor(String groep) => _wisselWacht[groep] ?? 0;

  /// Na een gewone wissel: de eerste precieze meting zegt hoeveel de volger te vroeg (positief) of te laat begon. De
  /// wachttijd schuift daarmee op, hoogstens 1,5 s; binnen 15 s na de wissel, anders zegt het niets meer.
  void _leerWissel(SamenAnker a, int afwijking, int nu) {
    if (!_wisselLeren || a.trackId != _wisselNummer) return;
    _wisselLeren = false;
    if (nu - _wisselOp > 15000) return;
    final oud = _wisselWacht[a.groep] ?? 0;
    final nieuw = (oud + afwijking * 0.8).round().clamp(0, 1500).toInt();
    _wisselWacht[a.groep] = nieuw;
    log?.call('samen: wachten bij een wissel $nieuw ms (na de wissel ${afwijking >= 0 ? '+' : ''}$afwijking ms)');
  }

  /// Een nieuw anker van de pc.
  Future<void> opAnker(SamenAnker a) async {
    final eerste = _anker == null;
    // Hoe ver dit anker het vorige van hetzelfde nummer tegenspreekt, op hetzelfde moment doorgerekend: de ruis van de
    // leider ([ruisUit]). Alleen een nieuwe meting (een andere tijd), en geen sprong van een seconde of meer (spoelen).
    final oud = _anker;
    if (oud != null && oud.trackId == a.trackId && oud.speelt && a.speelt && oud.pcMs != a.pcMs) {
      final t = math.max(oud.pcMs, a.pcMs);
      final d = (verwachtePlek(oud, nuPcMs: t, vertragingMs: 0) - verwachtePlek(a, nuPcMs: t, vertragingMs: 0))
          .inMilliseconds;
      if (d.abs() < 1000) {
        _ankerVerschillen.add(d);
        if (_ankerVerschillen.length > 8) _ankerVerschillen.removeAt(0);
      }
    }
    // Wanneer het nummer bij de leider op 0 stond, volgens dit anker. Een ander nummer, een pauze of een sprong van een
    // seconde of meer bij de leider: opnieuw beginnen.
    if (a.speelt) {
      final s = a.pcMs - a.positieMs;
      if (_startsVan != a.trackId || (_starts.isNotEmpty && (s - mediaan(_starts)).abs() >= 1000)) {
        _starts.clear();
        _startsVan = a.trackId;
      }
      if (_starts.isEmpty || oud?.pcMs != a.pcMs) _starts.add(s);
      if (_starts.length > kSamenVenster) _starts.removeAt(0);
    } else {
      _starts.clear();
    }
    _anker = a;
    await klok.ijk();
    if (eerste) log?.call('samen: volgt ${a.groep} (klok ±${((klok.rttUs ?? 0) / 2000).toStringAsFixed(1)} ms)');
    final t = speler.current;
    final zelfde = t != null && idVan(t) == a.trackId;
    if (!a.speelt) {
      if (speler.playing) speler.pauzeer();
      if (zelfde) speler.seek(Duration(milliseconds: a.positieMs));
      _gezetteSnelheid = 1.0;
      await speler.zetSnelheid(1.0);
      _stopLus();
      return;
    }
    if (!zelfde) {
      await _open(a);
    } else {
      _volgRij(a);
      await _volgVersie(a);
    }
    if (zelfde && !speler.playing) {
      speler.seek(verwachtePlek(a, nuPcMs: klok.nuPcMs(), vertragingMs: vertragingMs()));
      speler.speelAf();
      _herstartOp = _nuMs();
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

  /// Speelt de leider een andere versie van dit nummer dan hier klinkt (Saber koos er een, of de standaard verschilt):
  /// die hier ook. De sprong naar de juiste plek doet de gewone bijsturing daarna, zoals na elke herstart.
  Future<void> _volgVersie(SamenAnker a) async {
    final pad = speelPad, kies = kiesVersie;
    if (pad == null || kies == null || a.speelId.isEmpty || _versieBezig) return;
    final v = nummer(a.speelId);
    if (v == null || pad() == v.path) return;
    _versieBezig = true;
    try {
      log?.call('samen: de leider speelt een andere versie — ${v.title} (${v.album})');
      await kies(v.path);
      _herstartOp = _nuMs();
    } finally {
      _versieBezig = false;
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
      if (identical(_anker, a) || _anker?.trackId == a.trackId) {
        speler.speelAf();
        _herstartOp = _nuMs();
      }
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
    // De plek van de leider uit de mediaan van de laatste ankers ([leiderStart]); net na een wissel uit het laatste.
    final start = leiderStart;
    final nuPc = klok.nuPcMs();
    final moet = start == null
        ? verwachtePlek(a, nuPcMs: nuPc, vertragingMs: vertragingMs())
        : Duration(milliseconds: math.max(0, nuPc - start - vertragingMs()));
    final afwijking = (speler.positieNauwkeurig - moet).inMilliseconds;
    final nu = _nuMs();
    // Net begonnen: het nummer (de eerste seconden) of het spelen hier (na een pauze, na het openen). Eén vroege sprong per
    // keer — de sleutel is het nummer plus dat begin.
    // Een meting die de pc zelf niet vertrouwt: niets doen tot er een betere is ([kSamenNegeerVanaf]).
    if (a.onzekerMs > kSamenNegeerVanaf) {
      if (nu - _laatsteLog > 2000) {
        _laatsteLog = nu;
        log?.call('samen: meting te onzeker (±${a.onzekerMs} ms) — wacht op een betere');
      }
      if (_bezig) {
        _bezig = false;
        _zetSnelheid(1.0, nu);
      }
      return;
    }
    final sleutel = '${t.path}@$_herstartOp';
    final precies = a.onzekerMs <= kSamenPreciesMs;
    // Al gesprongen in dit begin — tenzij dat op een grove meting was en deze precies is: dan nog één keer.
    final beginKlaar = _beginGespoeld == sleutel && (_beginPrecies || !precies);
    final begin = (speler.positieNauwkeurig < kSamenBeginTot || nu - _herstartOp < kSamenBeginTot.inMilliseconds) &&
        !beginKlaar;
    // Wat er na een precieze sprong overblijft, is de tijd die het spoelen hier kost: de marge daarop bijstellen.
    // De eerste precieze meting na een gewone wissel: de wachttijd voor de volgende keer ([wisselWacht]).
    if (_wisselLeren && precies && begin) _leerWissel(a, afwijking, nu);
    if (_leerNaSprong && nu - _gespoeldOp >= 1500) {
      _leerNaSprong = false;
      if (precies && afwijking.abs() < kSamenSpoelVanaf) {
        _spoelMarge = (_spoelMarge - (afwijking * 0.7).round()).clamp(0, 200).toInt();
        log?.call('samen: spoelmarge $_spoelMarge ms (na de sprong ${afwijking >= 0 ? '+' : ''}$afwijking ms)');
      }
    }
    final rust = nu - _gespoeldOp < _spoelRust.inMilliseconds;
    // Grenzen die meegroeien met de ruis van de leider: een KEF meldt zijn plek eens per seconde, in stappen van 48 ms,
    // met tientallen ms ruis; ook de mediaan schommelt dan nog. Bijsturen pas boven die ruis.
    final gemeten = afwijking;
    final ruis = ruisMs;
    final drempel = math.max(kSamenBijsturenVanaf, math.min(ruis, kSamenDrempelHoogstens));
    final goed = math.max(kSamenGoed, math.min(ruis ~/ 2, kSamenDrempelHoogstens ~/ 2));
    final spoelBegin = math.max(kSamenSpoelBegin, math.min(2 * ruis, kSamenSpoelVanaf - 1));
    var b = bijsturing(gemeten, bezig: _bezig, begin: begin, drempel: drempel, goed: goed, spoelBegin: spoelBegin);
    // Net gespoeld: eerst bijsturen, niet meteen weer springen.
    if (b.spoel && rust) {
      b = (
        spoel: false,
        snelheid: bijsturing(gemeten.clamp(-kSamenSpoelVanaf, kSamenSpoelVanaf),
                bezig: true, drempel: drempel, goed: goed, spoelBegin: spoelBegin)
            .snelheid
      );
    }
    if (nu - _laatsteLog > 2000) {
      _laatsteLog = nu;
      log?.call('samen: afwijking ${afwijking >= 0 ? '+' : ''}$afwijking ms'
          '${ruis > 0 ? ' (ruis ±$ruis${start == null ? '' : ', mediaan van ${_starts.length}'})' : ''} → '
          '${b.spoel ? 'spoelen' : 'snelheid ${b.snelheid.toStringAsFixed(3)}'}');
    }
    if (b.spoel) {
      _gespoeldOp = nu;
      if (begin) {
        _beginGespoeld = sleutel;
        _beginPrecies = precies;
      }
      _leerNaSprong = precies;
      speler.seek(moet + Duration(milliseconds: _spoelMarge));
      _zetSnelheid(1.0, nu);
      _bezig = false;
      return;
    }
    // Zo weinig mogelijk snelheidsopdrachten: in stappen van [kSamenSnelheidStap], en een gezette snelheid blijft
    // minstens [kSamenSnelheidHoud] staan.
    var doel = snelheidsstap(b.snelheid);
    if (doel != _gezetteSnelheid && nu - _snelheidOp < kSamenSnelheidHoud.inMilliseconds) doel = _gezetteSnelheid;
    _bezig = doel != 1.0;
    _zetSnelheid(doel, nu);
  }

  /// Uit de groep: niet meer volgen, gewoon weer op dit toestel.
  Future<void> stop({bool pauzeer = true}) async {
    if (_anker == null) return;
    log?.call('samen: volgt ${_anker!.groep} niet meer');
    _anker = null;
    _stopLus();
    _gezetteSnelheid = 1.0;
    await speler.zetSnelheid(1.0);
    if (pauzeer && speler.playing) speler.pauzeer();
  }
}
