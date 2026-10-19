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
/// Op de pc berekend en bewaard (`nieuwe_releases.json`); een toestel krijgt de lijst in één vraag van
/// de pc. Zie [NieuweReleases].
///
/// **Twee rijen (Saber, 19-10-2026).** "Die wil ik in een nieuwe rij … een stuk of 20, en dan op meer
/// kunnen klikken, en daar wil ik er zeker een stuk of 100 of meer zien, zowel voor tracks en albums."
/// Daarom naast de oude lijst ([ReleasesLijst.uitgaven], voor oudere toestellen) twee nieuwe:
/// [ReleasesLijst.nummers] (singles en de nummers van nieuwe albums) en [ReleasesLijst.albums] (albums
/// en EP's). Uit AL je artiesten in plaats van de veertig meest gedraaide, zes maanden terug in plaats
/// van drie, en verwante artiesten vullen aan. Gemeten op 19-10-2026 bij de 39 herkende topartiesten: 24
/// uitgaven in drie maanden, 57 in zes, 105 in twaalf — vijf op de zes een single. Elke drie uur opnieuw,
/// met per artiest onthouden wat Deezer gaf, zodat een ronde weinig vraagt.
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
///
/// [soorten]: alleen deze soorten (album, EP, single); null is alles.
List<NieuweUitgave> kiesUitgaven(
  List<Aanbod> aanbod, {
  required DateTime nu,
  Set<String> alInBezit = const {},
  int terug = 90,
  int vooruit = 45,
  int perArtiest = 2,
  int max = 15,
  Set<UitgaveSoort>? soorten,
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
      if (soorten != null && !soorten.contains(soortVan(al.recordType))) continue;
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

// ── De twee rijen: nummers, en albums & EP's (19-10-2026) ──────────────────

/// Hoe ver terug en vooruit de twee rijen kijken, in dagen (Saber, 19-10-2026: "overal 6 maanden").
const kNieuwTerug = 182, kNieuwVooruit = 45;

/// Hoogstens zoveel per artiest, per lijst: twee nummers en twee albums (Saber, 19-10-2026).
const kNieuwPerArtiest = 2;

/// Hoeveel er in elke lijst hoogstens bewaard worden. Ruim boven de honderd die Saber wil zien.
const kNieuwMax = 300;

/// Eén nummer van een nieuw album of een nieuwe EP, zoals Deezer het noemt.
class AlbumNummer {
  final int id;
  final String titel, artiest;
  final int seconden, rank, positie;

  /// Het jaar uit de ISRC ([isrcJaar]); 0 als Deezer er geen gaf.
  final int jaar;
  const AlbumNummer({
    required this.id,
    required this.titel,
    this.artiest = '',
    this.seconden = 0,
    this.rank = 0,
    this.positie = 0,
    this.jaar = 0,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 't': titel, 'a': artiest, 's': seconden, 'r': rank, 'p': positie, 'j': jaar};

  /// Bewaard met een ISRC-jaar? Wat van vóór 19-10-2026 op schijf staat niet, en wordt één keer opnieuw
  /// gevraagd — anders zag de controle op oude opnamen ([oudeOpnamen]) die albums nooit.
  static bool metJaar(Object? j) => j is Map && j.containsKey('j');

  static AlbumNummer? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = (j['id'] as num?)?.toInt();
    final t = j['t'] as String?;
    if (id == null || t == null || t.isEmpty) return null;
    return AlbumNummer(
      id: id,
      titel: t,
      artiest: (j['a'] as String?) ?? '',
      seconden: (j['s'] as num?)?.toInt() ?? 0,
      rank: (j['r'] as num?)?.toInt() ?? 0,
      positie: (j['p'] as num?)?.toInt() ?? 0,
      jaar: (j['j'] as num?)?.toInt() ?? 0,
    );
  }

  /// Uit `/album/{id}/tracks` van Deezer (`data`), of uit `/album/{id}` (`tracks.data`). Alleen de
  /// eerste draagt de ISRC: in `/album/{id}` ontbreekt hij (gemeten 19-10-2026).
  static List<AlbumNummer> uitDeezer(Map<String, dynamic>? antwoord) => [
        for (final t in (antwoord?['data'] as List? ?? (antwoord?['tracks'] as Map?)?['data'] as List? ?? const []))
          if (t is Map && t['id'] is num && (t['title'] ?? '').toString().isNotEmpty)
            AlbumNummer(
              id: (t['id'] as num).toInt(),
              titel: t['title'] as String,
              artiest: ((t['artist'] as Map?)?['name'] as String?) ?? '',
              seconden: (t['duration'] as num?)?.toInt() ?? 0,
              rank: (t['rank'] as num?)?.toInt() ?? 0,
              positie: (t['track_position'] as num?)?.toInt() ?? 0,
              jaar: isrcJaar(t['isrc'] as String?) ?? 0,
            ),
      ];
}

/// Het jaar in een ISRC: "USWB19600603" → 1996, "USWB12604176" → 2026. Twee cijfers, dus vanaf '40 de
/// vorige eeuw (een opname van vóór 1940 heeft zelden een ISRC, en die van na 2039 bestaan nog niet).
int? isrcJaar(String? isrc) {
  final m = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}(\d{2})\d{5}$').firstMatch((isrc ?? '').trim().toUpperCase());
  if (m == null) return null;
  final jj = int.parse(m.group(1)!);
  return jj >= 40 ? 1900 + jj : 2000 + jj;
}

/// Hoeveel jaar vóór de uitgave een ISRC "oud" is.
const kOudeOpname = 3;

final _tussenstuk = RegExp(r'^\s*(intro|interlude|outro|skit)\b|[(\[]\s*(intro|interlude|outro|skit)\s*[)\]]',
    caseSensitive: false);

/// Een heruitgave volgens de opnamen zelf: meer dan de helft van de nummers draagt een ISRC van minstens
/// [kOudeOpname] jaar vóór [datum].
///
/// Saber, 19-10-2026, bij "You Must Love Me" van Madonna als grote kaart: "???". Deezer gaf hem als single
/// van 12 oktober 2026; twee van de drie nummers dragen een ISRC uit 1996. Over de 307 uitgaven van die
/// ochtend: 30 heruitgaven zo gevonden (Tears For Fears 1989, The Cranberries 1993, Ricky Martin 1996,
/// Katy Perry 2008, …), en geen enkele echte nieuwe. Wat half oud is (Whitney Houston 1 van 4, Dua Lipa
/// live 13 van 42) blijft.
bool oudeOpnamen(List<AlbumNummer> nummers, DateTime? datum) {
  if (datum == null) return false;
  final bekend = [for (final n in nummers) if (n.jaar > 0) n.jaar];
  if (bekend.isEmpty) return false;
  final oud = bekend.where((j) => j <= datum.year - kOudeOpname).length;
  return oud * 2 > bekend.length;
}

/// Hoogstens [max] per artiest, in de volgorde van [lijst].
List<NieuweUitgave> hoogstensPerArtiest(List<NieuweUitgave> lijst, int max) {
  final tel = <String, int>{};
  final uit = <NieuweUitgave>[];
  for (final u in lijst) {
    final k = artistKey(u.artiest);
    tel[k] = (tel[k] ?? 0) + 1;
    if (tel[k]! <= max) uit.add(u);
  }
  return uit;
}

/// Eén tegel in de rij "Nieuwe nummers": een single, of een nummer van een nieuw album of EP.
class NieuwNummer {
  final String titel, artiest;

  /// De uitgave waar het op staat: de single zelf, of het album.
  final CatalogAlbum album;

  /// Het Deezer-nummer, als het van een album komt; een single heeft er hier geen nodig.
  final int? trackId;
  final int seconden;

  /// Op wie dit lijkt, als het van een verwante artiest komt.
  final String? lijktOp;
  final int remixen;
  final double score;

  const NieuwNummer({
    required this.titel,
    required this.artiest,
    required this.album,
    this.trackId,
    this.seconden = 0,
    this.lijktOp,
    this.remixen = 0,
    this.score = 0,
  });

  DateTime? get datum => DateTime.tryParse(album.releaseDate ?? '');
  bool get eigen => lijktOp == null;

  /// Van een album (en dus niet de single zelf)?
  bool get vanAlbum => trackId != null && soortVan(album.recordType) != UitgaveSoort.single;

  /// Waarmee het scherm onthoudt of je hem al zag ("5 nieuw").
  String get sleutel => '${album.id}|${normKey(titel)}';

  Map<String, dynamic> toJson() => {
        'titel': titel,
        'artiest': artiest,
        'albumId': album.id,
        'album': album.title,
        'hoes': album.cover,
        'datum': album.releaseDate,
        'nummers': album.trackCount,
        'soort': album.recordType,
        if (trackId != null) 'trackId': trackId,
        if (seconden > 0) 'seconden': seconden,
        if (lijktOp != null) 'lijktOp': lijktOp,
        if (remixen > 0) 'remixen': remixen,
        'score': double.parse(score.toStringAsFixed(2)),
      };

  static NieuwNummer? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = (j['albumId'] as num?)?.toInt();
    final titel = j['titel'] as String?;
    final artiest = j['artiest'] as String?;
    if (id == null || titel == null || titel.isEmpty || artiest == null) return null;
    return NieuwNummer(
      titel: titel,
      artiest: artiest,
      album: CatalogAlbum(id, (j['album'] as String?) ?? titel, j['hoes'] as String?, j['datum'] as String?,
          (j['nummers'] as num?)?.toInt() ?? 0, (j['soort'] as String?) ?? 'single'),
      trackId: (j['trackId'] as num?)?.toInt(),
      seconden: (j['seconden'] as num?)?.toInt() ?? 0,
      lijktOp: j['lijktOp'] as String?,
      remixen: (j['remixen'] as num?)?.toInt() ?? 0,
      score: (j['score'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Een single uit de oude lijst als nummer (een oudere pc stuurt alleen [ReleasesLijst.uitgaven]).
  static NieuwNummer vanSingle(NieuweUitgave s) => NieuwNummer(
      titel: s.album.title, artiest: s.artiest, album: s.album, lijktOp: s.lijktOp, remixen: s.remixen, score: s.score);
}

/// De nummers voor "Nieuwe nummers": elke single (met zijn remixen eronder), en van elk nieuw album of
/// elke nieuwe EP de populairste nummers ([perAlbum], op Deezer's `rank`). Daarna per artiest hoogstens
/// [perArtiest], en een nummer dat als single én op het album staat één keer — als de single: die kwam
/// eerst, en dat is hoe je hem kent.
///
/// [inBezit]: [bezitssleutel]s van nummers die je al hebt (artiest + titel); die vallen weg (Saber,
/// 19-10-2026: "verbergen, zoals nu").
List<NieuwNummer> kiesNieuweNummers({
  required List<NieuweUitgave> singles,
  List<NieuweUitgave> albums = const [],
  Map<int, List<AlbumNummer>> nummersPerAlbum = const {},
  Set<String> inBezit = const {},
  int perArtiest = kNieuwPerArtiest,
  int perAlbum = 3,
  int max = kNieuwMax,
}) {
  final perArtiestK = <String, List<NieuwNummer>>{};
  void voeg(NieuwNummer n) {
    if (inBezit.contains(bezitssleutel(n.artiest, n.titel))) return;
    (perArtiestK[artistKey(n.artiest)] ??= []).add(n);
  }
  for (final s in singles) {
    voeg(NieuwNummer(
        titel: s.album.title,
        artiest: s.artiest,
        album: s.album,
        lijktOp: s.lijktOp,
        remixen: s.remixen,
        score: s.score + .5));
  }
  for (final a in albums) {
    final lijst = [...?nummersPerAlbum[a.album.id]]..sort((x, y) {
        final r = y.rank.compareTo(x.rank);
        return r != 0 ? r : x.positie.compareTo(y.positie);
      });
    // Een oude opname op een verder nieuwe plaat (een hit als bonus, een oude studioversie op een
    // live-album) is geen nieuw nummer.
    final d = a.datum;
    lijst.removeWhere((t) => d != null && t.jaar > 0 && t.jaar <= d.year - kOudeOpname);
    // Een intro, interlude of skit is geen nummer om op te zetten ("Instinct (intro)" van Angèle en
    // "Intro (Instrumental)" van Snoop Dogg stonden in de rij, pc 19-10-2026).
    lijst.removeWhere((t) => _tussenstuk.hasMatch(t.titel));
    for (var i = 0; i < lijst.length && i < perAlbum; i++) {
      final t = lijst[i];
      voeg(NieuwNummer(
          titel: t.titel,
          artiest: a.artiest,
          album: a.album,
          trackId: t.id,
          seconden: t.seconden,
          lijktOp: a.lijktOp,
          score: a.score - .5 - .3 * i));
    }
  }
  final uit = <NieuwNummer>[];
  for (final lijst in perArtiestK.values) {
    // Eén nummer één keer. Staat het als single én op het album, dan de single — met de hoogste score
    // van de twee, zodat het niet zakt omdat het album hoger staat.
    final perBasis = <String, NieuwNummer>{};
    // Versies van één liedje op hetzelfde album zijn één nummer, met de rest als "+ 1 remix" eronder.
    // Gemeten op de pc (19-10-2026): Whitney Houstons EP "One Wish (For Christmas)" stond twee keer
    // vooraan, als "(The Voice of Whitney Symphonic)" en "(The Voice - A cappella Mix)" — dat eerste
    // herkent [uitgaveBasis] niet als versie, en dat hoeft ook niet: op één album is wat vóór het
    // eerste haakje staat genoeg.
    final kernNaarBasis = <String, String>{};
    for (final x in lijst) {
      var b = uitgaveBasis(x.titel);
      if (x.vanAlbum) {
        final kern = _liedKern(x.titel);
        if (kern.isNotEmpty) b = kernNaarBasis.putIfAbsent('${x.album.id}|$kern', () => b);
      }
      final eerder = perBasis[b];
      if (eerder == null) {
        perBasis[b] = x;
        continue;
      }
      final single = !eerder.vanAlbum ? eerder : (!x.vanAlbum ? x : null);
      final hoogste = math.max(eerder.score, x.score);
      final houd = single ?? (x.score > eerder.score ? x : eerder);
      perBasis[b] = NieuwNummer(
          titel: houd.titel,
          artiest: houd.artiest,
          album: houd.album,
          trackId: houd.trackId,
          seconden: houd.seconden,
          lijktOp: houd.lijktOp,
          // Twee nummers van dezelfde plaat: de tweede is een versie. Een single naast zijn albumnummer
          // is dezelfde opname en telt niet.
          remixen: houd.remixen + (eerder.album.id == x.album.id ? 1 : 0),
          score: hoogste);
    }
    final gekozen = perBasis.values.toList()..sort((x, y) => y.score.compareTo(x.score));
    uit.addAll(gekozen.take(perArtiest));
  }
  uit.sort((x, y) {
    final s = y.score.compareTo(x.score);
    return s != 0 ? s : (y.album.releaseDate ?? '').compareTo(x.album.releaseDate ?? '');
  });
  return uit.take(max).toList();
}

/// Het liedje zonder wat erachter staat: "One Wish (For Christmas) (The Voice - A cappella Mix)" wordt
/// "one wish". Leeg als de titel met een haakje begint ("(I Can't Get No) Satisfaction"): dan zegt het
/// begin niets, en beslist [uitgaveBasis].
String _liedKern(String titel) => normKey(_zonderGasten(titel).split(RegExp(r'\s*[(\[]|\s+[-–]\s+')).first);


DateTime _dag(DateTime d) => DateTime(d.year, d.month, d.day);

/// Het kopje waaronder een uitgave van [datum] staat op de meer-pagina: "Binnenkort", "Deze week",
/// "Vorige week", "Eerder in oktober", "September", "Mei 2026" (een ander jaar erbij).
String weekKop(DateTime? datum, DateTime nu) {
  if (datum == null) return 'Eerder';
  final vandaag = _dag(nu), d = _dag(datum);
  if (d.isAfter(vandaag)) return 'Binnenkort';
  final maandag = vandaag.subtract(Duration(days: vandaag.weekday - 1));
  if (!d.isBefore(maandag)) return 'Deze week';
  if (!d.isBefore(maandag.subtract(const Duration(days: 7)))) return 'Vorige week';
  final maand = _maandenVol[d.month - 1];
  if (d.year == vandaag.year && d.month == vandaag.month) return 'Eerder in $maand';
  final groot = '${maand[0].toUpperCase()}${maand.substring(1)}';
  return d.year == vandaag.year ? groot : '$groot ${d.year}';
}

/// De volgorde van de kopjes: Binnenkort, Deze week, Vorige week, dan maand voor maand terug.
int _weekRang(DateTime? datum, DateTime nu) {
  if (datum == null) return 1 << 20;
  final vandaag = _dag(nu), d = _dag(datum);
  if (d.isAfter(vandaag)) return 0;
  final maandag = vandaag.subtract(Duration(days: vandaag.weekday - 1));
  if (!d.isBefore(maandag)) return 1;
  if (!d.isBefore(maandag.subtract(const Duration(days: 7)))) return 2;
  return 3 + (vandaag.year - d.year) * 12 + (vandaag.month - d.month);
}

/// Per kopje ([weekKop]), in de volgorde van de meer-pagina. Binnen een kopje eerst je eigen artiesten
/// (Saber, 19-10-2026: "eigen artiesten eerst, verwant vult aan"), dan de rest; bij Binnenkort wat het
/// eerst verschijnt bovenaan, verder de hoogste [score].
List<({String kop, List<T> items})> perWeek<T>(
  List<T> lijst, {
  required DateTime? Function(T) datum,
  required bool Function(T) eigen,
  required double Function(T) score,
  required DateTime nu,
}) {
  final groepen = <int, List<T>>{};
  final koppen = <int, String>{};
  for (final x in lijst) {
    final d = datum(x);
    final r = _weekRang(d, nu);
    (groepen[r] ??= []).add(x);
    koppen[r] ??= weekKop(d, nu);
  }
  final rangen = groepen.keys.toList()..sort();
  return [
    for (final r in rangen)
      (
        kop: koppen[r]!,
        items: groepen[r]!
          ..sort((a, b) {
            final e = (eigen(a) ? 0 : 1).compareTo(eigen(b) ? 0 : 1);
            if (e != 0) return e;
            if (r == 0) {
              final d = (datum(a) ?? nu).compareTo(datum(b) ?? nu);
              if (d != 0) return d;
            }
            final s = score(b).compareTo(score(a));
            if (s != 0) return s;
            return (datum(b) ?? nu).compareTo(datum(a) ?? nu);
          }),
      ),
  ];
}

/// De volgorde in de rij op Start: vooraan (op de grote kaart) het beste wat al uit is, dan wat
/// binnenkort verschijnt (met de datum op de hoes), dan de rest in de volgorde van [perWeek].
///
/// [nietVooraan]: wat niet op de grote kaart mag — bij "Nieuwe nummers" een nummer van precies de plaat
/// die de grote kaart van "Nieuwe albums & EP's" is, anders opent Start twee keer met dezelfde hoes (pc,
/// 19-10-2026). De grote kaart wordt dan het volgende dat al uit is, nooit iets van "Binnenkort".
List<T> rijVolgorde<T>(
  List<T> lijst, {
  required DateTime? Function(T) datum,
  required bool Function(T) eigen,
  required double Function(T) score,
  required DateTime nu,
  bool Function(T)? nietVooraan,
  int max = 20,
}) {
  final weken = perWeek(lijst, datum: datum, eigen: eigen, score: score, nu: nu);
  final binnenkort = [for (final w in weken) if (w.kop == 'Binnenkort') ...w.items];
  final uit = [for (final w in weken) if (w.kop != 'Binnenkort') ...w.items];
  if (uit.isEmpty) return binnenkort.take(max).toList();
  final i = nietVooraan == null ? 0 : math.max(0, uit.indexWhere((x) => !nietVooraan(x)));
  return [uit[i], ...binnenkort, ...uit.take(i), ...uit.skip(i + 1)].take(max).toList();
}

/// Het lintje op de hoes: "Vandaag", "Gisteren", "3 dagen", "12 sep" — en voor wat nog komt de datum
/// waarop hij verschijnt ("6 nov").
String? datumLint(DateTime? datum, DateTime nu) {
  if (datum == null) return null;
  final dagen = _dag(nu).difference(_dag(datum)).inDays;
  if (dagen < 0 || dagen >= 7) return '${datum.day} ${_maanden[datum.month - 1]}';
  if (dagen == 0) return 'Vandaag';
  if (dagen == 1) return 'Gisteren';
  return '$dagen dagen';
}

/// Hoeveel van [sleutels] er niet in [gezien] staan: de teller "5 nieuw" naast de kop.
int nieuwSindsVorige(Iterable<String> sleutels, Set<String> gezien) =>
    gezien.isEmpty ? 0 : sleutels.where((s) => !gezien.contains(s)).length;

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
///
/// [alsNummer]: boven één nummer van die plaat. Dan "UIT DE NIEUWE EP" — "NIEUWE EP" boven een nummer
/// zei dat het nummer de EP was.
String releaseKop(NieuweUitgave u, {required DateTime nu, bool alsNummer = false}) {
  final wat = switch (u.soort) {
    UitgaveSoort.album => alsNummer ? 'UIT HET NIEUWE ALBUM' : 'NIEUW ALBUM',
    UitgaveSoort.ep => alsNummer ? 'UIT DE NIEUWE EP' : 'NIEUWE EP',
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

  /// Vragen die ook na opnieuw proberen niet lukten (meestal het budget van Deezer).
  int mislukt = 0;
  final weg = <String, int>{};
  final overgeslagen = <String>[];
  @override
  String toString() => '$artiesten artiesten: $herkend herkend, $naamgenoot zonder bewijs '
      '(${overgeslagen.take(8).join(', ')}${overgeslagen.length > 8 ? ', …' : ''}), '
      '$nietGevonden niet bij Deezer, $verwant verwant; $vragen vragen${mislukt > 0 ? ', $mislukt mislukt' : ''}; weg: '
      '${weg.entries.map((e) => '${e.key} ${e.value}').join(', ')}';
}

/// De ophaling bij Deezer. [haal] is `DeezerBaan.haal` (één baan voor de hele app) of een nep in een
/// toets.
class NieuweReleasesZoeker {
  final Future<Map<String, dynamic>?> Function(String url) haal;
  NieuweReleasesZoeker(this.haal, {Future<void> Function(Duration)? slaap}) : slaap = slaap ?? Future<void>.delayed;

  /// Hoe er gewacht wordt; een toets zet hem op meteen.
  final Future<void> Function(Duration) slaap;

  /// Extra rust tussen twee vragen tijdens een hele ronde ([zoekAlles]).
  ///
  /// De Deezer-baan is van de hele app (`deezerbaan.dart`), en een ronde van honderden vragen mag een
  /// artiestpagina die je intussen opent niet in de weg zitten. Gemeten op 19-10-2026: zonder dit liep
  /// de eerste ronde over al je artiesten na 3,5 minuut op "Quota limit exceeded", en ging hij in zijn
  /// geheel verloren.
  static const rondeRust = Duration(milliseconds: 250);
  Duration _rust = Duration.zero;

  static const _api = 'https://api.deezer.com';

  /// Onder zoveel eigen tegels wordt aangevuld met verwante artiesten, tot [aanvullenTot].
  static const aanvullenOnder = 10, aanvullenTot = 12;

  /// Bekende Deezer-ids per artiest ([_naamSleutel] → id; 0 = geen bewijs gevonden), met wanneer.
  final ids = <String, ({int id, int ms})>{};

  /// Wat Deezer per artiest gaf, en wanneer: in het geheugen, zolang de pc draait. Met al je artiesten
  /// (±400) is dat het verschil tussen een ronde van vijfhonderd vragen en een van een paar dozijn.
  final _uitgaven = <int, ({int ms, List<CatalogAlbum> albums})>{};

  /// De nummers per album ([AlbumNummer.uitDeezer]), bewaard op schijf: een album dat uit is,
  /// verandert niet meer. Wat nog moet verschijnen, wordt niet bewaard.
  final nummers = <int, List<AlbumNummer>>{};

  int _vragen = 0;

  /// Eén vraag aan Deezer. Een "Quota limit exceeded" is geen nee maar "even niet": dan wachten en tot
  /// twee keer opnieuw. Al het andere gaat door naar wie vroeg.
  Future<Map<String, dynamic>?> _haal(String pad) async {
    _vragen++;
    if (_rust > Duration.zero) await slaap(_rust);
    for (var poging = 0;; poging++) {
      try {
        return await haal('$_api$pad');
      } catch (e) {
        if (!'$e'.toLowerCase().contains('quota') || poging >= 2) rethrow;
        await slaap(Duration(seconds: 6 * (poging + 1)));
      }
    }
  }

  /// Alle uitgaven van één Deezer-artiest. Deezer geeft ze NIET op datum (gemeten: eerst de albums,
  /// dan de singles) en hoogstens honderd per keer — David Guetta heeft er 398. Dus een tweede
  /// bladzijde als er meer zijn, en zelf sorteren.
  ///
  /// Met [nuMs] en [vers]: wat jonger is dan [vers] komt uit het geheugen ([_uitgaven]).
  Future<List<CatalogAlbum>> uitgavenVan(int id, {int? nuMs, Duration vers = Duration.zero}) async {
    final bekend = _uitgaven[id];
    if (nuMs != null && bekend != null && nuMs - bekend.ms < vers.inMilliseconds) return bekend.albums;
    final lijst = await _uitgavenVanDeezer(id);
    if (nuMs != null) _uitgaven[id] = (ms: nuMs, albums: lijst);
    return lijst;
  }

  /// De nummers van een album, uit [nummers] of van Deezer. [bewaar] alleen voor wat al uit is.
  Future<List<AlbumNummer>> nummersVan(int albumId, {bool bewaar = true}) async {
    final bekend = nummers[albumId];
    if (bekend != null) return bekend;
    final lijst = AlbumNummer.uitDeezer(await _haal('/album/$albumId/tracks?limit=100'));
    if (bewaar && lijst.isNotEmpty) nummers[albumId] = lijst;
    return lijst;
  }

  Future<List<CatalogAlbum>> _uitgavenVanDeezer(int id) async {
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
  ///
  /// [vers]: hoe oud wat er van een bekende artiest in het geheugen ligt mag zijn ([uitgavenVan]).
  /// [kandidaten]: hoeveel naamgenoten hoogstens geprobeerd worden (elk twee à drie vragen).
  Future<({int id, List<CatalogAlbum> albums})?> _herken(EigenArtiest eigen, ReleasesVerslag v,
      {required int nuMs, Duration vers = Duration.zero, int kandidaten = 3}) async {
    final k = _naamSleutel(eigen.naam);
    final bekend = ids[k];
    if (bekend != null) {
      final houdbaar = bekend.id > 0 ? const Duration(days: 30) : const Duration(days: 7);
      if (nuMs - bekend.ms < houdbaar.inMilliseconds) {
        if (bekend.id == 0) return null;
        return (id: bekend.id, albums: await uitgavenVan(bekend.id, nuMs: nuMs, vers: vers));
      }
    }
    final s = await _haal('/search/artist?q=${Uri.encodeQueryComponent(eigen.naam)}&limit=25');
    final namen = [
      for (final a in (s?['data'] as List? ?? const []))
        if (a is Map && a['id'] is num && _naamSleutel((a['name'] ?? '') as String) == k) a,
    ]..sort((a, b) => ((b['nb_fan'] as num?) ?? 0).compareTo((a['nb_fan'] as num?) ?? 0));
    if (namen.isEmpty) {
      v.nietGevonden++;
      return null;
    }
    for (final c in namen.take(kandidaten)) {
      final id = (c['id'] as num).toInt();
      final albums = await uitgavenVan(id, nuMs: nuMs, vers: vers);
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

  /// Hoe oud wat er van een artiest in het geheugen ligt mag zijn: je [vaakst] gedraaide artiesten
  /// elke ronde vers, de rest één keer per dag.
  static const vaakst = 60;
  static const _versTop = Duration(hours: 3), _versRest = Duration(hours: 24);

  /// De twee rijen ([ReleasesLijst.nummers] en [ReleasesLijst.albums]) en de oude lijst, in één ronde.
  ///
  /// [artiesten] in volgorde van [relevantie]: de bovenste [vaakst] worden elke ronde opnieuw gevraagd,
  /// de rest één keer per dag. Verwante artiesten komen van de [_bronnenVerwant] meest gedraaide
  /// artiesten die zelf iets nieuws hebben.
  ///
  /// [tussendoor] elke [tussenstap] artiesten, met een regel over de voortgang: de eerste ronde over
  /// al je artiesten duurt twintig minuten of langer (gemeten 19-10-2026), en zonder dit was niet te
  /// zien of hij liep — en ging het herkennen verloren als hij halverwege brak. De aanroeper bewaart
  /// dan [ids] alvast.
  Future<({List<NieuweUitgave> oud, List<NieuwNummer> nummers, List<NieuweUitgave> albums})> zoekAlles(
    List<EigenArtiest> artiesten, {
    required DateTime nu,
    Set<String> alInBezit = const {},
    Set<String> nummersInBezit = const {},
    ReleasesVerslag? verslag,
    Future<void> Function(String voortgang)? tussendoor,
  }) async {
    _rust = rondeRust;
    try {
      return await _zoekAlles(artiesten,
          nu: nu, alInBezit: alInBezit, nummersInBezit: nummersInBezit, verslag: verslag, tussendoor: tussendoor);
    } finally {
      _rust = Duration.zero;
    }
  }

  static const tussenstap = 50;

  Future<({List<NieuweUitgave> oud, List<NieuwNummer> nummers, List<NieuweUitgave> albums})> _zoekAlles(
    List<EigenArtiest> artiesten, {
    required DateTime nu,
    required Set<String> alInBezit,
    required Set<String> nummersInBezit,
    ReleasesVerslag? verslag,
    Future<void> Function(String voortgang)? tussendoor,
  }) async {
    final v = verslag ?? ReleasesVerslag();
    _vragen = 0;
    final nuMs = nu.millisecondsSinceEpoch;
    v.artiesten = artiesten.length;
    final aanbod = <Aanbod>[];
    final herkend = <({EigenArtiest eigen, int id})>[];
    for (final (i, a) in artiesten.indexed) {
      if (i > 0 && i % tussenstap == 0) {
        await tussendoor?.call('$i van ${artiesten.length} artiesten, $_vragen vragen, ${v.herkend} herkend'
            '${v.mislukt > 0 ? ', ${v.mislukt} mislukt' : ''}');
      }
      // Eén artiest die niet lukt, is één artiest minder — niet de hele ronde weg.
      ({int id, List<CatalogAlbum> albums})? h;
      try {
        // Wie je weinig draait: twee naamgenoten proberen en niet drie. Bij de eerste ronde over al je
        // artiesten scheelt dat honderden vragen, en wie je zelden draait heeft zelden een naamgenoot
        // die bekender is dan hijzelf.
        h = await _herken(a, v,
            nuMs: nuMs, vers: i < vaakst ? _versTop : _versRest, kandidaten: i < vaakst ? 3 : 2);
      } catch (_) {
        v.mislukt++;
        continue;
      }
      if (h == null) continue;
      v.herkend++;
      herkend.add((eigen: a, id: h.id));
      aanbod.add(Aanbod(
          artiest: a.naam, relevantie: relevantie(a, nuMs: nuMs), albums: h.albums, eerder: a.titelJaar));
    }

    List<NieuweUitgave> kies(List<Aanbod> van, Set<UitgaveSoort> soorten, {int perArtiest = kNieuwPerArtiest}) =>
        kiesUitgaven(van,
            nu: nu,
            alInBezit: alInBezit,
            terug: kNieuwTerug,
            vooruit: kNieuwVooruit,
            perArtiest: perArtiest,
            max: kNieuwMax,
            soorten: soorten,
            weg: v.weg);

    const albumSoorten = {UitgaveSoort.album, UitgaveSoort.ep};
    const singleSoort = {UitgaveSoort.single};
    // Ruimer dan twee per artiest: wat een heruitgave blijkt ([oudeOpnamen]) maakt plaats, en dan
    // schuift de volgende van die artiest op. De grens van twee komt daarna ([hoogstensPerArtiest]).
    final albumsEigen = kies(aanbod, albumSoorten, perArtiest: _ruimPerArtiest);
    // Ruimer dan twee: de grens per artiest komt in [kiesNieuweNummers], samen met de albumnummers.
    final singlesEigen = kies(aanbod, singleSoort, perArtiest: 6);

    // Verwant: de buren van wie zelf iets nieuws uitbracht, eigen artiesten eerst.
    final actief = {
      for (final u in [...albumsEigen, ...singlesEigen]) _naamSleutel(u.artiest),
    };
    final eigenNamen = {for (final a in artiesten) _naamSleutel(a.naam)};
    final verwant = <Aanbod>[];
    final gezien = <int>{};
    for (final h in herkend.where((h) => actief.contains(_naamSleutel(h.eigen.naam))).take(_bronnenVerwant)) {
      Map<String, dynamic>? r;
      try {
        r = await _haal('/artist/${h.id}/related?limit=10');
      } catch (_) {
        v.mislukt++;
        continue;
      }
      var vanDeze = 0;
      for (final x in (r?['data'] as List? ?? const [])) {
        if (vanDeze >= _burenPerBron) break;
        if (x is! Map || x['id'] is! num) continue;
        final id = (x['id'] as num).toInt();
        final naam = (x['name'] ?? '') as String;
        if (naam.isEmpty || eigenNamen.contains(_naamSleutel(naam)) || !gezien.add(id)) continue;
        List<CatalogAlbum> albums;
        try {
          albums = await uitgavenVan(id, nuMs: nuMs, vers: _versRest);
        } catch (_) {
          v.mislukt++;
          continue;
        }
        vanDeze++;
        verwant.add(Aanbod(artiest: naam, relevantie: 0, albums: albums, lijktOp: h.eigen.naam));
      }
    }
    final albumsVerwantRuim = kies(verwant, albumSoorten, perArtiest: _ruimPerArtiest);
    final singlesVerwantRuim = kies(verwant, singleSoort, perArtiest: 6);

    // De nummers van elke kandidaat, ook van elke single: één vraag per plaat, en daarna bewaard. Aan
    // hun ISRC's is te zien of het een heruitgave is ([oudeOpnamen]).
    final vandaag = DateTime(nu.year, nu.month, nu.day);
    final opgehaald = <int, List<AlbumNummer>>{};
    final datumVan = <int, DateTime?>{};
    for (final a in [...albumsEigen, ...albumsVerwantRuim, ...singlesEigen, ...singlesVerwantRuim]) {
      final d = a.datum;
      datumVan[a.album.id] = d;
      try {
        opgehaald[a.album.id] = await nummersVan(a.album.id, bewaar: d != null && !d.isAfter(vandaag));
      } catch (_) {
        v.mislukt++; // dan staat deze plaat er zonder zijn nummers bij; de volgende ronde probeert het opnieuw
      }
    }
    // Een album of EP met hetzelfde liedje als een bewezen oude opname van die artiest, is dezelfde
    // heruitgave in een andere verpakking — ook als een distributeur er nieuwe ISRC's op zette. Gemeten
    // op de pc (19-10-2026): "Witch Doktor (Basic Beat / ffrr Mixes)" van Armand Van Helden, de remixen
    // uit 1994 met codes uit 2026, naast de single "Witch Doktor" met zijn ISRC's uit 1994. Een single
    // blijft erbuiten: een echt nieuwe remix van een oude hit is wel nieuw.
    String lied(NieuweUitgave u) => '${artistKey(u.artiest)}|${uitgaveBasis(u.album.title)}';
    final alle = [...albumsEigen, ...albumsVerwantRuim, ...singlesEigen, ...singlesVerwantRuim];
    final oudeLiederen = {
      for (final u in alle)
        if (oudeOpnamen(opgehaald[u.album.id] ?? const [], u.datum)) lied(u),
    };
    bool heruitgave(NieuweUitgave u) =>
        oudeOpnamen(opgehaald[u.album.id] ?? const [], u.datum) ||
        (u.soort != UitgaveSoort.single && oudeLiederen.contains(lied(u)));
    List<NieuweUitgave> nieuwOpgenomen(List<NieuweUitgave> l) {
      final uit = <NieuweUitgave>[];
      for (final u in l) {
        if (heruitgave(u)) {
          v.weg['oude opnamen'] = (v.weg['oude opnamen'] ?? 0) + 1;
        } else {
          uit.add(u);
        }
      }
      return uit;
    }
    final albumsEigenNieuw = hoogstensPerArtiest(nieuwOpgenomen(albumsEigen), kNieuwPerArtiest);
    final albumsVerwant = hoogstensPerArtiest(nieuwOpgenomen(albumsVerwantRuim), kNieuwPerArtiest);
    final singlesVerwant = nieuwOpgenomen(singlesVerwantRuim);
    // Alleen de nummers van wat al uit is: een nummer van een album dat pas over een maand verschijnt
    // kun je niet spelen (pc, 19-10-2026: de halve rij was Sting en Calogero van eind november).
    final speelbaar = {
      for (final e in opgehaald.entries)
        if (!(datumVan[e.key]?.isAfter(vandaag) ?? true)) e.key: e.value,
    };
    final nummersEigen = kiesNieuweNummers(
        singles: nieuwOpgenomen(singlesEigen),
        albums: albumsEigenNieuw,
        nummersPerAlbum: speelbaar,
        inBezit: nummersInBezit);
    final nummersVerwant = kiesNieuweNummers(
        singles: singlesVerwant, albums: albumsVerwant, nummersPerAlbum: speelbaar, inBezit: nummersInBezit);

    // De oude lijst, voor een toestel dat de twee rijen nog niet kent: zoals hij was.
    var oud = kiesUitgaven(aanbod, nu: nu, alInBezit: alInBezit);
    if (oud.length < aanvullenOnder && verwant.isNotEmpty) {
      final alle = kiesUitgaven(verwant, nu: nu, alInBezit: alInBezit, terug: 60, perArtiest: 1, max: 50);
      oud = [...oud, ...omDeBeurt(alle, (u) => u.lijktOp ?? '', aanvullenTot - oud.length)];
    }
    v.verwant = albumsVerwant.length + nummersVerwant.length;
    v.vragen = _vragen;
    return (
      oud: oud,
      nummers: [...nummersEigen, ...nummersVerwant].take(kNieuwMax).toList(),
      albums: [...albumsEigenNieuw, ...albumsVerwant].take(kNieuwMax).toList(),
    );
  }

  /// Van hoeveel eigen artiesten de buren meedoen, en hoeveel buren per artiest.
  ///
  /// Was 15. Na het weren van heruitgaven op hun ISRC bleven er 74 albums & EP's over, 12 daarvan van
  /// verwante artiesten (pc, 19-10-2026), en Saber vroeg er "zeker een stuk of 100". Het venster blijft
  /// zes maanden; de buren vullen aan, zoals afgesproken.
  static const _bronnenVerwant = 40, _burenPerBron = 5;

  /// Hoeveel albums per artiest kandidaat zijn vóór de controle op oude opnamen.
  static const _ruimPerArtiest = 4;
}

// ── Bewaren en verversen ───────────────────────────────────────────────────

/// De lijst zoals hij bewaard en verstuurd wordt.
///
/// Versie 2 (19-10-2026) draagt naast de oude [uitgaven] de twee rijen [nummers] en [albums]. Een
/// oudere app leest alleen versie 1 en gooit al het andere weg; daarom krijgt die via `/api/releases`
/// nog steeds [toJsonV1], en de nieuwe app vraagt `/api/nieuw`.
class ReleasesLijst {
  final int berekendMs;
  final List<NieuweUitgave> uitgaven;
  final List<NieuwNummer> nummers;
  final List<NieuweUitgave> albums;

  /// Ingelezen uit versie 1: de twee rijen zijn dan afgeleid uit de oude twaalf tegels en geen echte
  /// ronde. [NieuweReleases.verouderd] rekent zo'n lijst meteen opnieuw, anders bleef na de update
  /// tot drie uur lang de oude lijst staan (pc, 19-10-2026: "Alles (7)" en "Alles (5)").
  final bool oudeVorm;
  const ReleasesLijst(this.berekendMs, this.uitgaven,
      {this.nummers = const [], this.albums = const [], this.oudeVorm = false});

  static const versie = 2;

  Map<String, dynamic> toJson() => {
        'versie': versie,
        'berekendMs': berekendMs,
        'uitgaven': [for (final u in uitgaven) u.toJson()],
        'nummers': [for (final n in nummers) n.toJson()],
        'albums': [for (final a in albums) a.toJson()],
      };

  /// Zoals een app van vóór de twee rijen hem verwacht.
  Map<String, dynamic> toJsonV1() => {
        'versie': 1,
        'berekendMs': berekendMs,
        'uitgaven': [for (final u in uitgaven) u.toJson()],
      };

  static ReleasesLijst? fromJson(Object? j) {
    if (j is! Map) return null;
    final v = j['versie'];
    if (v != 1 && v != versie) return null;
    final ms = (j['berekendMs'] as num?)?.toInt();
    if (ms == null) return null;
    final uitgaven = [
      for (final u in (j['uitgaven'] as List? ?? const [])) ?NieuweUitgave.fromJson(u),
    ];
    if (v == 1) {
      // Een oudere pc: de twee rijen uit de oude lijst, zo goed als het gaat.
      return ReleasesLijst(ms, uitgaven,
          nummers: [for (final u in uitgaven) if (u.soort == UitgaveSoort.single) NieuwNummer.vanSingle(u)],
          albums: [for (final u in uitgaven) if (u.soort != UitgaveSoort.single) u],
          oudeVorm: true);
    }
    return ReleasesLijst(ms, uitgaven,
        nummers: [for (final n in (j['nummers'] as List? ?? const [])) ?NieuwNummer.fromJson(n)],
        albums: [for (final a in (j['albums'] as List? ?? const [])) ?NieuweUitgave.fromJson(a)]);
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
    this.bezitNummers,
    required this.bestand,
    required this.idsBestand,
    this.nummersBestand,
    this.log,
    DateTime Function()? klok,
  }) : klok = klok ?? DateTime.now;

  /// De dienst van deze pc, als die er is. Zie `server.dart` (`/api/releases`) en de startpagina.
  static NieuweReleases? pc;

  final NieuweReleasesZoeker zoeker;
  final List<EigenArtiest> Function() nummers;
  final Set<String> Function() bezit;

  /// [bezitssleutel]s van de nummers die je hebt (artiest + titel), voor [kiesNieuweNummers].
  final Set<String> Function()? bezitNummers;
  final File bestand, idsBestand;

  /// Waar de nummers per album bewaard worden ([NieuweReleasesZoeker.nummers]). Null = niet bewaren.
  final File? nummersBestand;
  final void Function(String regel)? log;
  final DateTime Function() klok;

  /// Elke drie uur (Saber, 19-10-2026); per artiest onthouden, zodat een ronde weinig vraagt.
  static const houdbaar = Duration(hours: 3);

  ReleasesLijst? _lijst;
  ReleasesLijst? get lijst => _lijst;
  Future<ReleasesLijst?>? _bezig;
  Timer? _klokje;
  final _luisteraars = <void Function()>[];

  void luister(void Function() f) => _luisteraars.add(f);
  void stopLuisteren(void Function() f) => _luisteraars.remove(f);

  bool get verouderd =>
      _lijst == null ||
      _lijst!.oudeVorm ||
      klok().millisecondsSinceEpoch - _lijst!.berekendMs > houdbaar.inMilliseconds;

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
    try {
      final f = nummersBestand;
      if (f != null && await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          for (final e in j.entries) {
            final id = int.tryParse('${e.key}');
            if (id == null || e.value is! List) continue;
            final lijst = e.value as List;
            if (!lijst.every(AlbumNummer.metJaar)) continue;
            zoeker.nummers[id] = [for (final n in lijst) ?AlbumNummer.fromJson(n)];
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

  Future<void> _bewaarIds() async {
    try {
      await idsBestand.writeAsString(jsonEncode({
        for (final e in zoeker.ids.entries) e.key: {'id': e.value.id, 'ms': e.value.ms},
      }));
    } catch (_) {/* niet bewaard: dan herkent de volgende ronde ze opnieuw */}
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
    // Al je artiesten (Saber, 19-10-2026), de meest gedraaide eerst: die worden elke ronde opnieuw
    // gevraagd, de rest één keer per dag. Zie [NieuweReleasesZoeker.zoekAlles].
    final top = relevanteArtiesten(alle, nuMs: nu.millisecondsSinceEpoch, max: 2000);
    final v = ReleasesVerslag();
    try {
      final uit = await zoeker.zoekAlles(top,
          nu: nu,
          alInBezit: bezit(),
          nummersInBezit: bezitNummers?.call() ?? const {},
          verslag: v,
          tussendoor: (regel) async {
            log?.call('releases: bezig — $regel (${DateTime.now().difference(t0).inSeconds} s)');
            await _bewaarIds();
          });
      final lijst = ReleasesLijst(nu.millisecondsSinceEpoch, uit.oud, nummers: uit.nummers, albums: uit.albums);
      _lijst = lijst;
      await bestand.writeAsString(jsonEncode(lijst.toJson()));
      await _bewaarIds();
      final nb = nummersBestand;
      if (nb != null) {
        await nb.writeAsString(jsonEncode({
          for (final e in zoeker.nummers.entries) '${e.key}': [for (final n in e.value) n.toJson()],
        }));
      }
      log?.call('releases: ${uit.oud.length} oud, ${uit.nummers.length} nummers, ${uit.albums.length} albums in '
          '${DateTime.now().difference(t0).inMilliseconds} ms — $v');
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
