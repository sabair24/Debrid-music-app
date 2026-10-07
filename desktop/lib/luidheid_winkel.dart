/// Gelijk volume — waar de metingen staan, wat er naar de toestellen gaat, en wat er per nummer
/// gespeeld wordt.
///
/// Drie bronnen, één beslissing ([bijstellingVoorNummer]):
///  * **de pc** meet zelf (luidheid_veger.dart) en bewaart het in `luidheid.json`;
///  * **een toestel** krijgt de metingen van de pc in de catalogus (TrackDto `luid`), alleen in het
///    geheugen, en de status van de pc (doet hij mee, is hij klaar);
///  * **de Shield** krijgt ze per adres van de zender, bij elke /play.
///
/// **De sleutel heeft bewust geen pad**: `grootte|mtime` — precies wat de scan al weet (Track.sizeBytes,
/// Track.addedMs), dus opzoeken kost geen schijf. Verplaatsen houdt de mtime (rename, en de
/// kopie-terugval op Windows), tags schrijven geeft een nieuwe sleutel (en dan neemt de veger de
/// meting over als de audio aantoonbaar dezelfde is). En een ánder bestand op hetzelfde pad — een
/// vervanger, een remaster — erft nooit een meting: een oude "zacht"-meting op een luide master zou
/// ophogen tot boven vol bereik.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'flac_tags.dart' show FlacKern;
import 'luidheid.dart';
import 'models.dart';
import 'organize.dart' show RelKind, classifyRelease;
import 'paths.dart';

/// De sleutel van een nummer, of null als de scan geen grootte of tijd kent.
String? luidheidSleutel(Track t) =>
    (t.sizeBytes <= 0 || t.addedMs <= 0) ? null : '${t.sizeBytes}|${t.addedMs}';

/// Wat er van één bestand bekend is.
class _Record {
  final String pad;
  final Luidheidsmeting? meting;
  final int? kanalen; // > 2 = meerkanaals
  final String? fout; // definitief mislukt
  final int timeouts;
  final FlacKern? erf; // alleen bij een bewezen volledige meting

  const _Record({required this.pad, this.meting, this.kanalen, this.fout, this.timeouts = 0, this.erf});

  bool get definitief => meting != null || kanalen != null || fout != null;

  Map<String, dynamic> toJson() => {
        'p': pad,
        if (meting != null) ...meting!.toJson(),
        if (kanalen != null) 'mk': kanalen,
        if (fout != null) 'f': fout,
        if (timeouts > 0) 't': timeouts,
        if (erf != null)
          'e': {
            'md5': erf!.md5,
            'n': erf!.monsters,
            'sr': erf!.frequentie,
            'ch': erf!.kanalen,
            'b': erf!.diepte,
            'a': erf!.audioBytes,
          },
      };

  static _Record? fromJson(Object? j) {
    if (j is! Map) return null;
    final pad = j['p'];
    if (pad is! String) return null;
    FlacKern? erf;
    final e = j['e'];
    if (e is Map &&
        e['md5'] is String &&
        e['n'] is int &&
        e['sr'] is int &&
        e['ch'] is int &&
        e['b'] is int &&
        e['a'] is int) {
      erf = (
        md5: e['md5'] as String,
        monsters: e['n'] as int,
        frequentie: e['sr'] as int,
        kanalen: e['ch'] as int,
        diepte: e['b'] as int,
        audioBytes: e['a'] as int,
      );
    }
    final mk = j['mk'];
    final f = j['f'];
    final t = j['t'];
    return _Record(
      pad: pad,
      meting: Luidheidsmeting.fromJson(j),
      kanalen: mk is int ? mk : null,
      fout: f is String ? f : null,
      timeouts: t is int ? t : 0,
      erf: erf,
    );
  }
}

/// Wat een toestel weet over de pc: doet hij mee, en hoe ver is hij.
class LuidheidStatus {
  final bool klaar;
  final bool ffmpeg;
  final int gemeten;
  final int mislukt;
  final int totaal;
  final List<String> misluktTitels;

