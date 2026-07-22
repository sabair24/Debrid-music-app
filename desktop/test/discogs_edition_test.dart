import 'package:debridmusic/discogs.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which pressing of an album the library describes.
///
/// The rule asked for is digital → CD → LP. The complication that made it worth asking about:
/// Discogs is a collectors' database of physical media, so its digital entries are often stubs.
/// Of the 115 versions of *Discovery* exactly two are digital, and one of those has no year at all.
/// Following the preference blindly would trade a fully documented CD for an empty page.
DiscogsVersion v(String major, {int? year, String? label, String? catno, int id = 1}) => DiscogsVersion(
      id,
      major,
      major,
      label,
      catno,
      'Europe',
      year?.toString(),
    );

void main() {
  masters();
  test('a documented digital release wins, as asked', () {
    final order = DiscogsService.orderByPreference([
      v('CD', year: 2001, label: 'Virgin', catno: 'CD1', id: 2),
      v('File', year: 2001, label: 'Virgin', catno: 'DIG1', id: 3),
      v('Vinyl', year: 2001, label: 'Virgin', catno: 'LP1', id: 4),
    ]);
    expect(order.first.major, 'File');
    expect(order[1].major, 'CD');
    expect(order[2].major, 'Vinyl');
  });

  test('a digital stub steps aside for a documented CD', () {
    // The real case: an "AAC, Album" entry with no year and no catalogue number.
    final order = DiscogsService.orderByPreference([
      v('File', id: 3), // no year, no label, no catno
      v('CD', year: 2001, label: 'Virgin', catno: 'CD1', id: 2),
    ]);
    expect(order.first.major, 'CD', reason: 'an undocumented digital entry describes nothing');
  });

  test('...and so does a digital entry with a year but nobody behind it', () {
    final order = DiscogsService.orderByPreference([
      v('File', year: 2001, id: 3), // year, but no label and no catalogue number
      v('CD', year: 2001, label: 'Virgin', catno: 'CD1', id: 2),
    ]);
    expect(order.first.major, 'CD');
  });

  test('vinyl only comes up when digital and CD have nothing to say', () {
    final order = DiscogsService.orderByPreference([
      v('Vinyl', year: 1977, label: 'Warner', catno: 'BSK 3010', id: 4),
      v('File', id: 3),
      v('CD', id: 2),
    ]);
    expect(order.first.major, 'Vinyl');
  });

  test('between two pressings of one format, the documented one leads', () {
    final order = DiscogsService.orderByPreference([
      v('CD', id: 2), // stub
      v('CD', year: 2001, label: 'Virgin', catno: 'CD1', id: 5),
    ]);
    expect(order.first.id, 5);
  });

  test('between two documented pressings, the original beats the repress', () {
    final order = DiscogsService.orderByPreference([
      v('CD', year: 2015, label: 'Virgin', catno: 'RE1', id: 6),
      v('CD', year: 2001, label: 'Virgin', catno: 'CD1', id: 5),
    ]);
    expect(order.first.id, 5, reason: 'the first pressing describes the record, a repress itself');
  });

  test('entries with no usable id are dropped', () {
    final order = DiscogsService.orderByPreference([
      v('CD', year: 2001, label: 'Virgin', id: 0),
      v('CD', year: 2001, label: 'Virgin', id: 5),
    ]);
    expect(order.length, 1);
    expect(order.first.id, 5);
  });

  test('cassettes and CDrs sort last but are not thrown away', () {
    final order = DiscogsService.orderByPreference([
      v('Cassette', year: 2001, label: 'Virgin', catno: 'MC1', id: 7),
      v('CD', year: 2001, label: 'Virgin', catno: 'CD1', id: 5),
    ]);
    expect(order.first.major, 'CD');
    expect(order.length, 2);
  });
}

