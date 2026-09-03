import 'dart:math';

import 'deezerbaan.dart';

import 'models.dart' show Track;
import 'organize.dart' show artistKey;

/// De sleutel waarop "heb ik dit al?" beantwoord wordt.
///
/// Versiemarkeringen gaan eruit — "(2012 Remaster)", "[Live]", "- Single Version" — en alles vanaf
/// " feat" ook, zodat een schoon bestand in de bibliotheek matcht met een Deezer-titel die ze wél
/// draagt, en andersom.
///
/// Dat het zo los is, is met opzet. Bezit je een nummer, dan hoef je het niet aanbevolen te krijgen
/// omdat het een andere mix is. De strengere weg bestaat ook — `LibraryStore.ownedTrack` houdt de
/// markeringen juist vast — maar die beantwoordt een andere vraag: "heb ik precies dít bestand?".
String recNorm(String s) {
  var x = s.toLowerCase();
  x = x.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ');
  final f = x.indexOf(' feat');
  if (f > 0) x = x.substring(0, f);
  return x.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// De sleutels van alles wat er al staat, om aanbevelingen tegen te houden.
Set<String> bezitSleutels(Iterable<Track> eigen) =>
    {for (final t in eigen) '${recNorm(t.artist)}|${recNorm(t.title)}'};

/// De aanbevelingen die nog níét in de bibliotheek staan.
///
/// "Aanbevolen voor jou" hield zijn uitkomst nergens tegen de bibliotheek. De sprong via verwante
/// artiesten nijgt naar onbekend werk, maar verwante artiesten van jouw eigen bibliotheek zijn
/// geregeld je eigen bibliotheek — en dan staat er een rij met muziek die je al hebt.
///
/// Alleen op NUMMERS filteren en niet op artiesten: dat je iemand kent betekent niet dat hij nooit meer
/// langs mag komen.
List<RecTrack> nogNietInBezit(List<RecTrack> recs, Set<String> bezit) =>
    [for (final r in recs) if (!bezit.contains('${recNorm(r.artist)}|${recNorm(r.title)}')) r];

/// Which of Deezer's artist hits is the artist actually meant.
///
/// Deezer's artist search is not ranked by popularity, and the difference is not subtle: searching
/// "Adele" puts "Adele & The Chandeliers" (41 fans) first and the real Adele (15,429,227) fifth;
/// "Michael Jackson" leads with an 86-fan account. Taking row one — which is what asking for
/// limit=1 did — built the entire radio around a namesake with no catalogue, so /radio answered
/// "no data" and the Radio button came back empty.
///
/// The rule: the name has to be the name that was asked for, and among those, the one people
/// actually listen to. Fan count is the only popularity signal Deezer gives without a key, and it
/// separates fifteen million from forty-one without ambiguity. An exact name always outranks fans,
/// so "Enrique Iglesias & Ana Mena" can never win the query "Enrique Iglesias" — a collaboration
/// is a different act, however popular.
///
/// Names are compared through [artistKey], so "Beyonce" finds "Beyoncé".
///
/// **En de naam moet er wél iets mee te maken hebben.** Fans beslisten hier tussen ALLE treffers,
/// ook die waarvan de naam niets met de vraag te maken had — en Deezers zoekfunctie is losjes. Vraag
/// je een act uit een radioplan op die Deezer niet zo spelt, dan won gewoon de bekendste naam die
/// toevallig in de uitslag stond. Zo belandde er een traag U2-nummer midden in een eurodance-radio:
/// niet omdat het model U2 noemde, maar omdat een naam die erop leek nergens te vinden was en U2
/// vijf miljoen luisteraars heeft. Eén zaadartiest zonder nummers kost niets — er staan er veertig
/// in een plan — maar de complete discografie van een wildvreemde artiest bederft de hele radio.
int? pickArtist(List<dynamic> hits, String wanted) {
  final want = artistKey(wanted);
  final alle = [for (final h in hits) if (h is Map && h['id'] != null) h];
  // Bij een korte naam alleen een exacte treffer. "U96" en "U2" schelen één teken en zijn twee
  // verschillende werelden; bij drie tekens zegt "lijkt erop" niets meer.
  bool verwant(Object? naam) {
    final k = artistKey('${naam ?? ''}');
    if (k == want) return true;
    if (k.length < 4 || want.length < 4) return false;
    return k.contains(want) || want.contains(k);
  }

  final rows = [for (final r in alle) if (verwant(r['name'])) r];
  if (rows.isEmpty) return null;
  rows.sort((a, b) {
    final ea = artistKey('${a['name'] ?? ''}') == want;
    final eb = artistKey('${b['name'] ?? ''}') == want;
    if (ea != eb) return ea ? -1 : 1;
    final fa = (a['nb_fan'] as num?)?.toInt() ?? 0;
    final fb = (b['nb_fan'] as num?)?.toInt() ?? 0;
    return fb.compareTo(fa);
  });
  return (rows.first['id'] as num?)?.toInt();
}

/// A recommended track (metadata only) — resolved to a playable source on demand.
class RecTrack {
  final String artist;
  final String title;
  final String? cover;

  /// Which record it is on, and Deezer's id for it. Empty and 0 when the source did not say.
  ///
  /// Both were always in the answer — the cover above is that same album's — and throwing them away
  /// is why a tile under "Aanbevolen voor jou" could only start playing. Every other row on that
  /// screen opens the album; this one now can too.
  final String album;
  final int albumId;

  /// Hoe lang het nummer duurt, in seconden — 0 als de bron het niet zei.
  ///
  /// Stond ook altijd al in het antwoord en werd weggegooid. Het doet er pas toe sinds de radio
  /// nummers ophaalt: zonder looptijd beantwoordt de bibliotheek "die heb je al" op artiest + titel
  /// alleen, en dan wordt een heropname als mindere dubbel van schijf gewist. Zie `TrackTags.seconds`
  /// voor het gemelde Sting-geval.
  final int seconds;
  const RecTrack(this.artist, this.title, this.cover,
      {this.album = '', this.albumId = 0, this.seconds = 0});

  /// True when there is a record to open rather than only a song to play.
  bool get hasAlbum => albumId > 0 && album.trim().isNotEmpty && artist.trim().isNotEmpty;
  String get query => artist.isEmpty ? title : '$artist $title';
}

/// Recommendation engine (Deezer, keyless): artist radio + related artists,
/// for Radio / Smart Shuffle / discovery.
class RecommendService {
  static const _base = 'https://api.deezer.com';

  /// Waar de laatste aanroep op stukliep, of leeg. Zie [CatalogService.laatsteFout] — dezelfde
  /// reden: een weigering en een lege oogst zagen er van buiten hetzelfde uit.
  String laatsteFout = '';

  /// Via de gedeelde rijbaan, samen met [CatalogService]. Deze twee vuurden hun verzoeken los van
  /// elkaar af en overschreden zo samen het budget dat elk apart netjes leek te respecteren.
  Future<Map<String, dynamic>?> _get(String url) async {
    try {
      final j = await DeezerBaan.haal(url);
      if (j != null) laatsteFout = '';
      return j;
    } on DeezerFout catch (e) {
      laatsteFout = e.uitleg;
      return null;
    } catch (e) {
      laatsteFout = '$e';
      return null;
    }
  }

  Future<int?> _artistId(String name) async {
    final j = await _get('$_base/search/artist?q=${Uri.encodeComponent(name)}&limit=10');
    return pickArtist((j?['data'] as List?) ?? const [], name);
  }

  List<RecTrack> _tracks(Map<String, dynamic>? j) {
    final data = (j?['data'] as List?) ?? const [];
    return data
        .map((t) => RecTrack(
              ((t['artist']?['name']) ?? '') as String,
              (t['title'] ?? '') as String,
              (t['album']?['cover_medium']) as String?,
              album: ((t['album']?['title']) ?? '') as String,
              albumId: ((t['album']?['id']) as num?)?.toInt() ?? 0,
              seconds: (t['duration'] as num?)?.toInt() ?? 0,
            ))
        .where((r) => r.title.isNotEmpty)
        .toList();
  }

  /// De toppers van één artiest.
  ///
  /// De basis van een radio uit een getypte zin: het taalmodel noemt de ARTIESTEN, en hier wordt
  /// opgezocht welke nummers er van hen werkelijk bestaan. Vijfhonderd tracktitels uit het hoofd van
  /// een model zijn voor een deel verzonnen; deze lijst niet.
  Future<List<RecTrack>> topVan(String artiest, {int limit = 15}) async {
    final id = await _artistId(artiest);
    if (id == null) return const [];
    return _tracks(await _get('$_base/artist/$id/top?limit=$limit'));
  }

  /// Radio (~25 tracks) around an artist — the seed artist mixed with similar ones.
  Future<List<RecTrack>> artistRadio(String artist) async {
    final id = await _artistId(artist);
    if (id == null) return [];
    return _tracks(await _get('$_base/artist/$id/radio'));
  }

  /// Deduped radio built from the seed artist's own top tracks + a "similar" flow
  /// + a few related artists' top tracks. Including the seed's own catalogue is what
  /// lets Smart Shuffle lead with tracks the listener already owns (instant playback);
  /// the similar/related tracks are the discovery layer.
  Future<List<RecTrack>> mixRadio(String artist) async {
    final id = await _artistId(artist);
    if (id == null) return artistRadio(artist);
    final out = <RecTrack>[];
    final seen = <String>{};
    void add(Iterable<RecTrack> ts) {
      for (final t in ts) {
        if (seen.add('${t.artist.toLowerCase()}|${t.title.toLowerCase()}')) out.add(t);
      }
    }

    // Seed's own top tracks + seed "radio" (similar) + related-artist list, concurrently
    // (reusing the one artist id). Deezer's /radio is a similar-artist flow that omits the
    // seed, so /top is needed for the seed's own songs to appear in the queue at all.
    final topF = _get('$_base/artist/$id/top?limit=15');
    final radioF = _get('$_base/artist/$id/radio');
    final relF = _get('$_base/artist/$id/related?limit=4');
    add(_tracks(await topF));
    add(_tracks(await radioF));
    final rel = ((await relF)?['data'] as List?) ?? const [];
    final tops = await Future.wait(rel.take(4).map((a) => _get('$_base/artist/${a['id']}/top?limit=5')));
    for (final t in tops) {
      add(_tracks(t));
    }
    out.shuffle();
    return out;
  }

  /// Discovery feed: top tracks from artists related to the given library seeds.
  Future<List<RecTrack>> discover(List<String> seeds) async {
    final out = <RecTrack>[];
    final seen = <String>{};
    void add(Iterable<RecTrack> ts) {
      for (final t in ts) {
        if (seen.add('${t.artist.toLowerCase()}|${t.title.toLowerCase()}')) out.add(t);
      }
    }

    // Zes en niet vier. De aanroeper gaf er al zes mee en hier vielen er twee stil weg — en sinds de
    // uitkomst tegen de bibliotheek wordt gehouden, blijft er van een krappe oogst weinig over.
    for (final s in seeds.take(6)) {
      final id = await _artistId(s);
      if (id == null) continue;
      // TWINTIG OPHALEN EN ER VIER UIT TREKKEN, in plaats van er vier op te halen.
      //
      // `related?limit=20` kost exact hetzelfde ene verzoek als `limit=4` — nagemeten: Deezer geeft
      // er standaard twintig terug. De app vroeg er vier en gebruikte altijd diezelfde vier, dus
      // zag je bij Backstreet Boys eeuwig *NSYNC, Westlife, Christina Aguilera en Five, terwijl
      // Spice Girls, Kelly Clarkson, Boyzone, A*Teens en M2M er ook in stonden.
      //
      // Dit is de goedkoopste variatiewinst in het hele scherm: nul extra verzoeken, en het is wat
      // de ververs-knop pas iets laat betekenen — anders komt daar dezelfde lijst terug.
      final rel = ((await _get('$_base/artist/$id/related?limit=20'))?['data'] as List?) ?? const [];
      final pool = [...rel]..shuffle(_toeval);
      final tops = await Future.wait(
          pool.take(4).map((a) => _get('$_base/artist/${a['id']}/top?limit=6')));
      for (final t in tops) {
        add(_tracks(t));
      }
    }
    out.shuffle(_toeval);
    return out;
  }

  /// Waar het schudden zijn toeval vandaan haalt.
  ///
  /// Instelbaar zodat een test een verwachting kan uitschrijven; in de app is het gewoon het
  /// toeval van het systeem.
  Random? _toevalBron;
  Random? get _toeval => _toevalBron;
  set toeval(Random? r) => _toevalBron = r;
}
