import 'package:http/http.dart' as http;

import 'discogs.dart';
import 'editions.dart';
import 'json_body.dart';
import 'musicbrainz.dart';
import 'organize.dart' show zonderBeeld;
import 'settings.dart';

/// One candidate release/track from a metadata provider — used by the manual
/// "correct metadata" editor to fix a wrong cover/artist/title.
class MetaResult {
  final String title; // track title (single) or album title
  final String artist;
  final String album;
  final String? coverUrl;

  /// The Discogs release this candidate IS, when it came from Discogs. Picking a release in the
  /// editor used to change only the name and the front cover — the app then went off and chose its
  /// own edition for everything else, so the back cover and the disc never followed.
  final int? releaseId;

  /// The MusicBrainz release this candidate IS, when it came from there. Kept separately from
  /// [releaseId] rather than replacing it: an MBID is a string and a Discogs id is a number, and
  /// pins already written to disk as numbers have to keep working.
  final String? mbid;

  /// What this pressing IS, in one line: "CD · Europe · 19439937972 · 2021". Five results reading
  /// "30 — Adele" and nothing else give you nothing to choose between.
  final String? detail;

  /// De scan die BEWAARD wordt als je deze regel kiest, tegenover [coverUrl] die alleen de rij van
  /// 44 punten vult.
  ///
  /// Die twee liepen door elkaar. Het Cover Art Archive werd om `front-500` gevraagd, dat plaatje
  /// vulde de lijst én werd bij het kiezen als hoes van het album weggeschreven. Vijfhonderd pixels
  /// is ruim voor een rij en zichtbaar zacht zodra een hoes een scherm vult — en het is nergens voor
  /// nodig, want hetzelfde archief levert 1200.
  ///
  /// Nu vraagt de lijst 250 (genoeg voor 44 punten, vier keer minder verkeer over vijfentwintig
  /// rijen) en het bewaren 1200. Leeg betekent: dezelfde als [coverUrl].
  final String? coverFullUrl;

  /// Is [coverUrl] in werkelijkheid een MINIATUUR van 150 pixels?
  ///
  /// De persingenlijst van Discogs geeft per rij alleen een `uri150`. Die is prima voor de rij van
  /// 44 punten en rampzalig als hoes: hij zou als `correctedCover` weggeschreven worden — de hoogste
  /// voorrang die er is, bewaard op schijf, en bij elke start weer teruggeladen. Een hoes van 150
  /// pixels op een scherm dat er 1200 vraagt.
  ///
  /// Staat dit aan, dan geeft [bewaarCover] niets terug en haalt de kiezer eerst de volle scan op.
  /// Zie `MetadataSearch.volleHoes`.
  final bool coverIsMiniatuur;

  /// De scan om te bewaren, met [coverUrl] als terugval — maar nooit een miniatuur.
  String? get bewaarCover => coverFullUrl ?? (coverIsMiniatuur ? null : coverUrl);

  const MetaResult({
    required this.title,
    required this.artist,
    required this.album,
    this.coverUrl,
    this.coverFullUrl,
    this.releaseId,
    this.mbid,
    this.detail,
    this.coverIsMiniatuur = false,
  });
}

/// Searches Deezer / Discogs / MusicBrainz for correct metadata + cover art.
class MetadataSearch {
  final AppSettings settings;
  MetadataSearch(this.settings);

  static const _ua = 'DebridMusic/0.1 ( https://github.com/sabair24/Debrid-music-app )';

  /// "Alles" staat vooraan, en dat is de belangrijkste wijziging aan dit venster.
  ///
  /// Eén bron per keer betekende dat je zelf moest weten wélke bron jouw persing kent — en dat is
  /// precies de kennis die je niet hebt als je een correctie zoekt. Discogs kent de persingen,
  /// MusicBrainz kent de uitgaven, Deezer kent de populaire namen; ze samen bevragen kost één
  /// zoekopdracht in plaats van drie, en de lijst is de vereniging van wat ze weten.
  static const providers = ['Alles', 'Discogs', 'MusicBrainz', 'Deezer'];

