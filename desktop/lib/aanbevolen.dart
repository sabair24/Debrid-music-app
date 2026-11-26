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

/// Zoveel nummers staan er in "Aanbevolen voor jou" (21-11-2026, Saber: *"aanbevolen mag ook 200 liedjes bevatten"*;
/// 26-11-2026: *"ik wil daar zeker 200 liedjes zien"*). Iets meer dan 200: een toestel zeeft er nog uit wat het zelf al
/// heeft, en dan blijven er toch 200.
const int kAanbevolenNummers = 240;

/// Zoveel daarvan in de rij op Start: allemaal (26-11-2026: "zeker 200" in de rij; tot dan 100, de rest onder "Alles").
const int kAanbevolenInRij = kAanbevolenNummers;

/// Hoogstens zoveel nummers van één artiest in één trekking ([trekUitVoorraad]).
const int kAanbevolenPerArtiest = 2;

/// De breedte van de voorraad (26-11-2026, `RecommendService.ontdekVoorJou`): zoveel nieuwe artiesten, met elk zoveel
/// toppers bij Deezer, en zoveel daarvan in de voorraad. Een trekking neemt er hoogstens [kAanbevolenPerArtiest] per
/// artiest; de volgende trekking zijn andere nummers. Was 150 · 8 · 3.
const int kAanbevolenKandidaten = 450;
const int kAanbevolenToppers = 12;
const int kAanbevolenVoorraadPerArtiest = 5;

/// Zoveel nummers rekent de pc op de achtergrond uit als voorraad. Zo is verversen meteen klaar, met telkens
/// [kAanbevolenNummers] die je nog niet zag ([AanbevolenVoorJou.volgende]): een berekening is een paar honderd vragen
/// aan Deezer, en dat duurt een minuut of meer — te lang om op te wachten als je omlaag trekt.
///
/// 2000 sinds 26-11-2026. Met 600 (in de praktijk ~430: de verwanten van je bovenste veertig die je nog niet hebt, zijn
/// op) stond er na elke berekening "nog 0 nieuw": na twee keer verversen had je alles gezien, en kwam hetzelfde terug.
const int kAanbevolenVoorraad = 2000;

/// Zoveel zaden per berekening, gewogen getrokken uit je bovenste [kAanbevolenPoel] artiesten. Het waren er zes uit
/// twaalf: dan zaten er bijna altijd dezelfde in, en kwam je elke dag hetzelfde tegen (Saber, 21-11-2026: *"het is elke
/// dag dezelfde"*).
///
/// 26-11-2026: veertig uit je bovenste 120 (was twintig uit veertig) — de voorraad moet breder dan je vaste kern.
const int kAanbevolenZaden = 40;
const int kAanbevolenPoel = 120;

/// Zo lang gaat een nummer dat al in de lijst stond achteraan: verversen geeft eerst wat je nog niet zag.
const Duration kAanbevolenGezien = Duration(days: 14);

/// De sleutel van een aanbevolen nummer: artiest en titel.
String aanbevolenSleutel(RecTrack t) => '${artistKey(t.artist)}|${t.title.toLowerCase().trim()}';

/// De kandidaten evenredig over de zaden: elk zaad krijgt een gelijk deel ([aantal] / zaden), en de lijst wisselt om de
/// beurt van zaad.
///
/// **Waarom (Saber, 21-11-2026).** *"aanbevolen, zit vol met enkel rai of arabische muziek, wat mag maar dit is veel te
/// veel"*. Zijn zaden waren vooral pop (Michael Jackson, Whitney Houston, Adele), maar van die artiesten heeft hij de
/// verwanten bij Deezer bijna allemaal al — en wat je al hebt valt weg. Van Khaled had hij de verwanten nog niet, en dus
/// bleef alleen raï over. Gekozen: "Evenredig met wat ik draai".
///
/// Een kandidaat telt bij het zaad dat hem noemt en nog het minst heeft. Heeft een zaad te weinig, dan vult de rest op
/// score aan tot [aantal] — liever een volle lijst dan een lege plek.
List<Kandidaat> verdeelOverZaden(List<Kandidaat> rang, {required List<String> zaden, required int aantal}) {
  if (zaden.isEmpty) return rang.take(aantal).toList();
  final quotum = (aantal / zaden.length).ceil();
  final perZaad = {for (final z in zaden) z: <Kandidaat>[]};
  final gekozen = <int>{};
  for (final k in rang) {
    String? beste;
    for (final z in k.via) {
      final l = perZaad[z];
      if (l == null || l.length >= quotum) continue;
      if (beste == null || l.length < perZaad[beste]!.length) beste = z;
    }
    if (beste == null) continue;
    perZaad[beste]!.add(k);
    gekozen.add(k.id);
  }
  final uit = <Kandidaat>[];
  for (var i = 0; i < quotum && uit.length < aantal; i++) {
    for (final z in zaden) {
      final l = perZaad[z]!;
      if (i < l.length && uit.length < aantal) uit.add(l[i]);
    }
  }
  for (final k in rang) {
    if (uit.length >= aantal) break;
    if (gekozen.add(k.id)) uit.add(k);
  }
  return uit;
}

