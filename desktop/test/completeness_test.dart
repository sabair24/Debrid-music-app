import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/models.dart';

const _root = r'D:\Flac music 2024\Albums\Beyoncé\RENAISSANCE';

Track _t(String title, int seconds, {String? path, String artist = 'Beyoncé', int no = 0}) => Track(
      path: path ?? '$_root\\${no.toString().padLeft(2, '0')} - $title.flac',
      title: title,
      artist: artist,
      album: 'RENAISSANCE',
      trackNo: no,
      duration: Duration(seconds: seconds),
    );

ChoiceTrack _o(int n, String title, int? seconds) => ChoiceTrack('$n', title, seconds);

void main() {
  group('matchAlbumTracks', () {
    test('one owned track out of sixteen is one owned track out of sixteen', () {
      // The case that started this: RENAISSANCE showed "1 nummers" and nothing else, so the album
      // page could not tell you that fifteen of its tracks were simply not there.
      final official = [
        _o(1, "I'M THAT GIRL", 233),
        _o(2, 'COZY', 209),
        _o(3, 'ALIEN SUPERSTAR', 216),
        _o(4, 'CUFF IT', 225),
        _o(5, 'ENERGY', 116),
      ];
      final c = matchAlbumTracks(official, [_t('CUFF IT', 225, no: 4)], 'Beyoncé');

      expect(c.total, 5);
      expect(c.have, 1);
      expect(c.missing, hasLength(4));
      expect(c.complete, isFalse);
      expect(c.slots[3].track, isNotNull);
      expect(c.slots[3].number, 4, reason: 'the release numbers it, not the file');
      expect(c.slots.where((s) => s.missing).map((s) => s.title),
          ["I'M THAT GIRL", 'COZY', 'ALIEN SUPERSTAR', 'ENERGY']);
    });

    test('a complete album says so, and every row keeps the official number', () {
      final official = [_o(1, 'Intro', 60), _o(2, 'Cozy', 209)];
      final c = matchAlbumTracks(official, [_t('Cozy', 209, no: 7), _t('Intro', 60, no: 3)], 'Beyoncé');

      expect(c.complete, isTrue);
      expect(c.have, 2);
      // The files carry 3 and 7 in their tags; the release says 1 and 2.
      expect(c.slots.map((s) => s.number), [1, 2]);
      expect(c.slots.map((s) => s.track!.title), ['Intro', 'Cozy']);
    });

    test('spelling is normalised, so a curly apostrophe is not a missing track', () {
      final c = matchAlbumTracks([_o(1, 'I’M THAT GIRL', 233)], [_t("i'm that girl", 233)], 'Beyoncé');
      expect(c.complete, isTrue);
    });

    test('a live take of the same title is not the studio track', () {
      // Same words, six minutes longer. Counting it as owned would hide a track you don't have and
      // — worse — stop the download that would fetch it.
      final c = matchAlbumTracks([_o(1, 'Cozy', 209)], [_t('Cozy', 574)], 'Beyoncé');
      expect(c.slots.first.missing, isTrue);
      // …and the file itself is still listed, at the end, still playable.
      expect(c.slots, hasLength(2));
      expect(c.slots.last.index, -1);
      expect(c.slots.last.track!.duration!.inSeconds, 574);
    });

    test('a file the release does not name is never dropped', () {
      // A wrong or partial tracklist must not be able to make music you own disappear from its
      // own page. Anything unaccounted for comes back at the end.
      final c = matchAlbumTracks([_o(1, 'Cozy', 209)], [_t('Cozy', 209), _t('Hidden Bonus', 130)], 'Beyoncé');
      expect(c.slots, hasLength(2));
      expect(c.slots.last.index, -1);
      expect(c.slots.last.title, 'Hidden Bonus');
      // have/total count the rows on the page, so the extra counts towards both and the album
      // still reads as complete — there is nothing here to download.
      expect(c.have, 2);
      expect(c.total, 2);
      expect(c.complete, isTrue);
    });

    test('two entries with the same title claim two different files', () {
      final c = matchAlbumTracks(
        [_o(1, 'Interlude', 45), _o(9, 'Interlude', 45)],
        [_t('Interlude', 45, no: 1, path: '$_root\\01 - Interlude.flac'),
         _t('Interlude', 45, no: 9, path: '$_root\\09 - Interlude.flac')],
        'Beyoncé',
      );
      expect(c.complete, isTrue);
      expect(c.slots.map((s) => s.track!.path).toSet(), hasLength(2),
          reason: 'one file cannot fill two slots');
    });

    test('an exact title is not stolen by a looser match on another entry', () {
      // 'Move' is a subset of 'Move Your Body'. Pass one settles every exact title across the whole
      // list before any fuzzier rule runs, so the entry that names a track outright always wins it.
      final c = matchAlbumTracks(
        [_o(1, 'Move', 200), _o(2, 'Move Your Body', 240)],
        [_t('Move Your Body', 240), _t('Move', 200)],
        'Beyoncé',
      );
      expect(c.slots[0].track!.title, 'Move');
      expect(c.slots[1].track!.title, 'Move Your Body');
    });

    test('with no timings on either side the title alone decides', () {
      // Discogs often has no duration; refusing to match then would report a full album as empty.
      final c = matchAlbumTracks([_o(1, 'Cozy', null)],
          [Track(path: '$_root\\01 - Cozy.flac', title: 'Cozy', artist: 'Beyoncé', album: 'RENAISSANCE')],
          'Beyoncé');
      expect(c.complete, isTrue);
    });

    test('an empty tracklist yields nothing to show', () {
      final c = matchAlbumTracks(const [], [_t('Cozy', 209)], 'Beyoncé');
      expect(c.total, 1, reason: 'the file is still a row');
      expect(c.slots.single.index, -1);
      expect(c.have, 1);
    });

    test('the source is carried through for the line under the count', () {
      final c = matchAlbumTracks([_o(1, 'Cozy', 209)], const [], 'Beyoncé', source: 'MusicBrainz');
      expect(c.source, 'MusicBrainz');
      expect(c.have, 0);
      expect(c.missing, hasLength(1));
    });
  });

  group('pickPressing', () {
    test('never a pressing smaller than what is already on disk', () {
      // The Backstreet Boys case: MusicBrainz ranked a 10-track pressing first, the library holds
      // 13, and three tracks the user owns were filed as "not on this release" — with no bar to
      // say so, because by that pressing nothing was missing.
      expect(pickPressing([10, 13, 16], 13), 1);
    });

    test('the ranking is otherwise obeyed — the first that fits wins, not the biggest', () {
      expect(pickPressing([13, 16, 42], 13), 0);
    });

    test('a bigger pressing is exactly what this page is for', () {
      // Owning one track of sixteen must still resolve the sixteen-track record. Asking the search
      // for expectedTracks would have thrown it away for being too big.
      expect(pickPressing([16, 1], 1), 0);
    });

    test('an unstated track count is passed over rather than gambled on', () {
      expect(pickPressing([0, 0, 13], 13), 2);
    });

    test('but a described record beats no record when nothing qualifies', () {
      expect(pickPressing([10, 11], 13), 0);
      expect(pickPressing([0, 0], 13), 0);
    });

    test('no pressings, no answer', () {
      expect(pickPressing(const [], 13), -1);
    });
  });

  group('AlbumSlot.number', () {
    test('the release decides; the file only fills in when it does not', () {
      expect(AlbumSlot(index: 3, official: _o(4, 'CUFF IT', 225), track: _t('CUFF IT', 225, no: 20)).number, 4);
      expect(AlbumSlot(index: 3, track: _t('CUFF IT', 225, no: 20)).number, 20);
      expect(AlbumSlot(index: 3, track: _t('CUFF IT', 225)).number, 4, reason: 'index + 1');
    });

    test('a non-numeric position (vinyl A1) falls back rather than showing zero', () {
      expect(AlbumSlot(index: 0, official: ChoiceTrack('A1', 'Cozy', 209)).number, 1);
    });
  });
}