  const LuidheidStatus({
    required this.klaar,
    required this.ffmpeg,
    required this.gemeten,
    required this.mislukt,
    required this.totaal,
    this.misluktTitels = const [],
  });

  Map<String, dynamic> toJson() => {
        'v': 1,
        'klaar': klaar,
        'ffmpeg': ffmpeg,
        'gemeten': gemeten,
        'mislukt': mislukt,
        'totaal': totaal,
        if (misluktTitels.isNotEmpty) 'misluktTitels': misluktTitels,
      };

  static LuidheidStatus? fromJson(Object? j) {
    if (j is! Map) return null;
    int getal(String k) => (j[k] is int) ? j[k] as int : 0;
    final titels = j['misluktTitels'];
    return LuidheidStatus(
      klaar: j['klaar'] == true,
      ffmpeg: j['ffmpeg'] != false,
      gemeten: getal('gemeten'),
      mislukt: getal('mislukt'),
      totaal: getal('totaal'),
      misluktTitels: titels is List ? [for (final t in titels) if (t is String) t] : const [],
    );
  }

  /// Voor de vingerafdruk van de catalogus.
  String get vingerafdruk => '${klaar ? 1 : 0}|${ffmpeg ? 1 : 0}|$gemeten|$mislukt|$totaal|${misluktTitels.join('/')}';
}

// ── De pc ────────────────────────────────────────────────────────────────────────────────────────

final Map<String, _Record> _pc = {};
bool _klaar = false;
bool _geladen = false;

/// Is deze app de eigenaar van de muziek (de pc)? Gezet door [laadLuidheid].
bool luidheidEigenaar = false;

/// Laatste fout bij laden of bewaren, voor de log.
String? luidheidFout;

const int _plafond = 20000;

File get _bestand => appFile('luidheid.json');

/// Op de pc, bij het opstarten.
Future<void> laadLuidheid() async {
  luidheidEigenaar = true;
  _geladen = true;
  try {
    final f = _bestand;
    if (!await f.exists()) return;
    final raw = jsonDecode(await f.readAsString());
    if (raw is! Map) return;
    _klaar = raw['klaar'] == true;
    final m = raw['m'];
    if (m is! Map) return;
    _pc.clear();
    for (final e in m.entries) {
      final r = _Record.fromJson(e.value);
      if (r != null) _pc[e.key.toString()] = r;
    }
    if (_klaar) _publiceerUitBestand();
  } catch (e) {
    luidheidFout = 'luidheid.json onleesbaar: $e';
  }
}

/// Na een herstart van een pc die al klaar was: meteen de bewaarde metingen naar buiten, nog vóór de
/// bibliotheek geladen is en de veger start. Anders kregen de toestellen tot dan een catalogus zonder
/// metingen — dat wist hun kopie, ze speelden even alles op 0 dB, en de ETag sprong twee keer (twee
/// volledige downloads per toestel). De kaart is per sleutel en heeft de bibliotheek niet nodig; de
/// tellingen zijn die van het bestand en worden bij de eerste publicatie van de veger precies.
void _publiceerUitBestand() {
  var gemeten = 0, mislukt = 0;
  final kaart = <String, Map<String, dynamic>>{};
  for (final e in _pc.entries) {
    final r = e.value;
    if (!r.definitief) continue;
    if (r.meting != null) {
      kaart[e.key] = r.meting!.toJson();
      gemeten++;
    } else if (r.kanalen != null) {
      kaart[e.key] = {'mk': r.kanalen};
      gemeten++;
    } else if (r.fout != null) {
      kaart[e.key] = {'f': 1};
      mislukt++;
    }
  }
  _gepubliceerd = kaart;
  _status = LuidheidStatus(klaar: true, ffmpeg: true, gemeten: gemeten, mislukt: mislukt, totaal: gemeten + mislukt);
  luidheidUitgave.value++;
}

