/// De blijvende jacht op een betere kopie.
///
/// Saber, 27-10-2026: *"eigelijk mag de jacht niet stoppen, ten ware er echt 100 procent bewezen is dat die plaat of
/// nummer gewoon niet bestaat in betere kwaliteit, want zeker bij soulseek elk uur kan er iemand online zijn die de
/// betere kwaliteit heeft en dan missen we die niet ?? maar we moeten rekening houden dat we niet geblokkeerd
/// worden"*. Hij koos: na een bewijs nog één keer per maand kijken, alles wat niet bewezen het beste is, en hoogstens
/// tien Soulseek-zoekopdrachten per vijf minuten ([kJachtZoekPerVijfMinuten]).
///
/// **Wat "bewezen" hier betekent ([Jachtbewijs]).** Honderd procent kan niemand: morgen kan iemand een plaat rippen.
/// Wel zeker genoeg om het zoeken te vertragen tot één keer per maand:
///  * [Jachtbewijs.top]: echt 24 bit, met echte inhoud boven 24,5 kHz, op 88,2 kHz of meer — gemeten 27-10-2026 bij
///    455 van 1789 nummers;
///  * [Jachtbewijs.officieel]: TIDAL heeft precies deze opname alleen in cd-kwaliteit, en jouw kopie is een echte
///    verliesvrije van minstens cd-kwaliteit;
///  * [Jachtbewijs.eensgezind]: [kEensgezindKopieen] kopieën van evenveel uploaders, op minstens [kEensgezindDagen]
///    dagen binnengehaald en gemeten, en geen enkele beter dan de jouwe. Een vervalsing of een andere opname telt niet.
///
/// **Per plaat gezocht.** Eén zoekopdracht dekt alle nummers van een plaat ([volgendePlaat]); een losse single heeft er
/// één voor zich. De ronde ([BlijvendeJachtRonde]) neemt telkens één plaat die aan de beurt is.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'audioformaten.dart' show isVerliesvrij, soortVan;
import 'echtheid.dart';
import 'models.dart';
import 'tidal.dart' show TidalKwaliteit;

/// Waarom een nummer niet meer elke paar dagen gezocht hoeft te worden.
enum Jachtbewijs { geen, top, officieel, eensgezind }

/// Wat een binnengehaalde kopie bleek.
enum Kopieuitslag {
  /// Echt, dezelfde opname, maar niet bewezen beter dan wat je hebt. Telt mee voor [Jachtbewijs.eensgezind].
  gelijk,

  /// Opgeblazen, opgeschaald of uit een mp3 omgezet.
  nep,

  /// Een andere opname (live, remix), of een andere soort dan je zelf koos.
  anders,

  /// Bewezen beter: hij verving je kopie.
  beter,

  /// Als versie naast je kopie bewaard (versies.dart).
  versie,
}

/// Eén kopie die al binnen was: nooit nog eens halen. [dag] als `2026-10-27`, voor [kEensgezindDagen].
typedef Afwijzing = ({String uploader, int grootte, String dag, Kopieuitslag uit});

/// Zo vaak na jouw klik op "Zoek hi-res": een uur, drie, acht, een dag, drie dagen, een week; daarna [kJachtDaarna].
const kJachtRitmeGevraagd = [
  Duration(hours: 1),
  Duration(hours: 3),
  Duration(hours: 8),
  Duration(days: 1),
  Duration(days: 3),
  Duration(days: 7),
];

/// Zo vaak voor de rest van de bibliotheek, na de eerste ronde; daarna [kJachtDaarna].
const kJachtRitme = [Duration(days: 2), Duration(days: 4), Duration(days: 7)];

/// Daarna elke twee weken.
const kJachtDaarna = Duration(days: 14);

/// Na een bewijs nog één keer per maand (Saber: "Na bewijs maandelijks").
const kJachtNaBewijs = Duration(days: 30);

/// Zoveel echte kopieën van evenveel uploaders, geen enkele beter: [Jachtbewijs.eensgezind].
const kEensgezindKopieen = 3;

