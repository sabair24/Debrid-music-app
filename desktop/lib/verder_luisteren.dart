/// Verder luisteren op een ander toestel (Saber, 17-10-2026: "ik wil ook als music afspeelt op pc,
/// in ik ga op men mac, gsm, ipad of shield, dat die hervat waar ik zat").
///
/// **Wat hij koos.** Opent hij de app op een ander toestel terwijl er ergens iets speelt, dan staat er
/// een balk: "Speelt op de pc: Be My Lover — La Bouche · Hier verder luisteren". Eén klik (op de tv:
/// OK) en dit toestel speelt verder op dezelfde plek in het nummer, met dezelfde wachtrij, shuffle en
/// herhalen; het toestel waar het vandaan kwam pauzeert. Het werkt van elk toestel naar elk, en ook
/// als het al gepauzeerd staat ("Verder waar je was"), tot een dag oud. Op de pc staat daarnaast
/// "Speel op …" om het naar een ander toestel te sturen.
///
/// **Hoe.** Elk toestel meldt wat het speelt aan de pc (de op `progress` in de gedeelde staat, zie
/// `lan/state_store.dart`). Elk toestel kijkt naar die stand: de pc meteen (hij houdt hem zelf bij),
/// een gsm, iPad, Mac of Shield elke [kVerderKijk]. Neemt een toestel over, dan meldt het zijn eerste
/// stand met `overname` = het toestel waar het vandaan kwam; dat toestel ziet zichzelf genoemd en
/// pauzeert ([moetPauzeren]). Een verzoek van de pc ("Speel op …") is een op `verzoek` met het
/// toestel dat moet overnemen ([verzoekVoorMij]).
///
/// De regels staan los van de app als zuivere functies, zodat een toets ze kan narekenen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart' show Track;
import 'player.dart' show RepeatMode;

/// Hoe vaak een toestel (niet de pc) naar de stand kijkt.
const kVerderKijk = Duration(seconds: 4);

/// Een melding van "speelt" die ouder is dan dit, is een toestel dat weg is of slaapt: dan bieden we
/// hem aan als "verder waar je was", niet als "speelt op". Een spelend toestel meldt elke vijf seconden.
const kVerderSpeeltNog = Duration(seconds: 30);

/// Ouder dan een dag biedt niemand meer aan (Saber: "na een dag niet meer").
const kVerderTotEenDag = Duration(hours: 24);

/// Wat een ander toestel speelt of speelde.
@immutable
class VerderAanbod {
  const VerderAanbod({
    required this.toestel,
    required this.toestelNaam,
    required this.rij,
    required this.index,
    required this.positie,
    required this.speelde,
    required this.opMs,
    this.shuffle = false,
    this.herhaal = RepeatMode.off,
    this.radioArtiest,
  });

  /// Speelde er een radio: rond welke artiest. Dan start dit toestel dezelfde radio, met [nummer]
  /// eerst. Null zonder radio.
  final String? radioArtiest;

  final String toestel;
  final String toestelNaam;
  final List<Track> rij;
  final int index;
  final Duration positie;

  /// Speelde het nog toen het gemeld werd (en is die melding vers)?
  final bool speelde;

  /// Wanneer het gemeld werd, in milliseconden sinds 1970 (klok van de pc).
  final int opMs;
  final bool shuffle;
  final RepeatMode herhaal;

  Track get nummer => rij[index];

  /// Waarmee een weggeklikt aanbod weggeklikt blijft: hetzelfde toestel en hetzelfde nummer.
  String get sleutel => '$toestel|${nummer.path}';
}

