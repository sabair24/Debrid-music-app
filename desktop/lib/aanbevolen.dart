/// "Aanbevolen voor jou": nieuwe muziek die past bij wat je echt draait, en meteen op het scherm.
///
/// **Waarom dit opnieuw moest.** Saber, 16-10-2026, over deze rij: *"Laadt heel traag, en moet iets
/// meer relevant zijn met men muziek, en ik wil nieuwe muziek ontdekken."* Gemeten in de code:
/// - **traag:** zes artiesten werden NA ELKAAR opgezocht, elk met vier vragen voor toppers erachter, en
///   er werd niets bewaard — na elke koude start begon het opnieuw, op de gsm zelf;
/// - **niet relevant:** de zes waren willekeurig uit de bibliotheek, en van hun verwante artiesten werden
///   er vier willekeurig gekozen. Wat je draait of groen gaf telde niet;
/// - **geen ontdekking:** een artiest die je al had kon er gewoon in staan, met een remix.
///
/// Nu:
/// - de pc rekent op de achtergrond en bewaart (`aanbevolen.json`); een toestel krijgt het via
///   `/api/aanbevolen`, en toont tot dan wat het vorige keer kreeg;
/// - zaden op [relevantie] (beurten, recent gedraaid) plus groene duimen, een gewogen trekking uit de
///   bovenste twaalf zodat verversen iets anders geeft;
/// - kandidaten scoren op hoeveel van JOUW artiesten ze als verwant noemen, en hoe hoog; wat je al hebt
///   valt weg;
/// - per kandidaat zijn bekendste nummers, zonder remix, live of edit, hoogstens twee per artiest, om
///   de beurt over de artiesten verdeeld.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'nieuwe_releases.dart' show EigenArtiest, relevantie;
import 'organize.dart' show artistKey, versionMarkers;
import 'recommend.dart' show RecTrack;

/// Eén zaad: een artiest van jou, met hoe zwaar hij meetelt.
typedef Zaad = ({String naam, double gewicht});

/// De zaden: je artiesten op [relevantie], groen geeft er [kGroenBonus] bij. Uit de bovenste
/// [poel] worden er [aantal] gewogen getrokken: de zwaarste vaker, maar niet altijd dezelfde.
List<Zaad> kiesZaden(List<EigenArtiest> artiesten,
    {required int nuMs, Set<String> groen = const {}, int aantal = 6, int poel = 12, math.Random? toeval}) {
  final gewogen = [
    for (final a in artiesten)
      (naam: a.naam, gewicht: relevantie(a, nuMs: nuMs) + (groen.contains(artistKey(a.naam)) ? kGroenBonus : 0)),
  ]..sort((a, b) {
      final v = b.gewicht.compareTo(a.gewicht);
      return v != 0 ? v : a.naam.compareTo(b.naam);
    });
  final kandidaten = [for (final z in gewogen.take(poel)) if (z.gewicht > 0) z];
  if (kandidaten.length <= aantal) return kandidaten;
  final r = toeval ?? math.Random();
  final uit = <Zaad>[];
  final rest = [...kandidaten];
  while (uit.length < aantal && rest.isNotEmpty) {
    final totaal = rest.fold<double>(0, (s, z) => s + z.gewicht);
    var trek = r.nextDouble() * totaal;
    var i = 0;
    for (; i < rest.length - 1; i++) {
      trek -= rest[i].gewicht;
      if (trek <= 0) break;
    }
    uit.add(rest.removeAt(i));
  }
  return uit;
}

/// Wat een groene duim bij een artiest optelt: zoveel als ongeveer drie keer zo vaak gedraaid.
const double kGroenBonus = 3;

/// Een artiest die je nog niet hebt, met waarom hij erin staat.
typedef Kandidaat = ({int id, String naam, double score, List<String> via});

/// De verwante artiesten van alle zaden samen, gerangschikt.
///
/// Elk zaad geeft zijn verwanten punten naar hun plek in zijn lijst (de eerste het meest) maal zijn
/// gewicht. Een artiest die door meer van jouw artiesten genoemd wordt, krijgt daar per extra zaad de
/// helft bovenop: "verwant aan drie van je artiesten" zegt meer dan "aan één". Wat je al hebt, en de
/// zaden zelf, vallen weg — dit is om te ontdekken.
List<Kandidaat> rangschikKandidaten(Map<String, List<({int id, String naam})>> verwantVan,
    {required Map<String, double> gewicht, required Set<String> bezit}) {
  final score = <int, double>{};
  final naam = <int, String>{};
  final via = <int, List<String>>{};
  final zaadSleutels = {for (final z in verwantVan.keys) artistKey(z)};
  for (final e in verwantVan.entries) {
    final w = gewicht[e.key] ?? 1;
    for (var i = 0; i < e.value.length; i++) {
      final a = e.value[i];
      final k = artistKey(a.naam);
      if (a.id <= 0 || k.isEmpty || bezit.contains(k) || zaadSleutels.contains(k)) continue;
      score[a.id] = (score[a.id] ?? 0) + w * (1 - i / 25);
      naam[a.id] = a.naam;
      (via[a.id] ??= []).add(e.key);
    }
  }
  final uit = [
    for (final id in score.keys)
      (id: id, naam: naam[id]!, score: score[id]! * (1 + .5 * (via[id]!.length - 1)), via: via[id]!),
  ]..sort((a, b) {
      final v = b.score.compareTo(a.score);
      return v != 0 ? v : a.naam.compareTo(b.naam);
    });
  return uit;
}

