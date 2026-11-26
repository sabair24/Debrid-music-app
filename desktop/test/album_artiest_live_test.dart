// Live: Chimène Badi "Entre nous" (Deezer 175653082) — 43 nummers, van Chimène Badi, ook als je er via het duet van Julie Zenatti
// ("Zina (ici ou là-bas)") komt. Saber, 26-11-2026.
@Tags(['live'])
library;

import 'package:debridmusic/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Entre nous: alle 43 nummers, en de artiest van de plaat', () async {
    final (album, nummers) = await CatalogService().albumTracks(175653082);
    expect(album, isNotNull);
    expect(album!.artiest, 'Chimène Badi');
    expect(nummers.length, album.trackCount);
    expect(nummers.length, greaterThan(25));
    expect(albumArtiestVoorPagina('Julie Zenatti', album.artiest), 'Chimène Badi');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
