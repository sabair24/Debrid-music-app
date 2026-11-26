// Saber, 26-11-2026: "Aanbevolen nog niet goed ?? Op gsm?" en "verkeerde artist bij dit album, dit moet chimene badi zijn??"
//
// 1. Onderweg (poort 47821) weigerde de pc `/api/aanbevolen`: de gsm hield de 14 nummers van vóór 21-11.
// 2. De albumpagina nam de artiest van het nummer (Julie Zenatti, duet) in plaats van die van de plaat (Chimène Badi).
// 3. Deezer geeft bij `/album/{id}` hoogstens 25 nummers mee; "Entre nous" heeft er 43.
import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/lan/server.dart' show weigerVanBuiten;
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _nummer(int i, {String? artiest}) => {
      'id': 1000 + i,
      'title': 'Nummer $i',
      'duration': 180 + i,
      'track_position': i,
      if (artiest != null) 'artist': {'name': artiest},
    };

Map<String, dynamic> _plaat({required int nb, required int mee, String artiest = 'Chimène Badi'}) => {
      'id': 175653082,
      'title': 'Entre nous',
      'release_date': '2020-10-02',
      'nb_tracks': nb,
      'record_type': 'album',
      'artist': {'name': artiest},
      'tracks': {
        'data': [for (var i = 1; i <= mee; i++) _nummer(i, artiest: i == 6 ? 'Johnny Hallyday' : artiest)],
      },
    };

