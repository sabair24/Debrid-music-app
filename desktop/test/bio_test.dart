// Verifies artist bios load from TheAudioDB (prefers NL, falls back to EN).
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/settings.dart';

void main() {
  test('artist bios (TheAudioDB)', () async {
    final s = AppSettings();
    await s.load();
    final e = CoverEnricher(s);
    for (final name in ['Michael Jackson', 'Adele', 'Stromae']) {
      final bio = await e.fetchArtistBio(name);
      // ignore: avoid_print
      print('$name -> ${bio == null ? "no bio" : "${bio.length} chars: ${bio.substring(0, bio.length.clamp(0, 90))}…"}');
    }
    // At least one well-known artist should return a bio.
    final mj = await e.cachedBio('Michael Jackson');
    expect(mj != null && mj.length > 100, true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
