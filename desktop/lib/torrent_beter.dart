// Betere kopieën uit torrents voor de hele bibliotheek, op de achtergrond en op volle snelheid.
//
// Saber, 26-10-2026: "wordt torrent nu ook ingeschakeld voor betere versie achteraf ? torrent is een mooie aanvulling
// niet gebruiken voor snel download of afspelen functie, daavoor is torrent te traag" — en daarna: "torrent mag veel
// sneller e, daar is er nie echt controle e, dus die mag vollebak gaan". Anders dan bij TIDAL (twintig per uur: TIDAL
// blokkeert een login die als een machine zoekt) en Soulseek (de server zwijgt na te veel vragen) kijkt hier niemand
// mee. De ronde gaat dus plaat na plaat, [kTorrentBeterTegelijk] tegelijk, met alleen een korte adem ertussen.
//
// Per plaat de jacht van "Zoek hi-res" (`DownloadManager.zoekBeterInTorrents`): wat TorBox al heeft eerst, dan een paar
// die hij nog moet halen, alleen losse nummers, en elk bestand door de keuring van een wens (echt, even lang, dezelfde
// opname, bewezen beter). Nooit bij het halen of bij ▶: daarvoor zijn torrents te traag. Wat de ronde per plaat vond,
// staat in `torrent_beter.json`, zodat een herstart niet opnieuw begint.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lossless_want.dart' show isVerzamelnaam;
import 'models.dart' show Track;
import 'organize.dart' show normKey;
import 'tidal_beter.dart' show TidalMinstens;

/// Pas zo lang na het opstarten de eerste plaat: na de TIDAL-ronde (5 min) en de echtheidsveger (6 min).
const Duration kTorrentBeterStart = Duration(minutes: 8);

/// Zoveel platen tegelijk. Een plaat waarvan TorBox de torrent eerst nog moet halen, kan een kwartier duren; met twee
/// gaat de ronde intussen door.
const int kTorrentBeterTegelijk = 2;

/// De adem tussen twee platen van één werker: geen plafond per uur, alleen geen vraag op vraag.
const Duration kTorrentBeterAdem = Duration(seconds: 15);

/// Niets meer aan de beurt (alles bekeken, of TorBox niet klaar): zo lang tot de volgende blik.
const Duration kTorrentBeterNiets = Duration(minutes: 10);

/// Na een storing (TorBox antwoordt niet, of zoeken lukte niet) zo lang niets.
const Duration kTorrentBeterRust = Duration(minutes: 15);

/// Een plaat zonder betere torrent komt na zoveel dagen opnieuw aan de beurt: er komen torrents bij.
const int kTorrentBeterOpnieuwDagen = 30;

/// Een plaat die "Zoek hi-res" nu al afzoekt, slaat de ronde zo lang over.
const Duration kTorrentBeterAlBezig = Duration(minutes: 30);

/// Wat de jacht voor één plaat opleverde. [bruikbaar]: torrents die het proberen waard waren. [storing]: zoeken
/// mislukte, of geen enkele torrent die TorBox al had ging open — dan ligt het aan TorBox, niet aan de plaat.
/// [alBezig]: "Zoek hi-res" zocht deze plaat al af; die jacht doet het werk.
typedef TorrentJacht = ({int vervangen, int bruikbaar, bool storing, bool alBezig});

enum TorrentBeterUitslag {
  /// Geen torrent met iets beters voor deze plaat.
  geen,

  /// Minstens één nummer staat nu beter in de bibliotheek.
  vervangen,

  /// Zoeken of TorBox lukte niet. Morgen opnieuw.
  mislukt,
}

/// De regels waarmee de oordelen in het geheugen geveld zijn; omhoog bij een regel die vaker iets vindt, dan komen
/// de platen met "geen" van vóór die regel opnieuw aan de beurt.
const int kTorrentBeterGeheugenVersie = 1;

const _versieSleutel = 'versie';

/// Eén plaat voor de ronde: de sleutel van het geheugen, de naam om op te zoeken, en de nummers die beter kunnen.
typedef TorrentPlaat = ({String sleutel, String artiest, String album, List<Track> nummers, int rang});

/// De sleutel van een plaat in het geheugen.
String torrentPlaatSleutel(String artiest, String album) => '${normKey(artiest)}|${normKey(album)}';

/// Het geheugen van de ronde, per plaat: wanneer, met welke uitslag, en hoeveel nummers er vervangen werden.
class TorrentBeterGeheugen {
  TorrentBeterGeheugen(this._pad);
  final String _pad;
  final Map<String, ({int ms, TorrentBeterUitslag uit, int n})> _regels = {};

