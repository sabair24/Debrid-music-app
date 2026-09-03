import 'deezerbaan.dart';

/// Deezer catalog (keyless) — powers the Stremio-style browse:
/// search artist → their albums → an album's tracks. Sources (torrents/Soulseek)
/// are then searched per track/album via the existing OnlineService/SoulseekService.
/// Which catalogue an identity came from, and its id AT that catalogue.
///
/// This replaces the sign trick — positive meant Deezer, negative meant Discogs. That encoding
/// had no third value left, and a MusicBrainz id is a 36-character string that no int can hold.
/// A lossy encoding would land in the wrong arm of the dispatch AND in the download manager's
/// dedupe, where a false match silently REFUSES a download the user asked for.
///
/// The sign trick also quietly meant two different things: a negative id was a Discogs release
/// from search but a Discogs MASTER from the style page, and feeding a master id to the release
/// endpoint is why an album opened from a style page came up with no tracklist.
enum CatalogSource { deezer, discogsRelease, discogsMaster, musicbrainz, musicbrainzGroup }

class CatalogRef {
  final CatalogSource source;

  /// A decimal integer for Deezer and Discogs, an MBID for MusicBrainz. One field, because the
  /// only thing every catalogue agrees on is that an id is text.
  final String id;
  const CatalogRef(this.source, this.id);

  factory CatalogRef.deezer(int id) => CatalogRef(CatalogSource.deezer, '$id');
  factory CatalogRef.discogsRelease(int id) => CatalogRef(CatalogSource.discogsRelease, '$id');
  factory CatalogRef.discogsMaster(int id) => CatalogRef(CatalogSource.discogsMaster, '$id');
  factory CatalogRef.musicbrainz(String mbid) => CatalogRef(CatalogSource.musicbrainz, mbid);

  /// A RECORD rather than one of its pressings. Search returns these; opening one resolves it to
  /// an actual pressing first, because only a pressing has a tracklist.
  factory CatalogRef.musicbrainzGroup(String mbid) =>
      CatalogRef(CatalogSource.musicbrainzGroup, mbid);

  int get intId => int.tryParse(id) ?? 0;
  bool get isMb =>
      source == CatalogSource.musicbrainz || source == CatalogSource.musicbrainzGroup;

  /// What this identity contributes to a download key.
  ///
  /// Deezer and Discogs keep the OLD sign encoding byte for byte, so every download already
  /// waiting in pending_downloads.json still matches its row after an update. Only the new source
  /// gets a prefix, and "mb:…" can never equal a decimal integer, so nothing collides.
  String get keyPart {
    switch (source) {
      case CatalogSource.deezer:
        return id;
      case CatalogSource.discogsRelease:
      case CatalogSource.discogsMaster:
        return '-$id';
      case CatalogSource.musicbrainz:
        return 'mb:$id';
      case CatalogSource.musicbrainzGroup:
        return 'mbg:$id';
    }
  }
}

class CatalogArtist {
  final int id;
  final String name;
  final String? picture;
  final int albumCount;

  /// Where this artist came from. Null means Deezer, which is what an int id always meant.
  final CatalogRef? origin;

  /// "Group · US · 1993–", when the source knows. Two acts share a name more often than you would
  /// think, and this is the only thing that tells them apart in a list.
  final String? detail;
  const CatalogArtist(this.id, this.name, this.picture, this.albumCount, {this.origin, this.detail});

  CatalogRef get ref => origin ?? CatalogRef.deezer(id);
}

class CatalogAlbum {
  final int id;
  final String title;
  final String? cover;
  final String? releaseDate;
  final int trackCount;
  final String recordType; // album | single | ep | compile

  /// Where this hit came from. Null on the legacy paths that still encode the source in the SIGN
  /// of [id] — [ref] reads that encoding, so no existing call site had to change at once.
  final CatalogRef? origin;

  const CatalogAlbum(this.id, this.title, this.cover, this.releaseDate, this.trackCount,
      this.recordType, {this.origin});

  CatalogRef get ref => origin ?? (id < 0 ? CatalogRef.discogsRelease(-id) : CatalogRef.deezer(id));

  String? get year => (releaseDate != null && releaseDate!.length >= 4) ? releaseDate!.substring(0, 4) : null;
  bool get isSingle => recordType == 'single';
}

class CatalogTrack {
  final int id;
  final String title;
  final String artist;
  final int durationSec;
  final int position;
  const CatalogTrack(this.id, this.title, this.artist, this.durationSec, this.position);

