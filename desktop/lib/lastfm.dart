/// Vergelijkbare nummers van Last.fm, als extra bron voor de radio naast Deezer en het taalmodel.
///
/// Saber, 22-10-2026: *"alles wordt zo gebaseerd op deezer ma baseer ook op andere dingen e"* — en daarna zijn eigen
/// API-sleutel (die staat in Instellingen, veld "Last.fm API-sleutel"). Gemeten die dag met `track.getSimilar`:
///
/// * 2 Fabiola — Freak Out: 40 nummers, diepere 90s-eurodance (X-Session, Da Boy Tommy, 2 Brothers on the 4th Floor,
///   T-Spoon, Ann Lee): ontdekken, waar Deezer vooral de bekende hits geeft;
/// * Clouseau — Daar Gaat Ze: 38, Nederlandstalige pop (Frank Boeijen, Abel, Stef Bos, De Dijk, Rob de Nijs);
/// * Bruce Springsteen — Born in the U.S.A.: 40, klassieke rock;
/// * Petra — Ik Leef Voor Jou: 22, allemaal van "Petra" — Last.fm gooit naamgenoten op één hoop (christelijke rock,
///   Oostenrijkse schlager). Onbruikbaar, en daarom [kLastfmMinimum];
/// * Niels Destadsbader — Vuur en vlam: niets (te nieuw).
///
/// Wat hier terugkomt is een lijst namen; de radio zoekt ze op zoals de lijst van het model (Deezer, je eigen
/// bibliotheek, iTunes) en keurt ze streng op sfeer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cachesleutel.dart' show fnv1a;
import 'radiokeuze.dart' show zelfdeArtiest;

/// Een vergelijkbaar nummer: artiest en titel, zoals Last.fm ze schrijft.
typedef LastfmNummer = ({String artiest, String titel});

/// Minder nummers van ANDERE artiesten dan dit, en de lijst zegt niets — meestal naamgenoten van de zaadartiest.
const int kLastfmMinimum = 8;

/// Is meer dan dit deel van de lijst van de zaadartiest zelf, dan zijn het naamgenoten op één hoop. Gemeten op
/// 22-10-2026 met 50 gevraagd: Petra 22 van 31 (de andere 9: christelijke rock — Thieves & Liars, White Heart),
/// tegen 2 Fabiola 1 van 50, Clouseau 2 van 48, Bruce Springsteen 2 van 40.
const double kLastfmZelfHoogstens = 0.4;

/// De nummers uit een antwoord van `track.getSimilar`, zonder die van de zaadartiest zelf (die haalt de radio al op
/// een andere weg, en het plafond per artiest geldt). Leeg als er minder dan [kLastfmMinimum] overblijven, of als
/// meer dan [kLastfmZelfHoogstens] van de lijst van de zaadartiest zelf is.
({List<LastfmNummer> nummers, int vanZelf, int totaal}) lastfmVergelijkbaar(
  Map<String, dynamic>? j, {
  required String zaadArtiest,
}) {
  final rauw = (j?['similartracks'] is Map) ? (j!['similartracks'] as Map)['track'] : null;
  final alle = <LastfmNummer>[
    if (rauw is List)
      for (final t in rauw)
        if (t is Map && t['artist'] is Map)
          if (('${t['name'] ?? ''}').trim() case final titel when titel.isNotEmpty)
            if (('${(t['artist'] as Map)['name'] ?? ''}').trim() case final artiest when artiest.isNotEmpty)
              (artiest: artiest, titel: titel),
  ];
  final anderen = [
    for (final n in alle)
      if (!zelfdeArtiest(n.artiest, zaadArtiest)) n,
  ];
  final naamgenoten = alle.isNotEmpty && (alle.length - anderen.length) / alle.length > kLastfmZelfHoogstens;
  return (
    nummers: anderen.length < kLastfmMinimum || naamgenoten ? const <LastfmNummer>[] : anderen,
    vanZelf: alle.length - anderen.length,
    totaal: alle.length,
  );
}

/// Een nummer met het aantal luisteraars bij Last.fm (artist.getTopTracks, tag.getTopTracks).
typedef LastfmTopper = ({String artiest, String titel, int luisteraars});

/// Een nummer uit iemands geschiedenis (user.getTopTracks) met hoe vaak hij het speelde.
typedef LastfmGespeeld = ({String artiest, String titel, int keer});

/// De bekendste nummers van een artiest (artist.getTopTracks), in de volgorde van Last.fm: meeste luisteraars eerst.
List<LastfmTopper> lastfmTopNummers(Map<String, dynamic>? j) =>
    _nummersMetLuisteraars(j?['toptracks'] is Map ? (j!['toptracks'] as Map)['track'] : null);