  /// [track] true searches individual tracks (for a single), false searches albums.
  ///
  /// For an album the query is ALSO tried as a song title, and each hit comes back as the record it
  /// is on. That is the thing Discogs does and this did not: typing "Yasmine porselein" found
  /// nothing, because there is no release by that name — the song is track four of *Prêt-à-porter*.
  /// Knowing a song and wanting the album is at least as common as the other way round.
  ///
  /// Album hits come first and the song-derived ones after, so a query that really is an album title
  /// is not pushed down the list by them. Each of those says which song put it there, because
  /// "Prêt-à-porter" appearing under a search for "porselein" is otherwise a mystery.
  /// [artist] en [album] zijn wat er in de twee velden bovenaan het venster staat, als die er zijn.
  ///
  /// **Waarom die apart meekomen en niet als één zoekregel.** Discogs en MusicBrainz kunnen allebei
  /// op artiest én titel zoeken, en dat is een heel ander soort vraag dan één string over beide
  /// velden gooien: "Michael Jackson Thriller" als vrije tekst haalt documentaires en tributes
  /// binnen, `artist=Michael Jackson&release_title=Thriller` niet. Precies dat verschil is waarom
  /// deze lijst te kort en te scheef was.
  /// De tracklijst van één gevonden persing, opgehaald wanneer je hem openklapt.
  ///
  /// **Gevraagd op 05-09-2026.** Saber, over "Metadata corrigeren": *"moet ik ook op voorhand de
  /// uitgavens kunnen openklappen, zodanig dat ik kan zien of de versies die ik staan heb er ook in
  /// staan om zo fouten te vermijden"*. Het venster toonde per regel alleen formaat, land,
  /// catalogusnummer en jaar — genoeg om persingen uit elkaar te houden, niet genoeg om te zien of
  /// JOUW nummers erop staan. En dat laatste is waarvoor je een persing kiest: *Gorillaz &
  /// G-Sides* heeft persingen met en zonder de B-kanten, en de verkeerde kiezen zet je halve plaat
  /// onder "Niet op deze uitgave".
  ///
  /// Per regel opgehaald en pas bij het openklappen — niet vooraf voor alle regels. Een zoekactie
  /// levert er tientallen, en dat zouden tientallen aanroepen zijn voor iets wat je meestal maar bij
  /// twee of drie wilt weten.
  ///
  /// Leeg betekent: deze bron kent geen tracklijst voor deze regel. Deezer geeft er nooit een, want
  /// die kent geen persingen — dat is dezelfde reden waarom "Alles" de standaardbron is.
  /// **Een MISLUKTE opvraging is geen lege tracklijst**, en dat verschil telt hier zwaarder dan
  /// gewoonlijk. "Deze uitgave heeft geen tracklijst" leest als een eigenschap van de persing en is
  /// een reden om hem NIET te kiezen; "de bron antwoordde niet" is een reden om het opnieuw te
  /// proberen. Bij het uitproberen kwamen allebei voor — MusicBrainz geeft na te snel achter elkaar
  /// vragen een tijdje niets terug — dus gooit dit een fout in plaats van stilletjes leeg te zijn.
  Future<List<ChoiceTrack>> tracklistVan(MetaResult m) async {
    if (m.releaseId != null) {
      final e = await DiscogsService(settings).release(m.releaseId!);
      if (e == null) throw StateError('Discogs gaf deze persing niet terug.');
      final lijst = e.beeldErbij ? zonderBeeld(e.tracklist, (x) => x.position) : e.tracklist;
      return [
        for (final t in lijst)
          if (t.title.trim().isNotEmpty)
            ChoiceTrack(t.position, t.title, t.seconds, artist: t.artists.join(', ')),
      ];
    }
    if (m.mbid != null) {
      final mb = MusicBrainzService();
      final r = await mb.release(m.mbid!);
      if (r == null) throw StateError('MusicBrainz gaf deze persing niet terug.');
      return mb.tracklistOf(r);
    }
    return const [];
  }

