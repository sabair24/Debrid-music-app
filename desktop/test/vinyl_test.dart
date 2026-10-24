// Vinyl alleen als Saber kiest (24-10-2026): nooit vanzelf in de plaats van zijn versie, en een label in de zoeklijst.
import 'dart:io';

import 'package:debridmusic/lossless_want.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/vinyl.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een FLAC van [sec] seconden, zo groot als die diepte en bemonstering echt worden (ongeveer 60 % van de ruwe stroom).
SoulseekFile _f(String pad, {int? rate, int? bits, int sec = 228}) => SoulseekFile(
    username: 'u$pad', filename: pad, size: ((rate ?? 44100) * (bits ?? 16) * 2 * sec * .6 / 8).round(), speed: 500, freeSlots: true, sampleRate: rate, bitDepth: bits,
    durationSec: sec);

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('herkend aan het pad, zoals de peers het noemen (uit de proef van 24-10-2026)', () {
    for (final p in [
      r'Patricia Kaas\1988 - Mademoiselle chante (vinyl rip)\09 Patricia Kaas - Mademoiselle Chante Le Blues.flac',
      r'1981 - Phil Collins • Face Value [Japan Vinyl LP 24-96 kHz]\A1 - In the Air Tonight.flac',
      r'Daft Punk - 2001 - Discovery [Virgin, 8496061 V2940, vinyl rip by Guardian]\A3 - Digital Love.flac',
      r'12 Vinyl 01\Daft Punk - Discovery - 03 - Digital Love.flac',
      r'Bonnie Tyler\Secret Dreams (Needle Drop 24-192)\01.flac',
      r'Bonnie Tyler\Secret Dreams [LP-Rip]\01.flac',
      r'X\VinylRip\01.flac',
    ]) {
      expect(isVinylRip(p), isTrue, reason: p);
    }
    for (final p in [
      r'Phil Collins - Face Value (Remastered Hi-Res Version)\01.flac',
      r'Daft Punk\Discovery [24bit 96kHz]\03 - Digital Love.flac',
      r'The Remixes LP\01 - Help.flac',
      r'Lionel Richie\Can’t Slow Down (1983)\08 - Hello.flac',
    ]) {
      expect(isVinylRip(p), isFalse, reason: p);
    }
  });

  test('nooit een opwaardering, ook niet als hij duidelijk beter klinkt', () {
    final van = _f(r'Kaas\Mademoiselle Chante\09 - Mademoiselle Chante Le Blues.flac', rate: 44100, bits: 16);
    final vinyl = _f(r'Kaas\1988 (vinyl rip)\09 Mademoiselle Chante Le Blues.flac', rate: 192000, bits: 24);
    final digitaal = _f(r'Kaas\Mademoiselle Chante [24-96]\09 Mademoiselle Chante Le Blues.flac', rate: 96000, bits: 24);
    expect(DownloadManager.clearlyBetter(vinyl, van), isTrue, reason: 'op de getallen wél beter');
    expect(DownloadManager.magOpwaarderen(vinyl, van, 228), isFalse);
    expect(DownloadManager.magOpwaarderen(digitaal, van, 228), isTrue);
  });

  test('een wens neemt geen vinyl', () {
    const w = LosslessWant(
        artist: 'Patricia Kaas',
        title: 'Mademoiselle chante le blues',
        authority: TrackTags(title: 'Mademoiselle chante le blues', artist: 'Patricia Kaas', album: '', trackNo: 0, seconds: 228));
    final uit = DownloadManager.kandidatenVoorWens(w, [
      _f(r'Patricia Kaas\1988 - Mademoiselle chante (vinyl rip)\09 Patricia Kaas - Mademoiselle Chante Le Blues.flac',
          rate: 192000, bits: 24),
      _f(r'Patricia Kaas\Mademoiselle chante\09 - Patricia Kaas - Mademoiselle chante le blues.flac', rate: 44100, bits: 16),
    ]);
    expect(uit, hasLength(1));
    expect(isVinylRip(uit.single.filename), isFalse);
  });

  test('kiest de app zelf (▶, de radio): vinyl achteraan, en alleen als er niets anders is', () {
    final l = [_f(r'a\(vinyl rip)\1.flac'), _f(r'a\cd\1.flac'), _f(r'a\LP rip\1.flac'), _f(r'a\web\1.flac')];
    expect([for (final f in vinylAchteraan(l, (f) => f.filename)) f.filename],
        [r'a\cd\1.flac', r'a\web\1.flac', r'a\(vinyl rip)\1.flac', r'a\LP rip\1.flac']);
    final online = _bron('lib/online.dart');
    expect(online, contains('if (exact == null && !jouwKeuze) candidates = vinylAchteraan(candidates, (f) => f.filename);'),
        reason: 'wat je zelf aanklikt krijg je, ook vinyl');
    expect(online, contains('final bruikbaar = vinylAchteraan(passend..sort(opLengteDanRang(seconden)), (f) => f.filename);'),
        reason: 'de radio');
  });

  test('in de zoeklijst een label "vinyl"', () {
    final main = _bron('lib/main.dart');
    final i = main.indexOf('if (isVinylRip(f.filename))');
    expect(i, greaterThan(0));
    expect(main.substring(i, i + 900), contains("Text('vinyl'"));
  });
}
