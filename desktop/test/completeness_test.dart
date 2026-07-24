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

  group('catalogues that spell a title differently', () {
    test('the same song written two ways is still the same song', () {
      // MusicBrainz: "If You Want It to Be Good Girl". The ripper: "If You Want to Be a Good Girl".
      // This one title made an eleven-track album look incomplete on its own pressing.
      final c = matchAlbumTracks(
        [_o(10, 'If You Want It to Be Good Girl (Get Yourself a Bad Boy)', 290)],
        [_t('If You Want to Be a Good Girl (Get Yourself a Bad Boy)', 290)],
        'Backstreet Boys',
      );
      expect(c.complete, isTrue);
    });

    test('but a radio edit is still not the album cut', () {
      // Both sides are nearly the same words; only the marker separates them, and it must.
      final c = matchAlbumTracks(
        [_o(1, "Everybody (Backstreet's Back) (radio edit)", 225)],
        [_t("Everybody (Backstreet's Back)", 225)],
        'Backstreet Boys',
      );
      expect(c.slots.first.missing, isTrue);
      expect(c.slots.last.index, -1, reason: 'en het bestand blijft zichtbaar');
    });

    test('two different songs are not folded together by a shared word', () {
      final c = matchAlbumTracks([_o(1, 'Like a Child', 269)], [_t('Like a Prayer', 269)], 'X');
      expect(c.slots.first.missing, isTrue);
    });

    test('and the running time still has to agree', () {
      final c = matchAlbumTracks(
        [_o(10, 'If You Want It to Be Good Girl', 290)],
        [_t('If You Want to Be a Good Girl', 620)],
        'Backstreet Boys',
      );
      expect(c.slots.first.missing, isTrue);
    });
  });

  group('albumTrackCount', () {
    test('a radio edit is a bonus, not a twelfth track', () {
      // This inflated the count from 11 to 12, which ruled out every 11-track pressing of an
      // 11-track album and handed the page a Malaysian double CD instead.
      final tracks = [
        _t('Everybody', 225, path: '$_root\\01 - Everybody (Radio Edit).flac'),
        _t('As Long as You Love Me', 213),
        _t('All I Have to Give', 274),
      ];
      expect(albumTrackCount(tracks), 2);
    });

    test('a plain album counts every file', () {
      expect(albumTrackCount([_t('Cozy', 209), _t('Alien Superstar', 216)]), 2);
    });
  });

  group('shortlistPressings', () {
    test('smallest that fits first — the real Backstreet\'s Back counts', () {
      // MusicBrainz's ten pressings of the record, in preference order, against the eleven album
      // tracks on disk. The 11s must be tried before the 16.
      const counts = [16, 11, 13, 14, 14, 12, 12, 11, 13, 11];
      expect(shortlistPressings(counts, 11), [1, 7, 9]);
    });

    test('owning two tracks does not shortlist a two-track pressing above the album', () {
      // Within one release group everything is a pressing of the same record, so "smallest that
      // holds it" is safe — and owning 2 of 16 must still reach the 16.
      expect(shortlistPressings([16, 12], 2), [1, 0]);
    });

    test('an unstated count is passed over rather than gambled on', () {
      expect(shortlistPressings([0, 0, 13], 11), [2]);
    });

    test('when nothing is big enough, the biggest near misses are tried', () {
      expect(shortlistPressings([8, 10, 9], 13), [1, 2, 0]);
    });

    test('no pressings, nothing to try', () {
      expect(shortlistPressings(const [], 11), isEmpty);
    });
  });

  group('pickPressing', () {
    AlbumCompleteness fit(List<String> pressing, List<String> owned) => matchAlbumTracks(
          [for (var i = 0; i < pressing.length; i++) _o(i + 1, pressing[i], 200)],
          [for (final t in owned) _t(t, 200)],
          'Backstreet Boys',
        );

    test('the pressing that IS the record beats the one that merely holds it', () {
      // The whole bug: an 11-track album, a 16-track pressing that contains it, and the 11-track
      // pressing that is it. Choosing by size picked the 16 and invented five gaps.
      const mine = ['Everybody', 'As Long as You Love Me', 'All I Have to Give'];
      final eleven = fit(mine, mine);
      final sixteen = fit([...mine, 'Missing You', 'Christmas Time'], mine);
      expect(pickPressing([sixteen, eleven]), 1);
      expect(pickPressing([eleven, sixteen]), 0, reason: 'volgorde mag niet uitmaken');
    });

    test('owning a fraction still resolves the whole record', () {
      // RENAISSANCE with two tracks: every candidate names them, so the smallest wins — and within
      // a release group the smallest is still the album, never a single.
      final big = fit(['Cozy', 'Cuff It', 'Energy', 'Church Girl'], ['Cozy', 'Cuff It']);
      expect(pickPressing([big]), 0);
      expect(big.namesEverything, isTrue);
      expect(big.missing, hasLength(2));
    });

    test('a pressing that does not hold your music loses to a smaller one that does', () {
      const mine = ['Everybody', 'As Long as You Love Me'];
      final wrong = fit(['Quit Playing Games', 'Anywhere for You', 'Darlin\''], mine);
      final right = fit(mine, mine);
      expect(wrong.namesEverything, isFalse);
      expect(pickPressing([wrong, right]), 1);
    });

    test('when nothing holds everything, the best coverage wins rather than none', () {
      // A described record is more use than no record — but the page has to say so.
      const mine = ['Everybody', 'As Long as You Love Me', 'All I Have to Give'];
      final one = fit(['Everybody'], mine);
      final two = fit(['Everybody', 'As Long as You Love Me'], mine);
      expect(pickPressing([one, two]), 1);
      expect(two.namesEverything, isFalse);
    });

    test('no candidates, no answer', () {
      expect(pickPressing(const []), -1);
    });
  });

  group('bonusTracks', () {
    test('what the other pressings have that yours does not', () {
      final mine = [_o(1, 'Everybody', 225), _o(2, 'As Long as You Love Me', 213)];
      final us = [_o(1, 'Everybody', 225), _o(4, 'Missing You', 265)];
      final my2 = [_o(1, 'Christmas Time', 257)];
      final out = bonusTracks(mine, [('CD · US · 1997', us), ('CD · MY · 1997', my2)]);
      expect(out.map((b) => b.track.title), ['Missing You', 'Christmas Time']);
      expect(out.first.edition, 'CD · US · 1997');
    });

    test('a title you already have is never a bonus, however it is spelt', () {
      final mine = [_o(1, '10,000 Promises', 240)];
      final other = [_o(1, '10.000 Promises', 240), _o(2, 'Like a Child', 269)];
      final out = bonusTracks(mine, [('CD · JP', other)]);
      expect(out.map((b) => b.track.title), ['Like a Child']);
    });

    test('the same extra on two pressings is listed once, credited to the first', () {
      final mine = [_o(1, 'Everybody', 225)];
      final a = [_o(2, 'Missing You', 265)];
      final b = [_o(2, 'Missing You', 265)];
      final out = bonusTracks(mine, [('CD · US', a), ('CD · AU', b)]);
      expect(out, hasLength(1));
      expect(out.single.edition, 'CD · US');
    });
  });

  group('AlbumSlot numbering', () {
    test('a double album says which disc, but tags a number that counts through', () {
      // The Malaysian pressing: 13 tracks then 3 more. Printed raw, disc two read "1, 2, 3" after
      // track 13 — and two tracks sharing a number is what tears an album into editions.
      final official = [
        _o(1, 'Everybody', 225),
        _o(2, 'As Long as You Love Me', 213),
        ChoiceTrack('1', 'Christmas Time', 257, disc: 2),
        ChoiceTrack('2', 'Quit Playin\' Games (E-Smoove vocal mix)', 410, disc: 2),
      ];
      final c = matchAlbumTracks(official, const [], 'Backstreet Boys');

      expect(c.slots.map((s) => s.label), ['1-1', '1-2', '2-1', '2-2']);
      expect(c.slots.map((s) => s.number), [1, 2, 3, 4], reason: 'geen twee keer hetzelfde nummer');
      expect(c.slots.map((s) => s.disc), [1, 1, 2, 2]);
    });

    test('a single disc shows a bare number', () {
      final c = matchAlbumTracks([_o(4, 'CUFF IT', 225)], const [], 'Beyoncé');
      expect(c.slots.single.label, '4');
      expect(c.slots.single.number, 4);
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
