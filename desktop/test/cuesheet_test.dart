/// Een cuesheet lezen, want anders is een RuTracker-release één blok van 300 MB.
///
/// **Waarom dit bestaat.** Een groot deel van het lossless-aanbod op RuTracker is één albumbestand
/// (`.ape` of `.flac`) met een `.cue` ernaast. De app kende `ape` alleen als woord in de
/// kwaliteitsrangschikking en had nergens een cue-lezer, dus een geslaagde download leverde één
/// bestand in plaats van twaalf nummers.
///
/// Het knippen zelf heeft ffmpeg nodig en is hier dus niet te draaien. Wát er geknipt moet worden is
/// zuivere rekenkunde, en dat is precies het stuk dat fout kan gaan zonder dat je het ziet: één
/// frame verkeerd en het begin van het volgende nummer zit aan het eind van het vorige geplakt.
library;

import 'package:debridmusic/cp1251.dart';
import 'package:debridmusic/cuesheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een gewoon blad: één bestand, drie nummers, met een aanloop op nummer 2 en 3.
const _gewoon = '''
REM GENRE Electronic
REM DATE 1998
PERFORMER "Air"
TITLE "Moon Safari"
FILE "Air - Moon Safari.ape" WAVE
  TRACK 01 AUDIO
    TITLE "La Femme d'Argent"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Sexy Boy"
    INDEX 00 07:08:00
    INDEX 01 07:10:25
  TRACK 03 AUDIO
    TITLE "All I Need"
    PERFORMER "Air feat. Beth Hirsch"
    INDEX 00 11:15:00
    INDEX 01 11:17:50
''';

