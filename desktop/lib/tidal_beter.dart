// Een betere kopie van TIDAL voor de hele bibliotheek, traag op de achtergrond.
//
// Saber, 24-10-2026, bij "You Got It" (FLAC 16/44,1) op de pc: "als er een beter versie kwaliteit te vinden is op
// tidal, moet de app deze gebruiken". Gevraagd wanneer, koos hij de hele bibliotheek — ook wat er al staat. Soulseek
// blijft de eerste bron bij het halen (meteen spelen); TIDAL is waar de app daarna naar beter kijkt.
//
// Een ronde op de pc: om de [kTidalBeterTussen] één nummer. Eerst wat het meest wint (een mp3, of een FLAC met een
// muur in het spectrum), dan de FLAC's van 16 bit. TIDAL zoeken kost niets op schijf; halen gebeurt alleen als TIDAL
// zelf zegt dat het beter is ([beterOpTidal]), en wat binnenkomt gaat door de keuring van een wens
// (`DownloadManager.haalBeterVanTidal`): echt, even lang, dezelfde opname, bewezen beter. Wat de ronde per nummer
// vond, staat in `tidal_beter.json`, zodat een herstart niet opnieuw begint.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'audioformaten.dart' show isVerliesvrij, soortVan;
import 'models.dart' show Track;
import 'organize.dart' show normKey, zonderFeat, zonderNeutraalMerk;
import 'tidal.dart' show TidalKwaliteit, TidalTrack, tidalKwaliteitUit;
import 'tidaler.dart' show tidalArtiestPast;

/// Eén nummer per drie minuten: twintig per uur. TIDAL blokkeert een login die als een machine zoekt
/// ("abuse_detected"), en dit is een achtergrondklus, geen vraag van iemand die wacht.
const Duration kTidalBeterTussen = Duration(minutes: 3);

/// Pas zo lang na het opstarten de eerste: dan is de bibliotheek gelezen en is de app niet meer druk.
const Duration kTidalBeterStart = Duration(minutes: 5);

/// Na een fout van tidaler (niet ingelogd, geen netwerk) zo lang niets.
const Duration kTidalBeterRust = Duration(hours: 1);

/// Een nummer zonder betere kopie op TIDAL wordt na zoveel dagen opnieuw bekeken: TIDAL voegt hi-res toe.
const int kTidalBeterOpnieuwDagen = 60;

/// Hoeveel de lengte op TIDAL mag schelen. Strenger dan de keuring na het halen (6 s): "You Got It" heeft op TIDAL
/// naast het origineel (Mystery Girl, 210 s, alleen cd-kwaliteit) de orkestversie van 2017 (216 s) in hi-res, en dat
/// is een andere opname.
const int kTidalBeterLengteSpeling = 2;

/// Hoeveel de lengte mag schelen als TIDAL het nummer van HETZELFDE album heeft: zoveel als de keuring na het halen.
/// Toto, "Africa" (Saber, 24-10-2026): op TIDAL 295 s op Toto IV, elke cd-kopie op Soulseek 301 s — een andere master
/// van dezelfde plaat, die bij 2 s nooit geprobeerd werd. De orkestversie van "You Got It" staat op een ander album.
const int kTidalBeterLengteSpelingZelfdeAlbum = 6;

/// Wat TIDAL minstens moet hebben om beter te zijn dan wat er ligt.
enum TidalMinstens {
  /// Daar is bij TIDAL niets te winnen: 24 bit of meer.
  geenWinst,

  /// Een mp3 of een verdachte FLAC: cd-kwaliteit van TIDAL is al beter.
  cd,

  /// Een echte FLAC van 16 bit: alleen hi-res is beter.
  hires,
}

/// Wat TIDAL minstens moet hebben voor [t]. [verdacht]: het spectrum van dit bestand heeft een muur (afgekapt of
/// vermoedelijk), dan is het geen echte cd-kopie, ook al is het een FLAC. Een bitdiepte die de kop niet noemt (0) telt
/// als 16 bit; of een 24-bitbestand echt 24 bit draagt, meet de keuring pas als er iets binnenkomt.
TidalMinstens tidalMinstens(Track t, {bool verdacht = false}) {
  if (!isVerliesvrij(soortVan(t.path)) || verdacht) return TidalMinstens.cd;
  if (t.bitsPerSample <= 16) return TidalMinstens.hires;
  return TidalMinstens.geenWinst;
}

