import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/release_format.dart';

MbRelease _r(String format,
        {String? country, String? catno, String? date, int tracks = 12, String status = 'Official'}) =>
    MbRelease(
      mbid: '$format-$country-$catno-$date-$tracks',
      title: '30',
      format: format,
      country: country,
      catno: catno,
      date: date,
      trackCount: tracks,
      status: status,
    );

void main() {
  group('majorFormat', () {
    test('MusicBrainz names the object, not the family', () {
      // Ranked literally these would all fall off the end of the list and tie with each other.
      expect(majorFormat('CD'), 'CD');
      expect(majorFormat('Enhanced CD'), 'CD');
      expect(majorFormat('Hybrid SACD'), 'CD');
      expect(majorFormat('DualDisc'), 'CD');
      expect(majorFormat('12" Vinyl'), 'Vinyl');
      expect(majorFormat('7" Flexi-disc'), 'Vinyl');
      expect(majorFormat('Digital Media'), 'File');
      expect(majorFormat('Cassette'), 'Cassette');
      expect(majorFormat(''), '');
    });

    test('a CD-R is not a CD', () {
      // "CD-R" contains "cd", so the order of the checks is load-bearing.
      expect(majorFormat('CD-R'), 'CDr');
      expect(majorFormat('Enhanced CD-R'), 'CDr');
      expect(releaseFormatRank('CDr'), greaterThan(releaseFormatRank('CD')));
    });

    test('and Discogs spellings land in the same buckets', () {
      expect(majorFormat('Vinyl'), 'Vinyl');
      expect(majorFormat('File'), 'File');
    });
  });

  group('orderByPreference', () {
    test('CD leads and digital trails, whatever order they arrive in', () {
      final out = MusicBrainzService.orderByPreference([
        _r('Digital Media', country: 'XW', date: '2021'),
        _r('12" Vinyl', country: 'US', catno: 'B0034', date: '2021'),
        _r('CD', country: 'JP', catno: 'SICP-6425', date: '2021'),
      ]);
      expect(out.map((r) => r.major).toList(), ['CD', 'Vinyl', 'File']);
    });

    test('a documented CD is never overtaken by an undocumented one', () {
      final out = MusicBrainzService.orderByPreference([
        _r('CD', date: '2021'), // no country, no label, no catalogue number
        _r('CD', country: 'JP', catno: 'SICP-6425', date: '2021'),
      ]);
      expect(out.first.catno, 'SICP-6425');
    });

    test('but an undocumented CD still beats a documented download', () {
      // The format preference is the stronger rule: a pressed disc is a documented physical object,
      // which is what makes it both richer to read and safer to identify.
      final out = MusicBrainzService.orderByPreference([
        _r('Digital Media', country: 'XW', catno: 'ABC123', date: '2021'),
        _r('CD', date: '2021'),
      ]);
      expect(out.first.major, 'CD');
    });

    test('official beats a bootleg of the same format', () {
      final out = MusicBrainzService.orderByPreference([
        _r('CD', country: 'IT', catno: 'BOOT-1', date: '1990', status: 'Bootleg'),
        _r('CD', country: 'GB', catno: 'REAL-1', date: '1990'),
      ]);
      expect(out.first.catno, 'REAL-1');
    });

    test('the original pressing describes the record; a repress describes itself', () {
      final out = MusicBrainzService.orderByPreference([
        _r('CD', country: 'GB', catno: 'B', date: '2015'),
        _r('CD', country: 'GB', catno: 'A', date: '1982'),
      ]);
      expect(out.first.catno, 'A');
    });

    test('a pressing that is a different record is dropped, in both directions', () {
      final out = MusicBrainzService.orderByPreference([
        _r('CD', country: 'GB', catno: 'SINGLE', date: '2021', tracks: 2), // a single
        _r('CD', country: 'GB', catno: 'BOX', date: '2021', tracks: 42), // two albums in a box
        _r('CD', country: 'GB', catno: 'REAL', date: '2021', tracks: 12),
        _r('CD', country: 'GB', catno: 'DELUXE', date: '2021', tracks: 15), // bonus tracks are fine
      ], expectedTracks: 12);
      expect(out.map((r) => r.catno).toSet(), {'REAL', 'DELUXE'});
    });

    test('a pressing with no stated track count is kept rather than guessed away', () {
      final out = MusicBrainzService.orderByPreference(
          [_r('CD', country: 'GB', catno: 'A', date: '2021', tracks: 0)],
          expectedTracks: 12);
      expect(out, hasLength(1));
    });
  });

  group('MbRelease', () {
    test('reads the edition line straight off the release', () {
      expect(_r('CD', country: 'JP', catno: 'SICP-6425', date: '2021-11-19').line,
          'CD · JP · SICP-6425 · 2021');
    });

    test('a double LP is one format, not two', () {
      final r = MbRelease.from({
        'id': 'x',
        'title': '30',
        'media': [
          {'format': '12" Vinyl', 'track-count': 6},
          {'format': '12" Vinyl', 'track-count': 6},
        ],
      });
      expect(r.format, '12" Vinyl');
      expect(r.trackCount, 12, reason: 'both discs count towards the record');
      expect(r.major, 'Vinyl');
    });
  });

  group('MbImage', () {
    test('the archive says what a scan is, so nothing is inferred', () {
      MbImage? mk(List<String> types, {bool front = false, bool back = false}) =>
          MbImage.from({'image': 'u', 'types': types, 'front': front, 'back': back});

      expect(mk(['Medium'])!.isDisc, isTrue);
      expect(mk(['Front', 'Obi', 'Spine'], front: true)!.isFront, isTrue);
      expect(mk(['Back', 'Spine'], back: true)!.isBack, isTrue);
      expect(mk(['Booklet'])!.isDisc, isFalse);
      expect(mk(['Booklet'])!.isFront, isFalse);
      // An image can be the front cover without carrying the type.
      expect(mk(const [], front: true)!.isFront, isTrue);
      // No URL is no image.
      expect(MbImage.from({'image': ''}), isNull);
    });

    test('a small copy for a row, a 1200 for the screen', () {
      final i = MbImage.from({
        'image': 'https://…/full.jpg',
        'thumbnails': {
          '1200': 'https://…/1200.jpg',
          '500': 'https://…/500.jpg',
          '250': 'https://…/250.jpg',
        },
        'types': ['Front'],
      })!;
      // A 58px row does not need more than a 250, and there can be seventy-five of them.
      expect(i.thumb, endsWith('250.jpg'));
      // What actually gets shown: 1200, not the 500 that looked soft full-screen — and not the
      // upload, whose disc scans run to 3008px and 11.8 MB.
      expect(i.full, endsWith('1200.jpg'));
      expect(i.url, endsWith('full.jpg'));
    });

    test('with no 1200 rendering it falls back to the upload itself', () {
      final i = MbImage.from({
        'image': 'https://…/full.jpg',
        'thumbnails': {'250': 'https://…/250.jpg'},
        'types': ['Front'],
      })!;
      expect(i.full, endsWith('full.jpg'), reason: 'never show less than what exists');
      expect(i.thumb, endsWith('250.jpg'));
    });
  });
}
