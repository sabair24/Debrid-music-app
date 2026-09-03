/// Eén rijbaan voor alle Deezer-verzoeken, en één plek die zijn weigeringen herkent.
///
/// **Waarom dit moest bestaan.** Deezer staat ongeveer vijftig verzoeken per vijf seconden toe. De
/// startpagina vuurt er bij een koude start eenenzestig af, en de eerste vijfentwintig komen
/// tegelijk aan: `latestFromArtists` doet 12 × 2 verzoeken in één `Future.wait`, `discover` doet er
/// 6 × 6, en `_loadSeeds` start die twee vóór de eerste `await`.
///
/// **En de weigering is onzichtbaar.** Gemeten met zestig gelijktijdige verzoeken: tien ervan kwamen
/// terug met status **200** en dit als lichaam:
///
///     {"error":{"type":"Exception","message":"Quota limit exceeded","code":4}}
///
/// `_get` keek alleen naar `statusCode != 200`, gaf die map netjes door, en de aanroeper zocht er
/// `data` in dat er niet was. "Deezer weigerde" werd zo "er is niets" — niet van elkaar te
/// onderscheiden, precies zoals `OntdekView` dat een laag hoger al eens had opgeschreven.
///
/// **Statisch, en dat is het hele punt.** `HomeStartView` en `OntdekView` maken elk hun eigen
/// `CatalogService` en `RecommendService`. Als veld op een object heeft elke aanroeper zijn eigen
/// idee van het budget, en dan houdt niemand zich aan iets. Dezelfde afweging staat bij de rijbaan
/// van Discogs opgeschreven, en om dezelfde reden.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'json_body.dart';

/// Deezer zei nee. Apart van "er is niets gevonden", want dat is een ander antwoord.
class DeezerFout implements Exception {
  final String uitleg;

  /// True als het om het aanvraagbudget ging — dan helpt wachten, en dat mag op het scherm staan.
  final bool quota;
  const DeezerFout(this.uitleg, {this.quota = false});

  @override
  String toString() => uitleg;
}

/// De gedeelde rijbaan.
class DeezerBaan {
  DeezerBaan._();

  /// 110 ms geeft ruim vijfenveertig verzoeken per vijf seconden — onder de gemeten grens van
  /// vijftig, met marge voor de andere schermen die dezelfde baan delen.
  static const Duration minimaleTussenpoos = Duration(milliseconds: 110);

  static DateTime _laatste = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _beurt = Future.value();

  /// Waar de baan zijn verhaal kwijt kan. Wordt één keer gezet, door wie een logboek heeft — zo
  /// blijft dit bestand vrij van `dart:io`.
  static void Function(String)? spoor;

  /// Hoeveel er nu op een plek staan te wachten, voor datzelfde spoor.
  static int _wachtend = 0;
  static int get wachtend => _wachtend;

  /// De artiest-id's die al eens opgezocht zijn, gedeeld door alle diensten.
  ///
  /// `latestFromArtists` zoekt de id van twaalf artiesten op en `discover` doet dat daarna nog eens
  /// voor dezelfde namen. Dat scheelt niet alleen verzoeken: het dwingt ook af dat beide rijen
  /// DEZELFDE "Adele" bedoelen. Nu beslissen `pickArtist` en `searchArtists` dat elk apart.
  static final Map<String, int?> _idPerNaam = {};

  static int? gekendId(String sleutel) => _idPerNaam[sleutel];
  static void onthoudId(String sleutel, int? id) => _idPerNaam[sleutel] = id;

  /// Alles vergeten. Voor tests, en voor de ververs-knop.
  static void vergeet() {
    _idPerNaam.clear();
    _laatste = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Eén verzoek, netjes in de rij.
  ///
  /// Werpt [DeezerFout] bij een weigering en geeft `null` alleen terug als het antwoord geen
  /// bruikbare JSON was. Dat onderscheid is de hele reden dat deze functie bestaat.
  static Future<Map<String, dynamic>?> haal(String url, {http.Client? client}) {
    final mijn = _beurt.then((_) async {
      final nu = DateTime.now();
      final sinds = nu.difference(_laatste);
      if (sinds < minimaleTussenpoos) {
        await Future<void>.delayed(minimaleTussenpoos - sinds);
      }
      _laatste = DateTime.now();
    });
    _beurt = mijn.catchError((_) {});
    _wachtend++;
    return mijn.then((_) async {
      try {
        final r = await (client ?? http.Client())
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (r.statusCode != 200) {
          throw DeezerFout('Deezer gaf ${r.statusCode}');
        }
        final j = jsonBody(r);
        if (j is! Map<String, dynamic>) return null;
        // De weigering die als 200 binnenkomt. Zonder deze regel wordt hij een lege lijst.
        final fout = j['error'];
        if (fout is Map) {
          final bericht = '${fout['message'] ?? 'geweigerd'}';
          final isQuota = '${fout['code']}' == '4' ||
              bericht.toLowerCase().contains('quota');
          spoor?.call('deezer weigerde: $bericht${isQuota ? ' (budget)' : ''}');
          throw DeezerFout(bericht, quota: isQuota);
        }
        return j;
      } on DeezerFout {
        rethrow;
      } catch (e) {
        throw DeezerFout('$e');
      } finally {
        _wachtend--;
      }
    });
  }
}
