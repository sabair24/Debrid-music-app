@Tags(['live'])
library;

import 'package:debridmusic/booklet.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hits the real MusicBrainz and Cover Art Archive. No credentials — the price of admission is
/// a User-Agent — but it costs their rate limit, so it stays out of the normal suite:
///
///   flutter test test/booklet_live_test.dart --tags live
///
/// What it proves is the whole reason the archive was added: Discogs holds this record a page
/// at a time, so nothing turns. Matched by barcode, the archive has the booklet photographed
/// open, and every one of those sheets is two facing pages.
void main() {
  test('Bad: the barcode leads to the sheets the booklet is made of', () async {
    final sheets = await coverArtSheets(
      MusicBrainzService(),
      barcode: '5099745029020',
      catno: 'EPC 450290 2',
      artist: 'Michael Jackson',
      album: 'Bad',
    );
    final spreads = sheets.where((s) => s.spread).toList();
    for (final s in sheets) {
      // ignore: avoid_print
      print('  ${s.label.padRight(11)} ${s.width}x${s.height}'
          '  ratio ${s.ratio.toStringAsFixed(2)}${s.spread ? '  <- dubbele pagina' : ''}');
    }
    // ignore: avoid_print
    print('  ${sheets.length} scans, ${spreads.length} dubbele pagina\'s');

    expect(sheets, isNotEmpty, reason: 'the archive has scans for this barcode');
    expect(
      spreads.length,
      greaterThanOrEqualTo(4),
      reason: 'this is the pressing whose booklet was scanned open',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
