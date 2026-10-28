/// Haalt een discografie op bij drie catalogi en bewaart het antwoord.
///
/// Het samenvoegen zelf staat in `discography.dart` en is puur; hier zit alleen het ophalen, de
/// naamcontrole en de cache. Die scheiding is met opzet: het lastige deel — wanneer zijn twee regels
/// dezelfde plaat — is daardoor te testen zonder één netwerkverzoek na te bootsen.
///
/// Bewust NIET in [CatalogService]. Die is per eigen documentatie Deezer-only, kent geen
/// [AppSettings] en dus geen Discogs-token, en wordt overal los geconstrueerd. Bovendien importeert
/// `discogs.dart` al `catalog.dart`, dus het zou een kring worden.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cachesleutel.dart';
import 'catalog.dart';
import 'discography.dart';
import 'discogs.dart';
import 'musicbrainz.dart';
import 'organize.dart' show artistKey;
import 'paths.dart';

/// Wat één bron opleverde, en waarom hij niets opleverde als dat zo is.
///
/// "Geen token", "niet bereikbaar" en "niets gevonden" zijn drie verschillende antwoorden die er op
/// het scherm hetzelfde uitzien als je ze niet uit elkaar houdt. Discogs is de reden dat dit een
/// eigen type is: zonder token faalt daar élke aanroep stil.
enum BronStatus { klaar, geenToken, onbereikbaar, andereArtiest }

class BronUitkomst {
  final DiscoSource bron;
  final BronStatus status;
  final List<DiscoRelease> releases;

  /// Hoezen die deze bron kent voor platen die hij zelf niet als regel oplevert.
  ///
  /// Alleen Discogs vult dit, uit zijn zoeksweep. Ze staan apart van [releases] omdat ze bestaande
  /// regels van ANDERE bronnen aanvullen — MusicBrainz levert er nooit een — en er nadrukkelijk geen
  /// regels bij mogen komen. Zie [DiscogsSweep].
  final Map<String, String> hoezen;

  const BronUitkomst(this.bron, this.status, this.releases, {this.hoezen = const {}});

  bool get gelukt => status == BronStatus.klaar;
}

/// Het bewaarde antwoord voor één artiest.
class DiscoCache {
  final List<DiscoRelease> releases;
  final int fetchedMs;

  /// De hoesregel van dit antwoord (zie [bevriesDiscografie]). Null in een bestand van vóór
  /// 18-10-2026.
  final bool? zeefHoezen;
  const DiscoCache(this.releases, this.fetchedMs, {this.zeefHoezen});

  bool ouderDan(Duration d) =>
      DateTime.now().millisecondsSinceEpoch - fetchedMs > d.inMilliseconds;
}

/// De MusicBrainz-groep van de uitgave die [titel] heet en van [artiest] is, uit een zoekuitslag — of null.
///
/// Precies dezelfde titel ([discoKey]) en dezelfde artiest: de zoekvraag geeft ook "Millennium" zelf en platen
/// van naamgenoten terug, en die zeggen niets over waar "Millennium 2.0" hoort.
String? groepUitZoekuitslag(String artiest, String titel, List<MbRelease> uitslag) {
  final k = discoKey(titel);
  for (final r in uitslag) {
    final g = r.releaseGroupId;
    if (g == null || g.isEmpty || discoKey(r.title) != k) continue;
    if (r.artist.isNotEmpty && artistKey(r.artist) != artistKey(artiest)) continue;
    return g;
  }
  return null;
}

class DiscographyService {
  DiscographyService(this.catalog, this.mb, this.discogs);

  final CatalogService catalog;
  final MusicBrainzService mb;
  final DiscogsService discogs;

