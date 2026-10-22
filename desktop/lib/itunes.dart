/// Een tweede catalogus naast Deezer: de zoek-API van Apple (iTunes), zonder sleutel en op elk toestel.
///
/// Saber, 22-10-2026: *"alles wordt zo gebaseerd op deezer ma baseer ook op andere dingen e"*. Gemeten die dag op
/// de acht nummers die de Petra-radio "niet gevonden" noemde: iTunes en TIDAL kenden Plaza — Yo-Yo, Deezer en
/// MusicBrainz niet. De andere zeven kende geen enkele bron onder die artiest (Viva Hollandia is van Wolter Kroes,
/// Dag Vreemde Man van Ann Christy): die bleven terecht weg. iTunes komt dus pas na Deezer en je eigen bibliotheek,
/// en beslist met dezelfde keuze als Deezer ([besteTreffer]).
///
/// Apple vraagt hoogstens ongeveer twintig vragen per minuut. [ItunesZoeker] houdt zich daaraan over alle radio's
/// heen ([wachtVoorVenster]).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'radiolijst.dart' show besteTreffer;
import 'recommend.dart' show RecTrack;

/// De nummers uit een antwoord van `itunes.apple.com/search?entity=song`. Alleen liedjes met een titel en artiest.
List<RecTrack> itunesNummers(Map<String, dynamic>? j) {
  final rs = j?['results'];
  if (rs is! List) return const [];
  return [
    for (final r in rs)
      if (r is Map &&
          r['kind'] == 'song' &&
          '${r['trackName'] ?? ''}'.isNotEmpty &&
          '${r['artistName'] ?? ''}'.isNotEmpty)
        RecTrack(
          '${r['artistName']}',
          '${r['trackName']}',
          r['artworkUrl100'] is String ? r['artworkUrl100'] as String : null,
          album: '${r['collectionName'] ?? ''}',
          seconds: ((r['trackTimeMillis'] is num ? r['trackTimeMillis'] as num : 0) / 1000).round(),
        ),
  ];
}

/// Hoe lang er gewacht moet worden voor de volgende vraag, als er in het laatste [venster] al [max] gesteld zijn.
Duration wachtVoorVenster(
  List<DateTime> vorige,
  DateTime nu, {
  int max = 20,
  Duration venster = const Duration(minutes: 1),
}) {
  final binnen = [
    for (final t in vorige)
      if (nu.difference(t) < venster) t,
  ]..sort();
  if (binnen.length < max) return Duration.zero;
  return binnen[binnen.length - max].add(venster).difference(nu);
}

class ItunesZoeker {
  ItunesZoeker({http.Client? client, this.land = 'BE', DateTime Function()? klok})
    : _client = client,
      _klok = klok ?? DateTime.now;

  final http.Client? _client;
  final DateTime Function() _klok;

  /// De winkel waarin gezocht wordt. België: daar staat de Vlaamse muziek die Deezer mist.
  final String land;

  static final List<DateTime> _gesteld = [];
  static Future<void> _beurt = Future.value();

  /// Dit nummer van deze artiest, of null als iTunes het niet zo kent. Ook null bij geen antwoord: dit is een
  /// tweede kans, geen oordeel.
  Future<RecTrack?> vind(String artiest, String titel) async {
    final treffers = await zoek('$artiest $titel');
    if (treffers == null || treffers.isEmpty) return null;
    final i = besteTreffer(
      [for (final t in treffers) (artiest: t.artist, titel: t.title, rang: 0, seconden: t.seconds)],
      artiest,
      titel,
    );
    return i == null ? null : treffers[i];
  }

  /// De liedjes voor [vraag], of null als Apple niet (bruikbaar) antwoordde.
  Future<List<RecTrack>?> zoek(String vraag) async {
    final klaar = Completer<void>();
    final vorige = _beurt;
    _beurt = klaar.future;
    try {
      await vorige;
      final wacht = wachtVoorVenster(_gesteld, _klok());
      if (wacht > Duration.zero) await Future<void>.delayed(wacht);
      _gesteld
        ..add(_klok())
        ..removeWhere((t) => _klok().difference(t) > const Duration(minutes: 2));
    } finally {
      klaar.complete();
    }
    try {
      final u = Uri.https('itunes.apple.com', '/search', {
        'term': vraag,
        'entity': 'song',
        'limit': '15',
        'country': land,
      });
      final r = await (_client ?? http.Client()).get(u).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? itunesNummers(j) : null;
    } catch (_) {
      return null;
    }
  }
}