  String get durationLabel {
    final m = durationSec ~/ 60, s = durationSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// An album search hit — carries the artist name so browse can open its tracklist.
class CatalogAlbumHit {
  final CatalogAlbum album;
  final String artist;
  const CatalogAlbumHit(this.album, this.artist);
}

/// Alleen de albums die in [jaar] zijn uitgekomen.
///
/// Bestaat omdat de balk "NIEUWE RELEASE" albums uit 2011 en 2016 toonde. Er zat helemaal geen
/// jaarfilter op: er werd aflopend op releasedatum gesorteerd en dat was het. Deezer levert bij
/// `artist/{id}/albums` ook heruitgaves mee, en de wereldwijde hitlijst staat vol met evergreens — dus
/// "het nieuwste dat ik van deze artiest vind" is iets heel anders dan "nieuw".
///
/// Het jaar komt als parameter binnen en wordt hier niet zelf opgehaald, zodat deze regel in een test
/// uit te schrijven is zonder dat hij op de klok van de bouwmachine gaat leunen.
///
/// [CatalogAlbum.year] is TEKST (de eerste vier tekens van Deezers `release_date`), dus lezen met
/// int.tryParse: een ontbrekende of onleesbare datum valt weg in plaats van als 0 mee te tellen.
List<CatalogAlbumHit> uitJaar(List<CatalogAlbumHit> hits, int jaar) =>
    [for (final h in hits) if (int.tryParse(h.album.year ?? '') == jaar) h];

/// Een albumtitel zonder hoofdletters en leestekens, om er losjes op te kunnen vergelijken.
///
/// Klein en van hier, in plaats van `normKey` uit `organize.dart` te lenen: dat bestand sleept
/// `dart:io` en `dart:isolate` mee, en `catalog.dart` is bewust kaal HTTP.
String _kaleTitel(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// A track search hit — tapped to open torrent/Soulseek sources directly.
class CatalogTrackHit {
  final String title;
  final String artist;
  final String? cover;
  const CatalogTrackHit(this.title, this.artist, this.cover);
  String get query => artist.isEmpty ? title : '$artist $title';
}

class CatalogService {
  static const _base = 'https://api.deezer.com';

  /// Waar de laatste aanroep op stukliep, of leeg. Zodat een scherm "Deezer weigerde" kan
  /// onderscheiden van "er is niets gevonden" — twee antwoorden die er van buiten hetzelfde
  /// uitzagen zolang beide een lege lijst opleverden.
  String laatsteFout = '';

  /// Via de gedeelde rijbaan. Zie [DeezerBaan]: de startpagina vuurde eenenzestig verzoeken af waar
  /// Deezer er vijftig per vijf seconden toestaat, en de weigering kwam als status 200 met een
  /// foutlichaam binnen — dus als een lege lijst.
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

  /// Top albums right now (Deezer global chart) — for the home screen.
  Future<List<CatalogAlbumHit>> chartAlbums() async {
    final j = await _get('$_base/chart/0/albums?limit=25');
    final data = (j?['data'] as List?) ?? const [];
    return data
        .map((a) => CatalogAlbumHit(_album(a), (a['artist']?['name'] ?? '') as String))
        .where((h) => h.album.title.isNotEmpty)
        .toList();
  }

  /// Bestaat dit album van deze artiest? Zo ja, mét hoes en id.
  ///
  /// **Waarom dit bestaat.** Een taalmodel dat om albums gevraagd wordt, noemt er af en toe een die
  /// niet bestaat — overtuigend, met een plausibele titel. Een tegel op grond daarvan gaat nergens
  /// heen. Dus: het model kiest wélke plaat wordt voorgesteld, en deze functie bewijst dat hij er
  /// is. Wat hier niet gevonden wordt, verschijnt niet.
  ///
  /// Twee verzoeken per voorstel, via dezelfde rijbaan als de rest. Vandaar dat er hoogstens twaalf
  /// voorstellen gevraagd worden: het budget is gedeeld met de andere rijen.
  ///
  /// De titel wordt losjes vergeleken: hoofdletters en leestekens gaan eruit. "Oro Incenso & Birra"
  /// en "Oro, Incenso e Birra" horen hetzelfde te zijn — het model spelt niet altijd zoals de
  /// catalogus, en een tegel missen om een komma is zonde.
  Future<CatalogAlbumHit?> zoekAlbum(String artiest, String titel) async {
    if (artiest.trim().isEmpty || titel.trim().isEmpty) return null;
    final gevonden = await searchArtists(artiest);
    if (gevonden.isEmpty) return null;
    final albums = await artistAlbums(gevonden.first.id);
    final wil = _kaleTitel(titel);
    if (wil.isEmpty) return null;
    for (final a in albums) {
      final heeft = _kaleTitel(a.title);
      if (heeft.isEmpty) continue;
      if (heeft == wil || heeft.contains(wil) || wil.contains(heeft)) {
        return CatalogAlbumHit(a, gevonden.first.name);
      }
    }
    return null;
  }

  /// De hitlijsten van een handvol genres, om de beurt door elkaar gevlochten.
  ///
  /// **Waarom dit bestaat.** "Top van dit moment" was letterlijk `chart/0/albums`: Deezers algemene
  /// lijst, zonder één woord over de gebruiker. Bij iemand met 448 nummers uit de jaren 90 en een
  /// kast vol pop, R&B en dance stonden daar een sludge-metalband en twee musicalopnamen in —
  /// nagemeten op 02-09-2026, plaats 21 tot 25 van die lijst.
  ///
  /// **Om de beurt en niet achter elkaar.** Eerst de nummer 1 van elk genre, dan de nummer 2, enz.
  /// Plakte je de lijsten achter elkaar, dan zou pop met zijn negenenveertig platen de hele rij
  /// vullen en zou het kleinste genre er nooit in komen. Zo staat elk genre uit het profiel meteen
  /// vooraan.
  ///
  /// **Één verzoek per genre.** `chart/{id}` zonder subbron geeft albums, nummers én afspeellijsten
  /// tegelijk; alleen de albums worden hier gebruikt. Gemeten omvang per genre: pop 49, rap 50,
  /// rock 50, alternative 50, electro 22, jazz 14, R&B 10, dance 8. De kleine genres leveren dus
  /// weinig, en daarom is de volgorde van vlechten belangrijker dan de lengte.
  Future<List<CatalogAlbumHit>> chartPerGenre(List<int> genres, {int perGenre = 25}) async {
    if (genres.isEmpty) return [];
    final lijsten = await Future.wait(genres.map((g) async {
      final j = await _get('$_base/chart/$g?limit=$perGenre');
      final data = ((j?['albums'] as Map?)?['data'] as List?) ?? const [];
      return data
          .map((a) => CatalogAlbumHit(_album(a), (a['artist']?['name'] ?? '') as String))
          .where((h) => h.album.title.isNotEmpty)
          .toList();
    }));

    final uit = <CatalogAlbumHit>[];
    final gezien = <int>{};
    final diepste = lijsten.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (var rang = 0; rang < diepste; rang++) {
      for (final lijst in lijsten) {
        if (rang >= lijst.length) continue;
        final h = lijst[rang];
        // Op album-id ontdubbelen: een plaat kan in twee genrelijsten staan, en dan hoort hij er
        // één keer te staan op zijn beste plaats.
        if (gezien.add(h.album.id)) uit.add(h);
      }
    }
    return uit;
  }

  /// Newest albums from the artists the user already listens to (Deezer's global "editorial
  /// releases" endpoint is deprecated / empty). This is more personal anyway — "new from your
  /// artists". Runs the per-artist lookups concurrently and returns newest-release-first.
  Future<List<CatalogAlbumHit>> latestFromArtists(List<String> names) async {
    // Twaalf artiesten en vier albums per stuk, waar dat er zes en twee waren. Wie hierna op één jaar
    // filtert houdt van twaalf kandidaten meestal niets over; van achtenveertig wel iets.
    final picks = names.take(12).toList();
    final results = await Future.wait(picks.map((name) async {
      try {
        // Via searchArtists en niet via `search/artist?limit=1`, dat regel één blind overnam. Deezer
        // sorteert zijn zoekresultaten niet op bekendheid, dus die eerste regel is geregeld een
        // naamgenoot met één uitgave — en dan gaat deze hele balk over de verkeerde persoon. De
        // rangschikking (exacte naam eerst, daarna op luisteraars) staat al in searchArtists.
        final gevonden = await searchArtists(name);
        if (gevonden.isEmpty) return <CatalogAlbumHit>[];
        final albums = await artistAlbums(gevonden.first.id); // newest-first, deduped
        return albums.where((a) => !a.isSingle).take(4).map((a) => CatalogAlbumHit(a, name)).toList();
      } catch (_) {
        return <CatalogAlbumHit>[];
      }
    }));
    final out = <CatalogAlbumHit>[];
    final seen = <String>{};
    for (final list in results) {
      for (final h in list) {
        if (h.album.title.isNotEmpty && seen.add(h.album.title.toLowerCase())) out.add(h);
      }
    }
    out.sort((a, b) => (b.album.releaseDate ?? '').compareTo(a.album.releaseDate ?? ''));
    return out;
  }

  /// Top tracks right now (Deezer global chart) — for the home screen.
  Future<List<CatalogTrackHit>> chartTracks() async {
    final j = await _get('$_base/chart/0/tracks?limit=25');
    final data = (j?['data'] as List?) ?? const [];
    final seen = <String>{};
    return data
        .map((t) => CatalogTrackHit(
              (t['title'] ?? '') as String,
              (t['artist']?['name'] ?? '') as String,
              (t['album']?['cover_medium'] ?? t['album']?['cover']) as String?,
            ))
        .where((h) => h.title.isNotEmpty && seen.add('${h.artist.toLowerCase()}|${h.title.toLowerCase()}'))
        .toList();
  }

  /// Artists matching [q]. An EXACT name match outranks everything, and among equals the one with
  /// the most listeners wins — searching "Michael Jackson" otherwise returns a namesake with a
  /// single release ahead of the real one, and every page that follows is then about the wrong
  /// person.
  Future<List<CatalogArtist>> searchArtists(String q) async {
    final j = await _get('$_base/search/artist?q=${Uri.encodeComponent(q)}&limit=25');
    final data = (j?['data'] as List?) ?? const [];
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final wanted = norm(q);
    final scored = data
        .where((a) => ((a['name'] ?? '') as String).isNotEmpty)
        .map((a) => (
              artist: CatalogArtist(
                a['id'] as int,
                (a['name'] ?? '') as String,
                (a['picture_big'] ?? a['picture_medium']) as String?,
                (a['nb_album'] ?? 0) as int,
              ),
              fans: (a['nb_fan'] as num?)?.toInt() ?? 0,
            ))
        .toList();
    scored.sort((a, b) {
      final ea = norm(a.artist.name) == wanted, eb = norm(b.artist.name) == wanted;
      if (ea != eb) return ea ? -1 : 1;
      return b.fans.compareTo(a.fans);
    });
    return scored.map((e) => e.artist).toList();
  }

  /// Artists this one sits next to — the starting point for "more like this".
  Future<List<CatalogArtist>> relatedArtists(int artistId) async {
    final j = await _get('$_base/artist/$artistId/related?limit=20');
    final data = (j?['data'] as List?) ?? const [];
    return data
        .map((a) => CatalogArtist(
              a['id'] as int,
              (a['name'] ?? '') as String,
              (a['picture_big'] ?? a['picture_medium']) as String?,
              (a['nb_album'] ?? 0) as int,
            ))
        .where((a) => a.name.isNotEmpty)
        .toList();
  }

  /// Browse: albums matching a query (each keeps its artist for the tracklist page).
  Future<List<CatalogAlbumHit>> searchAlbums(String q) async {
    final j = await _get('$_base/search/album?q=${Uri.encodeComponent(q)}&limit=20');
    final data = (j?['data'] as List?) ?? const [];
    return data
        .map((a) => CatalogAlbumHit(_album(a), (a['artist']?['name'] ?? '') as String))
        .where((h) => h.album.title.isNotEmpty)
        .toList();
  }

  /// Browse: individual tracks matching a query (→ sources on tap).
  Future<List<CatalogTrackHit>> searchTracks(String q) async {
    final j = await _get('$_base/search?q=${Uri.encodeComponent(q)}&limit=25');
    final data = (j?['data'] as List?) ?? const [];
    final seen = <String>{};
    return data
        .map((t) => CatalogTrackHit(
              (t['title'] ?? '') as String,
              (t['artist']?['name'] ?? '') as String,
              (t['album']?['cover_medium'] ?? t['album']?['cover']) as String?,
            ))
        .where((h) => h.title.isNotEmpty && seen.add('${h.artist.toLowerCase()}|${h.title.toLowerCase()}'))
        .toList();
  }

  /// Everyone credited on a track, main artist first.
  ///
  /// Needed because a rip's tags often name only the main artist: the file for Lady Gaga's
  /// "Telephone" is tagged just "Lady Gaga" / "Telephone" with Beyoncé nowhere in it. Deezer's
  /// search result doesn't carry contributors either, so this costs a second call for the track
  /// itself. Cached per track — it never changes.
  final Map<String, List<String>> _contributorCache = {};

  Future<List<String>> trackContributors(String artist, String title) async {
    final key = '${artist.toLowerCase()}|${title.toLowerCase()}';
    final hit = _contributorCache[key];
    if (hit != null) return hit;

    String loose(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final wantedTitle = loose(title);
    final wantedArtist = loose(artist);

    final j = await _get('$_base/search?q=${Uri.encodeComponent('$artist $title')}&limit=8');
    final data = (j?['data'] as List?) ?? const [];
    int? id;
    for (final t in data) {
      final tt = loose((t['title'] ?? '') as String);
      final ta = loose((t['artist']?['name'] ?? '') as String);
      // The catalogue's title may carry the credit our file lacks, so match on "starts with".
      final titleOk = tt == wantedTitle || tt.startsWith(wantedTitle) || wantedTitle.startsWith(tt);
      if (titleOk && (ta == wantedArtist || ta.startsWith(wantedArtist) || wantedArtist.startsWith(ta))) {
        id = t['id'] as int?;
        break;
      }
    }
    if (id == null) return _contributorCache[key] = const [];

    final t = await _get('$_base/track/$id');
    final names = ((t?['contributors'] as List?) ?? const [])
        .map((c) => ((c as Map)['name'] ?? '') as String)
        .where((n) => n.trim().isNotEmpty)
        .toList();
    return _contributorCache[key] = names;
  }

  /// Van wie is dit album eigenlijk? Deezers hoofdartiest per album-id.
  ///
  /// Bestaat omdat `/artist/{id}/albums` GEEN artiestveld levert — gemeten, de regel draagt alleen
  /// id, titel, hoezen, genre_id, fans, release_date, record_type en tracklist. Daardoor staan platen
  /// waarop de artiest te GAST is niet te onderscheiden van zijn eigen werk, en belandde "Pavarotti &
  /// Friends for Cambodia and Tibet" tussen de albums van Enrique Iglesias. `/album/{id}` zegt het wel:
  /// `artist.name` is daar "Luciano Pavarotti", met Enrique als één van dertien gastartiesten.
  ///
  /// Eén verzoek per album, en dat is waarom de aanroeper zelf moet uitdunnen wat hij vraagt. Discogs
  /// filtert al op `role == 'Main'` en MusicBrainz browst op de releasegroepen van de artiest zelf —
  /// wat één van die twee ook kent, is dus al gedekt en hoeft hier niet langs.
  ///
  /// Deezer is hier de goedkope kant: gemeten 86 verzoeken in 12,7 s. Een lege uitkomst betekent
  /// "niet te achterhalen", nooit "van iemand anders" — bij twijfel blijft een regel staan.
  Future<Map<int, String>> albumArtists(Iterable<int> albumIds) async {
    final uit = <int, String>{};
    for (final id in albumIds) {
      if (id <= 0) continue;
      try {
        final j = await _get('$_base/album/$id');
        final naam = ((j?['artist']?['name']) as String? ?? '').trim();
        if (naam.isNotEmpty) uit[id] = naam;
      } catch (_) {/* een album dat niet antwoordt telt als onbekend, niet als vreemd */}
    }
    return uit;
  }

  Future<List<CatalogAlbum>> artistAlbums(int artistId) async {
    final j = await _get('$_base/artist/$artistId/albums?limit=100');
    final data = (j?['data'] as List?) ?? const [];
    final albums = data.map(_album).toList();
    // De-dupe by title (Deezer lists many re-releases), keep the newest, sort newest-first.
    final byTitle = <String, CatalogAlbum>{};
    for (final a in albums) {
      final k = a.title.toLowerCase();
      final cur = byTitle[k];
      if (cur == null || (a.releaseDate ?? '').compareTo(cur.releaseDate ?? '') > 0) byTitle[k] = a;
    }
    final out = byTitle.values.toList()
      ..sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
    return out;
  }

  /// The album (with cover) + its ordered tracklist.
  Future<(CatalogAlbum?, List<CatalogTrack>)> albumTracks(int albumId) async {
    final j = await _get('$_base/album/$albumId');
    if (j == null) return (null, const <CatalogTrack>[]);
    final album = _album(j);
    final artistName = (j['artist']?['name'] ?? '') as String;
    final td = ((j['tracks']?['data']) as List?) ?? const [];
    final tracks = td
        .map((t) => CatalogTrack(
              t['id'] as int,
              (t['title'] ?? '') as String,
              ((t['artist']?['name']) ?? artistName) as String,
              (t['duration'] ?? 0) as int,
              (t['track_position'] ?? 0) as int,
            ))
        .toList();
    return (album, tracks);
  }

  CatalogAlbum _album(dynamic a) => CatalogAlbum(
        a['id'] as int,
        (a['title'] ?? '') as String,
        (a['cover_big'] ?? a['cover_medium'] ?? a['cover']) as String?,
        a['release_date'] as String?,
        (a['nb_tracks'] ?? 0) as int,
        (a['record_type'] ?? 'album') as String,
      );
}
