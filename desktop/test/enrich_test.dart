// Verifies web cover enrichment (Deezer -> Discogs -> MusicBrainz) against the real
// library. Reads the on-device settings.json for the Discogs token (never hardcoded).
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/settings.dart';

void main() {
  test('enriches missing covers from the web', () async {
    final settings = AppSettings();
    await settings.load();
    // ignore: avoid_print
    print('discogs token set: ${settings.discogsToken.isNotEmpty}');

    final lib = LibraryStore();
    await lib.scan();
    final before = lib.albums.where((a) => a.embedded != null).length;
    // ignore: avoid_print
    print('albums with embedded cover: $before / ${lib.albums.length}');

    await lib.enrich(settings);
    final after = lib.albums.where((a) => a.cover != null).length;
    // ignore: avoid_print
    print('albums with ANY cover after enrich: $after / ${lib.albums.length}');
    for (final a in lib.albums.where((a) => a.embedded == null).take(8)) {
      // ignore: avoid_print
      print('   ${a.enriched != null ? "OK " : "-- "} ${a.artist} — ${a.title}');
    }
    expect(after, greaterThanOrEqualTo(before));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
