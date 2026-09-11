/// Wat Discogs op een zoekvraag teruggeeft, en wat de app daarvan als "dit album" aanneemt.
///
/// **Waarom dit er is.** Op 11-09-2026 toonden twee online albumpagina's een andere plaat, allebei
/// door een zoekantwoord dat klakkeloos werd aangenomen:
///
/// * **Nevermind** van Nirvana, geopend vanaf de stijlpagina Alternative Rock, had zesentwintig
///   technonummers. De stijlzoekopdracht vraagt Discogs om MASTERS maar gaf de albums geen etiket
///   mee, en de albumpagina las het negatieve id dan als RELEASE. Master 13814 is Nevermind, release
///   13814 is Billy Nasty's *Race Data E.T.A* — nagemeten bij Discogs zelf.
/// * **The Sound of Milk** van Camille, die op 18-09-2026 verschijnt, droeg de persing van Christina
///   Aguilera's *Back To Basics* (RCA, 82876-82639-2). Discogs kent de plaat nog niet; de losse
///   zoekvraag gaf *Back To Basics* en *The Annual Compilation 2007* terug, en die werden gewogen in
///   plaats van afgewezen — nagemeten in de cache van de app.
///
/// Allebei zonder net: de vertaling van een zoekantwoord is los van het verzoek na te rekenen.
library;

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discogs.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _antwoord(List<Map<String, dynamic>> treffers) => {'results': treffers};

Map<String, dynamic> _master(int id, String titel) =>
    {'master_id': id, 'id': id, 'type': 'master', 'title': titel, 'format': ['CD', 'Album']};

void main() {
  group('een stijlpagina geeft masters', () {
    test('DE KERN: een album van de stijlpagina opent als MASTER', () {
      final treffers = DiscogsStyles.stijlTreffers(_antwoord([
        {'master_id': 13814, 'id': 13814, 'title': 'Nirvana - Nevermind', 'year': '1991'},
      ]));
      expect(treffers, hasLength(1));
      final ref = treffers.single.album.ref;
      expect(ref.source, CatalogSource.discogsMaster,
          reason: 'als release gelezen is 13814 Billy Nasty: technonummers onder Nevermind');
      expect(ref.intId, 13814);
      expect(treffers.single.artist, 'Nirvana');
      expect(treffers.single.album.title, 'Nevermind');
    });

    test('DE GRENS: zonder id of zonder artiest valt een treffer weg, zoals altijd', () {
      final treffers = DiscogsStyles.stijlTreffers(_antwoord([
        {'master_id': 0, 'title': 'Nirvana - Bleach'},
        {'master_id': 5, 'title': 'Zonder streepje'},
      ]));
      expect(treffers, isEmpty);
    });
  });

  group('een losse zoekvraag moet het album noemen', () {
    final ruis = _antwoord([
      _master(3064811, 'Various - The Annual Compilation 2007'),
      _master(101325, 'Christina Aguilera - Back To Basics'),
    ]);

    test('DE KERN: wat de titel niet noemt, is geen kandidaat', () {
      expect(DiscogsService.mastersUit(ruis, 'Camille', 'The Sound of Milk', los: true), isEmpty,
          reason: 'The Sound of Milk van Camille kreeg de persing van Christina Aguilera');
    });

    test('DE VAL: het echte album blijft staan tussen de ruis', () {
      final gemengd = _antwoord([
        _master(101325, 'Christina Aguilera - Back To Basics'),
        _master(4242, 'Camille - The Sound Of Milk'),
      ]);
      expect(DiscogsService.mastersUit(gemengd, 'Camille', 'The Sound of Milk', los: true), [4242]);
    });

    test('DE GRENS: een andere schrijfwijze van de artiest blijft staan', () {
      // Discogs schrijft naamsvarianten met een sterretje. De titel noemt het album dan nog
      // steeds, en dat moet genoeg zijn: anders verliest een echte plaat haar persing.
      const hit = "Go-Go's* - Beauty And The Beat";
      expect(DiscogsService.titleScore(hit, "The Go-Go's", 'Beauty and the Beat'), greaterThan(-6));
      expect(
          DiscogsService.mastersUit(
              _antwoord([_master(77, hit)]), "The Go-Go's", 'Beauty and the Beat',
              los: true),
          [77]);
    });

    test('DE GRENS: een strenge zoekvraag houdt alles, alleen op volgorde', () {
      // Die filtert Discogs zelf al op artiest én titel; wat daar terugkomt is geen ruis.
      expect(DiscogsService.mastersUit(ruis, 'Camille', 'The Sound of Milk'), hasLength(2));
    });
  });
}
