/// Het genre van een plaat is wat de MEESTE nummers dragen, niet wat het eerste bestand zegt.
///
/// **Waarom dit bestaat.** `Album.genre` gaf het eerste niet-lege genre terug, en daarmee bepaalde
/// één bestand de hele kop. Gezien op 09-09-2026: *Jane Birkin - Serge Gainsbourg* (1969, chanson)
/// stond als "Pop", en zodra "Je T'Aime… Moi Non Plus" naar zijn eigen uitgave verhuisde sprong de
/// kop naar "Alternative And Punk" — het genre van wat toevallig het nieuwe eerste bestand was. De
/// plaat veranderde niet, alleen de volgorde.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart';

Track _t(String titel, {String? genre, int no = 0}) => Track(
      path: r'D:\muziek\x\' + '$no - $titel.flac',
      title: titel,
      artist: 'Serge Gainsbourg & Jane Birkin',
      album: 'Jane Birkin - Serge Gainsbourg',
      trackNo: no,
      genre: genre,
    );

Album _a(List<Track> nummers) =>
    Album('Jane Birkin - Serge Gainsbourg', 'Serge Gainsbourg & Jane Birkin', nummers);

void main() {
  test('de meerderheid beslist, niet het eerste bestand', () {
    final a = _a([
      _t('La Chanson De Slogan', genre: 'Alternative And Punk', no: 1),
      _t('69 Année Érotique', genre: 'Chanson', no: 2),
      _t('Les Sucettes', genre: 'Chanson', no: 3),
    ]);
    expect(a.genre, 'Chanson');
  });

  test('een nummer dat weggaat verandert de kop niet meer', () {
    // Precies het gemeten geval: het vertrek van één nummer liet de kop omslaan.
    final alle = [
      _t("Je T'Aime… Moi Non Plus", genre: 'Pop', no: 1),
      _t('La Chanson De Slogan', genre: 'Alternative And Punk', no: 2),
      _t('69 Année Érotique', genre: 'Chanson', no: 3),
      _t('Les Sucettes', genre: 'Chanson', no: 4),
    ];
    expect(_a(alle).genre, 'Chanson');
    expect(_a(alle.sublist(1)).genre, 'Chanson', reason: 'zonder het eerste nummer hetzelfde');
  });

  test('hoofdletters maken geen tweede genre', () {
    // Rippers schrijven "Pop", "pop" en "POP" door elkaar; dat is één genre, niet drie.
    final a = _a([
      _t('a', genre: 'Chanson', no: 1),
      _t('b', genre: 'pop', no: 2),
      _t('c', genre: 'POP', no: 3),
      _t('d', genre: 'Pop', no: 4),
    ]);
    expect(a.genre, 'pop', reason: 'de eerst geziene schrijfwijze van de winnaar');
  });

  test('bij gelijkspel wint wie het eerst voorkomt', () {
    final a = _a([_t('a', genre: 'Chanson', no: 1), _t('b', genre: 'Pop', no: 2)]);
    expect(a.genre, 'Chanson', reason: 'anders hangt de uitkomst van de sorteervolgorde af');
  });

  test('lege en ontbrekende genres tellen niet mee', () {
    final a = _a([
      _t('a', no: 1),
      _t('b', genre: '   ', no: 2),
      _t('c', genre: 'Chanson', no: 3),
    ]);
    expect(a.genre, 'Chanson');
    expect(_a([_t('a', no: 1), _t('b', genre: '', no: 2)]).genre, isNull);
  });
}
