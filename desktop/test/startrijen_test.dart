/// De regels waarmee de startpagina zijn rijen vult.
///
/// **Waarom deze toetsen bestaan.** Saber meldde op 02-09-2026 drie dingen over zijn startpagina:
/// te weinig variatie, "Top van dit moment" gaat niet over zijn muziek, en Dr. Alban — een artiest
/// uit de jaren 90 — stond onder "Nieuw van jouw artiesten". Elk van die klachten is hier een
/// getal geworden, en de meting die eronder ligt staat in de toets zelf.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/startrijen.dart';

CatalogAlbumHit hit(String artiest, String titel, String datum, {String soort = 'album'}) =>
    CatalogAlbumHit(CatalogAlbum(0, titel, null, datum, 0, soort), artiest);

void main() {
  group('maxPerArtiest', () {
    test('DE KERN: één artiest kan de rij niet meer overnemen', () {
      // Precies de gemeten schermafdruk: 18 tegels, waarvan 17 van vier artiesten.
      final rij = [
        for (var i = 0; i < 5; i++) hit('Timmy Trumpet', 'T$i', '2025-01-01'),
        for (var i = 0; i < 4; i++) hit('Slimane', 'S$i', '2025-01-01'),
        for (var i = 0; i < 4; i++) hit('Shakira', 'Sh$i', '2025-01-01'),
        for (var i = 0; i < 4; i++) hit('Dr. Alban', 'A$i', '2025-01-01'),
        hit('Alpha Blondy', 'Rise', '2025-01-01'),
      ];
      final uit = maxPerArtiest(rij, (h) => h.artist, 1);
      expect(uit, hasLength(5), reason: 'vijf artiesten, dus vijf tegels');
      expect(uit.map((h) => h.artist).toSet(), hasLength(5));
    });

    test('de volgorde blijft staan', () {
      // Bij een hitlijst IS de volgorde de hitlijst. Wie hier schudt gooit dat weg.
      final rij = [
        hit('A', 'een', '2025-01-01'),
        hit('B', 'twee', '2025-01-01'),
        hit('A', 'drie', '2025-01-01'),
        hit('C', 'vier', '2025-01-01'),
      ];
      expect(maxPerArtiest(rij, (h) => h.artist, 1).map((h) => h.album.title),
          ['een', 'twee', 'vier']);
    });

    test('"Beyonce" en "Beyoncé" tellen als één artiest', () {
      // Zonder accentvouwing haalt dezelfde persoon twee keer het rantsoen.
      final rij = [hit('Beyoncé', 'een', '2025-01-01'), hit('Beyonce', 'twee', '2025-01-01')];
      expect(maxPerArtiest(rij, (h) => h.artist, 1), hasLength(1));
    });

    test('een naamloze regel krijgt geen eigen emmer', () {
      final rij = [hit('', 'een', '2025-01-01'), hit('', 'twee', '2025-01-01')];
      expect(maxPerArtiest(rij, (h) => h.artist, 2), isEmpty);
    });

    test('max 0 levert niets, en dat is geen uitzondering', () {
      expect(maxPerArtiest([hit('A', 'een', '2025-01-01')], (h) => h.artist, 0), isEmpty);
    });
  });

  group('zonderHerlevering', () {
    test('DE KERN: de catalogusdump van Dr. Alban valt weg', () {
      // Letterlijk wat Deezer op 02-09-2026 teruggaf voor /artist/999/albums.
      final rij = [
        hit('Dr. Alban', "It's My Life", '2026-01-28'),
        hit('Dr. Alban', "Look Who's Talking", '2026-01-28'),
        hit('Dr. Alban', 'One Love', '2026-01-28'),
        hit('Dr. Alban', "Look Who's Talking", '2026-01-28', soort: 'ep'),
        hit('Dr. Alban', "It's My Life (Rmx)", '2026-01-28', soort: 'single'),
        hit('Dr. Alban', 'Sing Hallelujah!', '2026-01-28', soort: 'ep'),
      ];
      expect(zonderHerlevering(rij), isEmpty,
          reason: 'zes uitgaven op één dag is een herlevering, geen nieuwe muziek');
    });

    test('en een échte nieuwe plaat blijft staan', () {
      // Backstreet Boys: één regel op 2025-11-07, één op 2025-07-11. Zo ziet nieuw eruit.
      final rij = [
        hit('Backstreet Boys', 'Millennium 2.0', '2025-11-07'),
        hit('Backstreet Boys', 'Iets anders', '2025-07-11'),
      ];
      expect(zonderHerlevering(rij), hasLength(2));
    });

    test('twee op één dag is geen dump', () {
      // Beyoncé zette op 2024-02-09 twee singles uit. Drempel drie, juist hierom.
      final rij = [
        hit('Beyoncé', 'Texas Hold Em', '2024-02-09', soort: 'single'),
        hit('Beyoncé', '16 Carriages', '2024-02-09', soort: 'single'),
      ];
      expect(zonderHerlevering(rij), hasLength(2));
    });

    test('de dump van de ene artiest raakt de andere niet', () {
      final rij = [
        for (var i = 0; i < 4; i++) hit('Dr. Alban', 'A$i', '2026-01-28'),
        hit('Adele', '30', '2026-01-28'),
      ];
      expect(zonderHerlevering(rij).map((h) => h.artist), ['Adele']);
    });

    test('een regel zonder datum blijft gewoon staan', () {
      // Geen datum is geen bewijs van een dump; wegfilteren zou muziek kosten om niets.
      expect(zonderHerlevering([hit('A', 'een', '')]), hasLength(1));
    });
  });

  group('nieuwVanJouwArtiesten — de hele rij in één regel', () {
    test('DE KERN: precies wat Saber zag, en wat er overblijft', () {
      final ruw = [
        // De dump van Dr. Alban: draagt 2026 als datum, dus een jaarfilter alleen laat hem door.
        hit('Dr. Alban', "It's My Life", '2026-01-28'),
        hit('Dr. Alban', "Look Who's Talking", '2026-01-28'),
        hit('Dr. Alban', 'One Love', '2026-01-28'),
        hit('Dr. Alban', 'Sing Hallelujah!', '2026-01-28', soort: 'ep'),
        // Vier van dezelfde artiest: hoort er één te worden.
        for (var i = 0; i < 4; i++) hit('Timmy Trumpet', 'T$i', '2026-02-0${i + 1}'),
        // Echt nieuw, en van verschillende mensen.
        hit('Shakira', 'Las Mujeres', '2025-11-07'),
        hit('Slimane', 'Essentiels', '2026-03-14'),
        // Te oud.
        hit('Alpha Blondy', 'Rise', '2020-05-01'),
        // Een single hoort niet in een rij albumtegels.
        hit('Stromae', 'Iets', '2026-01-05', soort: 'single'),
      ];
      final uit = nieuwVanJouwArtiesten(ruw, jaren: {2026, 2025});
      expect(uit.map((h) => h.artist), ['Timmy Trumpet', 'Shakira', 'Slimane']);
    });

    test('de herleveringsregel draait vóór het singlefilter', () {
      // Dit is de val: haal je eerst de singles en ep's eruit, dan telt Dr. Alban nog maar twee
      // albums op die dag en glipt de hele dump er alsnog door.
      final ruw = [
        hit('Dr. Alban', 'A', '2026-01-28'),
        hit('Dr. Alban', 'B', '2026-01-28'),
        hit('Dr. Alban', 'C', '2026-01-28', soort: 'single'),
      ];
      expect(nieuwVanJouwArtiesten(ruw, jaren: {2026}), isEmpty);
    });

    test('wat je al hebt is niet nieuw', () {
      final ruw = [
        hit('Adele', '30', '2026-01-05'),
        hit('Sia', 'Iets nieuws', '2026-01-05'),
      ];
      final uit = nieuwVanJouwArtiesten(ruw,
          jaren: {2026}, alInBezit: {bezitssleutel('Adele', '30')});
      expect(uit.map((h) => h.artist), ['Sia']);
    });
  });

  group('uitJaren', () {
    test('dit jaar en vorig jaar erdoor, de rest niet', () {
      final rij = [
        hit('A', 'nu', '2026-03-01'),
        hit('B', 'vorig', '2025-11-07'),
        hit('C', 'oud', '1995-06-30'),
      ];
      expect(uitJaren(rij, {2026, 2025}).map((h) => h.album.title), ['nu', 'vorig']);
    });

    test('een onleesbare datum telt niet mee', () {
      expect(uitJaren([hit('A', 'x', '')], {2026}), isEmpty);
    });
  });
}
