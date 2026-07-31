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

  /// Waarom dit bestaat: het Hi-Res-filter in de bibliotheek meldde "niets binnen dit filter" terwijl
  /// er 102 van die nummers stonden — en in dezelfde lijst gouden badges. Het filter raadde uit de titel
  /// en de duur, en een titel zegt zelden "24bit/96kHz".
  group('hi-res van een bestand dat hier staat', () {
    test('boven 48 kHz is hi-res, ongeacht hoe het nummer heet', () {
      expect(isHiRes(sampleRate: 96000, bitsPerSample: 24), isTrue);
      expect(isHiRes(sampleRate: 88200, bitsPerSample: 24), isTrue);
      expect(isHiRes(sampleRate: 192000, bitsPerSample: 24), isTrue);
      expect(isHiRes(sampleRate: 176400, bitsPerSample: 24), isTrue);
    });

    test('cd-kwaliteit is dat niet, ook niet als het nummer druk gemasterd is', () {
      // De oude weg keek naar de bitrate, en een luid gemasterde 44,1/16 haalt ook boven de 1500 kbit/s.
      expect(isHiRes(sampleRate: 44100, bitsPerSample: 16), isFalse);
      expect(isHiRes(sampleRate: 48000, bitsPerSample: 16), isFalse);
    });

    test('24 bit op 48 kHz telt ook mee', () {
      expect(isHiRes(sampleRate: 48000, bitsPerSample: 24), isTrue);
    });

    test('niets bekend is geen hi-res', () {
      expect(isHiRes(sampleRate: 0, bitsPerSample: 0), isFalse);
    });

    test('het etiket schrijft de rate zoals hij op de hoes staat', () {
      expect(depthRateLabel(sampleRate: 96000, bitsPerSample: 24), '24/96');
      expect(depthRateLabel(sampleRate: 192000, bitsPerSample: 24), '24/192');
      // 88,2 en 176,4 zijn geen 88 en 176: dat zijn de veelvouden van de cd-rate en die decimaal is
      // precies waaraan je ze herkent.
      expect(depthRateLabel(sampleRate: 88200, bitsPerSample: 24), '24/88.2');
      expect(depthRateLabel(sampleRate: 176400, bitsPerSample: 24), '24/176.4');
      expect(depthRateLabel(sampleRate: 44100, bitsPerSample: 24), '24/44.1');
    });

    test('cd-kwaliteit krijgt hetzelfde etiket, want één notatie leest als één lijst', () {
      expect(depthRateLabel(sampleRate: 44100, bitsPerSample: 16), '16/44.1');
      expect(depthRateLabel(sampleRate: 48000, bitsPerSample: 16), '16/48');
    });
  });
}
