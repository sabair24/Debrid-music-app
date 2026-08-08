/// De albumbibliotheek als rijen, op een televisie.
///
/// Een raster kan op 540 punten hoog nooit meer dan ruim één rij tonen, dus daar worden het rijen.
/// Een rij zonder naam is alleen een willekeurige snee, dus elke rij krijgt een kop — en die kop
/// moet volgen wat de sortering doet, anders staat er iets dat niet klopt.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';

Album _album(String artist, String title, {int? year, int addedMs = 0}) => Album(
      title,
      artist,
      [
        Track(
          path: '/m/$artist/$title/01.flac',
          title: title,
          artist: artist,
          album: title,
          trackNo: 1,
          isFlac: true,
          year: year,
          addedMs: addedMs,
        )
      ],
    );

void main() {
  group('de kop van een rij zegt waarom die platen bij elkaar staan', () {
    test('op artiest: één rij per beginletter, in de volgorde die binnenkwam', () {
      final rows = groupAlbumsForTv([
        _album('ABBA', 'Arrival'),
        _album('Adele', '21'),
        _album('Blur', 'Parklife'),
      ], AlbumSort.artiest);

      expect(rows.map((r) => r.$1).toList(), ['A', 'B']);
      expect(rows.first.$2.length, 2, reason: 'ABBA en Adele horen in dezelfde rij');
      expect(rows.last.$2.single.artist, 'Blur');
    });

    test('op titel gaat het over de titel, niet over de artiest', () {
      final rows = groupAlbumsForTv([
        _album('Blur', 'Arrival'),
        _album('ABBA', 'Zeven'),
      ], AlbumSort.titel);

      expect(rows.map((r) => r.$1).toList(), ['A', 'Z']);
    });

    test('cijfers en tekens staan onder #, zoals in een platenkast', () {
      final rows = groupAlbumsForTv([
        _album('10cc', 'Sheet Music'),
        _album('!!!', 'Myth Takes'),
        _album('Adele', '21'),
      ], AlbumSort.artiest);

      expect(rows.first.$1, '#');
      expect(rows.first.$2.length, 2);
      expect(rows.last.$1, 'A');
    });

    test('op jaar zijn het decennia, en een onbekend jaar valt niet in een verkeerd decennium', () {
      final rows = groupAlbumsForTv([
        _album('A', 'Nieuw', year: 2024),
        _album('B', 'Ook nieuw', year: 2021),
        _album('C', 'Ouder', year: 1998),
        _album('D', 'Geen jaar'),
      ], AlbumSort.jaarNieuw);

      expect(rows.map((r) => r.$1).toList(), ["2020's", "1990's", 'Jaar onbekend']);
      expect(rows.first.$2.length, 2);
    });

    test('een lege lijst geeft geen lege rij met een kop erboven', () {
      expect(groupAlbumsForTv(const [], AlbumSort.artiest), isEmpty);
    });

    test('elk album komt in precies één rij terecht', () {
      // De echte invariant: groeperen mag niets kwijtraken en niets verdubbelen. Een fout in de
      // sleutel zou anders stilletjes een deel van je bibliotheek onzichtbaar maken.
      final albums = [
        for (var i = 0; i < 40; i++) _album(String.fromCharCode(65 + i % 7), 'Plaat $i', year: 1970 + i),
      ];
      for (final sort in AlbumSort.values) {
        final rows = groupAlbumsForTv(albums, sort);
        final terug = [for (final r in rows) ...r.$2];
        expect(terug.length, albums.length, reason: '$sort raakte albums kwijt of verdubbelde ze');
        expect(terug.toSet().length, albums.length, reason: '$sort zette een album in twee rijen');
      }
    });
  });
}