  /// Zit in de cachesleutel en moet omhoog bij ELKE wijziging aan het schema of aan [discoKey].
  ///
  /// Niet cosmetisch. De onderliggende caches van MusicBrainz en Discogs verlopen NOOIT, dus zonder
  /// deze marker blijft elke eerder bezochte artiest voor altijd het oude antwoord serveren — ook als
  /// de samenvoegregel intussen veranderd is. Dezelfde truc, en dezelfde reden, als `art|v6|` in
  /// discogs.dart en `v2|` in enrichment.dart.
  /// v2: Discogs-masters kregen hun soort uit de zoeksweep (waren allemaal `other`), regels zonder
  /// hoes worden aangevuld, en Deezer-gastoptredens vallen af. Zonder deze bump blijft elke eerder
  /// bezochte artiest het oude antwoord serveren — de onderliggende caches verlopen nooit.
  /// v3: MusicBrainz' tweede etiketten (Live, Remix, Interview…) worden nu eigen soorten in plaats
  /// van alles-is-album, en de browse bladert door tot 500 in plaats van bij 100 te stoppen. Drie
  /// zelfstandige redenen om te bumpen: de bewaarde `k`-waarden zijn verouderd (een livealbum staat
  /// er als `album`), de regelverzameling is groter, en de indeling zelf is veranderd.
  /// v4: dvd's, blu-rays en videobanden krijgen een eigen soort en komen niet meer op de pagina.
  /// Onder v3 stonden ze er nog — "Céline Parle D'elle(s)" (`DVD, Single, Promo, PAL`) zelfs tussen
  /// de singles, omdat het woord "Single" in het formaat stond.
  /// v5: de Discogs-hoezen zijn niet langer `thumb` (150×150, q40) maar `cover_image` (600×601,
  /// q90). De URL's staan ín dit bestand, dus zonder bump blijft elke eerder bezochte artiest zijn
  /// miniaturen tonen. GEMETEN: 73% van de Discogs-hoezen wordt hierdoor vier keer zo groot.
  /// v6: radioplaten (Discogs' formaatkenmerk `Transcription`, MusicBrainz' primary-type
  /// `Broadcast`) krijgen een eigen soort en komen niet meer op de pagina. Bij The Police waren dat
  /// twintig van de drieëndertig "albums" — BBC Rock Hour, Innerview, Off The Record Specials.
  /// v7: "Comp" wordt herkend als Compilation — dat is de ENIGE spelling die
  /// `/artists/{id}/releases` gebruikt, gemeten 1711 keer tegen nul keer "Compilation" voluit — en
  /// een plaat die aan "Various …" gecrediteerd is gaat naar de verzamelaars.
  /// v8: de jaren. Een bewaarde lijst van vóór de herkansing bij een MusicBrainz-"busy" en vóór de
  /// Discogs-masters uit de sweep draagt bij een grote catalogus het jaar van de heruitgave — bij
  /// Serge Gainsbourg *Aux armes et cætera* op 2003 en *Love on the Beat* op 2015.
  /// v9: een single of EP en een album met dezelfde titel zijn twee regels (zie [mergeDiscography]).
  /// Een bewaarde lijst draagt nog het album "Taking Chances" met de hoes en de link van de single.
  /// v10: remixuitgaven op hun titel ([soortMetTitel]) en Deezers maxisingles ([isMaxisingle]) naar de
  /// remixen, en Deezer doorgebladerd tot voorbij honderd uitgaven. Bij Madonna stonden er zestien
  /// remixuitgaven tussen de albums.
  /// v11: MusicBrainz beslist welke platen er zijn en van welke soort ([volgensMusicBrainz]); een
  /// bewaarde lijst draagt nog Deezers verzamelaars en Discogs' concertdownloads tussen de albums.
  /// v12: twee platen met dezelfde titel blijven twee regels, elk met zijn eigen Deezer-album en hoes (Seal 1991 en
  /// 1994, zie [mergeDiscography]). Een bewaarde lijst draagt nog "Seal" 1991 met de hoes en de tracklijst van de
  /// krantenuitgave van 2007, en de artiestpagina neemt de hoezen van een bewaarde lijst over in haar eigen tabel.
  static const schema = 'disco|v12';

  /// Hoe lang een bewaard antwoord meegaat voor er bij Deezer opnieuw wordt gekeken.
  ///
  /// Alleen Deezer, want die heeft geen eigen schijfcache en weet een nieuwe plaat als eerste. De twee
  /// andere blijven staan; hun bronbestanden verlopen toch niet, dus opnieuw vragen zou hetzelfde
  /// antwoord kosten op twee gelimiteerde banen.
  static const verversNa = Duration(days: 7);

  Directory get _dir => Directory('$appDir${Platform.pathSeparator}discography');

  File _bestand(String naam) {
    // artistKey en niet kaal kleine letters: die laat een leidend "the" vallen, zodat "The Doors" en
    // "Doors" — voor de bibliotheek één act — geen twee bestanden krijgen die elkaar tegenspreken.
    final sleutel = '$schema|${artistKey(naam)}';
    return File('${_dir.path}${Platform.pathSeparator}${fnv1a(sleutel)}.json');
  }

