/// De staande vragen om een studio-, cd- of vinylkopie (kopiesoort.dart), en welke kandidaten daarvoor in aanmerking komen.
///
/// Saber, 25-10-2026, gevraagd wat er moet gebeuren als er (nog) geen kopie van die soort te vinden is: *"Melding, en
/// blijven zoeken"*. Een vraag blijft dus staan tot er een kopie klaarstaat en je hem houdt — of tot je de vraag
/// intrekt. Komt er een klaar te staan en gooi je hem weg, dan zoekt de vraag de volgende ("alleen de beste kandidaat
/// per nummer; weg → volgende zoeken").
///
/// Op de pc in `soortvragen.json`. Het zoeken zelf staat in `DownloadManager.vraagSoort` (online.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'kopiesoort.dart';
import 'soulseek.dart' show SoulseekFile;
import 'versies.dart' show persingUit;

/// Wanneer een vraag opnieuw zoekt, na [rondes] rondes zonder klaargezette kopie: 30 min, 2 u, 6 u, dan elke dag.
Duration soortvraagWacht(int rondes) => switch (rondes) {
      <= 1 => const Duration(minutes: 30),
      2 => const Duration(hours: 2),
      3 => const Duration(hours: 6),
      _ => const Duration(days: 1),
    };

/// Wanneer een vraag van de cd-jacht ([Soortvraag.vanzelf]) opnieuw zoekt, na [rondes] rondes zonder cd: na 2, 4 en 7
/// dagen, daarna om de 14 dagen — en om de 30 als TIDAL de opname zelf niet kent ([tidalKentHemNiet]). Saber, 05-11-2026:
/// *"Blijven proberen"*, zoals de blijvende jacht.
Duration cdjachtWacht(int rondes, {bool tidalKentHemNiet = false}) => switch (rondes) {
      <= 1 => const Duration(days: 2),
      2 => const Duration(days: 4),
      3 => const Duration(days: 7),
      _ => tidalKentHemNiet ? const Duration(days: 30) : const Duration(days: 14),
    };

/// Hoeveel nummers van één plaat de cd-jacht in één ronde neemt (één plaat per ronde, één nummer tegelijk).
const int kCdjachtPerRonde = 12;

/// Hoeveel cd's de cd-jacht hoogstens per uur van TIDAL haalt: de opwaardeerronde van TIDAL (20 per uur) en de radio (15)
/// lopen ernaast.
const int kCdjachtTidalPerUur = 10;

/// De extra zoekopdracht bij Soulseek per soort: "<vraag> 24bit", "<vraag> vinyl". Een cd-kopie vindt de gewone vraag.
List<String> zoekwoordenVoorSoort(Kopiesoort s) => switch (s) {
      Kopiesoort.studio => const ['24bit'],
      Kopiesoort.vinyl => const ['vinyl'],
      Kopiesoort.cd => const [],
    };

/// Hoeveel kandidaten één ronde hoogstens binnenhaalt voor één nummer: elke mislukte kost een download.
const int kSoortKandidaten = 6;

/// Bij cd zoveel kandidaten, en die beginnen allemaal samen: wie het eerst stuurt wint, de rest stopt voor hij iets
/// stuurt (de wedloop van ▶, `DownloadManager._wedloop`). Elke cd-kopie is 16/44,1, dus de snelste is goed genoeg. Saber,
/// 29-10-2026, bij Dangerous: *"zeker cd kwaliteit moet instant gaan bijna, studio en vinyl dat snap ik maar cd is echt
/// basis"* — daar stond Jam op plaats 16 in de rij van de eerste uploader, en de vijf anderen wachtten erachter. Studio
/// en vinyl blijven de beste eerst, één voor één: daar kan de snelste een 24/48 zijn waar ook een 24/192 klaarstond.
const int kCdKandidaten = 12;

/// Is [f] een rip van een Japanse persing? Zijn mappen bij de uploader zeggen het ([persingUit]: "Japan", "JPN", SHM-CD).
bool japanseRip(SoulseekFile f) {
  final p = persingUit(f.filename, soort: Kopiesoort.cd);
  return p.contains('Japan') || p.contains('SHM-CD');
}

/// De wedlopen voor een cd: eerst [kandidaten] zonder Japanse rips ([japanseRip]), en die pas als er niets anders
/// bruikbaars kwam. Saber, 29-10-2026, toen het nummer Dangerous een "CD · Japan" kreeg: een Japanse cd-rip alleen als er
/// geen andere kandidaat is — zoals hij al gold voor de nummerlijst (zonderJapansePersingen in release_format.dart).
/// Lege groepen vallen weg.
List<List<SoulseekFile>> cdRondes(List<SoulseekFile> kandidaten) => [
      for (final japans in [false, true])
        if (kandidaten.where((f) => japanseRip(f) == japans).toList() case final g when g.isNotEmpty) g,
    ];

