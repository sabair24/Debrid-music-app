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

  group('surround rips lose to stereo', () {
    // Measured on a real download: Fleetwood Mac "Dreams" came back as a 6-channel 24/96 FLAC of
    // 263 MB — highest bitrate of all candidates, but downmixed on a stereo system and ten times
    // the size of the stereo master that was also on offer.
    test('the release name gives it away', () {
      expect(DownloadManager.isMultichannel(f('Rumours [5.1]\\02 - Dreams.flac')), isTrue);
      expect(DownloadManager.isMultichannel(f('Dark Side (Surround Mix)\\01.flac')), isTrue);
      expect(DownloadManager.isMultichannel(f('Album 7.1 Remix\\01.flac')), isTrue);
    });

    test('a plain stereo release is not flagged', () {
      expect(DownloadManager.isMultichannel(f('Rumours\\02 - Dreams.flac', bitrate: 885)), isFalse);
      // Stereo 24/192 is the highest a normal track reaches — it must stay under the threshold.
      expect(DownloadManager.isMultichannel(f('HiRes\\01.flac', bitrate: 5000)), isFalse);
    });

    test('an unnamed rip is caught by its impossible bitrate', () {
      expect(DownloadManager.isMultichannel(f('Album\\02 - Dreams.flac', bitrate: 8180)), isTrue);
    });

    test('stereo FLAC beats a 5.1 rip, and 5.1 still beats MP3', () {
      final surround = f('Rumours [5.1]\\02 - Dreams.flac', bitrate: 8180);
      final stereoCd = f('Rumours\\02 - Dreams.flac', bitrate: 885);
      final mp3 = f('Rumours\\02 - Dreams.mp3', bitrate: 320);
      expect(DownloadManager.clearlyBetter(stereoCd, surround), isTrue, reason: 'stereo wins');
      expect(DownloadManager.clearlyBetter(surround, stereoCd), isFalse);
      expect(DownloadManager.clearlyBetter(surround, mp3), isTrue, reason: '5.1 is still lossless');
      // And it may still stand in rather than dropping to MP3.
      expect(DownloadManager.isLossless(surround), isTrue);
    });
  });
}
