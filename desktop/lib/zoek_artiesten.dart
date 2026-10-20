/// De rij "Artiesten" in Online zoeken: wie hoort er bij een zoekzin, en met welke foto.
///
/// Saber, 20-10-2026, bij "Chappell Roan Good Luck Babe": *"waarom zijn er geen afbeeldingen bij
/// artist?"*. Deezer zoekt artiesten alleen op naam, en de hele zin is geen naam: nul artiesten. Wat er
/// stond kwam van MusicBrainz, dat geen foto's heeft en op losse woorden zoekt — "Good Luck", "BaBe",
/// "Roan", en de echte Chappell Roan zonder foto. Maar elk nummer dat Deezer vond, draagt zijn artiest
/// mét id en foto: die zijn het die je zocht.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog.dart';
import 'discogs.dart';
import 'enrichment.dart' show CoverEnricher, kAudioDbBasis;
import 'musicbrainz.dart';
import 'organize.dart' show artistKey;
import 'wikifotos.dart';

/// Hoeveel artiesten uit de gevonden nummers vooraan mogen.
const kArtiestenUitNummers = 3;

/// De artiestenrij: eerst wie precies zo heet als de zoekzin, dan de artiesten van de bovenste
/// [nummers] (Deezer, met foto — hoogstens [uitNummers]), dan de rest van wat de artiestenzoektocht
/// [gevonden] gaf. Elke artiest één keer, op [artistKey].
List<CatalogArtist> artiestenVoorZoekrij(List<CatalogArtist> gevonden, List<CatalogTrackHit> nummers, String q,
    {int uitNummers = kArtiestenUitNummers}) {
  final gezocht = artistKey(q);
  final uit = <CatalogArtist>[];
  final al = <String>{};
  bool voeg(CatalogArtist a) => al.add(artistKey(a.name)) ? (uit..add(a)).isNotEmpty : false;
  for (final a in gevonden) {
    if (artistKey(a.name) == gezocht) voeg(a);
  }
  var n = 0;
  for (final t in nummers) {
    if (n >= uitNummers) break;
    final id = t.artistId;
    if (id == null || id <= 0 || t.artist.trim().isEmpty) continue;
    if (voeg(CatalogArtist(id, t.artist, t.artistPicture, 0))) n++;
  }
  for (final a in gevonden) {
    voeg(a);
  }
  return uit;
}

/// Mag een artiest van MusicBrainz bij deze zoekzin in de rij? Alleen als de zin met zijn naam begint
/// (op een woordgrens), of zijn naam is.
///
/// MusicBrainz zoekt op tekst zonder enig gevoel voor wie bekend is, en op losse woorden: bij
/// "Chappell Roan Good Luck Babe" gaf het "Good Luck", "BaBe" en "Roan". Wie een artiest zoekt die
/// Deezer niet kent, typt diens naam — en die begint dan de zin.
bool mbArtiestPastBijZoekzin(String q, String naam) {
  final zin = artistKey(q), n = artistKey(naam);
  if (n.isEmpty) return false;
  return zin == n || zin.startsWith('$n ');
}

/// Een foto voor een artiest die alleen van MusicBrainz komt (Saber: "kan je wiki of discogs niet
/// gebruiken als vangnet, of TheAudioDB?").
///
/// **Altijd op zijn MusicBrainz-nummer, nooit op naam.** Op naam zitten er naamgenoten in — zie het
/// commentaar bij de artiestenrij in main.dart, en Oasis bij Discogs ([MusicBrainzService.discogsArtistId]).
/// Eerst TheAudioDB (`artist-mb.php`, gemeten op 20-10-2026: Oasis en Chappell Roan exact), dan Discogs
/// via het Discogs-nummer dat MusicBrainz kent (alleen met een Discogs-sleutel: zonder geeft Discogs geen
/// foto's, en het plaatje zelf vraagt de sleutel ook — zie [DiscogsService.beeldKoppen]), dan het
/// Wikipedia-portret via het Wikidata-nummer. Eén zoektocht per artiest per sessie.
class MbArtiestFoto {
  static final _bezig = <String, Future<String?>>{};

  static Future<String?> voor(String mbid, MusicBrainzService mb, {DiscogsService? discogs}) =>
      _bezig[mbid] ??= _zoek(mbid.trim(), mb, discogs).catchError((Object _) => null);

  static Future<String?> _zoek(String mbid, MusicBrainzService mb, DiscogsService? discogs) async {
    if (mbid.isEmpty) return null;
    final uitAudioDb = await _audioDb(mbid);
    if (uitAudioDb != null) return uitAudioDb;
    if (discogs != null && discogs.available) {
      final id = await mb.discogsArtistId(mbid);
      final beelden = id == null ? const <DiscogsImage>[] : (await discogs.artist('', id: id))?.images ?? const [];
      final foto = discogsFotoUit(beelden);
      if (foto != null) return foto;
    }
    final q = await mb.wikidataId(mbid);
    if (q == null) return null;
    final portretten = await WikiFotoService().portrettenVoor(q);
    return portretten.isEmpty ? null : portretten.first.voorbeeld;
  }

  static Future<String?> _audioDb(String mbid) async {
    try {
      CoverEnricher.meldAudioDbVraag(); // de achtergrond houdt daarna weer afstand
      final r = await http
          .get(Uri.parse('$kAudioDbBasis/artist-mb.php?i=${Uri.encodeQueryComponent(mbid)}'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      return audioDbFotoUit(jsonDecode(utf8.decode(r.bodyBytes)));
    } catch (_) {
      return null;
    }
  }
}

/// De foto uit de Discogs-beelden van een artiest: de hoofdfoto als Discogs er een aanwijst, anders de
/// eerste. Null als er geen is.
String? discogsFotoUit(List<DiscogsImage> beelden) {
  if (beelden.isEmpty) return null;
  final hoofd = beelden.where((b) => b.primary).firstOrNull ?? beelden.first;
  return hoofd.uri.isEmpty ? null : hoofd.uri;
}

/// De foto uit een antwoord van TheAudioDB (`{"artists":[{"strArtistThumb": …}]}`), of null.
String? audioDbFotoUit(Object? j) {
  final lijst = j is Map ? j['artists'] : null;
  if (lijst is! List || lijst.isEmpty || lijst.first is! Map) return null;
  final a = lijst.first as Map;
  for (final veld in const ['strArtistThumb', 'strArtistWideThumb', 'strArtistFanart']) {
    final v = a[veld];
    if (v is String && v.startsWith('http')) return v;
  }
  return null;
}
