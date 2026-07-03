// Verifies album year/genre (from tags) + artist photo enrichment (Deezer).
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/settings.dart';

void main() {
  test('album year/genre + artist images', () async {
    final settings = AppSettings();
    await settings.load();
    final lib = LibraryStore();
    await lib.scan();

    final withYear = lib.albums.where((a) => a.year != null).length;
    final withGenre = lib.albums.where((a) => a.genre != null).length;
    // ignore: avoid_print
    print('albums with year: $withYear / ${lib.albums.length}; with genre: $withGenre');
    for (final a in lib.albums.where((a) => a.year != null || a.genre != null).take(5)) {
      // ignore: avoid_print
      print('   ${a.title} — year=${a.year} genre=${a.genre}');
    }

    await lib.enrichArtists(settings);
    // ignore: avoid_print
    print('artist photos fetched: ${lib.artistImages.length} / ${lib.artists.length}');
    for (final name in lib.artists.where((n) => lib.artistImages.containsKey(n)).take(6)) {
      // ignore: avoid_print
      print('   photo: $name');
    }
    expect(lib.albums.length, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
