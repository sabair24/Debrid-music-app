// De spiegeltest in de volle meting, op echte bestanden (alleen op de pc). 25-11-2026: Missy Elliott "Get Ur Freak On"
// (studio, 24/48) gaf in de scratchpad-meting 0,96, een echte 24/48 (Céline Dion "Bonjour, Pardon, Merci") 0,006.
//
//   SPIEGEL_NEP="a.flac;b.flac" SPIEGEL_ECHT="c.flac" flutter test --run-skipped --tags live test/spiegel_live_test.dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_meter.dart';
import 'package:debridmusic/spiegel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('de spiegeltest op echte 24/48-bestanden', () async {
    final nep = (Platform.environment['SPIEGEL_NEP'] ?? '').split(';').where((s) => s.isNotEmpty).toList();
    final echt = (Platform.environment['SPIEGEL_ECHT'] ?? '').split(';').where((s) => s.isNotEmpty).toList();
    if (nep.isEmpty && echt.isEmpty) {
      markTestSkipped('SPIEGEL_NEP en SPIEGEL_ECHT niet gezet');
      return;
    }
    const exe = r'C:\ffmpeg\bin\ffmpeg.exe';
    Future<Echtheidsoordeel> meet(String pad) async =>
        (await meetHeelBestand(exe: exe, pad: pad, kopSampleRate: 48000, kopBits: 24, duurSeconden: 200))!;
    for (final p in nep) {
      final o = await meet(p);
      // ignore: avoid_print
      print('NEP  ${o.spiegel?.toStringAsFixed(4)}  ${o.boven.name}  $p');
      expect(o.spiegel, greaterThanOrEqualTo(kSpiegelOpgeschaald), reason: p);
      expect(o.isNep, isTrue, reason: p);
    }
    for (final p in echt) {
      final o = await meet(p);
      // ignore: avoid_print
      print('ECHT ${o.spiegel?.toStringAsFixed(4)}  ${o.boven.name}  $p');
      expect(o.spiegel, lessThan(kSpiegelOpgeschaald), reason: p);
      expect(o.boven, isNot(Bovenband.leeg), reason: p);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