/// De nummers in de uitvoer van het zoekhulpje van tidaler (een JSON-regel per treffer), zonder wat niet stereo is.
List<TidalTrack> tidalStereoNummers(String uitvoer) {
  final uit = <TidalTrack>[];
  final gezien = <String>{};
  for (final regel in uitvoer.split(RegExp(r'\r\n|\r|\n'))) {
    final r = regel.trim();
    if (!r.startsWith('{')) continue;
    try {
      final j = jsonDecode(r);
      if (j is! Map || j['id'] == null) continue;
      if ((j['soort'] ?? 'track') != 'track' || j['stereo'] == false) continue;
      final id = '${j['id']}';
      if (!gezien.add(id)) continue;
      final tags = j['tags'];
      final seconden = j['seconden'];
      uit.add(TidalTrack(id, '${j['titel'] ?? ''}', '${j['artiest'] ?? ''}',
          album: '${j['album'] ?? ''}',
          albumId: '${j['albumId'] ?? ''}',
          seconden: seconden is num ? seconden.toInt() : int.tryParse('${seconden ?? ''}') ?? 0,
          kwaliteit: tidalKwaliteitUit(tags is List ? [for (final x in tags) '$x'] : const [])));
    } catch (_) {/* geen treffer */}
  }
  return uit;
}

String _titelSleutel(String titel) => normKey(zonderNeutraalMerk(zonderFeat(titel)));

/// Het nummer op TIDAL dat [t] is en beter klinkt, of null.
///
/// Dezelfde opname: de artiest volgens [tidalArtiestPast], de titel gelijk op gast en neutrale haakjes na
/// ("(2015 Remaster)" telt niet, "(Live)" wel), en de lengte op [kTidalBeterLengteSpeling] seconden, of op
/// [kTidalBeterLengteSpelingZelfdeAlbum] als TIDAL het van hetzelfde album heeft. Beter: de kwaliteit die TIDAL zelf
/// opgeeft haalt [minstens]. Hi-res gaat voor, dan de kleinste lengteafwijking. Zonder gekende lengte van [t] niets:
/// dan is "dezelfde opname" niet na te gaan.
TidalTrack? beterOpTidal(Track t, List<TidalTrack> nummers,
    {required TidalMinstens minstens, Iterable<String> nee = const []}) {
  if (minstens == TidalMinstens.geenWinst) return null;
  final sec = t.duration?.inSeconds ?? 0;
  if (sec <= 0) return null;
  final weg = nee.toSet();
  bool goedGenoeg(TidalKwaliteit k) =>
      minstens == TidalMinstens.cd ? k != TidalKwaliteit.onbekend : k == TidalKwaliteit.hires;
  final kandidaten = [
    for (final x in zelfdeOpnameOpTidal(t, nummers))
      if (!weg.contains(x.id) && goedGenoeg(x.kwaliteit)) x,
  ];
  if (kandidaten.isEmpty) return null;
  int rang(TidalTrack x) => x.kwaliteit == TidalKwaliteit.hires ? 0 : 1;
  kandidaten.sort((a, b) {
    final r = rang(a).compareTo(rang(b));
    return r != 0 ? r : (a.seconden - sec).abs().compareTo((b.seconden - sec).abs());
  });
  return kandidaten.first;
}

/// De nummers in [nummers] die precies [t] zijn: de artiest volgens [tidalArtiestPast], de titel gelijk op gast en
/// neutrale haakjes na, en de lengte zoals bij [beterOpTidal]. Leeg zonder gekende lengte van [t].
List<TidalTrack> zelfdeOpnameOpTidal(Track t, List<TidalTrack> nummers) {
  final sec = t.duration?.inSeconds ?? 0;
  if (sec <= 0) return const [];
  final titel = _titelSleutel(t.title);
  final album = _titelSleutel(t.album);
  bool lengtePast(TidalTrack x) {
    final d = (x.seconden - sec).abs();
    return d <= kTidalBeterLengteSpeling ||
        (d <= kTidalBeterLengteSpelingZelfdeAlbum && album.isNotEmpty && _titelSleutel(x.album) == album);
  }

  return [
    for (final x in nummers)
      if (x.seconden > 0 && lengtePast(x) && _titelSleutel(x.title) == titel && tidalArtiestPast(t.artist, x.artist)) x,
  ];
}

/// Het beste dat TIDAL van precies [t] heeft ([zelfdeOpnameOpTidal]): hi-res, cd, of null als TIDAL hem niet heeft of
/// niet zegt in welke kwaliteit. "Cd" is het bewijs dat er officieel geen hi-res van deze opname bestaat
/// (blijvende_jacht.dart, [Jachtbewijs.officieel]).
TidalKwaliteit? hoogsteOpTidal(Track t, List<TidalTrack> nummers) {
  final zelfde = zelfdeOpnameOpTidal(t, nummers);
  if (zelfde.any((x) => x.kwaliteit == TidalKwaliteit.hires)) return TidalKwaliteit.hires;
  if (zelfde.any((x) => x.kwaliteit == TidalKwaliteit.cd)) return TidalKwaliteit.cd;
  return null;
}

