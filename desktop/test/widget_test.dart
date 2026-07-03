// Minimal smoke test — the app relies on native (window_manager/media_kit)
// initialisation that isn't available in the widget-test harness, so we only
// assert that the model layer behaves.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/models.dart';

void main() {
  test('Album exposes the first available cover', () {
    final album = Album('X', 'Y', [
      Track(path: 'a', title: 'a', artist: 'Y', album: 'X'),
    ]);
    expect(album.cover, isNull);
    expect(album.tracks.length, 1);
  });
}
