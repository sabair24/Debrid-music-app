/// De wachtrij bijwerken zonder hem stuk te maken.
///
/// Er zijn TWEE lijsten: het origineel zoals aangeleverd, en de speelvolgorde met shuffle erop.
/// `toggleShuffle` bouwt die tweede opnieuw op uit de eerste. Wat alleen in de speelvolgorde staat is
/// dus weg zodra iemand shuffle aantikt — geen foutmelding, geen crash, gewoon verdwenen. Dat is de
/// val in dit hele onderdeel, en de eerste test hieronder gaat er precies over.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';

Track t(String naam) => Track(
      path: 'D:\\m\\$naam.flac',
      title: naam,
      artist: 'A',
      album: 'Alb',
      trackNo: 1,
      duration: const Duration(seconds: 200),
      isFlac: true,
    );

Wachtrij rij(List<String> namen, int index) {
  final lijst = [for (final n in namen) t(n)];
  return (origineel: lijst, volgorde: List.of(lijst), index: index);
}

List<String> namen(List<Track> l) => [for (final x in l) x.title];

void main() {
  group('erbij zetten', () {
    test('hierna spelen komt direct achter het lopende nummer, in BEIDE lijsten', () {
      final w = voegInWachtrij(rij(['a', 'b', 'c'], 1), [t('x')], hierna: true);
      expect(namen(w.volgorde), ['a', 'b', 'x', 'c']);
      expect(namen(w.origineel), ['a', 'b', 'x', 'c'],
          reason: 'alleen in de speelvolgorde zetten is precies wat shuffle later weggooit');
      expect(w.index, 1, reason: 'het lopende nummer blijft waar het is');
    });

    test('en overleeft daarom een druk op shuffle', () {
      // De echte proef: na het toevoegen de speelvolgorde weggooien en opnieuw uit het origineel
      // bouwen, precies zoals toggleShuffle doet. Het toegevoegde nummer hoort er dan nog te zijn.
      final w = voegInWachtrij(rij(['a', 'b', 'c'], 1), [t('x')], hierna: true);
      final opnieuw = ordenVoor(w.origineel, w.volgorde[w.index], shuffle: true);
      expect(namen(opnieuw.order), contains('x'));
      expect(opnieuw.order.length, 4);
    });

    test('achteraan zetten hangt het aan het eind van allebei', () {
      final w = voegInWachtrij(rij(['a', 'b'], 0), [t('x'), t('y')], hierna: false);
      expect(namen(w.volgorde), ['a', 'b', 'x', 'y']);
      expect(namen(w.origineel), ['a', 'b', 'x', 'y']);
      expect(w.index, 0);
    });

    test('bij shuffle gaat het in het origineel achter hetzelfde NUMMER, niet achter dezelfde index',
        () {
      // Dit is waarom er niet op index wordt gerekend. De twee lijsten staan in een andere volgorde;
      // index 1 wijst in beide op een ander nummer.
      final geschud = (
        origineel: [t('a'), t('b'), t('c')],
        volgorde: [t('c'), t('a'), t('b')],
        index: 0, // 'c' klinkt
      );
      final w = voegInWachtrij(geschud, [t('x')], hierna: true);
      expect(namen(w.volgorde), ['c', 'x', 'a', 'b']);
      expect(namen(w.origineel), ['a', 'b', 'c', 'x'], reason: 'in het origineel hoort x achter c');
    });

    test('een lege toevoeging verandert niets', () {
      final voor = rij(['a'], 0);
      final na = voegInWachtrij(voor, [], hierna: true);
      expect(identical(na.volgorde, voor.volgorde), isTrue);
    });
  });

  group('eruit halen', () {
    test('haalt het uit beide lijsten', () {
      final w = haalUitWachtrijLijst(rij(['a', 'b', 'c'], 0), 2);
      expect(namen(w.volgorde), ['a', 'b']);
      expect(namen(w.origineel), ['a', 'b']);
    });

    test('iets vóór het lopende nummer weghalen schuift de index mee', () {
      final w = haalUitWachtrijLijst(rij(['a', 'b', 'c'], 2), 0);
      expect(namen(w.volgorde), ['b', 'c']);
      expect(w.index, 1, reason: 'c moet nog steeds het lopende nummer zijn');
      expect(w.volgorde[w.index].title, 'c');
    });

    test('het lopende nummer kan er NIET uit', () {
      // Dat is "stop" of "volgende", en die knoppen bestaan al. Het hier stilzwijgend als iets
      // anders uitvoeren maakt van één druk een onvoorspelbare handeling.
      final voor = rij(['a', 'b', 'c'], 1);
      final na = haalUitWachtrijLijst(voor, 1);
      expect(identical(na.volgorde, voor.volgorde), isTrue);
    });

    test('buiten de lijst wijzen doet niets', () {
      final voor = rij(['a'], 0);
      expect(identical(haalUitWachtrijLijst(voor, -1).volgorde, voor.volgorde), isTrue);
      expect(identical(haalUitWachtrijLijst(voor, 9).volgorde, voor.volgorde), isTrue);
    });

    test('hetzelfde nummer twee keer in de rij: precies die ene gaat eruit', () {
      // Twee keer hetzelfde nummer in een wachtrij mag. Op naam zoeken zou de verkeerde pakken.
      final zelfde = t('a');
      final w = (origineel: [zelfde, t('b'), zelfde], volgorde: [zelfde, t('b'), zelfde], index: 0);
      final na = haalUitWachtrijLijst(w, 2);
      expect(namen(na.volgorde), ['a', 'b']);
      expect(na.origineel.length, 2);
    });
  });

  group('verslepen', () {
    test('bij shuffle uit verhuist het in beide lijsten', () {
      final w = verplaatsInWachtrijLijst(rij(['a', 'b', 'c'], 0), 2, 0, shuffle: false);
      expect(namen(w.volgorde), ['c', 'a', 'b']);
      expect(namen(w.origineel), ['c', 'a', 'b']);
    });

    test('bij shuffle aan blijft het origineel de albumvolgorde', () {
      final geschud = (
        origineel: [t('a'), t('b'), t('c')],
        volgorde: [t('b'), t('c'), t('a')],
        index: 0,
      );
      final w = verplaatsInWachtrijLijst(geschud, 2, 0, shuffle: true);
      expect(namen(w.volgorde), ['a', 'b', 'c']);
      expect(namen(w.origineel), ['a', 'b', 'c'], reason: 'ongewijzigd — dat is de albumvolgorde');
    });

    test('het lopende nummer verslepen neemt de index mee', () {
      final w = verplaatsInWachtrijLijst(rij(['a', 'b', 'c'], 0), 0, 2, shuffle: false);
      expect(namen(w.volgorde), ['b', 'c', 'a']);
      expect(w.index, 2);
      expect(w.volgorde[w.index].title, 'a', reason: 'er mag niets anders gaan klinken');
    });

    test('eroverheen slepen laat het lopende nummer klinken', () {
      // Van vóór naar ná het lopende nummer: de index moet één omlaag, anders wijst hij ineens naar
      // een ander nummer terwijl er niets is heropend.
      var w = verplaatsInWachtrijLijst(rij(['a', 'b', 'c'], 1), 0, 2, shuffle: false);
      expect(w.volgorde[w.index].title, 'b');
      // En andersom.
      w = verplaatsInWachtrijLijst(rij(['a', 'b', 'c'], 1), 2, 0, shuffle: false);
      expect(w.volgorde[w.index].title, 'b');
    });

    test('naar dezelfde plek of buiten de lijst doet niets', () {
      final voor = rij(['a', 'b'], 0);
      expect(identical(verplaatsInWachtrijLijst(voor, 1, 1, shuffle: false).volgorde, voor.volgorde),
          isTrue);
      expect(identical(verplaatsInWachtrijLijst(voor, 5, 0, shuffle: false).volgorde, voor.volgorde),
          isTrue);
    });
  });
}
