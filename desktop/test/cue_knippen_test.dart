/// Eén albumbestand opknippen: welk bestand, welke stukken, welke opdracht.
///
/// **Waarom dit bestaat.** Het knippen zelf draait ffmpeg over een bestand van een gigabyte, en dat
/// gebeurt hier niet — geen ffmpeg, geen schijf, geen toestel. Wat wél te meten valt is het
/// denkwerk eromheen, en dat is precies waar dit stil fout gaat:
///
/// * een cue die naar `album.wav` wijst terwijl er `album.flac` ligt — dan wordt er niets gevonden
///   en gebeurt er niets, zonder een enkele foutmelding;
/// * `-ss` aan de verkeerde kant van `-i`, wat op nummer twaalf minuten kost in plaats van niets;
/// * twee nummers met dezelfde titel, waarvan de tweede de eerste overschrijft — dan is er een
///   nummer weg en telt niemand na.
///
/// Elk van die drie levert een plaat op die er *bijna* goed uitziet. Dat is het gevaarlijke soort.
library;

import 'package:debridmusic/cue_knippen.dart';
import 'package:debridmusic/cuesheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een gewone image-cue: één bestand, vier nummers.
const _blad = '''REM GENRE Pop
REM DATE 2017
PERFORMER "P!nk"
TITLE "Beautiful Trauma"
FILE "P!nk - Beautiful Trauma.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Beautiful Trauma"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Barbies"
    INDEX 01 04:32:00
  TRACK 03 AUDIO
    TITLE "What About Us"
    PERFORMER "P!nk & Iemand"
    INDEX 00 08:00:00
    INDEX 01 08:02:00
  TRACK 04 AUDIO
    TITLE "But We Lost It"
    INDEX 01 12:15:37
''';

CueBlad get _gelezen => leesCue(_blad)!;

