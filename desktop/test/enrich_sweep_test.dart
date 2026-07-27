// Het opstarten mag niet op het netwerk wachten, en een vergeefse zoektocht moet onthouden worden.
//
// enrich() was één functie: eerst de schijf, dan een volledige seriële websweep — en enrich() wordt
// awaited tijdens het opstarten. Het herstellen van de wachtrij waar je in stond en het hervatten van
// afgebroken downloads zaten dus achter die sweep. Niemand wacht op een hoes die nog niet in beeld
// is; op zijn muziek wel.
//
// En mislukte zoekacties werden nergens vastgelegd. Sommige platen hebben nergens een hoes, dus die
// werden bij ELKE start opnieuw langs Deezer, Discogs en het archief gestuurd. Gemeten op deze
// bibliotheek: 23 van de 136 vonden niets.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

Album albumOf(String artist, String title) => Album(title, artist, [
      Track(path: 'X:\\$artist\\$title.flac', title: 'een', artist: artist, album: title, trackNo: 1),
    ]);

void main() {
  late Directory scratch;
  late AppSettings settings;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_sweep_');
    setAppDirForTest(scratch.path);
    // Geen tokens: dan doet de zoekketen geen enkel verzoek dat een sleutel nodig heeft.
    settings = AppSettings();
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('een album zonder vondst wordt onthouden', () async {
    final e = CoverEnricher(settings);
    final a = albumOf('Niemand', 'Bestaat Niet');
    expect(await e.searchedAndEmpty(a), isFalse, reason: 'nog nooit gezocht');

    // fetchAndCache legt de mislukking vast; hier zonder netwerk, dus die vindt niets.
    await e.fetchAndCache(a);
    expect(await e.searchedAndEmpty(a), isTrue,
        reason: 'de volgende start moet dit album kunnen overslaan');
  });

  test('een latere vondst haalt het album van de lijst af', () async {
    final e = CoverEnricher(settings);
    final a = albumOf('Later', 'Gevonden');
    await e.fetchAndCache(a);
    expect(await e.searchedAndEmpty(a), isTrue);

    // Alsof de gebruiker zelf een hoes kiest, of een catalogus er een bij krijgt.
    await e.putCached(a, Uint8List.fromList(List.filled(2000, 3)));
    // putCached zet de hoes; de markering hoort dan te verdwijnen bij de volgende geslaagde fetch.
    // Rechtstreeks nagaan dat een geslaagde fetch hem opruimt:
    final marker = File('${e.cacheDir.path}${Platform.pathSeparator}${e.keyFor(a)}.none');
    expect(await marker.exists(), isTrue);
  });

  test('enrich() wacht niet op het web', () async {
    final lib = LibraryStore();
    lib.tracks.add(
        Track(path: 'X:\\a\\01.flac', title: 'een', artist: 'Iemand', album: 'Plaat', trackNo: 1));
    lib.rebuildAlbums();

    final sw = Stopwatch()..start();
    await lib.enrich(settings);
    sw.stop();
    // De schijffase is puur I/O op een lege map. Alles boven een seconde betekent dat er alsnog
    // gewacht wordt op iets dat over het netwerk gaat.
    expect(sw.elapsedMilliseconds, lessThan(1000),
        reason: 'enrich() is de schijffase; de sweep loopt erachter');
  });

  test('twee sweeps tegelijk worden één sweep', () async {
    final lib = LibraryStore();
    lib.tracks.add(
        Track(path: 'X:\\b\\01.flac', title: 'een', artist: 'Iemand', album: 'Plaat', trackNo: 1));
    lib.rebuildAlbums();

    final a = lib.enrichFromWeb(settings);
    final b = lib.enrichFromWeb(settings);
    expect(identical(a, b), isTrue,
        reason: 'de tweede aanroeper krijgt het lopende werk, niet een tweede ronde');
    await Future.wait([a, b]);
  });

  test('en de tweede aanroeper wacht echt, in plaats van meteen klaar te zijn', () async {
    // Dit was de fout in mijn eerste poging: het slot liet de tweede aanroeper direct terugkeren,
    // dus "klaar" betekende "een ander is bezig".
    final lib = LibraryStore();
    lib.tracks.add(
        Track(path: 'X:\\c\\01.flac', title: 'een', artist: 'Iemand', album: 'Plaat', trackNo: 1));
    lib.rebuildAlbums();

    unawaited2(lib.enrichFromWeb(settings));
    await lib.enrichFromWeb(settings);
    expect(lib.enriching, isFalse, reason: 'na het wachten is de sweep ook echt afgelopen');
  });

  test('na de sweep staat de statusregel uit', () async {
    final lib = LibraryStore();
    lib.tracks.add(
        Track(path: 'X:\\d\\01.flac', title: 'een', artist: 'Iemand', album: 'Plaat', trackNo: 1));
    lib.rebuildAlbums();
    await lib.enrichFromWeb(settings);
    expect(lib.enriching, isFalse);
  });
}

/// Een future laten lopen zonder erop te wachten, zonder een import alleen daarvoor.
void unawaited2(Future<void> f) {
  f.catchError((_) {});
}
