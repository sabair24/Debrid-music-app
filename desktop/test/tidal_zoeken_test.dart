/// Zoeken in TIDAL levert nu platen én nummers, en van allebei is een doel voor tiddl te maken.
///
/// **Waarom hier een toets op staat.** De zoekopdracht vraagt sinds deze wijziging om méér dan
/// eerst: `albums,albums.artists,tracks,tracks.artists` in plaats van alleen de nummers. Dat is een
/// aanname over een API van iemand anders, en die kan zonder waarschuwing veranderen. De
/// belangrijkste toets hieronder is daarom niet "vindt hij de platen" maar "wat gebeurt er als hij
/// ze níét krijgt" — dan hoort de nummerlijst het gewoon te blijven doen, en dat is met het oog
/// niet na te kijken.
///
/// Geen netwerk, geen aanmelding: dit zijn statische functies op een antwoord dat hier staat.
library;

import 'package:debridmusic/tidal.dart';
import 'package:debridmusic/tiddl.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een `included`-blok zoals de brede zoekopdracht het teruggeeft: twee platen, twee nummers, en
/// de artiesten waar ze allebei naar wijzen.
Map<String, dynamic> hetVolledigeAntwoord() => {
      'data': {'id': 'thriller', 'type': 'searchResults'},
      'included': [
        {
          'id': '10',
          'type': 'artists',
          'attributes': {'name': 'Michael Jackson'},
        },
        {
          'id': '11',
          'type': 'artists',
          'attributes': {'name': 'Quincy Jones'},
        },
        {
          'id': '100',
          'type': 'albums',
          'attributes': {'title': 'Thriller', 'releaseDate': '1982-11-30'},
          'relationships': {
            'artists': {
              'data': [
                {'id': '10', 'type': 'artists'},
              ],
            },
          },
        },
        {
          'id': '101',
          'type': 'albums',
          'attributes': {'title': 'The Dude', 'releaseDate': '1981-03-27'},
          'relationships': {
            'artists': {
              'data': [
                {'id': '11', 'type': 'artists'},
              ],
            },
          },
        },
        {
          'id': '200',
          'type': 'tracks',
          'attributes': {'title': 'Billie Jean'},
          'relationships': {
            'artists': {
              'data': [
                {'id': '10', 'type': 'artists'},
              ],
            },
          },
        },
        {
          'id': '201',
          'type': 'tracks',
          'attributes': {'title': 'Beat It'},
          'relationships': {
            'artists': {
              'data': [
                {'id': '10', 'type': 'artists'},
              ],
            },
          },
        },
      ],
    };

