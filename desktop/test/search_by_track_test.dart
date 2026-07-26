/// Searching for a SONG and being shown the record it is on.
///
/// Typing "Yasmine porselein" in the metadata editor found nothing, because there is no release by
/// that name — *Porselein* is a track on *Prêt-à-porter*. Discogs answers that question and this did
/// not, and knowing a song while wanting the album is at least as common as the reverse.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/musicbrainz.dart';

void main() {
  group('a recording knows every record it is on', () {
    test('all of them, not only the first', () {
      // A track sits on its album, on a single, and on three compilations. Keeping the first meant
      // a search by song could name one and hide the rest.
      final r = MbRecording.from(<String, dynamic>{
        'id': 'rec-1',
        'title': 'Porselein',
        'length': 231000,
        'artist-credit': [
          {'name': 'Yasmine'}
        ],
        'releases': [
          {
            'id': 'rel-2',
            'title': 'Het Beste Van',
            'release-group': {'primary-type': 'Album', 'secondary-types': ['Compilation']},
          },
          {
            'id': 'rel-1',
            'title': 'Prêt-à-porter',
            'release-group': {'primary-type': 'Album'},
          },
        ],
      });

      expect(r.title, 'Porselein');
      expect(r.artist, 'Yasmine');
      expect(r.seconds, 231);
      expect(r.releases.map((e) => e.title), ['Prêt-à-porter', 'Het Beste Van'],
          reason: 'het eigen album hoort voor de verzamelaar, ook al kwam het als tweede binnen');
      expect(r.releases.first.isStudioAlbum, isTrue);
      expect(r.releases.last.isCompilation, isTrue);
      // The old field still answers, so nothing that read it had to change.
      expect(r.onRelease, 'Prêt-à-porter');
    });

    /// The real shape of the problem, measured against MusicBrainz: "Porselein" by Yasmine sits on
    /// sixteen releases, of which exactly ONE is her own album. Listing them in the order the
    /// service returns them puts *30 kleinkunst klassiekers, deel 5* first and Prêt-à-porter
    /// eleventh.
    test('one studio album among fifteen compilations still comes first', () {
      final r = MbRecording.from(<String, dynamic>{
        'id': 'rec-1',
        'title': 'Porselein',
        'artist-credit': [
          {'name': 'Yasmine'}
        ],
        'releases': [
          for (var i = 0; i < 15; i++)
            {
              'id': 'comp-$i',
              'title': 'Verzamelaar $i',
              'release-group': {'primary-type': 'Album', 'secondary-types': ['Compilation']},
            },
          {
            'id': 'rel-1',
            'title': 'Prêt-à-porter',
            'release-group': {'primary-type': 'Album'},
          },
        ],
      });

      expect(r.releases.first.title, 'Prêt-à-porter');
      expect(r.releases, hasLength(16));
    });

    test('a release with no type at all sits between the two', () {
      // MusicBrainz leaves the primary type blank often enough — a live radio recording, say. Not an
      // album, but not a greatest-hits either, so it must not be ranked as one.
      final r = MbRecording.from(<String, dynamic>{
        'id': 'rec-1',
        'title': 'Porselein',
        'releases': [
          {
            'id': 'c',
            'title': 'Verzamelaar',
            'release-group': {'primary-type': 'Album', 'secondary-types': ['Compilation']},
          },
          {'id': 'u', 'title': 'Naamloos'},
          {
            'id': 'a',
            'title': 'Het album',
            'release-group': {'primary-type': 'Album'},
          },
        ],
      });
      expect(r.releases.map((e) => e.title), ['Het album', 'Naamloos', 'Verzamelaar']);
    });

    test('a release without an id is no use for pinning and is left out', () {
      final r = MbRecording.from(<String, dynamic>{
        'id': 'rec-1',
        'title': 'Porselein',
        'releases': [
          {'title': 'Naamloos zonder id'},
          {'id': 'rel-2', 'title': 'Prêt-à-porter'},
        ],
      });
      expect(r.releases.map((e) => e.title), ['Prêt-à-porter']);
      expect(r.onRelease, 'Prêt-à-porter');
    });

    test('no releases at all is not an error', () {
      final r = MbRecording.from(<String, dynamic>{'id': 'rec-1', 'title': 'Porselein'});
      expect(r.releases, isEmpty);
      expect(r.onRelease, isNull);
      expect(r.seconds, 0, reason: 'geen lengte is nul, niet een crash');
    });
  });
}
