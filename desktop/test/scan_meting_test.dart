/// De meetbank voor het opstarten.
///
/// `start.log` wist van de scan één getal — "scan klaar in 15034ms" — en dat zegt niet WELKE stap die
/// tijd opeet. Deze bank deelt hem op, tegen de échte bibliotheek, zonder venster en zonder CI.
///
/// Wat er al gemeten is met de hand, zodat je weet wat de bodem is:
///
///     775 audiobestanden op D: (een ST1000DM010, dus een harde schijf)
///                                      koud       warm
///       mappen doorlopen                85 ms      78 ms
///       stat op elk bestand             79 ms      14 ms
///       eerste 128 KB van elk lezen   6535 ms     163 ms
///
/// De schijf levert warm dus alle koppen in een zesde van een seconde. Wat de app daarbovenop
/// verbruikt is rekenwerk, en dat is wat hier zichtbaar wordt.
///
/// Drie keer achter elkaar: de eerste ronde mag koud zijn, ronde twee en drie horen op de warme
/// bodem te liggen. Blijft ronde drie hangen, dan zit het niet in de schijf.
///
/// Draaien:  flutter test test/scan_meting_test.dart --reporter expanded
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';

const echteBibliotheek = r'D:\Flac music 2024';

final slaOverZonderBibliotheek =
    Directory(echteBibliotheek).existsSync() ? null : 'geen $echteBibliotheek op deze machine';

void main() {
  test('waar gaat de opstartscan heen', () async {
    LibraryStore? lib;

    // Elke ronde een VERSE store, want dat is wat een herstart is. Met één store hergebruikt
    // `rebuildAlbums` de hoezen die al in het geheugen zitten, en dan vraagt ronde 2 er nog maar 75
    // in plaats van 236 — een veel te mooi getal dat de app zelf nooit haalt.
    for (var ronde = 1; ronde <= 3; ronde++) {
      lib = LibraryStore()..rootPath = echteBibliotheek;
      // ignore: avoid_print
      lib.meetlog = print;
      final klok = Stopwatch()..start();
      // ignore: avoid_print
      print('\n── ronde $ronde (verse start) ──');
      await lib.scan();
      final cache = File(lib.tagCachePad);
      final hoezen = Directory(lib.hoesCacheMap);
      // ignore: avoid_print
      print('  scan TOTAAL ${klok.elapsed.inMilliseconds}ms   '
          '(${lib.tracks.length} nummers, ${lib.albums.length} albums)   '
          'tagcache ${cache.existsSync() ? "${(cache.lengthSync() / 1024).round()} KB" : "-"}, '
          'hoescache ${hoezen.existsSync() ? hoezen.listSync().length : 0} bestanden');
    }

    expect(lib!.tracks.length, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 10)), skip: slaOverZonderBibliotheek);
}
