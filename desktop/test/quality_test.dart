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

  test('a file on your own shelf shows depth and rate, not bytes per second', () {
    // What the FLAC header actually says beats what the file size implies. The badge read
    // “FLAC · 3079k” for a 24/192 record — the same fact divided by the running time.
    final hr = qualityFromFile(
        name: 'x.flac',
        ext: 'flac',
        isFlac: true,
        durationSec: 60,
        size: 30 * 1000 * 1000,
        sampleRate: 192000,
        bitsPerSample: 24);
    expect(hr.label, 'FLAC 24/192');
    expect(hr.tier, QTier.hires);

    // A CD rip says so in full, and 44100 prints as 44.1 rather than 44.
    final cd = qualityFromFile(
        name: 'x.flac',
        ext: 'flac',
        isFlac: true,
        durationSec: 60,
        size: 10 * 1000 * 1000,
        sampleRate: 44100,
        bitsPerSample: 16);
    expect(cd.label, 'FLAC 16/44.1');
    expect(cd.tier, QTier.lossless);

    // 24/48 is hi-res on depth alone; 16/96 is hi-res on rate alone. Neither is a threshold on
    // bitrate, which is what the old heuristic had to guess with.
    expect(
        qualityFromFile(
                name: 'x.flac', ext: 'flac', isFlac: true, sampleRate: 48000, bitsPerSample: 24)
            .tier,
        QTier.hires);
    expect(
        qualityFromFile(
                name: 'x.flac', ext: 'flac', isFlac: true, sampleRate: 96000, bitsPerSample: 16)
            .tier,
        QTier.hires);

    // Only the rate known — everything except the FLAC reader reports it that way.
    final rateOnly =
        qualityFromFile(name: 'x.alac', ext: 'alac', isFlac: false, sampleRate: 88200);
    expect(rateOnly.label, 'ALAC 88.2 kHz');
    expect(rateOnly.tier, QTier.hires);

    // Neither known: back to the effective bitrate, exactly as before.
    expect(
        qualityFromFile(
                name: 'x.flac', ext: 'flac', isFlac: true, durationSec: 60, size: 10 * 1000 * 1000)
            .label,
        'FLAC · 1333k');
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