/// Een trekking van [aantal] uit de voorraad: eerst wat de laatste [kAanbevolenGezien] niet in de lijst stond, in de
/// volgorde van de voorraad (die wisselt al om de beurt van zaad); is dat te weinig, dan aangevuld met wat het langst
/// geleden getoond werd. Hoogstens [perArtiest] per artiest: een toestel toont er ook niet meer, en anders bleef er van
/// 200 minder over.
List<RecTrack> trekUitVoorraad(List<RecTrack> voorraad, Map<String, int> getoondOp,
    {required int aantal, required int nuMs, int perArtiest = kAanbevolenPerArtiest}) {
  bool vers(RecTrack t) {
    final ms = getoondOp[aanbevolenSleutel(t)];
    return ms == null || nuMs - ms > kAanbevolenGezien.inMilliseconds;
  }

  final uit = <RecTrack>[];
  final perA = <String, int>{};
  final gekozen = <String>{};
  void neem(RecTrack t) {
    final k = artistKey(t.artist);
    if ((perA[k] ?? 0) >= perArtiest || !gekozen.add(aanbevolenSleutel(t))) return;
    perA[k] = (perA[k] ?? 0) + 1;
    uit.add(t);
  }

  for (final t in voorraad) {
    if (uit.length >= aantal) break;
    if (vers(t)) neem(t);
  }
  if (uit.length < aantal) {
    final oud = [for (final t in voorraad) if (!vers(t)) t]
      ..sort((a, b) => (getoondOp[aanbevolenSleutel(a)] ?? 0).compareTo(getoondOp[aanbevolenSleutel(b)] ?? 0));
    for (final t in oud) {
      if (uit.length >= aantal) break;
      neem(t);
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
      if (t.deezerId != 0) 'deezerId': t.deezerId,
      if (t.preview != null) 'preview': t.preview,
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
      artistId: n(j['artistId']),
      deezerId: n(j['deezerId']),
      preview: j['preview'] is String ? j['preview'] as String : null);
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

  /// De voorraad van de laatste berekening ([kAanbevolenVoorraad]), en wanneer elk nummer voor het eerst in de lijst
  /// stond ([kAanbevolenGezien]).
  List<RecTrack> _voorraad = const [];
  final Map<String, int> _getoond = {};

  bool get verouderd =>
      _lijst == null || klok().millisecondsSinceEpoch - _lijst!.berekendMs > houdbaar.inMilliseconds;
  bool get bezig => _bezig != null;

  /// Hoeveel nummers van de voorraad je nog niet zag.
  int get nogVers {
    final nuMs = klok().millisecondsSinceEpoch;
    return _voorraad.where((t) {
      final ms = _getoond[aanbevolenSleutel(t)];
      return ms == null || nuMs - ms > kAanbevolenGezien.inMilliseconds;
    }).length;
  }

  Future<void> laad() async {
    try {
      if (await bestand.exists()) {
        final j = jsonDecode(await bestand.readAsString());
        _lijst = AanbevolenLijst.fromJson(j);
        if (j is Map) {
          _voorraad = [for (final t in (j['voorraad'] as List? ?? const [])) ?recTrackUitJson(t)];
          final g = j['getoond'];
          if (g is Map) {
            for (final e in g.entries) {
              if (e.value is num) _getoond['${e.key}'] = (e.value as num).toInt();
            }
          }
        }
      }
    } catch (_) {/* kapot of oud: dan rekenen we opnieuw */}
  }

  void start({Duration eerst = const Duration(seconds: 60)}) {
    _klokje?.cancel();
    Timer(eerst, () {
      if (verouderd) {
        unawaited(ververs());
      } else if (_voorraad.length < kAanbevolenVoorraad ~/ 2) {
        // Een smalle voorraad van vóór 26-11-2026 (~430): meteen een brede, en de lijst die er staat blijft.
        unawaited(ververs(bijvullen: true));
      }
    });
    _klokje = Timer.periodic(houdbaar, (_) => unawaited(ververs()));
  }

  void stop() => _klokje?.cancel();

  /// Rekent opnieuw; loopt er al een berekening, dan wacht deze daarop. [bijvullen]: alleen de voorraad aanvullen, de
  /// lijst die er staat (net getrokken bij een ververs) blijft — anders kreeg je na een minuut een andere, en telde alles
  /// daarin als gezien zonder dat iemand het zag.
  Future<AanbevolenLijst?> ververs({bool bijvullen = false}) {
    final lopend = _bezig;
    if (lopend != null) return lopend;
    final werk = _reken(bijvullen: bijvullen);
    _bezig = werk;
    return werk.whenComplete(() {
      _bezig = null;
    });
  }

  /// Verversen (omlaag trekken): meteen [kAanbevolenNummers] nummers uit de voorraad die je nog niet zag (Saber,
  /// 21-11-2026: *"ik wil als ik ververs elke keer nieuwe liedjes"*). Raakt de voorraad op, dan rekent de pc op de
  /// achtergrond een nieuwe, met andere zaden. Nog geen voorraad: dan wel wachten op een berekening.
  Future<AanbevolenLijst?> volgende() async {
    if (_voorraad.isEmpty) return ververs();
    await _trek(klok());
    if (nogVers < kAanbevolenNummers && _bezig == null) unawaited(ververs(bijvullen: true));
    log?.call('aanbevolen: ververst — ${_lijst?.nummers.length ?? 0} nummers, nog $nogVers nieuw in de voorraad');
    return _lijst;
  }

  /// Alleen de voorraad bewaren, bij de lijst die er staat.
  Future<void> _bewaarVoorraad() async {
    final l = _lijst;
    if (l == null) return;
    try {
      await bestand.writeAsString(jsonEncode({
        ...l.toJson(),
        'voorraad': [for (final t in _voorraad) recTrackNaarJson(t)],
        'getoond': _getoond,
      }));
    } catch (_) {}
  }

  /// Een nieuwe trekking uit de voorraad, als lijst, en bewaren.
  Future<void> _trek(DateTime nu) async {
    final nuMs = nu.millisecondsSinceEpoch;
    _getoond.removeWhere((_, ms) => nuMs - ms > kAanbevolenGezien.inMilliseconds);
    final nummers = trekUitVoorraad(_voorraad, _getoond, aantal: kAanbevolenNummers, nuMs: nuMs);
    for (final t in nummers) {
      _getoond.putIfAbsent(aanbevolenSleutel(t), () => nuMs);
    }
    _lijst = AanbevolenLijst(nuMs, nummers);
    try {
      await bestand.writeAsString(jsonEncode({
        ..._lijst!.toJson(),
        'voorraad': [for (final t in _voorraad) recTrackNaarJson(t)],
        'getoond': _getoond,
      }));
    } catch (_) {}
  }

  Future<AanbevolenLijst?> _reken({bool bijvullen = false}) async {
    final t0 = DateTime.now();
    final nu = klok();
    final alle = artiesten();
    if (alle.isEmpty) {
      log?.call('aanbevolen: nog geen bibliotheek — over twee minuten opnieuw');
      Timer(const Duration(minutes: 2), () => unawaited(ververs()));
      return _lijst;
    }
    final zaden = kiesZaden(alle,
        nuMs: nu.millisecondsSinceEpoch, groen: groen(), aantal: kAanbevolenZaden, poel: kAanbevolenPoel);
    try {
      final voorraad = await zoeker(zaden, bezit());
      // Niets gevonden is geen beter antwoord dan wat er lag.
      if (voorraad.isEmpty && _lijst != null) {
        log?.call('aanbevolen: niets gevonden — de vorige lijst blijft');
        return _lijst;
      }
      _voorraad = voorraad;
      if (bijvullen && _lijst != null) {
        await _bewaarVoorraad();
      } else {
        await _trek(nu);
      }
      log?.call('aanbevolen: ${_lijst!.nummers.length} nummers (voorraad ${voorraad.length}, nog $nogVers nieuw) uit '
          '${zaden.length} zaden: ${zaden.map((z) => z.naam).join(', ')} '
          'in ${DateTime.now().difference(t0).inMilliseconds} ms');
      return _lijst;
    } catch (e) {
      log?.call('aanbevolen: mislukt na ${DateTime.now().difference(t0).inMilliseconds} ms — $e');
      return _lijst;
    }
  }
}
