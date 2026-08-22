/// Een plaat benoemen op wat hij KLINKT, als geen catalogus hem op naam kan vinden.
///
/// De stemming is het hele idee, en die is met opzet pure rekenkunde: acht platen in de bibliotheek
/// komen leeg terug bij zowel MusicBrainz als Discogs, en het zijn allemaal verzamelaars.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/acoustid.dart';
import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/fingerprint.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('stemming over de release-groep', () {
    test('waar de meeste nummers het over eens zijn wint', () {
      // Een verzamelaar: elk nummer staat ook op zijn eigen album, maar op één uitgave komen ze
      // allemaal samen.
      final perTrack = [
        ['verzamelaar', 'album-a'],
        ['verzamelaar', 'album-b'],
        ['verzamelaar', 'album-c'],
        ['verzamelaar'],
      ];
      expect(bestReleaseGroup(perTrack), 'verzamelaar');
    });

    test('één nummer op acht persingen overstemt de rest niet', () {
      // Zonder ontdubbelen per bestand zou dit ene bestand met acht vermeldingen van dezelfde groep
      // in zijn eentje elk ander bestand overstemmen.
      final perTrack = [
        ['x', 'x', 'x', 'x', 'x', 'x', 'x', 'x'],
        ['echt'],
        ['echt'],
        ['echt'],
      ];
      expect(bestReleaseGroup(perTrack), 'echt');
    });

    test('te weinig eensgezindheid geeft geen antwoord', () {
      final perTrack = [
        ['a'],
        ['b'],
        ['c'],
        ['d'],
      ];
      expect(bestReleaseGroup(perTrack), isNull,
          reason: 'vier nummers die vier kanten op wijzen benoemen geen plaat');
    });

    test('nummers die AcoustID niet kent tellen niet als tegenstem', () {
      // Op een Belgische hardcore-verzamelaar kent AcoustID een deel van de nummers gewoon niet.
      // Zes van de zes herkende die het eens zijn is een antwoord; de zes onbekende wegtellen als
      // "oneens" zou dat weggooien.
      final perTrack = [
        <String>[], <String>[], <String>[],
        ['de plaat'], ['de plaat'], ['de plaat'],
      ];
      expect(bestReleaseGroup(perTrack), 'de plaat');
    });

    test('één bestand benoemt geen plaat', () {
      // "Vlaamse Diva's" is één bestand. Elke groep waar die ene opname op staat krijgt dan precies
      // één stem, en "de hoogste" is wie de tabel toevallig eerst teruggeeft -- een gok met een
      // getal erbij. Eén nummer staat op een dozijn verzamelaars; dat zegt niets over deze map.
      expect(bestReleaseGroup([['a', 'b', 'c']]), isNull);
    });

    test('een gelijkspel is geen winnaar', () {
      expect(bestReleaseGroup([['a'], ['b']]), isNull);
      // Maar een echte meerderheid wel, ook als er een tweede groep meestemt.
      expect(bestReleaseGroup([['a'], ['a', 'b'], ['a']]), 'a');
    });

    test('helemaal niets is geen antwoord', () {
      expect(bestReleaseGroup(const []), isNull);
      expect(bestReleaseGroup([<String>[], <String>[]]), isNull);
    });
  });

  group('een mislukking van vóór het luisteren krijgt één nieuwe kans', () {
    // Gemeten op de avond dat vingerafdrukken uitkwamen: de acht verzamelaars waar het voor gebouwd
    // was, waren uren eerder al mislukt op titel. Ze droegen dus failedMs, en de takenlijst van de
    // veeg kwam terug met "25 te doen van 132" -- met geen van de acht erin. De functie kon pas de
    // volgende dag geprobeerd worden.
    AlbumFacts mislukt({required int heard}) => AlbumFacts(
          uid: 'u',
          trackSetHash: 'h',
          failedMs: DateTime.now().millisecondsSinceEpoch,
          heardVersion: heard,
        );

    test('nog niet geluisterd: opnieuw proberen', () {
      expect(
          needsResolve(mislukt(heard: 0),
              trackSetHash: 'h', nowMs: DateTime.now().millisecondsSinceEpoch, canHear: true),
          isTrue);
    });

    test('al geluisterd: met rust laten', () {
      expect(
          needsResolve(mislukt(heard: kSoundVersion),
              trackSetHash: 'h', nowMs: DateTime.now().millisecondsSinceEpoch, canHear: true),
          isFalse,
          reason: 'één extra poging, geen lus');
    });

    test('kan niet luisteren: dan verandert er niets', () {
      expect(
          needsResolve(mislukt(heard: 0),
              trackSetHash: 'h', nowMs: DateTime.now().millisecondsSinceEpoch, canHear: false),
          isFalse);
    });

    test('een geslaagde opzoeking wordt niet opnieuw gedaan om te luisteren', () {
      final goed = AlbumFacts(
        uid: 'u',
        trackSetHash: 'h',
        source: 'MusicBrainz',
        tracklist: const [ChoiceTrack('1', 'Iets', 200)],
      );
      expect(
          needsResolve(goed,
              trackSetHash: 'h', nowMs: DateTime.now().millisecondsSinceEpoch, canHear: true),
          isFalse);
    });

    test('een gerepareerde geluidsweg levert opnieuw een beurt op', () {
      // Precies wat er misging: versie 1 vroeg AcoustID met een plus in plaats van een spatie, dus
      // die "poging" kon per definitie niets vinden -- en verbruikte wel de enige kans. Nu opent een
      // hoger versienummer die kans weer, en dezelfde versie niet.
      expect(
          needsResolve(mislukt(heard: kSoundVersion - 1),
              trackSetHash: 'h', nowMs: DateTime.now().millisecondsSinceEpoch, canHear: true),
          isTrue);
    });

    test('"geluisterd" overleeft de schijf, ook de oude booleaanse vorm', () {
      final j = mislukt(heard: kSoundVersion).toJson();
      expect(AlbumFacts.fromJson(j)!.heardVersion, kSoundVersion);
      expect(AlbumFacts.fromJson(mislukt(heard: 0).toJson())!.heardVersion, 0);
      // Wat de ene build met een bool wegschreef betekent "versie 1 geprobeerd" -- en versie 1 is
      // juist de kapotte, dus die platen horen hun beurt terug te krijgen.
      expect(AlbumFacts.fromJson({'uid': 'u', 'hash': 'h', 'heard': true})!.heardVersion, 1);
    });
  });

  test('de meta-parameter scheidt met een SPATIE, niet met een plus', () {
    // Eén teken, en het verschil tussen een antwoord en stilte. De documentatie schrijft
    // meta=recordings+releasegroups, maar dat is een URL waarin + een spatie IS. Als formulierveld
    // codeert Dart een letterlijke plus als %2B, en dan kreeg de server één onbekend woord binnen.
    // Gemeten op Michael Jackson: perfecte match op 0,9998 en nul metadata -- wat van buitenaf leest
    // als "AcoustID kent deze plaat niet".
    expect(AcoustIdService.metaParam, isNot(contains('+')));
    expect(AcoustIdService.metaParam.split(' '), containsAll(['recordings', 'releasegroupids']));
  });

  group('welke opname is bedoeld', () {
    AcoustIdMatch m(double score, String titel, double? secs) =>
        AcoustIdMatch(score, 'r-$titel', titel, const [], artist: 'Christina Aguilera', seconds: secs);

    test('de looptijd van het bestand beslist, niet de score alleen', () {
      // Gemeten geval. De hoogste score, 99%, hoort bij een opname met "(radio edit)" in de titel
      // die 3:17 duurt, terwijl het bestand de albumversie van 3:49 is. Blind de topscore nemen had
      // een versiemarkering geschreven die het bestand niet verdient -- een fout antwoord met hoog
      // vertrouwen, en dat is de vervelendste soort.
      final beste = AcoustIdService.bestFor([
        m(0.99, "Ain't No Other Man (radio edit)", 197),
        m(0.95, "Ain't No Other Man", 229),
      ], 229);
      expect(beste!.title, "Ain't No Other Man");
    });

    test('zegt niemand hoe lang hij is, dan telt de score gewoon', () {
      final beste = AcoustIdService.bestFor([
        m(0.99, 'Iets', null),
        m(0.80, 'Iets anders', null),
      ], 229);
      expect(beste!.title, 'Iets');
    });

    test('past geen enkele opgegeven lengte, dan liever niets zeggen', () {
      // Zwijgen is beter dan de verkeerde versie benoemen: de gebruiker ziet dan "niet herkend"
      // in plaats van een voorstel dat zijn tags zou verslechteren.
      expect(
          AcoustIdService.bestFor([
            m(0.99, 'Live at Wembley', 574),
            m(0.90, 'Extended Mix', 480),
          ], 229),
          isNull);
    });

    test('zonder lengte van het bestand blijft de score de enige maat', () {
      final beste = AcoustIdService.bestFor([m(0.99, 'Iets', 197)], null);
      expect(beste!.title, 'Iets');
    });

    test('niets in, niets uit', () {
      expect(AcoustIdService.bestFor(const [], 200), isNull);
    });
  });

  group('antwoord lezen', () {
    test('beide vormen van release-groepen worden gelezen, beste score eerst', () {
      final body = {
        'status': 'ok',
        'results': [
          {
            'score': 0.6,
            'recordings': [
              {'id': 'rec-laag', 'title': 'Tweede', 'releasegroupids': ['g1', 'g2']}
            ]
          },
          {
            'score': 0.98,
            'recordings': [
              {
                'id': 'rec-hoog',
                'title': 'Eerste',
                'releasegroups': [
                  {'id': 'g3'}
                ]
              }
            ]
          },
        ],
      };
      final out = AcoustIdService.parseLookup(body);
      expect(out, hasLength(2));
      expect(out.first.recordingId, 'rec-hoog', reason: 'de zekerste hoort vooraan');
      expect(out.first.releaseGroups, ['g3']);
      expect(out.last.releaseGroups, ['g1', 'g2']);
    });

    test('de artiest komt mee, en een duet leest als één regel', () {
      // Voor een los bestand IS het paar artiest-plus-titel het antwoord: een nummer dat in de
      // wortel staat onder de naam van een verzamelaar valt niet op zijn album te herkennen.
      final out = AcoustIdService.parseLookup({
        'status': 'ok',
        'results': [
          {
            'score': 1.0,
            'recordings': [
              {
                'id': 'r',
                'title': 'Voodoo',
                'artists': [
                  {'name': 'Nunca'},
                  {'name': 'Pat Krimson'},
                ],
              }
            ]
          }
        ],
      });
      expect(out.single.artist, 'Nunca & Pat Krimson');
      expect(out.single.title, 'Voodoo');
    });

    test('een opname zonder artiest levert een lege naam, geen uitzondering', () {
      final out = AcoustIdService.parseLookup({
        'status': 'ok',
        'results': [
          {
            'score': 1.0,
            'recordings': [
              {'id': 'r', 'title': 'Naamloos', 'artists': 'rommel'}
            ]
          }
        ],
      });
      expect(out.single.artist, isEmpty);
    });

    test('rommel levert niets op in plaats van een uitzondering', () {
      expect(AcoustIdService.parseLookup({'status': 'ok'}), isEmpty);
      expect(AcoustIdService.parseLookup({'status': 'ok', 'results': 'geen lijst'}), isEmpty);
      expect(
          AcoustIdService.parseLookup({
            'status': 'ok',
            'results': [
              {'score': 1.0, 'recordings': [{'title': 'zonder id'}]}
            ]
          }),
          isEmpty);
    });
  });

  group('een mislukking is geen "niet herkend"', () {
    /// **Waar dit over gaat.** Op de pc kwam er op élk nummer hetzelfde uit: "Geen van deze nummers
    /// is herkend" — ook op wereldberoemde platen waar AcoustID honderdduizend vingerafdrukken van
    /// heeft. Dat kón niet kloppen, maar er viel niets aan te onderzoeken: geen sleutel, een
    /// geweigerde sleutel, een tijdslimiet, een storing en een werkelijk onbekende plaat gaven
    /// alle vijf een lege lijst en verder niets.
    ///
    /// De verreweg meest gemaakte fout zit in die tweede: AcoustID heeft twee soorten sleutels en
    /// zijn eigen site toont de verkeerde het grootst. Deze toetsen leggen vast dat de app dat nu
    /// zegt in plaats van te zwijgen.
    Fingerprint vp() => const Fingerprint(229, [], 'AQAAA-vingerafdruk');

    AcoustIdService dienst(String sleutel, Future<http.Response> Function(http.Request) antwoord) =>
        AcoustIdService(AppSettings()..acoustidKey = sleutel, client: MockClient(antwoord));

    test('zonder sleutel wordt er niet gezwegen maar gezegd wat er ontbreekt', () async {
      final a = await AcoustIdService(AppSettings()).identify(vp());
      expect(a.gelukt, isFalse);
      expect(a.fout, contains('Instellingen'));
      expect(a.fout, contains('APPLICATION'));
    });

    test('de verkeerde soort sleutel wordt bij naam genoemd', () async {
      // Fout 4 van de server: "invalid API key". Precies wat je krijgt als je de sleutel van
      // acoustid.org/api-key plakt in plaats van die van acoustid.org/my-applications.
      final a = await dienst(
          'user-sleutel',
          (_) async => http.Response(
              jsonEncode({
                'status': 'error',
                'error': {'code': 4, 'message': 'invalid API key'}
              }),
              400)).identify(vp());
      expect(a.gelukt, isFalse);
      expect(a.fout, contains('my-applications'),
          reason: 'zonder de plek waar de goede sleutel staat helpt de melding niemand');
      expect(a.fout, contains('api-key'), reason: 'en welke de verkeerde is');
    });

    test('een user-sleutel die als zodanig herkend wordt, ook', () async {
      final a = await dienst(
          'x',
          (_) async => http.Response(
              jsonEncode({
                'status': 'error',
                'error': {'code': 6, 'message': 'invalid user API key'}
              }),
              400)).identify(vp());
      expect(a.fout, contains('USER-sleutel'));
    });

    test('te druk is iets heel anders dan onbekend, en zegt dat ook', () async {
      final a = await dienst(
          'goed',
          (_) async => http.Response(
              jsonEncode({
                'status': 'error',
                'error': {'code': 14, 'message': 'rate limit exceeded'}
              }),
              429)).identify(vp());
      expect(a.fout, contains('wacht'));
      expect(a.fout, contains('in orde'), reason: 'de sleutel is hier niet de schuldige');
    });

    test('een pc zonder net zegt dat, en niet "niet herkend"', () async {
      final a = await dienst('goed', (_) async => throw const SocketException('geen netwerk'))
          .identify(vp());
      expect(a.gelukt, isFalse);
      expect(a.fout, contains('niet bereikt'));
    });

    test('gevraagd en werkelijk onbekend: leeg, en GEEN fout', () async {
      // De enige stand waarin "niet herkend" de waarheid is. Zou hier ook een reden staan, dan was
      // het onderscheid weer weg — nu andersom.
      final a = await dienst('goed',
              (_) async => http.Response(jsonEncode({'status': 'ok', 'results': []}), 200))
          .identify(vp());
      expect(a.gelukt, isTrue);
      expect(a.matches, isEmpty);
      expect(a.fout, isNull);
    });

    test('en een gewoon antwoord komt er nog steeds gewoon uit', () async {
      final a = await dienst(
          'goed',
          (_) async => http.Response(
              jsonEncode({
                'status': 'ok',
                'results': [
                  {
                    'score': 0.98,
                    'recordings': [
                      {
                        'id': 'rec-1',
                        'title': 'Billie Jean',
                        'duration': 294,
                        'artists': [
                          {'name': 'Michael Jackson'}
                        ],
                        'releasegroupids': ['groep-1'],
                      }
                    ]
                  }
                ]
              }),
              200)).identify(vp());
      expect(a.gelukt, isTrue);
      expect(a.matches, hasLength(1));
      expect(a.matches.first.title, 'Billie Jean');
      expect(a.matches.first.artist, 'Michael Jackson');
      expect(a.matches.first.releaseGroups, ['groep-1']);
    });

    test('de sleutel gaat mee in het lichaam, met de meta-parameter erbij', () async {
      // Zou de sleutel ooit uit de vraag vallen, dan antwoordt AcoustID met fout 2 en zag je
      // opnieuw "niet herkend" zonder reden. Dit legt vast wat er werkelijk verstuurd wordt.
      String? verstuurd;
      await dienst('mijn-sleutel', (req) async {
        verstuurd = req.body;
        return http.Response(jsonEncode({'status': 'ok', 'results': []}), 200);
      }).identify(vp());
      expect(verstuurd, contains('client=mijn-sleutel'));
      expect(verstuurd, contains('duration=229'));
      expect(verstuurd, isNot(contains('%2B')), reason: 'een plus in meta is de oude stille fout');
    });
  });

  group('wat een foutcode betekent', () {
    test('een onbekende code valt terug op wat de server zelf zei', () {
      expect(AcoustIdService.uitleg(code: 99, bericht: 'iets nieuws'), contains('iets nieuws'));
    });

    test('een storing bij AcoustID wijst niet naar jouw sleutel', () {
      expect(AcoustIdService.uitleg(http: 503), contains('storing'));
      expect(AcoustIdService.uitleg(http: 503), contains('niet de oorzaak'));
    });

    test('en er komt nooit een lege melding uit', () {
      expect(AcoustIdService.uitleg(), isNotEmpty);
      expect(AcoustIdService.uitleg(http: 418), isNotEmpty);
    });
  });
}