/// De nummers onder een tag (tag.getTopTracks).
List<LastfmTopper> lastfmTagNummers(Map<String, dynamic>? j) =>
    _nummersMetLuisteraars(j?['tracks'] is Map ? (j!['tracks'] as Map)['track'] : null);

List<LastfmTopper> _nummersMetLuisteraars(Object? rauw) => [
  if (rauw is List)
    for (final t in rauw)
      if (t is Map && t['artist'] is Map)
        if (('${t['name'] ?? ''}').trim() case final titel when titel.isNotEmpty)
          if (('${(t['artist'] as Map)['name'] ?? ''}').trim() case final artiest when artiest.isNotEmpty)
            (artiest: artiest, titel: titel, luisteraars: int.tryParse('${t['listeners'] ?? ''}') ?? 0),
];

/// De tags van een artiest (artist.getTopTags), klein geschreven, alleen die met minstens [minstens] stemmen van
/// de 100. Gemeten op 22-10-2026 in Sabers bibliotheek: 46 van 50 artiesten hebben er, 16 een taal of streek
/// ("nederlandstalig", "belgian", "french"). Ook hier naamgenoten: K3 draagt "progressive metal".
List<String> lastfmTags(Map<String, dynamic>? j, {int minstens = 10}) {
  final rauw = j?['toptags'] is Map ? (j!['toptags'] as Map)['tag'] : null;
  return [
    if (rauw is List)
      for (final t in rauw)
        if (t is Map && (int.tryParse('${t['count'] ?? ''}') ?? 0) >= minstens)
          if (('${t['name'] ?? ''}').trim().toLowerCase() case final naam when naam.isNotEmpty) naam,
  ];
}

/// Verwante artiesten met hun maat (artist.getSimilar), 0..1.
List<({String naam, double maat})> lastfmVerwanteArtiesten(Map<String, dynamic>? j) {
  final rauw = j?['similarartists'] is Map ? (j!['similarartists'] as Map)['artist'] : null;
  return [
    if (rauw is List)
      for (final a in rauw)
        if (a is Map)
          if (('${a['name'] ?? ''}').trim() case final naam when naam.isNotEmpty)
            (naam: naam, maat: double.tryParse('${a['match'] ?? ''}') ?? 0),
  ];
}

/// Hoeveel luisteraars een nummer heeft (track.getInfo), of null als Last.fm het niet kent.
int? lastfmLuisteraars(Map<String, dynamic>? j) {
  final t = j?['track'];
  return t is Map ? int.tryParse('${t['listeners'] ?? ''}') : null;
}

/// Iemands meest gespeelde nummers (user.getTopTracks).
List<LastfmGespeeld> lastfmGebruikerTop(Map<String, dynamic>? j) {
  final rauw = j?['toptracks'] is Map ? (j!['toptracks'] as Map)['track'] : null;
  return [
    if (rauw is List)
      for (final t in rauw)
        if (t is Map && t['artist'] is Map)
          if (('${t['name'] ?? ''}').trim() case final titel when titel.isNotEmpty)
            if (('${(t['artist'] as Map)['name'] ?? ''}').trim() case final artiest when artiest.isNotEmpty)
              (artiest: artiest, titel: titel, keer: int.tryParse('${t['playcount'] ?? ''}') ?? 0),
  ];
}

/// Iemands meest gespeelde artiesten (user.getTopArtists).
List<({String naam, int keer})> lastfmGebruikerArtiesten(Map<String, dynamic>? j) {
  final rauw = j?['topartists'] is Map ? (j!['topartists'] as Map)['artist'] : null;
  return [
    if (rauw is List)
      for (final a in rauw)
        if (a is Map)
          if (('${a['name'] ?? ''}').trim() case final naam when naam.isNotEmpty)
            (naam: naam, keer: int.tryParse('${a['playcount'] ?? ''}') ?? 0),
  ];
}

/// Hoe lang een antwoord van deze soort bewaard blijft. Wat over smaak en bekendheid gaat, verandert traag; iemands
/// eigen geschiedenis een dag.
Duration lastfmHoudbaar(String methode) => switch (methode) {
  'user.gettoptracks' || 'user.gettopartists' => const Duration(days: 1),
  'artist.gettoptags' || 'track.getinfo' => const Duration(days: 30),
  _ => const Duration(days: 14),
};

/// Hoeveel antwoorden de buffer hoogstens houdt (één bestand per antwoord, een paar tot enkele tientallen kilobyte).
/// Last.fm staat 100 MB toe (voorwaarden, art. 4.3.4); dit blijft daar ruim onder.
const int kLastfmBufferMax = 3000;

