// iTunes als tweede catalogus naast Deezer. Saber, 22-10-2026: "alles wordt zo gebaseerd op deezer ma baseer ook op
// andere dingen e". Gemeten die dag: van de acht nummers die de Petra-radio "niet gevonden" noemde, kenden iTunes en
// TIDAL Plaza — Yo-Yo; Deezer en MusicBrainz niet. De andere zeven kende geen bron onder die artiest.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/itunes.dart';
import 'package:debridmusic/radiolijst.dart';
import 'package:debridmusic/recommend.dart';

/// Wat `itunes.apple.com/search?term=Plaza Yo Yo&entity=song&country=BE` op 22-10-2026 gaf, ingekort tot de velden
/// die gelezen worden.
const _plaza =
    '{"resultCount":3,"results":[{"wrapperType":"track","kind":"song","artistName":"Plaza","trackName":"Yo-Yo (Ten '
    'Years Ago)","collectionName":"Yo-Yo (Ten Years Ago) - Single","trackTimeMillis":552821,"artworkUrl100":"https:'
    '//is1-ssl.mzstatic.com/image/thumb/Music211/v4/e4/60/03/e46003dd-55a8-b7a2-81d5-f45fb0bfc62c/10671.jpg/100x100bb'
    '.jpg"},{"wrapperType":"track","kind":"song","artistName":"Ravyn Lenae","trackName":"Love Me Not","collectionName"'
    ':"Bird\'s Eye","trackTimeMillis":213467},{"wrapperType":"track","kind":"song","artistName":"Pedro Capó & '
    'Farruko","trackName":"Calma (Remix)","collectionName":"Calma (Remix) - Single","trackTimeMillis":238200}]}';

void main() {
  group('het antwoord van Apple', () {
    test('DE KERN: artiest, titel, album en lengte uit het echte antwoord', () {
      final n = itunesNummers(jsonDecode(_plaza) as Map<String, dynamic>);
      expect(n.length, 3);
      expect(
        (n.first.artist, n.first.title, n.first.album, n.first.seconds),
        ('Plaza', 'Yo-Yo (Ten Years Ago)', 'Yo-Yo (Ten Years Ago) - Single', 553),
      );
      expect(n.first.cover, contains('mzstatic.com'));
    });

    test('alleen liedjes; leeg of kapot is niets', () {
      expect(
        itunesNummers({
          'results': [
            {'kind': 'music-video', 'artistName': 'Plaza', 'trackName': 'Yo-Yo'},
            {'kind': 'song', 'artistName': '', 'trackName': 'Yo-Yo'},
          ],
        }),
        isEmpty,
      );
      expect(itunesNummers(null), isEmpty);
      expect(itunesNummers({'results': 'onzin'}), isEmpty);
    });
  });

  group('vinden', () {
    test('DE KERN: "Plaza — Yo Yo" is Plaza — Yo-Yo (Ten Years Ago); een ander nummer van hem niet', () async {
      final gevraagd = <Uri>[];
      final z = ItunesZoeker(
        client: MockClient((v) async {
          gevraagd.add(v.url);
          return http.Response.bytes(utf8.encode(_plaza), 200);
        }),
      );
      final r = (await z.vind('Plaza', 'Yo Yo'))!;
      expect((r.artist, r.title, r.seconds), ('Plaza', 'Yo-Yo (Ten Years Ago)', 553));
      expect(gevraagd.single.queryParameters, containsPair('country', 'BE'));
      expect(gevraagd.single.queryParameters, containsPair('entity', 'song'));
      expect(await z.vind('Plaza', 'Love You Again'), isNull);
      expect(await z.vind('Bart Kaëll', 'Viva Hollandia'), isNull);
    });

    test('geen antwoord of een fout van Apple is null, geen uitzondering', () async {
      final kapot = ItunesZoeker(client: MockClient((_) async => http.Response('nee', 503)));
      expect(await kapot.vind('Plaza', 'Yo Yo'), isNull);
      final weg = ItunesZoeker(client: MockClient((_) async => throw const SocketException('geen net')));
      expect(await weg.vind('Plaza', 'Yo Yo'), isNull);
    });
  });

  group('twintig per minuut', () {
    final nu = DateTime(2026, 10, 22, 14, 0);
    test('onder de twintig meteen; bij twintig tot de oudste een minuut oud is', () {
      expect(wachtVoorVenster([for (var i = 0; i < 19; i++) nu.subtract(Duration(seconds: i))], nu), Duration.zero);
      final twintig = [for (var i = 0; i < 20; i++) nu.subtract(Duration(seconds: 50 - i))];
      expect(wachtVoorVenster(twintig, nu), const Duration(seconds: 10));
      final oud = [for (var i = 0; i < 30; i++) nu.subtract(const Duration(minutes: 2))];
      expect(wachtVoorVenster(oud, nu), Duration.zero, reason: 'wat buiten de minuut valt, telt niet');
    });
  });

  group('in de modellijst', () {
    test('DE KERN: Deezer, dan jouw bibliotheek, dan iTunes; het logboek zegt waar het vandaan kwam', () async {
      final log = <String>[];
      final gevraagd = <String>[];
      final deezer = RecommendService(adem: Duration.zero, haal: (url) async => {'data': <Object>[]});
      final uit = await deezer.lijstOpDeezer(
        [AiNummer('Plaza', 'Yo Yo'), AiNummer('Bart Kaëll', 'Viva Hollandia')],
        spoor: log.add,
        elders: (n) async {
          gevraagd.add(n.titel);
          return n.artiest == 'Plaza' ? const RecTrack('Plaza', 'Yo-Yo (Ten Years Ago)', null, seconds: 553) : null;
        },
        eldersNaam: 'iTunes',
      );
      expect([for (final t in uit) t.title], ['Yo-Yo (Ten Years Ago)']);
      expect(gevraagd, ['Yo Yo', 'Viva Hollandia']);
      expect(log.last, contains('niet op Deezer, wel op iTunes: Plaza — Yo-Yo (Ten Years Ago)'));
      expect(log.last, contains('niet gevonden: Bart Kaëll — Viva Hollandia'));
    });

    test('wat al van jou is, gaat niet naar iTunes; hoogstens twaalf per lijst', () async {
      final gevraagd = <String>[];
      final deezer = RecommendService(adem: Duration.zero, haal: (url) async => {'data': <Object>[]});
      await deezer.lijstOpDeezer(
        [for (var i = 0; i < 20; i++) AiNummer('A$i', 'T$i')],
        vanJou: (n) => n.artiest == 'A0' ? const RecTrack('A0', 'T0', null) : null,
        elders: (n) async {
          gevraagd.add(n.artiest);
          return null;
        },
      );
      expect(gevraagd, isNot(contains('A0')));
      expect(gevraagd.length, kEldersPerLijst);
    });

    test('aangesloten: elke plek die een lijst namen opzoekt, vraagt ook iTunes', () {
      // Geteld tegen het aantal opzoekingen en niet tegen een vast getal: er kwamen er sinds de eerste drie bij
      // (Last.fm bij de start en onderweg, de rij uit je Last.fm-geschiedenis), en elke nieuwe hoort iTunes ook te vragen.
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final opzoekingen = RegExp(r'lijstOpDeezer\(').allMatches(main).length;
      expect(opzoekingen, greaterThanOrEqualTo(3));
      expect('elders: _itunesVoorModel'.allMatches(main).length, opzoekingen);
      expect(main, contains('Future<RecTrack?> _itunesVoorModel(AiNummer n) => _itunes.vind(n.artiest, n.titel);'));
    });
  });
}