/// Op zoveel verschillende dagen binnengehaald: wie vandaag online is, deelt vaak hetzelfde bestand.
const kEensgezindDagen = 2;

/// Zoveel Soulseek-zoekopdrachten hoogstens per vijf minuten voor de blijvende jacht — de helft van wat
/// achtergrondwerk mag ([kZoekPerVijfMinuten] min [kZoekVoorJouVijf] in soulseek.dart). Saber koos "Sneller".
const kJachtZoekPerVijfMinuten = 10;

/// Om de zoveel kijkt de ronde of er een plaat aan de beurt is.
const kJachtTik = Duration(minutes: 1);

/// Pas zo lang na het opstarten de eerste ronde: eerst de rest van de app.
const kJachtStart = Duration(minutes: 7);

/// Wat de jacht van één nummer weet.
class Jachtstand {
  const Jachtstand({this.rondes = 0, this.laatsteMs = 0, this.gevraagd = false, this.nee = const []});

  /// Hoeveel keer er gezocht is (een ronde die niet kon zoeken telt niet).
  final int rondes;
  final int laatsteMs;

  /// Je klikte zelf op "Zoek hi-res": het snelle ritme ([kJachtRitmeGevraagd]).
  final bool gevraagd;

  /// Wat er al binnen was en niet beter bleek.
  final List<Afwijzing> nee;

  Jachtstand met({int? rondes, int? laatsteMs, bool? gevraagd, List<Afwijzing>? nee}) => Jachtstand(
      rondes: rondes ?? this.rondes,
      laatsteMs: laatsteMs ?? this.laatsteMs,
      gevraagd: gevraagd ?? this.gevraagd,
      nee: nee ?? this.nee);

  Map<String, dynamic> toJson() => {
        if (rondes > 0) 'r': rondes,
        if (laatsteMs > 0) 'l': laatsteMs,
        if (gevraagd) 'g': true,
        if (nee.isNotEmpty) 'nee': [for (final a in nee) {'u': a.uploader, 's': a.grootte, 'd': a.dag, 'x': a.uit.name}],
      };

  static Jachtstand fromJson(Map<String, dynamic> j) => Jachtstand(
        rondes: (j['r'] as num?)?.toInt() ?? 0,
        laatsteMs: (j['l'] as num?)?.toInt() ?? 0,
        gevraagd: j['g'] == true,
        nee: [
          for (final x in (j['nee'] is List ? j['nee'] as List : const []))
            if (x is Map)
              (
                uploader: '${x['u'] ?? ''}',
                grootte: (x['s'] as num?)?.toInt() ?? 0,
                dag: '${x['d'] ?? ''}',
                uit: Kopieuitslag.values.where((u) => u.name == x['x']).firstOrNull ?? Kopieuitslag.gelijk,
              ),
        ],
      );
}

/// Is [t] bewezen het beste dat er is? Zie [Jachtbewijs] en de uitleg bovenaan. [o]: de meting van het bestand
/// (echtheid_oordelen.dart), [tidalHoogste]: het beste dat TIDAL van precies deze opname heeft (tidal_beter.dart).
Jachtbewijs bewijsVoor(Track t, {Echtheidsoordeel? o, TidalKwaliteit? tidalHoogste, List<Afwijzing> nee = const []}) {
  final echt = o != null && !o.isNep && !o.isKapot;
  if (echt &&
      t.bitsPerSample >= 24 &&
      t.sampleRate >= 88200 &&
      o.boven == Bovenband.vol &&
      (o.gebruikteBits ?? 0) >= 24) {
    return Jachtbewijs.top;
  }
  final verliesvrij = t.isFlac || isVerliesvrij(soortVan(t.path));
  if (echt &&
      verliesvrij &&
      tidalHoogste == TidalKwaliteit.cd &&
      t.bitsPerSample >= 16 &&
      t.sampleRate >= 44100 &&
      o.band != Bandbreedte.afgekapt) {
    return Jachtbewijs.officieel;
  }
  final gelijk = [for (final a in nee) if (a.uit == Kopieuitslag.gelijk) a];
  if ({for (final a in gelijk) a.uploader.toLowerCase()}.length >= kEensgezindKopieen &&
      {for (final a in gelijk) a.grootte}.length >= kEensgezindKopieen &&
      {for (final a in gelijk) a.dag}.length >= kEensgezindDagen) {
    return Jachtbewijs.eensgezind;
  }
  return Jachtbewijs.geen;
}

