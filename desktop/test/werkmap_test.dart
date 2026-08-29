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

void main() {
  // Precies het geval van de melding.
  const naam = 'Tears For Fears - Songs From The Big Chair (Deluxe Edition) (Deluxe) '
      '(1985 Pop Rock) [Flac 16-44]';
  const hash = '3b2a1f9e77c04d5188aa2b6c9f0e1d3a4b5c6d7e';
  final doel = Directory(r'D:\Flac music 2024\DebridMusic Downloads\' + naam);

  test('DE KERN: aria2 werkt NAAST de doelmap, niet erin', () {
    final werk = werkMapPad(doel, hash, naam);

    expect(werk, r'D:\Flac music 2024\DebridMusic Downloads\.dm-3b2a1f9e');
    expect(werk, isNot(contains(naam)), reason: 'anders staat de plaatnaam er weer dubbel in');
  });

  test('en daarmee past het pad ruim binnen wat Windows aankan', () {
    final werk = werkMapPad(doel, hash, naam);
    // Wat aria2 er zelf onder zet: zijn eigen map met de torrentnaam, en daarin het bestand.
    final volledig = '$werk\\$naam\\01. Tears For Fears - Shout.flac';
    final oud = '${doel.path}\\$naam\\01. Tears For Fears - Shout.flac';

    expect(oud.length, greaterThan(220), reason: 'zo lang was het pad dat omviel');
    expect(volledig.length, lessThan(230), reason: 'en zoveel korter is het nu');
    // Ruim onder de grens, niet er net onder: er komt bij aria2 nog `.aria2` achteraan.
    expect(volledig.length, lessThan(260 - 20));
  });

  test('zonder infohash valt hij terug op de naam, en blijft de map kort', () {
    final werk = werkMapPad(doel, '', naam);

    expect(werk.length, lessThan(doel.path.length));
    expect(werk, startsWith(r'D:\Flac music 2024\DebridMusic Downloads\.dm-'));
    expect(werk.split(Platform.pathSeparator).last.length, 12, reason: '.dm- plus acht tekens');
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
