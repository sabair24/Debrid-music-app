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
  const DiscoCache(this.releases, this.fetchedMs);

  bool ouderDan(Duration d) =>
      DateTime.now().millisecondsSinceEpoch - fetchedMs > d.inMilliseconds;
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
  static const schema = 'disco|v2';

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
    var h = 0x811c9dc5;
    for (final c in sleutel.codeUnits) {
      h = (h ^ c) * 0x01000193;
      h &= 0xFFFFFFFF;
    }
    return File('${_dir.path}${Platform.pathSeparator}${h.toRadixString(16)}.json');
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
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> schrijf(String naam, List<DiscoRelease> releases) async {
    try {
      await _dir.create(recursive: true);
      await _bestand(naam).writeAsString(jsonEncode({
        'fetchedMs': DateTime.now().millisecondsSinceEpoch,
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
    try {
      var mbid = bekendeMbid;
      if (mbid == null) {
        final a = await mb.resolveArtist(naam);
        if (a == null) return const BronUitkomst(DiscoSource.musicbrainz, BronStatus.klaar, []);
        if (!_zelfdeArtiest(naam, a.name)) {
          return const BronUitkomst(DiscoSource.musicbrainz, BronStatus.andereArtiest, []);
        }
        mbid = a.mbid;
      }
      final groepen = await mb.discographyOf(mbid);
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

  Future<BronUitkomst> vanDiscogs(String naam) async {
    // De aanroeper MOET dit zelf lezen: zonder token faalt elke aanroep in DiscogsService stil, en dan
    // is "geen token" niet te onderscheiden van "niets gevonden".
    if (!discogs.available) {
      return const BronUitkomst(DiscoSource.discogs, BronStatus.geenToken, []);
    }
    try {
      final id = await discogs.artistId(naam);
      if (id == null) return const BronUitkomst(DiscoSource.discogs, BronStatus.klaar, []);
      // Eén sweep, twee doelen: het formaat van elke master (anders valt die in "Overig") en een
      // miniatuurhoes voor regels die er geen hebben. Hier opgehaald en doorgegeven, zodat hij
      // gegarandeerd één keer gebeurt in plaats van te leunen op de schijfcache.
      final sweep = await discogs.artistSweep(id);
      final rijen = await discogs.artistReleases(id, sweep_: sweep);
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
  Future<Set<String>> gastoptredens(String naam, List<DiscoRelease> rijen) async {
    final teVragen = <int, String>{}; // deezer album-id -> discoKey
    for (final r in rijen) {
      if (r.sources.length != 1 || !r.sources.contains(DiscoSource.deezer)) continue;
      final ref = r.refs[DiscoSource.deezer];
      if (ref == null || ref.intId <= 0) continue;
      teVragen[ref.intId] = r.key;
    }
    if (teVragen.isEmpty) return const {};
    final vanWie = await catalog.albumArtists(teVragen.keys);
    return {
      for (final e in teVragen.entries)
        if (vanWie[e.key] case final wie?)
          if (!_zelfdeArtiest(naam, wie)) e.value,
    };
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