Future<void> bewaarLuidheid() async {
  if (!_geladen) return;
  try {
    final f = _bestand;
    await f.parent.create(recursive: true);
    final inhoud = jsonEncode({
      'v': 1,
      'klaar': _klaar,
      'm': {for (final e in _pc.entries) e.key: e.value.toJson()},
    });
    final tmp = File('${f.path}.tmp');
    try {
      await tmp.writeAsString(inhoud);
      await tmp.rename(f.path);
    } catch (_) {
      // Tweede kans langs de weg die het aantoonbaar wél doet; zie echtheid_oordelen.dart.
      await f.writeAsString(inhoud);
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  } catch (e) {
    luidheidFout = 'luidheid.json niet bewaard: $e';
  }
}

bool get luidheidKlaar => _klaar;

/// De eerste ronde is één keer helemaal doorgelopen. Blijft daarna waar.
void zetLuidheidKlaar() => _klaar = true;

/// Is dit bestand al definitief bekend (gemeten, meerkanaals of definitief mislukt)?
bool luidheidBekend(String sleutel) => _pc[sleutel]?.definitief ?? false;

/// Hoe vaak de meting van dit bestand al uit de tijd liep.
int luidheidTimeouts(String sleutel) => _pc[sleutel]?.timeouts ?? 0;

void _zet(String sleutel, _Record r) {
  _pc.remove(sleutel);
  _pc[sleutel] = r;
  while (_pc.length > _plafond) {
    _pc.remove(_pc.keys.first);
  }
}

/// Een uitslag vastleggen. [erfbaar] alleen als bewezen is dat de meting de volledige, correct
/// gedecodeerde audio betrof (gedecodeerde MD5 = kop-MD5 ≠ 0).
void onthoudLuidheid(String sleutel,
    {required String pad, required Luidheidsuitslag uitslag, FlacKern? erfbaar}) {
  _zet(
      sleutel,
      switch (uitslag) {
        Gemeten(:final meting) => _Record(pad: pad, meting: meting, erf: erfbaar),
        Meerkanaals(:final kanalen) => _Record(pad: pad, kanalen: kanalen, erf: erfbaar),
        Mislukt(:final reden) => _Record(pad: pad, fout: reden),
      });
}

/// Een meting liep uit de tijd: de eerste keer alleen deze sessie overslaan, de tweede keer
/// definitief mislukt. Geeft het aantal keer terug.
int onthoudLuidheidTimeout(String sleutel, {required String pad}) {
  final n = luidheidTimeouts(sleutel) + 1;
  _zet(sleutel, n >= 2 ? _Record(pad: pad, fout: 'te lang', timeouts: n) : _Record(pad: pad, timeouts: n));
  return n;
}

/// Een eerdere, bewezen volledige meting van precies dezelfde audio, of null.
({String sleutel, Luidheidsuitslag uitslag})? erfbareLuidheid(FlacKern kern) {
  if (kern.md5 == '00000000000000000000000000000000' || kern.md5.isEmpty) return null;
  for (final e in _pc.entries) {
    final erf = e.value.erf;
    if (erf == null) continue;
    if (erf.md5 == kern.md5 &&
        erf.monsters == kern.monsters &&
        erf.frequentie == kern.frequentie &&
        erf.kanalen == kern.kanalen &&
        erf.diepte == kern.diepte &&
        erf.audioBytes == kern.audioBytes) {
      final r = e.value;
      final Luidheidsuitslag u = r.meting != null
          ? Gemeten(r.meting!)
          : (r.kanalen != null ? Meerkanaals(r.kanalen!) : const Mislukt(''));
      if (u is Mislukt) continue;
      return (sleutel: e.key, uitslag: u);
    }
  }
  return null;
}

/// Was er op dit pad eerder een meting (een ander bestand, of hetzelfde vóór een bewerking)?
bool eerderGemetenOpPad(String pad) {
  final k = padSleutel(pad);
  for (final r in _pc.values) {
    if (r.definitief && padSleutel(r.pad) == k) return true;
  }
  return false;
}

/// Wat de pc over [nummers] weet: voor de status in de catalogus en de instelling.
({int gemeten, int mislukt, int totaal, List<String> misluktTitels}) luidheidTelling(
    Iterable<Track> nummers) {
  var gemeten = 0, mislukt = 0, totaal = 0;
  final titels = <String>[];
  for (final t in nummers) {
    totaal++;
    final k = luidheidSleutel(t);
    final r = k == null ? null : _pc[k];
    if (r == null || !r.definitief) continue;
    if (r.fout != null) {
      mislukt++;
      if (titels.length < 3) titels.add(t.title);
    } else {
      gemeten++;
    }
  }
  return (gemeten: gemeten, mislukt: mislukt, totaal: totaal, misluktTitels: titels);
}

// ── Wat er gepubliceerd is ───────────────────────────────────────────────────────────────────────

Map<String, Map<String, dynamic>> _gepubliceerd = {};
LuidheidStatus? _status;

/// Gaat één omhoog als er iets anders gepubliceerd is. De catalogus luistert hiernaar.
final ValueNotifier<int> luidheidUitgave = ValueNotifier<int>(0);

/// De status van deze pc zoals die in de catalogus staat, of null als dit geen eigenaar is (of als
/// [laadLuidheid] nog niet gedraaid heeft — dan houden bestaande catalogustoetsen hun ETag).
LuidheidStatus? get gepubliceerdeStatus => _status ??
    // Vóór de eerste publicatie (de veger start ~na het opstarten): "de pc begint zo met meten".
    // Bewust niet `klaar` uit het bestand: dan zou een toestel "klaar" zien zonder kaart.
    (luidheidEigenaar
        ? const LuidheidStatus(klaar: false, ffmpeg: true, gemeten: 0, mislukt: 0, totaal: 0)
        : null);

/// Zet een nieuwe stand naar buiten. [kaartOok] false = alleen de status (voortgang tijdens de eerste
/// ronde of een grote herronde).
void publiceerLuidheid({
  required Iterable<Track> nummers,
  required bool ffmpeg,
  required bool kaartOok,
}) {
  if (!luidheidEigenaar) return;
  final lijst = nummers.toList();
  final telling = luidheidTelling(lijst);
  final status = LuidheidStatus(
    klaar: _klaar,
    ffmpeg: ffmpeg,
    gemeten: telling.gemeten,
    mislukt: telling.mislukt,
    totaal: telling.totaal,
    misluktTitels: telling.misluktTitels,
  );
  var veranderd = _status?.vingerafdruk != status.vingerafdruk;
  _status = status;
  if (kaartOok && _klaar) {
    final padIndex = <String>{
      for (final r in _pc.values)
        if (r.definitief) padSleutel(r.pad)
    };
    final kaart = <String, Map<String, dynamic>>{};
    for (final t in lijst) {
      final k = luidheidSleutel(t);
      if (k == null) continue;
      final r = _pc[k];
      if (r != null && r.meting != null) {
        kaart[k] = r.meting!.toJson();
      } else if (r != null && r.kanalen != null) {
        kaart[k] = {'mk': r.kanalen};
      } else if (r != null && r.fout != null) {
        kaart[k] = {'f': 1};
      } else if (padIndex.contains(padSleutel(t.path))) {
        kaart[k] = {'her': 1};
      }
    }
    if (!mapEquals(_vlak(kaart), _vlak(_gepubliceerd))) {
      _gepubliceerd = kaart;
      veranderd = true;
    }
  }
  if (veranderd) luidheidUitgave.value++;
}

Map<String, String> _vlak(Map<String, Map<String, dynamic>> m) =>
    {for (final e in m.entries) e.key: jsonEncode(e.value)};

/// Het `luid`-veld van dit nummer in de catalogus, of null.
Map<String, dynamic>? gepubliceerdeLuidheid(Track t) {
  final k = luidheidSleutel(t);
  return k == null ? null : _gepubliceerd[k];
}

// ── Op een toestel ───────────────────────────────────────────────────────────────────────────────

final Map<String, Map<String, dynamic>> _vanPc = {};

/// Wat de pc in zijn catalogus over zichzelf zei. Null = geen status: een oudere pc, of nog geen
/// catalogus.
LuidheidStatus? statusVanPc;

/// Uit `_trackFromDto`: wat de pc over dit nummer zei.
void onthoudLuidheidVanPc({required int sizeBytes, required int addedMs, required Object? luid}) {
  if (sizeBytes <= 0 || addedMs <= 0) return;
  final k = '$sizeBytes|$addedMs';
  if (luid is Map) {
    _vanPc[k] = Map<String, dynamic>.from(luid);
  } else {
    _vanPc.remove(k);
  }
}

/// Uit `_adoptCatalog`: ALTIJD zetten, ook op null, zodat een oudere pc of opnieuw koppelen hem wist.
void zetLuidheidStatusVanPc(Object? status) => statusVanPc = LuidheidStatus.fromJson(status);

// ── Van een zender (de Shield) ───────────────────────────────────────────────────────────────────

final Map<String, Map<String, dynamic>> _vanZender = {};

/// De opgave per adres uit een /play; elke /play vervangt de vorige.
void onthoudLuidheidVanZender(Map<String, Map<String, dynamic>?> perAdres) {
  _vanZender.clear();
  for (final e in perAdres.entries) {
    final v = e.value;
    if (v != null) _vanZender[adresSleutel(e.key, kleineLetters: padenZijnHoofdletterOngevoelig)] = v;
  }
}

Map<String, dynamic>? _zenderopgave(String adres) =>
    _vanZender[adresSleutel(adres, kleineLetters: padenZijnHoofdletterOngevoelig)];

/// De opgave die de pc voor één adres naar de Shield stuurt: de eigen meting, en — als de plaat
/// als geheel speelt — de albumwaarde. Null als er niets te sturen is.
Map<String, dynamic>? zenderopgaveVoor(Track t, {required Bijstelling b, Luidheidsmeting? album}) {
  final eigen = _opgaveVoor(t);
  if (eigen == null) return null;
  if (eigen.kanalen != null) return {'mk': eigen.kanalen};
  if (eigen.mislukt) return {'f': 1};
  final m = eigen.meting;
  if (m == null) return null;
  return {
    ...m.toJson(),
    if (b.alsAlbum && album != null) ...{'alb': true, 'ai': album.toJson()['i'], 'atp': album.toJson()['tp']},
  };
}

// ── De beslissing ────────────────────────────────────────────────────────────────────────────────

/// Wat er over één nummer bekend is, ongeacht van wie.
class _Opgave {
  final Luidheidsmeting? meting;
  final int? kanalen;
  final bool mislukt;
  final bool netBewerkt;
  const _Opgave({this.meting, this.kanalen, this.mislukt = false, this.netBewerkt = false});

  bool get definitief => meting != null || kanalen != null || mislukt;

  static _Opgave? uitJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final mk = j['mk'];
    if (mk is int) return _Opgave(kanalen: mk);
    if (j['f'] != null) return const _Opgave(mislukt: true);
    final m = Luidheidsmeting.fromJson(j);
    if (m != null) return _Opgave(meting: m);
    if (j['her'] != null) return const _Opgave(netBewerkt: true);
    return null;
  }
}

