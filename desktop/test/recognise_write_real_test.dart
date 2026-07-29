// Geen 'live'-tag: die staat voor tests die de luidsprekers nodig hebben en worden overal
// overgeslagen. Deze heeft alleen de muziekmap nodig en slaat zichzelf over als die er niet is, dus
// hij kan gewoon in de gewone run mee.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

/// Schrijven wat de audio zegt, op een KOPIE van een echt bestand uit de bibliotheek.
///
/// Buiten de gewone run omdat het die bibliotheek nodig heeft, maar het is het enige dat bewijst dat
/// dit pad een echte ripper-uitvoer overleeft -- met zijn afbeeldingsblok, seektable en padding --
/// en dat het alleen de twee velden aanraakt die het hoort aan te raken.
void main() {
  test('artiest en titel worden geschreven, de rest blijft ongemoeid', () async {
    final root = Directory(r'D:\Flac music 2024');
    if (!root.existsSync()) {
      markTestSkipped('bibliotheek niet aanwezig');
      return;
    }
    final src = root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .firstWhere((f) =>
            f.path.toLowerCase().endsWith('.flac') && f.lengthSync() > 5 * 1024 * 1024);

    final dir = Directory.systemTemp.createTempSync('herken');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    setAppDirForTest(dir.path);
    final copy = src.copySync('${dir.path}${Platform.pathSeparator}t.flac');

    final voor = readFlacRawFields(copy);
    final voorBytes = copy.readAsBytesSync().length;

    final lib = LibraryStore()
      ..configDirOverride = dir.path
      ..rootPath = dir.path;
    final t = Track(
      path: copy.path,
      title: 'Wat er nu staat',
      artist: 'Various Artists',
      album: voor['album'] ?? 'Album',
      trackNo: 6,
      isFlac: true,
    );

    final r = await lib.applyRecognised({
      t: (artist: 'Lil’ Kim & Phil Collins', title: 'In the Air Tonite (Boogieman radio version)'),
    });
    expect(r.failed, isEmpty, reason: 'een kopie in temp houdt niemand open');
    expect(r.written, 1);

    final na = readFlacRawFields(copy);
    expect(na['artist'], 'Lil’ Kim & Phil Collins');
    expect(na['title'], 'In the Air Tonite (Boogieman radio version)');

    // Alles wat AcoustID niet weet, blijft van het bestand. Dat is het hele punt van de smalle
    // schrijfactie: welke opname dit is zegt niets over welke persing deze kopie is.
    for (final veld in ['album', 'albumartist', 'tracknumber', 'tracktotal', 'date']) {
      expect(na[veld], voor[veld], reason: '$veld hoort niet aangeraakt te zijn');
    }
    // Het afbeeldingsblok en de audio overleven: de schrijver herbouwt alleen het commentaarblok.
    expect((copy.readAsBytesSync().length - voorBytes).abs(), lessThan(4096),
        reason: 'alleen het commentaarblok mag van grootte veranderen');

    // En terug. Een veld dat er niet was hoort weer weg te zijn, niet op onze waarde te blijven.
    final terug = await lib.undoTagWrites(Album(t.album, t.artist, [t]));
    expect(terug.failed, isEmpty);
    expect(terug.restored, 1);
    final herstel = readFlacRawFields(copy);
    expect(herstel['artist'], voor['artist']);
    expect(herstel['title'], voor['title']);
  });
}