void main() {
  group('de platen uit een antwoord', () {
    test('titel, artiest en jaar komen eruit', () {
      final albums = TidalService.parseAlbums(hetVolledigeAntwoord());

      expect(albums.length, 2);
      expect(albums.first.id, '100');
      expect(albums.first.title, 'Thriller');
      expect(albums.first.artist, 'Michael Jackson',
          reason: 'de naam staat in een ánder blok en wordt via de relatie opgezocht');
      expect(albums.first.jaar, '1982', reason: 'releaseDate is 1982-11-30');
      expect(albums.last.artist, 'Quincy Jones', reason: 'elke plaat zijn eigen artiest');
    });

    test('het jaar staat erbij omdat heruitgaven anders niet te onderscheiden zijn', () {
      // Twee keer dezelfde titel van dezelfde artiest is het gewone geval bij een heruitgave. Zonder
      // het jaar staan er dan twee identieke regels en is er niets te kiezen.
      final albums = TidalService.parseAlbums({
        'included': [
          {
            'id': '1',
            'type': 'albums',
            'attributes': {'title': 'Thriller', 'releaseDate': '1982-11-30'},
          },
          {
            'id': '2',
            'type': 'albums',
            'attributes': {'title': 'Thriller', 'releaseDate': '2001-10-16'},
          },
        ],
      });

      expect(albums.map((a) => a.jaar).toList(), ['1982', '2001']);
      expect(albums.map((a) => a.id).toList(), ['1', '2'], reason: 'en het id verschilt óók');
    });
  });

  group('wat er gebeurt als TIDAL geen platen meestuurt', () {
    test('de nummers blijven het doen, en dat is het hele punt', () {
      // Dit is precies de vorm die de smalle `include` teruggeeft — de vraag waar `search()` op
      // terugvalt. Zou `parseAlbums` hier struikelen, dan zou een geweigerde brede vraag het zoeken
      // in één klap slopen in plaats van alleen de platenlijst leeg te laten.
      final alleenNummers = {
        'included': [
          {
            'id': '10',
            'type': 'artists',
            'attributes': {'name': 'Faithless'},
          },
          {
            'id': '200',
            'type': 'tracks',
            'attributes': {'title': 'Insomnia'},
            'relationships': {
              'artists': {
                'data': [
                  {'id': '10', 'type': 'artists'},
                ],
              },
            },
          },
          {
            'id': '201',
            'type': 'tracks',
            'attributes': {'title': 'God Is a DJ'},
            'relationships': {
              'artists': {
                'data': [
                  {'id': '10', 'type': 'artists'},
                ],
              },
            },
          },
        ],
      };

      expect(TidalService.parseAlbums(alleenNummers), isEmpty);
      final tracks = TidalService.parseTracks(alleenNummers);
      expect(tracks.length, 2);
      expect(tracks.first.artist, 'Faithless', reason: 'de gedeelde artiestenlijst werkt nog');
    });

    test('een leeg resultaat is leeg, en meldt zich als zodanig', () {
      const niets = TidalZoekResultaat([], []);
      expect(niets.leeg, isTrue);
      expect(const TidalZoekResultaat([], [TidalTrack('1', 'x', '')]).leeg, isFalse);
    });
  });

  group('gaten in het antwoord', () {
    test('geen included, geen data, niets — en toch geen fout', () {
      // Een fout hier is een rood scherm in plaats van een lege lijst, en dat voor een antwoord dat
      // gewoon niets bevatte.
      expect(TidalService.parseAlbums(const {}), isEmpty);
      expect(TidalService.parseAlbums(const {'included': []}), isEmpty);
      expect(TidalService.parseAlbums(const {'data': {}}), isEmpty);
    });

    test('zonder artiest of datum blijft de plaat gewoon staan', () {
      final albums = TidalService.parseAlbums({
        'included': [
          {
            'id': '5',
            'type': 'albums',
            'attributes': {'title': 'Naamloos'},
          },
        ],
      });

      expect(albums.single.artist, '');
      expect(albums.single.jaar, '');
      expect(albums.single.label, 'Naamloos', reason: 'geen zwevend liggend streepje');
      expect(albums.single.sourceQuery, 'Naamloos');
    });

    test('een plaat zonder titel wordt overgeslagen', () {
      // Anders staat er een lege regel in de lijst waar niets op te klikken valt.
      final albums = TidalService.parseAlbums({
        'included': [
          {'id': '6', 'type': 'albums', 'attributes': <String, dynamic>{}},
          {
            'id': '7',
            'type': 'albums',
            'attributes': {'title': 'Wél een titel'},
          },
        ],
      });

      expect(albums.single.id, '7');
    });
  });

  group('de terugweg van het inloggen', () {
    // Deze lus was met het oog niet te onderscheiden van "bezig": de app wachtte tien minuten op
    // een bestand dat niets ooit schreef, met een draaiend wieltje erbij. Vandaar een toets op de
    // schakel die dat bestand voedt.
    test('het adres wordt uit de opstartargumenten gehaald', () {
      expect(tidalCallbackUit(['debridmusic://tidal/callback?code=ABC123&state=x']),
          'debridmusic://tidal/callback?code=ABC123&state=x');
    });

    test('ook als Windows er iets vóór zet', () {
      // Windows geeft het adres door zoals het in het register staat; er kan van alles omheen staan.
      expect(tidalCallbackUit(['--verbose', 'debridmusic://tidal/callback?code=Q']),
          'debridmusic://tidal/callback?code=Q');
      expect(tidalCallbackUit([' debridmusic://tidal/callback?code=Q ']),
          'debridmusic://tidal/callback?code=Q',
          reason: 'spaties eromheen gaan eraf');
      expect(tidalCallbackUit(['DEBRIDMUSIC://tidal/callback?code=Q']),
          'DEBRIDMUSIC://tidal/callback?code=Q',
          reason: 'hoofdletters: het register is er niet kieskeurig in');
    });

    test('een gewone start is geen terugkoppeling', () {
      // Zou dit ooit waar worden bij een normale start, dan sluit de app zichzelf meteen af en is
      // hij helemaal niet meer te openen. Dat is de reden dat dit strikt op het adres kijkt.
      expect(tidalCallbackUit([]), isNull);
      expect(tidalCallbackUit(['--observatory-port=1234']), isNull);
      expect(tidalCallbackUit(['C:\\Muziek\\debridmusic-map']), isNull);
      expect(tidalCallbackUit(['tidal/callback?code=Q']), isNull);
    });

    test('en de code komt er daarna gewoon uit', () {
      // Wat de wachtende kopie ermee doet: dezelfde functie die ook de handmatige plakweg voedt.
      expect(TidalService.extractCode('debridmusic://tidal/callback?code=ABC123&state=x'), 'ABC123');
    });
  });

  group('van een id naar een doel voor tiddl', () {
    test('de soort gaat mee, want de ids botsen', () {
      // Een plaat "1" en een nummer "1" bestaan naast elkaar. Wie de soort zou raden uit het getal,
      // haalt de verkeerde binnen — en dat merk je pas als er muziek in je map staat die je niet
      // vroeg.
      expect(tidalDoelVanId('album', '1'), 'album/1');
      expect(tidalDoelVanId('track', '1'), 'track/1');
      expect(tidalDoelVanId('album', '103805723'), 'album/103805723');
    });

    test('spaties eromheen gaan eraf', () {
      expect(tidalDoelVanId('track', ' 103805726 '), 'track/103805726');
    });

    test('een kapot id wordt hier geweigerd, niet door Python', () {
      expect(tidalDoelVanId('album', ''), isNull);
      expect(tidalDoelVanId('album', '   '), isNull);
      expect(tidalDoelVanId('album', '12 34'), isNull);
      expect(tidalDoelVanId('album', 'a/b'), isNull, reason: 'geen tweede schuine streep');
      expect(tidalDoelVanId('onzin', '123'), isNull, reason: 'tiddl kent die soort niet');
    });
  });
}