/// De vragen aan Last.fm. Eén tegelijk en hoogstens ongeveer vier per seconde ([tussenpoos]), met een buffer op schijf
/// ([buffer]) zodat dezelfde vraag niet elke radio opnieuw gaat. De sleutel gaat alleen in de vraag zelf mee — nooit in
/// de buffer of in een logboek.
///
/// De buffer is een map met één bestand per antwoord (`<fnv1a>.json`), zoals die van MusicBrainz, Discogs en Wikipedia:
/// een nieuw antwoord schrijft één klein bestand in plaats van één grote lijst opnieuw.
class LastfmZoeker {
  LastfmZoeker({
    http.Client? client,
    this.buffer,
    DateTime Function()? klok,
    this.tussenpoos = const Duration(milliseconds: 250),
  }) : _client = client,
       _klok = klok ?? DateTime.now;

  final http.Client? _client;
  final DateTime Function() _klok;

  /// De map waarin de antwoorden bewaard worden, of null voor geen buffer (toetsen).
  final String? buffer;
  final Duration tussenpoos;

  Future<void> _beurt = Future.value();
  DateTime? _vorige;
  bool _gesnoeid = false;

  File? _bestand(String sleutel) {
    final m = buffer;
    return m == null ? null : File('$m${Platform.pathSeparator}${fnv1a('lf1|$sleutel')}.json');
  }

  Map<String, dynamic>? _uitBuffer(String sleutel, String methode) {
    final f = _bestand(sleutel);
    if (f == null) return null;
    try {
      if (!f.existsSync()) return null;
      final j = jsonDecode(f.readAsStringSync());
      if (j is! Map || j['j'] is! Map<String, dynamic>) return null;
      final t = DateTime.fromMillisecondsSinceEpoch(((j['haald'] as num?) ?? 0).toInt());
      return _klok().difference(t) < lastfmHoudbaar(methode) ? j['j'] as Map<String, dynamic> : null;
    } catch (_) {
      return null; // kapot of half geschreven: opnieuw vragen
    }
  }

