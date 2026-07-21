import 'package:debridmusic/organize.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which of a search's results count as "the same track from another peer".
///
/// Get this wrong in the permissive direction and the download race — which fetches whichever
/// candidate a peer sends first — delivers a different recording altogether. Twice, for real:
/// clicking "02 Aerodynamic.flac" (3:27) first delivered a 6:10 medley of 268 MB, and after that
/// was fixed on running time, "Aerodynamic Beats + Forget About the World" at 3:31 — four seconds
/// from the real track, so no clock separates them.
///
/// Peers are given as FULL paths on purpose: the folders are the evidence that tells an artist
/// name apart from another song's title.
void main() {
  const clicked = r'@shared\Daft Punk\Discovery\02 - Aerodynamic.flac';

  group('a different song is never the same track', () {
    test('a medley that contains the title', () {
      expect(
        sameRecording(clicked, 207, r'@me\Daft Punk\Alive 2007\08 - One More Time + Aerodynamic.flac', 370),
        isFalse,
      );
    });

    test('another song that shares a word, at almost the same length', () {
      // The one that got through the running-time check: 3:31 against 3:27.
      expect(
        sameRecording(
            clicked, 207, r'@me\Daft Punk - Gabrielle\Alive 2007\09 - Aerodynamic Beats + Forget About the World.flac', 211),
        isFalse,
      );
    });

    test('a remix, however close the length', () {
      // Aerodynamic is 3:27; the Slum Village remix of it is 3:35.
      expect(sameRecording(clicked, 207, r'@me\Daft Punk\04 - Aerodynamic (Slum Village Remix).flac', 215), isFalse);
      expect(sameRecording(clicked, 207, r'@me\Daft Punk\02 - Aerodynamic (Daft Punk Remix).flac', 210), isFalse);
    });

    test('an unrelated track', () {
      expect(sameRecording(clicked, 207, r'@me\Daft Punk\Discovery\03 - Digital Love.flac', 301), isFalse);
    });
  });

  group('the same track, named however a peer likes', () {
    test('artist and album spelled out in the filename', () {
      expect(sameRecording(clicked, 207, r'@me\music\Daft Punk - Discovery - 02 - Aerodynamic.flac', 209), isTrue);
    });

    test('bare title, no artist anywhere', () {
      expect(sameRecording(clicked, 207, r'@me\Aerodynamic.flac', 208), isTrue);
    });

    test('a different track number, and a few seconds of rip difference', () {
      expect(sameRecording(clicked, 207, r'@me\Daft Punk\Discovery\11 - Aerodynamic.flac', 214), isTrue);
    });

    test('the artist named only in the folder on one side', () {
      expect(sameRecording(clicked, 207, r'@me\flac\Daft Punk - Aerodynamic.flac', 207), isTrue);
    });
  });

  group('rips that disagree by more than a rip should', () {
    test('fifty seconds apart is a different recording', () {
      expect(sameRecording(clicked, 207, r'@me\Daft Punk\Discovery\02 - Aerodynamic.flac', 260), isFalse);
    });
  });

  /// The album page matches a bare Deezer title against a peer's path. No second filename explains
  /// the extra words there, so the artist's own name has to.
  group('album page, matching a catalogue title', () {
    test('a medley containing the title is not that track', () {
      expect(
        fileOffersTitle('Aerodynamic', 207, 'Daft Punk', r'@me\Alive 2007\08 - One More Time + Aerodynamic.flac', 370),
        isFalse,
      );
    });

    test('another song sharing a word is not that track', () {
      expect(
        fileOffersTitle(
            'Aerodynamic', 207, 'Daft Punk', r'@me\Alive 2007\09 - Aerodynamic Beats + Forget About the World.flac', 211),
        isFalse,
      );
    });

    test('a remix is not that track', () {
      expect(
        fileOffersTitle('Aerodynamic', 207, 'Daft Punk', r'@me\04 - Aerodynamic (Slum Village Remix).flac', 215),
        isFalse,
      );
    });

    test('the artist and track number in the filename are not held against it', () {
      expect(
        fileOffersTitle('Aerodynamic', 207, 'Daft Punk', r'@me\Discovery\02 - Daft Punk - Aerodynamic.flac', 209),
        isTrue,
      );
    });

    test('album folders are not held against it either', () {
      expect(
        fileOffersTitle('Aerodynamic', 207, 'Daft Punk', r'@me\Daft Punk\Discovery\02 - Aerodynamic.flac', 207),
        isTrue,
      );
    });
  });
}
