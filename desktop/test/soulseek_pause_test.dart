/// Five different situations that all used to reach the screen as "login geweigerd".
///
/// Two of them are not a refusal at all. A kick happens AFTER a login that worked — Soulseek allows
/// one session per account, so the native client taking it back is normal and says nothing about
/// the password. A timeout is the server not answering, which says nothing about the account
/// either: a probe logged in with the app's exact bytes in 251 ms while the app was telling its
/// owner the login had been refused.
///
/// Being told the wrong reason is worse than being told nothing. It sends you to check a password
/// that was never the problem, and it hides the one thing you could have acted on.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_slskpause_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> readGuard() => jsonDecode(
      File('${scratch.path}${Platform.pathSeparator}soulseek_guard.json').readAsStringSync());

  test('a refusal repeats the server, word for word', () {
    final c = SoulseekClient()..noteLoginRefused('Server is temporarily unavailable');
    expect(c.pause, SlskPause.refused);
    expect(c.serverSaid, 'Server is temporarily unavailable');
    expect(c.whyNotLogin, contains('Server is temporarily unavailable'));
  });

  test('a refusal that names the password is not something to wait out', () {
    final c = SoulseekClient()..noteLoginRefused('INVALIDPASS');
    expect(c.pause, SlskPause.badLogin);
    expect(c.whyNotLogin, contains('Instellingen'),
        reason: 'the only thing that fixes it is changing the login');
    expect(c.whyNotLogin, isNot(contains('probeert het straks weer')),
        reason: 'promising to retry a wrong password is a promise that cannot come true');
  });

  test('a wrong password does not escalate the wait', () {
    // 2 → 6 → 15 → 30 minutes made sense for a burst. Applied to a typo it just buries the message
    // deeper each time.
    final c = SoulseekClient();
    for (var i = 0; i < 4; i++) {
      c.noteLoginRefused('INVALIDPASS');
    }
    expect(c.pause, SlskPause.badLogin);
    expect(c.blockedFor!.inMinutes, lessThan(11));
  });

  test('silence is not a refusal', () {
    final c = SoulseekClient()..noteLoginNoAnswer();
    expect(c.pause, SlskPause.noAnswer);
    expect(c.whyNotLogin, contains('zegt niets over je account'));
    expect(c.blockedFor!.inMinutes, lessThan(2), reason: 'a hiccup earns a short wait, not a long one');
  });

  test('silence does not count towards the escalation either', () {
    final c = SoulseekClient();
    for (var i = 0; i < 3; i++) {
      c.noteLoginNoAnswer();
    }
    // The next real refusal must still be treated as the first one.
    c.noteLoginRefused('busy');
    expect(c.blockedFor!.inMinutes, lessThan(3),
        reason: 'three timeouts had pushed this to fifteen minutes');
  });

  test('a kick names the other app, and never the password', () {
    final c = SoulseekClient()
      ..noteLoggedIn()
      ..noteConnectionLost();
    expect(c.pause, SlskPause.kicked);
    expect(c.whyNotLogin, contains('andere Soulseek-app'));
    expect(c.pauseLabel, isNot(contains('weiger')),
        reason: 'the login worked; something took the account afterwards');
  });

  test('a connection that dies long after logging in is nobody being kicked', () {
    // Only a death within a minute of logging in looks like a kick. An ordinary disconnect after an
    // hour is just a disconnect.
    final c = SoulseekClient()..noteConnectionLost();
    expect(c.blocked, isFalse);
    expect(c.pause, SlskPause.none);
  });

  test('the login budget explains itself instead of failing silently', () {
    final c = SoulseekClient();
    for (var i = 0; i < 4; i++) {
      c.noteLoginAttempt();
    }
    expect(c.mustNotLogin, isTrue);
    expect(c.pause, SlskPause.tooMany);
    expect(c.whyNotLogin, contains('officiële Soulseek-app'),
        reason: 'this is the case where closing the other client is the fix');
  });

  test('a successful login clears the reason as well as the wait', () {
    final c = SoulseekClient()..noteLoginRefused('INVALIDPASS');
    expect(c.pause, SlskPause.badLogin);
    c.noteLoggedIn();
    expect(c.blocked, isFalse);
    expect(c.pause, SlskPause.none);
    expect(c.serverSaid, isEmpty);
    expect(c.whyNotLogin, isNull);
  });

  test('closing the app keeps the reason, not just the wait', () async {
    final a = SoulseekClient()..noteLoginRefused('INVALIDPASS');
    await a.guardSaved();
    expect(readGuard()['pause'], 'badLogin');

    // A new process, same folder.
    final b = SoulseekClient();
    await b.loadGuard();
    expect(b.blocked, isTrue);
    expect(b.pause, SlskPause.badLogin, reason: 'it came back knowing only that it had to wait');
    expect(b.serverSaid, 'INVALIDPASS');
  });

  test('a kick survives a restart as a kick', () async {
    final a = SoulseekClient()
      ..noteLoggedIn()
      ..noteConnectionLost();
    await a.guardSaved();
    final b = SoulseekClient();
    await b.loadGuard();
    expect(b.pause, SlskPause.kicked);
    expect(b.whyNotLogin, contains('andere Soulseek-app'));
  });

  test('an expired wait comes back with no reason attached', () async {
    // The wait is what carries the reason; without one there is nothing to explain.
    final a = SoulseekClient()..noteLoginRefused('busy');
    await a.guardSaved();
    final raw = jsonDecode(
        File('${scratch.path}${Platform.pathSeparator}soulseek_guard.json').readAsStringSync())
      as Map<String, dynamic>;
    raw['blockedUntil'] = DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
    File('${scratch.path}${Platform.pathSeparator}soulseek_guard.json')
        .writeAsStringSync(jsonEncode(raw));

    final b = SoulseekClient();
    await b.loadGuard();
    expect(b.blocked, isFalse);
    expect(b.pause, SlskPause.none);
    expect(b.whyNotLogin, isNull);
  });

  test('the strip has something short to say for every case', () {
    for (final p in SlskPause.values) {
      final c = SoulseekClient();
      switch (p) {
        case SlskPause.none:
          continue;
        case SlskPause.refused:
          c.noteLoginRefused('busy');
        case SlskPause.badLogin:
          c.noteLoginRefused('INVALIDPASS');
        case SlskPause.noAnswer:
          c.noteLoginNoAnswer();
        case SlskPause.kicked:
          c
            ..noteLoggedIn()
            ..noteConnectionLost();
        case SlskPause.tooMany:
          for (var i = 0; i < 4; i++) {
            c.noteLoginAttempt();
          }
      }
      expect(c.pause, p);
      expect(c.pauseLabel, isNotEmpty, reason: 'no label for $p');
      expect(c.whyNotLogin, isNotNull, reason: 'no explanation for $p');
    }
  });

  test('the manual retry clears every wait, whatever caused it', () {
    final c = SoulseekClient()..noteLoginRefused('INVALIDPASS');
    for (var i = 0; i < 4; i++) {
      c.noteLoginAttempt();
    }
    expect(c.mustNotLogin, isTrue);
    c.allowOneRetry();
    expect(c.mustNotLogin, isFalse, reason: 'the button has to be able to get past the budget too');
    expect(c.pause, SlskPause.none);
  });
}
