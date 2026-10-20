// IJking van de volle echtheidsmeting op echte bestanden met een bekende waarheid (20-10-2026).
//
// De ijkset: zes echte bestanden uit Sabers bibliotheek en 110 nep-versies ervan (MP3 128-320/V0/V2,
// AAC, Opus, Vorbis, opgeschaald via soxr en ffmpeg, opgeblazen bits), met een manifest dat zegt wat elk
// bestand IS. Niet in de bouwstraat: de bestanden staan alleen op de pc.
//
//   IJK=<map met manifest.json> flutter test --run-skipped --tags live test/echtheid_vol_live_test.dart
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_meter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IJKING: de volle meting op de ijkset', () async {
    final map = Platform.environment['IJK'];
    if (map == null) {
      markTestSkipped('IJK niet gezet');
      return;
    }
    final manifest = (jsonDecode(File('$map/manifest.json').readAsStringSync()) as List).cast<Map>();
    const exe = r'C:\ffmpeg\bin\ffmpeg.exe';
    final telling = <String, List<int>>{};
    final uitslagen = <String, Map<String, int>>{};
    for (final m in manifest) {
      final pad = m['doel'] as String;
      final info = leesStreaminfo(pad);
      if (info == null) continue;
      final o = await meetHeelBestand(
          exe: exe, pad: pad, kopSampleRate: info.sr, kopBits: info.bps, duurSeconden: info.totaal / info.sr);
      if (o == null) continue;
      final soort = m['soort'] as String, verwacht = m['verwacht'] as String;
      final uitslag = o.isKapot
          ? 'kapot'
          : o.bits == Bitdiepte.opgeblazen
              ? 'opgeblazen'
              : o.boven == Bovenband.leeg
                  ? 'opgeschaald'
                  : o.band == Bandbreedte.afgekapt
                      ? 'lossy'
                      : o.band == Bandbreedte.vermoedelijk
                          ? 'vermoedelijk'
                          : 'consistent';
      final goed = switch (verwacht) {
        'echt' => uitslag == 'consistent' && o.integriteit == Integriteit.klopt,
        'lossy' => uitslag == 'lossy' || uitslag == 'vermoedelijk' || uitslag == 'opgeschaald',
        'opgeschaald' => uitslag == 'opgeschaald',
        'opgeblazen' => uitslag == 'opgeblazen',
        _ => true,
      };
      (telling[soort] ??= [0, 0])
        ..[0] += goed ? 1 : 0
        ..[1] += 1;
      (uitslagen[soort] ??= {})[uitslag] = (uitslagen[soort]![uitslag] ?? 0) + 1;
    }
    for (final e in (telling.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
      // ignore: avoid_print
      print('${e.key.padRight(16)} ${e.value[0]}/${e.value[1]}  ${uitslagen[e.key]}');
    }
    expect(telling['origineel']?[0], telling['origineel']?[1], reason: 'geen vals alarm op de echte bestanden');
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('via de echte weg: isolate, procesnummer en cache', () async {
    final map = Platform.environment['IJK'];
    if (map == null) {
      markTestSkipped('IJK niet gezet');
      return;
    }
    final manifest = (jsonDecode(File('$map/manifest.json').readAsStringSync()) as List).cast<Map>();
    final m = manifest.firstWhere((x) => x['soort'] == 'mp3_192');
    final pad = m['doel'] as String;
    final info = leesStreaminfo(pad)!;
    final cache = Directory.systemTemp.createTempSync('dm_echt_cache_');
    final meter = Echtheidsmeter(ffmpegPad: r'C:\ffmpeg\bin\ffmpeg.exe', cacheMap: cache.path);
    int? pid;
    final o = await meter.van(pad,
        kopSampleRate: info.sr, kopBits: info.bps, duurSeconden: info.totaal / info.sr, opStart: (p) => pid = p);
    expect(pid, isNotNull, reason: 'het procesnummer komt terug, voor laatLos');
    expect(o?.band, Bandbreedte.afgekapt);
    expect(o?.integriteit, Integriteit.klopt);
    // Tweede keer uit de cache, zonder ffmpeg.
    pid = null;
    final weer = await meter.van(pad, kopSampleRate: info.sr, kopBits: info.bps, duurSeconden: info.totaal / info.sr, opStart: (p) => pid = p);
    expect(pid, isNull);
    expect(weer?.band, Bandbreedte.afgekapt);
    cache.deleteSync(recursive: true);
  });
}
