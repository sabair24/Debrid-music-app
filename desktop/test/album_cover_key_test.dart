import 'dart:typed_data';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: editing one album made another album's hand-picked cover disappear.
///
/// Covers are snapshotted before a regroup and restored after. The snapshot was keyed by the
/// album's DISPLAYED artist while the regroup keyed by the track's raw tag — fine until "feat."
/// credits started displaying stripped ("Nunca feat. Pat Krimson" shown as "Nunca"), after which
/// the two keys never matched and every regroup dropped that album's covers.
Track track(String path, {required String artist, required String album, String title = 'Song'}) => Track(
      path: path,
      title: title,
      artist: artist,
      album: album,
      trackNo: 1,
      duration: const Duration(minutes: 3),
      isFlac: true,
      addedMs: 0,
      sizeBytes: 1000,
    );

void main() {
  test('an album by a "feat." artist keeps its cover across a regroup', () {
    final lib = LibraryStore();
    lib.tracks.addAll([
      track(r'C:\m\voodoo.flac', artist: 'Nunca feat. Pat Krimson', album: 'Voodoo'),
      track(r'C:\m\other.flac', artist: 'Daft Punk', album: 'Discovery'),
    ]);
    lib.rebuildAlbums();

    final voodoo = lib.albums.firstWhere((a) => a.title == 'Voodoo');
    expect(voodoo.artist, 'Nunca', reason: 'the guest is stripped for display');
    final picked = Uint8List.fromList([1, 2, 3, 4]);
    voodoo.correctedCover = picked;

    // Editing any other album regroups everything — this is when the cover used to vanish.
    lib.rebuildAlbums();

    final after = lib.albums.firstWhere((a) => a.title == 'Voodoo');
    expect(after.correctedCover, picked, reason: 'the hand-picked cover must survive the regroup');
  });

  test('a plain album keeps its cover too', () {
    final lib = LibraryStore();
    lib.tracks.add(track(r'C:\m\d.flac', artist: 'Daft Punk', album: 'Discovery'));
    lib.rebuildAlbums();
    final picked = Uint8List.fromList([9, 9]);
    lib.albums.first.correctedCover = picked;
    lib.rebuildAlbums();
    expect(lib.albums.first.correctedCover, picked);
  });

  test('a single (no album tag) keeps its cover across a regroup', () {
    final lib = LibraryStore();
    lib.tracks.add(track(r'C:\m\s.flac', artist: 'X feat. Y', album: '', title: 'Loose Track'));
    lib.rebuildAlbums();
    final picked = Uint8List.fromList([7]);
    lib.albums.first.correctedCover = picked;
    lib.rebuildAlbums();
    expect(lib.albums.first.correctedCover, picked);
  });
}
