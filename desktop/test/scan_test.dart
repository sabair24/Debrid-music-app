// Verifies the library scanner + metadata/cover reading against the real folder.
// Runs on the Dart VM (no Visual Studio / Windows runner needed).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';

/// The folder these three read. It used to be the hard-coded default of LibraryStore.rootPath, so
/// they passed on this machine by accident and could never have passed anywhere else. Now it is said
/// out loud, and a machine without it skips instead of failing.
const realLibrary = r'D:\Flac music 2024';

/// Nothing to scan on a machine that does not hold the music — say so rather than fail.
final skipUnlessLibrary =
    Directory(realLibrary).existsSync() ? null : 'geen $realLibrary op deze machine';

void main() {
  test('scans D:\\Flac music 2024 and reads tags + covers', () async {
    final lib = LibraryStore()..rootPath = realLibrary;
    await lib.scan();
    // ignore: avoid_print
    print('SCAN RESULT: tracks=${lib.tracks.length} albums=${lib.albums.length} artists=${lib.artists.length}');
    final withCover = lib.albums.where((a) => a.embeddedCover != null).length;
    // ignore: avoid_print
    print('albums with embedded cover: $withCover / ${lib.albums.length}');
    final singles = lib.albums.where((a) => a.isSingle).length;
    // ignore: avoid_print
    print('singles: $singles; fake "Flac music 2024" album present: '
        '${lib.albums.any((a) => a.title.toLowerCase().contains("flac music 2024"))}');
    for (final a in lib.albums.take(6)) {
      // ignore: avoid_print
      print('  • ${a.isSingle ? "[single] " : ""}${a.title} — ${a.artist} (${a.tracks.length} nr)');
    }
    expect(lib.tracks.length, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 4)), skip: skipUnlessLibrary);
}