/// Hoe lang na de vorige ronde de volgende komt.
Duration jachtWacht(Jachtstand s, Jachtbewijs b) {
  if (s.rondes <= 0) return Duration.zero;
  if (b != Jachtbewijs.geen) return kJachtNaBewijs + _spreiding(s.rondes);
  final ritme = s.gevraagd ? kJachtRitmeGevraagd : kJachtRitme;
  final i = s.rondes - 1;
  final w = i < ritme.length ? ritme[i] : kJachtDaarna;
  return w >= const Duration(days: 1) ? w + _spreiding(s.rondes) : w;
}

/// Bij elke ronde van een dag of langer een ander uur: wie 's avonds online is, is dat 's ochtends niet.
Duration _spreiding(int rondes) => Duration(hours: (rondes * 5) % 24);

/// Is [s] aan de beurt op [nuMs]?
bool jachtAanDeBeurt(Jachtstand? s, int nuMs, Jachtbewijs b) =>
    s == null || nuMs - s.laatsteMs >= jachtWacht(s, b).inMilliseconds;

/// `2026-10-27`.
String jachtDag(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Het geheugen van de blijvende jacht, per nummer, in `blijvende_jacht.json`.
class BlijvendeJachten {
  BlijvendeJachten(this._pad);
  final String _pad;
  final Map<String, Jachtstand> _per = {};

  static String sleutel(String pad) => pad.replaceAll('\\', '/').toLowerCase();

  int get aantal => _per.length;

  Jachtstand? van(String pad) => _per[sleutel(pad)];

  /// Je klikte op "Zoek hi-res": die zoekopdracht telt als de eerste ronde, en het snelle ritme begint.
  void vraag(Iterable<String> paden, int nuMs) {
    for (final p in paden) {
      final oud = van(p);
      _per[sleutel(p)] = (oud ?? const Jachtstand()).met(rondes: 1, laatsteMs: nuMs, gevraagd: true);
    }
  }

  /// Er is gezocht voor [pad].
  void ronde(String pad, int nuMs) {
    final oud = van(pad) ?? const Jachtstand();
    _per[sleutel(pad)] = oud.met(rondes: oud.rondes + 1, laatsteMs: nuMs);
  }

  /// Een kopie voor [pad] kwam binnen en bleek [uit]. Een betere wist niets: wat niet beter was dan je vorige kopie, is
  /// ook niet beter dan deze.
  void noteer(String pad, String uploader, int grootte, Kopieuitslag uit, DateTime nu) {
    if (uit == Kopieuitslag.beter) return;
    final oud = van(pad) ?? const Jachtstand();
    if (isAfgewezen(pad, uploader, grootte)) return;
    _per[sleutel(pad)] = oud.met(nee: [...oud.nee, (uploader: uploader, grootte: grootte, dag: jachtDag(nu), uit: uit)]);
  }

  /// Was deze kopie al binnen? Op uploader en grootte: dezelfde uploader met hetzelfde bestand.
  bool isAfgewezen(String pad, String uploader, int grootte) =>
      van(pad)?.nee.any((a) => a.grootte == grootte && a.uploader.toLowerCase() == uploader.toLowerCase()) ?? false;

  Future<void> laad() async {
    try {
      final f = File(_pad);
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      final n = j['nummers'];
      if (n is! Map) return;
      for (final e in n.entries) {
        if (e.value is Map) _per['${e.key}'] = Jachtstand.fromJson(Map<String, dynamic>.from(e.value as Map));
      }
    } catch (_) {/* een kapot geheugen begint opnieuw: dat kost alleen zoekwerk */}
  }

  Future<void> bewaar() async {
    try {
      final tmp = File('$_pad.tmp');
      await tmp.writeAsString(jsonEncode({
        'versie': 1,
        'nummers': {for (final e in _per.entries) e.key: e.value.toJson()},
      }));
      await tmp.rename(_pad);
    } catch (_) {/* volgende keer opnieuw */}
  }
}

/// Eén plaat om te zoeken: één zoekopdracht voor al [nummers]. [album] leeg: een losse single.
typedef Jachtplaat = ({String album, List<Track> nummers});

/// De sleutel van de plaat van [t]: de map, behalve bij een single of een nummer zonder album — dat staat voor zich.
String plaatsleutel(Track t) {
  final p = t.path.replaceAll('\\', '/');
  final i = p.lastIndexOf('/');
  final map = i < 0 ? '' : p.substring(0, i).toLowerCase();
  if (t.album.trim().isEmpty || map.contains('/singles/') || map.endsWith('/singles')) return 'los|${p.toLowerCase()}';
  return map;
}

/// De plaat die nu aan de beurt is, of null. Een plaat is aan de beurt als één van haar nummers het is; de nummers die
/// het niet zijn, gaan niet mee. Eerst wat je zelf vroeg, dan wat nog nooit gezocht is (het nieuwst binnengekomen eerst),
/// dan wat het langst wacht.
Jachtplaat? volgendePlaat(
  Iterable<Track> nummers,
  BlijvendeJachten jachten, {
  required int nuMs,
  required Jachtbewijs Function(Track t, Jachtstand? s) bewijs,
  required bool Function(Track t) overslaan,
}) {
  final per = <String, List<Track>>{};
  for (final t in nummers) {
    if (t.artist.trim().isEmpty || t.title.trim().isEmpty || overslaan(t)) continue;
    final s = jachten.van(t.path);
    if (!jachtAanDeBeurt(s, nuMs, bewijs(t, s))) continue;
    (per[plaatsleutel(t)] ??= []).add(t);
  }
  if (per.isEmpty) return null;
  int rang(List<Track> ts) {
    final ss = [for (final t in ts) jachten.van(t.path)];
    if (ss.any((s) => s?.gevraagd ?? false)) return 0;
    if (ss.any((s) => s == null || s.rondes == 0)) return 1;
    return 2;
  }

  int oudste(List<Track> ts) => [for (final t in ts) jachten.van(t.path)?.laatsteMs ?? 0].reduce((a, b) => a < b ? a : b);
  int nieuwste(List<Track> ts) => [for (final t in ts) t.addedMs].reduce((a, b) => a > b ? a : b);
  final lijst = per.values.toList()
    ..sort((a, b) {
      final r = rang(a).compareTo(rang(b));
      if (r != 0) return r;
      if (rang(a) == 1) return nieuwste(b).compareTo(nieuwste(a));
      return oudste(a).compareTo(oudste(b));
    });
  final kies = lijst.first;
  final los = plaatsleutel(kies.first).startsWith('los|');
  return (album: los ? '' : kies.first.album.trim(), nummers: kies);
}

/// Hoe een ronde afliep.
enum Jachtronde {
  /// Er is gezocht: de nummers schuiven op in hun ritme.
  gezocht,

  /// Soulseek gaf geen antwoord op zoekopdrachten, of was er niet: niets telt, later opnieuw.
  nietGezocht,
}

/// De ronde: om de [kJachtTik] één plaat die aan de beurt is, zolang [kan] waar is. Alles wat de app weet, komt erin
/// geschoven; zo is hij zonder Soulseek en zonder schijf te toetsen.
class BlijvendeJachtRonde {
  BlijvendeJachtRonde({
    required this.jachten,
    required this.nummers,
    required this.bewijs,
    required this.jaag,
    required this.kan,
    required this.overslaan,
    this.log,
    DateTime Function()? klok,
  }) : _klok = klok ?? DateTime.now;

  final BlijvendeJachten jachten;
  final Iterable<Track> Function() nummers;
  final Jachtbewijs Function(Track t, Jachtstand? s) bewijs;

  /// Zoek één plaat en jaag op wat beter is. Geeft terug of er gezocht kon worden.
  final Future<Jachtronde> Function(Jachtplaat plaat) jaag;

  /// Mag er nu gezocht worden: Soulseek is er, en de rij met jachten is niet vol.
  final bool Function() kan;
  final bool Function(Track t) overslaan;
  final void Function(String regel)? log;
  final DateTime Function() _klok;

  Timer? _wekker;
  bool _bezig = false;
  bool _gestopt = false;

  Future<void> start() async {
    await jachten.laad();
    _plan(kJachtStart);
  }

  void stop() {
    _gestopt = true;
    _wekker?.cancel();
  }

  void _plan(Duration na) {
    if (_gestopt) return;
    _wekker?.cancel();
    _wekker = Timer(na, () async {
      try {
        await stap();
      } catch (e) {
        log?.call('blijvende jacht: $e');
      }
      _plan(kJachtTik);
    });
  }

  /// Eén plaat. Geeft de plaat terug die gezocht werd, of null.
  Future<Jachtplaat?> stap() async {
    if (_bezig || !kan()) return null;
    final nu = _klok();
    final plaat = volgendePlaat(nummers(), jachten, nuMs: nu.millisecondsSinceEpoch, bewijs: bewijs, overslaan: overslaan);
    if (plaat == null) return null;
    _bezig = true;
    try {
      final r = await jaag(plaat);
      if (r != Jachtronde.gezocht) return null;
      final klaar = _klok().millisecondsSinceEpoch;
      for (final t in plaat.nummers) {
        jachten.ronde(t.path, klaar);
      }
      await jachten.bewaar();
      return plaat;
    } finally {
      _bezig = false;
    }
  }
}

/// De regel in het kwaliteitsblad: wat de blijvende jacht van [t] weet ([s], [b]), op [nu].
String jachtZin(Track t, Jachtstand? s, Jachtbewijs b, {required DateTime nu}) {
  final maand = 'De app kijkt nog één keer per maand.';
  switch (b) {
    case Jachtbewijs.top:
      final khz = (t.sampleRate / 1000).toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',');
      return 'Bewezen het beste: echt ${t.bitsPerSample}/$khz, met echte klank boven 24,5 kHz. $maand';
    case Jachtbewijs.officieel:
      return 'Het beste dat officieel bestaat: TIDAL heeft deze opname alleen in cd-kwaliteit, en de jouwe is een echte. '
          'De app kijkt nog één keer per maand, voor een vinyl of een nieuwe uitgave.';
    case Jachtbewijs.eensgezind:
      final gelijk = [for (final a in s?.nee ?? const <Afwijzing>[]) if (a.uit == Kopieuitslag.gelijk) a];
      final uploaders = {for (final a in gelijk) a.uploader.toLowerCase()}.length;
      final dagen = {for (final a in gelijk) a.dag}.length;
      return '${gelijk.length} andere echte kopieën van $uploaders uploaders, op $dagen dagen — geen enkele beter. $maand';
    case Jachtbewijs.geen:
      if (s == null || s.rondes == 0) return 'Nog niet gezocht: dit nummer komt vanzelf aan de beurt.';
      final volgende = DateTime.fromMillisecondsSinceEpoch(s.laatsteMs).add(jachtWacht(s, b));
      final binnen = s.nee.length;
      return 'Zoekt verder naar een betere kopie: ${s.rondes} keer gezocht'
          '${binnen == 0 ? '' : ', $binnen ${binnen == 1 ? 'kopie' : 'kopieën'} binnengehaald en niet beter'}. '
          'Volgende keer ${_wanneer(volgende, nu)}.';
  }
}

String _wanneer(DateTime d, DateTime nu) {
  String uur(DateTime x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
  if (!d.isAfter(nu)) return 'zo meteen';
  final vandaag = DateTime(nu.year, nu.month, nu.day);
  final dag = DateTime(d.year, d.month, d.day);
  final verschil = dag.difference(vandaag).inDays;
  if (verschil == 0) return 'vandaag om ${uur(d)}';
  if (verschil == 1) return 'morgen om ${uur(d)}';
  return 'op ${d.day}-${d.month} om ${uur(d)}';
}
