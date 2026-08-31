/// "(Duet With …)" is een credit; "With" midden in een titel is dat niet.
///
/// **Waarom dit bestaat.** Gemeten op 01-09-2026 met tien bestanden van *Dangerously In Love*: negen
/// vonden hun rij, en er bleef er één over — "The Closer I Get To You (Duet With Luther Vandross)".
/// MusicBrainz schrijft die rij als "The Closer I Get to You" met de credit "Beyoncé & Luther
/// Vandross" ernaast, dus het bewijs om ze te koppelen lág er. Alleen haalde [splitFeatured] geen
/// gast uit die titel — het herkende "feat." en "ft.", maar geen "with" — en dus kwam de
/// vergelijking die dat bewijs gebruikt niet eens op gang.
///
/// **En waarom het haakje de hele veiligheid is.** "with" los in een titel is doodgewoon Engels.
/// Zou het ook daar tellen, dan krijgt "Dancing With Myself" ineens Myself als gastartiest, en
/// vervolgens valt dat nummer op de rij van een ander. Achter een haakje is "with" nooit deel van de
/// naam; daar staat een credit.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart';

Track bestand(String titel, int seconden, {String artiest = 'Beyoncé', int nr = 0}) => Track(
      path: 'D:\\muziek\\${titel.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')}.flac',
      title: titel,
      artist: artiest,
      album: 'Dangerously In Love',
      isFlac: true,
      duration: Duration(seconds: seconden),
      trackNo: nr,
    );

void main() {
  group('splitFeatured', () {
    test('DE KERN: een duet tussen haakjes levert de gast op', () {
      final uit = splitFeatured('Beyoncé', 'The Closer I Get To You (Duet With Luther Vandross)');
      expect(uit.featured, ['Luther Vandross']);
    });

    test('en een gewone credit tussen haakjes ook', () {
      expect(splitFeatured('Adele', 'Easy On Me (With Chris Stapleton)').featured,
          ['Chris Stapleton']);
    });

    test('MAAR: "with" los in een titel is geen gast', () {
      // Anders krijgt de halve bibliotheek er artiesten bij die niet bestaan.
      expect(splitFeatured('Billy Idol', 'Dancing With Myself').featured, isEmpty);
      expect(splitFeatured('Whitney Houston', 'Dance With Somebody').featured, isEmpty);
    });
  });

  group('en wat dat op de albumpagina doet', () {
    test('het duet vindt zijn rij, want de uitgave noemt Vandross', () {
      // Zoals MusicBrainz het schrijft: kale titel, en de credit met een ampersand ernaast.
      final uit = matchAlbumTracks(
        [const ChoiceTrack('11', 'The Closer I Get to You', 297,
            artist: 'Beyoncé & Luther Vandross')],
        [bestand('The Closer I Get To You (Duet With Luther Vandross)', 298, nr: 11)],
        'Beyoncé',
      );
      expect(uit.matched, 1);
    });

    test('en blijft liggen als de uitgave die gast NIET noemt', () {
      // Dezelfde vorm, ander geval: staat er alleen "Adele", dan is het duet een andere opname en
      // hoort de rij leeg te blijven staan zodat de app hem nog kan halen.
      final uit = matchAlbumTracks(
        [const ChoiceTrack('1', 'Easy on Me', 224, artist: 'Adele')],
        [bestand('Easy On Me (With Chris Stapleton)', 224, artiest: 'Adele', nr: 1)],
        'Adele',
      );
      expect(uit.matched, 0, reason: 'de uitgave noemt Stapleton niet, dus dit is niet die rij');
    });
  });
}
