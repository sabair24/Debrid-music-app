// The rate limiter's actual promise: it spaces the STARTS.
//
// It used to hold each whole request inside the queue, so every caller waited out the previous
// round trip as well as the gap. On the Cover Art Archive lane — spaced for 250 ms, while a lookup
// really takes one to two seconds — eight pressings cost fifteen seconds instead of two, and the
// pressing gallery sat on a spinner for all of it. Parallelising the callers, which is what was
// shipped first, could not help: the queue was downstream of them.
//
// These tests hold the lane to both halves of the deal — polite enough, and not slower than that.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/musicbrainz.dart';

void main() {
  setUp(MusicBrainzService.resetLanes);

  test('starts are spaced by at least the gap', () async {
    const gap = Duration(milliseconds: 40);
    final starts = <int>[];
    final t0 = DateTime.now();
    await Future.wait([
      for (var i = 0; i < 5; i++)
        MusicBrainzService.laneSlot('test-space', gap)
            .then((_) => starts.add(DateTime.now().difference(t0).inMilliseconds)),
    ]);

    expect(starts, hasLength(5));
    starts.sort();
    for (var i = 1; i < starts.length; i++) {
      // A few ms of scheduler slack; the point is that the gap is honoured, not the exact tick.
      expect(starts[i] - starts[i - 1], greaterThanOrEqualTo(gap.inMilliseconds - 5),
          reason: 'slot $i started ${starts[i] - starts[i - 1]}ms after slot ${i - 1}');
    }
  });

  test('a slow request does not hold up the next slot', () async {
    // This is the regression. Each caller takes a slot and then "works" for far longer than the gap.
    // Serialised, five callers cost 5 x (gap + work) = 1.2 s; paced, they cost 4 x gap + work.
    const gap = Duration(milliseconds: 40);
    const work = Duration(milliseconds: 200);
    final sw = Stopwatch()..start();
    await Future.wait([
      for (var i = 0; i < 5; i++)
        MusicBrainzService.laneSlot('test-overlap', gap)
            .then((_) => Future<void>.delayed(work)),
    ]);
    sw.stop();

    // 4 x 40 + 200 = 360 ms if the round trips overlap; 1200 ms if the lane holds them.
    expect(sw.elapsedMilliseconds, lessThan(700),
        reason: 'the lane is holding whole round trips again, not just handing out start slots');
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(work.inMilliseconds),
        reason: 'the work itself still has to happen');
  });

  test('lanes are independent', () async {
    // The webservice and the Cover Art Archive are different hosts with different budgets; a slow
    // turn on one must not delay the other.
    const gap = Duration(milliseconds: 60);
    final sw = Stopwatch()..start();
    await Future.wait([
      MusicBrainzService.laneSlot('lane-a', gap),
      MusicBrainzService.laneSlot('lane-b', gap),
      MusicBrainzService.laneSlot('lane-c', gap),
    ]);
    sw.stop();
    // First call on each lane has no predecessor to wait for, so all three start at once.
    expect(sw.elapsedMilliseconds, lessThan(gap.inMilliseconds));
  });

  test('a thrown turn does not deadlock the lane', () async {
    const gap = Duration(milliseconds: 20);
    // A caller that blows up AFTER taking its slot — the chain still has to move on, or every later
    // request on that lane waits forever on a future that will never complete.
    await MusicBrainzService.laneSlot('test-throw', gap)
        .then<void>((_) => throw StateError('boom'))
        .catchError((_) {});
    await MusicBrainzService.laneSlot('test-throw', gap).timeout(const Duration(seconds: 2));
    expect(true, isTrue, reason: 'the second slot was granted');
  });

  test('resetLanes forgets the timing', () async {
    const gap = Duration(milliseconds: 300);
    await MusicBrainzService.laneSlot('test-reset', gap);
    MusicBrainzService.resetLanes();
    final sw = Stopwatch()..start();
    await MusicBrainzService.laneSlot('test-reset', gap);
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(gap.inMilliseconds),
        reason: 'after a reset there is no last call to be spaced from');
  });
}