  void _bewaar(String sleutel, Map<String, dynamic> j) {
    final f = _bestand(sleutel);
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      final tijdelijk = File('${f.path}.nieuw');
      tijdelijk.writeAsStringSync(jsonEncode({'haald': _klok().millisecondsSinceEpoch, 'j': j}), flush: true);
      tijdelijk.renameSync(f.path);
    } catch (_) {
      /* de volgende keer opnieuw */
    }
    if (!_gesnoeid) {
      _gesnoeid = true;
      _snoei();
    }
  }

  /// Eén keer per sessie: houd hoogstens [kLastfmBufferMax] antwoorden, de oudste gaan eerst.
  void _snoei() {
    final m = buffer;
    if (m == null) return;
    try {
      final alle = [
        for (final e in Directory(m).listSync())
          if (e is File && e.path.endsWith('.json')) e,
      ];
      if (alle.length <= kLastfmBufferMax) return;
      alle.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      for (final f in alle.take(alle.length - kLastfmBufferMax)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      /* snoeien is geen reden om iets te laten mislukken */
    }
  }

  /// Eén vraag, uit de buffer als hij vers genoeg is. Null bij geen antwoord, een fout of een geweigerde sleutel.
  Future<Map<String, dynamic>?> _vraag(Map<String, String> params, {required String sleutel}) async {
    if (sleutel.trim().isEmpty) return null;
    final methode = params['method'] ?? '';
    final bufferSleutel = (params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}=${e.value.toLowerCase()}')
        .join('&');
    final al = _uitBuffer(bufferSleutel, methode);
    if (al != null) return al;
    final klaar = Completer<void>();
    final vorige = _beurt;
    _beurt = klaar.future;
    try {
      await vorige;
      final v = _vorige;
      if (v != null) {
        final wacht = tussenpoos - _klok().difference(v);
        if (wacht > Duration.zero) await Future<void>.delayed(wacht);
      }
      _vorige = _klok();
    } finally {
      klaar.complete();
    }
    try {
      final u = Uri.https('ws.audioscrobbler.com', '/2.0/', {...params, 'api_key': sleutel.trim(), 'format': 'json'});
      final r = await (_client ?? http.Client()).get(u).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map<String, dynamic> || j.containsKey('error')) return null;
      _bewaar(bufferSleutel, j);
      return j;
    } catch (_) {
      return null;
    }
  }

  /// Voor een artiest: zijn MusicBrainz-id als die bekend is (geen naamgenoten), anders zijn naam met autocorrect.
  Map<String, String> _artiest(String artiest, String? mbid) =>
      (mbid != null && mbid.trim().isNotEmpty) ? {'mbid': mbid.trim()} : {'artist': artiest.trim(), 'autocorrect': '1'};

  /// Wat Last.fm vergelijkbaar vindt met [titel] van [artiest], of null als het niet antwoordde (of de sleutel
  /// weigerde).
  Future<({List<LastfmNummer> nummers, int vanZelf, int totaal})?> vergelijkbaar(
    String artiest,
    String titel, {
    required String sleutel,
    int limit = 50,
  }) async {
    if (artiest.trim().isEmpty || titel.trim().isEmpty) return null;
    final j = await _vraag({
      'method': 'track.getsimilar',
      'artist': artiest.trim(),
      'track': titel.trim(),
      'autocorrect': '1',
      'limit': '$limit',
    }, sleutel: sleutel);
    return j == null ? null : lastfmVergelijkbaar(j, zaadArtiest: artiest);
  }

  /// De bekendste nummers van [artiest], meeste luisteraars eerst.
  Future<List<LastfmTopper>?> topNummers(
    String artiest, {
    required String sleutel,
    String? mbid,
    int limit = 50,
  }) async {
    if (artiest.trim().isEmpty && (mbid ?? '').isEmpty) return null;
    final j = await _vraag({
      'method': 'artist.gettoptracks',
      ..._artiest(artiest, mbid),
      'limit': '$limit',
    }, sleutel: sleutel);
    return j == null ? null : lastfmTopNummers(j);
  }

  /// De tags van [artiest] (zie [lastfmTags]).
  Future<List<String>?> tags(String artiest, {required String sleutel, String? mbid}) async {
    if (artiest.trim().isEmpty && (mbid ?? '').isEmpty) return null;
    final j = await _vraag({'method': 'artist.gettoptags', ..._artiest(artiest, mbid)}, sleutel: sleutel);
    return j == null ? null : lastfmTags(j);
  }

  /// Verwante artiesten van [artiest], met hun maat.
  Future<List<({String naam, double maat})>?> verwanteArtiesten(
    String artiest, {
    required String sleutel,
    String? mbid,
    int limit = 30,
  }) async {
    if (artiest.trim().isEmpty && (mbid ?? '').isEmpty) return null;
    final j = await _vraag({
      'method': 'artist.getsimilar',
      ..._artiest(artiest, mbid),
      'limit': '$limit',
    }, sleutel: sleutel);
    return j == null ? null : lastfmVerwanteArtiesten(j);
  }

  /// Hoeveel luisteraars [titel] van [artiest] heeft, of null.
  Future<int?> luisteraars(String artiest, String titel, {required String sleutel}) async {
    if (artiest.trim().isEmpty || titel.trim().isEmpty) return null;
    final j = await _vraag({
      'method': 'track.getinfo',
      'artist': artiest.trim(),
      'track': titel.trim(),
      'autocorrect': '1',
    }, sleutel: sleutel);
    return j == null ? null : lastfmLuisteraars(j);
  }

  /// De nummers onder [tag], bekendste eerst.
  Future<List<LastfmTopper>?> tagNummers(String tag, {required String sleutel, int limit = 50}) async {
    if (tag.trim().isEmpty) return null;
    final j = await _vraag({'method': 'tag.gettoptracks', 'tag': tag.trim(), 'limit': '$limit'}, sleutel: sleutel);
    return j == null ? null : lastfmTagNummers(j);
  }

  /// De meest gespeelde nummers van [gebruiker] over [periode] (overall, 12month, …), bladzijde [blad].
  Future<List<LastfmGespeeld>?> gebruikerTop(
    String gebruiker, {
    required String sleutel,
    String periode = 'overall',
    int limit = 200,
    int blad = 1,
  }) async {
    if (gebruiker.trim().isEmpty) return null;
    final j = await _vraag({
      'method': 'user.gettoptracks',
      'user': gebruiker.trim(),
      'period': periode,
      'limit': '$limit',
      'page': '$blad',
    }, sleutel: sleutel);
    return j == null ? null : lastfmGebruikerTop(j);
  }

  /// De meest gespeelde artiesten van [gebruiker].
  Future<List<({String naam, int keer})>?> gebruikerArtiesten(
    String gebruiker, {
    required String sleutel,
    String periode = 'overall',
    int limit = 50,
  }) async {
    if (gebruiker.trim().isEmpty) return null;
    final j = await _vraag({
      'method': 'user.gettopartists',
      'user': gebruiker.trim(),
      'period': periode,
      'limit': '$limit',
    }, sleutel: sleutel);
    return j == null ? null : lastfmGebruikerArtiesten(j);
  }
}
