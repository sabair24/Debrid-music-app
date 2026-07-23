import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/organize.dart';

/// The scenario from the screenshots: track 3 of the self-titled album, "Get Down (You're the One
/// for Me)", 3:52. It failed to download while a live 3:50 copy was plainly in the search results —
/// because the query carried the parenthetical and the apostrophe, and the fallback took every
/// audio result unfiltered. These pin down the query that finds it and the filter that keeps only
/// the right copies.
void main() {
  group('soulseekQuery', () {
    test('drops the parenthetical aside and the punctuation', () {
      // The bracketed part hurts Soulseek and is recovered by the title filter, so it comes off.
      expect(soulseekQuery('Backstreet Boys', 'Get Down (You’re the One for Me)'),
          'backstreet boys get down');
    });

    test('keeps a plain title whole', () {
      expect(soulseekQuery('Backstreet Boys', 'Anywhere for You'), 'backstreet boys anywhere for you');
    });

    test('an apostrophe splits rather than merges', () {
      // "I'll" must not become the term "ill", which no peer file matches.
      final q = soulseekQuery('Backstreet Boys', "I'll Never Break Your Heart");
      expect(q.contains('ill'), isFalse);
      expect(q, 'backstreet boys ll never break your heart');
    });

    test('a title that is all aside is kept rather than searched blank', () {
      expect(soulseekQuery('Bryan Adams', '(Everything I Do) I Do It for You'),
          isNot('bryan adams'));
      expect(soulseekQuery('X', '(Intro)'), contains('intro'));
    });
  });

  group('fileOffersTitle on the real Get Down copies', () {
    const title = 'Get Down (You’re the One for Me)';
    const dur = 232; // 3:52 on the album page

    test('accepts the full copy at 3:50', () {
      expect(
          fileOffersTitle(title, dur, 'Backstreet Boys',
              r"@peer\Backstreet Boys - Get Down (You're The One For Me).flac", 230),
          isTrue);
    });

    test('rejects the mistyped 3:33 copy — wrong word and wrong length', () {
      // "12 - Backstreet Boys - Get Down (Your the One for Me).flac", 3:33. "Your" is an unexplained
      // extra word AND the running time is 19s short; either alone is enough.
      expect(
          fileOffersTitle(title, dur, 'Backstreet Boys',
              r'@peer\12 - Backstreet Boys - Get Down (Your the One for Me).flac', 213),
          isFalse);
    });

    test('rejects an LP edit even at the same length', () {
      // "edit" is a version marker, so a same-duration different mix never passes as this recording.
      expect(
          fileOffersTitle(title, dur, 'Backstreet Boys',
              r"@peer\Get Down (You're the One for Me) [LP Edit No Rap].flac", 230),
          isFalse);
    });

    test('a broad "get down" search still narrows to this song, not another', () {
      // The query is broad on purpose; the filter is what stops a plain "Get Down" by someone else.
      expect(fileOffersTitle(title, dur, 'Backstreet Boys', r'@peer\Get Down.flac', 200), isFalse);
    });
  });
}
