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
