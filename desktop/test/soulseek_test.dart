// Verifies Soulseek login + search against the real network, using the on-device
// credentials. Also checks the "michael" vs "*ichael" query quirk.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/settings.dart';

void main() {
  test('soulseek search + *quirk', () async {
    final s = AppSettings();
    await s.load();
    // ignore: avoid_print
    print('soulseek creds set: ${s.soulseekUser.isNotEmpty && s.soulseekPass.isNotEmpty} (user=${s.soulseekUser})');
    final client = SoulseekClient();
    // Try the password as stored and with any trailing '.' stripped.
    final passwords = {s.soulseekPass, s.soulseekPass.replaceAll(RegExp(r'\.$'), '')}.toList();
    String? goodPass;
    for (final pw in passwords) {
      try {
        await client.search(s.soulseekUser, pw, 'test');
        goodPass = pw;
        // ignore: avoid_print
        print('LOGIN OK with password length ${pw.length}');
        break;
      } catch (e) {
        // ignore: avoid_print
        print('login with length ${pw.length}: $e');
      }
    }
    final usePass = goodPass ?? s.soulseekPass;
    for (final q in ['michael jackson thriller', '*ichael jackson thriller']) {
      try {
        final r = await client.search(s.soulseekUser, usePass, q);
        // ignore: avoid_print
        print("'$q' -> ${r.length} results");
        for (final f in r.take(3)) {
          // ignore: avoid_print
          print('   ${f.freeSlots ? "vrij" : "wachtrij"} · ${f.username} · ${f.displayName} · ${f.isFlac ? "FLAC" : "${f.bitrate}kbps"}');
        }
      } catch (e) {
        // ignore: avoid_print
        print("'$q' error: $e");
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
