/// Een titel die niet op de uitgave past, rechtzetten — en wat daarbij NIET mag gebeuren.
///
/// **Waarvoor dit bestaat.** Onder "Niet op deze uitgave" staat sinds kort een uitleg per nummer:
///
/// > jouw bestand heet "One Minute Man (Feat Ludacris)"; de uitgave noemt "One Minute Man" en zegt
/// > niet wie er meespeelt
///
/// Die uitleg was een doodlopende weg — je las wat er mis was en kon er niets aan doen. Gevraagd op
/// 02-09-2026: *"zorg dat ik er iets aan kan doen, titel aanpassen met suggesties wat het dan wel
/// moet zijn officieel"*.
///
/// Twee dingen worden hier vastgezet, en het tweede is het gevaarlijkste:
///
///   1. de uitleg en de suggestie komen uit ÉÉN vergelijking, zodat de knop nooit iets anders kan
///      voorstellen dan de regel eronder beweert;
///   2. een titelherstel raakt de titel en verder niets — geen nummering, geen jaartal, geen
///      ALBUMARTIST. Die drie zouden respectievelijk het nummer naar de kop van de lijst schieten,
///      het jaartal wissen, en de plaat in tweeën trekken.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

Track bestand(String titel, {String artiest = 'Missy Elliott', int seconden = 275}) => Track(
      path: 'D:\\muziek\\$titel.flac',
      title: titel,
      artist: artiest,
      album: 'Miss E... So Addictive',
      isFlac: true,
      duration: Duration(seconds: seconden),
    );

void main() {
  group('waaromGeenPlaatsMet — één vergelijking, twee uitkomsten', () {
    test('DE KERN: de suggestie is de rij die de uitleg noemt', () {
      // Het gemelde geval, letterlijk.
      const uitgave = [ChoiceTrack('7', 'One Minute Man', 275)];
      final t = bestand('One Minute Man (Feat Ludacris)');
      final uit = waaromGeenPlaatsMet(uitgave, t);

      expect(uit.uitgave?.title, 'One Minute Man');
      expect(uit.reden, contains('One Minute Man'));
      expect(uit.reden, contains('zegt niet wie er meespeelt'));
    });

    test('en de oude zin is woord voor woord dezelfde gebleven', () {
      // `waaromGeenPlaats` is nu een omhulling. Zou die tekst verschuiven, dan verandert wat er op
      // het scherm staat zonder dat iemand daarom vroeg.
      const uitgave = [ChoiceTrack('7', 'One Minute Man', 275)];
      final t = bestand('One Minute Man (Feat Ludacris)');
      expect(waaromGeenPlaats(uitgave, t), waaromGeenPlaatsMet(uitgave, t).reden);
    });

    test('bij twee gelijke rijen komt er GEEN suggestie', () {
      // De zin zegt zelf dat niet te bepalen is welke rij het is; een suggestie zou dat
      // tegenspreken.
      const uitgave = [
        ChoiceTrack('7', 'One Minute Man', 275),
        ChoiceTrack('14', 'One Minute Man (feat. Jay-Z)', 275),
      ];
      final uit = waaromGeenPlaatsMet(uitgave, bestand('One Minute Man (Feat Ludacris)'));
      expect(uit.uitgave, isNull);
      expect(uit.reden, contains('2 keer'));
    });

    test('bij een lengteverschil ook niet, want de titel klopt al', () {
      // Een knop "titel rechtzetten" zou daar niets veranderen.
      const uitgave = [ChoiceTrack('7', 'One Minute Man', 400)];
      final uit = waaromGeenPlaatsMet(uitgave, bestand('One Minute Man', seconden: 275));
      expect(uit.uitgave, isNull);
      expect(uit.reden, contains('duurt'));
    });

    test('en zonder tracklijst valt er niets te wijzen', () {
      final uit = waaromGeenPlaatsMet(const [], bestand('One Minute Man (Feat Ludacris)'));
      expect(uit.uitgave, isNull);
      expect(uit.reden, 'er is geen tracklijst opgehaald');
    });
  });

  group('veldenBijTitelherstel — wat er WEL en NIET geschreven wordt', () {
    test('DE KERN: alleen de titel', () {
      final v = veldenBijTitelherstel(titel: 'One Minute Man');
      expect(v, {'TITLE': 'One Minute Man'});
    });

    test('de nummering blijft staan, en dat is het hele punt', () {
      // Via `applyCorrection(alleen:)` zouden deze gewist worden — dat hoort bij een VERHUIZING
      // naar een andere plaat, en daar klopt het ook. Hier verhuist er niets: het nummer blijft op
      // dezelfde plaat staan, alleen de spelling van de titel klopte niet.
      //
      // Het symptoom als het toch gebeurt: `rebuildAlbums` sorteert op `trackNo`, dus met een
      // gewiste TRACKNUMBER schiet het nummer naar de kop van de tracklijst.
      final v = veldenBijTitelherstel(titel: 'One Minute Man', artiest: 'Missy Elliott');
      for (final veld in [
        'TRACKNUMBER',
        'TRACKTOTAL',
        'TOTALTRACKS',
        'DISCNUMBER',
        'DISCTOTAL',
        'TOTALDISCS',
        'DATE',
      ]) {
        expect(v.containsKey(veld), isFalse, reason: '$veld hoort hier niet aangeraakt te worden');
      }
    });

    test('DE VAL: ALBUMARTIST blijft er buiten, ook mét een artiest', () {
      // `_groupKey` groepeert op het ARTIESTveld. "Missy Elliott feat. Ludacris" in ARTIST is één
      // ding — dezelfde staart in ALBUMARTIST zou de plaat in tweeën trekken. `applyCorrection`
      // maakt van een meegegeven artiest wél een ALBUMARTIST, en dat is precies waarom deze weg
      // apart bestaat.
      final v = veldenBijTitelherstel(
          titel: 'One Minute Man', artiest: 'Missy Elliott feat. Ludacris');
      expect(v.containsKey('ALBUMARTIST'), isFalse);
      expect(v['ARTIST'], 'Missy Elliott feat. Ludacris');
      expect(v['TITLE'], 'One Minute Man');
    });

    test('zonder artiest wordt ARTIST niet aangeraakt', () {
      expect(veldenBijTitelherstel(titel: 'X').containsKey('ARTIST'), isFalse);
      expect(
          veldenBijTitelherstel(titel: 'X', artiest: '   ').containsKey('ARTIST'),
          isFalse);
    });

    test('een lege titel schrijft niets, in plaats van hem te wissen', () {
      // Anders zou een leeg tekstveld de titel uit het bestand halen.
      expect(veldenBijTitelherstel(titel: '   '), isEmpty);
    });

    test('en de titel wordt getrimd', () {
      expect(veldenBijTitelherstel(titel: '  One Minute Man  '),
          {'TITLE': 'One Minute Man'});
    });
  });
}