/// Is dit een nummer om iemand mee kennis te laten maken?
///
/// Geen remix, live, edit of karaoke (de versiewoorden van de zeef), en ook geen andere versie tussen
/// haakjes: gemeten op 16-10-2026 kwam "Moves Like Jagger (Studio Recording From "The Voice"
/// Performance)" erdoor. Een ondertitel blijft wel: "Stronger (What Doesn't Kill You)" ÍS de titel.
/// Geen intro, niet korter dan anderhalve minuut, en kerstnummers pas vanaf half november.
bool goedOmTeOntdekken(RecTrack t, {DateTime? nu}) {
  if (versionMarkers(t.title).isNotEmpty) return false;
  for (final m in _haakjes.allMatches(t.title)) {
    if (_versieTussenHaakjes.hasMatch(m[1]!)) return false;
  }
  if (_geenNummer.hasMatch(t.title)) return false;
  final d = nu ?? DateTime.now();
  final kerst = (d.month == 11 && d.day >= 15) || d.month == 12;
  if (!kerst && _kerst.hasMatch(t.title)) return false;
  return t.seconds == 0 || t.seconds >= 90;
}

final _haakjes = RegExp(r'[(\[]([^)\]]*)[)\]]');
final _versieTussenHaakjes = RegExp(
    r'\b(recording|performance|version|remaster(ed)?|mix|edit|live|session|demo|acoustic|instrumental|'
    r'karaoke|cover|tribute|sped|slowed|reverb|nightcore|from the|soundtrack)\b',
    caseSensitive: false);
final _geenNummer = RegExp(r'^\s*(intro|outro|interlude|skit)\b', caseSensitive: false);
final _kerst = RegExp(r'\b(christmas|xmas|kerst\w*|noël|noel)\b', caseSensitive: false);

/// De nummers: per kandidaat (in volgorde van score) zijn bekendste geschikte nummers, hoogstens
/// [perArtiest], om de beurt — eerst één van elke kandidaat, dan een tweede — tot [max].
List<RecTrack> kiesNummers(List<({Kandidaat kandidaat, List<RecTrack> toppers})> perKandidaat,
    {int max = 15, int perArtiest = 2, DateTime? nu}) {
  final rijen = [
    for (final p in perKandidaat)
      ([...p.toppers.where((t) => goedOmTeOntdekken(t, nu: nu))]..sort((a, b) => b.rank.compareTo(a.rank))).take(perArtiest).toList(),
  ];
  final uit = <RecTrack>[];
  final gezien = <String>{};
  for (var ronde = 0; ronde < perArtiest && uit.length < max; ronde++) {
    for (final r in rijen) {
      if (uit.length >= max) break;
      if (ronde >= r.length) continue;
      final t = r[ronde];
      if (gezien.add('${artistKey(t.artist)}|${t.title.toLowerCase()}')) uit.add(t);
    }
  }
  return uit;
}

/// Wat er bewaard wordt: de lijst en wanneer hij berekend is.
class AanbevolenLijst {
  const AanbevolenLijst(this.berekendMs, this.nummers);
  final int berekendMs;
  final List<RecTrack> nummers;

  static const versie = 1;

  Map<String, dynamic> toJson() => {
        'versie': versie,
        'berekendMs': berekendMs,
        'nummers': [for (final t in nummers) recTrackNaarJson(t)],
      };

  static AanbevolenLijst? fromJson(Object? j) {
    if (j is! Map || j['versie'] != versie) return null;
    final ms = (j['berekendMs'] as num?)?.toInt();
    if (ms == null) return null;
    return AanbevolenLijst(ms, [for (final t in (j['nummers'] as List? ?? const [])) ?recTrackUitJson(t)]);
  }
}