void main() {
  group('van buiten', () {
    test('Aanbevolen mag onderweg, zoals Ontdek', () {
      expect(weigerVanBuiten('/api/aanbevolen', 'GET'), isNull);
      expect(weigerVanBuiten('/api/ontdek', 'GET'), isNull);
    });

    test('koppelen en een speaker thuis starten blijven thuis', () {
      expect(weigerVanBuiten('/api/cast/play', 'POST'), isNotNull);
      expect(weigerVanBuiten('/api/sleutel/ruil', 'POST'), isNotNull);
    });
  });

  group('albumArtiestVoorPagina', () {
    test('een duet op de plaat van een ander: de artiest van de plaat', () {
      expect(albumArtiestVoorPagina('Julie Zenatti', 'Chimène Badi'), 'Chimène Badi');
    });

    test('dezelfde artiest, ook in een andere schrijfwijze: niets veranderen', () {
      expect(albumArtiestVoorPagina('Chimène Badi', 'Chimène Badi'), isNull);
      expect(albumArtiestVoorPagina('The Doors', 'Doors'), isNull);
      expect(albumArtiestVoorPagina('chimène badi', 'Chimène Badi'), isNull);
    });

    test('een verzamelaar of niets: de naam van het nummer blijft', () {
      expect(albumArtiestVoorPagina('Julie Zenatti', 'Various Artists'), isNull);
      expect(albumArtiestVoorPagina('Julie Zenatti', 'Verschillende artiesten'), isNull);
      expect(albumArtiestVoorPagina('Julie Zenatti', null), isNull);
      expect(albumArtiestVoorPagina('Julie Zenatti', '  '), isNull);
    });
  });

  group('albumTracks', () {
    test('43 nummers terwijl er 25 meekwamen: de volledige lijst, met de artiest van de plaat', () async {
      final gevraagd = <String>[];
      final c = CatalogService(haalVoorToets: (url) async {
        gevraagd.add(url);
        if (url.endsWith('/album/175653082')) return _plaat(nb: 43, mee: 25);
        if (url.contains('/album/175653082/tracks')) {
          return {
            'data': [for (var i = 1; i <= 43; i++) _nummer(i, artiest: i == 6 ? 'Johnny Hallyday' : 'Chimène Badi')],
            'total': 43,
          };
        }
        return null;
      });
      final (album, nummers) = await c.albumTracks(175653082);
      expect(album!.artiest, 'Chimène Badi');
      expect(album.trackCount, 43);
      expect(nummers, hasLength(43));
      expect(nummers.last.title, 'Nummer 43');
      expect(nummers.last.position, 43);
      expect(nummers[5].artist, 'Johnny Hallyday');
      expect(gevraagd, hasLength(2));
    });

    test('alles kwam al mee: geen tweede vraag', () async {
      final gevraagd = <String>[];
      final c = CatalogService(haalVoorToets: (url) async {
        gevraagd.add(url);
        return _plaat(nb: 12, mee: 12);
      });
      final (_, nummers) = await c.albumTracks(175653082);
      expect(nummers, hasLength(12));
      expect(gevraagd, hasLength(1));
    });

    test('meer dan honderd: de volgende pagina ook', () async {
      final c = CatalogService(haalVoorToets: (url) async {
        if (url.endsWith('/album/1')) return _plaat(nb: 130, mee: 25);
        if (url.endsWith('/album/1/tracks?limit=100')) {
          return {
            'data': [for (var i = 1; i <= 100; i++) _nummer(i, artiest: 'X')],
            'next': 'https://api.deezer.com/album/1/tracks?limit=100&index=100',
          };
        }
        if (url.endsWith('index=100')) {
          return {
            'data': [for (var i = 101; i <= 130; i++) _nummer(i, artiest: 'X')],
          };
        }
        return null;
      });
      final (_, nummers) = await c.albumTracks(1);
      expect(nummers, hasLength(130));
      expect(nummers.last.position, 130);
    });

    test('de volledige lijst lukt niet: de 25 die er waren blijven', () async {
      final c = CatalogService(haalVoorToets: (url) async {
        if (url.endsWith('/album/175653082')) return _plaat(nb: 43, mee: 25);
        return null;
      });
      final (_, nummers) = await c.albumTracks(175653082);
      expect(nummers, hasLength(25));
    });

    test('hoogstens kAlbumPaginas pagina\'s, ook als Deezer blijft doorverwijzen', () async {
      var paginas = 0;
      final c = CatalogService(haalVoorToets: (url) async {
        if (url.endsWith('/album/2')) return _plaat(nb: 5000, mee: 25);
        paginas++;
        return {
          'data': [for (var i = 1; i <= 100; i++) _nummer(paginas * 100 + i, artiest: 'X')],
          'next': 'https://api.deezer.com/album/2/tracks?limit=100&index=${paginas * 100}',
        };
      });
      final (_, nummers) = await c.albumTracks(2);
      expect(paginas, CatalogService.kAlbumPaginas);
      expect(nummers, hasLength(CatalogService.kAlbumPaginas * 100));
    });
  });

  group('de bedrading op de albumpagina', () {
    final bron = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final begin = bron.indexOf('class _AlbumBrowsePageState');
    final pagina = bron.substring(begin, bron.indexOf('\nclass ', begin + 10));

    test('de artiest van de plaat komt uit Deezer en staat overal waar de pagina een naam gebruikt', () {
      expect(pagina, contains('final eigen = albumArtiestVoorPagina(widget.artistName, album?.artiest);'));
      expect(pagina, contains('_albumArtiest = eigen;'));
      expect(pagina, contains('String get _artiest => _albumArtiest ?? widget.artistName;'));
      expect(RegExp(r'widget\.artistName').allMatches(pagina).length, 2,
          reason: 'alleen in de getter en bij de vraag aan Deezer; de rest leest _artiest');
    });

    test('bij een plaat uit Deezer zoekt Soulseek pas als de artiest bekend is', () {
      expect(pagina, contains('if (widget.album.ref.source != CatalogSource.deezer) {'));
      final laad = pagina.substring(pagina.indexOf('Future<void> _load() async {'));
      final na = laad.indexOf('_albumArtiest = eigen;');
      final zoek = laad.indexOf('unawaited(_preloadSoulseek());');
      expect(na, greaterThan(0));
      expect(zoek, greaterThan(na));
    });
  });

  test('deezerAlbumNummers: een nummer zonder eigen artiest krijgt die van de plaat', () {
    final n = deezerAlbumNummers([
      _nummer(1),
      _nummer(2, artiest: 'Johnny Hallyday'),
      'rommel',
    ], 'Chimène Badi');
    expect([for (final t in n) t.artist], ['Chimène Badi', 'Johnny Hallyday']);
  });
}
