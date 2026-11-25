// De nultoets over bemonsteringen heen op echte paren (alleen op de pc), 25-11-2026: Modjo-achtige "studio's" (een cd
// door een codec, als 24/48 bewaard) horen lossy te zijn; echte 24/48's en opgeschaalde cd's nooit.
//
//   NUL_PAREN="L|kandidaat|cd;A|kandidaat|cd" flutter test --run-skipped --tags live test/nultoets_rates_live_test.dart
//   (L = lossy verwacht, A = anders verwacht, ? = alleen tonen)
@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/nultoets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Float32List> decodeer(String pad, int tot) async {
  final r = await Process.run(
      r'C:\ffmpeg\bin\ffmpeg.exe',
      [
        '-v', 'error', '-nostdin', '-i', pad, '-t', '$tot', '-map', '0:a:0', //
        '-af', 'aresample=$kNulRate:resampler=soxr:precision=28:cutoff=0.99',
        '-ac', '1', '-ar', '$kNulRate', '-f', 'f32le', '-',
      ],
      stdoutEncoding: null);
  final bytes = Uint8List.fromList(r.stdout as List<int>);
  return bytes.buffer.asFloat32List(0, bytes.length ~/ 4);
}

void main() {
  test('de codectoets over bemonsteringen heen op echte paren', () async {
    // Veel paren: uit een bestand (NUL_PAREN_BESTAND) — een omgevingsvariabele houdt op bij 32 KB.
    final bestand = Platform.environment['NUL_PAREN_BESTAND'];
    final tekst = bestand != null ? File(bestand).readAsStringSync() : (Platform.environment['NUL_PAREN'] ?? '');
    final paren = tekst.split(';').where((s) => s.contains('|')).toList();
    if (paren.isEmpty) {
      markTestSkipped('NUL_PAREN niet gezet');
      return;
    }
    final fout = <String>[];
    for (final p in paren) {
      final [verwacht, k, c] = p.split('|');
      final plekken = meetplekken(200);
      final tot = plekken.last + kStukSeconden + kZoekSeconden + 2;
      final a = await decodeer(k, tot), b = await decodeer(c, tot);
      final o = nultoetsOverRates(a, b, plekken)!;
      final v = o.punten.map((x) => x.verschuiving).toList()..sort();
      final s = samenhangPerBand(a, b, plekken, v[v.length ~/ 2]);
      final g = o.punten.map((x) => x.versterkingDb).toList()..sort();
      // ignore: avoid_print
      print('${o.uitkomst.name.padRight(6)} (verwacht $verwacht) snr ${s.snrDb.map((x) => x.toStringAsFixed(0)).join('/')} '
          'verh ${s.verhoudingDb.map((x) => x.toStringAsFixed(2)).join('/')} hoog ${s.hoogKandidaat.toStringAsFixed(0)} '
          'tegen ${s.hoogCd.toStringAsFixed(0)} verzet ${g[g.length ~/ 2].toStringAsFixed(2)}  ${k.split(r'\').last}');
      final ok = verwacht == '?' || (verwacht == 'L') == (o.uitkomst == Nuluitkomst.lossy);
      if (!ok) fout.add(k);
      expect(o.uitkomst, isNot(Nuluitkomst.bron));
      expect(o.uitkomst, isNot(Nuluitkomst.bewerkt));
    }
    expect(fout, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 60)));
}
