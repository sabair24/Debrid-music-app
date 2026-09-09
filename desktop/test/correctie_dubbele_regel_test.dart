/// Eén bestand, één correctieregel — ook als de schrijfwijze onderweg verandert.
///
/// **GEMETEN op 09-09-2026 in Sabers eigen `corrections.json`**, na twee keer een uitgave vastzetten
/// op Adele *30*:
///
///     "…\01 - Strangers by Nature.flac" : {"artist":"Adele","album":"30","release":"21021802"}
///     "…\01 - Strangers By Nature.flac" : {"artist":"Adele","album":"30","release":"21021802"}
///
/// Op Windows is dat één bestand. De eerste correctie schreef de titel van de uitgave in het bestand
/// (`by` werd `By`), de tweede maakte daar een nieuwe regel voor — en welke van de twee de pin droeg
/// hing af van de volgorde in het bestand. Zo verdween een zojuist vastgezette deluxe achter de oude
/// standaarduitgave, zonder één melding: het scherm toonde na "Toepassen" de goede tracklijst, en na
/// een herstart weer de verkeerde.
///
/// `LibraryStore._correctionsFor` bestond al en waarschuwde er in zijn eigen uitleg zelfs voor;
/// `applyCorrection` ging er alleen omheen met een kale `putIfAbsent`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/settings.dart';

void main() {
  late Directory scratch;
  late Directory muziek;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_dubbel_');
    muziek = Directory('${scratch.path}${Platform.pathSeparator}muziek')..createSync();
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('een correctie op een andere schrijfwijze schrijft GEEN tweede regel', () async {
    // Alleen zinvol waar het bestandssysteem zelf geen onderscheid maakt.
    if (!(Platform.isWindows || Platform.isMacOS)) return;

    final pad = '${muziek.path}${Platform.pathSeparator}01 - Strangers By Nature.flac';
    File(pad).writeAsBytesSync([0]);
    final andersGeschreven =
        '${muziek.path}${Platform.pathSeparator}01 - Strangers by Nature.flac';

    // De regel die er al stond, onder de OUDE schrijfwijze, met de oude pin.
    File('${scratch.path}${Platform.pathSeparator}corrections.json').writeAsStringSync(jsonEncode({
      andersGeschreven: {'artist': 'Adele', 'album': '30', 'release': '21021802'},
    }));

    final lib = LibraryStore()
      ..configDirOverride = scratch.path
      ..rootPath = muziek.path;
    await lib.loadCorrections();
    lib.tracks.add(Track(
      path: pad,
      title: 'Strangers By Nature',
      artist: 'Adele',
      album: '30',
      trackNo: 1,
      isFlac: true,
    ));
    lib.rebuildAlbums();

    await lib.applyCorrection(lib.albums.single, AppSettings(), discogsRelease: 21040684);
    await lib.saveCorrectionsNow();

    final op = jsonDecode(
            File('${scratch.path}${Platform.pathSeparator}corrections.json').readAsStringSync())
        as Map<String, dynamic>;
    final regels = op.keys.where((k) => k.toLowerCase() == pad.toLowerCase()).toList();
    expect(regels.length, 1, reason: 'één bestand hoort één regel te hebben');
    expect((op[regels.single] as Map)['release'], '21040684',
        reason: 'de zojuist vastgezette uitgave, niet de oude die toevallig eerst stond');
    expect((op[regels.single] as Map)['artist'], 'Adele',
        reason: 'en wat er al stond blijft staan');
  });
}
