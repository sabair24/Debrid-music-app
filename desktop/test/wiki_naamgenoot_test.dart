// "Over Milow · Wikipedia" toonde de Duitse gemeente.
//
// Saber, 11-11-2026, schermafdruk van de artiestpagina van Milow: *"Milow is een gemeente in de Duitse deelstaat
// Mecklenburg-Voor-Pommeren"*. Wikidata geeft bij "Milow" eerst de gemeente (Q674445), dan pas de zanger (Q784453), en de
// app nam de eerste met dezelfde naam. Nu alleen een item met een nummer bij MusicBrainz, Discogs of Spotify; een oude
// bewaarde keuze wordt één keer nagekeken. Live nagemeten (wegwerptoets): Milow → "Milow (zanger)", Khaled → "zanger uit
// Algerije", Zornik → "Belgische popgroep", Air → "Air (Franse band)".
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/cachesleutel.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/wikipedia.dart';

const _gemeente = 'Q674445', _zanger = 'Q784453';

Map<String, dynamic> _claim(String waarde) => {
      'mainsnak': {
        'datavalue': {'value': waarde, 'type': 'string'}
      }
    };

/// Wikidata en Wikipedia zoals ze op 11-11-2026 antwoordden, ingekort. [stil]: alles faalt. [zonderZanger]: Wikidata kent
/// alleen de gemeente, en Wikipedia vindt bij "Milow" alleen haar pagina — de zoekval.
MockClient _net(List<String> gevraagd, {bool stil = false, bool zonderZanger = false}) => MockClient((req) async {
      final q = req.url.queryParameters;
      gevraagd.add('${q['action']} ${q['entity'] ?? q['ids'] ?? q['search'] ?? q['srsearch'] ?? q['titles'] ?? ''} '
              '${q['property'] ?? q['list'] ?? q['prop'] ?? ''}'
          .trim());
      if (stil) return http.Response('', 503);
      switch (q['action']) {
        case 'wbsearchentities':
          return http.Response(
              jsonEncode({
                'search': [
                  {'id': _gemeente, 'label': 'Milow', 'description': 'Mecklenburg'},
                  if (!zonderZanger) {'id': _zanger, 'label': 'Milow', 'description': 'Belgisch zanger en songwriter'},
                ]
              }),
              200);
        case 'query':
          if (q['list'] == 'search') {
            return http.Response(
                jsonEncode({
                  'query': {
                    'search': [
                      {'title': 'Milow'}
                    ]
                  }
                }),
                200);
          }
          return http.Response(
              jsonEncode({
                'query': {
                  'pages': [
                    {
                      'title': 'Milow',
                      'pageprops': {'wikibase_item': _gemeente}
                    }
                  ]
                }
              }),
              200);
        case 'wbgetclaims':
          final heeft = q['entity'] == _zanger && q['property'] == 'P434';
          return http.Response(
              jsonEncode({
                'claims': heeft
                    ? {
                        'P434': [_claim('5a8e07d5-d932-4484-a7f7-e700793a9c94')]
                      }
                    : {}
              }),
              200);
        case 'wbgetentities':
          return http.Response(
              jsonEncode({
                'entities': {
                  _zanger: {
                    'sitelinks': {
                      'nlwiki': {'title': 'Milow (zanger)'}
                    }
                  }
                }
              }),
              200);
      }
      return http.Response('', 404);
    });

File _naamBestand(String naam) =>
    File('$appDir${Platform.pathSeparator}wikipedia${Platform.pathSeparator}${fnv1a('a1|${naam.toLowerCase()}')}.json');

