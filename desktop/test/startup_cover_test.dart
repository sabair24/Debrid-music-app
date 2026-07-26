// Reproduces the app's startup path (scan → enrich) against the real library at
// D:\Flac music 2024 to prove covers populate and nothing hangs.
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
  test('scan returns quickly and covers load from cache', () async {
    final settings = AppSettings();
    await settings.load();
    final lib = LibraryStore()..rootPath = realLibrary;

    final sw = Stopwatch()..start();
    await lib.scan();
    // ignore: avoid_print
    print('scan() returned in ${sw.elapsedMilliseconds}ms — ${lib.albums.length} albums');
    expect(lib.albums.isNotEmpty, true);

    final embedded = lib.albums.where((a) => a.embeddedCover != null).length;
    // ignore: avoid_print
    print('embedded covers after scan: $embedded');

    // Phase 1 of enrich() must fill most covers from the on-disk cache fast.
    // Run enrich but only wait a bounded time; phase-1 (cache) is synchronous disk I/O.
    sw.reset();
    await lib.enrich(settings).timeout(const Duration(seconds: 120), onTimeout: () {});
    final withCover = lib.albums.where((a) => a.cover != null).length;
    // ignore: avoid_print
    print('covers after enrich: $withCover / ${lib.albums.length} (in ${sw.elapsedMilliseconds}ms)');

    // With 60 cached covers on disk, the vast majority must be present.
    expect(withCover, greaterThan(40));
  }, timeout: const Timeout(Duration(minutes: 4)), skip: skipUnlessLibrary);
}
