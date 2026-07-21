import 'package:debridmusic/online.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real case: "She Drives Me Wild" offered a hundred free lossless copies, yet the download sat
/// on "wacht op peer". Ranked purely on bitrate the top of the list is the big hi-res rips, and
/// those come from a few collectors who each offer several — so the attempt budget was spent on a
/// handful of peers while dozens of others were never asked.
SoulseekFile f(String peer, int kbps, {bool free = true, int queue = 0}) => SoulseekFile(
      username: peer,
      filename: 'x\\04 - She Drives Me Wild.flac',
      size: (kbps * 221 / 8).round() * 1000,
      bitrate: kbps,
      durationSec: 221,
      freeSlots: free,
      queueLength: queue,
    );

void main() {
  // Peers and bitrates as they actually came back for that track.
  final pool = <SoulseekFile>[
    f('nicotinestain', 6522),
    f('anima-angel', 5131),
    f('anima-angel', 3091),
    f('holden093', 3117),
    f('leejbarker', 3106),
    f('Dizziness6681', 3106),
    f('robotz', 3092),
    f('adammeme', 3091),
    f('jimmy9', 3091),
    f('Juvenile0603', 3091),
    f('poly-blooper', 1031),
    f('poly-blooper', 1091),
    f('poly-blooper', 1080),
    f('poly-blooper', 1037),
    f('borb', 1150),
    f('stefa_menne', 1051),
    f('Aevidynn', 1022),
    f('soulseekboy43', 1010),
    f('ShadowedKindness', 967),
    f('mah_uso310', 963),
    f('major_egg', 960),
    f('johnnybravo19', 962),
  ];

  test('every attempt is a different peer', () {
    final order = DownloadManager.sweepOrderFor(pool);
    final firstTwenty = order.take(20).map((e) => e.username).toList();
    expect(firstTwenty.toSet().length, firstTwenty.length,
        reason: 'a budget of N attempts must buy N real chances');
  });

  test('a peer offering several copies is tried once, with its best', () {
    final order = DownloadManager.sweepOrderFor(pool);
    final poly = order.where((e) => e.username == 'poly-blooper').toList();
    expect(poly.length, 1);
    expect(poly.first.bitrate, 1091, reason: 'their best copy of the four');
  });

  test('a peer with a free slot is tried before a busy one, whatever the bitrate', () {
    final busyHiRes = f('busy-collector', 6000, free: false);
    final freeCd = f('free-peer', 950);
    final order = DownloadManager.sweepOrderFor([busyHiRes, freeCd]);
    expect(order.first.username, 'free-peer');
  });

  test('between two free peers the better copy still wins', () {
    final order = DownloadManager.sweepOrderFor([f('a', 950), f('b', 3000)]);
    expect(order.first.username, 'b');
  });

  test('the old quality-only order would have wasted the budget', () {
    // Sanity check on the premise: sorted by bitrate alone, the top 14 covers far fewer peers.
    final byQuality = [...pool]..sort((a, b) => (b.bitrate ?? 0) - (a.bitrate ?? 0));
    final peersInTop14 = byQuality.take(14).map((e) => e.username).toSet().length;
    expect(peersInTop14, lessThan(14));
    expect(DownloadManager.sweepOrderFor(pool).take(14).map((e) => e.username).toSet().length, 14);
  });
}
