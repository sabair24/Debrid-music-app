import 'package:debridmusic/organize.dart';
import 'package:flutter_test/flutter_test.dart';

/// A track credited "Lady Gaga feat. Beyoncé" belongs on Lady Gaga's album, but Beyoncé must
/// still be visible — and clickable — while it plays.
void main() {
  group('the main artist is the one the album belongs to', () {
    test('credit in the artist tag', () {
      final r = splitFeatured('Lady Gaga feat. Beyoncé', 'Telephone');
      expect(r.main, 'Lady Gaga');
      expect(r.featured, ['Beyoncé']);
    });

    test('credit in the title', () {
      final r = splitFeatured('Lady Gaga', 'Telephone (feat. Beyoncé)');
      expect(r.main, 'Lady Gaga');
      expect(r.featured, ['Beyoncé']);
    });

    test('the various ways rippers write it', () {
      for (final s in ['Ft. Beyoncé', 'ft Beyoncé', 'FEAT. Beyoncé', 'featuring Beyoncé']) {
        expect(splitFeatured('Lady Gaga $s', 'Telephone').featured, ['Beyoncé'], reason: s);
      }
    });

    test('several guests', () {
      final r = splitFeatured('Calvin Harris', 'Feels (feat. Pharrell Williams, Katy Perry & Big Sean)');
      expect(r.main, 'Calvin Harris');
      expect(r.featured, ['Pharrell Williams', 'Katy Perry', 'Big Sean']);
    });

    test('no credit at all leaves everything alone', () {
      final r = splitFeatured('Daft Punk', 'Around the World');
      expect(r.main, 'Daft Punk');
      expect(r.featured, isEmpty);
    });
  });

  group('bands with & in their name are not torn apart', () {
    test('"&" alone never splits an artist', () {
      for (final band in ['Simon & Garfunkel', 'Hall & Oates', 'Florence + The Machine']) {
        final r = splitFeatured(band, 'Some Song');
        expect(r.main, band, reason: band);
        expect(r.featured, isEmpty, reason: band);
      }
    });

    test('but & DOES separate names inside a feat. credit', () {
      expect(splitFeatured('Drake feat. Rihanna & Future', 'X').featured, ['Rihanna', 'Future']);
    });
  });

  test('the main artist is never listed as their own guest', () {
    final r = splitFeatured('Beyoncé feat. Beyonce', 'X');
    expect(r.featured, isEmpty);
  });

  test('duplicate guests are listed once', () {
    final r = splitFeatured('A feat. Beyoncé', 'Song (feat. Beyonce)');
    expect(r.featured, ['Beyoncé']);
  });

  group('titleWithoutFeat', () {
    test('drops the credit tail', () {
      expect(titleWithoutFeat('Telephone (feat. Beyoncé)'), 'Telephone');
      expect(titleWithoutFeat('Feels [ft. Katy Perry]'), 'Feels');
    });

    test('leaves a plain title untouched', () {
      expect(titleWithoutFeat('Around the World'), 'Around the World');
      expect(titleWithoutFeat('D.A.N.C.E. (Live Version)'), 'D.A.N.C.E. (Live Version)');
    });
  });
}
