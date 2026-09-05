/// De toewijzing als één som, in plaats van een reeks gokjes.
///
/// **Waarom dit bestaat.** Saber, 05-09-2026, over *Dip It Low (Mixes)*: *"het probleem is nog altijd
/// niet opgelost e, vindt een manier om dit correct aan te passen [...] ik wil de beste tagger
/// systeem hebben, zoek online hoe zij het doen en basseer je daarop!"*
///
/// Dat is [beets](https://beets.readthedocs.io/en/stable/reference/config.html): één gewogen
/// afstandsfunctie, en een globaal optimale toewijzing via het Hongaarse algoritme in plaats van
/// volgordelijke passen. De toets hieronder die het duidelijkst maakt is "een gulzige pas kiest hier
/// fout": twee rijen die op elkaar lijken, en de eerste rij die pakt wat de tweede nodig had.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/editions.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/toewijzing.dart';

Track b(String titel, int seconden, {String artiest = 'Christina Milian', int nr = 0}) => Track(
      path: 'D:\\m\\$titel-$seconden.flac',
      title: titel,
      artist: artiest,
      album: 'Dip It Low (Mixes)',
      trackNo: nr,
      isFlac: true,
      duration: Duration(seconds: seconden),
    );

void main() {
  group('rijAfstand', () {
    test('DE KERN: gelijke titel en bijna gelijke lengte is bijna nul', () {
      expect(rijAfstand(const ChoiceTrack('1', 'Dip It Low', 198), b('Dip It Low', 194)),
          lessThan(0.05));
    });

    test('en een versiemerk aan één kant is een VETO, geen straf', () {
      // Dit is strenger dan beets met opzet: zou het een gewicht zijn, dan drukken een gelijke
      // titel en een toevallig kloppende lengte het weg -- en dat is precies het gemelde geval.
      final d = rijAfstand(
          const ChoiceTrack('1', 'Dip It Low (Full Intention Dub)', 200), b('Dip It Low', 194));
      expect(d, greaterThan(1000));
    });

    test('een lengteverschil binnen de speling kost niets', () {
      final dichtbij = rijAfstand(const ChoiceTrack('1', 'Song', 200), b('Song', 195));
      final gelijk = rijAfstand(const ChoiceTrack('1', 'Song', 200), b('Song', 200));
      expect(dichtbij, gelijk);
    });

    test('en een groot lengteverschil telt zwaar', () {
      final ver = rijAfstand(const ChoiceTrack('1', 'Song', 200), b('Song', 400));
      final dicht = rijAfstand(const ChoiceTrack('1', 'Song', 200), b('Song', 200));
      expect(ver, greaterThan(dicht));
      expect(ver, greaterThan(0.3));
    });

    test('de credit van de uitgave telt mee als die er is', () {
      const rij = ChoiceTrack('2', 'Dip It Low', 220, artist: 'Christina Milian feat. Fabolous');
      final metGast = rijAfstand(rij, b('Dip It Low', 218, artiest: 'Christina Milian feat. Fabolous'));
      final zonder = rijAfstand(rij, b('Dip It Low', 218));
      expect(metGast, lessThan(zonder));
    });

    test('accenten en hoofdletters maken geen verschil', () {
      expect(rijAfstand(const ChoiceTrack('1', 'Ce Rêve Bleu', 200), b('ce reve bleu', 200)),
          lessThan(0.05));
    });
  });

  group('besteToewijzing', () {
    test('DE KERN: een gulzige pas kiest hier fout, deze niet', () {
      // Twee rijen die "Dip It Low" heten, van 3:18 en 3:40. Twee bestanden van 3:14 en 3:38.
      // Een pas die rij 1 als eerste bedient en het eerste bestand pakt dat binnen de marge valt,
      // kan het 3:38-bestand op rij 1 leggen -- en dan klopt de rest ook niet meer.
      const rijen = [
        ChoiceTrack('1', 'Dip It Low', 198),
        ChoiceTrack('2', 'Dip It Low', 220),
      ];
      // Met opzet in de ONGUNSTIGE volgorde aangeboden.
      final bestanden = [b('Dip It Low', 218), b('Dip It Low', 194)];
      expect(besteToewijzing(rijen, bestanden), [1, 0]);
    });

    test('en de uitkomst hangt niet van de volgorde af', () {
      const rijen = [
        ChoiceTrack('1', 'Dip It Low', 198),
        ChoiceTrack('2', 'Dip It Low', 220),
      ];
      final a = b('Dip It Low', 194), c = b('Dip It Low', 218);
      expect(besteToewijzing(rijen, [a, c]), [0, 1]);
      expect(besteToewijzing(rijen, [c, a]), [1, 0]);
    });

    test('DE VAL: hij legt niet ALLES ergens neer', () {
      // Zonder een bovengrens vindt een optimale toewijzing altijd wel een plek. Een bestand dat op
      // geen enkele rij hoort moet een weeskind blijven.
      const rijen = [ChoiceTrack('1', 'Dip It Low', 198)];
      final bestanden = [b('Iets Heel Anders', 300)];
      expect(besteToewijzing(rijen, bestanden), [null]);
    });

    test('meer bestanden dan rijen: de beste krijgen de rijen', () {
      const rijen = [ChoiceTrack('1', 'Song', 200)];
      final bestanden = [b('Song', 260), b('Song', 201)];
      expect(besteToewijzing(rijen, bestanden), [1]);
    });

    test('meer rijen dan bestanden: de rest blijft leeg', () {
      const rijen = [
        ChoiceTrack('1', 'Een', 200),
        ChoiceTrack('2', 'Twee', 200),
        ChoiceTrack('3', 'Drie', 200),
      ];
      final uit = besteToewijzing(rijen, [b('Twee', 200)]);
      expect(uit, [null, 0, null]);
    });

    test('een remix pikt de rij van de albumversie niet in', () {
      const rijen = [
        ChoiceTrack('1', 'Song', 200),
        ChoiceTrack('2', 'Song (Radio Edit)', 190),
      ];
      final uit = besteToewijzing(rijen, [b('Song (Radio Edit)', 191), b('Song', 202)]);
      expect(uit, [1, 0]);
    });

    test('lege lijsten doen niets', () {
      expect(besteToewijzing(const [], [b('Song', 200)]), isEmpty);
      expect(besteToewijzing(const [ChoiceTrack('1', 'Song', 200)], const []), [null]);
    });
  });
}
