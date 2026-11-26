// Bestaat deze opname officieel in studiokwaliteit? TIDAL vragen.
//
// Saber, 26-11-2026, bij Ricky Martin "Maria" ("Studio · 24/48" van Soulseek — een gedecodeerde Opus-stream): *"Laat de
// app controleren via qobuz en tidal of dit daadwerkelijk studio bestaat"*. TIDAL heeft precies die opname — "María
// (Pablo Flores Spanglish Radio Edit)", 271 s, op het album "Ricky Martin" — alleen als LOSSLESS; alleen een andere edit
// (243 s, op een verzamelplaat) staat er in hi-res. Qobuz zegt hetzelfde (16-Bit/44.1 kHz), maar Qobuz laat geen app
// binnen: zijn API vraagt sinds kort een login, en zijn winkelpagina's weigeren automatische verzoeken ("Access
// Denied"). TIDAL zoekt de app al, met tidaler.
//
// Wat het beslist: heeft TIDAL precies deze opname, en nergens in hi-res, dan is een "studio" ervan geen studio — bij
// binnenkomst weg (online.dart), en een studioversie die er al staat ook ([StudioNakijker]). Kent TIDAL hem niet, of
// antwoordt TIDAL niet, dan beslist alleen de meter zoals voorheen: niets weten is geen bewijs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'organize.dart' show normKey, zonderFeat, zonderNeutraalMerk;
import 'tidal.dart' show TidalKwaliteit, TidalTrack;
import 'tidal_beter.dart' show tidalStereoNummers;
import 'tidaler.dart' show tidalArtiestPast;

/// Wat TIDAL over een opname zegt.
enum StudioOpTidal {
  /// TIDAL heeft precies deze opname in hi-res (HIRES_LOSSLESS): een studio kan bestaan.
  hires,

  /// TIDAL heeft precies deze opname, maar alleen in cd-kwaliteit (LOSSLESS): officieel bestaat er geen studio.
  alleenCd,

  /// TIDAL kent deze opname niet (of niet bij deze lengte): niets bewezen.
  onbekend,

  /// TIDAL antwoordde niet (niet ingelogd, geen netwerk): niets bewezen, later opnieuw.
  geenAntwoord,
}

/// Hoeveel de lengte op TIDAL mag schelen: zoveel als de TIDAL-ronde ([kTidalBeterLengteSpeling]). Een andere edit
/// van hetzelfde nummer (Maria: 263, 271, 331, 243 s) scheelt meer.
const int kStudioLengteSpeling = 2;

/// Een haakje of staart die een ANDERE opname noemt dan het origineel. Die telt alleen als jouw titel hem ook noemt —
/// "María (MTV Unplugged Version)" is niet de "Maria" van je single, ook al was hij even lang.
final _andereOpname = RegExp(
    r'\b(?:live|unplugged|acoustic|akoestisch|ac[uú]stic[oa]|instrumental|instrumentaal|karaoke|re-?mix|rmx|demo|'
    r'a\s?cap+ella|cover|orchestral|symphonic|sessions?|rehearsal)\b',
    caseSensitive: false);

final _haakjes = RegExp(r'\s*[(\[][^)\]]*[)\]]');
final _staart = RegExp(r'\s+[-–—]\s+.*$');

/// De titel zonder haakjes en zonder staart na een streepje: "María (Pablo Flores Spanglish Radio Edit)" → "maria".
String studioTitelKern(String titel) => normKey(zonderFeat(titel).replaceAll(_haakjes, ' ').replaceAll(_staart, ''));

String _strak(String titel) => normKey(zonderNeutraalMerk(zonderFeat(titel)));

