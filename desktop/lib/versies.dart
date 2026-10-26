/// Versies van één nummer: dezelfde opname als studio-, cd- of vinylkopie, of in een andere persing.
///
/// Saber, 26-10-2026: *"Behoud ik alles e, cd, studio, en vinyl. Dan kan ik nog kiezen wat ik wil … tijdens het spelen
/// wil ik probleemloos, vloeiend kunnen springen van cd, naar studio of vinyl, en andersom"*. Zijn keuzes (zes rondes):
///
/// * **Elke echt andere versie blijft**: een andere soort ([Kopiesoort]), of een andere persing of remaster. Twee rips van
///   dezelfde uitgave niet — daar wint de bewezen betere, zoals altijd ([zelfdeVersie]).
/// * **Op schijf een eigen map per versie**, naast het album: "Spice (vinyl LP 1996)" ([versieMap]). In de app één tegel.
///   Het hoofdbestand — het ANKER — staat in de gewone map en is de standaard: studio > cd > vinyl ([soortRang]).
/// * **Welke versie speelt**, kies je per plaat of per nummer ([Versieregister.kies]). Zonder keuze: het anker.
///
/// Alleen op de pc (`versies.json`); een toestel krijgt de versies per nummer mee met de catalogus.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'kopiesoort.dart';
import 'models.dart';
import 'paths.dart';
import 'quality.dart' show depthRateLabel;
import 'vinyl.dart' show isVinylRip;

/// Studio vóór cd vóór vinyl (Saber, 26-10-2026): de volgorde van de standaard en van de lijst.
int soortRang(Kopiesoort s) => switch (s) { Kopiesoort.studio => 0, Kopiesoort.cd => 1, Kopiesoort.vinyl => 2 };

/// Hoe de soort in een naam staat: "Studio", "CD", "Vinyl".
String soortKop(Kopiesoort s) => switch (s) { Kopiesoort.studio => 'Studio', Kopiesoort.cd => 'CD', Kopiesoort.vinyl => 'Vinyl' };

final _jaar = RegExp(r'(?<![0-9])(19[4-9][0-9]|20[0-4][0-9])(?![0-9])');
final _remaster = RegExp(r're-?master(ed)?', caseSensitive: false);

/// Wat een persing van een andere onderscheidt, met de naam waaronder het in het label staat. Alleen wat over het
/// GELUID gaat (de master, de persing, het label dat zelf mastert) — "Deluxe" of "Expanded" gaan over de nummerlijst en
/// zeggen daar niets over.
const _merken = <(String, String)>[
  (r'\bmfsl\b|mobile[\s_.-]*fidelity|one[\s_.-]*step', 'MFSL'),
  (r'\bsacd\b', 'SACD'),
  (r'\bdcc\b', 'DCC'),
  (r'shm[\s_.-]*cd', 'SHM-CD'),
  (r'\bjapan(ese)?\b|\bjpn\b', 'Japan'),
  (r'\bmono\b', 'Mono'),
  (r'half[\s_.-]*speed', 'Half-Speed'),
  (r'pbthal', 'PBTHAL'),
  (r'\breissue\b|\bre-issue\b|\bherpersing\b', 'Reissue'),
  (r'\bpromo\b', 'Promo'),
  (r'test[\s_.-]*press', 'Test Pressing'),
  (r'\b(original|first|1st|og)[\s_.-]*press(ing)?\b', 'Eerste persing'),
];

/// Hoe een vinylplaat is uitgebracht: dubbel-lp, maxi, single.
final _vorm = RegExp(r'\b([2-4])[\s_.-]*lp\b|\b(12|7|10)[\s_.-]*("|inch|in\b)|\bmaxi\b', caseSensitive: false);