/// Wat de ronde voor één bestand vond.
enum TidalBeterUitslag {
  /// TIDAL heeft niets beters van deze opname.
  geen,

  /// Een betere kopie van TIDAL staat nu in de bibliotheek.
  vervangen,

  /// Gehaald, maar de keuring wees hem af (niet echt, andere opname, niet bewezen beter). Dat id komt niet terug.
  afgewezen,

  /// Zoeken of halen lukte niet. Morgen opnieuw.
  mislukt,
}

/// Het geheugen van de ronde, per pad: wanneer en met welke uitslag, en welke TIDAL-ids de keuring afwees.
/// De regels waarmee de oordelen in het geheugen geveld zijn. Omhoog bij een regel die vaker "beter" vindt: dan
/// komen de nummers met "niets beters" van vóór die regel opnieuw aan de beurt, in plaats van pas na
/// [kTidalBeterOpnieuwDagen] dagen.
/// 2 (25-10-2026): tot 6 s lengteverschil van hetzelfde album ([kTidalBeterLengteSpelingZelfdeAlbum]) — Africa (Toto)
/// stond met "niets beters" in het geheugen door de 2 s van toen.
const int kTidalBeterGeheugenVersie = 2;

/// In het bestand een gewone sleutel naast de paden; [TidalBeterGeheugen.laad] slaat hem over (geen kaart).
const _versieSleutel = 'versie';

class TidalBeterGeheugen {
  TidalBeterGeheugen(this._pad);
  final String _pad;
  final Map<String, ({int ms, TidalBeterUitslag uit, List<String> nee, TidalKwaliteit? hoogste})> _regels = {};

  static String _sleutel(String pad) => pad.replaceAll('\\', '/').toLowerCase();

  int get aantal => _regels.length;

  ({int ms, TidalBeterUitslag uit, List<String> nee, TidalKwaliteit? hoogste})? van(String pad) => _regels[_sleutel(pad)];

  /// Is [pad] aan de beurt op [nuMs]? Nooit bekeken: ja. Mislukt: na een dag. Anders na [kTidalBeterOpnieuwDagen].
  bool aanDeBeurt(String pad, int nuMs) {
    final r = van(pad);
    if (r == null) return true;
    final wacht = r.uit == TidalBeterUitslag.mislukt ? const Duration(days: 1) : const Duration(days: kTidalBeterOpnieuwDagen);
    return nuMs - r.ms >= wacht.inMilliseconds;
  }

  /// [hoogste]: het beste dat TIDAL van deze opname heeft ([hoogsteOpTidal]); zonder blijft wat er stond.
  void zet(String pad, TidalBeterUitslag uit, int nuMs, {String? afgewezenId, TidalKwaliteit? hoogste}) {
    final oud = van(pad);
    _regels[_sleutel(pad)] = (
      ms: nuMs,
      uit: uit,
      nee: [...?oud?.nee, if (afgewezenId != null && !(oud?.nee.contains(afgewezenId) ?? false)) afgewezenId],
      hoogste: hoogste ?? oud?.hoogste,
    );
  }

  /// Het beste dat TIDAL van de opname van [pad] heeft, zoals de ronde het laatst zag; null als hij het niet weet.
  TidalKwaliteit? hoogsteVan(String pad) => van(pad)?.hoogste;

  Future<void> laad() async {
    try {
      final f = File(_pad);
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      final oudeRegels = j[_versieSleutel] != kTidalBeterGeheugenVersie;
      for (final e in j.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final uit = TidalBeterUitslag.values.where((u) => u.name == v['uit']).firstOrNull;
        final ms = v['ms'];
        if (uit == null || ms is! num) continue;
        // "Niets beters" volgens een oudere regel: opnieuw aan de beurt (zie [kTidalBeterGeheugenVersie]).
        if (oudeRegels && uit == TidalBeterUitslag.geen) continue;
        _regels['${e.key}'] = (
          ms: ms.toInt(),
          uit: uit,
          nee: [for (final x in (v['nee'] is List ? v['nee'] as List : const [])) '$x'],
          hoogste: TidalKwaliteit.values.where((k) => k.name == v['max']).firstOrNull,
        );
      }
    } catch (_) {/* een kapot geheugen begint opnieuw: dat kost alleen zoekwerk */}
  }