Map<String, dynamic> recTrackNaarJson(RecTrack t) => {
      'artist': t.artist,
      'title': t.title,
      if (t.cover != null) 'cover': t.cover,
      if (t.album.isNotEmpty) 'album': t.album,
      if (t.albumId != 0) 'albumId': t.albumId,
      if (t.seconds != 0) 'seconds': t.seconds,
      if (t.rank != 0) 'rank': t.rank,
      if (t.artistId != 0) 'artistId': t.artistId,
    };

RecTrack? recTrackUitJson(Object? j) {
  if (j is! Map) return null;
  final artiest = j['artist'], titel = j['title'];
  if (artiest is! String || titel is! String || titel.isEmpty) return null;
  int n(Object? v) => (v as num?)?.toInt() ?? 0;
  return RecTrack(artiest, titel, j['cover'] as String?,
      album: (j['album'] as String?) ?? '',
      albumId: n(j['albumId']),
      seconds: n(j['seconds']),
      rank: n(j['rank']),
      artistId: n(j['artistId']));
}

/// Hoe de kandidaten en hun nummers gevonden worden — Deezer in de app, een nep in de toets.
typedef OntdekZoeker = Future<List<RecTrack>> Function(List<Zaad> zaden, Set<String> bezit);

/// De dienst op de pc: rekent op de achtergrond, bewaart, en geeft meteen wat er ligt.
class AanbevolenVoorJou {
  AanbevolenVoorJou({
    required this.zoeker,
    required this.artiesten,
    required this.groen,
    required this.bezit,
    required this.bestand,
    this.log,
    DateTime Function()? klok,
  }) : klok = klok ?? DateTime.now;

  /// De dienst van deze pc, als die er is. Zie `server.dart` (`/api/aanbevolen`) en de startpagina.
  static AanbevolenVoorJou? pc;

  final OntdekZoeker zoeker;
  final List<EigenArtiest> Function() artiesten;
  final Set<String> Function() groen;
  final Set<String> Function() bezit;
  final File bestand;
  final void Function(String regel)? log;
  final DateTime Function() klok;

  static const houdbaar = Duration(hours: 6);

  AanbevolenLijst? _lijst;
  AanbevolenLijst? get lijst => _lijst;
  Future<AanbevolenLijst?>? _bezig;
  Timer? _klokje;

  bool get verouderd =>
      _lijst == null || klok().millisecondsSinceEpoch - _lijst!.berekendMs > houdbaar.inMilliseconds;
  bool get bezig => _bezig != null;

  Future<void> laad() async {
    try {
      if (await bestand.exists()) _lijst = AanbevolenLijst.fromJson(jsonDecode(await bestand.readAsString()));
    } catch (_) {/* kapot of oud: dan rekenen we opnieuw */}
  }

  void start({Duration eerst = const Duration(seconds: 60)}) {
    _klokje?.cancel();
    Timer(eerst, () {
      if (verouderd) unawaited(ververs());
    });
    _klokje = Timer.periodic(houdbaar, (_) => unawaited(ververs()));
  }

  void stop() => _klokje?.cancel();

  /// Rekent opnieuw; loopt er al een berekening, dan wacht deze daarop.
  Future<AanbevolenLijst?> ververs() {
    final lopend = _bezig;
    if (lopend != null) return lopend;
    final werk = _reken();
    _bezig = werk;
    return werk.whenComplete(() {
      _bezig = null;
    });
  }

  Future<AanbevolenLijst?> _reken() async {
    final t0 = DateTime.now();
    final nu = klok();
    final alle = artiesten();
    if (alle.isEmpty) {
      log?.call('aanbevolen: nog geen bibliotheek — over twee minuten opnieuw');
      Timer(const Duration(minutes: 2), () => unawaited(ververs()));
      return _lijst;
    }
    final zaden = kiesZaden(alle, nuMs: nu.millisecondsSinceEpoch, groen: groen());
    try {
      final nummers = await zoeker(zaden, bezit());
      // Niets gevonden is geen beter antwoord dan wat er lag.
      if (nummers.isEmpty && _lijst != null) {
        log?.call('aanbevolen: niets gevonden — de vorige lijst blijft');
        return _lijst;
      }
      final l = AanbevolenLijst(nu.millisecondsSinceEpoch, nummers);
      _lijst = l;
      await bestand.writeAsString(jsonEncode(l.toJson()));
      log?.call('aanbevolen: ${nummers.length} nummers uit ${zaden.map((z) => z.naam).join(', ')} '
          'in ${DateTime.now().difference(t0).inMilliseconds} ms');
      return l;
    } catch (e) {
      log?.call('aanbevolen: mislukt na ${DateTime.now().difference(t0).inMilliseconds} ms — $e');
      return _lijst;
    }
  }
}