/// Is de bron klaar om bij te stellen? Op de pc na de eerste ronde; op een toestel als de pc dat zegt.
bool get _bronKlaar => luidheidEigenaar ? _klaar : (statusVanPc?.klaar ?? false);

_Opgave? _opgaveVoor(Track t) {
  final k = luidheidSleutel(t);
  if (k == null) return null;
  if (luidheidEigenaar) {
    final r = _pc[k];
    if (r == null) return null;
    if (r.kanalen != null) return _Opgave(kanalen: r.kanalen);
    if (r.fout != null) return const _Opgave(mislukt: true);
    if (r.meting != null) return _Opgave(meting: r.meting);
    return null;
  }
  return _Opgave.uitJson(_vanPc[k]);
}

bool _isAdres(String p) {
  final l = p.toLowerCase();
  return l.startsWith('http://') || l.startsWith('https://');
}

/// De versterking voor [t], op plek [plek] in [rij].
///
/// [opVolgorde] is "niet geschud en geen radio". [albumVan] en [isVerzamelaar] komen uit de
/// bibliotheek; [bibliotheek] alleen voor de botsingsregel (twee paden met dezelfde sleutel: alleen
/// verlagen, nooit ophogen).
Bijstelling bijstellingVoorNummer(
  Track t, {
  required List<Track> rij,
  required int plek,
  required bool opVolgorde,
  required Luidheidsstand stand,
  required bool albumGeheel,
  required Album? Function(String pad) albumVan,
  Iterable<Track> Function()? bibliotheek,
}) {
  // Een nummer van een zender (de Shield): de zender heeft gemeten en beslist over de plaat, en ZIJN
  // stand gaat voor — ook boven Uit op dit toestel (zo stond het in het plan; het merk en het blad
  // zeggen het, en het blad toont hier geen keuzes die niets zouden doen). Eerst, want zo'n nummer is
  // een kaal adres zonder grootte of tijd.
  final z = _isAdres(t.path) ? _zenderopgave(t.path) : null;
  if (z != null) {
    final zs = z['stand'];
    final s = zs is String ? luidheidsstandUit(zs) : stand;
    if (s == Luidheidsstand.uit) return Bijstelling.nul;
    final doel = doelVoor(s);
    final o = _Opgave.uitJson(z);
    if (o == null) return Bijstelling(0, Bijstelbron.ongemeten, doel: doel, vanZender: true);
    if (o.kanalen != null) return Bijstelling(0, Bijstelbron.meerkanaals, doel: doel, vanZender: true);
    if (o.mislukt || o.meting == null) return Bijstelling(0, Bijstelbron.mislukt, doel: doel, vanZender: true);
    final albumMeting = Luidheidsmeting.fromJson({'i': z['ai'], 'tp': z['atp']});
    if (z['alb'] == true && albumMeting != null) {
      final g = albumVersterking(albumMeting, doel);
      final p = perNummerInAlbum(g, o.meting);
      return Bijstelling(p.db, p.bron,
          doel: doel, meting: o.meting, alsAlbum: true, albumDb: g, albumMeting: albumMeting, vanZender: true);
    }
    final v = versterking(o.meting!, doel);
    return Bijstelling(v.db, v.bron, doel: doel, meting: o.meting, vanZender: true);
  }

  if (stand == Luidheidsstand.uit) return Bijstelling.nul;
  final doel = doelVoor(stand);

  // Zonder grootte en tijd is het geen nummer uit de bibliotheek: een online radioadres, of een kaal
  // adres van een zender die niets meestuurde. Let op: op een TOESTEL is het pad van elk
  // bibliotheeknummer een stream-adres van de pc (library.dart `_trackFromDto`) — dat is dus geen
  // reden voor "online"; de sleutel beslist.
  if (luidheidSleutel(t) == null) {
    return Bijstelling(0, _isAdres(t.path) ? Bijstelbron.online : Bijstelbron.ongemeten, doel: doel);
  }
  if (!_bronKlaar) {
    // Drie redenen, drie zinnen: "pc meet nog" bij een pc die nooit gaat meten is een belofte die
    // niet uitkomt — een telefoon die eerst bijgewerkt werd zou dat dagen tonen.
    final s = luidheidEigenaar ? _status : statusVanPc;
    final bron = (!luidheidEigenaar && s == null)
        ? Bijstelbron.pcOud
        : ((s != null && !s.ffmpeg) ? Bijstelbron.pcZonderFfmpeg : Bijstelbron.pcNietKlaar);
    return Bijstelling(0, bron, doel: doel);
  }
  final eigen = _opgaveVoor(t);
  if (eigen == null || !eigen.definitief) {
    return Bijstelling(0, Bijstelbron.ongemeten,
        doel: doel, netBewerkt: (eigen?.netBewerkt ?? false) || (luidheidEigenaar && eerderGemetenOpPad(t.path)));
  }
  if (eigen.kanalen != null) return Bijstelling(0, Bijstelbron.meerkanaals, doel: doel);
  if (eigen.mislukt) return Bijstelling(0, Bijstelbron.mislukt, doel: doel);
  final meting = eigen.meting!;

  Bijstelling uitkomst;
  final album = albumVan(t.path);
  final alsAlbum = album != null && _speeltAlsAlbum(album, rij, plek, opVolgorde, albumGeheel);
  final am = alsAlbum ? _albumMetingVan(album) : null;
  if (am != null) {
    final g = albumVersterking(am, doel);
    final p = perNummerInAlbum(g, meting);
    uitkomst = Bijstelling(p.db, p.bron, doel: doel, meting: meting, alsAlbum: true, albumDb: g, albumMeting: am);
  } else {
    final v = versterking(meting, doel);
    uitkomst = Bijstelling(v.db, v.bron,
        doel: doel,
        meting: meting,
        // Voor het blad: waarom een plaat op volgorde tóch per nummer gaat.
        verzamelaar: album != null && albumGeheel && opVolgorde && _isVerzamelaar(album));
  }

  if (uitkomst.db > 0 && bibliotheek != null) {
    final k = luidheidSleutel(t);
    var zelfde = 0;
    for (final x in bibliotheek()) {
      if (luidheidSleutel(x) == k && ++zelfde > 1) {
        return uitkomst.metBron(Bijstelbron.klemNul, db: 0);
      }
    }
  }
  return uitkomst;
}