/// Hoe vaak een cd-wedloop waarin iedereen alleen BEZET was (een ander nummer van de plaat haalt bij dezelfde uploader),
/// na [kCdBezetPauze] opnieuw begint vóór de volgende groep ([cdRondes]) aan de beurt komt.
const int kCdBezetRondes = 6;
const Duration kCdBezetPauze = Duration(seconds: 5);

/// Hoeveel nummers van een plaat er samen zoeken als je zelf een soort vroeg (zie [kCdKandidaten]): de veertien van
/// Dangerous gingen één voor één. De ronde die vanzelf terugkomt ([soortvraagWacht]) blijft één voor één.
const int kSoortNummersTegelijk = 4;

/// [werk] voor elk van [items], in volgorde begonnen en hoogstens [n] tegelijk. Een fout stopt alleen die ene loper: de
/// andere werken de rij af, en daarna komt de eerste fout terug.
Future<void> metHoogstens<T>(int n, Iterable<T> items, Future<void> Function(T) werk) async {
  final rij = items.toList();
  if (rij.isEmpty) return;
  var volgende = 0;
  Future<void> loper() async {
    while (volgende < rij.length) {
      await werk(rij[volgende++]);
    }
  }

  await Future.wait([for (var i = 0; i < n.clamp(1, rij.length); i++) loper()]);
}

/// Hoeveel een vinylrip in lengte mag schelen vóór het binnenhalen: een plaat draait vaak een paar seconden langer
/// ("Mademoiselle chante le blues": 235 s tegen 228 s). De vingerafdruk beslist daarna of het dezelfde opname is.
const int kVinylLengteSpeling = 15;

/// Uit [kandidaten] (al gezeefd op titel, verliesvrij en stereo) wat [soort] kan zijn, de beste eerst: eerst wat zijn
/// pad en opgave bevestigen, de hoogste bemonstering en diepte voorop; daarna wat de uploader niet meldt. Nooit
/// [eigenGrootte] (hetzelfde bestand als wat je hebt) of een grootte uit [afgewezen] (weggegooid).
List<SoulseekFile> kandidatenVoorSoort(
  Kopiesoort soort,
  List<SoulseekFile> kandidaten, {
  int eigenGrootte = 0,
  Set<int> afgewezen = const {},
}) {
  final ja = <SoulseekFile>[], misschien = <SoulseekFile>[];
  for (final f in kandidaten) {
    if (f.size == eigenGrootte || afgewezen.contains(f.size)) continue;
    switch (kanSoortZijn(soort, bronpad: f.filename, bits: f.bitDepth ?? 0, hz: f.sampleRate ?? 0)) {
      case true:
        ja.add(f);
      case null:
        misschien.add(f);
      case false:
        break;
    }
  }
  // Stabiel: binnen dezelfde kwaliteit blijft de volgorde van de zeef (snelheid, vrije plek).
  final rang = {for (var i = 0; i < ja.length; i++) ja[i]: i};
  ja.sort((a, b) {
    final r = (b.sampleRate ?? 0).compareTo(a.sampleRate ?? 0);
    if (r != 0) return r;
    final d = (b.bitDepth ?? 0).compareTo(a.bitDepth ?? 0);
    return d != 0 ? d : rang[a]!.compareTo(rang[b]!);
  });
  return [...ja, ...misschien];
}

/// Eén staande vraag.
class Soortvraag {
  Soortvraag({
    required this.pad,
    required this.soort,
    required this.artiest,
    required this.titel,
    this.album = '',
    this.seconden,
    required this.sindsMs,
    this.rondes = 0,
    this.laatsteMs = 0,
    this.gezag,
    this.vanzelf = false,
    Set<int>? nee,
    this.tidalKentHemNiet = false,
  }) : nee = nee ?? <int>{};

  /// Het nummer in de bibliotheek.
  String pad;
  final Kopiesoort soort;
  final String artiest, titel, album;
  final int? seconden;
  final int sindsMs;
  int rondes;
  int laatsteMs;

  /// De tags voor het opbergen (`TrackTags.toJson`).
  final Map<String, dynamic>? gezag;

