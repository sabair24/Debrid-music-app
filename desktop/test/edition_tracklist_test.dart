/// "Take this pressing's numbering", and the tracklist it needs to do it.
///
/// The picker lists a whole master off one request and fills each row in as it comes into view.
/// That lookup returns the scans AND the tracklist in one answer — but only the scans were kept,
/// so a Discogs pressing never had a tracklist and the app said "Deze uitgave geeft geen
/// nummering" about a release whose six tracks were on screen at that moment.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/editions.dart';

void main() {
  /// A row exactly as the picker makes it: named off the master's versions listing, with nothing
  /// looked up yet — which is why `detailed` is false here and true by default everywhere else.
  ReleaseChoice bare() => const ReleaseChoice(
        source: EditionSource.discogs,
        releaseId: 805205, // Âme — Rej, Defected DFTD138CDX
        format: 'CD',
        label: 'Defected',
        catno: 'DFTD138CDX',
        country: 'UK',
        year: 2006,
        detailed: false,
      );

  const rej = <ChoiceTrack>[
    ChoiceTrack('1', 'Rej (Original)', 481),
    ChoiceTrack('2', 'Rej (Pastaboys Club Mix)', 464),
    ChoiceTrack('3', 'Rej (Pastaboys Dub Mix)', 402),
    ChoiceTrack('4', 'Rej (A Hundred Birds Remix)', 478),
    ChoiceTrack('5', 'Rej (A Hundred Birds Beatless Mix)', 295),
    ChoiceTrack('6', 'Rej (Original Beatless Mix)', 162),
  ];

  test('a row starts without a tracklist — nobody has asked yet', () {
    expect(bare().hasTracklist, isFalse);
    expect(bare().detailed, isFalse,
        reason: 'en dat is niet hetzelfde als "deze uitgave heeft er geen"');
  });

  test('the lookup that brings the scans brings the numbering with it', () {
    final detailed = bare().withArt(
      front: const ChoiceImage('front.jpg', 'front-t.jpg'),
      disc: const ChoiceImage('cd.jpg', 'cd-t.jpg'),
      tracks: rej,
    );

    expect(detailed.hasTracklist, isTrue, reason: 'dit is de fout die de melding veroorzaakte');
    expect(detailed.tracklist, hasLength(6));
    expect(detailed.tracklist.first.title, 'Rej (Original)');
    expect(detailed.tracklist.last.position, '6');
    // And the art still arrives, which is what this method was for.
    expect(detailed.hasDisc, isTrue);
    expect(detailed.detailed, isTrue);
  });

  test('a caller that only knows about art cannot erase a tracklist', () {
    // withArt is called from more than one place. Passing no tracks must keep what is there rather
    // than quietly blanking it — that is how this was lost in the first place.
    final withList = bare().withArt(tracks: rej);
    final again = withList.withArt(front: const ChoiceImage('f.jpg', 'f.jpg'));

    expect(again.hasTracklist, isTrue);
    expect(again.tracklist, hasLength(6));
  });

  test('an empty answer leaves the row as it was', () {
    final withList = bare().withArt(tracks: rej);
    expect(withList.withArt(tracks: const []).tracklist, isEmpty,
        reason: 'een lege lijst doorgeven is een expliciete keuze, geen ongeluk');
  });
}
