// Verifies artist bios load from TheAudioDB (prefers NL, falls back to EN).
//
// **`_live_` in de naam, en daarom niet in de CI-lijst.** Deze toets belt TheAudioDB echt op. Hij
// heette `bio_test.dart` en stond daardoor wél in `build-release.yml`, waar hij de APK-bouw aan een
// gratis externe dienst hing. Op 14-09-2026 ging dat mis bij win-v3.9.391: 3162 toetsen door, deze
// ene om, en dus geen APK — terwijl hij bij 385 tot en met 390 gewoon slaagde. Wisselvallig, niet
// kapot.
//
// Dat is precies dezelfde vorm als de storing die van 12-09 tot 13-09 elf uitleveringen lang de APK
// tegenhield: één rode toets in die lijst slaat álles daarna over, publiceren incluis. Een toets die
// van iemand anders zijn server afhangt hoort daar niet in.
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
