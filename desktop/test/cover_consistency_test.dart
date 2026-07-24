import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

/// One sleeve, everywhere, the moment it changes.
///
/// Correcting a record's artwork while it plays used to leave three answers on screen at once: the
/// album page showed the new sleeve, the bar at the bottom showed the bytes captured when the track
/// opened, and clicking the art opened those same old bytes.
///
/// The fix is a wire — `library.addListener(() => player.refreshCover())` in main — feeding
/// [PlayerStore.refreshCover], which asks [LibraryStore.coverForTrack] again. PlayerStore itself
/// cannot be built in a test: it opens a libmpv Player in a field initialiser and `flutter test`
/// has no libmpv-2.dll, which is why now_playing_test.dart drives a fake instead. So what is pinned
/// here is the ANSWER that wire carries; that it is wired at all is checked in the running app.
Track _track(Directory root, String name, {String album = 'Rec', String artist = 'X'}) {
  final d = Directory('${root.path}${Platform.pathSeparator}$album')..createSync(recursive: true);
  final f = File('${d.path}${Platform.pathSeparator}$name')..writeAsBytesSync(List.filled(64, 7));
  return Track(
      path: f.path,
      title: name.replaceAll('.flac', ''),
      artist: artist,
      album: album,
      trackNo: 1,
      duration: const Duration(seconds: 200),
      isFlac: true);
}

Uint8List _bytes(int fill) => Uint8List.fromList(List.filled(32, fill));

void main() {
  late Directory root;
  late LibraryStore lib;
  setUp(() {
    root = Directory.systemTemp.createTempSync('covers');
    lib = LibraryStore()..configDirOverride = '${root.path}${Platform.pathSeparator}_cfg';
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('coverForTrack follows a corrected cover', () {
    final t = _track(root, '01 - Song.flac');
    lib.tracks.add(t);
    lib.rebuildAlbums();

    final album = lib.albums.single;
    album.embeddedCover = _bytes(1);
    expect(lib.coverForTrack(t), _bytes(1));

    // What applyCorrection does once a release is picked in the gallery.
    album.correctedCover = _bytes(2);
    expect(lib.coverForTrack(t), _bytes(2),
        reason: 'a hand-picked sleeve outranks the one in the file');
  });

  test('a track on no album page has no cover to offer, and that is not an error', () {
    final t = _track(root, '01 - Song.flac');
    // Never grouped into an album, so albumForPath knows nothing about it. refreshCover treats this
    // as "no answer yet" and keeps the bytes it has, rather than blanking the bar mid-regroup.
    expect(lib.coverForTrack(t), isNull);
  });

  test('a regroup re-points the cover at the album the track ended up on', () {
    final t = _track(root, '01 - Song.flac');
    lib.tracks.add(t);
    lib.rebuildAlbums();
    lib.albums.single.correctedCover = _bytes(4);
    expect(lib.coverForTrack(t), _bytes(4));

    // rebuildAlbums makes fresh Album objects; the snapshot has to survive it, or every correction
    // would be followed by the bar going blank.
    lib.rebuildAlbums();
    expect(lib.coverForTrack(t), _bytes(4),
        reason: 'the corrected sleeve must outlive the regroup that applying it triggers');
  });
}