  Future<List<MetaResult>> search(
    String provider,
    String query, {
    bool track = false,
    String artist = '',
    String album = '',
  }) async {
    if (provider == 'Alles') {
      // Alle drie tegelijk, niet na elkaar: ze wachten op verschillende servers en het duurt dus
      // zo lang als de traagste in plaats van zo lang als alle drie bij elkaar.
      //
      // Elk apart afgeschermd. Zonder dat zou één bron die een fout gooit — een verlopen
      // Discogs-token is het gewone geval — de andere twee meesleuren, en dan lijkt "Alles" minder
      // te kunnen dan elke bron los.
      Future<List<MetaResult>> veilig(String p) async {
        try {
          return await search(p, query, track: track, artist: artist, album: album);
        } catch (_) {
          return const [];
        }
      }

      final alles = await Future.wait(
          [veilig('Discogs'), veilig('MusicBrainz'), veilig('Deezer')]);
      // Discogs voorop, want dat is de bron die PERSINGEN kent — cd's, catalogusnummers, landen —
      // en dat is waar in dit venster op gekozen wordt. De andere twee vullen aan wat Discogs niet
      // heeft; dubbele persingen vallen weg in [_merged].
      return _merged(alles[0], [...alles[1], ...alles[2]]);
    }
    if (query.trim().isEmpty && album.trim().isEmpty) return [];
    final direct = switch (provider) {
      'Discogs' => await _discogs(query, artist: artist, album: album),
      'MusicBrainz' => await _musicbrainz(query, artist: artist, album: album),
      _ => await _deezer(query, track),
    };
    if (track) return direct;
    final viaTrack = switch (provider) {
      'Discogs' => await _discogsByTrack(query),
      'MusicBrainz' => await _musicbrainzByTrack(query),
      _ => await _deezerByTrack(query),
    };
    return _merged(direct, viaTrack);
  }

  /// Album hits first, song-derived after, and nothing twice.
  ///
  /// Keyed on the pressing where there is one and on artist+album otherwise: the same record found
  /// both ways is one row, and two different pressings of it stay two.
  static List<MetaResult> _merged(List<MetaResult> first, List<MetaResult> then) {
    final out = <MetaResult>[];
    final seen = <String>{};
    for (final m in [...first, ...then]) {
      final key = m.mbid ?? (m.releaseId?.toString() ?? '${m.artist}|${m.album}'.toLowerCase());
      if (seen.add(key)) out.add(m);
    }
    return out;
  }