/// Wat TIDAL ([nummers], de treffers van één zoekvraag) van precies deze opname heeft.
///
/// Dezelfde opname: de artiest volgens [tidalArtiestPast], de lengte op [kStudioLengteSpeling] seconden, en de titel
/// gelijk — streng (op gast en neutrale haakjes na, zoals de TIDAL-ronde), of op de kern als de rest alleen de uitgave
/// noemt: jouw single heet "Maria", TIDAL noemt dezelfde 271 seconden "María (Pablo Flores Spanglish Radio Edit)". Wat
/// een andere opname noemt (live, remix, akoestisch …) telt niet, tenzij jouw titel dat ook doet.
///
/// Eén treffer in hi-res is genoeg: dan kan een studio bestaan. Alleen treffers in cd-kwaliteit: [StudioOpTidal.alleenCd].
StudioOpTidal studioOpTidal({
  required String artiest,
  required String titel,
  required int seconden,
  required List<TidalTrack> nummers,
}) {
  final kern = studioTitelKern(titel);
  if (seconden <= 0 || kern.isEmpty || artiest.trim().isEmpty) return StudioOpTidal.onbekend;
  final strak = _strak(titel);
  final anders = _andereOpname.hasMatch(titel);
  final zelfde = [
    for (final x in nummers)
      if (x.seconden > 0 &&
          (x.seconden - seconden).abs() <= kStudioLengteSpeling &&
          x.kwaliteit != TidalKwaliteit.onbekend &&
          tidalArtiestPast(artiest, x.artist) &&
          (_strak(x.title) == strak || (studioTitelKern(x.title) == kern && _andereOpname.hasMatch(x.title) == anders)))
        x,
  ];
  if (zelfde.any((x) => x.kwaliteit == TidalKwaliteit.hires)) return StudioOpTidal.hires;
  if (zelfde.isNotEmpty) return StudioOpTidal.alleenCd;
  return StudioOpTidal.onbekend;
}

/// De zin voor het logboek en het scherm als TIDAL de studio tegenspreekt.
const String kGeenStudioOpTidal = 'geen studio: TIDAL heeft deze opname alleen in cd-kwaliteit';

/// De vraag aan TIDAL: [zoek] krijgt "artiest titel" en geeft de ruwe uitvoer van tidalers zoekhulpje (of null als
/// tidaler niet antwoordde). Wat TIDAL zei, onthoudt hij [geheugenDuur] per opname: de jacht probeert vaak meerdere
/// kopieën van hetzelfde nummer na elkaar, en TIDAL blokkeert een login die als een machine zoekt.
Future<StudioOpTidal> Function(String artiest, String titel, int seconden) studioOpTidalVraag({
  required Future<String?> Function(String vraag) zoek,
  Duration geheugenDuur = const Duration(hours: 12),
  DateTime Function()? klok,
}) {
  final nu = klok ?? DateTime.now;
  final geheugen = <String, (DateTime, StudioOpTidal)>{};
  return (artiest, titel, seconden) async {
    final sleutel = '${normKey(artiest)}|${studioTitelKern(titel)}|$seconden';
    final al = geheugen[sleutel];
    if (al != null && nu().difference(al.$1) < geheugenDuur) return al.$2;
    String? uit;
    try {
      uit = await zoek('$artiest ${zonderFeat(titel)}');
    } catch (_) {
      uit = null;
    }
    if (uit == null) return StudioOpTidal.geenAntwoord;
    final k = studioOpTidal(artiest: artiest, titel: titel, seconden: seconden, nummers: tidalStereoNummers(uit));
    geheugen[sleutel] = (nu(), k);
    return k;
  };
}

/// Een studioversie om na te kijken: het bestand, het nummer ernaast, en wat TIDAL moet zoeken.
typedef StudioTeKijken = ({String versie, String anker, String artiest, String titel, int seconden});

/// Kijkt de studioversies die er al staan één voor één na bij TIDAL, traag op de achtergrond: wat TIDAL alleen in
/// cd-kwaliteit heeft, gaat weg ([weg], main.dart: naar de prullenbak, het nummer blijft). Wat hij vond, staat in
/// `studio_op_tidal.json`, zodat een herstart niet opnieuw begint.
class StudioNakijker {
  StudioNakijker({
    required this.bestand,
    required this.teKijken,
    required this.vraag,
    required this.weg,
    this.log,
    DateTime Function()? klok,
  }) : _klok = klok ?? DateTime.now;