bool _isVerzamelaar(Album album) =>
    classifyRelease(album: album.title, artist: album.artist, trackCount: album.tracks.length) ==
    RelKind.compilation;

bool _speeltAlsAlbum(Album album, List<Track> rij, int plek, bool opVolgorde, bool albumGeheel) {
  if (!albumGeheel || !opVolgorde || album.isSingle) return false;
  final verzamel = _isVerzamelaar(album);
  if (verzamel) return false;
  final plekVan = <String, int>{
    for (var i = 0; i < album.tracks.length; i++) padSleutel(album.tracks[i].path): i
  };
  final plekken = [for (final x in rij) plekVan[padSleutel(x.path)]];
  return speeltAlsAlbum(
    albumGeheel: albumGeheel,
    opVolgorde: opVolgorde,
    isSingle: album.isSingle,
    isVerzamelaar: verzamel,
    reeks: aaneengeslotenReeks(plekken, plek),
    plaatLengte: album.tracks.length,
  );
}

Luidheidsmeting? _albumMetingVan(Album album) => albumMeting([
      for (final x in album.tracks)
        () {
          final o = _opgaveVoor(x);
          return (meting: o?.meting, definitief: o?.definitief ?? false, duur: x.duration);
        }(),
    ]);

/// De albummeting van de plaat waar [t] op staat, of null (voor de Shield-opgave en het blad).
Luidheidsmeting? albumMetingVoor(Album? album) => album == null ? null : _albumMetingVan(album);

// ── Voor toetsen ─────────────────────────────────────────────────────────────────────────────────

@visibleForTesting
void resetLuidheidVoorTest() {
  _pc.clear();
  _klaar = false;
  _geladen = false;
  luidheidEigenaar = false;
  _gepubliceerd = {};
  _status = null;
  _vanPc.clear();
  statusVanPc = null;
  _vanZender.clear();
}

@visibleForTesting
void zetLuidheidVoorTest(Track t, Luidheidsuitslag u, {bool klaar = true}) {
  luidheidEigenaar = true;
  _geladen = true;
  _klaar = klaar;
  final k = luidheidSleutel(t);
  if (k != null) onthoudLuidheid(k, pad: t.path, uitslag: u);
}
