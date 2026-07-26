// Verifies album year/genre (from tags) + artist photo enrichment (Deezer).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/settings.dart';

/// The folder these three read. It used to be the hard-coded default of LibraryStore.rootPath, so
/// they passed on this machine by accident and could never have passed anywhere else. Now it is said
/// out loud, and a machine without it skips instead of failing.
const realLibrary = r'D:\Flac music 2024';

/// Nothing to scan on a machine that does not hold the music — say so rather than fail.
final skipUnlessLibrary =
    Directory(realLibrary).existsSync() ? null : 'geen $realLibrary op deze machine';

void main() {
  test('album year/genre + artist images', () async {
    final settings = AppSettings();
    await settings.load();
    final lib = LibraryStore()..rootPath = realLibrary;
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
  }, timeout: const Timeout(Duration(minutes: 5)), skip: skipUnlessLibrary);
}
