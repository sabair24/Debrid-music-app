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
      // Hier stond `{'BEYONCE': 9, 'Beyoncé': 2}` -> 'BEYONCE'. Sinds 05-09-2026 wint een ACCENT van
      // het aantal, en dat geval dus ook: er staat nu 'Beyoncé'. De reden staat in
      // `naamschade_test.dart` -- rippers strippen accenten en verzinnen ze nooit, dus bij twee
      // spellingen die alleen in tekens schelen is de meerderheid het bewijs van de schade.
      //
      // Het voorbeeld is vervangen door een dat hetzelfde bewijst zónder accenten in het spel te
      // brengen, zodat deze toets over het AANTAL blijft gaan.
      expect(canonicalName({'MICHAEL JACKSON': 9, 'Michael Jackson': 2}), 'MICHAEL JACKSON');
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

  group('een apostrof scheidt geen woorden', () {
    // **Gemeten op 05-09-2026.** Van de 261 namen op het scherm bleef er precies één groep in
    // tweeën staan: "Driver's Seed" en "Drivers Seed". [normKey] maakte van elk leesteken een
    // spatie, en een apostrof staat juist MIDDEN in een woord — "driver s" is iets anders dan
    // "drivers". Na de reparatie: nul paren, en elk ander getal van de meting onveranderd.
    test('DE KERN: dezelfde naam met en zonder apostrof is één artiest', () {
      expect(artistKey("Driver's Seed"), artistKey('Drivers Seed'));
      expect(artistKey("Guns N' Roses"), artistKey('Guns N Roses'));
    });

    test('en hetzelfde geldt voor titels', () {
      expect(normKey("Don't Stop the Music"), normKey('Dont Stop the Music'));
      expect(normKey("Rockin' Robin"), 'rockin robin');
    });

    test('DE GRENS: andere leestekens scheiden nog steeds wél', () {
      // Zonder deze grens zou "Love-Song" gelijk worden aan "Lovesong", en dat zijn twee namen.
      expect(normKey('Love-Song'), 'love song');
      expect(normKey('Love.Song'), 'love song');
      expect(normKey('Love/Song'), 'love song');
    });

    test('en twee echt verschillende namen blijven verschillend', () {
      expect(artistKey("Driver's Seed") == artistKey('Drivers Creed'), isFalse);
    });
  });
}