/// De persing uit [bronpad] (waar de kopie vandaan kwam: het pad bij de uploader, in de torrent): "LP 1996",
/// "Remaster 2011", "MFSL", "2LP PBTHAL". Leeg als er niets over te zeggen valt — en dat is het gewone geval.
///
/// Gekeken wordt naar de mappen, niet naar de bestandsnaam: daar staat de titel van het nummer, en "Mono" of "1999"
/// kunnen gewoon een titel zijn.
String persingUit(String bronpad, {Kopiesoort? soort}) {
  final delen = bronpad.split(RegExp(r'[\\/]'))..removeWhere((d) => d.trim().isEmpty);
  if (delen.length > 1) delen.removeLast();
  final mappen = delen.join(' / ');
  final uit = <String>[];
  if (soort == Kopiesoort.vinyl) {
    final v = _vorm.firstMatch(mappen);
    if (v == null) {
      uit.add('LP');
    } else if (v.group(1) != null) {
      uit.add('${v.group(1)}LP');
    } else if (v.group(2) != null) {
      uit.add('${v.group(2)}"');
    } else {
      uit.add('Maxi');
    }
  }
  final rm = _remaster.firstMatch(mappen);
  if (rm != null) {
    // Het jaar dat bij "remaster" hoort: het dichtstbijzijnde binnen een paar tekens ("2011 Remaster", "Remastered 2009").
    String? bij;
    var beste = 1 << 30;
    for (final j in _jaar.allMatches(mappen)) {
      final afstand = j.start >= rm.end ? j.start - rm.end : rm.start - j.end;
      if (afstand <= 4 && afstand < beste) {
        beste = afstand;
        bij = j.group(0);
      }
    }
    uit.add(bij == null ? 'Remaster' : 'Remaster $bij');
  } else if (soort == Kopiesoort.vinyl) {
    // Bij vinyl zegt het jaar welke persing het is ("LP 1996" tegen "LP 2016 Reissue"). Uit de map waar het vinylteken
    // staat, anders de albummap (de laatste).
    final metTeken = delen.lastWhere(isVinylRip, orElse: () => delen.isEmpty ? '' : delen.last);
    final j = _jaar.firstMatch(metTeken);
    if (j != null) uit.add(j.group(0)!);
  }
  for (final (patroon, naam) in _merken) {
    if (RegExp(patroon, caseSensitive: false).hasMatch(mappen) && !uit.contains(naam)) uit.add(naam);
  }
  return uit.join(' ');
}


/// De naam van een versie: "Vinyl · LP 1996 · 24/192", "CD · 16/44.1", "Studio · Remaster 2011 · 24/96".
String versieLabel(Kopiesoort soort, String persing, {int bits = 0, int hz = 0}) => [
      soortKop(soort),
      if (persing.trim().isNotEmpty) persing.trim(),
      if (bits > 0 && hz > 0) depthRateLabel(sampleRate: hz, bitsPerSample: bits),
    ].join(' · ');

/// Wat er tussen haakjes achter de albummap komt: "vinyl LP 1996", "cd", "studio Remaster 2011".
String versieMapLabel(Kopiesoort soort, String persing) =>
    [soort.naam, if (persing.trim().isNotEmpty) persing.trim()].join(' ');

/// De map van een versie naast de map van zijn anker: `…/Spice` → `…/Spice (vinyl LP 1996)`. Tekens die Windows in een
/// mapnaam weigert, gaan eruit.
String versieMap(String ankerMap, Kopiesoort soort, String persing) {
  final label = versieMapLabel(soort, persing).replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
  return '$ankerMap ($label)';
}

