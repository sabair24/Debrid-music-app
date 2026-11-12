/// Welke platen van een artiest op vinyl bestaan, volgens Discogs.
///
/// Saber, 12-11-2026, bij Spice Girls: *"ik wil bij de discographie van de artisten een volledige nieuwe sectie, Vinyl
/// en Lp … dan weet ik ook of er uberhaut Lp of vinyl bestaat van de artist. dat moet dan ook helpen bij het zoeken
/// … als die artist er zeker geen heeft dan hoeft de app niet te zoeken"*.
///
/// **Waar het vandaan komt.** Eén zoekopdracht bij Discogs op het nummer van de artiest (`artist_id`, dus geen
/// naamgenoten: op naam kwam bij "Celeste" ook een Franse metalband mee) en `format=Vinyl`, honderd persingen per
/// pagina. Gemeten 12-11-2026: Spice Girls 111 persingen in twee pagina's, Milow 11 in één, Michael Jackson 3644 in 37.
/// MusicBrainz kent veel minder vinyl (17 bij Spice Girls) — Discogs is hier de bron. Per NUMMER weten of het op vinyl
/// bestaat kost een tracklijst per plaat (`/masters/{id}`); die haalt de app pas als een vinylzoektocht het vraagt, en
/// dan plaat voor plaat tot het nummer gevonden is ([VinylBestaan.bestaatMetNummers]) — een bezoek aan de
/// artiestpagina kost zo alleen de persingen.
///
/// **Zijn keuzes** (zie het geheugen, vinyl-sectie-keuzes-12-11):
///  * bootlegs ("Unofficial Release") tellen nergens mee;
///  * promo's toont de sectie niet, maar ze tellen wel om te zoeken — van een promo-12" gaat best een rip rond;
///  * LP's en vinylsingles (7"/12"/10") apart, op jaar;
///  * elke week opnieuw kijken ([kVinylVers]): er komen heruitgaves bij (Forever van Spice Girls in 2020 op LP);
///  * weet Discogs het niet (geen sleutel, geen antwoord, geen artiest), dan is het antwoord null en zoekt de app
///    zoals vroeger: geen antwoord is geen nee.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'organize.dart' show normKey;
import 'paths.dart';
import 'vinyl.dart' show isVinylRip;

/// Zo lang geldt wat Discogs zei; daarna kijkt de app bij het volgende bezoek of de volgende vinylzoektocht opnieuw.
const Duration kVinylVers = Duration(days: 7);

/// Hoogstens zoveel pagina's van honderd persingen: Michael Jackson past erin (37). Wie meer heeft (The Beatles, Elvis),
/// krijgt een onvolledige lijst ([VinylKennis.volledig]), en daaruit volgt nooit een nee. Elke pagina is een vraag uit
/// een budget van zestig per minuut, en dat één keer per week.
const int kVinylPaginas = 40;

/// Zoveel uitgaven moet een Discogs-pagina zonder vinyl hebben voor de app "geen vinyl" gelooft: anders is het een lege
/// of bijna lege pagina (een alias, een dubbele invoer), en zegt dat niets.
const int kVinylEchtePagina = 5;

/// LP of single (7", 12", 10", EP, maxi).
enum VinylVorm { lp, single }

/// Eén plaat die op vinyl verscheen, met al zijn persingen samen.
@immutable
class VinylPlaat {
  const VinylPlaat({
    this.master,
    this.release,
    required this.titel,
    required this.vorm,
    this.formaten = const {},
    this.persingen = 0,
    this.promos = 0,
    this.jaarVan,
    this.jaarTot,
    this.hoes,
    this.nummers,
  });

  /// De Discogs-master, of null voor een losse persing zonder master ([release]).
  final int? master;
  final int? release;
  final String titel;
  final VinylVorm vorm;

  /// "LP", "7\"", "12\"", "10\"" — wat er op de persingen staat.
  final Set<String> formaten;

  /// Gewone, officiële persingen — wat de sectie telt. Zonder promo's en bootlegs.
  final int persingen;

  /// Promopersingen: niet getoond, wel genoeg om vinyl te zoeken.
  final int promos;

  final int? jaarVan, jaarTot;
  final String? hoes;

  /// De nummers op de plaat. Null: nog niet opgehaald (of Discogs gaf hem niet) — dan weet de app voor die plaat
  /// niet welke nummers erop staan, en zegt [VinylKennis.bestaat] geen nee.
  final List<String>? nummers;

