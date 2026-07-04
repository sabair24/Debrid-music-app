// Verifies the Deezer catalog flow: search artist → albums → album tracks.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/catalog.dart';

void main() {
  test('artist -> albums -> tracks', () async {
    final c = CatalogService();
    final artists = await c.searchArtists('michael jackson');
    // ignore: avoid_print
    print('artists: ${artists.length}; first=${artists.isEmpty ? "-" : "${artists.first.name} (${artists.first.albumCount} albums, pic=${artists.first.picture != null})"}');
    expect(artists.isNotEmpty, true);

    final albums = await c.artistAlbums(artists.first.id);
    // ignore: avoid_print
    print('albums: ${albums.length}; sample=${albums.take(4).map((a) => "${a.title} [${a.year ?? "?"}]").toList()}');
    expect(albums.isNotEmpty, true);

    final (album, tracks) = await c.albumTracks(albums.first.id);
    // ignore: avoid_print
    print('album=${album?.title} cover=${album?.cover != null} tracks=${tracks.length}');
    for (final t in tracks.take(4)) {
      // ignore: avoid_print
      print('   ${t.position}. ${t.title} (${t.durationLabel}) — ${t.artist}');
    }
    expect(tracks.isNotEmpty, true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
