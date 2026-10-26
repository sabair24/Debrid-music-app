// Vinyl (24-10-2026: alleen als Saber kiest; sinds 25-10-2026 ook vanzelf, na elke digitale kopie) met een label in de
// zoeklijst.
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
      // Africa, 24-10-2026: vanzelf binnengekomen als 24/96; PBTHAL maakt alleen vinylrips.
      r'@@habkj\PBTHAL rips  [NOT REENCODED]\Toto\Toto - IV (TML)\10 - Africa.flac',
      r'Genesis - Abacab (1981) (PBTHAL LP 24-96) [FLAC] vtwin88cube\01.-Abacab.flac',
      r'Genesis - Duke (Piros) PBTHAL (1980 Progressive Rock) [Flac 24-96 LP]\01.flac',
      r'Joy Division\1988 Substance [LP 24-192]\01.flac',
    ]) {
      expect(isVinylRip(p), isTrue, reason: p);
    }
    for (final p in [
      r'Phil Collins - Face Value (Remastered Hi-Res Version)\01.flac',
      r'Daft Punk\Discovery [24bit 96kHz]\03 - Digital Love.flac',
      r'The Remixes LP\01 - Help.flac',
      r'Lionel Richie\Can’t Slow Down (1983)\08 - Hello.flac',
      r'Music\Prince - 1999\6. Automatic (LP Version).flac',
      r'Toto - IV [24-96]\10 - Africa.flac',
    ]) {
      expect(isVinylRip(p), isFalse, reason: p);
    }
  });

  // 26-10-2026 (versies): na het opbergen staat de bron nergens meer, maar de tags van de ripper blijven.
  test('een vinylrip aan zijn tags: MEDIA=Vinyl, het element in COMMENT', () {
    expect(vinylUitTags({'media': 'Vinyl (LP,Album)'}), isTrue, reason: 'Patricia Kaas');
    expect(vinylUitTags({'comment': 'AT150ANV', 'originator': 'iZotope RX 2'}), isTrue, reason: 'Toto IV van PBTHAL');
    expect(vinylUitTags({'comment': 'Ortofon 2M Blue, Technics SL-1200'}), isTrue);
    expect(vinylUitTags({'comment': 'Exact Audio Copy V1.6', 'encodedby': 'dBpoweramp Release 16.1'}), isFalse);
    expect(vinylUitTags({'comment': 'Ripped at 320 kbps'}), isFalse);
    expect(vinylUitTags({'album': 'Vinyl Days', 'title': 'Vinyl'}), isFalse, reason: 'een naam is geen bron');
    expect(vinylUitTags({'originator': 'iZotope RX 2'}), isFalse, reason: 'RX alleen is ook gewone restauratie');
  });

  // Sinds 25-10-2026 mag vinyl opwaarderen (Saber: "ik mis wel heel veel goede kwaliteit liedjes door vinyl en lp weg
  // te laten oor, laat ze toch maar door"), maar na elke digitale kopie.
  test('vinyl mag opwaarderen, maar een digitale kopie gaat voor', () {
    final van = _f(r'Kaas\Mademoiselle Chante\09 - Mademoiselle Chante Le Blues.flac', rate: 44100, bits: 16);
    final vinyl = _f(r'Kaas\1988 (vinyl rip)\09 Mademoiselle Chante Le Blues.flac', rate: 192000, bits: 24);
    final digitaal = _f(r'Kaas\Mademoiselle Chante [24-96]\09 Mademoiselle Chante Le Blues.flac', rate: 96000, bits: 24);
    expect(DownloadManager.magOpwaarderen(vinyl, van, 228), isTrue);
    expect(DownloadManager.magOpwaarderen(digitaal, van, 228), isTrue);
    expect(DownloadManager.betereKandidaten([vinyl, digitaal], van, 228), [digitaal, vinyl],
        reason: 'de 24/192 vinyl staat hoger, maar de digitale 24/96 wordt eerst geprobeerd');
    final online = _bron('lib/online.dart');
    expect(online, contains('var better = vinylAchteraan(ranked.where((f) => magOpwaarderen(f, from, officieel)).toList(), (f) => f.filename);'),
        reason: 'ook de jacht na een gewone download');
  });

  test('een wens neemt vinyl, na de digitale kopieën; de lengte blijft gelden', () {
    const w = LosslessWant(
        artist: 'Patricia Kaas',
        title: 'Mademoiselle chante le blues',
        authority: TrackTags(title: 'Mademoiselle chante le blues', artist: 'Patricia Kaas', album: '', trackNo: 0, seconds: 228));
    final vinyl = _f(r'Patricia Kaas\1988 - Mademoiselle chante (vinyl rip)\09 Patricia Kaas - Mademoiselle Chante Le Blues.flac',
        rate: 192000, bits: 24);
    final cd = _f(r'Patricia Kaas\Mademoiselle chante\09 - Patricia Kaas - Mademoiselle chante le blues.flac', rate: 44100, bits: 16);
    expect(DownloadManager.kandidatenVoorWens(w, [vinyl, cd]), [cd, vinyl]);
    final teLang = _f(r'Patricia Kaas\Mademoiselle chante (LP rip)\09 Mademoiselle chante le blues.flac',
        rate: 192000, bits: 24, sec: 235);
    expect(DownloadManager.kandidatenVoorWens(w, [teLang]), isEmpty, reason: '235 tegen 228 s: andere lengte, ook bij vinyl');
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