  Future<void> bewaar() async {
    try {
      final tmp = File('$_pad.tmp');
      await tmp.writeAsString(jsonEncode({
        _versieSleutel: kTidalBeterGeheugenVersie,
        for (final e in _regels.entries)
          e.key: {
            'ms': e.value.ms,
            'uit': e.value.uit.name,
            if (e.value.nee.isNotEmpty) 'nee': e.value.nee,
            if (e.value.hoogste != null) 'max': e.value.hoogste!.name,
          },
      }));
      await tmp.rename(_pad);
    } catch (_) {/* volgende keer opnieuw */}
  }
}

/// Het volgende nummer voor de ronde, of null als er niets meer aan de beurt is.
///
/// Eerst wat cd-kwaliteit al beter maakt (mp3, verdachte FLAC), dan de FLAC's van 16 bit; binnen elk het nieuwst
/// binnengekomen eerst. [overslaan]: vaste keuze, spelend, in de wachtrij, door de radio gehaald.
Track? volgendeVoorTidal(
  Iterable<Track> nummers,
  TidalBeterGeheugen geheugen, {
  required int nuMs,
  required TidalMinstens Function(Track) minstens,
  required bool Function(Track) overslaan,
}) {
  Track? beste;
  var besteRang = 99;
  for (final t in nummers) {
    final m = minstens(t);
    if (m == TidalMinstens.geenWinst) continue;
    if ((t.duration?.inSeconds ?? 0) <= 0 || t.artist.trim().isEmpty || t.title.trim().isEmpty) continue;
    if (!geheugen.aanDeBeurt(t.path, nuMs) || overslaan(t)) continue;
    final rang = m == TidalMinstens.cd ? 0 : 1;
    if (beste == null || rang < besteRang || (rang == besteRang && t.addedMs > beste.addedMs)) {
      beste = t;
      besteRang = rang;
    }
  }
  return beste;
}

/// De ronde zelf. Alles wat de app weet, komt erin geschoven; zo is hij zonder TIDAL en zonder schijf te toetsen.
class TidalBeterRonde {
  TidalBeterRonde({
    required this.geheugen,
    required this.nummers,
    required this.zoek,
    required this.haal,
    required this.overslaan,
    this.inGebruik,
    this.verdacht,
    this.log,
    DateTime Function()? klok,
  }) : _klok = klok ?? DateTime.now;

  final TidalBeterGeheugen geheugen;
  final Iterable<Track> Function() nummers;

  /// De ruwe uitvoer van het zoekhulpje voor een vraag, of null als tidaler niet antwoordde.
  final Future<String?> Function(String vraag) zoek;

  /// Haal TIDAL-nummer [id] voor [t] en laat de keuring beslissen.
  final Future<TidalBeterUitslag> Function(Track t, TidalTrack kandidaat) haal;
  final bool Function(Track t) overslaan;

  /// De paden die nu spelen of in de wachtrij staan: één keer per stap opgevraagd, niet per nummer.
  final Iterable<String> Function()? inGebruik;
  final bool Function(Track t)? verdacht;
  final void Function(String regel)? log;
  final DateTime Function() _klok;

  Timer? _wekker;
  bool _bezig = false;
  bool _gestopt = false;
  DateTime? _rustTot;

  TidalMinstens _minstens(Track t) => tidalMinstens(t, verdacht: verdacht?.call(t) ?? false);