/// De persing in kleine letters en in vaste volgorde, om te vergelijken.
List<String> _facetten(String persing) => persing.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Zijn [a] en [b] dezelfde versie van een nummer — dan wint de bewezen betere en blijft er één ([soort] gelijk, en
/// niets in hun persing dat elkaar tegenspreekt)?
///
/// **Onbekend is geen verschil.** De meeste kopieën zeggen niets over hun persing: een cd-rip van Soulseek en een
/// cd-rip uit een torrent zijn dan twee rips van dezelfde cd, en daar blijft er één van (Saber, 26-10-2026: "alleen echt
/// andere versies"). Pas als BEIDE een jaar noemen en dat verschilt ("LP 1996" tegen "LP 2016"), of beide een merk
/// en dat verschilt ("MFSL" tegen "Japan"), zijn het twee versies.
bool zelfdeVersie(Kopiesoort soortA, String persingA, Kopiesoort soortB, String persingB) {
  if (soortA != soortB) return false;
  final a = _facetten(persingA), b = _facetten(persingB);
  final jaarA = a.where((w) => _jaar.hasMatch(w)).toSet(), jaarB = b.where((w) => _jaar.hasMatch(w)).toSet();
  if (jaarA.isNotEmpty && jaarB.isNotEmpty && jaarA.intersection(jaarB).isEmpty) return false;
  final merkA = _merkenIn(a), merkB = _merkenIn(b);
  if (merkA.isNotEmpty && merkB.isNotEmpty && (merkA.difference(merkB).isNotEmpty || merkB.difference(merkA).isNotEmpty)) {
    return false;
  }
  return true;
}

Set<String> _merkenIn(List<String> woorden) {
  final tekst = woorden.join(' ');
  return {
    for (final (_, naam) in _merken)
      if (tekst.contains(naam.toLowerCase())) naam,
  };
}

/// De sleutel waaronder een keuze bewaard wordt: soort en persing ("vinyl|lp 1996").
String versieSleutel(Kopiesoort soort, String persing) => '${soort.naam}|${persing.trim().toLowerCase()}';

/// Eén versie van een nummer, naast zijn anker.
@immutable
class Versie {
  const Versie({
    required this.pad,
    required this.soort,
    this.persing = '',
    this.bron = '',
    this.sindsMs = 0,
    this.verschuivingMs,
    this.snelheid = 1.0,
  });

  /// Waar het bestand staat (in zijn versiemap).
  final String pad;
  final Kopiesoort soort;

  /// "LP 1996", "Remaster 2011", leeg als onbekend ([persingUit]).
  final String persing;

  /// Waar hij vandaan kwam: het pad bij de uploader, in de torrent, "TIDAL …", of "_dubbel" (een oude kopie die
  /// teruggezet werd).
  final String bron;

  /// Wanneer hij als versie bewaard werd: voor "Nieuwe versies" op Start.
  final int sindsMs;

  /// Waar in DEZE versie het moment `t` van het anker valt: `verschuivingMs + t × snelheid` ([plekInVersie]). Null: nog
  /// niet gemeten — dan wisselt de speler op dezelfde seconde.
  final int? verschuivingMs;

  /// Een vinylplaat draait zelden precies op toeren: na vier minuten loopt hij soms een halve seconde voor of achter.
  final double snelheid;

  String get sleutel => versieSleutel(soort, persing);

  Versie met({String? pad, String? persing, int? verschuivingMs, double? snelheid}) => Versie(
        pad: pad ?? this.pad,
        soort: soort,
        persing: persing ?? this.persing,
        bron: bron,
        sindsMs: sindsMs,
        verschuivingMs: verschuivingMs ?? this.verschuivingMs,
        snelheid: snelheid ?? this.snelheid,
      );

  Map<String, dynamic> toJson() => {
        'pad': pad,
        's': soort.naam,
        if (persing.isNotEmpty) 'p': persing,
        if (bron.isNotEmpty) 'b': bron,
        if (sindsMs > 0) 't': sindsMs,
        if (verschuivingMs != null) 'v': verschuivingMs,
        if (snelheid != 1.0) 'x': snelheid,
      };

  static Versie? fromJson(Object? j) {
    if (j is! Map) return null;
    final pad = j['pad'], soort = kopiesoortUit(j['s']);
    if (pad is! String || pad.isEmpty || soort == null) return null;
    return Versie(
      pad: pad,
      soort: soort,
      persing: j['p'] is String ? j['p'] as String : '',
      bron: j['b'] is String ? j['b'] as String : '',
      sindsMs: (j['t'] as num?)?.toInt() ?? 0,
      verschuivingMs: (j['v'] as num?)?.toInt(),
      snelheid: (j['x'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Wat een nummer zonder bekende soort is, uit zijn kop: 24 bit studio, 16/44,1 cd. Verliesgevend of anders: null.
/// (Een vinylrip zonder soort is zo niet te herkennen; alleen nieuwe downloads weten waar ze vandaan kwamen.)
Kopiesoort? soortUitKop(Track t) {
  const verliesvrij = {'flac', 'wav', 'aif', 'aiff', 'wv', 'ape', 'alac'};
  if (!t.isFlac && !verliesvrij.contains(t.ext)) return null;
  if (t.bitsPerSample >= 24) return Kopiesoort.studio;
  if (t.bitsPerSample == 16 && t.sampleRate == 44100) return Kopiesoort.cd;
  return null;
}

/// Eén speelbare versie van een nummer, voor de speler en de schermen — op de pc en op een toestel hetzelfde. Het anker
/// staat er ook tussen ([anker]).
@immutable
class VersieInfo {
  const VersieInfo({
    required this.track,
    required this.soort,
    this.persing = '',
    this.anker = false,
    this.standaard = false,
    this.verschuivingMs,
    this.snelheid = 1.0,
    this.sindsMs = 0,
  });

  /// Wat er speelt: op de pc het bestand, op een toestel de stroom van de pc.
  final Track track;

  /// Null: een anker waarvan de soort onbekend is (verliesgevend, of 16/48).
  final Kopiesoort? soort;
  final String persing;
  final bool anker;

  /// Speelt als je niets kiest: de keuze voor dit nummer of deze plaat, en anders het anker.
  final bool standaard;
  final int? verschuivingMs;
  final double snelheid;
  final int sindsMs;

  String get sleutel => soort == null ? '' : versieSleutel(soort!, persing);

  /// "Vinyl · LP 1996 · 24/192". Een anker zonder soort heet naar zijn kwaliteit.
  String get label => soort == null
      ? (track.bitsPerSample > 0 && track.sampleRate > 0
          ? depthRateLabel(sampleRate: track.sampleRate, bitsPerSample: track.bitsPerSample)
          : track.ext.toUpperCase())
      : versieLabel(soort!, persing, bits: track.bitsPerSample, hz: track.sampleRate);

  /// Waar het moment [ankerMs] van het anker in deze versie valt.
  int plekVanAnker(int ankerMs) => anker ? ankerMs : plekInVersie(ankerMs, verschuivingMs: verschuivingMs, snelheid: snelheid);

  /// Waar het moment [ms] van deze versie in het anker valt.
  int ankerPlek(int ms) => anker ? ms : plekInAnker(ms, verschuivingMs: verschuivingMs, snelheid: snelheid);
}

/// [lijst] op de volgorde van het scherm: studio, cd, vinyl; een onbekende soort achteraan, het anker voor zijn soortgenoten.
List<VersieInfo> opVolgorde(List<VersieInfo> lijst) => [...lijst]
  ..sort((a, b) {
    final r = (a.soort == null ? 9 : soortRang(a.soort!)).compareTo(b.soort == null ? 9 : soortRang(b.soort!));
    if (r != 0) return r;
    if (a.anker != b.anker) return a.anker ? -1 : 1;
    return 0;
  });

/// Waar het moment [ankerMs] van het anker in versie [v] valt.
int plekInVersie(int ankerMs, {int? verschuivingMs, double snelheid = 1.0}) =>
    ((verschuivingMs ?? 0) + ankerMs * snelheid).round();

/// Het omgekeerde: waar het moment [versieMs] van een versie in het anker valt.
int plekInAnker(int versieMs, {int? verschuivingMs, double snelheid = 1.0}) =>
    ((versieMs - (verschuivingMs ?? 0)) / (snelheid <= 0 ? 1.0 : snelheid)).round();

/// Een anker met zijn versies.
class Versiegroep {
  Versiegroep({required this.anker, this.soort, this.persing = '', List<Versie>? versies}) : versies = versies ?? [];

  /// Het hoofdbestand, in de gewone albummap.
  String anker;

  /// Wat het anker zelf is, als dat bekend is (een oud nummer zonder soort: null — dan zegt zijn kop het).
  Kopiesoort? soort;
  String persing;
  final List<Versie> versies;

  Map<String, dynamic> toJson() => {
        'anker': anker,
        if (soort != null) 's': soort!.naam,
        if (persing.isNotEmpty) 'p': persing,
        'versies': [for (final v in versies) v.toJson()],
      };

  static Versiegroep? fromJson(Object? j) {
    if (j is! Map || j['anker'] is! String) return null;
    return Versiegroep(
      anker: j['anker'] as String,
      soort: kopiesoortUit(j['s']),
      persing: j['p'] is String ? j['p'] as String : '',
      versies: [
        for (final v in (j['versies'] as List? ?? const []))
          if (Versie.fromJson(v) case final x?) x,
      ],
    );
  }
}

String _sleutel(String pad) =>
    pad.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator).toLowerCase();

String _mapVan(String pad) {
  final s = pad.replaceAll('\\', '/');
  final i = s.lastIndexOf('/');
  return i < 0 ? '' : pad.substring(0, i);
}

/// Waar de keuze voor geldt: alleen dit nummer, of de hele plaat (alle nummers in de map van het anker).
enum VersieBereik { nummer, plaat }

/// Het register: welke bestanden versies zijn van welk anker, en welke versie je koos.
class Versieregister {
  Versieregister({String? Function()? bestand}) : _bestandPad = bestand;

  final String? Function()? _bestandPad;

  /// Anker (sleutel) → groep.
  final Map<String, Versiegroep> _groepen = {};

  /// Versiepad (sleutel) → anker (sleutel).
  final Map<String, String> _ankerVan = {};

  /// `n:<anker>` of `p:<map van het anker>` → [versieSleutel].
  final Map<String, String> _keuzes = {};

  /// Gaat omhoog bij elke wijziging: de catalogus en de schermen luisteren ernaar.
  final ValueNotifier<int> uitgave = ValueNotifier<int>(0);

  File? get _bestand {
    final p = _bestandPad?.call();
    return p == null ? null : File(p);
  }

  bool get isLeeg => _groepen.isEmpty;

  Iterable<Versiegroep> get groepen => _groepen.values;

  /// Is [pad] een versie (en dus geen nummer van de bibliotheek)?
  bool isVersie(String pad) => _ankerVan.containsKey(_sleutel(pad));

  /// Het anker waar [pad] een versie van is, of null.
  String? ankerVan(String pad) => _groepen[_ankerVan[_sleutel(pad)]]?.anker;

  Versiegroep? groep(String anker) => _groepen[_sleutel(anker)];

  /// De versies van [anker] (zonder het anker zelf), op volgorde: studio, cd, vinyl.
  List<Versie> versiesVan(String anker) {
    final g = _groepen[_sleutel(anker)];
    if (g == null) return const [];
    return [...g.versies]..sort((a, b) => soortRang(a.soort).compareTo(soortRang(b.soort)));
  }

  /// De versie op [pad], of null.
  Versie? versie(String pad) {
    final g = _groepen[_ankerVan[_sleutel(pad)]];
    if (g == null) return null;
    final k = _sleutel(pad);
    for (final v in g.versies) {
      if (_sleutel(v.pad) == k) return v;
    }
    return null;
  }

  /// [v] bewaren als versie van [anker]. Een versie die er al was op hetzelfde pad, wordt vervangen. [ankerSoort] en
  /// [ankerPersing]: wat het anker zelf is, als de aanroeper dat weet.
  void voegToe(String anker, Versie v, {Kopiesoort? ankerSoort, String? ankerPersing}) {
    final k = _sleutel(anker);
    final g = _groepen.putIfAbsent(k, () => Versiegroep(anker: anker));
    if (ankerSoort != null) g.soort = ankerSoort;
    if (ankerPersing != null) g.persing = ankerPersing;
    final vk = _sleutel(v.pad);
    // Een pad hoort bij één anker: wie het eerder als versie van een ander had, laat het los.
    final ander = _ankerVan[vk];
    if (ander != null && ander != k) _haalUitGroep(ander, vk);
    g.versies.removeWhere((x) => _sleutel(x.pad) == vk);
    g.versies.add(v);
    _ankerVan[vk] = k;
    _gewijzigd();
  }

  /// [pad] is geen versie meer (weggegooid, of zelf het anker geworden).
  Versie? verwijder(String pad) {
    final vk = _sleutel(pad);
    final ak = _ankerVan.remove(vk);
    if (ak == null) return null;
    final v = _haalUitGroep(ak, vk);
    _gewijzigd();
    return v;
  }

  Versie? _haalUitGroep(String ak, String vk) {
    final g = _groepen[ak];
    if (g == null) return null;
    Versie? weg;
    g.versies.removeWhere((x) {
      if (_sleutel(x.pad) != vk) return false;
      weg = x;
      return true;
    });
    if (g.versies.isEmpty) _groepen.remove(ak);
    return weg;
  }

  /// De uitlijning van [pad] is gemeten.
  void zetUitlijning(String pad, {required int verschuivingMs, required double snelheid}) {
    final g = _groepen[_ankerVan[_sleutel(pad)]];
    if (g == null) return;
    final i = g.versies.indexWhere((x) => _sleutel(x.pad) == _sleutel(pad));
    if (i < 0) return;
    g.versies[i] = g.versies[i].met(verschuivingMs: verschuivingMs, snelheid: snelheid);
    _gewijzigd();
  }

  /// Een ander bestand is nu het anker van de groep van [oud] — een opwaardering die op een andere plek landde (een
  /// andere extensie), of een versie die het anker werd. Een keuze voor het nummer verhuist mee.
  void verhuisAnker(String oud, String nieuw, {Kopiesoort? soort, String? persing}) {
    final ok = _sleutel(oud), nk = _sleutel(nieuw);
    final g = _groepen.remove(ok);
    if (g == null) return;
    // Was het nieuwe anker zelf een versie van deze groep, dan is het dat niet meer.
    g.versies.removeWhere((x) => _sleutel(x.pad) == nk);
    _ankerVan.remove(nk);
    g.anker = nieuw;
    if (soort != null) g.soort = soort;
    if (persing != null) g.persing = persing;
    if (g.versies.isNotEmpty) {
      final al = _groepen[nk];
      if (al != null) {
        for (final v in g.versies) {
          if (!al.versies.any((x) => _sleutel(x.pad) == _sleutel(v.pad))) al.versies.add(v);
        }
      } else {
        _groepen[nk] = g;
      }
      for (final v in g.versies) {
        _ankerVan[_sleutel(v.pad)] = nk;
      }
    }
    final keuze = _keuzes.remove('n:$ok');
    if (keuze != null) _keuzes['n:$nk'] = keuze;
    _gewijzigd();
  }

  /// Het bestand op [van] staat nu op [naar] (`_move` in organize.dart). Een versie verhuist mee, en een anker ook. Gaat
  /// het naar `_dubbel`, dan is het geen versie meer: daar staat wat verloor.
  void herNoem(String van, String naar) {
    final vk = _sleutel(van);
    if (vk == _sleutel(naar)) return;
    final weg = _ligtInDubbel(naar);
    final ak = _ankerVan[vk];
    if (ak != null) {
      if (weg) {
        verwijder(van);
        return;
      }
      final g = _groepen[ak];
      final i = g?.versies.indexWhere((x) => _sleutel(x.pad) == vk) ?? -1;
      if (g != null && i >= 0) {
        g.versies[i] = g.versies[i].met(pad: naar);
        _ankerVan.remove(vk);
        _ankerVan[_sleutel(naar)] = ak;
        _gewijzigd();
      }
      return;
    }
    // Een anker dat naar _dubbel gaat: wie het verving, heeft de groep al overgenomen ([verhuisAnker]). Zo niet, dan
    // ruimt [ruimOp] het op bij de volgende scan.
    if (_groepen.containsKey(vk) && !weg) verhuisAnker(van, naar);
  }

  static bool _ligtInDubbel(String pad) {
    final s = pad.replaceAll('\\', '/').toLowerCase();
    return s.contains('/_dubbel/');
  }

  /// Na een scan: wat niet meer bestaat eruit. [bestaat] zegt of een pad op schijf staat. Een anker dat weg is (je gooide
  /// het weg, of het verhuisde buiten de app om): de beste versie wordt het anker — anders verdwenen ze mee uit beeld.
  /// Geeft de paden terug die zo anker werden.
  List<String> ruimOp(bool Function(String pad) bestaat) {
    final nieuweAnkers = <String>[];
    var veranderd = false;
    for (final ak in _groepen.keys.toList()) {
      final g = _groepen[ak]!;
      final weg = g.versies.where((v) => !bestaat(v.pad)).toList();
      for (final v in weg) {
        g.versies.remove(v);
        _ankerVan.remove(_sleutel(v.pad));
        veranderd = true;
      }
      if (g.versies.isEmpty) {
        _groepen.remove(ak);
        veranderd = true;
        continue;
      }
      if (!bestaat(g.anker)) {
        final rest = [...g.versies]..sort((a, b) => soortRang(a.soort).compareTo(soortRang(b.soort)));
        final opvolger = rest.first;
        verhuisAnker(g.anker, opvolger.pad, soort: opvolger.soort, persing: opvolger.persing);
        nieuweAnkers.add(opvolger.pad);
        veranderd = true;
      }
    }
    if (veranderd) _gewijzigd();
    return nieuweAnkers;
  }

  // ── Keuze ──────────────────────────────────────────────────────────────

  /// Welke versie speelt voor [anker]: [sleutel] ([versieSleutel]) voor dit nummer of voor de hele plaat. Null wist de
  /// keuze (voor dat bereik).
  void kies(String anker, String? sleutel, {required VersieBereik bereik}) {
    final k = bereik == VersieBereik.nummer ? 'n:${_sleutel(anker)}' : 'p:${_sleutel(_mapVan(anker))}';
    if (sleutel == null) {
      if (_keuzes.remove(k) == null) return;
    } else {
      var veranderd = _keuzes[k] != sleutel;
      _keuzes[k] = sleutel;
      // Een keuze voor de plaat geldt voor elk nummer: een oudere keuze voor één nummer zou hem stil tegenspreken.
      if (bereik == VersieBereik.plaat) {
        final map = _sleutel(_mapVan(anker));
        final voor = _keuzes.length;
        _keuzes.removeWhere((key, _) => key.startsWith('n:') && _sleutel(_mapVan(key.substring(2))) == map);
        veranderd |= _keuzes.length != voor;
      }
      if (!veranderd) return;
    }
    _gewijzigd();
  }

  /// De keuze die voor [anker] geldt: eerst voor dit nummer, dan voor de plaat. Null: geen.
  String? keuzeVoor(String anker) =>
      _keuzes['n:${_sleutel(anker)}'] ?? _keuzes['p:${_sleutel(_mapVan(anker))}'];

  /// Waar de keuze voor [anker] vandaan komt (voor het scherm: "gekozen voor deze plaat").
  VersieBereik? bereikVan(String anker) => _keuzes.containsKey('n:${_sleutel(anker)}')
      ? VersieBereik.nummer
      : _keuzes.containsKey('p:${_sleutel(_mapVan(anker))}')
          ? VersieBereik.plaat
          : null;

  /// De versie die speelt voor [anker], of null voor het anker zelf. Een keuze die niet precies past, valt terug op een
  /// versie van dezelfde soort ("vinyl" gekozen voor de plaat, en dit nummer heeft een andere vinylpersing).
  Versie? speelVersie(String anker, {Kopiesoort? ankerSoort}) {
    final k = keuzeVoor(anker);
    final g = _groepen[_sleutel(anker)];
    if (k == null || g == null || g.versies.isEmpty) return null;
    for (final v in g.versies) {
      if (v.sleutel == k) return v;
    }
    final soort = kopiesoortUit(k.split('|').first);
    if (soort == null || soort == (ankerSoort ?? g.soort)) return null;
    for (final v in versiesVan(anker)) {
      if (v.soort == soort) return v;
    }
    return null;
  }

  // ── Bewaren ────────────────────────────────────────────────────────────

  Future<void> laad() async {
    try {
      final f = _bestand;
      if (f == null || !await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      _groepen.clear();
      _ankerVan.clear();
      _keuzes.clear();
      for (final g in (j['groepen'] as List? ?? const [])) {
        final x = Versiegroep.fromJson(g);
        if (x == null || x.versies.isEmpty) continue;
        final ak = _sleutel(x.anker);
        _groepen[ak] = x;
        for (final v in x.versies) {
          _ankerVan[_sleutel(v.pad)] = ak;
        }
      }
      final k = j['keuzes'];
      if (k is Map) {
        for (final e in k.entries) {
          if (e.value is String) _keuzes['${e.key}'] = e.value as String;
        }
      }
      uitgave.value++;
    } catch (e) {
      debugPrint('versies.json onleesbaar: $e');
    }
  }

  Timer? _bewaarKlok;

  void _gewijzigd() {
    uitgave.value++;
    if (_bestand == null) return;
    _bewaarKlok?.cancel();
    _bewaarKlok = Timer(const Duration(seconds: 2), () => unawaited(bewaarNu()));
  }

  Future<void> bewaarNu() async {
    _bewaarKlok?.cancel();
    _bewaarKlok = null;
    try {
      final f = _bestand;
      if (f == null) return;
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'versie': 1,
        'groepen': [for (final g in _groepen.values) g.toJson()],
        'keuzes': _keuzes,
      }));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('versies.json niet te bewaren: $e');
    }
  }

  @visibleForTesting
  void wis() {
    _bewaarKlok?.cancel();
    _bewaarKlok = null;
    _groepen.clear();
    _ankerVan.clear();
    _keuzes.clear();
    uitgave.value++;
  }
}

/// In een toets: dit bestand in plaats van dat in de appmap. **Zonder: in een toets niets naar schijf** (zoals
/// `soortenBestandVoorToets`).
@visibleForTesting
String? versiesBestandVoorToets;

/// Het register van deze app.
final Versieregister versies = Versieregister(bestand: () {
  if (versiesBestandVoorToets case final p?) return p;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  return '$appDir${Platform.pathSeparator}versies.json';
});
