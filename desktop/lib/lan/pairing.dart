import 'dart:math';

/// A short-lived code that trades itself for the real access token.
///
/// The token is 32 hex characters. Typing that on a TV remote, one letter at a time on an
/// on-screen keyboard, is not something to ask of anyone — so pairing goes the other way round:
/// the PC shows six digits, the device types those, and gets the token back over the wire.
///
/// Deliberately narrow: one code at a time, five minutes, five attempts. On a home network that
/// is plenty, and it means a code left on screen can't be brute-forced by anything that wanders
/// onto the network later.
class PairingStore {
  PairingStore({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  String? _code;
  DateTime? _expiresAt;
  int _attemptsLeft = 0;

  static const codeLifetime = Duration(minutes: 5);
  static const _maxAttempts = 5;

  /// The code currently on screen, or null when pairing isn't open.
  String? get code => _valid ? _code : null;

  DateTime? get expiresAt => _valid ? _expiresAt : null;

  bool get _valid =>
      _code != null &&
      _attemptsLeft > 0 &&
      _expiresAt != null &&
      DateTime.now().isBefore(_expiresAt!);

  /// Open pairing and return the six digits to show the user.
  String start({DateTime? now}) {
    final at = now ?? DateTime.now();
    _code = List.generate(6, (_) => _random.nextInt(10)).join();
    _expiresAt = at.add(codeLifetime);
    _attemptsLeft = _maxAttempts;
    return _code!;
  }

  /// Close pairing — after a successful pair, or when the user leaves the screen.
  void stop() {
    _code = null;
    _expiresAt = null;
    _attemptsLeft = 0;
  }

  /// Does [attempt] match the code on screen?
  ///
  /// A wrong guess costs an attempt whether or not pairing is even open, so a caller cannot
  /// tell "no code right now" apart from "wrong code" by how the two respond.
  bool redeem(String attempt, {DateTime? now}) {
    final at = now ?? DateTime.now();
    if (_code == null || _expiresAt == null || at.isAfter(_expiresAt!) || _attemptsLeft <= 0) {
      return false;
    }
    _attemptsLeft--;
    if (attempt.trim() != _code) return false;
    stop(); // one code, one device
    return true;
  }
}
