// Na ▶: eerst de snelste FLAC, daarna dezelfde jacht op beter als na een gewone download (Saber,
// 20-10-2026: "eerst de meest directe flac, om daarna een betere versie te zoeken"). De radio niet — die
// alleen bij een 👍.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/online.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  // De app schat de kwaliteit uit de bitrate (grootte / lengte), zoals Soulseek hem toont: een 16/44,1
  // FLAC van 3:51 is ± 30 MB, een 24/96 ± 110 MB.
  SoulseekFile f(String peer, {int bits = 16, int khz = 44100, int sec = 231, String naam = '01 - Lied.flac'}) =>
      SoulseekFile(
          username: peer,
          filename: 'Muziek\\Artiest\\$naam',
          size: bits == 24 && khz >= 88200 ? 110000000 : 30000000,
          freeSlots: true,
          speed: 2000000,
          durationSec: sec,
          sampleRate: khz,
          bitDepth: bits);

  test('beter = duidelijk beter én niet verder van de officiële lengte; nooit hetzelfde bestand', () {
    final gekozen = f('snel');
    final beter = DownloadManager.betereKandidaten([
      gekozen,
      f('hires', bits: 24, khz: 96000),
      f('hires-ander-lengte', bits: 24, khz: 96000, sec: 240),
      f('gelijk'),
    ], gekozen, 231);
    expect(beter.map((k) => k.username), ['hires'],
        reason: 'een 24/96 van 4:00 is geen opwaardering van een 16/44,1 van 3:51 (zie lengteKlopt)');
  });

  test('aangesloten: ▶ zoekt daarna beter, de radio niet; vervangen pas als het niet meer speelt', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('await (bron as EigenRadiobron).haal(plek, vroeg: vroeg, zoekBeter: true, los: true)'));
    // Sinds 24-10-2026 ook wat een toestel van de pc leest (lan/lezers.dart).
    expect(main, contains('downloads.speeltNu = ergensInGebruik;'));
    expect(main, contains('bool ergensInGebruik(String p) =>\n        (player.current?.path == p && !player.losgelaten) ||'));
    final radio = File('lib/radio.dart').readAsStringSync();
    expect(radio, contains('zoekDaarnaBeter: zoekBeter,'));
    expect(radio, contains('await (zelf as EigenRadiobron).haal(p, vroeg: vroeg)'),
        reason: 'de radio zelf: geen jacht zonder 👍');
    final online = File('lib/online.dart').readAsStringSync();
    expect(online, contains('if (zoekBeter) {\n            unawaited(_zoekBeterNaHetLanden(job, f, uit.path, seconden,'));
    expect(online, contains('alle: () async => kandidatenUit(await uitslag() ?? tussenstand)'));
    final jacht = online.substring(online.indexOf('  Future<void> _chaseUpgrade('));
    expect(jacht.indexOf('if (speeltPad != null && !await _wachtTotNietMeerSpeelt(speeltPad)) {'),
        lessThan(jacht.indexOf('final uit = await placeFileDetailed(staged, _downloadsRoot,')),
        reason: 'eerst wachten, dan pas vervangen');
    expect(jacht, contains('if (how == Placement.moved && gezag != null) {'));
    expect(jacht, contains('tags: job.authority, staatAl: mapVanBestaande, parkeerAltijd: parkeerAltijd);'));
    expect(online, contains('_queueUpgrade(beter, job, gezag: gezag, speeltPad: pad, parkeerAltijd: true);'));
  });
}
