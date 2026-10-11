/// De titelzeef van "Ontbrekende downloaden", buiten de UI-draad.
///
/// **Waarom.** Op de S26 stond de UI-draad 2078 ms stil na "Ontbrekende downloaden" op *Morning
/// Glory* (warmte.log, 11-10-2026): elf nummers, elk gezeefd over de hele albumbrede zoeklijst, in één
/// blok. En de catalogusalbumpagina zeefde diezelfde lijst opnieuw bij elke opbouw van elke rij.
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/kandidatenzeef.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

const _titels = [
  'Hello', 'Roll With It', 'Wonderwall', "Don't Look Back in Anger", 'Hey Now!', 'Some Might Say',
  'Cast No Shadow', "She's Electric", 'Morning Glory', 'Champagne Supernova',
];

List<SoulseekFile> _albumbreed(int peers) => [
      for (var u = 0; u < peers; u++)
        for (var i = 0; i < _titels.length; i++)
          SoulseekFile(
            username: 'peer$u',
            filename: '@@peer$u\\Music\\Oasis\\(What\'s The Story) Morning Glory (1995)\\'
                '${(i + 1).toString().padLeft(2, '0')} - ${_titels[i]}.${u.isEven ? 'flac' : 'mp3'}',
            size: 30000000,
            speed: 1000000,
            queueLength: 0,
            freeSlots: true,
            durationSec: 240 + i,
          ),
    ];

void main() {
  test('in de isolate komt precies hetzelfde uit als ter plekke', () async {
    final lijst = _albumbreed(60); // 600 bestanden
    for (final t in ['Wonderwall', 'Morning Glory']) {
      final nu = zeefKandidatenNu(lijst, titel: t, seconden: 242, artiest: 'Oasis', album: "(What's The Story) Morning Glory?");
      final apart = await zeefKandidaten(lijst, titel: t, seconden: 242, artiest: 'Oasis', album: "(What's The Story) Morning Glory?");
      expect(apart.map((f) => f.filename), nu.map((f) => f.filename));
      expect(nu, isNotEmpty, reason: 'anders bewijst de vergelijking niets');
    }
  });

  test('DE KERN: een grote lijst houdt de draad niet vast', () async {
    // Een klok die elke 10 ms tikt. Zeeft de draad zelf 4400 bestanden, dan tikt hij al die tijd niet.
    final lijst = _albumbreed(440);
    var tikken = 0;
    final klok = Timer.periodic(const Duration(milliseconds: 10), (_) => tikken++);
    final sw = Stopwatch()..start();
    for (final t in _titels) {
      await zeefKandidaten(lijst, titel: t, seconden: 240, artiest: 'Oasis', album: "(What's The Story) Morning Glory?");
    }
    sw.stop();
    klok.cancel();
    // Minstens de helft van de tikken die in die tijd hadden moeten vallen.
    expect(tikken, greaterThanOrEqualTo(sw.elapsedMilliseconds ~/ 20),
        reason: '${sw.elapsedMilliseconds} ms gezeefd en maar $tikken tikken: de draad zat vast');
  });

  test('ook een korte lijst, en alleen het gevraagde nummer', () async {
    final lijst = _albumbreed(2);
    final uit = await zeefKandidaten(lijst, titel: 'Hello', seconden: 240, artiest: 'Oasis');
    expect(uit.map((f) => f.username).toSet(), {'peer0', 'peer1'});
  });

  test('beide albumpagina\'s gebruiken de zeef, en de catalogus onthoudt hem per titel', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main.contains('Future<List<SoulseekFile>> zeef(List<SoulseekFile> files) => zeefKandidaten(files,'),
        isTrue, reason: '"Ontbrekende downloaden" zeeft buiten de UI-draad');
    expect(main.contains('    return _slskPerTitel.putIfAbsent(\n'), isTrue,
        reason: 'de telling naast elke rij zeeft niet bij elke opbouw opnieuw');
    expect(main.contains('    if (!identical(_slskPerTitelVan, _albumSlsk)) {'), isTrue,
        reason: 'een nieuw zoekresultaat begint het geheugen opnieuw');
  });
}
