/// A correction reaching what is playing.
///
/// The player holds `Track` VALUES taken when the queue was built. `Track` is immutable and a
/// correction builds new ones, so without this the queue points at the old objects for as long as
/// it lives: every list in the app updates, and the three places you are actually looking at — the
/// player bar, the now-playing screen, the lockscreen — keep the old name until the next song.
///
/// The cover half of this was fixed long ago with refreshCover(). This is the text half.
///
/// Tested through [remapQueue] rather than PlayerStore, because constructing one loads libmpv and
/// that cannot happen in a test run. What is tested here is the part with the invariants: the
/// shuffle permutation, the "nothing visible changed" answer, and what a missing track does.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';

Track _t(String path, {String title = 't', String artist = 'Portishead', String album = 'Dummy'}) =>
    Track(path: path, title: title, artist: artist, album: album);

void main() {
  final a = _t('/m/1.flac', title: 'Mysterons');
  final b = _t('/m/2.flac', title: 'Sour Times');
  final c = _t('/m/3.flac', title: 'Strangers');
  final queue = [a, b, c];

  /// The library after the artist was corrected.
  Track? corrected(String path) {
    final by = {for (final t in queue) t.path: t};
    final t = by[path];
    return t == null
        ? null
        : Track(path: t.path, title: t.title, artist: 'Portishead & Beth Gibbons', album: t.album);
  }

  group('what plays gets the new name', () {
    test('a corrected artist reaches every track in the queue', () {
      final next = remapQueue(queue, queue, corrected);
      expect(next, isNotNull);
      expect(next!.original.map((t) => t.artist),
          everyElement('Portishead & Beth Gibbons'));
      expect(next.order.map((t) => t.path), [a.path, b.path, c.path],
          reason: 'de volgorde is niet het onderwerp van een naamswijziging');
    });

    test('the paths are untouched, because everything else is keyed on them', () {
      final next = remapQueue(queue, queue, corrected)!;
      // Favourites, playlists, resume and the "this row is playing" highlight all match on path.
      expect(next.original.map((t) => t.path), queue.map((t) => t.path));
    });
  });

  group('the shuffle survives', () {
    test('a shuffled order keeps its permutation exactly', () {
      final shuffled = [c, a, b]; // what _rebuildOrder produced
      final next = remapQueue(queue, shuffled, corrected)!;

      expect(next.order.map((t) => t.path), [c.path, a.path, b.path],
          reason: 'anders springt de wachtrij naar een ander nummer tijdens het spelen');
      expect(next.original.map((t) => t.path), [a.path, b.path, c.path]);
    });

    test('the track at the playing index is still the same song', () {
      const index = 1; // playing `a` inside the shuffled order
      final shuffled = [c, a, b];
      final next = remapQueue(queue, shuffled, corrected)!;

      expect(next.order[index].path, shuffled[index].path);
      expect(next.order[index].artist, 'Portishead & Beth Gibbons');
    });
  });

  group('when nothing visible changed', () {
    test('an unchanged library answers null, so nothing rebuilds', () {
      expect(remapQueue(queue, queue, (p) => {for (final t in queue) t.path: t}[p]), isNull);
    });

    test('a re-stat that only moves size and mtime is not a change', () {
      // What a rescan of untouched files produces. Rebuilding the player bar for this would mean
      // rebuilding it constantly, since the library re-reads the disk on every scan.
      Track? restatted(String path) {
        final t = {for (final x in queue) x.path: x}[path];
        return t == null
            ? null
            : Track(
                path: t.path,
                title: t.title,
                artist: t.artist,
                album: t.album,
                addedMs: 1730000000000,
                sizeBytes: 41231107,
                duration: const Duration(minutes: 4),
              );
      }

      expect(remapQueue(queue, queue, restatted), isNull);
    });

    test('but a renumber IS a change — the queue sheet shows it', () {
      Track? renumbered(String path) {
        final t = {for (final x in queue) x.path: x}[path];
        return t == null
            ? null
            : Track(path: t.path, title: t.title, artist: t.artist, album: t.album, trackNo: 7);
      }

      expect(remapQueue(queue, queue, renumbered), isNotNull);
    });
  });

  group('a track the library cannot answer for', () {
    test('keeps what it had rather than blanking', () {
      // Mid-regroup, or a radio stream with no library entry at all.
      Track? partial(String path) => path == b.path ? null : corrected(path);

      final next = remapQueue(queue, queue, partial)!;
      expect(next.original[1].path, b.path);
      expect(next.original[1].artist, 'Portishead', reason: 'oud, maar aanwezig');
      expect(next.original[0].artist, 'Portishead & Beth Gibbons');
    });

    test('a library that answers for nothing changes nothing at all', () {
      expect(remapQueue(queue, queue, (_) => null), isNull);
    });

    test('an empty queue is not a special case', () {
      expect(remapQueue(const [], const [], corrected), isNull);
    });
  });

  /// What makes the walk above affordable.
  ///
  /// The library notifies once per cached cover while a library warms up — hundreds of times — and
  /// a shuffled queue can be every track there is. If the player had to compare the whole queue on
  /// each of those, startup would spend millions of lookups discovering nothing changed. metaRev
  /// answers the same question with one integer comparison, so it must move for text and stay put
  /// for everything else.
  group('the counter that stops a notify storm', () {
    late Directory scratch;
    late LibraryStore lib;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('dm_metarev_');
      lib = LibraryStore()..configDirOverride = scratch.path;
      lib.tracks.addAll(queue);
      lib.rebuildAlbums();
    });

    tearDown(() {
      try {
        scratch.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('a cover arriving does not move it', () {
      final before = lib.metaRev;
      final bytes = Uint8List.fromList(List<int>.filled(2000, 7));

      for (var i = 0; i < 200; i++) {
        lib.adoptAlbumCover('Portishead', 'Dummy', Uint8List.fromList(bytes), from: 'rel:$i');
      }

      expect(lib.metaRev, before, reason: 'hoezen zijn geen namen');
    });

    test('a correction does move it', () {
      final before = lib.metaRev;
      lib.seedCorrectionForTest(queue.first.path, {'artist': 'Portishead & Beth Gibbons'});
      lib.refreshFromCorrections();

      expect(lib.metaRev, greaterThan(before));
      expect(lib.tracks.first.artist, 'Portishead & Beth Gibbons');
    });
  });

  /// The sleeve the album page resolved has to be the one the grid shows.
  ///
  /// It was already handed back to the library, and filed as `enriched` — which loses to the cover
  /// embedded in the files. So for every record whose files carry a wrong sleeve this appeared to
  /// work and changed nothing: right art on the album page, one step back and the old one again.
  group('which cover wins', () {
    final art = Uint8List.fromList(List<int>.filled(2000, 1));
    final embedded = Uint8List.fromList(List<int>.filled(2000, 2));

    Album album() => Album('Dummy', 'Portishead', queue)..embeddedCover = embedded;

    test('a sleeve from an identified pressing beats the one in the files', () {
      final a = album()
        ..resolvedCover = art
        ..resolvedFrom = 'rel:12345';
      expect(a.cover, art);
    });

    test('a search-by-name guess does not', () {
      final a = album()..enriched = art;
      expect(a.cover, embedded, reason: 'een gok mag de hoes uit je bestand niet overrulen');
    });

    test('what the user picked by hand still beats everything', () {
      final mine = Uint8List.fromList(List<int>.filled(2000, 3));
      final a = album()
        ..resolvedCover = art
        ..resolvedFrom = 'rel:12345'
        ..correctedCover = mine;
      expect(a.cover, mine);
    });

    test('and it survives a regroup, which is what a correction causes', () {
      final scratch = Directory.systemTemp.createTempSync('dm_cov_');
      try {
        final lib = LibraryStore()..configDirOverride = scratch.path;
        lib.tracks.addAll(queue);
        lib.rebuildAlbums();
        lib.adoptAlbumCover('Portishead', 'Dummy', art, from: 'rel:12345');
        expect(lib.albums.single.cover, art);

        lib.rebuildAlbums();
        expect(lib.albums.single.cover, art,
            reason: 'anders is de hoes weg zodra je iets anders corrigeert');
        expect(lib.albums.single.resolvedFrom, 'rel:12345');
      } finally {
        scratch.deleteSync(recursive: true);
      }
    });
  });
}