void main() {
  setUp(() {
    setAppDirForTest(Directory.systemTemp.createTempSync('wiki_naamgenoot').path);
    MusicBrainzService.resetLanes();
  });

  group('herkennen zonder netwerk', () {
    test('een nummer bij MusicBrainz telt; een lege of waardeloze rij niet', () {
      expect(
          heeftKenmerk({
            'claims': {
              'P434': [_claim('x')]
            }
          }, 'P434'),
          isTrue);
      expect(heeftKenmerk({'claims': {}}, 'P434'), isFalse);
      expect(
          heeftKenmerk({
            'claims': {
              'P434': [
                {
                  'mainsnak': {'snaktype': 'novalue'}
                }
              ]
            }
          }, 'P434'),
          isFalse,
          reason: '"heeft geen MusicBrainz-nummer" is geen nummer');
    });

    test('het Wikidata-nummer van een pagina', () {
      expect(
          wikidataNummerUit({
            'query': {
              'pages': [
                {
                  'title': 'Milow (zanger)',
                  'pageprops': {'wikibase_item': _zanger}
                }
              ]
            }
          }),
          _zanger);
      expect(
          wikidataNummerUit({
            'query': {
              'pages': [
                {'title': 'Milow', 'missing': true}
              ]
            }
          }),
          isNull);
    });

    test('drie kenmerken, MusicBrainz eerst', () {
      expect(kArtiestKenmerken, ['P434', 'P1953', 'P1902']);
    });
  });

  group('de titelweg', () {
    test('DE KERN: een verse zoektocht slaat de gemeente over die vooraan staat, en neemt de zanger', () async {
      final gevraagd = <String>[];
      final t = await http.runWithClient(() => WikipediaService().titelVoor('Milow'), () => _net(gevraagd));
      expect(t?.titel, 'Milow (zanger)');
      expect(await WikipediaService().wikidataVoor('Milow'), _zanger);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('DE KERN: de oude keuze (de gemeente) wordt nagekeken en vervangen door de zanger', () async {
      final f = _naamBestand('Milow');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({'taal': 'nl', 'titel': 'Milow (Mecklenburg)', 'q': _gemeente}));
      final gevraagd = <String>[];
      final t = await http.runWithClient(() => WikipediaService().titelVoor('Milow'), () => _net(gevraagd));
      expect(t?.titel, 'Milow (zanger)');
      expect(await WikipediaService().wikidataVoor('Milow'), _zanger);
      expect(jsonDecode(f.readAsStringSync())['v'], kWikiNaamVersie);
      expect(gevraagd.where((g) => g.startsWith('wbgetclaims $_gemeente')).length, kArtiestKenmerken.length,
          reason: 'de gemeente één keer nagekeken, niet nog eens bij het opnieuw zoeken ([_oordeel])');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('een oude keuze die klopt, blijft; daarna geen enkel verzoek meer', () async {
      final f = _naamBestand('Milow');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({'taal': 'nl', 'titel': 'Milow (zanger)', 'q': _zanger}));
      final gevraagd = <String>[];
      final t = await http.runWithClient(() => WikipediaService().titelVoor('Milow'), () => _net(gevraagd));
      expect(t?.titel, 'Milow (zanger)');
      expect(gevraagd, ['wbgetclaims $_zanger P434']);
      gevraagd.clear();
      await http.runWithClient(() => WikipediaService().titelVoor('Milow'), () => _net(gevraagd));
      expect(gevraagd, isEmpty, reason: 'nagekeken is nagekeken');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('ook de zoekval op Wikipedia zelf neemt geen gemeente aan met dezelfde titel', () async {
      final gevraagd = <String>[];
      final t = await http.runWithClient(
          () => WikipediaService().titelVoor('Milow'), () => _net(gevraagd, zonderZanger: true));
      expect(t, isNull, reason: 'liever TheAudioDB dan een gemeente');
      expect(gevraagd, contains('query Milow pageprops'), reason: 'de titel "Milow" werd nagekeken');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('zwijgt Wikidata, dan blijft de oude keuze voorlopig staan, en wordt later nagekeken', () async {
      final f = _naamBestand('Milow');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({'taal': 'nl', 'titel': 'Milow (zanger)', 'q': _zanger}));
      final t = await http.runWithClient(() => WikipediaService().titelVoor('Milow'), () => _net([], stil: true));
      expect(t?.titel, 'Milow (zanger)', reason: 'een hapering gooit geen goed artikel weg');
      expect(jsonDecode(f.readAsStringSync())['v'], isNull);
      expect(await WikipediaService().wikidataVoor('Milow'), isNull, reason: 'Foto kiezen wacht op het nakijken');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