/// Uit de gemelde stand [p] (de json van `PlaybackProgress`) het aanbod voor dit toestel, of null.
///
/// Geen aanbod van jezelf, niet als je zelf iets speelt, niet ouder dan een dag, en niet als het
/// weggeklikt is ([afgewezen]). [nummer] vertaalt een id van de pc naar een nummer hier; ids die hier
/// niet bestaan vallen uit de rij, en blijft het nummer zelf onvindbaar dan is er geen aanbod.
VerderAanbod? aanbodUit(
  Map<String, dynamic>? p, {
  required String mijnId,
  required int nuMs,
  required bool ikSpeel,
  required Track? Function(String id) nummer,
  Set<String> afgewezen = const {},
}) {
  if (p == null || ikSpeel) return null;
  final id = (p['trackId'] ?? '') as String;
  final van = (p['deviceId'] ?? '') as String;
  if (id.isEmpty || van.isEmpty || van == mijnId) return null;
  final op = (p['updatedAt'] as num?)?.toInt() ?? 0;
  final oud = nuMs - op;
  if (op <= 0 || oud > kVerderTotEenDag.inMilliseconds) return null;
  final speelde = p['playing'] == true && oud <= kVerderSpeeltNog.inMilliseconds;

  final ids = [for (final x in (p['queue'] as List? ?? const [])) x.toString()];
  final gemeld = (p['index'] as num?)?.toInt() ?? 0;
  final rij = <Track>[];
  var index = -1;
  for (var i = 0; i < ids.length; i++) {
    final t = ids[i].isEmpty ? null : nummer(ids[i]);
    if (t == null) continue;
    if (i == gemeld && ids[i] == id) index = rij.length;
    rij.add(t);
  }
  if (index < 0) {
    // De rij klopte niet met het nummer (of was leeg): dan alleen het nummer zelf.
    final t = nummer(id);
    if (t == null) return null;
    rij
      ..clear()
      ..add(t);
    index = 0;
  }
  final herhaal = switch (p['repeat']) {
    'all' => RepeatMode.all,
    'one' => RepeatMode.one,
    _ => RepeatMode.off,
  };
  final a = VerderAanbod(
    toestel: van,
    toestelNaam: (p['deviceName'] ?? '') as String,
    rij: rij,
    index: index,
    positie: Duration(milliseconds: (p['positionMs'] as num?)?.toInt() ?? 0),
    speelde: speelde,
    opMs: op,
    shuffle: p['shuffle'] == true,
    herhaal: herhaal,
    radioArtiest: switch ((p['radio'] as Map?)?['artiest']) {
      final String r when r.trim().isNotEmpty => r,
      _ => null,
    },
  );
  if (afgewezen.contains(a.sleutel)) return null;
  return a;
}

/// Waar het nummer nu is: de gemelde plek, plus de tijd sindsdien als het speelde (hooguit een
/// minuut: wat langer weg is, is niet meer "net").
Duration startPositie(VerderAanbod a, int nuMs) => a.speelde
    ? a.positie + Duration(milliseconds: (nuMs - a.opMs).clamp(0, 60000))
    : a.positie;

/// Moet dit toestel pauzeren? Ja als een ander toestel meldt dat het van DIT toestel overnam, en dat
/// nog niet eerder afgehandeld is ([alGedaanOp] = de `updatedAt` van de vorige keer).
bool moetPauzeren(Map<String, dynamic>? p, {required String mijnId, required bool ikSpeel, int alGedaanOp = 0}) {
  if (p == null || !ikSpeel) return false;
  final op = (p['updatedAt'] as num?)?.toInt() ?? 0;
  return (p['overname'] ?? '') == mijnId && (p['deviceId'] ?? '') != mijnId && op > alGedaanOp;
}

/// Is er een verzoek van de pc ("Speel op …") voor dit toestel dat nog niet afgehandeld is?
bool verzoekVoorMij(Map<String, dynamic>? v, {required String mijnId, required int nuMs, int alGedaanOp = 0}) {
  if (v == null) return false;
  final op = (v['at'] as num?)?.toInt() ?? 0;
  // Een verzoek dat een halve minuut blijft liggen (het toestel sliep), voert niemand meer uit.
  return (v['naar'] ?? '') == mijnId && op > alGedaanOp && nuMs - op < 30000;
}

/// Wat de bediening van buiten nodig heeft: de speler en de pc.
abstract class VerderBron {
  /// Wie ben ik, voor de pc.
  String get mijnId;

  /// Speelt er hier iets?
  bool get ikSpeel;

  /// Een id van de pc als nummer hier.
  Track? nummer(String id);

  /// De laatst bekende stand en het laatste verzoek, of null als de pc er niet is.
  Future<({Map<String, dynamic>? stand, Map<String, dynamic>? verzoek})?> haal();

  /// Speel [rij] vanaf [index], op [positie]. Met [radioArtiest] een radio rond die artiest, met het
  /// nummer op [index] eerst.
  Future<void> speel(List<Track> rij, int index, Duration positie,
      {required bool spelen, required bool shuffle, required RepeatMode herhaal, String? radioArtiest});

  /// Pauzeer hier.
  void pauzeer();
}

/// De balk "Hier verder luisteren" en wat erachter zit. Eén per app.
class VerderLuisteren extends ChangeNotifier {
  VerderLuisteren(this.bron, {this.klok, this.kijkElke = kVerderKijk});

  final VerderBron bron;

