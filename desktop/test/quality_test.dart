import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/quality.dart';

void main() {
  test('torrent name → quality/tier', () {
    expect(qualityFromName('Michael Jackson - Thriller [FLAC]').tier, QTier.lossless);
    final hires = qualityFromName('MJ - Thriller (24bit-96kHz) FLAC');
    expect(hires.tier, QTier.hires);
    print('hires label = ${hires.label}');
    expect(qualityFromName('MJ - Thriller [SACD-R] DSD').tier, QTier.hires);
    final mp3 = qualityFromName('MJ - Thriller Mp3 320kbps');
    expect(mp3.tier, QTier.lossy);
    print('mp3 label = ${mp3.label}');
    expect(qualityFromName('MJ - Thriller (Remastered) 1982').tier, QTier.unknown);
    print('24/192 label = ${qualityFromName('Thriller 24-192 FLAC').label}');
  });

  test('Soulseek file → quality (effective bitrate)', () {
    // 16-bit FLAC: ~10MB, 60s → ~1333 kbps → lossless
    final cd = qualityFromFile(name: 'x.flac', ext: 'flac', isFlac: true, durationSec: 60, size: 10 * 1000 * 1000);
    print('cd flac = ${cd.label} ${cd.tier}');
    expect(cd.lossless, true);
    // 24-bit FLAC: ~30MB, 60s → ~4000 kbps → hires
    final hr = qualityFromFile(name: 'x.flac', ext: 'flac', isFlac: true, durationSec: 60, size: 30 * 1000 * 1000);
    expect(hr.tier, QTier.hires);
    print('hires flac = ${hr.label}');
    final mp3 = qualityFromFile(name: 'x.mp3', ext: 'mp3', isFlac: false, bitrate: 320);
    expect(mp3.tier, QTier.lossy);
    print('mp3 = ${mp3.label}');
  });

  test('filters match the right tiers', () {
    final flac = qualityFromName('album FLAC');
    final mp3 = qualityFromName('album MP3 320');
    final hires = qualityFromName('album FLAC 24/96');
    expect(QFilter.lossless.matches(flac), true);
    expect(QFilter.lossless.matches(mp3), false);
    expect(QFilter.hires.matches(flac), false);
    expect(QFilter.hires.matches(hires), true);
    expect(QFilter.mp3.matches(mp3), true);
    expect(QFilter.all.matches(mp3), true);
  });
}
