/// De staande wens: FLAC is koning, en de app mag het niet opgeven.
///
/// Het gaat hier om het GEDRAG van de lijst, zonder één peer aan te spreken. Wat er misging is
/// gemeten: één jacht van tien minuten die na twintig seconden dood was omdat de enige lossless bron
/// het account geband had, en een dag later stond er wél iemand online.
library;

import 'dart:io';

import 'package:debridmusic/lossless_want.dart';
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:flutter_test/flutter_test.dart';

const _uur = 3600 * 1000;

LosslessWant _w(String artist, String title, {int tries = 0, int lastTryMs = 0, int sinceMs = 0}) =>
    LosslessWant(artist: artist, title: title, tries: tries, lastTryMs: lastTryMs, sinceMs: sinceMs);

void main() {
  group('het ritme', () {
    test('de eerste poging mag meteen', () {
      expect(wachtVoor(0), Duration.zero);
      expect(wensIsAanDeBeurt(_w('a', 'b'), 1000), isTrue);
    });

    test('het wordt ruimer, want de reden beweegt langzaam', () {
      expect(wachtVoor(1), const Duration(minutes: 20));
      expect(wachtVoor(2), const Duration(hours: 2));
      expect(wachtVoor(3), const Duration(hours: 8));
    });

    test('maar het loopt niet eindeloos op — een dag blijft een dag', () {
      // "Over een maand" is hetzelfde als opgeven, en opgeven is precies wat hier niet mag.
      expect(wachtVoor(4), const Duration(days: 1));
      expect(wachtVoor(40), const Duration(days: 1));
      expect(wachtVoor(4000), const Duration(days: 1));
    });

    test('binnen het venster is hij niet aan de beurt, erna wel', () {
      final w = _w('a', 'b', tries: 1, lastTryMs: 0);
      expect(wensIsAanDeBeurt(w, const Duration(minutes: 19).inMilliseconds), isFalse);
      expect(wensIsAanDeBeurt(w, const Duration(minutes: 20).inMilliseconds), isTrue);
    });
  });

  group('de lijst', () {
    late Directory tmp;
    late LosslessWants lijst;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('wensen');
      lijst = LosslessWants('${tmp.path}${Platform.pathSeparator}lossless_wanted.json');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('dezelfde wens twee keer blijft één wens, met zijn eigen ritme', () {
      expect(lijst.want(_w('Sabien Tiels', 'Trein')), isTrue);
      // Zonder dit zou elke nieuwe mp3 van hetzelfde nummer de teller terugzetten, en dan zoekt de
      // app elke twintig minuten opnieuw bij een peer die hem toch niet geeft.
      lijst.update(lijst.all.single.met(tries: 3, lastTryMs: 5 * _uur));
      expect(lijst.want(_w('sabien tiels', 'trein')), isFalse, reason: 'zelfde nummer, andere spelling');
      expect(lijst.all.single.tries, 3, reason: 'het ritme blijft staan');
    });

    test('wie het langst wacht is eerst aan de beurt', () {
      lijst.want(_w('A', 'oud', sinceMs: 1000));
      lijst.want(_w('B', 'nieuw', sinceMs: 9000));
      expect(lijst.due(10 * _uur).map((w) => w.title), ['oud', 'nieuw']);
    });

    test('een wens die nog moet wachten staat niet in de rij', () {
      lijst.want(_w('A', 'net geprobeerd', tries: 2, lastTryMs: 10 * _uur));
      expect(lijst.due(10 * _uur + 1000), isEmpty);
      expect(lijst.due(13 * _uur).length, 1);
    });

    test('een FLAC die je al hebt laat de wens vallen, ook van buiten de app', () {
      // Het echte geval: de gebruiker haalde hem met de native client binnen, in een map die naar de
      // peer heet en onder een andere albumnaam. Zonder deze controle jaagt de app eeuwig op iets wat
      // al op schijf staat.
      lijst.want(_w('Sabien Tiels', 'Trein'));
      lijst.want(_w('Rihanna', 'Loud'));
      final weg = lijst.forgetWhatWeHave((a, t) => t.toLowerCase() == 'trein');
      expect(weg, hasLength(1));
      expect(lijst.all.single.title, 'Loud');
    });

    test('op een verzamelaar telt de UITVOERDER mee, niet de artiest-tag', () {
      // Het geval dat in `hasLossless` als bekende ondergrens beschreven stond. Op een verzamelaar
      // zegt de artiest-tag "Various Artists" — daar is niets mee te vinden in de bibliotheek. De
      // echte naam staat in de bestandsnaam van de peer, en die wordt als `performer` bewaard.
      // Zonder deze tweede vraag bleef de wens eeuwig staan terwijl de FLAC er allang was.
      lijst.want(LosslessWant(
        artist: 'Various Artists',
        title: 'Ecstasy',
        performer: 'Johnny Vicious',
        sinceMs: 0,
      ));
      final gevraagd = <String>[];
      final weg = lijst.forgetWhatWeHave((a, t) {
        gevraagd.add(a);
        return a == 'Johnny Vicious';
      });

      expect(weg, hasLength(1));
      // En "Various Artists" wordt niet eens gevraagd: dat is geen naam maar een mededeling.
      expect(gevraagd, ['Johnny Vicious']);
    });

    test('zonder uitvoerder blijft een verzamelaarswens gewoon staan', () {
      lijst.want(LosslessWant(artist: 'Various Artists', title: 'Ecstasy', sinceMs: 0));

      expect(lijst.forgetWhatWeHave((a, t) => true), isEmpty,
          reason: 'er valt niets te vergelijken, dus niets te laten vervallen');
    });

    test('overleeft een herstart, met ritme en geweigerde peers', () async {
      lijst.want(_w('Sabien Tiels', 'Trein', sinceMs: 42));
      lijst.update(lijst.all.single.met(tries: 2, lastTryMs: 7 * _uur, refused: {'DANY2905': 'banned'}));
      await lijst.save();

      final opnieuw = LosslessWants('${tmp.path}${Platform.pathSeparator}lossless_wanted.json');
      await opnieuw.load();
      final w = opnieuw.all.single;
      expect(w.title, 'Trein');
      expect(w.tries, 2);
      expect(w.sinceMs, 42);
      expect(w.refused['DANY2905'], 'banned');
    });

    test('het gezag van de eerste landing reist mee', () async {
      // Zonder dit landde de eerste echte vondst als "Singles\Onbekende artiest\Daft Punk - One More
      // Time (club mix).flac": de peer stuurde een bestand zonder één tag, en er was niets om op terug
      // te vallen. Een wens die dagen later uitkomt moet weten waar hij hoort.
      lijst.want(LosslessWant(
        artist: 'Daft Punk',
        title: 'One More Time (Club Mix)',
        album: 'One More Time',
        authority: const TrackTags(
            title: 'One More Time (Club Mix)',
            artist: 'Daft Punk',
            album: 'One More Time',
            trackNo: 3,
            trackTotal: 4),
      ));
      await lijst.save();

      final opnieuw = LosslessWants('${tmp.path}${Platform.pathSeparator}lossless_wanted.json');
      await opnieuw.load();
      final a = opnieuw.all.single.authority;
      expect(a, isNotNull, reason: 'anders belandt de FLAC onder "Onbekende artiest"');
      expect(a!.trackNo, 3);
      expect(a.album, 'One More Time');
      expect(a.isAuthoritative, isTrue, reason: 'trackTotal maakt het gezaghebbend, net als bij de mp3');
    });

    test('een wens zonder gezag blijft bruikbaar', () {
      // Oude regels op schijf hebben dit veld niet, en een landing zonder officiële match ook niet.
      expect(_w('A', 'B').authority, isNull);
    });

    test('een lege lijst laat geen bestand achter', () async {
      lijst.want(_w('A', 'B'));
      await lijst.save();
      expect(File('${tmp.path}${Platform.pathSeparator}lossless_wanted.json').existsSync(), isTrue);
      lijst.forget(lijst.all.single.key);
      await lijst.save();
      expect(File('${tmp.path}${Platform.pathSeparator}lossless_wanted.json').existsSync(), isFalse);
    });

    test('rommel op schijf betekent geen wensen, geen uitzondering', () async {
      final f = File('${tmp.path}${Platform.pathSeparator}lossless_wanted.json');
      f.writeAsStringSync('{ dit is geen lijst');
      await lijst.load();
      expect(lijst.count, 0);
    });

    test('een regel zonder artiest of titel wordt overgeslagen', () async {
      final f = File('${tmp.path}${Platform.pathSeparator}lossless_wanted.json');
      f.writeAsStringSync('[{"artist":"","title":"Trein"},{"artist":"A","title":"B"}]');
      await lijst.load();
      expect(lijst.count, 1, reason: 'zonder naam valt er niets te zoeken');
    });

    test('de zoekvraag is wat de gebruiker zelf zou typen', () {
      expect(_w('Sabien Tiels', 'Trein').query, 'Sabien Tiels Trein');
    });
  });

  group('de zoekvraag van een verzamelaar', () {
    test('"Various Artists" gaat er niet in — dan liever de titel alleen', () {
      // Gemeten: "Various Artists Jij Bent Zo Mooi" gaf precies één treffer. Peers noemen hun bestand
      // naar de uitvoerder en nooit naar "Various Artists", dus dat woord maakt de vraag slechter.
      expect(LosslessWant(artist: 'Various Artists', title: 'Jij Bent Zo Mooi').query,
          'Jij Bent Zo Mooi');
    });

    test('de uitvoerder gaat er wél in, en gaat vóór de artiest-tag', () {
      expect(
          const LosslessWant(artist: 'Various Artists', title: 'Jij Bent Zo Mooi', performer: 'Petra')
              .query,
          'Petra Jij Bent Zo Mooi');
    });

    test('elke schrijfwijze van "verzamelaar" wordt herkend', () {
      // "Diverse" staat er kaal bij, en dat is een keuze: op een Nederlandse verzamelaar betekent dat
      // woord "diverse artiesten". Er bestaat ook een rapper Diverse; die valt dan terug op de titel
      // alleen, wat een matige zoekvraag is en geen verkeerde.
      for (final n in ['Various', 'various artists', 'VA', 'V.A.', 'Diverse', 'Diverse artiesten',
        'Unknown Artist', 'Onbekende artiest', '  Various Artists  ']) {
        expect(isVerzamelnaam(n), isTrue, reason: '"$n" is geen artiest');
      }
    });

    test('maar een echte naam blijft een echte naam', () {
      // De grens, en hij is smal met opzet: deze bestaan allemaal en mogen niet wegvallen.
      for (final n in ['Various Cruelties', 'VNV Nation', 'Unknown Mortal Orchestra', 'Diversion']) {
        expect(isVerzamelnaam(n), isFalse, reason: '"$n" is wel een artiest');
      }
    });
  });

  group('de uitvoerder uit een bestandsnaam', () {
    test('de gewone vorm van een peer', () {
      expect(performerFromFilename('5-03 Sabien Tiels - Trein.mp3', 'Trein'), 'Sabien Tiels');
      expect(performerFromFilename('215 - sabien tiels - trein.flac', 'Trein'), 'sabien tiels');
      expect(performerFromFilename('01. Daft Punk - One More Time.flac', 'One More Time'), 'Daft Punk');
    });

    test('een pad ervoor stoort niet', () {
      expect(performerFromFilename(r'd:\muziek\top 100\13 - Petra - Jij Bent Zo Mooi.mp3',
          'Jij Bent Zo Mooi'), 'Petra');
    });

    test('een artiest met een streepje in de naam blijft heel', () {
      expect(performerFromFilename('04 - Jean-Michel Jarre - Oxygene - Part IV.flac', 'Part IV'),
          'Jean-Michel Jarre - Oxygene');
    });

    test('past het staartstuk niet bij de titel, dan liever niets', () {
      // Zonder deze eis is het middenstuk net zo goed een deel van de titel, en dan zoekt de app op
      // een woord dat niemand als artiest kent -- met een geloofwaardig gezicht.
      expect(performerFromFilename('01 - Intro - Iets Anders.flac', 'Iets'), isNull);
      expect(performerFromFilename('Trein.mp3', 'Trein'), isNull, reason: 'geen streepje, geen naam');
      expect(performerFromFilename('13 - Various Artists - Jij Bent Zo Mooi.mp3', 'Jij Bent Zo Mooi'),
          isNull, reason: 'dat is nog steeds geen artiest');
    });
  });

  group('een wens om PRECIES dit bestand', () {
    // Waarom dit bestaat: wie zelf een regel aanklikt doet dat omdat de automaat de verkeerde
    // opname pakte. Kwam die kopie niet binnen, dan is "dan halen we morgen wel iets anders van dat
    // nummer" diezelfde overrule, alleen een dag later.
    const bron = VasteBron(
      username: 'SoundInvestment',
      filename: r'@@abc\2 belgen\trop petit [1985]\01. lena.flac',
      size: 53 * 1000 * 1000,
      sampleRate: 48000,
      bitDepth: 24,
    );

    LosslessWant vast({String artist = '', String title = ''}) =>
        LosslessWant(artist: artist, title: title, exact: bron);

    test('hij overleeft een herstart met bron en al', () {
      final terug = LosslessWant.fromJson(vast(artist: '2 Belgen', title: 'Lena').toJson())!;
      expect(terug.exact, isNotNull);
      expect(terug.exact!.username, 'SoundInvestment');
      expect(terug.exact!.filename, bron.filename);
      expect(terug.exact!.size, bron.size);
      expect(terug.exact!.bitDepth, 24);
      expect(terug.exact!.sampleRate, 48000);
    });

    test('zonder artiest en titel blijft hij bestaan — er valt niets te ZOEKEN, wel aan te kloppen', () {
      // Een download die misging voordat er ook maar één tag gelezen kon worden heeft niets anders
      // dan een naam en een pad. Dat is genoeg om dezelfde peer morgen opnieuw te vragen.
      expect(LosslessWant.fromJson(vast().toJson()), isNotNull);
      // En de gewone wens blijft wél weigeren: zoeken zonder zoekvraag levert rommel op.
      expect(LosslessWant.fromJson(_w('', '').toJson()), isNull);
    });

    test('hij botst niet met de gewone wens om hetzelfde nummer', () {
      final lijst = LosslessWants('${Directory.systemTemp.path}${Platform.pathSeparator}x.json');
      expect(lijst.want(_w('2 Belgen', 'Lena')), isTrue);
      expect(lijst.want(vast(artist: '2 Belgen', title: 'Lena')), isTrue,
          reason: 'anders overschrijft de een de ander, en verdwijnt of de keuze of de jacht');
      expect(lijst.count, 2);
    });

    test('twee keer dezelfde bron blijft één wens', () {
      final lijst = LosslessWants('${Directory.systemTemp.path}${Platform.pathSeparator}y.json');
      expect(lijst.want(vast(artist: '2 Belgen', title: 'Lena')), isTrue);
      expect(lijst.want(vast(artist: 'iets anders', title: 'Lena')), isFalse);
    });

    test('een naamloze wens wordt niet weggegooid door "die heb je al"', () {
      final lijst = LosslessWants('${Directory.systemTemp.path}${Platform.pathSeparator}z.json');
      lijst.want(vast());
      // Twee lege namen matchen anders van alles, en dan verdwijnt de wens meteen weer.
      expect(lijst.forgetWhatWeHave((a, t) => true), isEmpty);
      expect(lijst.count, 1);
    });
  });

  group('de zoekvraag', () {
    // Losgetrokken uit `LosslessWant.query` toen het menu er "Zoeken met Soulseek" bij kreeg: daar
    // geldt precies dezelfde valkuil, en één plek waar hij opgelost is scheelt de tweede fout.
    test('artiest en titel, zoals je het zou typen', () {
      expect(zoekvraagVoorNummer('Get Down', artist: 'Backstreet Boys'),
          'Backstreet Boys Get Down');
    });

    test('"Various Artists" is geen naam en gaat eruit', () {
      // Gemeten: "Various Artists Jij Bent Zo Mooi" gaf één treffer, de titel alleen tientallen.
      expect(zoekvraagVoorNummer('Jij Bent Zo Mooi', artist: 'Various Artists'),
          'Jij Bent Zo Mooi');
      expect(zoekvraagVoorNummer('Trein', artist: 'Onbekende artiest'), 'Trein');
    });

    test('de uitvoerder uit de bestandsnaam wint van de tag', () {
      const pad = r'D:\m\Top 100\13 - Petra - Jij Bent Zo Mooi.mp3';
      expect(
          zoekvraagVoorNummer('Jij Bent Zo Mooi',
              performer: performerFromFilename(pad, 'Jij Bent Zo Mooi'), artist: 'Various Artists'),
          'Petra Jij Bent Zo Mooi');
    });

    test('zonder artiest en zonder uitvoerder blijft de titel over', () {
      expect(zoekvraagVoorNummer('Trein'), 'Trein');
      expect(zoekvraagVoorNummer('Trein', artist: '   '), 'Trein');
    });

    test('een plaat zoekt op artiest en albumtitel', () {
      expect(zoekvraagVoorAlbum('Portishead', 'Dummy'), 'Portishead Dummy');
    });

    test('een verzamelplaat zoekt op de albumtitel alleen', () {
      // Hier is geen bestandsnaam om op terug te vallen, dus is dit het beste wat er is.
      expect(zoekvraagVoorAlbum('Various Artists', 'Now 47'), 'Now 47');
      expect(zoekvraagVoorAlbum('V.A.', 'Now 47'), 'Now 47');
      expect(zoekvraagVoorAlbum('', 'Now 47'), 'Now 47');
    });

    test('en de wens gebruikt dezelfde functie, dus dit bewaakt ook die', () {
      expect(_w('Various Artists', 'Trein').query, 'Trein');
      expect(_w('Sabien Tiels', 'Trein').query, 'Sabien Tiels Trein');
    });
  });
}
