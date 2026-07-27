// A row that is still loading must not claim to know anything.
//
// The gallery shows its rows as soon as the pressings are named, with the scans filling in behind
// them. That is the whole point of the change — but for the second or two in between, the three
// thumbnails drew a cross with the tooltip "Deze uitgave heeft geen hoes", about a pressing nobody
// had asked about yet. The badges beside them already got this right and said "scans ophalen…";
// only the pictures were stating it flatly.
//
// [ReleaseChoice.detailed] is the distinction, and it existed before the rows did — it just was not
// being set on the MusicBrainz side, because until now those rows were only ever built after their
// scans had arrived.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/editions.dart';

ReleaseChoice row({bool detailed = true, ChoiceImage? front}) => ReleaseChoice(
      source: EditionSource.musicbrainz,
      mbid: 'x',
      format: 'CD',
      country: 'FR',
      front: front,
      detailed: detailed,
    );

/// What the picker decides to draw, kept here so the rule can be tested without a widget tree.
/// Mirrors `_thumb`: a missing image on an undetailed row is "waiting", never "none".
String slotState(ReleaseChoice c, ChoiceImage? img) =>
    img != null ? 'image' : (c.detailed ? 'none' : 'waiting');

void main() {
  const img = ChoiceImage('http://x/full.jpg', 'http://x/thumb.jpg');

  test('a row whose scans have not been fetched is waiting, not empty', () {
    final c = row(detailed: false);
    expect(slotState(c, c.front), 'waiting');
    expect(slotState(c, c.back), 'waiting');
    expect(slotState(c, c.disc), 'waiting');
  });

  test('once the scans are in, a missing one really is missing', () {
    final c = row(detailed: true, front: img);
    expect(slotState(c, c.front), 'image');
    expect(slotState(c, c.back), 'none', reason: 'asked, and the archive had none');
  });

  test('an image that arrived early is shown even while the rest is loading', () {
    // Discogs rows carry a thumbnail from the versions listing before their detail lookup runs.
    final c = row(detailed: false, front: img);
    expect(slotState(c, c.front), 'image');
    expect(slotState(c, c.back), 'waiting');
  });

  test('filling in the art marks the row as looked-up', () {
    final c = row(detailed: false).withArt(front: img);
    expect(c.detailed, isTrue);
    expect(slotState(c, c.back), 'none',
        reason: 'withArt is the answer arriving; after it, silence means none');
  });

  test('the three roles are decided independently', () {
    final c = ReleaseChoice(
      source: EditionSource.musicbrainz,
      mbid: 'x',
      front: img,
      disc: img,
      detailed: true,
    );
    expect([slotState(c, c.front), slotState(c, c.back), slotState(c, c.disc)],
        ['image', 'none', 'image']);
  });
}