void main() {
  group('mm:ss:ff is frames, geen honderdsten', () {
    test('vijfenzeventig frames maken een seconde', () {
      // Dit is het getal waar alles op staat. Zou dit honderd zijn, dan zit elk nummer er een
      // fractie naast en hoor je het begin van het volgende aan het eind van het vorige.
      expect(framesPerSeconde, 75);
      expect(framesUitTijd('00:00:00'), 0);
      expect(framesUitTijd('00:01:00'), 75);
      expect(framesUitTijd('00:00:74'), 74);
      expect(framesUitTijd('01:00:00'), 60 * 75);
      expect(framesUitTijd('07:10:25'), (7 * 60 + 10) * 75 + 25);
    });

    test('minuten mogen boven de negenenvijftig uitkomen', () {
      // Een cd loopt tot vierenzeventig minuten en een blad schrijft dat als 74:30:00, niet als uren.
      expect(framesUitTijd('74:30:00'), (74 * 60 + 30) * 75);
    });

    test('wat geen tijd is levert niets op', () {
      expect(framesUitTijd('AUDIO'), isNull);
      expect(framesUitTijd('1:2'), isNull);
      expect(framesUitTijd('00:00:75'), isNull, reason: 'frame 75 bestaat niet, 0 t/m 74 wel');
      expect(framesUitTijd('00:60:00'), isNull, reason: 'seconde 60 bestaat niet');
    });
  });

  group('een gewoon blad', () {
    test('album, artiest, jaar en genre komen eruit', () {
      final blad = leesCue(_gewoon)!;
      expect(blad.album, 'Moon Safari');
      expect(blad.albumArtiest, 'Air');
      expect(blad.jaar, '1998');
      expect(blad.genre, 'Electronic');
      expect(blad.nummers.length, 3);
      expect(blad.bestanden, ['Air - Moon Safari.ape']);
    });

    test('DE KERN: er wordt op INDEX 01 geknipt, niet op INDEX 00', () {
      // INDEX 00 is de aanloop — de stilte vóór het nummer. Knip je daarop, dan plak je die stilte
      // vóór het volgende nummer in plaats van achter het vorige.
      final n = leesCue(_gewoon)!.nummers;
      expect(n[1].startFrames, framesUitTijd('07:10:25'));
      expect(n[2].startFrames, framesUitTijd('11:17:50'));
    });

    test('en het einde is waar het VOLGENDE nummer begint', () {
      // Daarmee hoort de aanloop bij het vorige nummer, precies zoals op de cd.
      final n = leesCue(_gewoon)!.nummers;
      expect(n[0].eindeFrames, framesUitTijd('07:10:25'));
      expect(n[1].eindeFrames, framesUitTijd('11:17:50'));
    });

    test('het laatste nummer heeft geen einde — dat weet alleen het bestand', () {
      final n = leesCue(_gewoon)!.nummers;
      expect(n.last.eindeFrames, isNull);
      expect(n.last.duurSeconden, isNull);
    });

    test('een eigen artiest wint van die van het album', () {
      final n = leesCue(_gewoon)!.nummers;
      expect(n[0].artiest, 'Air', reason: 'geen eigen PERFORMER, dus die van het album');
      expect(n[2].artiest, 'Air feat. Beth Hirsch');
    });

    test('de duur klopt in seconden', () {
      final n = leesCue(_gewoon)!.nummers;
      expect(n[0].startSeconden, 0);
      expect(n[0].duurSeconden, closeTo(7 * 60 + 10 + 25 / 75, 0.001));
    });
  });

  group('een dubbel-cd als twee images', () {
    // Komt echt voor: twee FILE-blokken in één blad. Het laatste nummer van schijf één loopt tot het
    // einde van ZIJN bestand — niet tot een tijdstip uit het bestand van schijf twee.
    const twee = '''
PERFORMER "Iemand"
TITLE "Verzameld"
FILE "cd1.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Een"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Twee"
    INDEX 01 03:00:00
FILE "cd2.flac" WAVE
  TRACK 03 AUDIO
    TITLE "Drie"
    INDEX 01 00:00:00
''';

    test('DE KERN: het einde loopt niet door naar het volgende bestand', () {
      final n = leesCue(twee)!.nummers;
      expect(n[1].bestand, 'cd1.flac');
      expect(n[1].eindeFrames, isNull,
          reason: 'laatste van cd1 — nummer 3 zit in een ander bestand');
      expect(n[2].bestand, 'cd2.flac');
      expect(n[2].startFrames, 0);
    });

    test('de bestanden staan op volgorde en zonder herhaling', () {
      expect(leesCue(twee)!.bestanden, ['cd1.flac', 'cd2.flac']);
    });
  });

  group('de vorm van de regels', () {
    test('het soort achter FILE hoort niet bij de naam', () {
      expect(cueWaarde('"album.ape" WAVE'), 'album.ape');
      expect(cueWaarde('album.ape WAVE', zonderStaart: const {'WAVE'}), 'album.ape');
    });

    test('een naam met spaties zonder aanhalingstekens blijft heel', () {
      expect(cueWaarde('Air - Moon Safari.ape WAVE', zonderStaart: const {'WAVE'}),
          'Air - Moon Safari.ape');
    });

    test('een nummer zonder titel krijgt er een die je kunt lezen', () {
      final blad = leesCue('FILE "x.flac" WAVE\n TRACK 05 AUDIO\n  INDEX 01 00:00:00\n')!;
      expect(blad.nummers.single.titel, 'Nummer 5');
      expect(blad.nummers.single.nummer, 5, reason: 'zoals het in de cue staat, niet de plaats');
    });

    test('Windows-regeleindes breken het niet', () {
      expect(leesCue('FILE "x.flac" WAVE\r\n TRACK 01 AUDIO\r\n  INDEX 01 00:00:00\r\n')!.nummers,
          hasLength(1));
    });

    test('geen nummers is geen cuesheet', () {
      expect(leesCue(''), isNull);
      expect(leesCue('PERFORMER "Iemand"\nTITLE "Iets"\n'), isNull);
      expect(leesCue('dit is gewoon een tekstbestand'), isNull);
    });

    test('een nummer zonder INDEX 01 telt niet mee', () {
      // Alleen INDEX 00 is geen begin. Zonder deze regel zou dat nummer op de aanloop geknipt worden.
      final blad = leesCue('FILE "x.flac" WAVE\n'
          ' TRACK 01 AUDIO\n  INDEX 01 00:00:00\n'
          ' TRACK 02 AUDIO\n  INDEX 00 03:00:00\n');
      expect(blad!.nummers, hasLength(1));
    });
  });

  group('de codering, want die is hier het bestand met de namen', () {
    test('cp1251 heen en terug', () {
      const russisch = 'Кино';
      final bytes = russisch.runes.map((r) => cp1251Byte(r)!).toList();
      expect(cp1251Tekst(bytes), russisch);
    });

    test('leestekens uit de bovenste helft overleven ook', () {
      // № en de aanhalingstekens komen in albumtitels vaker voor dan je zou denken; zonder de tabel
      // worden het vraagtekens.
      for (final teken in ['№', '«', '»', '—', '©', '°']) {
        final b = cp1251Byte(teken.runes.first);
        expect(b, isNotNull, reason: teken);
        expect(cp1251Tekst([b!]), teken);
      }
    });

    test('UTF-8 wordt als UTF-8 gelezen, ook met BOM', () {
      // Кино in UTF-8. Dezelfde vier letters als hierboven, maar acht bytes in plaats van vier —
      // en dát is het verschil dat verkeerd raden zichtbaar maakt.
      const kino = [0xD0, 0x9A, 0xD0, 0xB8, 0xD0, 0xBD, 0xD0, 0xBE];
      expect(tekstUitOnbekend([...'TITLE "'.codeUnits, ...kino, ...'"'.codeUnits]),
          'TITLE "Кино"');
      // Met een BOM ervoor: die is een verklaring en verdwijnt uit de tekst.
      expect(tekstUitOnbekend([0xEF, 0xBB, 0xBF, ...kino]), 'Кино');
    });

    test('DE KERN: een cue in cp1251 levert leesbare namen', () {
      // Dit is waarom er geen latin-1-vangnet onder mag liggen: latin-1 lukt ALTIJD, en dan krijg je
      // stilletjes onzin in plaats van een fout.
      const blad = 'FILE "x.flac" WAVE\n TRACK 01 AUDIO\n  TITLE "Кино"\n  INDEX 01 00:00:00\n';
      final bytes = blad.runes.map((r) => cp1251Byte(r)!).toList();
      expect(leesCueBytes(bytes)!.nummers.single.titel, 'Кино');
    });
  });
}
