/// "Nieuwe release": wat er de laatste drie maanden echt verscheen bij de artiesten die je draait.
///
/// **Waarom dit opnieuw moest.** Saber op 15-10-2026: *"is niet relevant met mijn artisten of
/// nummers, is niet altijd nieuw ??? Te weinig, laadt heel traag."* Nagespeeld op zijn bibliotheek:
///
/// * **Niet relevant.** De balk nam bij elke start twaalf WILLEKEURIGE artiesten uit 406 — Kim Carnes,
///   ICE MC, Kaoma, artiesten die hij twee keer draaide. Wie hij echt draait (Britney Spears, David
///   Guetta, Dua Lipa) kwam er alleen bij toeval in.
/// * **De verkeerde artiest.** "Predator" werd een metalband; zijn Predator is één gabbernummer.
/// * **Niet nieuw.** "Nieuw" was "dit kalenderjaar", en heruitgaven telden mee: *This Is Acting (10th
///   Anniversary Edition)*, *ReVivo: Los Hits*, de soundtrack van *The Devil Wears Prada 2*.
/// * **Te weinig.** Alleen albums; bij zijn artiesten is het meeste nieuwe een single.
/// * **Traag.** De balk wachtte op álle rijen van de startpagina, ook op de AI. Deezer zelf antwoordt
///   in een mediaan van 144 ms.
///
/// **Wat Saber koos:** heruitgaven weglaten, singles meetellen, aangekondigde platen tonen.
///
/// **Hoe het nu gaat.** De artiesten op beurten, recentheid en bezit (de bovenste veertig); elke
/// artiest bij Deezer pas na bewijs dat het dezelfde is (hij deelt een plaat of een nummer met wat jij
/// van hem hebt); dan alles van de laatste 90 dagen en wat binnen 45 dagen verschijnt, zonder
/// heruitgaven, verzamelaars, soundtracks en archief. Remixen van één single vallen onder die single.
/// Hoogstens twee per artiest, hoogstens vijftien in totaal. Is het er minder dan tien, dan aangevuld tot
/// twaalf met nieuwe muziek van verwante artiesten — met erbij op wie ze lijken. Nooit een algemene
/// hitlijst. (Gemeten op de eigen bibliotheek, 15-10-2026: negen echte nieuwe uitgaven van de veertig
/// meest gedraaide artiesten.)
///
/// Op de pc berekend en bewaard (`nieuwe_releases.json`), elke zes uur opnieuw; een toestel krijgt de
/// lijst in één vraag van de pc. Zie [NieuweReleases].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'catalog.dart';
import 'organize.dart' show artistKey, normKey, versionMarkers, withoutVersionText;
import 'startrijen.dart' show bezitssleutel, zonderHerlevering;

// ── Wie ────────────────────────────────────────────────────────────────────

/// Eén artiest zoals jouw bibliotheek hem kent.
class EigenArtiest {
  final String naam;
  final int beurten;
  final int laatstMs;
  final int nummers;

  /// Albumtitels en nummertitels, gevouwen — om bij Deezer de juiste naamgenoot te herkennen.
  final Set<String> albums;
  final Set<String> titels;

  /// Het vroegste jaar per nummertitel, waar de tags het zeggen. Zie [kiesUitgaven]: "We Found Love
  /// (Extended Version)" van september 2026 is een nummer uit 2011.
  final Map<String, int> titelJaar;

  const EigenArtiest({
    required this.naam,
    this.beurten = 0,
    this.laatstMs = 0,
    this.nummers = 0,
    this.albums = const {},
    this.titels = const {},
    this.titelJaar = const {},
  });
}

/// Eén nummer uit de bibliotheek, zoals [eigenArtiesten] het nodig heeft.
class EigenNummer {
  final String artiest, album, titel;
  final int beurten, laatstMs;
  final int? jaar;
  const EigenNummer({
    required this.artiest,
    this.album = '',
    required this.titel,
    this.beurten = 0,
    this.laatstMs = 0,
    this.jaar,
  });
}

