import 'dart:convert';

import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

/// A download interrupted by the app closing — or the PC shutting down mid-transfer, which is how
/// this came up — is written down so it can be picked up again. That note has to carry enough to
/// rebuild the candidates, INCLUDING the quality fields: those are what decide which peer the race
/// prefers, so a note that loses them would resume the download at the wrong quality.
void main() {
  test('a candidate survives a round trip through the pending-downloads note', () {
    final f = SoulseekFile(
      username: 'craycraycray',
      filename: r'@shared\Daft Punk\Discovery\02 - Aerodynamic.flac',
      size: 26214400,
      speed: 512000,
      queueLength: 3,
      freeSlots: true,
      bitrate: 2952,
      durationSec: 207,
      isVbr: false,
    );

    final back = SoulseekFile.fromJson(jsonDecode(jsonEncode(f.toJson())) as Map<String, dynamic>)!;

    expect(back.username, f.username);
    expect(back.filename, f.filename);
    expect(back.size, f.size);
    expect(back.speed, f.speed);
    expect(back.queueLength, f.queueLength);
    expect(back.freeSlots, f.freeSlots);
    expect(back.bitrate, f.bitrate, reason: 'quality decides which candidate wins the race');
    expect(back.durationSec, f.durationSec, reason: 'duration is half the same-track identity');
    expect(back.isVbr, f.isVbr);
    // Derived getters must still work, or the resumed job can't be ranked or filed.
    expect(back.displayName, '02 - Aerodynamic.flac');
    expect(back.isFlac, isTrue);
  });

  test('a candidate with nothing but a name and a path still comes back', () {
    // Peers vary in what they report; a note missing the optional fields must not throw away the
    // whole download.
    final back = SoulseekFile.fromJson({'username': 'someone', 'filename': r'x\y.mp3'})!;
    expect(back.size, 0);
    expect(back.bitrate, isNull);
    expect(back.isAudio, isTrue);
  });

  test('a note too broken to rebuild is skipped, not guessed at', () {
    expect(SoulseekFile.fromJson({'filename': r'x\y.flac'}), isNull); // no peer to ask
    expect(SoulseekFile.fromJson({'username': 'someone'}), isNull); // no file to ask for
  });
}
