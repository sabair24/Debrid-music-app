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

  group('deezerGenre', () {
    test('DE VAL: "Hardcore" is hier techno en geen metal', () {
      // 85 nummers met deze tag in Sabers bibliotheek, naast 129 Discogs-stijlen "Electronic",
      // 21 "Euro House" en 21 "Eurodance". Zonder deze regel wordt zijn op één na grootste tag een
      // metal-hitlijst.
      expect(deezerGenre('Hardcore'), Genre.dance);
      expect(deezerGenre('Gabber'), Genre.dance);
      // En echte metal blijft gewoon metal.
      expect(deezerGenre('Thrash Metal'), Genre.metal);
    });

    test('de tags die er in deze bibliotheek werkelijk staan', () {
      expect(deezerGenre('Pop'), Genre.pop);
      expect(deezerGenre('Contemporary R&B'), Genre.rnb);
      expect(deezerGenre('Eurodance'), Genre.dance);
      expect(deezerGenre('Euro House'), Genre.dance);
      expect(deezerGenre('Electronic'), Genre.electro);
      expect(deezerGenre('Synth-pop'), Genre.electro);
      expect(deezerGenre('Variété française'), Genre.chanson);
      expect(deezerGenre('Funk / Soul'), Genre.soulFunk);
      expect(deezerGenre('Reggae'), Genre.reggae);
      expect(deezerGenre('Pop Rock'), Genre.rock);
    });

    test('het meest specifieke wint van het bredere', () {
      // "Dance-pop" bevat zowel "dance" als "pop"; "Contemporary R&B" bevat "r&b" én niets anders
      // dat eerder komt. Zonder een vaste volgorde is de uitkomst een kwestie van geluk.
      expect(deezerGenre('Dance-pop'), Genre.dance);
      expect(deezerGenre('Soul / Funk / R&B'), Genre.rnb);
    });

    test('onbekend en leeg leveren niets', () {
      expect(deezerGenre(''), isNull);
      expect(deezerGenre('Onbekend'), isNull);
    });
  });

  group('genreProfiel', () {
    test('DE KERN: het profiel van deze bibliotheek', () {
      // De werkelijk gemeten telling: Pop 324, Hardcore 85, Electronic 55, Rock 38, R&B 36,
      // Contemporary R&B 25, Variété française 24, Dance 22, Eurodance 21.
      final tags = [
        for (var i = 0; i < 324; i++) 'Pop',
        for (var i = 0; i < 85; i++) 'Hardcore',
        for (var i = 0; i < 55; i++) 'Electronic',
        for (var i = 0; i < 38; i++) 'Rock',
        for (var i = 0; i < 36; i++) 'R&B',
        for (var i = 0; i < 25; i++) 'Contemporary R&B',
        for (var i = 0; i < 24; i++) 'Variété française',
        for (var i = 0; i < 22; i++) 'Dance',
        for (var i = 0; i < 21; i++) 'Eurodance',
      ];
      final profiel = genreProfiel(tags);
      expect(profiel.first, Genre.pop, reason: 'pop is met afstand het grootst');
      expect(profiel, contains(Genre.dance));
      expect(profiel, contains(Genre.rnb));
      expect(profiel, contains(Genre.chanson));
      expect(profiel, isNot(contains(Genre.metal)),
          reason: 'er staat geen metal in deze bibliotheek, hoe vaak "Hardcore" er ook staat');
    });

    test('één raar album kaapt de rij niet', () {
      final tags = [for (var i = 0; i < 30; i++) 'Pop', 'Death Metal'];
      expect(genreProfiel(tags), [Genre.pop]);
    });

    test('een lege bibliotheek geeft een leeg profiel, geen uitzondering', () {
      expect(genreProfiel(const <String?>[]), isEmpty);
      expect(genreProfiel([null, '', 'Onbekend']), isEmpty);
    });
  });

  group('meestGespeeldeArtiest', () {
    final nu = DateTime(2026, 9, 2).millisecondsSinceEpoch;
    int dagenGeleden(int d) => nu - Duration(days: d).inMilliseconds;

    test('DE KERN: minder-maar-recent wint van vaker-maar-lang-geleden', () {
      // Dit is de hele reden dat er recentheid in zit. Wie alleen op de teller kijkt, blijft
      // eeuwig de artiest voorstellen waar je een half jaar geleden een weekend aan verslingerd
      // was — en dat is niet waar je nu naar luistert.
      final beurten = <Beurt>[
        (artiest: 'Oud Favoriet', aantal: 20, laatstMs: dagenGeleden(200)),
        (artiest: 'Nu Bezig', aantal: 5, laatstMs: dagenGeleden(1)),
      ];
      expect(meestGespeeldeArtiest(beurten, nuMs: nu), 'Nu Bezig');
    });

    test('maar één keer ooit verslaat vijf keer deze week niet', () {
      final beurten = <Beurt>[
        (artiest: 'Vijf Keer', aantal: 5, laatstMs: dagenGeleden(3)),
        (artiest: 'Eén Keer', aantal: 1, laatstMs: dagenGeleden(0)),
      ];
      expect(meestGespeeldeArtiest(beurten, nuMs: nu), 'Vijf Keer');
    });

    test('de beurten van één artiest tellen bij elkaar op', () {
      // Elk nummer levert zijn eigen beurt aan; de rij gaat over de ARTIEST.
      final beurten = <Beurt>[
        (artiest: 'Backstreet Boys', aantal: 2, laatstMs: dagenGeleden(2)),
        (artiest: 'Backstreet Boys', aantal: 2, laatstMs: dagenGeleden(2)),
        (artiest: 'Adele', aantal: 3, laatstMs: dagenGeleden(2)),
      ];
      expect(meestGespeeldeArtiest(beurten, nuMs: nu), 'Backstreet Boys');
    });

    test('overslaan geeft de volgende, zodat de rij niet altijd dezelfde naam noemt', () {
      final beurten = <Beurt>[
        (artiest: 'Eerste', aantal: 10, laatstMs: dagenGeleden(1)),
        (artiest: 'Tweede', aantal: 5, laatstMs: dagenGeleden(1)),
      ];
      expect(meestGespeeldeArtiest(beurten, nuMs: nu, overslaan: 1), 'Tweede');
      expect(meestGespeeldeArtiest(beurten, nuMs: nu, overslaan: 2), 'Eerste');
    });

    test('zonder beurten is er geen naam', () {
      expect(meestGespeeldeArtiest(const <Beurt>[], nuMs: nu), isNull);
      expect(
          meestGespeeldeArtiest(
              [(artiest: 'X', aantal: 0, laatstMs: dagenGeleden(1))], nuMs: nu),
          isNull);
    });

    test('een klok die vooruit staat is "zojuist", niet "over een jaar"', () {
      final beurten = <Beurt>[
        (artiest: 'Toekomst', aantal: 1, laatstMs: nu + Duration(days: 30).inMilliseconds),
        (artiest: 'Verleden', aantal: 1, laatstMs: dagenGeleden(300)),
      ];
      expect(meestGespeeldeArtiest(beurten, nuMs: nu), 'Toekomst');
    });
  });

  group('zwaartepuntDecennium', () {
    /// De werkelijk gemeten verdeling van deze bibliotheek.
    List<int?> deVerdeling() => [
          for (var i = 0; i < 6; i++) 1965,
          for (var i = 0; i < 17; i++) 1975,
          for (var i = 0; i < 70; i++) 1985,
          for (var i = 0; i < 448; i++) 1995,
          for (var i = 0; i < 374; i++) 2005,
          for (var i = 0; i < 203; i++) 2015,
          for (var i = 0; i < 92; i++) 2022,
        ];

    test('DE KERN: de jaren 90, met 448 nummers', () {
      expect(zwaartepuntDecennium(deVerdeling()), 1990);
    });

    test('en om de beurt een ander decennium', () {
      // Anders staat er elke keer dezelfde rij, en dan is het een stempel.
      expect(zwaartepuntDecennium(deVerdeling(), overslaan: 1), 2000);
      expect(zwaartepuntDecennium(deVerdeling(), overslaan: 2), 2010);
      // En hij loopt rond in plaats van buiten de lijst te vallen.
      expect(zwaartepuntDecennium(deVerdeling(), overslaan: 99), isNotNull);
    });

    test('te weinig muziek is geen bewering waard', () {
      expect(zwaartepuntDecennium([1995, 1996, 1997]), isNull);
      expect(zwaartepuntDecennium(const <int?>[]), isNull);
    });

    test('onmogelijke jaartallen tellen niet mee', () {
      // Een tag met 0 of 9999 erin komt in elke bibliotheek voor.
      final jaren = <int?>[0, 9999, null, for (var i = 0; i < 25; i++) 1995];
      expect(zwaartepuntDecennium(jaren), 1990);
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