  /// Een vraag van de cd-jacht (Saber, 05-11-2026: *"zoiezo bij alle liedjes de cd kwaliteit"*), niet van jou: geen label
  /// op het scherm, geen melding, en een kopie waar de vingerafdruk over twijfelt wordt niet aangeboden.
  final bool vanzelf;

  /// De groottes die de cd-jacht voor dit nummer al binnenhaalde en weggooide: niet nog eens halen.
  final Set<int> nee;

  /// TIDAL vond bij de laatste ronde niets van deze opname ([cdjachtWacht]).
  bool tidalKentHemNiet;

  /// Mag hij nu weer zoeken?
  bool aanDeBeurt(DateTime nu) =>
      rondes == 0 ||
      nu.millisecondsSinceEpoch - laatsteMs >=
          (vanzelf ? cdjachtWacht(rondes, tidalKentHemNiet: tidalKentHemNiet) : soortvraagWacht(rondes)).inMilliseconds;

  Map<String, dynamic> toJson() => {
        'pad': pad,
        'soort': soort.naam,
        'artiest': artiest,
        'titel': titel,
        if (album.isNotEmpty) 'album': album,
        if (seconden != null) 'seconden': seconden,
        'sinds': sindsMs,
        'rondes': rondes,
        'laatste': laatsteMs,
        if (gezag != null) 'gezag': gezag,
        if (vanzelf) 'vanzelf': true,
        if (nee.isNotEmpty) 'nee': nee.toList(),
        if (tidalKentHemNiet) 'tidalNiet': true,
      };

  static Soortvraag? fromJson(Object? j) {
    if (j is! Map) return null;
    final pad = j['pad'], soort = kopiesoortUit(j['soort']);
    if (pad is! String || soort == null) return null;
    return Soortvraag(
      pad: pad,
      soort: soort,
      artiest: '${j['artiest'] ?? ''}',
      titel: '${j['titel'] ?? ''}',
      album: '${j['album'] ?? ''}',
      seconden: (j['seconden'] as num?)?.toInt(),
      sindsMs: (j['sinds'] as num?)?.toInt() ?? 0,
      rondes: (j['rondes'] as num?)?.toInt() ?? 0,
      laatsteMs: (j['laatste'] as num?)?.toInt() ?? 0,
      gezag: j['gezag'] is Map ? Map<String, dynamic>.from(j['gezag'] as Map) : null,
      vanzelf: j['vanzelf'] == true,
      nee: {for (final x in (j['nee'] is List ? j['nee'] as List : const [])) if (x is num) x.toInt()},
      tidalKentHemNiet: j['tidalNiet'] == true,
    );
  }
}

/// Hoe ver de cd-jacht is (Kwaliteit, op de pc en op een toestel): hoeveel nummers er sinds de start een cd bij kregen,
/// en hoeveel er nog zoeken.
class CdjachtStand {
  const CdjachtStand({this.binnen = 0, this.zoekt = 0});
  final int binnen, zoekt;

  Map<String, dynamic> toJson() => {'binnen': binnen, 'zoekt': zoekt};

  static CdjachtStand fromJson(Map<String, dynamic> j) =>
      CdjachtStand(binnen: (j['binnen'] as num?)?.toInt() ?? 0, zoekt: (j['zoekt'] as num?)?.toInt() ?? 0);

  /// De regel onder Kwaliteit, of null als er niets te zeggen valt.
  String? get zin => binnen == 0 && zoekt == 0
      ? null
      : zoekt == 0
          ? 'Cd erbij: $binnen — elk nummer heeft nu een cd'
          : 'Cd erbij: $binnen · zoekt nog $zoekt';
}

String _sleutel(String pad) => pad.replaceAll('\\', '/').toLowerCase();

// ── Wat een scherm leest: welke soort er voor een nummer gezocht wordt ─────────────────────────────────────────────
// Op de pc gevuld door [Soortvragen], op een toestel door de catalogus ([zetSoortvraagVanPc]) — zoals twijfel.dart.
// Saber, 25-10-2026: op de gsm en de Shield laten zien dat er al gezocht wordt, met "Stop met zoeken" erbij.

final Map<String, Kopiesoort> _gezocht = {};

/// Gaat omhoog bij elke wijziging: de catalogus en het label luisteren ernaar.
final ValueNotifier<int> soortvraagUitgave = ValueNotifier<int>(0);

/// Welke soort er voor het nummer op [pad] gezocht wordt, of null.
Kopiesoort? gezochtVoor(String pad) => _gezocht[_sleutel(pad)];