  /// Voor een toets: de tijd. Anders de klok van dit toestel.
  final int Function()? klok;
  final Duration kijkElke;

  int get _nu => klok?.call() ?? DateTime.now().millisecondsSinceEpoch;

  VerderAanbod? _aanbod;

  /// Wat de balk nu aanbiedt, of null.
  VerderAanbod? get aanbod => _aanbod;

  final _afgewezen = <String>{};
  int _gepauzeerdOp = 0;
  int _verzoekOp = 0;

  /// Het toestel waarvan zojuist overgenomen werd: gaat één keer mee in de volgende melding.
  String? _overnameVan;

  /// Na pauzeren door een overname even niets melden: anders overschrijft "gepauzeerd op de pc" de
  /// stand van het toestel dat net overnam.
  int _stilTot = 0;

  Timer? _kijk;
  bool _bezig = false;

  /// Begin met kijken (op een toestel elke [kijkElke]; de pc roept [opStand] zelf aan).
  void start({bool zelfKijken = true}) {
    _kijk?.cancel();
    if (zelfKijken) _kijk = Timer.periodic(kijkElke, (_) => kijkNu());
    unawaited(kijkNu());
  }

  void stop() {
    _kijk?.cancel();
    _kijk = null;
  }

  /// Nu meteen kijken (bij het openen van de app, of als de pc weer bereikbaar is).
  Future<void> kijkNu() async {
    if (_bezig) return;
    _bezig = true;
    try {
      final r = await bron.haal();
      if (r != null) await opStand(r.stand, verzoek: r.verzoek);
    } catch (_) {
      // Geen pc: de balk blijft wat hij was.
    } finally {
      _bezig = false;
    }
  }

  /// Een nieuwe stand van de pc.
  Future<void> opStand(Map<String, dynamic>? stand, {Map<String, dynamic>? verzoek}) async {
    final nu = _nu;
    if (moetPauzeren(stand, mijnId: bron.mijnId, ikSpeel: bron.ikSpeel, alGedaanOp: _gepauzeerdOp)) {
      _gepauzeerdOp = (stand!['updatedAt'] as num?)?.toInt() ?? nu;
      _stilTot = nu + 6000;
      bron.pauzeer();
    }
    if (verzoekVoorMij(verzoek, mijnId: bron.mijnId, nuMs: nu, alGedaanOp: _verzoekOp)) {
      _verzoekOp = (verzoek!['at'] as num?)?.toInt() ?? nu;
      final a = aanbodUit({...verzoek, 'updatedAt': _verzoekOp},
          mijnId: bron.mijnId, nuMs: nu, ikSpeel: false, nummer: bron.nummer);
      if (a != null) {
        await neemOver(a);
        return;
      }
    }
    final nieuw = aanbodUit(stand,
        mijnId: bron.mijnId, nuMs: nu, ikSpeel: bron.ikSpeel, nummer: bron.nummer, afgewezen: _afgewezen);
    if (!_zelfde(nieuw, _aanbod)) {
      _aanbod = nieuw;
      notifyListeners();
    }
  }

  static bool _zelfde(VerderAanbod? a, VerderAanbod? b) =>
      a?.sleutel == b?.sleutel && a?.speelde == b?.speelde && a?.positie == b?.positie && a?.opMs == b?.opMs;

  /// "Hier verder luisteren".
  Future<void> neemOver([VerderAanbod? welk]) async {
    final a = welk ?? _aanbod;
    if (a == null) return;
    _aanbod = null;
    notifyListeners();
    _overnameVan = a.toestel;
    await bron.speel(a.rij, a.index, startPositie(a, _nu),
        spelen: true, shuffle: a.shuffle, herhaal: a.herhaal, radioArtiest: a.radioArtiest);
  }

  /// Het kruisje: dit nummer van dit toestel niet meer aanbieden.
  void wijsAf() {
    final a = _aanbod;
    if (a == null) return;
    _afgewezen.add(a.sleutel);
    _aanbod = null;
    notifyListeners();
  }

  /// Hoort er bij de volgende melding van dit toestel een `overname` (één keer), en mag er nu
  /// gemeld worden? Null als er niet gemeld moet worden.
  ({String? overname})? meldNu() {
    if (_nu < _stilTot) return null;
    final van = _overnameVan;
    _overnameVan = null;
    return (overname: van);
  }

  /// Speelt er nu hier iets, dan is er niets aan te bieden.
  void spelerVeranderd() {
    if (_aanbod != null && bron.ikSpeel) {
      _aanbod = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
