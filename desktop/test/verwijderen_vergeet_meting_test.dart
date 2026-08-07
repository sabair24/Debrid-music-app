/// Een gewist bestand mag geen meting achterlaten.
///
/// Twee redenen, en de tweede is de vervelende. Ten eerste telt "701 onderzocht" anders spoken mee.
/// Ten tweede erft een pad dat later opnieuw gebruikt wordt — en dat gebeurt, want de app noemt een
/// vervanger naar het bestand dat hij vervangt — het oordeel van een héél ander bestand. Dan staat
/// er een oranje merkje bij een nummer dat nooit gemeten is.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

const _afgekapt = Echtheidsoordeel(
  bits: Bitdiepte.spreektNietTegen,
  boven: Bovenband.onbekend,
  band: Bandbreedte.afgekapt,
  afkapHz: 20040,
  wandDb: 64,
  vensters: 32,
);

void main() {
  late Directory root;
  late LibraryStore lib;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dm_wis_');
    setAppDirForTest(root.path);
    resetEchtheidVoorTest();
    await laadEchtheid();
    lib = LibraryStore()..configDirOverride = '${root.path}${Platform.pathSeparator}_cfg';
  });

  tearDown(() {
    resetEchtheidVoorTest();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  File maak(String naam) {
    final f = File('${root.path}${Platform.pathSeparator}$naam')..writeAsBytesSync(List.filled(2048, 7));
    return f;
  }

  Track tr(String pad) => Track(
        path: pad,
        title: 'Where Have You Been',
        artist: 'Rihanna',
        album: 'Talk That Talk',
        trackNo: 2,
        duration: const Duration(seconds: 220),
        isFlac: true,
      );

  test('van schijf wissen wist ook de meting', () async {
    final f = maak('slecht.flac');
    lib.tracks.add(tr(f.path));
    await onthoudOordeel(f.path, _afgekapt);
    expect(bewezenNep(f.path), isTrue);

    final n = await lib.removeTracks([f.path], fromDisk: true);
    expect(n, 1);
    expect(f.existsSync(), isFalse);
    expect(gemeten(f.path), isNull, reason: 'het bestand is weg, de meting slaat nergens meer op');
  });

  test('alleen uit de bibliotheek halen laat de meting staan', () async {
    // Het bestand blijft op schijf, dus de meting klopt nog steeds. Hem hier ook wissen zou een
    // dure meting weggooien voor iets wat de gebruiker alleen uit het zicht wilde hebben.
    final f = maak('verborgen.flac');
    lib.tracks.add(tr(f.path));
    await onthoudOordeel(f.path, _afgekapt);

    await lib.removeTracks([f.path], fromDisk: false);
    expect(f.existsSync(), isTrue);
    expect(gemeten(f.path), isNotNull);
  });

  test('een pad dat opnieuw gebruikt wordt erft niets van zijn voorganger', () async {
    // Dit is het geval dat pijn doet. De app noemt een vervanger naar het bestand dat hij vervangt,
    // dus hetzelfde pad krijgt een ander bestand — en zonder de vorige regel zou dat schone bestand
    // het oordeel van de betrapte voorganger dragen.
    final f = maak('02 - Where Have You Been.flac');
    lib.tracks.add(tr(f.path));
    await onthoudOordeel(f.path, _afgekapt);
    await lib.removeTracks([f.path], fromDisk: true);

    maak('02 - Where Have You Been.flac'); // de vervanger, zelfde naam
    expect(gemeten(f.path), isNull);
    expect(bewezenNep(f.path), isFalse, reason: 'anders draagt de goede kopie het merkje van de slechte');
  });
}
