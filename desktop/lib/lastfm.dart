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

import 'package:http/http.dart' as http;

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

class LastfmZoeker {
  LastfmZoeker({http.Client? client}) : _client = client;
  final http.Client? _client;

  /// Wat Last.fm vergelijkbaar vindt met [titel] van [artiest], of null als het niet antwoordde (of de sleutel
  /// weigerde). De sleutel gaat alleen in de vraag zelf mee — nooit in een logboek.
  Future<({List<LastfmNummer> nummers, int vanZelf, int totaal})?> vergelijkbaar(
    String artiest,
    String titel, {
    required String sleutel,
    int limit = 50,
  }) async {
    if (sleutel.trim().isEmpty || artiest.trim().isEmpty || titel.trim().isEmpty) return null;
    try {
      final u = Uri.https('ws.audioscrobbler.com', '/2.0/', {
        'method': 'track.getsimilar',
        'artist': artiest.trim(),
        'track': titel.trim(),
        'autocorrect': '1',
        'limit': '$limit',
        'api_key': sleutel.trim(),
        'format': 'json',
      });
      final r = await (_client ?? http.Client()).get(u).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map<String, dynamic> || j.containsKey('error')) return null;
      return lastfmVergelijkbaar(j, zaadArtiest: artiest);
    } catch (_) {
      return null;
    }
  }
}
