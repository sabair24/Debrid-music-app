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
  test('editions that do not collide are left as one album', () {
    // Differing totals alone are usually just sloppy tagging. Splitting on them gave one artist six
    // identical tiles — worse to look at than the merging it was meant to fix.
    final albums = group([
      t('a.flac', total: 12, no: 10),
      t('b.flac', total: 16, no: 4),
      t('c.flac', total: 13, no: 6),
    ]);
    expect(albums.length, 1);
  });

  test('three editions DO split once their track numbers collide', () {
    final albums = group([
      t('a.flac', total: 12, no: 10), // US 1997 Zomba
      t('b.flac', total: 12, no: 6),
      t('c.flac', total: 16, no: 6), // 16-track RCA — collides on 6
      t('d.flac', total: 13, no: 6), // international Jive — collides again
    ]);
    expect(albums.length, 3);
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

  test('split albums say which pressing they are', () {
    // Six identical tiles are unusable however correct the split is — and you cannot choose which
    // to merge if you cannot tell them apart.
    final albums = group([
      t('a.flac', total: 12, no: 6),
      t('b.flac', total: 13, no: 6),
      t('c.flac', no: 6),
    ]);
    expect(albums.length, 3);
    expect(albums.map((a) => a.edition).toSet(), {'12 nummers', '13 nummers', 'zonder nummering'});
  });

  test('an album that did not split carries no edition label', () {
    final albums = group([t('a.flac', total: 12, no: 1), t('b.flac', total: 12, no: 2)]);
    expect(albums.single.edition, isNull);
  });

  test('a radio edit beside the album cut is not a second pressing', () {
    // What filling a gap did to a good album. The folder held only the RADIO EDIT of track 1, so
    // the missing-track list correctly offered the album version and fetched it — and the album now
    // had two number ones. That collision, over files claiming 0, 11, 12 and 16 tracks, turned one
    // Backstreet's Back tile into four. Completing a record must never break it.
    Track v(String file, String title, int no, int total) => Track(
          path: r"D:\Flac music 2024\Albums\Backstreet Boys\Backstreet's Back\" '$file',
          title: title,
          artist: 'Backstreet Boys',
          album: "Backstreet's Back",
          trackNo: no,
          trackTotal: total,
          isFlac: true,
        );
    final albums = group([
      v("01 - Everybody (Backstreet's Back) (Radio Edit).flac", "Everybody (Backstreet's Back) (Radio Edit)", 1, 0),
      v("01 - Everybody (Backstreet's Back).flac", "Everybody (Backstreet's Back)", 1, 16),
      v('02 - As Long as You Love Me.flac', 'As Long as You Love Me', 2, 11),
      v("04 - That's the Way I Like It.flac", "That's the Way I Like It", 4, 12),
    ]);
    expect(albums.length, 1, reason: 'vier tegels voor één map met twaalf bestanden');
    expect(albums.single.tracks.length, 4);
  });

  test('the marker counts even when the tag forgot it, but a folder name never does', () {
    // Read from the title and the filename only. Taking the whole path would mark every track under
    // "… (Deluxe Edition)" as a variant and the split would never fire for that album again.
    Track at(String path, String title, int total) => Track(
          path: path, title: title, artist: 'X', album: 'Album', trackNo: 6, trackTotal: total, isFlac: true);

    final tagForgot = group([
      at(r'D:\M\X\Album\06 - Song (Live).flac', 'Song', 0),
      at(r'D:\M\X\Album\06 - Lied.flac', 'Lied', 16),
    ]);
    expect(tagForgot.length, 1, reason: 'de bestandsnaam zegt het wel');

    final deluxeFolder = group([
      at(r'D:\M\X\Album (Deluxe Edition)\06 - Song.flac', 'Song', 12),
      at(r'D:\M\X\Album (Deluxe Edition)\06 - Lied.flac', 'Lied', 16),
    ]);
    expect(deluxeFolder.length, 2, reason: 'een mapnaam mag de splitsing niet uitschakelen');
  });

  test('pinnedRelease returns null on an album with no pin, and does not throw', () {
    // Adele's 30 had fifteen live tracks pinned to one release and fifteen orphan corrections from
    // a deleted Japanese edition, all empty. Reading the wrong list made the pin look empty. An
    // album with no pin at all must simply answer null.
    final lib = LibraryStore();
    lib.tracks.addAll([t('live1.flac', total: 15, no: 1), t('live2.flac', total: 15, no: 2)]);
    lib.rebuildAlbums();
    expect(lib.pinnedRelease(lib.albums.single), isNull);
  });
}
