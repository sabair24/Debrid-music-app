import 'package:debridmusic/organize.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which of a search's results count as "the same track from another peer".
///
/// Get this wrong in the permissive direction and the download race — which ranks candidates by
/// quality — happily fetches the biggest file among them, which may be a different recording
/// altogether. That is not hypothetical: clicking "02 Aerodynamic.flac" (3:27, 25 MB) delivered
/// "08 - One More Time + Aerodynamic.flac" (6:10, 268 MB), a medley of two songs.
void main() {
  albumPage();
  test('a longer title containing the clicked one is NOT the same track', () {
    // The exact pair that went wrong. Containment scores this 1.0: {aerodynamic} sits entirely
    // inside {one, more, time, aerodynamic}. The running times are what give it away.
    expect(
      sameRecording('02 Aerodynamic.flac', 207, '08 - One More Time + Aerodynamic.flac', 370),
      isFalse,
    );
  });

  test('...and still not when neither peer states a running time', () {
    expect(sameRecording('02 Aerodynamic.flac', null, '08 - One More Time + Aerodynamic.flac', null), isFalse);
  });

  test('the same track named differently by different peers still matches', () {
    expect(sameRecording('02 Aerodynamic.flac', 207, 'Daft Punk - Aerodynamic.flac', 207), isTrue);
    expect(sameRecording('02 Aerodynamic.flac', 207, '2. Aerodynamic.flac', 209), isTrue);
    expect(sameRecording('02 Aerodynamic.flac', 207, '11 - Aerodynamic.flac', 205), isTrue);
  });

  test('a track number prefix is not part of the title', () {
    expect(sameRecording('01 - Everybody.flac', 240, 'Artist - Everybody.flac', 240), isTrue);
  });

  test('rips of one track differ by a few seconds, not by minutes', () {
    // Gapless vs faded rips of the same song disagree slightly; a different song does not.
    expect(sameRecording('Aerodynamic.flac', 207, 'Aerodynamic.flac', 214), isTrue);
    expect(sameRecording('Aerodynamic.flac', 207, 'Aerodynamic.flac', 260), isFalse);
  });

  test('different songs never match, however they are named', () {
    expect(sameRecording('02 Aerodynamic.flac', 207, '03 Digital Love.flac', 301), isFalse);
    expect(sameRecording('Aerodynamic.flac', 207, 'Aerodynamic (Slum Village Remix).flac', 215), isFalse);
  });

  test('a remix is not the original even at a similar length', () {
    expect(
      sameRecording('02 - Aerodynamic.flac', 207, '02 - Aerodynamic (Daft Punk Remix).flac', 210),
      isFalse,
    );
  });
}

/// The album page matches a bare Deezer title against a peer's filename, which also carries the
/// artist and a track number. Same two traps, so the same guards have to hold.
void albumPage() {
  test('a medley containing the title is not that track', () {
    expect(fileOffersTitle('Aerodynamic', 207, '08 - One More Time + Aerodynamic.flac', 370), isFalse);
  });

  test('a remix of about the same length is not that track', () {
    expect(fileOffersTitle('Aerodynamic', 207, 'Aerodynamic (Slum Village Remix).flac', 215), isFalse);
  });

  test('the artist and track number in the filename are not held against it', () {
    expect(fileOffersTitle('Aerodynamic', 207, '02 - Daft Punk - Aerodynamic.flac', 209), isTrue);
  });
}
