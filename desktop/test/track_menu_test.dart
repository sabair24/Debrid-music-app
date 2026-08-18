/// What the track menu offers, and — above everything else — what comes last.
///
/// The menu now opens from four places: the album page, the Nummers tab, the queue and the
/// now-playing screen, on a thumb, a mouse and a remote. That is a lot of ways to reach one red
/// irreversible button, and the rules that keep it safe are not the kind of thing a screenshot
/// shows. [TrackMenu.itemsFor] is deliberately pure so they can be checked here instead: building
/// anything else from `main.dart` needs fourteen providers and a libmpv a test run does not have.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';

void main() {
  /// The ordinary case: your own file, on a record, by somebody with a name.
  List<TrackAction> full({bool onTv = false}) => TrackMenu.itemsFor(
        hasAlbum: true,
        namedArtist: true,
        inLibrary: true,
        onTv: onTv,
      );

  test('een nummer uit je bibliotheek krijgt alles, in deze volgorde', () {
    expect(full(), [
      TrackAction.album,
      TrackAction.artist,
      TrackAction.radio,
      TrackAction.move,
      TrackAction.delete,
    ]);
  });

  test('verwijderen staat altijd achteraan', () {
    // The one rule that must survive every future item added to this menu: nothing a stray thumb
    // or a stray press of OK can reach may sit underneath the red one.
    for (final onTv in [false, true]) {
      for (final hasAlbum in [false, true]) {
        for (final named in [false, true]) {
          final items = TrackMenu.itemsFor(
            hasAlbum: hasAlbum,
            namedArtist: named,
            inLibrary: true,
            onTv: onTv,
          );
          expect(items.last, TrackAction.delete,
              reason: 'onTv=$onTv album=$hasAlbum artiest=$named zet iets ónder verwijderen');
        }
      }
    }
  });

  test('wat niet in je bibliotheek staat, kun je niet bewerken', () {
    // The radio track on the now-playing screen: its “path” is a stream URL, so there is no file
    // to move and nothing to delete. Offering either would be a button that lies.
    final items = TrackMenu.itemsFor(hasAlbum: false, namedArtist: true, inLibrary: false);
    expect(items, isNot(contains(TrackAction.delete)));
    expect(items, isNot(contains(TrackAction.move)));
    expect(items, [TrackAction.artist, TrackAction.radio]);
  });

  test('geen album betekent alleen: geen weg naar het album', () {
    final items = TrackMenu.itemsFor(hasAlbum: false, namedArtist: true, inLibrary: true);
    expect(items, isNot(contains(TrackAction.album)));
    expect(items, containsAll([TrackAction.artist, TrackAction.radio, TrackAction.delete]));
  });

  test('zonder echte artiestnaam vallen artiest én radio weg', () {
    // Radio used to be offered unconditionally and then failed on “Onbekende artiest” — it starts
    // from the name, so it needs the same condition the artist page does.
    final items = TrackMenu.itemsFor(hasAlbum: true, namedArtist: false, inLibrary: true);
    expect(items, isNot(contains(TrackAction.artist)));
    expect(items, isNot(contains(TrackAction.radio)));
    expect(items, [TrackAction.album, TrackAction.move, TrackAction.delete]);
  });

  test('de tv krijgt een uitweg, en die vangt de eerste druk op', () {
    // A bottom sheet has no Cancel, and its drag handle cannot be grabbed with a remote. “Sluiten”
    // is both the way off and where the highlight parks — the one item that costs nothing.
    expect(full(onTv: true).first, TrackAction.close);
    expect(full(onTv: false), isNot(contains(TrackAction.close)));
  });

  test('nooit dubbel, en nooit leeg voor een nummer dat je hebt', () {
    for (final onTv in [false, true]) {
      final items = full(onTv: onTv);
      expect(items.toSet().length, items.length, reason: 'dezelfde regel twee keer');
      expect(items, isNotEmpty);
    }
  });
}