  int get aantal => _regels.length;

  ({int ms, TorrentBeterUitslag uit, int n})? van(String sleutel) => _regels[sleutel];

  /// Is [sleutel] aan de beurt op [nuMs]? Nooit bekeken: ja. Mislukt: na een dag. Anders na
  /// [kTorrentBeterOpnieuwDagen]: ook een plaat waar iets vervangen werd, want de rest van de plaat kan nog beter.
  bool aanDeBeurt(String sleutel, int nuMs) {
    final r = van(sleutel);
    if (r == null) return true;
    final wacht =
        r.uit == TorrentBeterUitslag.mislukt ? const Duration(days: 1) : const Duration(days: kTorrentBeterOpnieuwDagen);
    return nuMs - r.ms >= wacht.inMilliseconds;
  }

  void zet(String sleutel, TorrentBeterUitslag uit, int nuMs, {int n = 0}) =>
      _regels[sleutel] = (ms: nuMs, uit: uit, n: n);

  Future<void> laad() async {
    try {
      final f = File(_pad);
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      final oudeRegels = j[_versieSleutel] != kTorrentBeterGeheugenVersie;
      for (final e in j.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final uit = TorrentBeterUitslag.values.where((u) => u.name == v['uit']).firstOrNull;
        final ms = v['ms'];
        if (uit == null || ms is! num) continue;
        if (oudeRegels && uit == TorrentBeterUitslag.geen) continue;
        _regels['${e.key}'] = (ms: ms.toInt(), uit: uit, n: v['n'] is num ? (v['n'] as num).toInt() : 0);
      }
    } catch (_) {/* een kapot geheugen begint opnieuw: dat kost alleen zoekwerk */}
  }

  Future<void> bewaar() async {
    try {
      final tmp = File('$_pad.tmp');
      await tmp.writeAsString(jsonEncode({
        _versieSleutel: kTorrentBeterGeheugenVersie,
        for (final e in _regels.entries)
          e.key: {'ms': e.value.ms, 'uit': e.value.uit.name, if (e.value.n > 0) 'n': e.value.n},
      }));
      await tmp.rename(_pad);
    } catch (_) {/* volgende keer opnieuw */}
  }
}

/// De volgende plaat voor de ronde, of null als er niets aan de beurt is.
///
/// Alleen platen met een naam en één artiest (geen verzamelaar: daar zoekt een torrent op de verkeerde naam), en
/// alleen de nummers die beter kunnen ([minstens] niet [TidalMinstens.geenWinst]) en niet overgeslagen worden
/// ([overslaan]: vaste keuze, door de radio gehaald, zelf cd of vinyl gekozen). Eerst een plaat met een mp3 of een
/// verdachte FLAC (daar wint al een cd-kopie), dan die met FLAC's van 16 bit; binnen elk de nieuwst binnengekomen.
/// [bezig]: platen die een andere werker nu doet.
TorrentPlaat? volgendePlaatVoorTorrents(
  Iterable<({String artiest, String album, List<Track> nummers})> platen,
  TorrentBeterGeheugen geheugen, {
  required int nuMs,
  required TidalMinstens Function(Track) minstens,
  required bool Function(Track) overslaan,
  Set<String> bezig = const {},
}) {
  TorrentPlaat? beste;
  var besteNieuw = 0;
  for (final p in platen) {
    final artiest = p.artiest.trim(), album = p.album.trim();
    if (artiest.isEmpty || album.isEmpty || isVerzamelnaam(artiest)) continue;
    final sleutel = torrentPlaatSleutel(artiest, album);
    if (bezig.contains(sleutel) || !geheugen.aanDeBeurt(sleutel, nuMs)) continue;
    var rang = 2, nieuw = 0;
    final nummers = <Track>[];
    for (final t in p.nummers) {
      if (t.title.trim().isEmpty || overslaan(t)) continue;
      final m = minstens(t);
      if (m == TidalMinstens.geenWinst) continue;
      nummers.add(t);
      if (m == TidalMinstens.cd) rang = 0;
      if (rang > 1) rang = 1;
      if (t.addedMs > nieuw) nieuw = t.addedMs;
    }
    if (nummers.isEmpty) continue;
    if (beste == null || rang < beste.rang || (rang == beste.rang && nieuw > besteNieuw)) {
      beste = (sleutel: sleutel, artiest: artiest, album: album, nummers: nummers, rang: rang);
      besteNieuw = nieuw;
    }
  }
  return beste;
}