  /// In de sectie: alleen wat als gewone persing bestaat.
  bool get getoond => persingen > 0;

  VinylPlaat metNummers(List<String>? n) => VinylPlaat(
      master: master,
      release: release,
      titel: titel,
      vorm: vorm,
      formaten: formaten,
      persingen: persingen,
      promos: promos,
      jaarVan: jaarVan,
      jaarTot: jaarTot,
      hoes: hoes,
      nummers: n);

  Map<String, dynamic> toJson() => {
        if (master != null) 'm': master,
        if (release != null) 'r': release,
        't': titel,
        'v': vorm.name,
        'f': formaten.toList(),
        'p': persingen,
        if (promos > 0) 'pr': promos,
        if (jaarVan != null) 'j1': jaarVan,
        if (jaarTot != null) 'j2': jaarTot,
        if (hoes != null) 'h': hoes,
        if (nummers != null) 'n': nummers,
      };

  static VinylPlaat? uitJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'];
    if (t is! String || t.isEmpty) return null;
    final n = j['n'];
    return VinylPlaat(
      master: j['m'] is int ? j['m'] as int : null,
      release: j['r'] is int ? j['r'] as int : null,
      titel: t,
      vorm: j['v'] == 'lp' ? VinylVorm.lp : VinylVorm.single,
      formaten: {for (final f in (j['f'] as List? ?? const [])) '$f'},
      persingen: j['p'] is int ? j['p'] as int : 0,
      promos: j['pr'] is int ? j['pr'] as int : 0,
      jaarVan: j['j1'] is int ? j['j1'] as int : null,
      jaarTot: j['j2'] is int ? j['j2'] as int : null,
      hoes: j['h'] is String ? j['h'] as String : null,
      nummers: n is List ? [for (final x in n) '$x'] : null,
    );
  }
}

/// Wat Discogs over het vinyl van één artiest zei, en wanneer.
@immutable
class VinylKennis {
  const VinylKennis({required this.discogsId, required this.gemetenMs, required this.platen, this.volledig = true});

  final int discogsId;
  final int gemetenMs;

  /// Alle persingen binnen ([kVinylPaginas]). Anders kan een plaat ontbreken, en zegt [bestaat] nooit nee.
  final bool volledig;

  /// Alle platen met minstens één officiële persing of promo. Bootlegs staan er niet in.
  final List<VinylPlaat> platen;

  DateTime get gemeten => DateTime.fromMillisecondsSinceEpoch(gemetenMs);
  bool get isVers => DateTime.now().difference(gemeten) < kVinylVers;

  /// De LP's voor de sectie, oudste eerst.
  List<VinylPlaat> get lps => _getoond(VinylVorm.lp);

  /// De vinylsingles voor de sectie, oudste eerst.
  List<VinylPlaat> get singles => _getoond(VinylVorm.single);

  List<VinylPlaat> _getoond(VinylVorm v) =>
      [for (final p in platen) if (p.getoond && p.vorm == v) p]..sort((a, b) => (a.jaarVan ?? 9999).compareTo(b.jaarVan ?? 9999));

  /// Bestaat [titel] van deze artiest op vinyl? Waar: op één of andere plaat (LP, single, promo). Onwaar: op geen
  /// enkele, en van elke plaat is de tracklijst bekend. Null: niet te zeggen (een plaat zonder tracklijst).
  ///
  /// Dezelfde VERSIE telt ([vinylNummerSleutel]): een radio edit of single version is het nummer zelf, een remix op
  /// een 12" alleen die remix (Saber, 12-11-2026: "Alleen dezelfde versie").
  bool? bestaat(String titel) {
    final sleutel = vinylNummerSleutel(titel);
    if (sleutel.isEmpty) return null;
    var onbekend = false;
    for (final p in platen) {
      // Een single heet naar zijn A-kant: "Wannabe", of "Wannabe / 2 Become 1" voor een dubbele A-kant.
      if (p.vorm == VinylVorm.single && p.titel.split(' / ').any((t) => vinylNummerSleutel(t) == sleutel)) return true;
      final n = p.nummers;
      if (n == null) {
        onbekend = true;
        continue;
      }
      if (n.any((t) => vinylNummerSleutel(t) == sleutel)) return true;
    }
    return onbekend || !volledig ? null : false;
  }

  VinylKennis metPlaat(int i, VinylPlaat p) =>
      VinylKennis(discogsId: discogsId, gemetenMs: gemetenMs, volledig: volledig, platen: [...platen]..[i] = p);