  Future<void> start() async {
    await geheugen.laad();
    _plan(kTidalBeterStart);
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
      _plan(kTidalBeterTussen);
    });
  }

  /// Op jouw vraag — de knop "Zoek hi-res" op een album, of 👍 op een radionummer: deze nummers meteen bij TIDAL
  /// nakijken, ook als de ronde ze kort geleden bekeek. Eén tegelijk, naast de ronde. Een nummer dat nu speelt
  /// ([speeltNu]) schuift achteraan en wacht tot het niet meer speelt: zijn bestand wordt vervangen. Geeft de paden
  /// terug die hij gaat nakijken (niet: 24 bit, vaste keuze, onbekende lengte).
  Set<String> nu(Iterable<Track> nummers) {
    final erbij = <String>{};
    for (final t in nummers) {
      if (_minstens(t) == TidalMinstens.geenWinst || overslaan(t) || (t.duration?.inSeconds ?? 0) <= 0) continue;
      if (_gevraagd.any((x) => x.path == t.path)) continue;
      _gevraagd.add(t);
      erbij.add(t.path);
    }
    if (erbij.isNotEmpty) unawaited(_werkGevraagdAf());
    return erbij;
  }

  /// Is [pad] het nummer dat nu speelt? Voor [nu].
  bool Function(String pad)? speeltNu;

  /// Hoe lang [nu] wacht als alles wat nog gevraagd is speelt, of als de ronde bezig is.
  Duration wachtNaSpelen = const Duration(seconds: 30);

  final List<Track> _gevraagd = [];
  bool _gevraagdBezig = false;

  Future<void> _werkGevraagdAf() async {
    if (_gevraagdBezig) return;
    _gevraagdBezig = true;
    try {
      while (_gevraagd.isNotEmpty && !_gestopt) {
        final i = _gevraagd.indexWhere((t) => !(speeltNu?.call(t.path) ?? false));
        if (i < 0 || _bezig) {
          await Future<void>.delayed(_bezig ? const Duration(seconds: 1) : wachtNaSpelen);
          continue;
        }
        final t = _gevraagd.removeAt(i);
        _bezig = true;
        try {
          await _bekijk(t);
        } catch (e) {
          log?.call('TIDAL beter "${t.artist} — ${t.title}": $e');
        } finally {
          _bezig = false;
        }
      }
    } finally {
      _gevraagdBezig = false;
    }
  }

  /// Eén nummer bekijken. Geeft terug wat er gebeurde, of null als er niets te doen was.
  Future<TidalBeterUitslag?> stap() async {
    if (_bezig) return null;
    final nu = _klok();
    if (_rustTot != null && nu.isBefore(_rustTot!)) return null;
    final bezet = {for (final p in inGebruik?.call() ?? const <String>[]) TidalBeterGeheugen._sleutel(p)};
    final t = volgendeVoorTidal(nummers(), geheugen,
        nuMs: nu.millisecondsSinceEpoch,
        minstens: _minstens,
        overslaan: (t) => bezet.contains(TidalBeterGeheugen._sleutel(t.path)) || overslaan(t));
    if (t == null) return null;
    _bezig = true;
    try {
      final uit = await _bekijk(t);
      if (uit == TidalBeterUitslag.mislukt) _rustTot = _klok().add(kTidalBeterRust);
      return uit;
    } finally {
      _bezig = false;
    }
  }

  Future<TidalBeterUitslag> _bekijk(Track t) async {
    final naam = '${t.artist} — ${t.title}';
    final m = _minstens(t);
    final nuMs = _klok().millisecondsSinceEpoch;
    final uitvoer = await zoek('${t.artist} ${zonderFeat(t.title)}');
    if (uitvoer == null) {
      log?.call('TIDAL beter "$naam": zoeken lukte niet — een uur rust');
      geheugen.zet(t.path, TidalBeterUitslag.mislukt, nuMs);
      await geheugen.bewaar();
      return TidalBeterUitslag.mislukt;
    }
    final treffers = tidalStereoNummers(uitvoer);
    final hoogste = hoogsteOpTidal(t, treffers);
    final k = beterOpTidal(t, treffers, minstens: m, nee: geheugen.van(t.path)?.nee ?? const []);
    if (k == null) {
      log?.call('TIDAL beter "$naam" (${_watErLigt(t)}): niets beters van deze opname '
          '(${treffers.length} treffers${hoogste == null ? '' : ', TIDAL heeft hem in ${hoogste == TidalKwaliteit.hires ? 'hi-res' : 'cd-kwaliteit'}'})');
      geheugen.zet(t.path, TidalBeterUitslag.geen, nuMs, hoogste: hoogste);
      await geheugen.bewaar();
      return TidalBeterUitslag.geen;
    }
    log?.call('TIDAL beter "$naam" (${_watErLigt(t)}): ${k.kwaliteit == TidalKwaliteit.hires ? "hi-res" : "cd"} op '
        'TIDAL (${k.id}, "${k.album}", ${k.seconden} s) — halen en keuren');
    final uit = await haal(t, k);
    geheugen.zet(t.path, uit, _klok().millisecondsSinceEpoch,
        afgewezenId: uit == TidalBeterUitslag.afgewezen ? k.id : null, hoogste: hoogste);
    await geheugen.bewaar();
    return uit;
  }

  static String _watErLigt(Track t) {
    final soort = soortVan(t.path).toUpperCase();
    if (!isVerliesvrij(soortVan(t.path))) return soort;
    final bits = t.bitsPerSample > 0 ? '${t.bitsPerSample}' : '?';
    final khz = t.sampleRate > 0 ? (t.sampleRate / 1000).toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',') : '?';
    return '$soort $bits/$khz';
  }
}
