/// Dubbel gecodeerde tekst rechtzetten, en vooral: alles ANDERS met rust laten.
///
/// De helft van deze tests gaat over wat er NIET mag veranderen. Een reparatie die een echte Franse
/// titel verbouwt is erger dan de verminking zelf, want die valt niet op.
library;

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/mojibake.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => mojibakeHersteld = 0);

  group('herstelt wat gemeten is', () {
    test('de apostrof van Nobody’s Business', () {
      expect(unmojibake('Nobodyâ€™s Business'), 'Nobody’s Business');
      expect(mojibakeHersteld, 1);
    });

    test('accenten: MÃ¡s es amar en Iâ€™m Your Man', () {
      expect(unmojibake('MÃ¡s es amar'), 'Más es amar');
      expect(unmojibake('Iâ€™m Your Man'), 'I’m Your Man');
    });

    test('een sterretje uit COWBOY CARTER', () {
      expect(unmojibake('SWEET â˜… HONEY'), 'SWEET ★ HONEY');
    });

    test('meerdere in één titel', () {
      expect(unmojibake('Pour que tu mâ€™aimes encore â€” live'),
          'Pour que tu m’aimes encore — live');
    });
  });

  group('aangesloten op de feiten die van schijf komen', () {
    // De functie alleen testen was niet genoeg: de eerste versie zat op de tracktitel en niet op de
    // uitgaveregel van bonusnummers. Op schijf zag ik toen 124 verminkte titels verdwijnen en nog
    // tien "Â·" overblijven, allemaal in dat ene veld. Vandaar een test op de BEDRADING.
    test('titels én de uitgaveregel van bonusnummers', () {
      final f = AlbumFacts.fromJson({
        'uid': 'u',
        'schema': kAlbumFactsSchema,
        'hash': 'h',
        'tracks': [
          {'p': '10', 't': 'Nobodyâ€™s Business', 's': 216},
        ],
        'bonus': [
          {'p': '3', 't': 'MÃ¡s es amar', 's': 240, 'e': 'CD-R Â· US Â· 2022'},
        ],
      });
      expect(f!.tracklist.single.title, 'Nobody’s Business');
      expect(f.bonus.single.track.title, 'Más es amar');
      expect(f.bonus.single.edition, 'CD-R · US · 2022');
    });

    test('en een plaat die al goed staat komt er ongewijzigd door', () {
      final f = AlbumFacts.fromJson({
        'uid': 'u',
        'schema': kAlbumFactsSchema,
        'hash': 'h',
        'tracks': [
          {'p': '1', 't': 'Ce rêve bleu', 's': 200},
        ],
        'bonus': [
          {'p': '2', 't': 'TEXAS HOLD ’EM', 's': 233, 'e': 'CD · US · 2024'},
        ],
      });
      expect(f!.tracklist.single.title, 'Ce rêve bleu');
      expect(f.bonus.single.edition, 'CD · US · 2024');
      expect(mojibakeHersteld, 0, reason: 'niets te repareren, dus de teller blijft staan');
    });
  });

  group('laat met rust wat heel is', () {
    test('tekst die al goed staat', () {
      for (final s in ['Nobody’s Business', 'Más es amar', 'TEXAS HOLD ’EM', 'SWEET ★ HONEY']) {
        expect(unmojibake(s), s, reason: '"$s" hoort onaangeroerd te blijven');
      }
      expect(mojibakeHersteld, 0);
    });

    test('gewone accentletters: één losse byte is geen UTF-8', () {
      for (final s in ['café', 'Mieux qu\'ici-bas', 'Ce rêve bleu', 'Björk', 'Sinéad O\'Connor']) {
        expect(unmojibake(s), s, reason: '"$s" hoort onaangeroerd te blijven');
      }
      expect(mojibakeHersteld, 0);
    });

    test('kale ascii komt er ongewijzigd door en kost geen werk', () {
      expect(unmojibake('Pump Up the Jam (Terry Dome Mix)'), 'Pump Up the Jam (Terry Dome Mix)');
      expect(unmojibake(''), '');
      expect(mojibakeHersteld, 0);
    });

    test('een teken buiten cp1252 sluit de reparatie meteen uit', () {
      // Cyrillisch, Japans, emoji: die kunnen nooit uit een cp1252-misser komen, dus er valt niets
      // terug te draaien. О'ПІВНОЧІ staat echt in de bibliotheek.
      for (final s in ['О\'ПІВНОЧІ', '君の名は', 'Loud 🔊']) {
        expect(unmojibake(s), s);
      }
    });

    test('een reeks die korter noch langer wordt, blijft', () {
      // De lengte-eis is de laatste vangrail: dubbele codering maakt tekst altijd langer, dus iets
      // wat niet krimpt was geen dubbele codering.
      expect(unmojibake('Ãa'), 'Ãa');
    });
  });
}
