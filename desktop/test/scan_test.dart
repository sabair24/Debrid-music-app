// Verifies the library scanner + metadata/cover reading against the real folder.
// Runs on the Dart VM (no Visual Studio / Windows runner needed).
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';

void main() {
  test('scans D:\\Flac music 2024 and reads tags + covers', () async {
    final lib = LibraryStore();
    await lib.scan();
    // ignore: avoid_print
    print('SCAN RESULT: tracks=${lib.tracks.length} albums=${lib.albums.length} artists=${lib.artists.length}');
    final withCover = lib.tracks.where((t) => t.cover != null).length;
    // ignore: avoid_print
    print('tracks with embedded cover: $withCover / ${lib.tracks.length}');
    for (final a in lib.albums.take(5)) {
      // ignore: avoid_print
      print('  • ${a.title} — ${a.artist} (${a.tracks.length} nr, cover=${a.cover != null}, flac=${a.tracks.first.isFlac})');
    }
    expect(lib.tracks.length, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
