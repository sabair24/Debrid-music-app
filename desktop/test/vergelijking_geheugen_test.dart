/// De albumpagina vergelijkt de officiële tracklijst met je bestanden alleen opnieuw als er iets
/// veranderd is.
///
/// **Gemeten op 05-10-2026:** [matchAlbumTracks] kost op de pc 1,3 ms bij 12 nummers, 2,9 ms bij 20
/// en 25,6 ms bij 60, en de pagina deed hem bij elke bouw — en die bouwt bij elke melding van de
/// bibliotheek. Onthouden mag, maar alleen zolang de uitkomst niet anders zou zijn: een gemiste
/// verandering is hier erger dan een trage pagina, want dan staat een gedownload nummer nog als
/// "ontbreekt" en een gecorrigeerde titel nog onder zijn oude naam.
library;

import 'package:debridmusic/editions.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _officieel = [
  ChoiceTrack('1', 'Hello', 180),
  ChoiceTrack('2', 'Roll With It', 240),
  ChoiceTrack('3', 'Wonderwall', 260),
];

Track _nummer(int nr, String titel) => Track(
      path: '/m/Oasis/Morning Glory/0$nr - $titel.flac',
      title: titel,
      artist: 'Oasis',
      album: 'Morning Glory',
      trackNo: nr,
      duration: Duration(seconds: [180, 240, 260][nr - 1]),
    );

Album _plaat(List<Track> t) => Album('Morning Glory', 'Oasis', t);

int _ontbrekend(dynamic uitkomst) => (uitkomst.slots as List).where((s) => s.missing as bool).length;

void main() {
  test('DE KERN: dezelfde plaat twee keer is één vergelijking', () {
    final g = VergelijkingGeheugen();
    final plaat = _plaat([_nummer(3, 'Wonderwall')]);
    final a = g.van(_officieel, plaat, source: 'mb', handmatig: const {});
    final b = g.van(_officieel, plaat, source: 'mb', handmatig: const {});
    expect(g.keer, 1, reason: 'elke bouw van de albumpagina vergeleek opnieuw — 25 ms bij 60 nummers');
    expect(identical(a, b), isTrue);
  });

  test('DE KERN: dezelfde plaat opnieuw opgebouwd, met dezelfde nummers, is ook één vergelijking', () {
    // Een melding van de bibliotheek wijst [AlbumDetailPage] opnieuw naar "zijn" album; zolang de
    // nummers dezelfde objecten zijn, is er niets veranderd.
    final g = VergelijkingGeheugen();
    final w = _nummer(3, 'Wonderwall');
    g.van(_officieel, _plaat([w]), source: 'mb', handmatig: const {});
    g.van(_officieel, _plaat([w]), source: 'mb', handmatig: const {});
    expect(g.keer, 1);
  });

  group('DE VAL: wat er verandert, moet hij zien', () {
    test('een gedownload nummer staat niet meer als ontbrekend', () {
      final g = VergelijkingGeheugen();
      final w = _nummer(3, 'Wonderwall');
      final eerst = g.van(_officieel, _plaat([w]), source: 'mb', handmatig: const {});
      final daarna = g.van(_officieel, _plaat([_nummer(1, 'Hello'), w]), source: 'mb', handmatig: const {});
      expect(g.keer, 2);
      expect(_ontbrekend(daarna), _ontbrekend(eerst) - 1,
          reason: 'een net binnengekomen nummer bleef als "ontbreekt" staan');
    });

    test('een gecorrigeerd nummer — een nieuw object op dezelfde plek — wordt opnieuw vergeleken', () {
      final g = VergelijkingGeheugen();
      g.van(_officieel, _plaat([_nummer(3, 'Wonderwal')]), source: 'mb', handmatig: const {});
      g.van(_officieel, _plaat([_nummer(3, 'Wonderwall')]), source: 'mb', handmatig: const {});
      expect(g.keer, 2, reason: 'een titel die je net verbeterde, bleef onder de oude vergelijking staan');
    });

    test('een andere officiële lijst, ook met dezelfde inhoud', () {
      final g = VergelijkingGeheugen();
      final plaat = _plaat([_nummer(3, 'Wonderwall')]);
      g.van(_officieel, plaat, source: 'mb', handmatig: const {});
      g.van(List.of(_officieel), plaat, source: 'mb', handmatig: const {});
      expect(g.keer, 2);
    });
  });

  group('DE GRENS: ook buiten de nummers', () {
    test('een toewijzing van jou', () {
      final g = VergelijkingGeheugen();
      final w = _nummer(3, 'Wonderwall');
      final plaat = _plaat([w]);
      g.van(_officieel, plaat, source: 'mb', handmatig: const {});
      g.van(_officieel, plaat, source: 'mb', handmatig: {w.path: '2'});
      expect(g.keer, 2, reason: 'een rij die je zelf aanwees, kwam niet op zijn plek');
      // En een nieuwe kaart met dezelfde inhoud is geen verandering.
      g.van(_officieel, plaat, source: 'mb', handmatig: {w.path: '2'});
      expect(g.keer, 2);
    });

    test('een andere bron, artiest of titel', () {
      final g = VergelijkingGeheugen();
      final w = _nummer(3, 'Wonderwall');
      g.van(_officieel, _plaat([w]), source: 'mb', handmatig: const {});
      g.van(_officieel, _plaat([w]), source: 'dg', handmatig: const {});
      expect(g.keer, 2);
      g.van(_officieel, Album('Morning Glory?', 'Oasis', [w]), source: 'dg', handmatig: const {});
      expect(g.keer, 3);
      g.van(_officieel, Album('Morning Glory?', 'Oasis UK', [w]), source: 'dg', handmatig: const {});
      expect(g.keer, 4);
    });
  });
}
