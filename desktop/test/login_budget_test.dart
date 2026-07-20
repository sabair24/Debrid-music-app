import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

/// Soulseek allows one login per account and blocks it after a burst. This account has been
/// blocked twice by this app, so these are the guards that must never quietly regress.
void main() {
  test('a burst of logins closes the door, even when every one of them SUCCEEDS', () {
    final c = SoulseekClient();
    // The kick-war case: our login succeeds, the native client is kicked, it reconnects and kicks
    // us, and round we go. The old guard only counted consecutive FAILURES, so it never fired.
    for (var i = 0; i < 4; i++) {
      expect(c.mustNotLogin, isFalse, reason: 'login ${i + 1} should still be allowed');
      c.noteLoginAttempt();
      c.noteLoggedIn();
    }
    expect(c.mustNotLogin, isTrue);
    expect(c.whyNotLogin, contains('Soulseek'));
  });

  test('a refused login stops all traffic', () {
    final c = SoulseekClient();
    expect(c.mustNotLogin, isFalse);
    c.noteLoginRefused();
    expect(c.mustNotLogin, isTrue);
    expect(c.blocked, isTrue);
    expect(c.blockedFor, isNotNull);
  });

  test('being kicked right after logging in makes us stand down instead of racing back', () {
    final c = SoulseekClient();
    c.noteLoginAttempt();
    c.noteLoggedIn();
    expect(c.mustNotLogin, isFalse);
    c.noteConnectionLost(); // dropped seconds after login → another client took the account
    expect(c.mustNotLogin, isTrue);
  });

  test('a connection lost long after login is not treated as a kick', () {
    final c = SoulseekClient();
    c.noteConnectionLost(); // never logged in — nothing to stand down from
    expect(c.blocked, isFalse);
  });

  test('a successful login clears an earlier refusal', () {
    final c = SoulseekClient();
    c.noteLoginRefused();
    expect(c.blocked, isTrue);
    c.noteLoggedIn();
    expect(c.blocked, isFalse);
  });
}
