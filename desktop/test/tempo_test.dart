// Het tempo, gemeten uit de audio (Saber, 22-10-2026: "Is er iets anders dat het tempo kan kennen/meten?"). Geijkt
// op 154 getagde nummers (81 % exact); hier een kunstmatige maat, zodat de meter zonder bestanden na te rekenen is.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/aanbevelingplan.dart' show SmaakProfiel;
import 'package:debridmusic/radiolijst.dart';
import 'package:debridmusic/tempo.dart';

/// [seconden] lang een kickdrum (een korte daling in toon) op [bpm], met een hihat ertussen en wat ruis.
Float32List _maat(double bpm, double seconden, {int zaad = 1}) {
  final n = (seconden * kTempoSr).round();
  final x = Float32List(n);
  final r = math.Random(zaad);
  final tel = 60 / bpm * kTempoSr;
  for (var i = 0; i < n; i++) {
    x[i] = (r.nextDouble() - 0.5) * 0.01;
  }
  for (var t = 0.0; t < n; t += tel) {
    for (var j = 0; j < 1500 && t + j < n; j++) {
      final s = math.exp(-j / 300) * math.sin(2 * math.pi * (60 + 90 * math.exp(-j / 200)) * j / kTempoSr);
      x[(t + j).floor()] += 0.8 * s;
    }
    final h = (t + tel / 2).floor();
    for (var j = 0; j < 300 && h + j < n; j++) {
      x[h + j] += (r.nextDouble() - 0.5) * 0.3 * math.exp(-j / 60);
    }
  }
  return x;
}

void main() {
  group('de meter', () {
    for (final bpm in [96.0, 120.0, 128.0, 142.0]) {
      test('een maat op $bpm BPM', () {
        final t = meetTempo(_maat(bpm, 40))!;
        expect((t.bpm / bpm - 1).abs(), lessThan(0.02), reason: 'gemeten ${t.bpm}');
        expect(t.aanslagen, greaterThan(0));
      });
    }

    test('een heel nummer: drie vensters, hetzelfde tempo', () {
      expect((meetTempo(_maat(124, 210))!.bpm / 124 - 1).abs(), lessThan(0.02));
    });

    test('te kort om iets te zeggen: niets', () {
      expect(meetTempo(_maat(120, 5)), isNull);
      expect(meetTempo(Float32List(0)), isNull);
    });

    test('zonder ffmpeg of zonder bestand: geen tempo, en geen uitzondering', () async {
      final map = Directory.systemTemp.createTempSync('dm_tempo_');
      addTearDown(() {
        try {
          map.deleteSync(recursive: true);
        } catch (_) {}
      });
      final m = Tempometer(geheugen: '${map.path}${Platform.pathSeparator}tempo.json');
      expect(await m.van('${map.path}${Platform.pathSeparator}bestaat-niet.flac'), isNull);
    });
  });

  group('het radiotempo', () {
    test('een eigen bestand gaat voor het fragment; zonder fragment niets', () async {
      final gevraagd = <String>[];
      final rt = Radiotempo(
        meter: Tempometer(geheugen: '${Directory.systemTemp.path}${Platform.pathSeparator}dm_tempo_geen.json'),
        fragment: (a, t, s) async {
          gevraagd.add('$a — $t');
          return null;
        },
      );
      final uit = await rt.vanRij([
        (artiest: 'A', titel: 'Een', pad: null, seconden: null),
        (artiest: 'B', titel: 'Twee', pad: null, seconden: 200),
      ]);
      expect(uit, [null, null]);
      if (rt.meter.kan) expect(gevraagd, ['A — Een', 'B — Twee']);
    });
  });

  group('de sfeervraag hoort het tempo', () {
    const k = [
      (artiest: 'Benny Neyman', titel: 'Waarom fluister ik je naam nog'),
      (artiest: 'Gerard Joling', titel: 'Maak me gek'),
    ];

    test('DE KERN: het zaad en elk gemeten nummer met zijn BPM, en de regel "af en toe rustiger mag"', () {
      final v = sfeerPrompt(
        artiest: 'Petra',
        titel: 'Ik Leef Voor Jou',
        kandidaten: k,
        zaadBpm: 142,
        bpm: const [94, 144],
      );
      expect(v, contains(tempoZin(142)));
      expect(v, contains('rond 142 BPM'));
      expect(v, contains('1. Benny Neyman - Waarom fluister ik je naam nog (~94 BPM)'));
      expect(v, contains('2. Gerard Joling - Maak me gek (~144 BPM)'));
      expect(tempoZin(142), contains('af en toe een rustiger nummer'));
      expect(tempoZin(142), contains('het dubbele of de helft'));
    });

    test('zonder meting zoals voorheen; een nummer zonder meting zonder getal', () {
      final zonder = sfeerPrompt(artiest: 'Petra', titel: 'Ik Leef Voor Jou', kandidaten: k);
      expect(zonder, isNot(contains('BPM')));
      final half = sfeerPrompt(artiest: 'Petra', kandidaten: k, zaadBpm: 142, bpm: const [null, 144]);
      expect(half, contains('1. Benny Neyman - Waarom fluister ik je naam nog\n'));
    });

    // Gemeten op 22-10-2026, radio vanaf Petra — Ik Leef Voor Jou: 37 keer Engelstalige eurodance, en de lijst van het
    // model zette er trage ballads tussen. Saber: "Mengeling van beide" (Nederlandstalig up-tempo én 90s-eurodance).
    test('de lijst hoort de taalregel en het tempo; de sfeervraag de taalregel', () {
      final lijst = nummersPrompt(
        artiest: 'Petra',
        titel: 'Ik Leef Voor Jou',
        profiel: const SmaakProfiel(),
        zaadBpm: 142,
      );
      expect(lijst, contains(kTaalZin));
      expect(lijst, contains(tempoLijstZin(142)));
      expect(kTaalZin, contains('de helft'));
      expect(kTaalZin, contains('Plaza - Yo Yo'), reason: 'Sabers eigen voorbeeld');
      expect(nummersPrompt(artiest: 'Petra', profiel: const SmaakProfiel()), isNot(contains('BPM')));
      expect(sfeerPrompt(artiest: 'Petra', kandidaten: const []), contains(kTaalSfeerZin));
    });

    test('aangesloten: de lijsten krijgen het zaadtempo, en ook wat het model koos gaat langs de sfeervraag', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(
        'zaadBpm: await keuring.zaadTempo,'.allMatches(main).length,
        2,
        reason: 'de startlijst en de vervolglijst',
      );
      expect(main.contains('          keuring.vraagSfeer(vanModel);\n'), isTrue);
      expect(main.contains('            keuring.vraagSfeer(vanModel, onderweg: true);\n'), isTrue);
      expect(
        main.contains('          mag: () => !keuring.lijstIsBinnen\n'),
        isTrue,
        reason: 'geen tweede lijst zolang de eerste onderweg is',
      );
    });

    test('aangesloten: de pc meet voor zijn eigen radio en voor een toestel', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main.contains('    ..tempo = lib.isRemote ? null : _radiotempo;'), isTrue);
      expect(main.contains('        tempo: _radiotempo,\n'), isTrue);
      expect(main.contains('          zaadBpm: zaadBpm,\n          bpm: bpm);'), isTrue);
    });
  });
}
