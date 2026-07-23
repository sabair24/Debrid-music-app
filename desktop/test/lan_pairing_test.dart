import 'dart:math';

import 'package:debridmusic/lan/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Predictable digits, so a test can assert on the exact code.
class _FixedRandom implements Random {
  _FixedRandom(this.digits);
  final List<int> digits;
  var _i = 0;

  @override
  int nextInt(int max) => digits[_i++ % digits.length];

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  test('a code is six digits', () {
    final store = PairingStore(random: _FixedRandom([1, 2, 3, 4, 5, 6]));
    expect(store.start(), '123456');
    expect(store.code, '123456');
  });

  test('the right code hands over the token, once', () {
    final store = PairingStore(random: _FixedRandom([1, 2, 3, 4, 5, 6]));
    store.start();
    expect(store.redeem('123456'), isTrue);
    // Spent. A code left on screen after the Shield has paired must not let a second device in.
    expect(store.redeem('123456'), isFalse);
    expect(store.code, isNull);
  });

  test('surrounding whitespace is forgiven', () {
    final store = PairingStore(random: _FixedRandom([1, 2, 3, 4, 5, 6]));
    store.start();
    expect(store.redeem(' 123456 '), isTrue);
  });

  test('guessing runs out after five tries', () {
    final store = PairingStore(random: _FixedRandom([1, 2, 3, 4, 5, 6]));
    store.start();
    for (var i = 0; i < 5; i++) {
      expect(store.redeem('000000'), isFalse);
    }
    // Even the right code is refused now — the window is spent, not just wrong.
    expect(store.redeem('123456'), isFalse);
    expect(store.code, isNull, reason: 'a burnt code must not still read as open');
  });

  test('a code expires', () {
    final store = PairingStore(random: _FixedRandom([1, 2, 3, 4, 5, 6]));
    final now = DateTime(2026, 7, 23, 12);
    store.start(now: now);
    expect(store.redeem('123456', now: now.add(const Duration(minutes: 4, seconds: 59))), isTrue);

    store.start(now: now);
    expect(store.redeem('123456', now: now.add(const Duration(minutes: 5, seconds: 1))), isFalse);
  });

  test('nothing is on offer when pairing was never opened', () {
    final store = PairingStore(random: _FixedRandom([1, 2, 3, 4, 5, 6]));
    expect(store.code, isNull);
    expect(store.redeem('123456'), isFalse);
  });

  test('closing the panel withdraws the code', () {
    final store = PairingStore(random: _FixedRandom([1, 2, 3, 4, 5, 6]));
    store.start();
    store.stop();
    expect(store.code, isNull);
    expect(store.redeem('123456'), isFalse);
  });

  test('codes are not all the same', () {
    // Guards against a fixed or trivially seeded generator, which would make the whole exercise
    // pointless — every PC on earth showing the same six digits.
    final store = PairingStore();
    final seen = {for (var i = 0; i < 40; i++) store.start()};
    expect(seen.length, greaterThan(30));
  });
}
