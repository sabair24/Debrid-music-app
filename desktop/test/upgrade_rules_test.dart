import 'package:debridmusic/online.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two rules that decide (a) whether a copy is good enough to serve as a fast stand-in and
/// (b) whether another copy is worth a background hunt. Both delete or replace files, so a wrong
/// "yes" costs the user something real.
SoulseekFile f(String name, {int? bitrate, int seconds = 240, int? sizeMb}) => SoulseekFile(
      username: 'peer',
      filename: 'dir\\$name',
      size: (sizeMb ?? 30) * 1000 * 1000,
      bitrate: bitrate,
      durationSec: seconds,
    );

void main() {
  group('isLossless — an MP3 is never a fast stand-in', () {
    test('FLAC counts', () {
      expect(DownloadManager.isLossless(f('a.flac', bitrate: 900)), isTrue);
      expect(DownloadManager.isLossless(f('a.flac', bitrate: 4000)), isTrue);
    });

    test('lossy does not', () {
      expect(DownloadManager.isLossless(f('a.mp3', bitrate: 320)), isFalse);
      expect(DownloadManager.isLossless(f('a.m4a', bitrate: 256)), isFalse);
    });
  });

  group('clearlyBetter — only a real step up starts a chase', () {
    test('hi-res beats CD-quality FLAC', () {
      final hires = f('a.flac', bitrate: 4000);
      final cd = f('b.flac', bitrate: 900);
      expect(DownloadManager.clearlyBetter(hires, cd), isTrue);
      expect(DownloadManager.clearlyBetter(cd, hires), isFalse);
    });

    test('FLAC beats MP3 — the case worth chasing after settling for lossy', () {
      expect(DownloadManager.clearlyBetter(f('a.flac', bitrate: 900), f('b.mp3', bitrate: 320)), isTrue);
    });

    test('two rips of the same CD do NOT trigger a chase', () {
      // Rip-to-rip byte-rate noise is normal; chasing it would swap a good FLAC for an equal one
      // and burn ten minutes per track.
      expect(DownloadManager.clearlyBetter(f('a.flac', bitrate: 912), f('b.flac', bitrate: 900)), isFalse);
      expect(DownloadManager.clearlyBetter(f('a.flac', bitrate: 1050), f('b.flac', bitrate: 900)), isFalse);
    });

    test('a clearly higher bitrate within the same tier does', () {
      expect(DownloadManager.clearlyBetter(f('a.flac', bitrate: 1400), f('b.flac', bitrate: 900)), isTrue);
    });

    test('an equal copy is never worth chasing', () {
      expect(DownloadManager.clearlyBetter(f('a.flac', bitrate: 900), f('b.flac', bitrate: 900)), isFalse);
    });
  });
}