  /// De vorm van het bestand. 2: sinds de juiste Discogs-pagina gekozen wordt (12-11-2026) — wat ervoor bewaard werd,
  /// kan op een pagina onder de echte naam staan ("Adele Adkins": 0 vinyl) en telt niet meer.
  static const kVorm = 2;

  Map<String, dynamic> toJson() => {
        'v': kVorm,
        'id': discogsId,
        'ms': gemetenMs,
        if (!volledig) 'vol': false,
        'platen': [for (final p in platen) p.toJson()]
      };

  static VinylKennis? uitJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], ms = j['ms'], platen = j['platen'];
    if (id is! int || ms is! int || platen is! List || j['v'] != kVorm) return null;
    return VinylKennis(discogsId: id, gemetenMs: ms, volledig: j['vol'] != false, platen: [
      for (final p in platen)
        if (VinylPlaat.uitJson(p) case final v?) v
    ]);
  }
}

/// Wat er niets aan het nummer verandert: "(Radio Edit)", "(Single Version)", "(Album Version)", "(Remastered 2011)",
/// "(Mono)", "feat. …". Een remix, live, akoestisch of andere mix verandert het wél, en blijft in de sleutel.
final RegExp _neutraal = RegExp(
    r'^(?:(?:\d{4}\s+)?re-?master(?:ed)?(?:\s+\d{4})?(?:\s+version)?|(?:radio|single|album|lp|7"|7 inch|short|original|uk|us)'
    r'(?:\s+(?:edit|version|mix))?|edit|mono|stereo|explicit|clean|(?:feat|ft|featuring|with)\b.*)$',
    caseSensitive: false);
final RegExp _haakjes = RegExp(r'\s*[\(\[]([^\)\]]*)[\)\]]');

/// Een "… Version" is meestal dezelfde opname onder een andere naam: "(My Songs Version)" heet op de vinylplaat My
/// Songs gewoon "Shape Of My Heart" (Sting, de tweede lijst van 12-11-2026). Behalve als er een ander soort opname of
/// een andere taal in staat — dan blijft hij in de sleutel ([_eigenSoort]).
final RegExp _versieStaart = RegExp(r'\bversion$|\bversie$', caseSensitive: false);
final RegExp _eigenSoort = RegExp(
    r'remix|\bmix\b|live|acoustic|akoestisch|unplugged|instrumental|extended|\bdub\b|club|demo|piano|orchestral|symphonic'
    r'|karaoke|cappella|acapella|rework|reprise|strings|spanish|espa[nñ]ol|french|fran[cç]ais|italian|italiano|german'
    r'|deutsch|english|portugu[eê]s|dutch|nederlands',
    caseSensitive: false);

bool _isNeutraal(String binnen) =>
    _neutraal.hasMatch(binnen) || (_versieStaart.hasMatch(binnen) && !_eigenSoort.hasMatch(binnen));
final RegExp _streepStaart = RegExp(r'\s+-\s+([^-]+)$');
final RegExp _featLos = RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false);

/// De sleutel waarop een nummer met een nummer op een vinylplaat vergeleken wordt. Zie [VinylKennis.bestaat].
String vinylNummerSleutel(String titel) {
  // "(7″ Version)" met een dubbel accent in plaats van een aanhalingsteken (Billy Ocean, de tweede lijst): dat is een inch.
  var t = titel.trim().replaceAll(RegExp('[″”“]'), '"');
  // "Wannabe - Radio Edit" (Deezer, TIDAL): een staart na een streep die niets verandert, gaat weg.
  final streep = _streepStaart.firstMatch(t);
  if (streep != null && _isNeutraal(streep.group(1)!.trim())) t = t.substring(0, streep.start);
  t = t.replaceAllMapped(_haakjes, (m) => _isNeutraal(m.group(1)!.trim()) ? '' : ' ${m.group(1)}');
  t = t.replaceAll(_featLos, '');
  return normKey(t);
}

/// De regel onder een vinyltegel: "LP · 21 persingen · 1996–2024", "7\" · 12\" · 8 persingen · 1997".
String vinylOnderregel(VinylPlaat p) {
  const volgorde = ['LP', '12"', '10"', '7"'];
  final f = [for (final x in volgorde) if (p.formaten.contains(x)) x];
  final jaren = p.jaarVan == null
      ? null
      : (p.jaarTot == null || p.jaarTot == p.jaarVan ? '${p.jaarVan}' : '${p.jaarVan}–${p.jaarTot}');
  return [
    if (f.isNotEmpty) f.join(' · ') else if (p.vorm == VinylVorm.lp) 'LP' else 'vinyl',
    p.persingen == 1 ? '1 persing' : '${p.persingen} persingen',
    if (jaren != null) jaren,
  ].join(' · ');
}

