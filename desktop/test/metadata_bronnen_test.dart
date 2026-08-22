/// "Metadata corrigeren" moest meer bronnen laden, en accurater zijn.
///
/// **Wat er misging.** Het venster vroeg Discogs om `database/search?q=…&per_page=12`. Dat is de
/// zoeklijst, gesorteerd op relevantie: voor *Thriller* levert dat vinyl, vinyl, een laserdisc en een
/// vhs-documentaire — terwijl Discogs honderden persingen van die plaat heeft, cd's incluis. Twaalf
/// van de honderden, en niet de twaalf waar je iets aan hebt.
///
/// De uitgavekiezer had dat al opgelost en zegt in zijn eigen commentaar waaróm: Discogs heeft
/// tweeëntwintig masters die "Michael Jackson - Thriller" heten, en de best scorende is een
/// vinyl-only ingang. Twee lijsten van dezelfde plaat die elkaar tegenspreken — dat is hoe dit
/// venster aanvoelde.
///
/// Deze toets raakt het net niet. Hij legt de twee dingen vast die zonder netwerk te bewijzen zijn:
/// de bronnenkeuze, en de val waar het bewaren van een persing-hoes in kan lopen.
library;

import 'package:debridmusic/editions.dart';
import 'package:debridmusic/metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('de bronnen', () {
    test('"Alles" staat er, en staat vooraan', () {
      // Vooraan omdat het de standaard is. Wie dit venster opent om een persing te corrigeren hoort
      // niet te beginnen bij de enige bron die geen persingen kent.
      expect(MetadataSearch.providers.first, 'Alles');
      expect(MetadataSearch.providers, containsAll(['Discogs', 'MusicBrainz', 'Deezer']));
    });

    test('Deezer staat achteraan, want die kent geen persingen', () {
      // Geen cd's, geen catalogusnummers, geen landen. Als standaard was dat de bron die het
      // antwoord op de gestelde vraag niet kán geven.
      expect(MetadataSearch.providers.last, 'Deezer');
    });
  });

  group('de regel onder een persing', () {
    test('formaat, land, catalogusnummer en jaar', () {
      const k = ReleaseChoice(
        source: EditionSource.discogs,
        releaseId: 9902241,
        format: 'CD',
        country: 'Netherlands',
        catno: '9902241',
        year: 1995,
      );
      expect(MetadataSearch.persingRegel(k), 'CD · Netherlands · 9902241 · 1995');
    });

    test('wat een persing niet weet, staat er niet', () {
      // Lege stukken hebben hier een prijs: "CD ·  · " leest als een fout in de app in plaats van
      // als een gat in de database.
      const k = ReleaseChoice(source: EditionSource.discogs, format: 'CD', year: 1982);
      expect(MetadataSearch.persingRegel(k), 'CD · 1982');
    });

    test('een persing zonder gegevens krijgt geen lege regel', () {
      const k = ReleaseChoice(source: EditionSource.discogs);
      expect(MetadataSearch.persingRegel(k), isNull);
    });
  });

  group('welke scan er bewaard wordt', () {
    test('de volle scan, als die er is', () {
      const m = MetaResult(
        title: 'Thriller',
        artist: 'Michael Jackson',
        album: 'Thriller',
        coverUrl: 'https://x/klein.jpg',
        coverFullUrl: 'https://x/groot.jpg',
      );
      expect(m.bewaarCover, 'https://x/groot.jpg');
    });

    test('zonder volle scan is de rijafbeelding goed genoeg', () {
      const m = MetaResult(
        title: 'Thriller',
        artist: 'Michael Jackson',
        album: 'Thriller',
        coverUrl: 'https://x/hoes.jpg',
      );
      expect(m.bewaarCover, 'https://x/hoes.jpg');
    });

    test('een MINIATUUR wordt nooit bewaard', () {
      // De val. De persingenlijst van Discogs geeft per rij een `uri150` van 150×150. Zonder deze
      // regel wordt dat je `correctedCover`: de hoogste voorrang die er is, weggeschreven naar
      // schijf, en bij elke start weer teruggeladen — een hoes van 150 pixels op een scherm dat er
      // 1200 vraagt. Deze app is daar al eens ingelopen; zie `ChoiceImage.alleenMiniatuur`.
      const m = MetaResult(
        title: 'Thriller',
        artist: 'Michael Jackson',
        album: 'Thriller',
        coverUrl: 'https://x/uri150.jpg',
        coverIsMiniatuur: true,
        releaseId: 9902241,
      );
      expect(m.bewaarCover, isNull, reason: 'de kiezer haalt eerst de volle scan op');
      // De rij zelf toont hem wél — 150 pixels is ruim voor 44 punten.
      expect(m.coverUrl, isNotNull);
      // En het id moet er zijn, want dáármee wordt de volle scan opgehaald.
      expect(m.releaseId, 9902241);
    });
  });
}