  Future<List<MetaResult>> _deezer(String query, bool track) async {
    final path = track ? 'search' : 'search/album';
    try {
      final r = await http
          .get(Uri.parse('https://api.deezer.com/$path?q=${Uri.encodeComponent(query)}&limit=12'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return [];
      final data = (jsonBody(r)['data'] as List?) ?? const [];
      final out = <MetaResult>[];
      for (final e in data) {
        if (track) {
          final al = e['album'] as Map<String, dynamic>?;
          out.add(MetaResult(
            title: (e['title'] ?? '') as String,
            artist: (e['artist']?['name'] ?? '') as String,
            album: (al?['title'] ?? '') as String,
            coverUrl: (al?['cover_xl'] ?? al?['cover_big']) as String?,
          ));
        } else {
          out.add(MetaResult(
            title: (e['title'] ?? '') as String,
            artist: (e['artist']?['name'] ?? '') as String,
            album: (e['title'] ?? '') as String,
            coverUrl: (e['cover_xl'] ?? e['cover_big']) as String?,
          ));
        }
      }
      return out.where((m) => m.title.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Elke persing die Discogs van deze plaat kent — niet de eerste twaalf zoekresultaten.
  ///
  /// **Waarom dit venster zo weinig cd's liet zien.** Het vroeg `database/search?q=...&per_page=12`.
  /// Dat is de zoeklijst, en die is op RELEVANTIE gesorteerd: voor *Thriller* levert dat vinyl,
  /// vinyl, een laserdisc en een vhs-documentaire — terwijl Discogs honderden persingen van die
  /// plaat heeft, cd's incluis. Twaalf van de honderden, en niet de twaalf waar je iets aan hebt.
  ///
  /// De uitgavekiezer had dit al opgelost, en de reden staat daar met zoveel woorden bij: Discogs
  /// heeft tweeëntwintig masters die "Michael Jackson - Thriller" heten, en de best scorende is een
  /// vinyl-only ingang met twee versies. Wie daar stopt, ziet vinyl en concludeert dat er geen cd's
  /// bestaan. [DiscogsService.releaseChoices] loopt daarom méér masters af en haalt van elk de
  /// persingen op. Dat is precies dezelfde vraag als hier, en het antwoord hoort ook hetzelfde te
  /// zijn — twee lijsten van dezelfde plaat die elkaar tegenspreken is hoe dit venster aanvoelde.
  ///
  /// Zonder artiest valt hij terug op de oude zoeklijst: `releaseChoices` heeft een artiest nodig om
  /// de masters te vinden, en een lege lijst zou hier slechter zijn dan een korte.
  Future<List<MetaResult>> _discogs(String query, {String artist = '', String album = ''}) async {
    if (settings.discogsToken.isEmpty) return [];
    final wie = artist.trim(), wat = album.trim();
    if (wie.isEmpty || wat.isEmpty) return _discogsZoeklijst(query);
    try {
      // Eén pagina per master. `maxPaginas <= 1` vraagt er vijftig tegelijk op — genoeg om alle
      // formaten te zien — en het scheelt de reeks vervolgverzoeken die dit venster niet kan
      // betalen: er staat iemand te wachten met een draaiend wieltje.
      final keuzes = await DiscogsService(settings)
          .releaseChoices(wie, wat, max: 60, maxPaginas: 1);
      if (keuzes.isEmpty) return _discogsZoeklijst(query);
      final persingen = [
        for (final k in keuzes)
          MetaResult(
            title: wat,
            artist: wie,
            album: wat,
            coverUrl: k.front?.thumb ?? k.front?.uri,
            // De volle scan alleen als hij er echt een IS. Zie [MetaResult.coverIsMiniatuur]: de
            // persingenlijst geeft 150 pixels, en die als hoes wegschrijven is de val die deze app
            // al eens ingelopen is.
            coverFullUrl: (k.front != null && !k.front!.alleenMiniatuur) ? k.front!.uri : null,
            coverIsMiniatuur: k.front?.alleenMiniatuur ?? false,
            releaseId: k.releaseId > 0 ? k.releaseId : null,
            mbid: k.mbid,
            detail: persingRegel(k),
          )
      ];
      // De persingen vóórop, want dat is waar in dit venster op gekozen wordt. De zoeklijst
      // erachteraan, en niet in plaats daarvan: die is de enige van de twee die TITELS meebrengt.
      //
      // Een persing van deze plaat weet niet hoe de plaat heet — hij is er een persing ván, en de
      // titel komt uit het veld hierboven. Alleen persingen tonen zou dus stilletjes de helft van
      // dit venster uitzetten: het heet "metadata corrigeren", en een naam corrigeren hoort daar
      // net zo goed bij als de juiste cd aanwijzen. Dubbele vallen weg in [_merged], en die houdt
      // de eerste — dus een persing blijft een persing.
      return _merged(persingen, await _discogsZoeklijst(query));
    } catch (_) {
      // Een fout hier hoort niet het hele venster leeg te laten: de zoeklijst is minder, maar hij
      // is er wel.
      return _discogsZoeklijst(query);
    }
  }

  /// De oude, ondiepe zoeklijst. Terugval voor wanneer er geen artiest bekend is.
  Future<List<MetaResult>> _discogsZoeklijst(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final tok = Uri.encodeComponent(settings.discogsToken);
      final r = await http.get(
        Uri.parse('https://api.discogs.com/database/search?type=release&token=$tok&q=${Uri.encodeComponent(query)}&per_page=25'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return [];
      return _discogsRows(jsonBody(r));
    } catch (_) {
      return [];
    }
  }

  /// De volle scan van een Discogs-persing, voor een rij die alleen een miniatuur meebracht.
  ///
  /// Eén verzoek, en alleen op het moment dat iemand een rij aantikt. Dit voor alle zestig rijen
  /// vooraf doen zou zestig verzoeken kosten uit een budget van zestig per minuut — voor rijen waar
  /// niemand naar kijkt.
  Future<String?> volleHoes(MetaResult m) async {
    final id = m.releaseId;
    if (id == null || id <= 0) return null;
    try {
      final vol = await DiscogsService(settings)
          .detailOf(ReleaseChoice(source: EditionSource.discogs, releaseId: id));
      final f = vol?.front;
      if (f == null || f.alleenMiniatuur) return null;
      return f.uri;
    } catch (_) {
      return null;
    }
  }

  /// "CD · Netherlands · 9902241 · 1995" — waar een rij op te kiezen valt.
  static String? persingRegel(ReleaseChoice k) {
    final bits = <String>[
      if (k.format.isNotEmpty) k.format,
      if ((k.country ?? '').isNotEmpty) k.country!,
      if ((k.catno ?? '').isNotEmpty) k.catno!,
      if (k.year != null) '${k.year}',
    ];
    return bits.isEmpty ? null : bits.join(' · ');
  }

  /// Discogs search results as rows. Shared, because searching by title and searching by track
  /// answer in exactly the same shape — only the question differs.
  ///
  /// [because] names the song that brought these in, for the search that asked by track.
  static List<MetaResult> _discogsRows(dynamic body, {String? because}) {
    final results = (body is Map ? body['results'] as List? : null) ?? const [];
    final out = <MetaResult>[];
    for (final e in results) {
      if (e is! Map) continue;
      final ttl = (e['title'] ?? '') as String; // usually "Artist - Album"
      var artist = '', album = ttl;
      final dash = ttl.indexOf(' - ');
      if (dash > 0) {
        artist = ttl.substring(0, dash).trim();
        album = ttl.substring(dash + 3).trim();
      }
      final cover = (e['cover_image'] ?? e['thumb']) as String?;
      // Format first, because it is the thing worth choosing on: a CD carries a catalogue number
      // and a country, a digital entry usually carries neither.
      final formats = [for (final f in (e['format'] as List? ?? const [])) f.toString()];
      final bits = <String>[
        if (formats.isNotEmpty) formats.first,
        if ((e['country'] as String?)?.isNotEmpty ?? false) e['country'] as String,
        if ((e['catno'] as String?)?.isNotEmpty ?? false) e['catno'] as String,
        if ((e['year'] as String?)?.isNotEmpty ?? false) e['year'] as String,
      ];
      final line = bits.isEmpty ? null : bits.join(' · ');
      out.add(MetaResult(
        title: album,
        artist: artist,
        album: album,
        coverUrl: (cover != null && cover.isNotEmpty && !cover.contains('spacer')) ? cover : null,
        releaseId: (e['id'] as num?)?.toInt(),
        detail: because == null ? line : _because(because, line),
      ));
    }
    return out;
  }

  /// Every pressing MusicBrainz knows, CD first, each saying what it is.
  ///
  /// This used to return bare titles: five rows reading "30 — Adele" with nothing to choose
  /// between, and picking one changed the album's name and nothing else. The pressing is now
  /// described the same way a Discogs row is, and its MBID travels with it so the choice can
  /// actually be pinned.
  Future<List<MetaResult>> _musicbrainz(String query, {String artist = '', String album = ''}) async {
    try {
      final mb = MusicBrainzService();
      // Staan de twee velden bovenaan het venster ingevuld, dan is de vraag al gesteld en hoeft er
      // niets uit een zoekregel afgeleid te worden. Dat scheelt niet alleen raadwerk maar ook
      // verzoeken: het uitpluizen hieronder doet er één per poging om de artiest te herkennen.
      if (artist.trim().isNotEmpty && album.trim().isNotEmpty) {
        return _mbRijen(await mb.searchReleases(artist.trim(), album.trim(), max: 25));
      }
      // The query MUST be scoped to an artist. Unscoped, MusicBrainz matches the whole string as
      // one phrase against the release title, so "Daft Punk Discovery" finds two SM64-soundfont
      // parodies and nothing else — it has no popularity signal to rescue a bad match. Split on
      // "Artist - Album" first, then fall back to resolving the leading words as an artist.
      artist = '';
      album = query.trim();
      final dash = query.indexOf(' - ');
      if (dash > 0) {
        artist = query.substring(0, dash).trim();
        album = query.substring(dash + 3).trim();
      } else {
        final words = query.trim().split(RegExp(r'\s+'));
        // Try the longest leading run of words that names a real artist, shortest search first.
        for (var take = words.length - 1; take >= 1; take--) {
          final cand = words.take(take).join(' ');
          final a = await mb.resolveArtist(cand);
          if (a != null && a.name.toLowerCase() == cand.toLowerCase()) {
            artist = a.name;
            album = words.skip(take).join(' ');
            break;
          }
        }
      }
      return _mbRijen(await mb.searchReleases(artist, album.isEmpty ? query.trim() : album, max: 25));
    } catch (_) {
      return [];
    }
  }

  /// MusicBrainz-uitgaven als rijen. Gedeeld, want de twee wegen hierboven — met en zonder ingevulde
  /// velden — leveren precies dezelfde soort treffers op.
  static List<MetaResult> _mbRijen(List<MbRelease> hits) => [
        for (final r in hits)
          if (r.title.isNotEmpty)
            MetaResult(
              title: r.title,
              artist: r.artist,
              album: r.title,
              // The archive answers 404 for a pressing with no scans, which the image widget shows
              // as an empty box — honest, and the row is still choosable on its edition line.
              coverUrl: 'https://coverartarchive.org/release/${r.mbid}/front-250',
              coverFullUrl: 'https://coverartarchive.org/release/${r.mbid}/front-1200',
              mbid: r.mbid,
              detail: r.line.isEmpty ? null : r.line,
            )
      ];

  // ── The same question, asked as a song ──────────────────────────────────────

  /// One line saying which song brought this record into the list.
  static String _because(String song, String? existing) {
    final via = 'bevat “$song”';
    return existing == null || existing.isEmpty ? via : '$existing · $via';
  }

  /// Deezer already answers this: a track hit names the album it is on.
  Future<List<MetaResult>> _deezerByTrack(String query) async {
    final tracks = await _deezer(query, true);
    return [
      for (final t in tracks)
        if (t.album.isNotEmpty)
          MetaResult(
            // The row is a RECORD now, so its title is the album's — the song is why it is here.
            title: t.album,
            artist: t.artist,
            album: t.album,
            coverUrl: t.coverUrl,
            coverFullUrl: t.coverFullUrl,
            detail: _because(t.title, t.detail),
          )
    ];
  }

  /// Discogs searches tracklists directly — `track=` is a field of its release search.
  Future<List<MetaResult>> _discogsByTrack(String query) async {
    if (settings.discogsToken.isEmpty) return [];
    try {
      final tok = Uri.encodeComponent(settings.discogsToken);
      final r = await http.get(
        Uri.parse('https://api.discogs.com/database/search?type=release&token=$tok'
            '&track=${Uri.encodeComponent(query)}&per_page=12'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return [];
      return _discogsRows(jsonBody(r), because: query);
    } catch (_) {
      return [];
    }
  }

  /// A song title, then the records it was recorded onto.
  ///
  /// Two steps and one request: the recording search already answers with the releases each hit
  /// appears on, so no per-recording lookup is needed — which matters on a service that asks for
  /// one request a second.
  Future<List<MetaResult>> _musicbrainzByTrack(String query) async {
    try {
      final mb = MusicBrainzService();
      // Scoped the same way the album search is: "Yasmine porselein" is an artist and a song, and
      // unscoped it matches the whole string as one phrase against the title.
      var artist = '', song = query.trim();
      final dash = query.indexOf(' - ');
      if (dash > 0) {
        artist = query.substring(0, dash).trim();
        song = query.substring(dash + 3).trim();
      } else {
        final words = query.trim().split(RegExp(r'\s+'));
        for (var take = words.length - 1; take >= 1; take--) {
          final cand = words.take(take).join(' ');
          final a = await mb.resolveArtist(cand);
          if (a != null && a.name.toLowerCase() == cand.toLowerCase()) {
            artist = a.name;
            song = words.skip(take).join(' ');
            break;
          }
        }
      }
      if (song.isEmpty) return [];
      final found = await mb.searchRecordings(song, artist: artist, max: 25);
      final out = <MetaResult>[];
      // One row per RECORD, not per pressing. "Porselein" sits on sixteen releases of which fifteen
      // are compilations, and listing them all buries the one album somebody wanted under a
      // greatest-hits pile. Titles are already ranked studio-album-first by searchRecordings.
      final byTitle = <String>{};
      for (final rec in found) {
        for (final rel in rec.releases) {
          if (!byTitle.add(rel.title.toLowerCase())) continue;
          out.add(MetaResult(
            title: rel.title,
            artist: rec.artist,
            album: rel.title,
            coverUrl: 'https://coverartarchive.org/release/${rel.mbid}/front-250',
            coverFullUrl: 'https://coverartarchive.org/release/${rel.mbid}/front-1200',
            mbid: rel.mbid,
            detail: _because(rec.title, rel.isCompilation ? 'verzamelaar' : null),
          ));
          // Enough to find the record without turning the dialog into a discography.
          if (out.length >= 12) return out;
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}