/// Een titel uit de zoekuitslag zonder de artiest ervoor: "Spice Girls - Spice" → "Spice".
String _zonderArtiest(String t) {
  final i = t.indexOf(' - ');
  return i > 0 ? t.substring(i + 3).trim() : t.trim();
}

int? _jaar(Object? j) {
  final v = j is num ? j.toInt() : int.tryParse('${j ?? ''}'.trim());
  return v == null || v < 1900 ? null : v;
}

/// De persingen uit `database/search?artist_id=…&format=Vinyl&type=release`, per plaat samen. Bootlegs vallen weg.
@visibleForTesting
List<VinylPlaat> vinylPlatenUit(List<Map<String, dynamic>> persingen) {
  final per = <String, ({int? master, int? release, String titel, Set<String> formaten, bool lp, int gewoon, int promo,
      int? van, int? tot, String? hoes})>{};
  for (final r in persingen) {
    final f = [for (final x in (r['format'] as List? ?? const [])) '$x'];
    if (f.contains('Unofficial Release')) continue;
    final master = (r['master_id'] as num?)?.toInt() ?? 0;
    final id = (r['id'] as num?)?.toInt();
    final sleutel = master > 0 ? 'm$master' : 'r$id';
    final titel = _zonderArtiest('${r['title'] ?? ''}');
    if (titel.isEmpty) continue;
    final promo = f.contains('Promo');
    final lp = f.contains('LP') || (f.contains('Album') && !f.contains('Single') && !f.any((x) => x == '7"'));
    final formaten = {for (final x in f) if (const {'LP', '7"', '12"', '10"'}.contains(x)) x};
    final jaar = _jaar(r['year']);
    final cover = '${r['cover_image'] ?? ''}'.trim();
    final hoes = cover.isEmpty || cover.contains('spacer') ? null : cover;
    final oud = per[sleutel];
    per[sleutel] = (
      master: master > 0 ? master : null,
      release: master > 0 ? null : id,
      titel: oud?.titel ?? titel,
      formaten: {...?oud?.formaten, ...formaten},
      lp: (oud?.lp ?? false) || lp,
      gewoon: (oud?.gewoon ?? 0) + (promo ? 0 : 1),
      promo: (oud?.promo ?? 0) + (promo ? 1 : 0),
      van: [oud?.van, jaar].whereType<int>().fold<int?>(null, (a, b) => a == null || b < a ? b : a),
      tot: [oud?.tot, jaar].whereType<int>().fold<int?>(null, (a, b) => a == null || b > a ? b : a),
      hoes: oud?.hoes ?? hoes,
    );
  }
  return [
    for (final e in per.values)
      VinylPlaat(
        master: e.master,
        release: e.release,
        titel: e.titel,
        vorm: e.lp ? VinylVorm.lp : VinylVorm.single,
        formaten: e.formaten,
        persingen: e.gewoon,
        promos: e.promo,
        jaarVan: e.van,
        jaarTot: e.tot,
        hoes: e.hoes,
      )
  ];
}

/// De nummers uit een `/masters/{id}` of `/releases/{id}`: alleen echte nummers, ook die onder een kopje.
@visibleForTesting
List<String> tracklijstUit(Map<String, dynamic> body) {
  final uit = <String>[];
  for (final t in (body['tracklist'] as List? ?? const [])) {
    if (t is! Map) continue;
    final soort = '${t['type_'] ?? 'track'}';
    if (soort == 'track') {
      final titel = '${t['title'] ?? ''}'.trim();
      if (titel.isNotEmpty) uit.add(titel);
    } else if (soort == 'index') {
      for (final s in (t['sub_tracks'] as List? ?? const [])) {
        final titel = s is Map ? '${s['title'] ?? ''}'.trim() : '';
        if (titel.isNotEmpty) uit.add(titel);
      }
    }
  }
  return uit;
}

/// Hoe de dienst bij Discogs vraagt — los, zodat een toets geen netwerk nodig heeft.
abstract class VinylBron {
  /// Het Discogs-nummer van de artiest, of null als Discogs hem niet kent.
  Future<int?> discogsId(String artiest);