/// Which MASTER the album page describes, before any edition is chosen at all.
///
/// Searching Discogs for "Michael Jackson — Bad" returns three masters with exactly that title:
/// a promo flexi-disc, a promo 7" single, and the album. Taking the first hit described the album
/// as a Belgian promo single with three pressings. Discogs puts "Album" in the format list of the
/// masters that are one, so the answer is already in the search response.
void masters() {
  test('an album master beats a promo single of the same name', () {
    expect(DiscogsService.albumScore(['Flexi-disc', '7"', '33 ⅓ RPM', 'Mixed', 'Promo']),
        lessThan(DiscogsService.albumScore(['CD', 'Album', 'Stereo'])));
    expect(DiscogsService.albumScore(['Vinyl', '7"', '45 RPM', 'Single', 'Promo', 'Stereo']),
        lessThan(DiscogsService.albumScore(['CD', 'Album', 'Stereo'])));
  });

  test('a bootleg does not describe the record', () {
    expect(DiscogsService.albumScore(['Vinyl', 'LP', 'Limited Edition', 'Unofficial Release']),
        lessThan(DiscogsService.albumScore(['Vinyl', 'LP', 'Album'])));
  });

  test('a video release is not the album either', () {
    expect(DiscogsService.albumScore(['Blu-ray', 'Stereo', 'Multichannel']),
        lessThan(DiscogsService.albumScore(['CD', 'Album'])));
  });

  test('a remastered album reissue still counts as the album', () {
    expect(DiscogsService.albumScore(['Vinyl', 'LP', 'Album', 'Record Store Day', 'Limited Edition', 'Remastered']),
        greaterThan(0));
  });

  group('does this pressing hold the album we have?', () {
    test('the exact count fits', () => expect(DiscogsService.fitsTrackCount(14, 14), isTrue));
    test('a couple of bonus tracks fit', () => expect(DiscogsService.fitsTrackCount(16, 14), isTrue));
    test('a deluxe edition still fits', () => expect(DiscogsService.fitsTrackCount(22, 14), isTrue));
    test('a two-in-one does not', () {
      // Searching for Discovery found a 30-track double CD that was Homework as well.
      expect(DiscogsService.fitsTrackCount(30, 14), isFalse);
      // And searching for Bad found a 32-track anniversary set.
      expect(DiscogsService.fitsTrackCount(32, 11), isFalse);
    });
    test('a promo single does not', () => expect(DiscogsService.fitsTrackCount(2, 11), isFalse));
    test('a pressing missing one track still fits — rips disagree about hidden tracks', () {
      expect(DiscogsService.fitsTrackCount(13, 14), isTrue);
    });
  });

  group('does this hit actually name the album?', () {
    const a = 'Daft Punk', t = 'Discovery';
    test('the exact record', () => expect(DiscogsService.titleScore('Daft Punk - Discovery', a, t), greaterThan(0)));
    test('a deluxe edition of it', () {
      expect(DiscogsService.titleScore('Daft Punk - Discovery (Deluxe Edition)', a, t), greaterThan(0));
    });
    test('a bundle with another album is NOT it', () {
      // The one that got through everything else: a Virgin two-disc set that scored well on format
      // and had plausibly many tracks, and was Human After All.
      expect(DiscogsService.titleScore('Daft Punk - Human After All / Discovery', a, t), lessThan(0));
      expect(DiscogsService.titleScore('Daft Punk - Discovery / Homework', a, t), lessThan(0));
    });
    test('a different record entirely is NOT it', () {
      expect(DiscogsService.titleScore('Daft Punk - Homework', a, t), lessThan(0));
    });
    test('the artist prefix is not held against the title', () {
      expect(DiscogsService.titleScore('Discovery', a, t), greaterThan(0));
    });
  });

  group('owning only part of an album', () {
    test('four tracks of a fifteen-track record still describe that record', () {
      // Demon Days: the library held four tracks, and measuring pressings against THAT rejected
      // every real fifteen-track one. The master's own length is the reference.
      expect(DiscogsService.fitsTrackCount(15, 15), isTrue);
      expect(DiscogsService.fitsTrackCount(15, 4), isFalse, reason: 'this is why the library count is not the yardstick');
    });
  });
}