  final String bestand;
  final Iterable<StudioTeKijken> Function() teKijken;
  final Future<StudioOpTidal> Function(String artiest, String titel, int seconden) vraag;
  final Future<void> Function(StudioTeKijken s) weg;
  final void Function(String regel)? log;
  final DateTime Function() _klok;

  /// Eén per zes minuten: naast de TIDAL-ronde (één per drie) samen dertig vragen per uur.
  static const Duration tussen = Duration(minutes: 6);

  /// Pas zo lang na het opstarten de eerste.
  static const Duration eerste = Duration(minutes: 8);

  /// Opnieuw na: hi-res of alleen-cd een maand (TIDAL voegt hi-res toe), onbekend een week, geen antwoord een dag.
  static Duration wachtNa(StudioOpTidal k) => switch (k) {
        StudioOpTidal.hires || StudioOpTidal.alleenCd => const Duration(days: 30),
        StudioOpTidal.onbekend => const Duration(days: 7),
        StudioOpTidal.geenAntwoord => const Duration(days: 1),
      };

  final Map<String, ({int ms, StudioOpTidal k})> _gezien = {};
  Timer? _wekker;
  bool _gestopt = false, _bezig = false;

  static String _sleutel(String pad) => pad.replaceAll('\\', '/').toLowerCase();

  ({int ms, StudioOpTidal k})? van(String pad) => _gezien[_sleutel(pad)];

  Future<void> laad() async {
    try {
      final f = File(bestand);
      if (!f.existsSync()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      for (final e in j.entries) {
        final v = e.value;
        if (v is! Map || v['ms'] is! num) continue;
        final k = StudioOpTidal.values.where((x) => x.name == v['k']).firstOrNull;
        if (k != null) _gezien['${e.key}'] = (ms: (v['ms'] as num).toInt(), k: k);
      }
    } catch (_) {/* een kapot geheugen begint gewoon opnieuw */}
  }

  Future<void> _bewaar() async {
    try {
      final tmp = File('$bestand.tmp');
      await tmp.writeAsString(jsonEncode({for (final e in _gezien.entries) e.key: {'ms': e.value.ms, 'k': e.value.k.name}}));
      await tmp.rename(bestand);
    } catch (_) {/* bewaren is mooi meegenomen */}
  }

  Future<void> start() async {
    await laad();
    _plan(eerste);
  }

  void stop() {
    _gestopt = true;
    _wekker?.cancel();
  }

  void _plan(Duration na) {
    if (_gestopt) return;
    _wekker?.cancel();
    _wekker = Timer(na, () async {
      await stap();
      _plan(tussen);
    });
  }

  /// De volgende die aan de beurt is: nooit nagekeken eerst, dan het langst geleden — of null.
  StudioTeKijken? volgende() {
    final nuMs = _klok().millisecondsSinceEpoch;
    StudioTeKijken? beste;
    var besteMs = 1 << 62;
    for (final s in teKijken()) {
      if (s.seconden <= 0) continue;
      final g = van(s.versie);
      if (g != null && nuMs - g.ms < wachtNa(g.k).inMilliseconds) continue;
      final ms = g?.ms ?? -1;
      if (ms < besteMs) {
        beste = s;
        besteMs = ms;
      }
    }
    return beste;
  }

  /// Eén studioversie nakijken. Geeft terug wat TIDAL zei, of null als er niets te doen was.
  Future<StudioOpTidal?> stap() async {
    if (_bezig || _gestopt) return null;
    final s = volgende();
    if (s == null) return null;
    _bezig = true;
    try {
      final k = await vraag(s.artiest, s.titel, s.seconden);
      _gezien[_sleutel(s.versie)] = (ms: _klok().millisecondsSinceEpoch, k: k);
      await _bewaar();
      if (k == StudioOpTidal.alleenCd) {
        log?.call('studio op TIDAL: "${s.artiest} — ${s.titel}" (${s.seconden} s) alleen in cd-kwaliteit — ${s.versie}');
        await weg(s);
      }
      return k;
    } catch (e) {
      log?.call('studio op TIDAL "${s.artiest} — ${s.titel}": $e');
      return null;
    } finally {
      _bezig = false;
    }
  }
}