  /// De vinylpersingen van [discogsId], en of het ze allemaal zijn ([kVinylPaginas]); null als Discogs niet antwoordde.
  Future<({List<Map<String, dynamic>> rijen, bool volledig})?> persingen(int discogsId);

  /// De tracklijst van een plaat; null als Discogs niet antwoordde.
  Future<Map<String, dynamic>?> plaat({int? master, int? release});

  /// Hoeveel uitgaven (alle formaten) Discogs op deze pagina heeft; null als Discogs niet antwoordde.
  Future<int?> uitgaven(int discogsId);
}

/// Eén voor de hele app: onthoudt per artiest wat Discogs zei (`vinyl_bestaan.json`) en vraagt hoogstens één keer
/// tegelijk per artiest.
class VinylBestaan extends ChangeNotifier {
  VinylBestaan({this.bestand});

  /// Waar het op schijf staat; null in een toets.
  final File? bestand;

  final Map<String, VinylKennis> _kennis = {};
  final Map<String, Future<VinylKennis?>> _onderweg = {};
  bool _geladen = false;

  static String _sleutel(String artiest) => normKey(artiest);

  /// Wat er al bekend is (ook ouder dan een week), zonder te vragen.
  VinylKennis? bekend(String artiest) => _kennis[_sleutel(artiest)];

  /// Bestaat dit nummer op vinyl? Uit wat er bekend is, zonder te vragen; null als de app het niet weet.
  bool? bestaatOpVinyl(String artiest, String titel) => bekend(artiest)?.bestaat(titel);

  /// Wat Discogs over [artiest] weet: uit het geheugen als het minder dan een week oud is, anders opnieuw gevraagd (de
  /// persingen; tracklijsten die er al waren blijven). Null als Discogs het niet weet — dan blijft wat er was staan.
  Future<VinylKennis?> voor(String artiest, VinylBron bron, {bool vers = false}) async {
    await laad();
    final k = _sleutel(artiest);
    final al = _kennis[k];
    if (!vers && al != null && al.isVers) return al;
    final bezig = _onderweg[k];
    if (bezig != null) return bezig;
    final f = _haal(artiest, bron, al);
    _onderweg[k] = f;
    try {
      return await f;
    } finally {
      _onderweg.remove(k);
    }
  }

  Future<VinylKennis?> _haal(String artiest, VinylBron bron, VinylKennis? oud) async {
    try {
      final id = oud?.discogsId ?? await bron.discogsId(artiest);
      if (id == null) return oud;
      final uit = await bron.persingen(id);
      if (uit == null) return oud;
      // Geen enkele vinylpersing: alleen een nee als de pagina echt een discografie heeft. "The Black-Eyed Peas" is bij
      // Discogs een lege pagina naast de echte groep (de tweede lijst van 12-11-2026) — daaruit volgt niets.
      var volledig = uit.volledig;
      if (uit.rijen.isEmpty) {
        final n = await bron.uitgaven(id);
        if (n == null || n < kVinylEchtePagina) volledig = false;
      }
      // Wat er vorige keer al aan tracklijsten was, hoeft niet opnieuw: een plaat verandert zijn nummers niet.
      final eerder = {for (final p in oud?.platen ?? const <VinylPlaat>[]) '${p.master}|${p.release}': p.nummers};
      final kennis = VinylKennis(
          discogsId: id,
          gemetenMs: DateTime.now().millisecondsSinceEpoch,
          volledig: volledig,
          platen: [for (final p in vinylPlatenUit(uit.rijen)) p.metNummers(eerder['${p.master}|${p.release}'])]);
      _zet(artiest, kennis);
      return kennis;
    } catch (e) {
      debugPrint('Vinyl van $artiest niet opgehaald: $e');
      return oud;
    }
  }

  void _zet(String artiest, VinylKennis k) {
    _kennis[_sleutel(artiest)] = k;
    notifyListeners();
    _bewaarStraks();
  }

  /// Bestaat [titel] op vinyl, en haal daarvoor de tracklijsten die nog ontbreken — plaat voor plaat, LP's eerst (daar
  /// staat een nummer het vaakst), en stoppen zodra het gevonden is. Alleen als alle tracklijsten er zijn, kan het
  /// antwoord nee zijn. Null: Discogs weet het niet.
  Future<bool?> bestaatMetNummers(String artiest, String titel, VinylBron bron) async {
    var k = bekend(artiest);
    if (k == null) return null;
    final eerst = k.bestaat(titel);
    if (eerst != null) return eerst;
    final volgorde = [for (var i = 0; i < k.platen.length; i++) if (k.platen[i].nummers == null) i]
      ..sort((a, b) => k!.platen[a].vorm.index.compareTo(k.platen[b].vorm.index));
    final sleutel = vinylNummerSleutel(titel);
    for (final i in volgorde) {
      final p = k!.platen[i];
      final body = await bron.plaat(master: p.master, release: p.release);
      if (body == null) continue; // dan blijft die plaat onbekend, en het antwoord hoogstens null
      final n = tracklijstUit(body);
      k = k.metPlaat(i, p.metNummers(n));
      _zet(artiest, k);
      if (n.any((t) => vinylNummerSleutel(t) == sleutel)) return true;
    }
    return k!.bestaat(titel);
  }