  Future<DiscoCache?> lees(String naam) async {
    try {
      final f = _bestand(naam);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return null;
      // Een bestand dat niet te lezen is telt als AFWEZIG, niet als lege discografie. Een lege lijst
      // zonder melding is precies de faalvorm die deze pagina moet wegnemen.
      final rijen = j['releases'];
      if (rijen is! List) return null;
      return DiscoCache(
        [for (final r in rijen) if (r is Map<String, dynamic>) _uitJson(r)].whereType<DiscoRelease>().toList(),
        (j['fetchedMs'] as num?)?.toInt() ?? 0,
        zeefHoezen: j['zeefHoezen'] is bool ? j['zeefHoezen'] as bool : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// [zeefHoezen]: de hoesregel die bij deze lijst hoort. Het volgende bezoek zet de lijst daarmee
  /// meteen vast, zie [bevriesDiscografie].
  Future<void> schrijf(String naam, List<DiscoRelease> releases, {bool? zeefHoezen}) async {
    try {
      await _dir.create(recursive: true);
      await _bestand(naam).writeAsString(jsonEncode({
        'fetchedMs': DateTime.now().millisecondsSinceEpoch,
        if (zeefHoezen != null) 'zeefHoezen': zeefHoezen,
        'releases': [for (final r in releases) _naarJson(r)],
      }));
    } catch (_) {/* een cache die niet kan schrijven mag de pagina niet tegenhouden */}
  }

  // ── De drie bronnen ────────────────────────────────────────────────────────

  /// Is dit wel dezelfde artiest?
  ///
  /// Drie bronnen worden onafhankelijk op naam opgezocht, dus er zijn drie kansen op een naamgenoot.
  /// Een lijst met de platen van iemand anders erin is erger dan een korte lijst, dus een bron die een
  /// andere naam teruggeeft dan gevraagd valt af — en zegt dat ook.
  static bool _zelfdeArtiest(String gevraagd, String gevonden) =>
      artistKey(gevraagd) == artistKey(gevonden);

  Future<BronUitkomst> vanDeezer(String naam, {int? bekendId}) async {
    try {
      var id = bekendId;
      if (id == null) {
        final hits = await catalog.searchArtists(naam);
        final treffer = hits.where((a) => _zelfdeArtiest(naam, a.name)).firstOrNull;
        if (treffer == null) {
          return BronUitkomst(
              DiscoSource.deezer, hits.isEmpty ? BronStatus.klaar : BronStatus.andereArtiest, const []);
        }
        id = treffer.id;
      }
      final albums = await catalog.artistAlbums(id);
      return BronUitkomst(DiscoSource.deezer, BronStatus.klaar, [
        for (final a in albums)
          DiscoRelease(
            title: a.title,
            kind: kindFromDeezer(a.recordType),
            firstDate: a.releaseDate,
            cover: a.cover,
            trackCount: a.trackCount,
            sources: const {DiscoSource.deezer},
            refs: {DiscoSource.deezer: CatalogRef.deezer(a.id)},
          )
      ]);
    } catch (_) {
      return const BronUitkomst(DiscoSource.deezer, BronStatus.onbereikbaar, []);
    }
  }

  Future<BronUitkomst> vanMusicBrainz(String naam, {String? bekendeMbid}) async {
    // `MusicBrainzService` slikt elke fout en geeft dan "niets" terug — ook bij een 503. Of een lege
    // uitkomst "deze artiest heeft er geen" of "MusicBrainz antwoordde niet" betekent, staat alleen
    // in deze teller. Zonder dat onderscheid meldde de pagina van Serge Gainsbourg niets bijzonders
    // terwijl MusicBrainz ontbrak, en stond elke plaat op het jaar van zijn heruitgave.
    final foutenVoor = MusicBrainzService.transportErrors;
    BronUitkomst leeg() => BronUitkomst(
        DiscoSource.musicbrainz,
        MusicBrainzService.transportErrors > foutenVoor ? BronStatus.onbereikbaar : BronStatus.klaar,
        const []);
    try {
      var mbid = bekendeMbid;
      if (mbid == null) {
        final a = await mb.resolveArtist(naam);
        if (a == null) return leeg();
        if (!_zelfdeArtiest(naam, a.name)) {
          return const BronUitkomst(DiscoSource.musicbrainz, BronStatus.andereArtiest, []);
        }
        mbid = a.mbid;
      }
      final groepen = await mb.discographyOf(mbid);
      if (groepen.isEmpty) return leeg();
      return BronUitkomst(DiscoSource.musicbrainz, BronStatus.klaar, [
        for (final g in groepen)
          DiscoRelease(
            title: g.title,
            kind: kindFromMb(g.primaryType, g.secondaryTypes),
            firstDate: g.firstDate,
            sources: const {DiscoSource.musicbrainz},
            refs: {DiscoSource.musicbrainz: CatalogRef.musicbrainzGroup(g.mbid)},
          )
      ]);
    } catch (_) {
      return const BronUitkomst(DiscoSource.musicbrainz, BronStatus.onbereikbaar, []);
    }
  }

  /// Hoogstens zoveel albums per bezoek bij [mbGroepenVoor]: één zoekvraag per stuk op de baan van 1,1 s.
  /// Wat gevraagd is, ligt daarna in de cache van [MusicBrainzService]; de rest komt bij een volgend bezoek.
  static const kUitgaveVragen = 12;

  /// Voor elk album in [albums] (uit [wegGevallenAlbums]): onder welke MusicBrainz-groep staat die uitgave
  /// daar? Deezer-nummer → groep, alleen waar MusicBrainz een uitgave met precies die titel van deze artiest
  /// kent ([groepUitZoekuitslag]). Een fout of geen antwoord laat het album weg, zoals voorheen.
  Future<Map<String, String>> mbGroepenVoor(String naam, List<DiscoRelease> albums) async {
    final uit = <String, String>{};
    for (final r in albums.take(kUitgaveVragen)) {
      final dz = r.refs[DiscoSource.deezer]?.id;
      if (dz == null) continue;
      try {
        final g = groepUitZoekuitslag(naam, r.title, await mb.searchReleases(naam, r.title, max: 10));
        if (g != null) uit[dz] = g;
      } catch (_) {/* dan blijft hij weg, zoals vóór 28-10-2026 */}
    }
    return uit;
  }

  /// Welke Discogs-artiest deze naam is: eerst via de verwijzing van MusicBrainz, dan pas op naam.
  ///
  /// **Op naam kiest bij naamgenoten de verkeerde.** Discogs nummert ze — "Oasis" is daar een
  /// Belgisch tranceproject, de band heet "Oasis (2)" — en de zoektocht nam de eerste die exact zo
  /// heette. MusicBrainz verwijst rechtstreeks naar het juiste nummer, en die opvraag ligt na het
  /// eerste bezoek in de cache. Dezelfde naamtucht als [vanMusicBrainz]: een MusicBrainz-artiest met
  /// een andere naam telt niet.
  Future<int?> discogsIdVoor(String naam, {String? bekendeMbid}) async {
    var mbid = bekendeMbid;
    if (mbid == null) {
      try {
        final a = await mb.resolveArtist(naam);
        if (a != null && _zelfdeArtiest(naam, a.name)) mbid = a.mbid;
      } catch (_) {/* dan maar op naam */}
    }
    if (mbid != null) {
      try {
        final id = await mb.discogsArtistId(mbid);
        if (id != null) return id;
      } catch (_) {/* dan maar op naam */}
    }
    return discogs.artistId(naam);
  }

  Future<BronUitkomst> vanDiscogs(String naam, {String? bekendeMbid}) async {
    // De aanroeper MOET dit zelf lezen: zonder token faalt elke aanroep in DiscogsService stil, en dan
    // is "geen token" niet te onderscheiden van "niets gevonden".
    if (!discogs.available) {
      return const BronUitkomst(DiscoSource.discogs, BronStatus.geenToken, []);
    }
    try {
      final id = await discogsIdVoor(naam, bekendeMbid: bekendeMbid);
      if (id == null) return const BronUitkomst(DiscoSource.discogs, BronStatus.klaar, []);
      // Eén sweep, twee doelen: het formaat van elke master (anders valt die in "Overig") en een
      // miniatuurhoes voor regels die er geen hebben. Hier opgehaald en doorgegeven, zodat hij
      // gegarandeerd één keer gebeurt in plaats van te leunen op de schijfcache.
      final sweep = await discogs.artistSweep(id);
      final rijen = await discogs.artistReleases(id, sweep_: sweep, naam: naam);
      return BronUitkomst(DiscoSource.discogs, BronStatus.klaar, rijen,
          hoezen: sweep.hoesPerSleutel);
    } catch (_) {
      return const BronUitkomst(DiscoSource.discogs, BronStatus.onbereikbaar, []);
    }
  }

  /// Welke van deze regels in werkelijkheid andermans plaat zijn.
  ///
  /// Levert de [discoKey]s die van de discografie af moeten. Alleen Deezer heeft dit nodig: Discogs
  /// filtert al op `role == 'Main'` en MusicBrainz browst de releasegroepen van de artiest zelf, dus
  /// die twee laten een gastoptreden al vallen. Deezers `/artist/{id}/albums` doet dat niet en noemt
  /// de hoofdartiest ook niet — zie [CatalogService.albumArtists].
  ///
  /// GEMETEN op Enrique Iglesias: 15 van zijn 86 Deezer-regels zijn van iemand anders, van "Pavarotti
  /// & Friends" tot vier taalversies van een single van Descemer Bueno. Wat één van de andere twee
  /// bronnen óók kent gaat er niet langs, want dat is al gedekt; voor Enrique scheelt dat 39 verzoeken.
  ///
  /// Bij twijfel blijft een regel staan. Een plaat die ten onrechte verdwijnt merk je niet.
  Future<Set<String>> gastoptredens(String naam, List<DiscoRelease> rijen) async =>
      (await nakijken(naam, rijen)).gasten;

  /// De regels die alleen Deezer kent, één voor één nagekeken: welke andermans plaat zijn ([gastoptredens],
  /// hun [discoKey]s) en welke "albums" in werkelijkheid maxisingles zijn ([isMaxisingle], hun
  /// Deezer-nummers). Hetzelfde verzoek per regel voor allebei, dus de tweede vraag kost niets extra.
  ///
  /// Maxisingles (Saber, 20-10-2026: remixen "tussen albums"): Madonna's "Deeper and Deeper" en "Rain"
  /// van 2022 noemt Deezer album, en alleen Deezer kent ze onder die naam. Remixalbums ([isRemixAlbum]):
  /// "Finally Enough Love: 50 Number Ones", vijftig remixen.
  Future<({Set<String> gasten, Set<int> maxisingles, Set<int> remixAlbums})> nakijken(
      String naam, List<DiscoRelease> rijen) async {
    final teVragen = <int, DiscoRelease>{};
    for (final r in rijen) {
      if (r.sources.length != 1 || !r.sources.contains(DiscoSource.deezer)) continue;
      final ref = r.refs[DiscoSource.deezer];
      if (ref == null || ref.intId <= 0) continue;
      teVragen[ref.intId] = r;
    }
    if (teVragen.isEmpty) return (gasten: const <String>{}, maxisingles: const <int>{}, remixAlbums: const <int>{});
    final kenmerken = await catalog.albumKenmerken(teVragen.keys);
    return (
      gasten: {
        for (final e in kenmerken.entries)
          if (e.value.artiest.isNotEmpty && !_zelfdeArtiest(naam, e.value.artiest)) teVragen[e.key]!.key,
      },
      maxisingles: {
        for (final e in kenmerken.entries)
          if (teVragen[e.key]!.blok == RecordKind.album && isMaxisingle(teVragen[e.key]!.title, e.value.titels)) e.key,
      },
      remixAlbums: {
        for (final e in kenmerken.entries)
          if (teVragen[e.key]!.blok == RecordKind.album &&
              !isMaxisingle(teVragen[e.key]!.title, e.value.titels) &&
              isRemixAlbum(e.value.titels))
            e.key,
      },
    );
  }

  // ── Opslagvorm ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> _naarJson(DiscoRelease r) => {
        't': r.title,
        'd': r.firstDate,
        'k': r.kind.name,
        'c': r.cover,
        'n': r.trackCount,
        's': [for (final s in r.sources) s.name],
        'r': {for (final e in r.refs.entries) e.key.name: '${e.value.source.name}|${e.value.id}'},
      };

  static DiscoRelease? _uitJson(Map<String, dynamic> j) {
    final titel = j['t'] as String?;
    if (titel == null || titel.isEmpty) return null;
    CatalogRef? ref(String s) {
      final i = s.indexOf('|');
      if (i <= 0) return null;
      final bron = CatalogSource.values.where((v) => v.name == s.substring(0, i)).firstOrNull;
      return bron == null ? null : CatalogRef(bron, s.substring(i + 1));
    }

    return DiscoRelease(
      title: titel,
      firstDate: j['d'] as String?,
      kind: RecordKind.values.where((v) => v.name == j['k']).firstOrNull ?? RecordKind.other,
      cover: j['c'] as String?,
      trackCount: (j['n'] as num?)?.toInt() ?? 0,
      sources: {
        for (final s in (j['s'] as List? ?? const []))
          ...DiscoSource.values.where((v) => v.name == s),
      },
      refs: {
        for (final e in (j['r'] as Map? ?? const {}).entries)
          if (DiscoSource.values.where((v) => v.name == e.key).firstOrNull case final b?)
            if (ref('${e.value}') case final r?) b: r,
      },
    );
  }
}