/// De ronde zelf. Alles wat de app weet, komt erin geschoven; zo is hij zonder TorBox en zonder schijf te toetsen.
class TorrentBeterRonde {
  TorrentBeterRonde({
    required this.geheugen,
    required this.platen,
    required this.jaag,
    required this.minstens,
    required this.overslaan,
    this.kan,
    this.log,
    DateTime Function()? klok,
  }) : _klok = klok ?? DateTime.now;

  final TorrentBeterGeheugen geheugen;
  final Iterable<({String artiest, String album, List<Track> nummers})> Function() platen;

  /// De jacht voor één plaat ([nummers] zijn de nummers die beter kunnen).
  final Future<TorrentJacht> Function(List<Track> nummers, String album) jaag;
  final TidalMinstens Function(Track t) minstens;
  final bool Function(Track t) overslaan;

  /// Kan er nu gezocht worden (TorBox ingesteld)? Zo niet, dan slaat de ronde over zonder iets te onthouden.
  final bool Function()? kan;
  final void Function(String regel)? log;
  final DateTime Function() _klok;

  final _bezig = <String>{};
  final _alBezigTot = <String, DateTime>{};
  final _wekkers = <Timer>[];
  bool _gestopt = false;
  DateTime? _rustTot;

  /// Platen die nu afgezocht worden. Voor de toetsen.
  Set<String> get bezig => Set.unmodifiable(_bezig);

  Future<void> start() async {
    await geheugen.laad();
    for (var i = 0; i < kTorrentBeterTegelijk; i++) {
      // De tweede werker iets later: anders vragen ze in dezelfde seconde allebei de eerste plaat.
      _plan(i, kTorrentBeterStart + kTorrentBeterAdem * i);
    }
  }

  void stop() {
    _gestopt = true;
    for (final w in _wekkers) {
      w.cancel();
    }
  }

  void _plan(int werker, Duration na) {
    if (_gestopt) return;
    late final Timer w;
    w = Timer(na, () async {
      _wekkers.remove(w);
      TorrentBeterUitslag? uit;
      try {
        uit = await stap();
      } catch (e) {
        log?.call('torrents beter: $e');
      }
      _plan(werker, uit == null ? kTorrentBeterNiets : kTorrentBeterAdem);
    });
    _wekkers.add(w);
  }

  /// Eén plaat afzoeken. Geeft terug wat er gebeurde, of null als er niets te doen was (alles bekeken, rust na een
  /// storing, TorBox niet ingesteld).
  Future<TorrentBeterUitslag?> stap() async {
    final nu = _klok();
    if (_rustTot != null && nu.isBefore(_rustTot!)) return null;
    if (!(kan?.call() ?? true)) return null;
    _alBezigTot.removeWhere((_, tot) => !nu.isBefore(tot));
    final p = volgendePlaatVoorTorrents(platen(), geheugen,
        nuMs: nu.millisecondsSinceEpoch,
        minstens: minstens,
        overslaan: overslaan,
        bezig: {..._bezig, ..._alBezigTot.keys});
    if (p == null) return null;
    _bezig.add(p.sleutel);
    final naam = '"${p.artiest} — ${p.album}"';
    try {
      final TorrentJacht j;
      try {
        j = await jaag(p.nummers, p.album);
      } catch (e) {
        return await _onthoud(p, TorrentBeterUitslag.mislukt, 0, '$naam: $e — rust');
      }
      if (j.alBezig) {
        _alBezigTot[p.sleutel] = _klok().add(kTorrentBeterAlBezig);
        return TorrentBeterUitslag.geen;
      }
      if (j.vervangen > 0) {
        return await _onthoud(p, TorrentBeterUitslag.vervangen, j.vervangen,
            '$naam: ${j.vervangen} van ${p.nummers.length} nummers beter uit torrents');
      }
      if (j.storing) {
        return await _onthoud(p, TorrentBeterUitslag.mislukt, 0, '$naam: TorBox of zoeken haperde — rust');
      }
      return await _onthoud(p, TorrentBeterUitslag.geen, 0,
          '$naam: niets beters (${j.bruikbaar} torrents geprobeerd) — over $kTorrentBeterOpnieuwDagen dagen opnieuw');
    } finally {
      _bezig.remove(p.sleutel);
    }
  }

  Future<TorrentBeterUitslag> _onthoud(TorrentPlaat p, TorrentBeterUitslag uit, int n, String regel) async {
    if (uit == TorrentBeterUitslag.mislukt) _rustTot = _klok().add(kTorrentBeterRust);
    geheugen.zet(p.sleutel, uit, _klok().millisecondsSinceEpoch, n: n);
    await geheugen.bewaar();
    log?.call('torrents beter $regel');
    return uit;
  }
}
