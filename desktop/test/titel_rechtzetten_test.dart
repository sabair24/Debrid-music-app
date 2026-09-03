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
import 'package:debridmusic/organize.dart';

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

    test('de zin blijft de zin — de rij komt erbij, niet in plaats van', () {
      // De vijf letterlijke zinsasserties staan in `gastartiest_test.dart`; hier wordt alleen
      // vastgelegd dat de uitleg nog steeds over hetzelfde gaat als de suggestie.
      const uitgave = [ChoiceTrack('7', 'One Minute Man', 275)];
      final uit = waaromGeenPlaatsMet(uitgave, bestand('One Minute Man (Feat Ludacris)'));
      expect(uit.reden, contains('"${uit.uitgave!.title}"'));
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

  group('de gast verdwijnt niet, hij verhuist', () {
    // De app heeft al een regel dat een persing GEEN gasten van jouw titel mag afpakken:
    // `_behoudTitel` in main.dart, geschreven voor "Lose Control (feat. Ciara and Fat Man Scoop)",
    // met als reden "dan is niet meer te zien wie er meedoet". Een knop die de officiële titel
    // overneemt en verder niets zou precies dat doen. Deze groep bewaakt de afspraak.
    test('DE KERN: de naam die uit de titel valt, komt in het artiestveld terug', () {
      const uitgave = ChoiceTrack('7', 'One Minute Man', 275);
      final uit = titelherstel(uitgave, bestand('One Minute Man (Feat Ludacris)'));
      expect(uit.titel, 'One Minute Man');
      expect(uit.artiest, 'Missy Elliott feat. Ludacris');
    });

    test('en die credit is terug te lezen als dezelfde namen', () {
      // Het heen en weer moet sluiten: wie deze credit morgen weer splitst, hoort Ludacris terug te
      // krijgen. Anders groeit er bij elke bewerking een andere spelling in de bibliotheek.
      final credit = gastcredit('Missy Elliott', ['Ludacris']);
      final terug = splitFeatured(credit, '');
      expect(terug.main, 'Missy Elliott');
      expect(terug.featured, ['Ludacris']);
    });

    test('zegt de uitgave zelf wie er meespeelt, dan wint die credit', () {
      // Dat is wat de plaat beweert, en het is dezelfde tekst die in de uitleg op het scherm stond.
      const uitgave = ChoiceTrack('7', 'Crazy in Love', 236, artist: 'Beyoncé feat. JAY-Z');
      final uit = titelherstel(
          uitgave, bestand('Crazy in Love (feat. Jay-Z)', artiest: 'Beyoncé', seconden: 236));
      expect(uit.artiest, 'Beyoncé feat. JAY-Z');
    });

    test('noemt de nieuwe titel de gast nog, dan verhuist er niets', () {
      // Anders zou de naam er dubbel in komen: in de titel én in het artiestveld.
      expect(
          gastNaarArtiest(
              bestand('One Minute Man (Feat Ludacris)'), 'One Minute Man (feat. Ludacris)'),
          isNull);
    });

    test('en staat het al in het artiestveld, dan ook niet', () {
      expect(
          gastNaarArtiest(
              bestand('One Minute Man (Feat Ludacris)', artiest: 'Missy Elliott feat. Ludacris'),
              'One Minute Man'),
          isNull);
    });

    test('zonder gast valt er niets te verhuizen', () {
      expect(gastNaarArtiest(bestand('Work It'), 'Work It'), isNull);
      expect(gastcredit('Missy Elliott', const []), 'Missy Elliott');
    });
  });

  group('het groeperen kijkt naar de HOOFDartiest', () {
    // De voorwaarde voor de groep hierboven: zolang de albumsleutel het RUWE artiestveld leest,
    // zou "gast naar het artiestveld" de plaat waar dat nummer op staat in tweeën trekken.
    //
    // Wat het BUITEN dat feature oplost is gemeten en het is niet wat het plan verwachtte. Het
    // aantal albumsleutels in deze bibliotheek gaat van 469 naar 469: de 12 nummers met een gast in
    // het artiestveld staan elk op een plaat waar álle nummers diezelfde credit dragen, dus er
    // wordt hernoemd en niets samengevoegd. Wat er wél stuk was, staat in de tweede toets.
    Track nummer(String pad, {required String artiest, String titel = 'Song'}) => Track(
          path: pad,
          title: titel,
          artist: artiest,
          album: 'Elephunk',
          trackNo: 1,
          isFlac: true,
        );

    test('DE KERN: een gast in het artiestveld scheurt de plaat niet meer', () {
      final lib = LibraryStore();
      lib.tracks.addAll([
        nummer(r'C:\m\1.flac', artiest: 'Black Eyed Peas', titel: 'Hey Mama'),
        nummer(r'C:\m\2.flac', artiest: 'Black Eyed Peas feat. Justin Timberlake', titel: 'Where Is the Love?'),
      ]);
      lib.rebuildAlbums();

      final elephunk = lib.albums.where((a) => a.title == 'Elephunk').toList();
      expect(elephunk, hasLength(1), reason: 'één plaat, geen los tegeltje ernaast');
      expect(elephunk.single.tracks, hasLength(2));
      expect(elephunk.single.artist, 'Black Eyed Peas');
    });

    test('DE ECHTE BUG: "samenvoegen" kon een feat-plaat niet eens vinden', () {
      // `mergeEditions` en `isMerged` bouwen hun sleutel uit de GETOONDE artiest van de plaat, en
      // die is al gesplitst ("Black Eyed Peas"). De sleutel waaronder het album lag kwam uit het
      // ruwe veld ("black eyed peas feat. justin timberlake"). Die twee konden nooit gelijk zijn:
      // de knop deed niets en bleef zichzelf aanbieden. `album_cover_key_test.dart` beschrijft
      // dezelfde soort scheve sleutel voor de hoezen.
      final lib = LibraryStore();
      lib.tracks.add(nummer(r'C:\m\5.flac',
          artiest: 'Black Eyed Peas feat. Justin Timberlake', titel: 'Where Is the Love?'));
      lib.rebuildAlbums();

      final a = lib.albums.single;
      expect(
          lib.editionsOfRecord('album::${artistKey(a.artist)}|${normKey(a.title)}'),
          isNotNull,
          reason: 'de sleutel die mergeEditions bouwt moet de plaat ook echt vinden');
    });

    test('en een "&" in een bandnaam splitst nog steeds niet', () {
      // De tegenproef. `splitFeatured` raakt een `&` niet aan — dat scheidt alleen namen BINNEN een
      // gastenlijst. Zou dat veranderen, dan valt elk duo uiteen.
      final lib = LibraryStore();
      lib.tracks.addAll([
        nummer(r'C:\m\3.flac', artiest: 'Simon & Garfunkel', titel: 'America'),
        nummer(r'C:\m\4.flac', artiest: 'Simon & Garfunkel', titel: 'The Boxer'),
      ]);
      lib.rebuildAlbums();

      expect(lib.albums.where((a) => a.title == 'Elephunk'), hasLength(1));
      expect(lib.albums.single.artist, 'Simon & Garfunkel');
    });
  });
}