void main() {
  group('DE KERN: welk bestand op schijf bedoelt de cue?', () {
    test('gewoon dezelfde naam', () {
      final plan = knipPlan(
          blad: _gelezen,
          bestandenInMap: ['P!nk - Beautiful Trauma.flac', 'album.cue', 'cover.jpg']);
      expect(plan, hasLength(4));
      expect(plan.every((k) => k.bronNaam == 'P!nk - Beautiful Trauma.flac'), isTrue);
    });

    test('DE KERN: de cue zegt .wav, er ligt .flac', () {
      // Dit is eerder regel dan uitzondering: een blad dat tijdens het rippen gemaakt is wijst naar
      // het wav-bestand van vóór het inpakken. Zonder deze weg vindt hij niets en gebeurt er niets.
      final blad = leesCue(_blad.replaceAll('.flac"', '.wav"'))!;
      final plan = knipPlan(
          blad: blad, bestandenInMap: ['P!nk - Beautiful Trauma.flac', 'album.cue']);
      expect(plan, hasLength(4));
      expect(plan.first.bronNaam, 'P!nk - Beautiful Trauma.flac');
    });

    test('DE KERN: een naam die onderweg gesaneerd is', () {
      // `P!nk - Beautiful Trauma.flac` kan als `P_nk - Beautiful Trauma.flac` op schijf staan zodra
      // er een teken in zat dat Windows weigert. Dan matcht geen naam en geen stam — maar er is één
      // blad en één albumbestand, dus er valt niets te verwarren.
      final plan = knipPlan(
          blad: _gelezen,
          bestandenInMap: ['P_nk - Beautiful Trauma.flac', 'album.cue', 'folder.jpg']);
      expect(plan, hasLength(4));
      expect(plan.first.bronNaam, 'P_nk - Beautiful Trauma.flac');
    });

    test('twee albumbestanden en geen naam die past: niets doen', () {
      // Hier zou raden een verkeerde plaat opknippen. Niets doen laat de download staan zoals hij
      // was, en dat is te herstellen.
      final plan = knipPlan(
          blad: _gelezen, bestandenInMap: ['cd1.flac', 'cd2.flac', 'album.cue']);
      expect(plan, isEmpty);
    });

    test('helemaal geen audio in de map', () {
      expect(knipPlan(blad: _gelezen, bestandenInMap: ['album.cue']), isEmpty);
    });
  });

  group('DE KERN: wanneer er NIET geknipt wordt', () {
    test('een cue naast losse nummers blijft met rust', () {
      // Dit is de goede situatie: twaalf bestanden en een blad erbij. Wie hier gaat knippen haalt
      // een geldige plaat door ffmpeg voor niets, en overschrijft mogelijk wat er al stond.
      const los = '''FILE "01 - Een.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Een"
    INDEX 01 00:00:00
FILE "02 - Twee.flac" WAVE
  TRACK 02 AUDIO
    TITLE "Twee"
    INDEX 01 00:00:00
''';
      final plan = knipPlan(
          blad: leesCue(los)!, bestandenInMap: ['01 - Een.flac', '02 - Twee.flac', 'a.cue']);
      expect(plan, isEmpty, reason: 'één nummer per bestand valt niets te knippen');
    });
  });

  group('de stukken zelf', () {
    test('start en duur komen uit het blad, in seconden', () {
      final plan = knipPlan(blad: _gelezen, bestandenInMap: ['P!nk - Beautiful Trauma.flac']);
      expect(plan[0].start, 0);
      expect(plan[1].start, closeTo(4 * 60 + 32, 0.001));
      expect(plan[0].duur, closeTo(4 * 60 + 32, 0.001));
    });

    test('DE KERN: het laatste nummer heeft geen duur', () {
      // Tot het einde van het bestand, en die lengte weet alleen ffmpeg. Een verzonnen duur kapt
      // het laatste nummer af, en dat hoor je pas als je het een keer helemaal uitluistert.
      final plan = knipPlan(blad: _gelezen, bestandenInMap: ['P!nk - Beautiful Trauma.flac']);
      expect(plan.last.duur, isNull);
    });

    test('INDEX 00 telt niet mee als begin', () {
      // Nummer 3 heeft een aanloop op 8:00 en begint op 8:02. Knippen op de aanloop plakt de stilte
      // vóór dit nummer in plaats van achter het vorige.
      final plan = knipPlan(blad: _gelezen, bestandenInMap: ['P!nk - Beautiful Trauma.flac']);
      expect(plan[2].start, closeTo(8 * 60 + 2, 0.001));
    });

    test('de labels: albumartiest van de plaat, artiest van het nummer', () {
      final plan = knipPlan(blad: _gelezen, bestandenInMap: ['P!nk - Beautiful Trauma.flac']);
      expect(plan[0].artiest, 'P!nk', reason: 'geen eigen PERFORMER, dus die van de plaat');
      expect(plan[2].artiest, 'P!nk & Iemand', reason: 'wel een eigen PERFORMER');
      expect(plan.every((k) => k.albumArtiest == 'P!nk'), isTrue);
      expect(plan.every((k) => k.album == 'Beautiful Trauma'), isTrue);
      expect(plan.first.jaar, '2017');
      expect(plan.first.genre, 'Pop');
      expect(plan.every((k) => k.totaal == 4), isTrue);
    });
  });

  group('DE KERN: de namen van de nieuwe bestanden', () {
    test('genummerd, met de titel erachter', () {
      final plan = knipPlan(blad: _gelezen, bestandenInMap: ['P!nk - Beautiful Trauma.flac']);
      expect(plan.map((k) => k.doelNaam), [
        '01 - Beautiful Trauma.flac',
        '02 - Barbies.flac',
        '03 - What About Us.flac',
        '04 - But We Lost It.flac',
      ]);
    });

    test('DE KERN: twee nummers die op dezelfde naam uitkomen overschrijven elkaar niet', () {
      // Een blad met twee keer hetzelfde nummer erin is niet verzonnen: het gebeurt bij een
      // handgemaakte cue en bij een verkeerd samengevoegde dubbel-cd. Zonder de hernoeming staat er
      // na afloop één nummer minder in je bibliotheek, en telt niemand na.
      const dubbel = '''TITLE "Iets"
FILE "x.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Intro"
    INDEX 01 00:00:00
  TRACK 01 AUDIO
    TITLE "Intro"
    INDEX 01 01:00:00
  TRACK 02 AUDIO
    TITLE "Slot"
    INDEX 01 02:00:00
''';
      final plan = knipPlan(blad: leesCue(dubbel)!, bestandenInMap: ['x.flac']);
      expect(plan.map((k) => k.doelNaam),
          ['01 - Intro.flac', '01 - Intro (2).flac', '02 - Slot.flac']);
    });

    test('DE KERN: een naam die al in de map staat wordt niet overschreven', () {
      const bots = '''TITLE "Iets"
FILE "x.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Een"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Twee"
    INDEX 01 01:00:00
''';
      final plan = knipPlan(
          blad: leesCue(bots)!, bestandenInMap: ['x.flac', '01 - Een.flac']);
      expect(plan.first.doelNaam, isNot('01 - Een.flac'));
      expect(plan.first.doelNaam, '01 - Een (2).flac');
    });

    test('tekens die Windows weigert gaan eruit', () {
      expect(veiligeNaam('AC/DC: Live?'), 'AC_DC_ Live_');
      expect(veiligeNaam('Iets.'), 'Iets', reason: 'een naam op een punt kan Windows niet aanmaken');
      expect(veiligeNaam('   '), 'Naamloos');
    });
  });

  group('een dubbel-cd als twee images', () {
    const twee = '''TITLE "Verzameling"
PERFORMER "Diverse"
FILE "cd1.flac" WAVE
  TRACK 01 AUDIO
    TITLE "A"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "B"
    INDEX 01 03:00:00
FILE "cd2.flac" WAVE
  TRACK 01 AUDIO
    TITLE "C"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "D"
    INDEX 01 02:30:00
''';

    test('allebei de schijven worden geknipt', () {
      final plan = knipPlan(blad: leesCue(twee)!, bestandenInMap: ['cd1.flac', 'cd2.flac']);
      expect(plan, hasLength(4));
      expect(plan.where((k) => k.bronNaam == 'cd1.flac'), hasLength(2));
      expect(plan.where((k) => k.bronNaam == 'cd2.flac'), hasLength(2));
    });

    test('DE KERN: het laatste nummer van schijf één loopt tot het einde van schijf één', () {
      // De tijd van het eerste nummer op schijf twee staat in een ánder bestand. Wie die als einde
      // neemt, kapt het laatste nummer van schijf één af op nul seconden.
      final plan = knipPlan(blad: leesCue(twee)!, bestandenInMap: ['cd1.flac', 'cd2.flac']);
      expect(plan.firstWhere((k) => k.titel == 'B').duur, isNull);
    });

    test('elke schijf telt zijn eigen nummers', () {
      final plan = knipPlan(blad: leesCue(twee)!, bestandenInMap: ['cd1.flac', 'cd2.flac']);
      expect(plan.every((k) => k.totaal == 2), isTrue);
    });
  });

  group('DE KERN: de opdracht voor ffmpeg', () {
    Knip knipVoor({double? duur}) => Knip(
          bronNaam: 'x.flac',
          doelNaam: '02 - Barbies.flac',
          start: 272.44,
          duur: duur,
          titel: 'Barbies',
          artiest: 'P!nk',
          album: 'Beautiful Trauma',
          albumArtiest: 'P!nk',
          nummer: 2,
          totaal: 4,
          jaar: '2017',
          genre: 'Pop',
        );

    test('DE KERN: -ss staat vóór -i', () {
      // Erachter decodeert ffmpeg het hele bestand tot aan het startpunt. Op een image van een
      // gigabyte is dat bij nummer twaalf minuten wachten, twaalf keer achter elkaar — en het werkt
      // wél, dus niets wijst je erop.
      final a = ffmpegArgumenten(knipVoor(duur: 60), bronPad: '/m/x.flac', doelPad: '/m/u.flac');
      expect(a.indexOf('-ss'), lessThan(a.indexOf('-i')));
    });

    test('DE KERN: een duur met -t, nooit -to', () {
      // Met een -ss vóór de invoer telt -to in de ene ffmpeg-versie vanaf het bestandsbegin en in de
      // andere vanaf het startpunt. Dat verschil hoor je pas als een nummer een halve seconde duurt.
      final a = ffmpegArgumenten(knipVoor(duur: 60), bronPad: '/m/x.flac', doelPad: '/m/u.flac');
      expect(a, contains('-t'));
      expect(a, isNot(contains('-to')));
      expect(a[a.indexOf('-t') + 1], '60.000000');
    });

    test('het laatste nummer krijgt helemaal geen duur mee', () {
      final a = ffmpegArgumenten(knipVoor(), bronPad: '/m/x.flac', doelPad: '/m/u.flac');
      expect(a, isNot(contains('-t')));
    });

    test('de starttijd gaat mee met zes cijfers achter de komma', () {
      // Een cue telt in frames van 1/75 seconde. Afronden op hele seconden zet het begin van het
      // volgende nummer aan het eind van het vorige, en dat is precies het klikje dat je hoort.
      final a = ffmpegArgumenten(knipVoor(), bronPad: '/m/x.flac', doelPad: '/m/u.flac');
      expect(a[a.indexOf('-ss') + 1], '272.440000');
    });

    test('DE KERN: de labels van het grote bestand gaan eraf', () {
      // Die zeggen dat dit "Beautiful Trauma" heet — de PLAAT. Zonder dit heten alle twaalf de
      // nummers zo, en dan is er in je bibliotheek niets opgeschoten.
      final a = ffmpegArgumenten(knipVoor(), bronPad: '/m/x.flac', doelPad: '/m/u.flac');
      expect(a.indexOf('-map_metadata'), greaterThan(-1));
      expect(a[a.indexOf('-map_metadata') + 1], '-1');
    });

    test('de labels die er wél op komen', () {
      final a = ffmpegArgumenten(knipVoor(), bronPad: '/m/x.flac', doelPad: '/m/u.flac');
      expect(a, contains('TITLE=Barbies'));
      expect(a, contains('ARTIST=P!nk'));
      expect(a, contains('ALBUM=Beautiful Trauma'));
      expect(a, contains('ALBUMARTIST=P!nk'));
      expect(a, contains('TRACKNUMBER=2'));
      expect(a, contains('TRACKTOTAL=4'));
      expect(a, contains('DATE=2017'));
      expect(a, contains('GENRE=Pop'));
    });

    test('er komt FLAC uit, en het doel staat achteraan', () {
      final a = ffmpegArgumenten(knipVoor(), bronPad: '/m/x.flac', doelPad: '/m/u.flac');
      expect(a[a.indexOf('-c:a') + 1], 'flac');
      expect(a.last, '/m/u.flac');
    });

    test('een leeg jaar of genre levert geen leeg label op', () {
      const kaal = Knip(
        bronNaam: 'x.ape',
        doelNaam: '01 - Iets.flac',
        start: 0,
        duur: null,
        titel: 'Iets',
        artiest: 'Iemand',
        album: 'Ergens',
        albumArtiest: '',
        nummer: 1,
        totaal: 1,
      );
      final a = ffmpegArgumenten(kaal, bronPad: '/m/x.ape', doelPad: '/m/u.flac');
      expect(a.any((s) => s.startsWith('DATE=')), isFalse);
      expect(a.any((s) => s.startsWith('GENRE=')), isFalse);
      expect(a.any((s) => s.startsWith('ALBUMARTIST=')), isFalse);
    });
  });

  group('DE KERN: eerst kijken of dit het albumbestand wél IS', () {
    // Gemeld op 27-08-2026, met schermafdruk: *"Knippen mislukt: nummer 1: [out#0/flac @ …] Output
    // file does not contain any stream"*. Het blad hoort bij de plaat, maar het bestand dat ernaast
    // ligt hoeft dat niet te zijn — haal je via "Kies nummer" één nummer uit een torrent, dan komt
    // het blad wél mee en staat er één cue naast één audiobestand van vijf minuten.

    /// Zoals ffmpeg het opschrijft als je hem een bestand geeft en geen uitvoer vraagt.
    String kop(String duur) => '''
Input #0, flac, from 'CD3.flac':
  Duration: $duur, start: 0.000000, bitrate: 921 kb/s
  Stream #0:0: Audio: flac, 44100 Hz, stereo, s16
At least one output file must be specified''';

    test('de duur wordt uit ffmpegs eigen kop gelezen', () {
      expect(duurUitFfmpeg(kop('01:12:40.53')), closeTo(4360.53, 0.01));
      expect(duurUitFfmpeg(kop('00:05:14.00')), closeTo(314, 0.01));
      expect(duurUitFfmpeg(kop('00:00:00.00')), 0);
    });

    test('honderdsten mogen ontbreken', () {
      expect(duurUitFfmpeg(kop('00:03:20')), 200);
    });

    test('geen duur betekent geen antwoord, geen nul', () {
      // Het verschil is alles: nul zou "een leeg bestand" zijn, null is "ik weet het niet". Bij
      // `Duration: N/A` zit er geen bruikbare audio in, en dan mag er zeker niet geknipt worden.
      expect(duurUitFfmpeg(kop('N/A')), isNull);
      expect(duurUitFfmpeg('ffmpeg: geen idee wat dit is'), isNull);
      expect(duurUitFfmpeg(''), isNull);
      expect(duurUitFfmpeg(null), isNull);
    });

    test('een blad dat verder loopt dan het bestand is niet dit bestand', () {
      // Het echte geval: een blad tot 1:12:40 naast een gedownload nummer van 5:14.
      expect(duurtLangGenoeg(314, 4360), isFalse);
    });

    test('een bestand dat het hele blad dekt mag geknipt worden', () {
      expect(duurtLangGenoeg(4400, 4360), isTrue);
    });

    test('een paar seconden tekort is nog steeds hetzelfde bestand', () {
      // Een rip die één seconde korter uitviel dan het blad zegt is normaal; daar hoort geen
      // weigering op te volgen, want dan wordt er nooit meer iets geknipt.
      expect(duurtLangGenoeg(4358, 4360), isTrue);
      expect(duurtLangGenoeg(4300, 4360), isFalse, reason: 'een minuut tekort is een ander bestand');
    });

    test('zonder duur wordt er niet geknipt', () {
      // Een lege plaatshouder van nul bytes komt hier uit. Daar ging ffmpeg vroeger op stuk.
      expect(duurtLangGenoeg(null, 0), isFalse);
      expect(duurtLangGenoeg(null, 4360), isFalse);
    });
  });
}
