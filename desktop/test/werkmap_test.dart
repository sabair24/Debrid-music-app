/// Waar aria2 mag schrijven, en waarom dat niet in de doelmap is.
///
/// **Waarom dit bestaat.** Gemeld op 29-08-2026 met Tears For Fears — Songs From The Big Chair
/// (Deluxe Edition): twee nummers "Mislukt", met deze twee meldingen eronder:
///
///     Failed to open the file D:/Flac music 2024/DebridMusic Downloads/Tears For Fears - Songs
///     From The Big Chair (Deluxe Edition) (Deluxe) (1985 Pop Rock) [Flac 16-44]/Tears For Fears -
///     Songs From The Big Chair (Deluxe Edition) (Deluxe) (1985 Pop Rock) [Flac 16-44]/01. Tears
///     For Fears - Shout.flac, cause: File I/O error 3
///
///     … exists, but a control file(*.aria2) does not exist.
///
/// De eerste is Windows' ERROR_PATH_NOT_FOUND: 234 tekens, en de grens ligt op 260. De plaatnaam
/// staat er TWEE keer in — één keer omdat de app de doelmap zo noemt, en één keer omdat aria2 een
/// map maakt met de naam van de torrent. De tweede melding is het gevolg: het halve bestand bleef
/// staan zonder administratie, en daarmee was die plaat voorgoed dicht.
///
/// Deze toets legt vast dat aria2 in een korte map werkt. Een naam die er stiekem weer bij komt
/// levert geen foutmelding op maar een plaat die niet te downloaden is.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';

void main() {
  // Precies het geval van de melding.
  const naam = 'Tears For Fears - Songs From The Big Chair (Deluxe Edition) (Deluxe) '
      '(1985 Pop Rock) [Flac 16-44]';
  const hash = '3b2a1f9e77c04d5188aa2b6c9f0e1d3a4b5c6d7e';

  // **De paden worden hier met de scheidingsteken van het PLATFORM gebouwd, en dat is niet netjes
  // doen om het netjes doen.** `werkMapPad` gebruikt `doelMap.parent`, en wat een ouder is bepaalt
  // het platform: op Linux heeft `D:\Flac music 2024\...` geen enkele scheiding, dus is het hele
  // ding een bestandsnaam en is de ouder `.`. Deze toets stond daardoor rood in de bouwstraat -
  // zes toetsen lang, tien uitleveringen lang geen APK - terwijl hij hier op Windows groen was.
  //
  // De GRENS waar hij over gaat blijft die van Windows (260 tekens); alleen de vorm van de paden
  // volgt de machine waarop hij draait.
  String p(List<String> delen) => delen.join(Platform.pathSeparator);
  final basis = p(['D:', 'Flac music 2024', 'DebridMusic Downloads']);
  final doel = Directory(p([basis, naam]));

  test('DE KERN: aria2 werkt NAAST de doelmap, niet erin', () {
    final werk = werkMapPad(doel, hash, naam);

    expect(werk, p([basis, torrentWerkMap, '3b2a1f9e']));
    expect(werk, isNot(contains(naam)), reason: 'anders staat de plaatnaam er weer dubbel in');
    // In een map die de bibliotheekscanner overslaat. Zonder dat komen de halve bestanden die aria2
    // aan het binnenhalen is gewoon in je bibliotheek — gemeld als "er komen liedjes bij die ik
    // nooit heb aangeklikt".
    expect(werk, contains('${Platform.pathSeparator}$torrentWerkMap${Platform.pathSeparator}'));
  });

  test('en daarmee past het pad ruim binnen wat Windows aankan', () {
    final werk = werkMapPad(doel, hash, naam);
    // Wat aria2 er zelf onder zet: zijn eigen map met de torrentnaam, en daarin het bestand.
    final volledig = p([werk, naam, '01. Tears For Fears - Shout.flac']);
    final oud = p([doel.path, naam, '01. Tears For Fears - Shout.flac']);

    expect(oud.length, greaterThan(220), reason: 'zo lang was het pad dat omviel');
    expect(volledig.length, lessThan(230), reason: 'en zoveel korter is het nu');
    // Ruim onder de grens, niet er net onder: er komt bij aria2 nog `.aria2` achteraan.
    expect(volledig.length, lessThan(260 - 20));
  });

  test('zonder infohash valt hij terug op de naam, en blijft de map kort', () {
    final werk = werkMapPad(doel, '', naam);

    expect(werk.length, lessThan(doel.path.length));
    expect(werk, startsWith(p([basis, torrentWerkMap, ''])));
    expect(werk.split(Platform.pathSeparator).last.length, 8, reason: 'acht tekens uit de naam');
  });

  group('de laatste map van een pad', () {
    test('aria2 schrijft met voorwaartse strepen, ook op Windows', () {
      // Precies wat `tellStatus` teruggeeft. Splitsen op alleen `\` maakt hiervan één stuk, en dan
      // wordt het HELE pad de mapnaam van het bestand — 29 MB onder een onleesbare naam, in de map
      // waar de bibliotheek uit leest.
      expect(
          laatsteMap('D:/Flac music 2024/DebridMusic Downloads/.dm-6f948bec/'
              'Tears For Fears - Songs From The Big Chair (Deluxe Edition)'),
          'Tears For Fears - Songs From The Big Chair (Deluxe Edition)');
    });

    test('en met terugwaartse strepen ook', () {
      expect(laatsteMap(r'D:\Muziek\Downloads\CD2'), 'CD2');
    });

    test('een pad dat op een streep eindigt telt die niet mee', () {
      expect(laatsteMap('D:/Muziek/CD2/'), 'CD2');
      expect(laatsteMap(''), '');
    });
  });

  test('twee nummers van dezelfde plaat delen dezelfde werkmap', () {
    // Anders haalt aria2 dezelfde torrent twee keer binnen, en telt hij hem als dubbel.
    expect(werkMapPad(doel, hash, naam), werkMapPad(doel, hash, 'een andere naam'));
  });
}