/// Wat de pc zegt, op een toestel. Null wist.
void zetSoortvraagVanPc(String pad, Kopiesoort? soort) {
  final k = _sleutel(pad);
  if (_gezocht[k] == soort) return;
  if (soort == null) {
    _gezocht.remove(k);
  } else {
    _gezocht[k] = soort;
  }
  soortvraagUitgave.value++;
}

/// De staande vragen van de pc, op schijf. Eén per nummer: een nieuwe vraag voor hetzelfde nummer vervangt de vorige.
class Soortvragen {
  /// [toon] uit: de vragen van de cd-jacht (`cdjacht.json`) — geen "zoekt cd" bij honderden nummers op het scherm.
  Soortvragen(this._bestand, {this.toon = true});
  final String _bestand;
  final bool toon;
  final Map<String, Soortvraag> _perPad = {};

  /// Hoeveel nummers hun vraag zagen uitkomen ([CdjachtStand.binnen]); bewaard met de lijst.
  int binnen = 0;

  Iterable<Soortvraag> get alle => _perPad.values;
  Soortvraag? van(String pad) => _perPad[_sleutel(pad)];

  void zet(Soortvraag v) {
    _perPad[_sleutel(v.pad)] = v;
    if (!toon) return;
    _gezocht[_sleutel(v.pad)] = v.soort;
    soortvraagUitgave.value++;
  }

  Soortvraag? verwijder(String pad) {
    final v = _perPad.remove(_sleutel(pad));
    if (toon && v != null && _gezocht.remove(_sleutel(pad)) != null) soortvraagUitgave.value++;
    return v;
  }

  /// Het nummer is verplaatst (een opwaardering met een andere extensie): de vraag gaat mee.
  void herNoem(String van, String naar) {
    final v = verwijder(van);
    if (v == null) return;
    v.pad = naar;
    zet(v);
  }

  Future<void> laad() async {
    try {
      final f = File(_bestand);
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      for (final x in (j is Map ? j['vragen'] as List? ?? const [] : const [])) {
        final v = Soortvraag.fromJson(x);
        if (v != null) zet(v);
      }
      if (j is Map && j['binnen'] is num) binnen = (j['binnen'] as num).toInt();
      // De cd-jacht van 3.9.716 gooide een andere mastering weg (0,80–0,90) en onthield die kopieën ([Soortvraag.nee]):
      // Haddaway — Life kreeg er op 05-11-2026 zeven (0,86–0,87), en die haalde hij daarna nooit meer. Eén keer opnieuw.
      if (!toon && j is Map && ((j['versie'] as num?) ?? 1) < 2) {
        for (final v in _perPad.values) {
          v.nee.clear();
          v.rondes = 0;
          v.laatsteMs = 0;
        }
      }
    } catch (_) {/* een kapotte lijst begint leeg */}
  }

  Future<void> bewaar() async {
    try {
      final tmp = File('$_bestand.tmp');
      await tmp.writeAsString(jsonEncode({
        'versie': 2,
        if (binnen > 0) 'binnen': binnen,
        'vragen': [for (final v in _perPad.values) v.toJson()],
      }));
      await tmp.rename(_bestand);
    } catch (_) {/* volgende keer opnieuw */}
  }
}

/// Waarom een binnengekomen kandidaat voor [gevraagd] niet klaar mag staan, of null als hij mag. [binnen]: wat hij volgens
/// zijn kop en zijn bron is ([kopiesoortVan]); [lengte] en [seconden]: zijn lengte en die van jouw nummer; [score]: de
/// vingerafdruk tegen jouw kopie (null: niet te meten). Niet gevraagd wordt "bewezen beter": jij kiest de soort, ook als
/// je huidige kopie op papier hoger staat. Wel dezelfde opname — vanaf [drempel] (de twijfelzone, met een waarschuwing),
/// nooit daaronder (live, remix).
String? waaromNietKlaar({
  required Kopiesoort gevraagd,
  required Kopiesoort? binnen,
  String? binnenZin,
  int? lengte,
  int? seconden,
  double? score,
  required double drempel,
}) {
  if (binnen != gevraagd) return 'geen ${gevraagd.voluit} maar ${binnen?.voluit ?? binnenZin ?? 'iets anders'}';
  final speling = gevraagd == Kopiesoort.vinyl ? kVinylLengteSpeling : 6;
  if (seconden != null && lengte != null && (lengte - seconden).abs() > speling) {
    return 'andere lengte (${lengte}s tegen ${seconden}s)';
  }
  if (score != null && score < drempel) {
    return 'een andere opname (vingerafdruk ${score.toStringAsFixed(2).replaceAll('.', ',')})';
  }
  return null;
}
