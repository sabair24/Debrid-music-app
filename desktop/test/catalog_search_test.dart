import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/catalog.dart';

void main() {
  test('searchAlbums returns albums with artist + cover', () async {
    final r = await CatalogService().searchAlbums('daft punk');
    print('albums: ${r.length}; first=${r.isEmpty ? "-" : "${r.first.artist} — ${r.first.album.title} (cover=${r.first.album.cover != null})"}');
    expect(r.isNotEmpty, true);
    expect(r.first.artist.isNotEmpty, true);
  });

  test('searchTracks returns tracks with artist', () async {
    final r = await CatalogService().searchTracks('one more time daft punk');
    print('tracks: ${r.length}; first=${r.isEmpty ? "-" : "${r.first.artist} — ${r.first.title}"}');
    expect(r.isNotEmpty, true);
    expect(r.first.query.isNotEmpty, true);
  });
}
