import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two EDITIONS of one record are not one album.
///
/// A single Backstreet Boys folder held tracks whose tags claimed 12, 16 and 13 tracks total — the
/// US 1997 Zomba pressing, a 16-track RCA one, and the 13-track international Jive release. Grouped
/// on artist and title alone they became one album with two number sixes, two number tens, and
/// "Quit Playing Games" listed twice.
///
/// The escape hatch matters as much as the split: a file that states no track total keeps the plain
/// album key it always had. Untagged rips, and everything that isn't FLAC, must not be guessed into
/// an edition — scattering a library is worse than the merging this fixes.
Track t(String path, {String artist = 'Backstreet Boys', String album = 'Backstreet Boys', int total = 0, int no = 1}) =>
    Track(
      path: path,
      title: 'Song $no',
      artist: artist,
      album: album,
      trackNo: no,
      trackTotal: total,
      duration: const Duration(minutes: 3),
      isFlac: true,
      addedMs: 0,
      sizeBytes: 1000,
    );

List<Album> group(List<Track> tracks) {
  final lib = LibraryStore();
  lib.tracks.addAll(tracks);
  lib.rebuildAlbums();
  return lib.albums;
}

void main() {
  test('three editions of one title become three albums', () {
    final albums = group([
      t('a.flac', total: 12, no: 10), // US 1997 Zomba
      t('b.flac', total: 12, no: 2),
      t('c.flac', total: 16, no: 4), // 16-track RCA
      t('d.flac', total: 16, no: 5),
      t('e.flac', total: 13, no: 6), // international Jive
    ]);
    expect(albums.length, 3);
    expect(albums.map((a) => a.tracks.length).toList()..sort(), [1, 2, 2]);
  });

  test('the clashing track numbers end up in different albums', () {
    // Two number sixes: one from the 12-track edition, one from the 13-track one.
    final albums = group([t('a.flac', total: 12, no: 6), t('b.flac', total: 13, no: 6)]);
    expect(albums.length, 2);
    for (final a in albums) {
      expect(a.tracks.length, 1);
    }
  });

  test('files with no stated total stay together on the plain album', () {
    final albums = group([t('a.flac', no: 1), t('b.flac', no: 7), t('c.flac', no: 12)]);
    expect(albums.length, 1, reason: 'guessing which edition these belong to would scatter them');
    expect(albums.first.tracks.length, 3);
  });

  test('an untagged rip does not get pulled into a stated edition', () {
    final albums = group([t('a.flac', total: 12, no: 10), t('b.flac', no: 10)]);
    expect(albums.length, 2);
  });

  test('one edition on its own is still just one album', () {
    final albums = group([t('a.flac', total: 13, no: 1), t('b.flac', total: 13, no: 2)]);
    expect(albums.length, 1);
    expect(albums.first.tracks.length, 2);
  });

  test('different records are still different albums', () {
    final albums = group([
      t('a.flac', album: 'Millennium', total: 12),
      t('b.flac', album: 'Never Gone', total: 12),
    ]);
    expect(albums.length, 2);
  });

  test('different artists sharing a total do not merge', () {
    final albums = group([
      t('a.flac', artist: 'Backstreet Boys', album: 'Hits', total: 12),
      t('b.flac', artist: 'Westlife', album: 'Hits', total: 12),
    ]);
    expect(albums.length, 2);
  });
}