/// De hoofdartiest, zonder gasten: "Lil' Kim feat. Phil Collins" → "Lil' Kim". Niet op "&": "Simon &
/// Garfunkel" is één act.
String hoofdartiest(String artiest) => artiest
    .split(RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+|\s*[\(\[](?:feat\.?|ft\.?|featuring)\s',
        caseSensitive: false))
    .first
    .trim();

/// Zonder "(feat. Calvin Harris)": de gasten maken het geen ander nummer, en de ene bron noemt ze wel
/// en de andere niet.
String _zonderGasten(String s) =>
    s.replaceAll(RegExp(r'\s*[\(\[](feat\.?|ft\.?|featuring|with)\s[^\)\]]*[\)\]]', caseSensitive: false), ' ');

/// Een titel om op te vergelijken: zonder versie, zonder gasten, zonder "(Deluxe Edition)", gevouwen.
String vergelijkTitel(String titel) {
  var t = withoutVersionText(_zonderGasten(titel));
  t = t.replaceAll(
      RegExp(r'\s*[\(\[][^\)\]]*(deluxe|edition|remaster|expanded|anniversary|bonus|version)[^\)\]]*[\)\]]',
          caseSensitive: false),
      ' ');
  t = t.replaceAll(RegExp(r'\s+-\s+(single|ep)\s*$', caseSensitive: false), ' ');
  return normKey(t);
}

/// Wat de bibliotheek over elke artiest weet. [overslaan] houdt "Various Artists" en dergelijke weg.
List<EigenArtiest> eigenArtiesten(
  Iterable<EigenNummer> nummers, {
  bool Function(String artiest)? overslaan,
}) {
  final per = <String,
      ({String naam, int beurten, int laatstMs, int nummers, Set<String> albums, Set<String> titels, Map<String, int> jaren})>{};
  final spelling = <String, Map<String, int>>{};
  for (final n in nummers) {
    final naam = hoofdartiest(n.artiest);
    if (naam.isEmpty || (overslaan?.call(naam) ?? false)) continue;
    final k = artistKey(naam);
    if (k.isEmpty) continue;
    (spelling[k] ??= {})[naam] = (spelling[k]![naam] ?? 0) + 1;
    final oud = per[k];
    final albums = oud?.albums ?? <String>{};
    final titels = oud?.titels ?? <String>{};
    final jaren = oud?.jaren ?? <String, int>{};
    if (n.album.trim().isNotEmpty) albums.add(vergelijkTitel(n.album));
    if (n.titel.trim().isNotEmpty) {
      final t = vergelijkTitel(n.titel);
      titels.add(t);
      final j = n.jaar;
      if (j != null && j > 1900 && (jaren[t] == null || j < jaren[t]!)) jaren[t] = j;
    }
    per[k] = (
      naam: naam,
      beurten: (oud?.beurten ?? 0) + n.beurten,
      laatstMs: math.max(oud?.laatstMs ?? 0, n.laatstMs),
      nummers: (oud?.nummers ?? 0) + 1,
      albums: albums,
      titels: titels,
      jaren: jaren,
    );
  }
  return [
    for (final e in per.entries)
      EigenArtiest(
        // De spelling die het vaakst voorkomt.
        naam: (spelling[e.key]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key,
        beurten: e.value.beurten,
        laatstMs: e.value.laatstMs,
        nummers: e.value.nummers,
        albums: e.value.albums..remove(''),
        titels: e.value.titels..remove(''),
        titelJaar: e.value.jaren..remove(''),
      ),
  ];
}

/// Hoe zwaar een artiest weegt: beurten tellen dubbel, bezit telt, en wie je de laatste dertig dagen
/// draaide krijgt er twee bij. Logaritmisch, zodat duizend beurten van één artiest de rest niet
/// wegdrukken.
double relevantie(EigenArtiest a, {required int nuMs}) {
  double log2(num x) => math.log(x) / math.ln2;
  final recent = a.laatstMs > 0 && nuMs - a.laatstMs < const Duration(days: 30).inMilliseconds;
  return 2 * log2(1 + a.beurten) + log2(1 + a.nummers) + (recent ? 2 : 0);
}

/// De bovenste [max] artiesten op [relevantie]. Bij gelijke stand op naam, zodat de lijst niet per
/// berekening van volgorde wisselt.
List<EigenArtiest> relevanteArtiesten(List<EigenArtiest> alle, {required int nuMs, int max = 40}) {
  final r = {for (final a in alle) a: relevantie(a, nuMs: nuMs)};
  final uit = [...alle]..sort((a, b) {
      final v = r[b]!.compareTo(r[a]!);
      return v != 0 ? v : a.naam.compareTo(b.naam);
    });
  return uit.take(max).toList();
}

/// Is deze Deezer-artiest dezelfde als de jouwe? Hij moet een plaat of een nummer delen met wat jij
/// van hem hebt. Een naamgenoot deelt niets — dat is precies hoe "Predator" een metalband werd.
bool zelfdeArtiest(EigenArtiest eigen, {Iterable<String> albums = const [], Iterable<String> titels = const []}) {
  for (final a in albums) {
    if (eigen.albums.contains(vergelijkTitel(a))) return true;
  }
  for (final t in titels) {
    if (eigen.titels.contains(vergelijkTitel(t))) return true;
  }
  return false;
}

// ── Wat ────────────────────────────────────────────────────────────────────

enum UitgaveSoort { album, ep, single }

UitgaveSoort soortVan(String recordType) => switch (recordType.toLowerCase()) {
      'single' => UitgaveSoort.single,
      'ep' => UitgaveSoort.ep,
      _ => UitgaveSoort.album,
    };

/// Waarom een uitgave GEEN nieuwe muziek is, of null als hij dat wel is.
///
/// Gemeten op 15-10-2026 bij Deezer: "WH1TNEY (Expanded Edition)", "B'DAY (20th ANNIVERSARY DELUXE
/// EDITION)", "ReVivo: Los Hits", "Careless Whisper (Live in Paris, 1988)", "The Roof Is Leaking (Live
/// at the Secret Policeman's Other Ball, London, 1981)", "Tomorrow Never Knows (Outtake)". Een live-
/// opname ZONDER oud jaartal ("The Night Watch (Live at the Rijksmuseum)") blijft: die kan nieuw zijn.
String? geenNieuweMuziek(String titel, {required String recordType, required int jaar}) {
  final t = titel.toLowerCase();
  if (recordType.toLowerCase() == 'compile') return 'verzamelaar';
  if (RegExp(r'\b(anniversary|jubil\w*|deluxe|expanded|remaster(ed)?|re-?issue|edition|collector)\b').hasMatch(t)) {
    return 'heruitgave';
  }
  if (RegExp(r"\b(greatest|biggest|best|los|all the|the) hits\b|\bbest of\b|\bthe very best\b|\bcollection\b|"
          r'\bessentials?\b|\banthology\b|\bgrandes [eé]xitos\b|\bgold(en)? hits\b|'
          // "The Early Dancehall Years" (Beenie Man, 2026) en een jaarbereik als "(1990-2003)".
          r'\bthe early\b|\bearly years\b|(?<!\d)(19|20)\d\d\s*[-–]\s*(19|20)\d\d(?!\d)')
      .hasMatch(t)) {
    return 'verzamelaar';
  }
  if (RegExp(r'\b(soundtrack|motion picture|music from|original score|banda sonora|o\.s\.t\.?)\b').hasMatch(t)) {
    return 'soundtrack';
  }
  if (RegExp(r'\b(outtakes?|demos?|previously unreleased|from the vaults|rarities|b-sides)\b').hasMatch(t)) {
    return 'archief';
  }
  if (RegExp(r'\b(karaoke|instrumental versions?|in the style of|tribute to)\b').hasMatch(t)) {
    return 'karaoke';
  }
  if (RegExp(r'\blive\b').hasMatch(t)) {
    for (final m in RegExp(r'(?<!\d)(19[5-9]\d|20[0-4]\d)(?!\d)').allMatches(t)) {
      if (int.parse(m.group(1)!) <= jaar - 2) return 'archief';
    }
  }
  return null;
}

/// De titel waaronder remixen van één single samenvallen: "Sad Girls (Extended Mix)" en "MORNING DEW
/// (DONK) REMIX PACK" horen bij "Sad Girls" en "MORNING DEW (DONK)".
String uitgaveBasis(String titel) {
  var t = _zonderGasten(titel).trim().replaceAll(
      RegExp(r'\s*[-–]?\s*\b(the\s+)?(remix(es)?\s*(pack|ep)?|remixed|extended( mix)?|radio edit|versions)\s*$',
          caseSensitive: false),
      '');
  // Ook "- The EP": "Songs In The Key Of Life - The EP" (2026) is de plaat uit 1976.
  t = t.replaceAll(RegExp(r'\s+-\s+(the\s+)?(single|ep)\s*$', caseSensitive: false), '');
  return normKey(withoutVersionText(t));
}

/// Is dit een remix, een extended of een remixpakket — en niet de single zelf?
bool isRemixUitgave(String titel) =>
    versionMarkers(titel).isNotEmpty ||
    RegExp(r'\b(remix(es)?|remixed)\s*(pack|ep)?\s*$|\bextended\b', caseSensitive: false).hasMatch(titel);

/// Eén tegel in de balk.
class NieuweUitgave {
  final CatalogAlbum album;
  final String artiest;

  /// Op wie dit lijkt, als het van een verwante artiest komt en niet van een van de jouwe.
  final String? lijktOp;

  /// Hoeveel remixen of versies van deze single er nog meer uitkwamen.
  final int remixen;

  final double score;

  const NieuweUitgave({
    required this.album,
    required this.artiest,
    this.lijktOp,
    this.remixen = 0,
    this.score = 0,
  });

  CatalogAlbumHit get hit => CatalogAlbumHit(album, artiest);
  UitgaveSoort get soort => soortVan(album.recordType);
  DateTime? get datum => DateTime.tryParse(album.releaseDate ?? '');

  Map<String, dynamic> toJson() => {
        'id': album.id,
        'titel': album.title,
        'hoes': album.cover,
        'datum': album.releaseDate,
        'nummers': album.trackCount,
        'soort': album.recordType,
        'artiest': artiest,
        if (lijktOp != null) 'lijktOp': lijktOp,
        if (remixen > 0) 'remixen': remixen,
        'score': double.parse(score.toStringAsFixed(2)),
      };

  static NieuweUitgave? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = (j['id'] as num?)?.toInt();
    final titel = j['titel'] as String?;
    final artiest = j['artiest'] as String?;
    if (id == null || titel == null || titel.isEmpty || artiest == null) return null;
    return NieuweUitgave(
      album: CatalogAlbum(id, titel, j['hoes'] as String?, j['datum'] as String?,
          (j['nummers'] as num?)?.toInt() ?? 0, (j['soort'] as String?) ?? 'album'),
      artiest: artiest,
      lijktOp: j['lijktOp'] as String?,
      remixen: (j['remixen'] as num?)?.toInt() ?? 0,
      score: (j['score'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Wat er per artiest bij Deezer ligt, om uit te kiezen.
class Aanbod {
  final String artiest;
  final double relevantie;
  final List<CatalogAlbum> albums;
  final String? lijktOp;

  /// Uit je bibliotheek: het vroegste jaar per nummertitel ([EigenArtiest.titelJaar]).
  final Map<String, int> eerder;
  const Aanbod(
      {required this.artiest,
      required this.relevantie,
      required this.albums,
      this.lijktOp,
      this.eerder = const {}});
}

/// Het vroegste jaar waarin dit nummer al bestond, uit Deezer's eigen lijst en uit je bibliotheek.
///
/// Gemeten op 15-10-2026, de eerste echte ronde: "We Found Love (Extended Version)" van Rihanna (22
/// september 2026) en "I'm A Slave 4 U (Remixes)" van Britney Spears (25 september) kwamen als nieuwe
/// single bovenaan. Het zijn nummers uit 2011 en 2001 in een nieuw jasje — precies de heruitgaven die
/// Saber weg wilde. De nieuwe remix van een nummer van juli (Céline Dions "Bonjour, Pardon, Merci")
/// blijft: dat nummer is zelf nieuw.
Map<String, int> _vroegsteJaren(Aanbod a) {
  final uit = <String, int>{...a.eerder};
  for (final al in a.albums) {
    final j = int.tryParse(al.year ?? '');
    if (j == null || j < 1900) continue;
    final b = uitgaveBasis(al.title);
    if (uit[b] == null || j < uit[b]!) uit[b] = j;
  }
  return uit;
}

/// Uit het aanbod de tegels voor de balk.
///
/// [terug] en [vooruit] in dagen. [alInBezit] zijn [bezitssleutel]s. [weg] telt per reden wat er
/// afviel, voor het logboek.
List<NieuweUitgave> kiesUitgaven(
  List<Aanbod> aanbod, {
  required DateTime nu,
  Set<String> alInBezit = const {},
  int terug = 90,
  int vooruit = 45,
  int perArtiest = 2,
  int max = 15,
  Map<String, int>? weg,
}) {
  void tel(String r) {
    if (weg != null) weg[r] = (weg[r] ?? 0) + 1;
  }

  final vanaf = DateTime(nu.year, nu.month, nu.day).subtract(Duration(days: terug));
  final tot = DateTime(nu.year, nu.month, nu.day).add(Duration(days: vooruit));
  final uit = <NieuweUitgave>[];
  for (final a in aanbod) {
    // Eén titel één keer: Deezer had "DISGUISE" van Sia twee keer, een dag uit elkaar.
    final gezien = <String>{};
    final kandidaten = <CatalogAlbum>[];
    final vroegst = _vroegsteJaren(a);
    for (final al in a.albums) {
      final d = DateTime.tryParse(al.releaseDate ?? '');
      if (d == null || d.isBefore(vanaf) || d.isAfter(tot)) continue;
      final reden = geenNieuweMuziek(al.title, recordType: al.recordType, jaar: d.year);
      if (reden != null) {
        tel(reden);
        continue;
      }
      final eerst = vroegst[uitgaveBasis(al.title)];
      if (eerst != null && eerst <= d.year - 2) {
        tel('oud nummer');
        continue;
      }
      if (alInBezit.contains(bezitssleutel(a.artiest, al.title))) {
        tel('al in bezit');
        continue;
      }
      if (!gezien.add(normKey(al.title))) continue;
      kandidaten.add(al);
    }
    // Een catalogusdump op één dag is geen nieuwe muziek (zie [zonderHerlevering]).
    final schoon = [
      for (final h in zonderHerlevering([for (final k in kandidaten) CatalogAlbumHit(k, a.artiest)])) h.album
    ];
    if (schoon.length < kandidaten.length) tel('herlevering');

    // Remixen onder hun single.
    final groepen = <String, List<CatalogAlbum>>{};
    for (final k in schoon) {
      (groepen[uitgaveBasis(k.title)] ??= []).add(k);
    }
    final perGroep = <NieuweUitgave>[];
    for (final g in groepen.values) {
      // De single zelf als hij er is, anders de vroegste versie.
      g.sort((x, y) {
        final rx = isRemixUitgave(x.title), ry = isRemixUitgave(y.title);
        if (rx != ry) return rx ? 1 : -1;
        return (x.releaseDate ?? '').compareTo(y.releaseDate ?? '');
      });
      final kop = g.first;
      perGroep.add(NieuweUitgave(
        album: kop,
        artiest: a.artiest,
        lijktOp: a.lijktOp,
        remixen: g.length - 1,
        score: _score(kop, a, nu),
      ));
    }
    perGroep.sort((x, y) => y.score.compareTo(x.score));
    uit.addAll(perGroep.take(perArtiest));
    if (perGroep.length > perArtiest) tel('meer dan $perArtiest van één artiest');
  }
  uit.sort((x, y) {
    final s = y.score.compareTo(x.score);
    if (s != 0) return s;
    return (y.album.releaseDate ?? '').compareTo(x.album.releaseDate ?? '');
  });
  return uit.take(max).toList();
}

/// Hoogstens [max] uit [lijst], om de beurt uit elke groep, in de volgorde waarin de groepen voor het
/// eerst voorkomen. Gemeten op 15-10-2026: zonder dit kwamen alle drie de aanvullers via Céline Dion.
List<T> omDeBeurt<T>(List<T> lijst, String Function(T) groep, int max) {
  final groepen = <String, List<T>>{};
  for (final x in lijst) {
    (groepen[groep(x)] ??= []).add(x);
  }
  final uit = <T>[];
  for (var rang = 0; uit.length < max; rang++) {
    var iets = false;
    for (final g in groepen.values) {
      if (rang < g.length && uit.length < max) {
        uit.add(g[rang]);
        iets = true;
      }
    }
    if (!iets) break;
  }
  return uit;
}

/// Hoe hoog een tegel komt: hoe zwaar de artiest weegt, hoe vers de plaat is, en wat het is.
double _score(CatalogAlbum al, Aanbod a, DateTime nu) {
  final d = DateTime.tryParse(al.releaseDate ?? '');
  var s = a.relevantie;
  if (d != null) {
    final dagen = DateTime(nu.year, nu.month, nu.day).difference(d).inDays;
    if (dagen < 0) {
      s += 1.5; // verschijnt binnenkort
    } else if (dagen <= 14) {
      s += 3;
    } else if (dagen <= 30) {
      s += 2;
    } else if (dagen <= 60) {
      s += 1;
    }
  }
  s += switch (soortVan(al.recordType)) { UitgaveSoort.album => 1.0, UitgaveSoort.ep => 0.5, _ => 0.0 };
  if (isRemixUitgave(al.title)) s -= 1.5;
  if (a.lijktOp != null) s -= 2;
  return s;
}

const _maanden = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
const _maandenVol = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni',
  'juli', 'augustus', 'september', 'oktober', 'november', 'december',
];

/// De kop boven een tegel: "NIEUWE SINGLE", "NIEUW ALBUM · VERSCHIJNT 6 NOV", "LIJKT OP DUA LIPA".
String releaseKop(NieuweUitgave u, {required DateTime nu}) {
  final wat = switch (u.soort) {
    UitgaveSoort.album => 'NIEUW ALBUM',
    UitgaveSoort.ep => 'NIEUWE EP',
    UitgaveSoort.single => 'NIEUWE SINGLE',
  };
  final d = u.datum;
  final vandaag = DateTime(nu.year, nu.month, nu.day);
  final delen = <String>[
    if (u.lijktOp != null) 'LIJKT OP ${u.lijktOp!.toUpperCase()}',
    wat,
    if (d != null && d.isAfter(vandaag)) 'VERSCHIJNT ${d.day} ${_maanden[d.month - 1].toUpperCase()}',
  ];
  return delen.join(' · ');
}

/// De regel onder de artiest: "9 oktober 2026 · + 2 remixen".
String releaseOnderschrift(NieuweUitgave u) {
  final d = u.datum;
  final delen = <String>[
    if (d != null) '${d.day} ${_maandenVol[d.month - 1]} ${d.year}',
    if (u.remixen == 1) '+ 1 remix',
    if (u.remixen > 1) '+ ${u.remixen} remixen',
  ];
  return delen.join(' · ');
}

// ── Deezer ─────────────────────────────────────────────────────────────────

/// Deezer's `release_date` en `record_type` uit een ruw album.
CatalogAlbum? deezerAlbumUit(Object? a) {
  if (a is! Map) return null;
  final id = (a['id'] as num?)?.toInt();
  final titel = a['title'] as String?;
  if (id == null || titel == null || titel.isEmpty) return null;
  return CatalogAlbum(
    id,
    titel,
    deezerHoes(a),
    a['release_date'] as String?,
    (a['nb_tracks'] as num?)?.toInt() ?? 0,
    (a['record_type'] as String?) ?? 'album',
  );
}

/// Een gevouwen naam om twee schrijfwijzen van één artiest gelijk te stellen.
String _naamSleutel(String s) => artistKey(s).replaceAll(' ', '');

/// Wat er gebeurde bij één berekening, voor het logboek. Zie [NieuweReleasesZoeker.zoek].
class ReleasesVerslag {
  int artiesten = 0, herkend = 0, naamgenoot = 0, nietGevonden = 0, verwant = 0, vragen = 0;
  final weg = <String, int>{};
  final overgeslagen = <String>[];
  @override
  String toString() => '$artiesten artiesten: $herkend herkend, $naamgenoot zonder bewijs '
      '(${overgeslagen.take(8).join(', ')}${overgeslagen.length > 8 ? ', …' : ''}), '
      '$nietGevonden niet bij Deezer, $verwant verwant; $vragen vragen; weg: '
      '${weg.entries.map((e) => '${e.key} ${e.value}').join(', ')}';
}

/// De ophaling bij Deezer. [haal] is `DeezerBaan.haal` (één baan voor de hele app) of een nep in een
/// toets.
class NieuweReleasesZoeker {
  final Future<Map<String, dynamic>?> Function(String url) haal;
  NieuweReleasesZoeker(this.haal);

  static const _api = 'https://api.deezer.com';

  /// Onder zoveel eigen tegels wordt aangevuld met verwante artiesten, tot [aanvullenTot].
  static const aanvullenOnder = 10, aanvullenTot = 12;

  /// Bekende Deezer-ids per artiest ([_naamSleutel] → id; 0 = geen bewijs gevonden), met wanneer.
  final ids = <String, ({int id, int ms})>{};

  int _vragen = 0;

  Future<Map<String, dynamic>?> _haal(String pad) {
    _vragen++;
    return haal('$_api$pad');
  }

  /// Alle uitgaven van één Deezer-artiest. Deezer geeft ze NIET op datum (gemeten: eerst de albums,
  /// dan de singles) en hoogstens honderd per keer — David Guetta heeft er 398. Dus een tweede
  /// bladzijde als er meer zijn, en zelf sorteren.
  Future<List<CatalogAlbum>> uitgavenVan(int id) async {
    final eerste = await _haal('/artist/$id/albums?limit=100');
    final lijst = [for (final a in (eerste?['data'] as List? ?? const [])) ?deezerAlbumUit(a)];
    final totaal = (eerste?['total'] as num?)?.toInt() ?? 0;
    if (totaal > 100) {
      final tweede = await _haal('/artist/$id/albums?limit=100&index=100');
      lijst.addAll([for (final a in (tweede?['data'] as List? ?? const [])) ?deezerAlbumUit(a)]);
    }
    lijst.sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
    return lijst;
  }

  /// Het Deezer-id van [eigen], na bewijs. Null als er geen kandidaat iets met jou deelt.
  Future<({int id, List<CatalogAlbum> albums})?> _herken(EigenArtiest eigen, ReleasesVerslag v,
      {required int nuMs}) async {
    final k = _naamSleutel(eigen.naam);
    final bekend = ids[k];
    if (bekend != null) {
      final houdbaar = bekend.id > 0 ? const Duration(days: 30) : const Duration(days: 7);
      if (nuMs - bekend.ms < houdbaar.inMilliseconds) {
        if (bekend.id == 0) return null;
        return (id: bekend.id, albums: await uitgavenVan(bekend.id));
      }
    }
    final s = await _haal('/search/artist?q=${Uri.encodeQueryComponent(eigen.naam)}&limit=25');
    final kandidaten = [
      for (final a in (s?['data'] as List? ?? const []))
        if (a is Map && a['id'] is num && _naamSleutel((a['name'] ?? '') as String) == k) a,
    ]..sort((a, b) => ((b['nb_fan'] as num?) ?? 0).compareTo((a['nb_fan'] as num?) ?? 0));
    if (kandidaten.isEmpty) {
      v.nietGevonden++;
      return null;
    }
    for (final c in kandidaten.take(3)) {
      final id = (c['id'] as num).toInt();
      final albums = await uitgavenVan(id);
      var raak = zelfdeArtiest(eigen, albums: [for (final a in albums) a.title]);
      if (!raak) {
        final top = await _haal('/artist/$id/top?limit=50');
        raak = zelfdeArtiest(eigen,
            titels: [for (final t in (top?['data'] as List? ?? const [])) if (t is Map) '${t['title'] ?? ''}']);
      }
      if (raak) {
        ids[k] = (id: id, ms: nuMs);
        return (id: id, albums: albums);
      }
    }
    ids[k] = (id: 0, ms: nuMs);
    v.naamgenoot++;
    v.overgeslagen.add(eigen.naam);
    return null;
  }

  /// De hele berekening: de artiesten herkennen, hun aanbod ophalen, kiezen, en zo nodig aanvullen
  /// met verwante artiesten.
  Future<List<NieuweUitgave>> zoek(
    List<EigenArtiest> artiesten, {
    required DateTime nu,
    Set<String> alInBezit = const {},
    ReleasesVerslag? verslag,
  }) async {
    final v = verslag ?? ReleasesVerslag();
    _vragen = 0;
    final nuMs = nu.millisecondsSinceEpoch;
    v.artiesten = artiesten.length;
    final aanbod = <Aanbod>[];
    final herkend = <({EigenArtiest eigen, int id})>[];
    for (final a in artiesten) {
      final h = await _herken(a, v, nuMs: nuMs);
      if (h == null) continue;
      v.herkend++;
      herkend.add((eigen: a, id: h.id));
      aanbod.add(Aanbod(
          artiest: a.naam, relevantie: relevantie(a, nuMs: nuMs), albums: h.albums, eerder: a.titelJaar));
    }
    var gekozen = kiesUitgaven(aanbod, nu: nu, alInBezit: alInBezit, weg: v.weg);

    // Te weinig? Dan nieuwe muziek van wie op je meest gedraaide artiesten lijkt. Nooit een algemene
    // hitlijst: die zegt niets over jou.
    if (gekozen.length < aanvullenOnder && herkend.isNotEmpty) {
      final eigenNamen = {for (final a in artiesten) _naamSleutel(a.naam)};
      final verwant = <Aanbod>[];
      final gezien = <int>{};
      // Eerst de buren van wie zelf nieuw werk uitbracht. Gemeten op 15-10-2026: de buren van Michael
      // Jackson leverden een kerstverzamelaar van de Jackson 5 en een jubileum-EP van Stevie Wonder —
      // wie op een artiest van toen lijkt, brengt vooral archief uit.
      //
      // Actief is wie iets nieuws uitbracht, ook als je het al hebt: op de pc (15-10-2026, 3.9.490)
      // vielen Céline Dion en Britney Spears er anders uit zodra hun nieuwe nummer gedownload was, en
      // kwam Michael Jackson als vijfde bron terug — met weer de kerstplaat van de Jackson 5. Alleen als
      // niemand actief is, de rest.
      final actief = {
        for (final g in kiesUitgaven(aanbod, nu: nu, perArtiest: 1, max: 1000)) _naamSleutel(g.artiest)
      };
      final actieveBronnen = [...herkend.where((h) => actief.contains(_naamSleutel(h.eigen.naam)))];
      final bronnen = actieveBronnen.isNotEmpty ? actieveBronnen : herkend;
      // Vier buren per bron, vijf bronnen: twintig artiesten om uit te kiezen, en niet allemaal van één.
      for (final h in bronnen.take(5)) {
        final r = await _haal('/artist/${h.id}/related?limit=10');
        var vanDeze = 0;
        for (final x in (r?['data'] as List? ?? const [])) {
          if (vanDeze >= 4) break;
          if (x is! Map || x['id'] is! num) continue;
          final id = (x['id'] as num).toInt();
          final naam = (x['name'] ?? '') as String;
          if (naam.isEmpty || eigenNamen.contains(_naamSleutel(naam)) || !gezien.add(id)) continue;
          vanDeze++;
          verwant.add(Aanbod(
              artiest: naam, relevantie: 0, albums: await uitgavenVan(id), lijktOp: h.eigen.naam));
        }
      }
      final alle = kiesUitgaven(verwant, nu: nu, alInBezit: alInBezit, terug: 60, perArtiest: 1, max: 50, weg: v.weg);
      final extra = omDeBeurt(alle, (u) => u.lijktOp ?? '', aanvullenTot - gekozen.length);
      v.verwant = extra.length;
      gekozen = [...gekozen, ...extra];
    }
    v.vragen = _vragen;
    return gekozen;
  }
}

// ── Bewaren en verversen ───────────────────────────────────────────────────

/// De lijst zoals hij bewaard en verstuurd wordt.
class ReleasesLijst {
  final int berekendMs;
  final List<NieuweUitgave> uitgaven;
  const ReleasesLijst(this.berekendMs, this.uitgaven);

  static const versie = 1;

  Map<String, dynamic> toJson() => {
        'versie': versie,
        'berekendMs': berekendMs,
        'uitgaven': [for (final u in uitgaven) u.toJson()],
      };

  static ReleasesLijst? fromJson(Object? j) {
    if (j is! Map || j['versie'] != versie) return null;
    final ms = (j['berekendMs'] as num?)?.toInt();
    if (ms == null) return null;
    return ReleasesLijst(ms, [
      for (final u in (j['uitgaven'] as List? ?? const [])) ?NieuweUitgave.fromJson(u),
    ]);
  }
}

/// De dienst: rekent op de achtergrond, bewaart op schijf, en geeft meteen wat er ligt.
///
/// **Waarom op de pc en niet op elk toestel.** De berekening kost bij de eerste keer zo'n honderd
/// vragen aan Deezer (veertig artiesten, elk herkennen en ophalen) en daarna een veertigtal. Vier
/// toestellen die dat elk zelf doen, delen één Deezer-budget; de pc doet het één keer en de rest
/// vraagt het hem.
class NieuweReleases {
  NieuweReleases({
    required this.zoeker,
    required this.nummers,
    required this.bezit,
    required this.bestand,
    required this.idsBestand,
    this.log,
    DateTime Function()? klok,
  }) : klok = klok ?? DateTime.now;

  /// De dienst van deze pc, als die er is. Zie `server.dart` (`/api/releases`) en de startpagina.
  static NieuweReleases? pc;

  final NieuweReleasesZoeker zoeker;
  final List<EigenArtiest> Function() nummers;
  final Set<String> Function() bezit;
  final File bestand, idsBestand;
  final void Function(String regel)? log;
  final DateTime Function() klok;

  static const houdbaar = Duration(hours: 6);

  ReleasesLijst? _lijst;
  ReleasesLijst? get lijst => _lijst;
  Future<ReleasesLijst?>? _bezig;
  Timer? _klokje;
  final _luisteraars = <void Function()>[];

  void luister(void Function() f) => _luisteraars.add(f);
  void stopLuisteren(void Function() f) => _luisteraars.remove(f);

  bool get verouderd =>
      _lijst == null || klok().millisecondsSinceEpoch - _lijst!.berekendMs > houdbaar.inMilliseconds;

  /// Loopt er nu een berekening?
  bool get bezig => _bezig != null;

  /// Wat er op schijf ligt inlezen. Eén keer, bij het opstarten.
  Future<void> laad() async {
    try {
      if (await bestand.exists()) _lijst = ReleasesLijst.fromJson(jsonDecode(await bestand.readAsString()));
    } catch (_) {/* kapot of oud: dan rekenen we opnieuw */}
    try {
      if (await idsBestand.exists()) {
        final j = jsonDecode(await idsBestand.readAsString());
        if (j is Map) {
          for (final e in j.entries) {
            final w = e.value;
            if (e.key is String && w is Map && w['id'] is num && w['ms'] is num) {
              zoeker.ids[e.key as String] = (id: (w['id'] as num).toInt(), ms: (w['ms'] as num).toInt());
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Om de zes uur opnieuw, en de eerste keer na [eerst] als wat er ligt verouderd is.
  void start({Duration eerst = const Duration(seconds: 45)}) {
    _klokje?.cancel();
    Timer(eerst, () {
      if (verouderd) unawaited(ververs());
    });
    _klokje = Timer.periodic(houdbaar, (_) => unawaited(ververs()));
  }

  void stop() => _klokje?.cancel();

  /// Rekent opnieuw. Loopt er al een berekening, dan wacht deze daarop in plaats van een tweede te
  /// starten.
  Future<ReleasesLijst?> ververs() {
    final lopend = _bezig;
    if (lopend != null) return lopend;
    final werk = _reken();
    _bezig = werk;
    return werk.whenComplete(() {
      _bezig = null;
    });
  }

  Future<ReleasesLijst?> _reken() async {
    final t0 = DateTime.now();
    final nu = klok();
    final alle = nummers();
    if (alle.isEmpty) {
      // De bibliotheek is nog aan het inlezen. Niet zes uur wachten: over twee minuten opnieuw.
      log?.call('releases: nog geen bibliotheek — over twee minuten opnieuw');
      Timer(const Duration(minutes: 2), () => unawaited(ververs()));
      return _lijst;
    }
    final top = relevanteArtiesten(alle, nuMs: nu.millisecondsSinceEpoch);
    final v = ReleasesVerslag();
    try {
      final uit = await zoeker.zoek(top, nu: nu, alInBezit: bezit(), verslag: v);
      final lijst = ReleasesLijst(nu.millisecondsSinceEpoch, uit);
      _lijst = lijst;
      await bestand.writeAsString(jsonEncode(lijst.toJson()));
      await idsBestand.writeAsString(jsonEncode({
        for (final e in zoeker.ids.entries) e.key: {'id': e.value.id, 'ms': e.value.ms},
      }));
      log?.call('releases: ${uit.length} tegels in ${DateTime.now().difference(t0).inMilliseconds} ms — $v');
      for (final f in [..._luisteraars]) {
        f();
      }
      return lijst;
    } catch (e) {
      log?.call('releases: mislukt na ${DateTime.now().difference(t0).inMilliseconds} ms — $e');
      return _lijst;
    }
  }
}
