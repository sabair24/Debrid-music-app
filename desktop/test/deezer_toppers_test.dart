/// De toppers van een artiest, ook als Deezer's eigen lijst zwijgt.
///
/// Op 04-10-2026 gaf `api.deezer.com/artist/{id}/top` voor élke artiest `{"data":[],"total":0}` —
/// gemeten voor Michael Jackson (259), Stevie Wonder, Daft Punk en Backstreet Boys — terwijl gewoon
/// zoeken, `/related` en `/radio` gewoon antwoordden. Ontdek bleef leeg, en een radio vanaf een
/// artiest kreeg geen enkel nummer van die artiest zelf. Gevonden doordat `discover_test` omviel, ook
/// op de commit van vóór die dag. Gewoon zoeken op "Michael Jackson" gaf die dag 82 treffers, 80 van
/// hem, en op Deezer's eigen `rank` stonden Smooth Criminal, Billie Jean en Beat It bovenaan.
library;

import 'dart:io';

import 'package:debridmusic/radiosmaak.dart';
import 'package:debridmusic/recommend.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _nr(String titel, int artiestId, String artiest, int rang) => {
      'title': titel,
      'artist': {'id': artiestId, 'name': artiest},
      'album': {'title': 'A', 'id': 1},
      'duration': 240,
      'rank': rang,
    };

/// Een Deezer met een zwijgende `/top`, zoals op 04-10-2026.
RecommendService _deezer(List<String> urls, {List<Map<String, dynamic>>? top}) =>
    RecommendService(haal: (url) async {
      urls.add(url);
      if (url.contains('/search/artist')) {
        return {
          'data': [
            {'id': 259, 'name': 'Michael Jackson'}
          ]
        };
      }
      if (url.contains('/artist/259/top')) return {'data': top ?? const [], 'total': 0};
      if (url.contains('/search?q=')) {
        return {
          'data': [
            _nr('Thriller', 259, 'Michael Jackson', 942416),
            _nr('Billie Jean', 259, 'Michael Jackson', 971418),
            _nr('Michael Jackson Tribute', 9999, 'Een Naamgenoot', 999999),
            _nr('Smooth Criminal', 259, 'Michael Jackson', 981768),
            _nr('Beat It', 259, 'Michael Jackson', 970264),
          ]
        };
      }
      return {'data': const []};
    });

void main() {
  test('DE KERN: zwijgt /top, dan komen de toppers uit gewoon zoeken — op Deezer\'s eigen populariteit',
      () async {
    final urls = <String>[];
    final uit = await _deezer(urls).topVan('Michael Jackson', limit: 3);
    expect([for (final t in uit) t.title], ['Smooth Criminal', 'Billie Jean', 'Beat It'],
        reason: 'Ontdek bleef leeg: nul nummers uit drie zaadartiesten');
    expect(urls.where((u) => u.contains('/search?q=Michael%20Jackson')), hasLength(1));
  });

  test('DE VAL: een naamgenoot in de treffers telt niet — alleen wat van dezelfde id is', () async {
    final uit = await _deezer([]).topVan('Michael Jackson', limit: 10);
    expect([for (final t in uit) t.artist].toSet(), {'Michael Jackson'},
        reason: 'de populairste treffer was van iemand anders, en zou bovenaan de radio staan');
    expect(uit, hasLength(4));
  });

  test('DE GRENS: geeft /top wél iets, dan wordt er niet gezocht', () async {
    final urls = <String>[];
    final uit = await _deezer(urls, top: [_nr('Bad', 259, 'Michael Jackson', 1)]).topVan('Michael Jackson');
    expect([for (final t in uit) t.title], ['Bad']);
    expect(urls.where((u) => u.contains('/search?q=')), isEmpty, reason: 'geen extra verzoek als het niet hoeft');
  });

  test('topUitZoeken: vanaf de juiste plek, zoals de radio zijn "vanaf" gebruikt', () {
    final eigen = topUitZoeken([
      _nr('c', 1, 'X', 10),
      _nr('a', 1, 'X', 30),
      _nr('z', 2, 'Y', 99),
      _nr('b', 1, 'X', 20),
      'geen kaart',
    ], 1);
    expect([for (final t in eigen) t['title']], ['a', 'b', 'c']);
    expect([for (final t in eigen.skip(1).take(1)) t['title']], ['b']);
  });

  test('DE VAL: "Ontdekken" slaat de bekendste vijf van het zaad over — ook via de terugval', () async {
    final rs = RecommendService(haal: (url) async {
      if (url.contains('/search/artist')) {
        return {
          'data': [
            {'id': 259, 'name': 'Michael Jackson'}
          ]
        };
      }
      if (url.contains('/top')) return {'data': const [], 'total': 0};
      if (url.contains('/search?q=')) {
        return {
          'data': [for (var i = 1; i <= 12; i++) _nr('Nummer $i', 259, 'Michael Jackson', 1000 - i)]
        };
      }
      return {'data': const []};
    });
    final uit = await rs.mixRadio('Michael Jackson', smaak: Radiosmaak.ontdekken);
    expect({for (final t in uit) t.title}, {for (var i = 6; i <= 12; i++) 'Nummer $i'},
        reason: 'anders speelt "Ontdekken" gewoon Billie Jean en Thriller, net als "Bekend"');
  });

  test('Ontdek vult zich weer, ook met een zwijgende /top', () async {
    final rs = RecommendService(haal: (url) async {
      if (url.contains('/search/artist')) {
        return {
          'data': [
            {'id': 1, 'name': 'Zaad'}
          ]
        };
      }
      if (url.contains('/artist/1/related')) {
        return {
          'data': [
            {'id': 2, 'name': 'Buur Een'},
            {'id': 3, 'name': 'Buur Twee'},
          ]
        };
      }
      if (url.contains('/top')) return {'data': const [], 'total': 0};
      if (url.contains('/search?q=Buur%20Een')) return {'data': [_nr('Een', 2, 'Buur Een', 5)]};
      if (url.contains('/search?q=Buur%20Twee')) return {'data': [_nr('Twee', 3, 'Buur Twee', 5)]};
      return {'data': const []};
    });
    final uit = await rs.discover(['Zaad']);
    expect({for (final t in uit) t.title}, {'Een', 'Twee'},
        reason: 'het scherm Ontdek bleef leeg op 04-10-2026');
  });

  test('alle vijf de plekken gaan via de terugval', () {
    final bron = File('lib/recommend.dart').readAsStringSync();
    expect(RegExp(r'/top\?').allMatches(bron).length, 1,
        reason: 'een rechtstreekse /top-aanroep blijft leeg zodra Deezer weer zwijgt');
    expect(RegExp(r'_top\(').allMatches(bron).length, greaterThanOrEqualTo(6),
        reason: 'de definitie plus topVan, zaad, buren, model en Ontdek');
  });
}
