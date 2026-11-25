// De nultoets over bemonsteringen heen (nultoets.dart, 25-11-2026): een 24/48 tegen je cd zegt alleen lossy (de
// codecvingerafdruk) of anders — nooit bron of bewerkt. Saber, bij Modjo "Lady (Hear Me Tonight)" ("24/48 · studio"):
// "of het 100 procent klopt ?" — het was zijn cd, door een codec gehaald. De getallen hieronder zijn die van de
// livetoets (nultoets_rates_live_test.dart) op zijn bibliotheek.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:debridmusic/nultoets.dart';
import 'package:flutter_test/flutter_test.dart';

Samenhang s(List<double> snr, List<double> verh, double hoogK, double hoogCd) =>
    (snrDb: snr, verhoudingDb: verh, hoogKandidaat: hoogK, hoogCd: hoogCd);

Float32List ruis(int n, int zaad) {
  final r = math.Random(zaad);
  return Float32List.fromList([for (var i = 0; i < n; i++) (r.nextDouble() - 0.5) * 0.4]);
}

void main() {
  group('de codecvingerafdruk', () {
    test('DE KERN: Modjo, Girl, Do It Well en I\'m Real zijn lossy', () {
      expect(isCodecOverRates(s([30, 19, 15, 12], [-0.01, 0.01, 0.04, 0.09], -59, -47), verzetDb: -0.03), isTrue,
          reason: 'Modjo');
      expect(isCodecOverRates(s([27, 23, 19, 17], [-0.01, 0.01, 0.03, 0.05], -59, -45), verzetDb: -0.02), isTrue,
          reason: 'Girl');
      expect(isCodecOverRates(s([22, 22, 18, 15], [0.05, 0.03, 0.06, 0.08], -66, -46), verzetDb: -0.05), isTrue,
          reason: 'Do It Well');
      expect(isCodecOverRates(s([27, 23, 18, 14], [-0.01, -0.01, 0.02, 0.05], -49, -37), verzetDb: -0.04), isTrue,
          reason: "I'm Real");
    });

    test('echte 24/48\'s en opgeschaalde cd\'s zijn het nooit', () {
      // Céline Dion: 0,6 dB verzet, verder tot op −69 dB gelijk.
      expect(isCodecOverRates(s([87, 83, 79, 74], [-0.6, -0.6, -0.6, -0.6], -67, -69), verzetDb: -0.6), isFalse);
      // Confessions: smaller dan de cd, maar de samenhang is goed (38 dB).
      expect(isCodecOverRates(s([55, 48, 38, 31], [0, 0, 0, -0.01], -60, -49), verzetDb: 0), isFalse);
      // Get Ur Freak On (opgeschaald, de spiegeltest vangt hem): zelfde volume, maar 33 dB.
      expect(isCodecOverRates(s([71, 65, 33, 16], [0, 0, 0, -0.05], -45, -44), verzetDb: 0), isFalse);
      // The One: lage samenhang, maar niet smaller dan de cd (2 dB) — wie de smalle is, beslist.
      expect(isCodecOverRates(s([37, 31, 18, 20], [-0.11, -0.11, -0.12, -0.24], -39, -37), verzetDb: -0.13), isFalse);
      // Can't Be Together: 2,1 dB verzet.
      expect(isCodecOverRates(s([36, 34, 25, 26], [2.12, 2.13, 2.11, 2.11], -52, -50), verzetDb: 2.12), isFalse);
      // Torn: 4,6 dB zachter.
      expect(isCodecOverRates(s([42, 66, 79, 75], [4.64, 4.64, 4.64, 4.64], -47, -45), verzetDb: 4.55), isFalse);
    });

    test('elke voorwaarde telt: zonder één ervan geen lossy', () {
      final modjo = s([30, 19, 15, 12], [-0.01, 0.01, 0.04, 0.09], -59, -47);
      expect(isCodecOverRates(modjo, verzetDb: 0.5), isFalse, reason: 'volume verzet');
      expect(isCodecOverRates(s([30, 19, 15, 12], [-0.01, 0.8, 0.04, 0.09], -59, -47), verzetDb: 0), isFalse,
          reason: 'een andere EQ');
      expect(isCodecOverRates(s([30, 19, 25, 12], [-0.01, 0.01, 0.04, 0.09], -59, -47), verzetDb: 0), isFalse,
          reason: 'samenhang te goed');
      expect(isCodecOverRates(s([16, 19, 15, 12], [-0.01, 0.01, 0.04, 0.09], -59, -47), verzetDb: 0), isFalse,
          reason: 'het laag niet beter');
      expect(isCodecOverRates(s([30, 19, 15, 12], [-0.01, 0.01, 0.04, 0.09], -50, -47), verzetDb: 0), isFalse,
          reason: 'de kandidaat is niet de smalle');
      // Een andere zangopname (clean tegenover explicit): slecht in de zangbanden, daarboven weer gelijk — geen codec.
      expect(isCodecOverRates(s([90, 37, 22, 90], [0.1, 0.2, 0.1, 0.0], -60, -50), verzetDb: 0.19), isFalse,
          reason: 'samenhang stijgt terug (Hozier "Too Sweet")');
    });
  });

  group('de samenhang per lijn', () {
    test('dezelfde monsters: volle samenhang, gelijke energie; andere ruis: geen samenhang', () {
      const n = kNulRate * 60;
      final a = ruis(n, 1);
      final plekken = [10, 25, 40];
      final zelf = samenhangPerBand(a, a, plekken, 0);
      expect(zelf.snrDb.every((x) => x > 60), isTrue);
      expect(zelf.verhoudingDb.every((x) => x.abs() < 0.01), isTrue);
      final ander = samenhangPerBand(a, ruis(n, 2), plekken, 0);
      expect(ander.snrDb.every((x) => x < 0), isTrue);
    });

    test('een verschuiving wordt meegenomen: cd[i + v] ≈ kandidaat[i]', () {
      const n = kNulRate * 60, v = 1234;
      final cd = ruis(n, 3);
      final kandidaat = Float32List(n);
      for (var i = 0; i + v < n; i++) {
        kandidaat[i] = cd[i + v];
      }
      expect(samenhangPerBand(kandidaat, cd, [10, 25, 40], v).snrDb.every((x) => x > 60), isTrue);
      expect(samenhangPerBand(kandidaat, cd, [10, 25, 40], 0).snrDb.every((x) => x < 0), isTrue);
    });
  });

  test('de zin: geen voorloop van een encoder, wel een codec', () {
    final o = (
      uitkomst: Nuluitkomst.lossy,
      punten: <Nulpunt>[(verschuiving: 0, versterkingDb: 0, restDb: -20, restDbfs: -40)],
    );
    expect(nulZin(o), contains('door een codec gehaald'));
    final oud = (
      uitkomst: Nuluitkomst.lossy,
      punten: <Nulpunt>[(verschuiving: -1024, versterkingDb: 0, restDb: -20, restDbfs: -40)],
    );
    expect(nulZin(oud), contains('precies 1024 monsters achter je cd'));
  });

  test('aangesloten: de meter weigert een andere bemonstering niet meer, rekent met soxr en vraagt alleen de codectoets', () {
    final m = File('lib/nultoets_meter.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(m, contains('    final overRates = a != null && b != null && a.sr != b.sr;\n'));
    expect(m, isNot(contains('if (a != null && b != null && a.sr != b.sr) return null;')));
    expect(m, contains("if (soxr) ...['-af', 'aresample=\$kNulRate:resampler=soxr:precision=28:cutoff=0.99'],"));
    expect(m, contains('  return overRates ? nultoetsOverRates(a, b, plekken) : nultoetsOp(a, b, plekken);'));
  });
}