  /// Inlezen, één keer.
  Future<void> laad() async {
    if (_geladen) return;
    _geladen = true;
    final f = bestand;
    if (f == null) return;
    try {
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      for (final e in j.entries) {
        if (VinylKennis.uitJson(e.value) case final k?) _kennis.putIfAbsent('${e.key}', () => k);
      }
    } catch (e) {
      debugPrint('vinyl_bestaan.json onleesbaar: $e');
    }
  }

  Timer? _klok;
  void _bewaarStraks() {
    if (bestand == null) return;
    _klok?.cancel();
    _klok = Timer(const Duration(seconds: 2), () => unawaited(bewaarNu()));
  }

  @visibleForTesting
  Future<void> bewaarNu() async {
    _klok?.cancel();
    final f = bestand;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({for (final e in _kennis.entries) e.key: e.value.toJson()}));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('vinyl_bestaan.json niet bewaard: $e');
    }
  }
}

/// Hoe de app buiten de artiestpagina bij Discogs vraagt, met dezelfde artiest als de discografie (main.dart zet dit,
/// via [DiscographyService.vinylBron]). Null in een toets: dan vraagt hij niets en geldt alleen wat bekend is.
VinylBron Function()? vinylBronVoorZoeken;

/// Bestaat [titel] van [artiest] op vinyl? Vóór een vinylzoektocht (Saber, 12-11-2026: "Bij bezoek + vóór elke
/// vinylzoektocht"): wat ouder is dan een week, wordt eerst opnieuw gevraagd. Null: niet te zeggen — dan zoekt de app
/// zoals altijd.
Future<bool?> vinylVoorNummer(String artiest, String titel, {VinylBestaan? dienst}) async {
  final d = dienst ?? vinylBestaan;
  final maak = vinylBronVoorZoeken;
  if (maak == null) {
    await d.laad();
    return d.bestaatOpVinyl(artiest, titel);
  }
  final bron = maak();
  await d.voor(artiest, bron);
  return d.bestaatMetNummers(artiest, titel, bron);
}

/// Wat een AUTOMATISCHE keuze uit [kandidaten] laat vallen: een vinylrip van een nummer dat volgens Discogs nooit op
/// vinyl verscheen (Saber, 12-11-2026: "Weigeren") — bijna altijd een cd met een verkeerd etiket, of een andere plaat.
/// Alleen op wat al bekend is; hier vraagt de app Discogs niets. Weet hij het niet, dan blijft alles staan.
List<T> zonderNepVinyl<T>(List<T> kandidaten, String artiest, String titel, String Function(T) pad,
    {VinylBestaan? dienst}) {
  if (artiest.trim().isEmpty || titel.trim().isEmpty) return kandidaten;
  if ((dienst ?? vinylBestaan).bestaatOpVinyl(artiest, titel) != false) return kandidaten;
  return [for (final k in kandidaten) if (!isVinylRip(pad(k))) k];
}

/// Bestaat geen van [nummers] (artiest, titel) op vinyl, volgens wat er bekend is? Voor het grijze "Download in vinyl".
bool geenVinylBekend(Iterable<({String artiest, String titel})> nummers, {VinylBestaan? dienst}) {
  final d = dienst ?? vinylBestaan;
  var een = false;
  for (final n in nummers) {
    if (d.bestaatOpVinyl(n.artiest, n.titel) != false) return false;
    een = true;
  }
  return een;
}

/// Het bestand. **In een toets niets naar schijf**: de appmap is daar die van de echte app.
File? vinylBestaanBestand() => Platform.environment.containsKey('FLUTTER_TEST')
    ? null
    : File('$appDir${Platform.pathSeparator}vinyl_bestaan.json');

/// Eén voor de hele app.
final VinylBestaan vinylBestaan = VinylBestaan(bestand: vinylBestaanBestand());
