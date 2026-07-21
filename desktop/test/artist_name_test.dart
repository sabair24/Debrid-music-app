import 'package:debridmusic/organize.dart';
import 'package:flutter_test/flutter_test.dart';

/// One artist must appear ONCE. Tags disagree about capitalisation and accents, and the artist
/// list used to show every variant as a separate person.
void main() {
  group('artistKey groups spellings of one artist', () {
    test('capitalisation only — the case that showed Lady Gaga twice', () {
      expect(artistKey('Lady GaGa'), artistKey('Lady Gaga'));
      expect(artistKey('DAFT PUNK'), artistKey('Daft Punk'));
    });

    test('accents', () {
      expect(artistKey('Beyoncé'), artistKey('Beyonce'));
      expect(artistKey('Sinéad O’Connor'), artistKey("Sinead O'Connor"));
      expect(artistKey('Björk'), artistKey('Bjork'));
      expect(artistKey('Alizée'), artistKey('Alizee'));
    });

    test('punctuation and spacing', () {
      expect(artistKey('AC/DC'), artistKey('AC DC'));
      expect(artistKey('P!nk'), artistKey('P nk'));
      expect(artistKey('Jay-Z'), artistKey('Jay Z'));
    });

    test('a leading "the" is dropped — artists only', () {
      expect(artistKey('The Beatles'), artistKey('Beatles'));
      expect(artistKey('The Doors'), artistKey('Doors'));
      // normKey (used for ALBUM titles) must NOT do this: the word is part of the title.
      expect(normKey('The Wall'), isNot(normKey('Wall')));
    });

    test('genuinely different artists stay apart', () {
      expect(artistKey('Michael Jackson'), isNot(artistKey('Janet Jackson')));
      expect(artistKey('Lady Gaga'), isNot(artistKey('Lady Gaga feat. Beyoncé')));
      expect(artistKey('Justice'), isNot(artistKey('Justin')));
    });
  });

  group('canonicalName picks the spelling to show', () {
    test('the most-used spelling wins', () {
      expect(canonicalName({'Lady GaGa': 1, 'Lady Gaga': 12}), 'Lady Gaga');
      expect(canonicalName({'BEYONCE': 9, 'Beyoncé': 2}), 'BEYONCE');
    });

    test('on a tie, the tidiest capitalisation wins — not alphabetical luck', () {
      // 'Lady GaGa' sorts before 'Lady Gaga' in plain string order, so a naive tie-break would
      // pick the odd one.
      expect(canonicalName({'Lady GaGa': 3, 'Lady Gaga': 3}), 'Lady Gaga');
      expect(canonicalName({'DJ SNAKE': 2, 'DJ Snake': 2}), 'DJ Snake');
      expect(canonicalName({'daft punk': 2, 'Daft Punk': 2}), 'Daft Punk');
    });

    test('a single spelling is returned untouched', () {
      expect(canonicalName({'Røyksopp': 4}), 'Røyksopp');
    });
  });
}
