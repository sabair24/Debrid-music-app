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

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// Hoe er gewacht wordt. Een toets zet hier een klok die te vroeg afgaat; zie [haal].
  @visibleForTesting
  static Future<void> Function(Duration) wacht = Future<void>.delayed;

  /// Waar de baan zijn verhaal kwijt kan. Wordt één keer gezet, door wie een logboek heeft — zo
  /// blijft dit bestand vrij van `dart:io`.
  static void Function(String)? spoor;

  /// Vanaf hier meldt [haal] een verzoek in het [spoor]: hoe lang het in de rij stond en hoe lang
  /// Deezer erover deed. Op de gsm duurde Online zoeken 3,2 s van tik tot uitslag (21-10-2026), terwijl
  /// Deezer zelf de drie zoekvragen vanaf de pc in 0,14–0,20 s beantwoordt — de rest is niet te zien
  /// zonder deze regel. Alleen het pad, nooit de zoektekst.
  static const Duration traagVanaf = Duration(milliseconds: 300);

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
    final gevraagd = DateTime.now();
    final mijn = _beurt.then((_) async {
      // **Opnieuw kijken na het wachten, tot de tijd echt om is.** Hier stond één `delayed` en dan
      // door. Op de bouwstraat (Linux) gemeten op 10-10-2026: drie verzoeken in minder dan 2 × 110
      // ms — een klok die een fractie vóór zijn tijd afgaat, gemeten tegen `DateTime.now()`. Een
      // klok die terugsprong (negatief) wacht niet; anders stond de baan een uur stil.
      var sinds = DateTime.now().difference(_laatste);
      while (!sinds.isNegative && sinds < minimaleTussenpoos) {
        await wacht(minimaleTussenpoos - sinds);
        sinds = DateTime.now().difference(_laatste);
      }
      _laatste = DateTime.now();
    });
    _beurt = mijn.catchError((_) {});
    final voorMij = _wachtend;
    _wachtend++;
    return mijn.then((_) async {
      final vertrek = DateTime.now();
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
        final s = spoor;
        if (s != null) {
          final rij = vertrek.difference(gevraagd);
          final vraag = DateTime.now().difference(vertrek);
          if (rij + vraag >= traagVanaf) {
            s('${Uri.tryParse(url)?.path ?? '?'}: ${rij.inMilliseconds} ms in de rij ($voorMij voor) + '
                '${vraag.inMilliseconds} ms bij Deezer');
          }
        }
      }
    });
  }
}

/// Deezer's digitale hoes op 1200×1200 in plaats van de 1000×1000 van `cover_xl`.
///
/// Gemeten op 20-10-2026 (Short n' Sweet, Unheard): de CDN levert 1200×1200 echt; vraag je 1800, dan komt
/// er 1200 terug — dat is de bron — en 1400 is opgerekt. Saber: "front is meestal de digitale versie het
/// beste 1200x1200". Een adres dat niet van Deezer is, blijft zoals het is.
String deezerHoes1200(String url) => url.contains('dzcdn.net/images/')
    ? url.replaceFirst(RegExp(r'/\d{2,4}x\d{2,4}-'), '/1200x1200-')
    : url;
