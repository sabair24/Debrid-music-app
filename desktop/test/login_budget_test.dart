import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

/// Soulseek allows one login per account and blocks it after a burst. This account has been
/// blocked twice by this app, so these are the guards that must never quietly regress.
void main() {
  backoff();
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
    c.noteLoginRefused('');
    expect(c.mustNotLogin, isTrue);
    expect(c.blocked, isTrue);
    expect(c.blockedFor, isNotNull);
  });

  test('being kicked right after logging in makes us stand down instead of racing back', () {
    final c = SoulseekClient();
    c.noteLoginAttempt();
    c.noteLoggedIn();
    expect(c.mustNotLogin, isFalse);
    c.noteConnectionLost(); // dropped seconds after login â†’ another client took the account
    expect(c.mustNotLogin, isTrue);
  });

  test('a connection lost long after login is not treated as a kick', () {
    final c = SoulseekClient();
    c.noteConnectionLost(); // never logged in â€” nothing to stand down from
    expect(c.blocked, isFalse);
  });

  test('a successful login clears an earlier refusal', () {
    final c = SoulseekClient();
    c.noteLoginRefused('');
    expect(c.blocked, isTrue);
    c.noteLoggedIn();
    expect(c.blocked, isFalse);
  });
}

/// The back-off is OUR guard, not Soulseek's, so it has to be proportionate â€” and escapable when
/// the user can see the account is fine (the official client logged in right beside it).
void backoff() {
  test('one refusal costs minutes, not half an hour', () {
    final c = SoulseekClient();
    c.noteLoginRefused('');
    expect(c.blocked, isTrue);
    expect(c.blockedFor!.inMinutes, lessThan(3));
  });

  test('but a refusal that keeps repeating costs more each time', () {
    final c = SoulseekClient();
    c.noteLoginRefused('');
    final first = c.blockedFor!;
    c.noteLoginRefused('');
    final second = c.blockedFor!;
    c.noteLoginRefused('');
    expect(second, greaterThan(first));
    expect(c.blockedFor!, greaterThan(second));
  });

  test('a successful login forgets the escalation', () {
    final c = SoulseekClient();
    c.noteLoginRefused('');
    c.noteLoginRefused('');
    c.noteLoginRefused('');
    c.noteLoggedIn();
    c.noteLoginRefused('');
    expect(c.blockedFor!.inMinutes, lessThan(3)); // back to the first step
  });

  test('the user can clear the wait, budget included', () {
    final c = SoulseekClient();
    for (var i = 0; i < 6; i++) {
      c.noteLoginAttempt();
    }
    c.noteLoginRefused('');
    expect(c.mustNotLogin, isTrue);
    c.allowOneRetry();
    expect(c.mustNotLogin, isFalse);
  });
}
