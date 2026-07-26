/// The Soulseek login guard, and the fact that it has to survive the app closing.
///
/// Soulseek allows one login per account and rate-limits repeated ones. The app has a guard for
/// that — four logins per ten minutes, plus a growing wait after a refusal — but it lived in memory
/// only, so closing and reopening the app forgot it. That is precisely the case it exists for:
/// four launches, each opening an album (which searches in the background, which logs in), sailed
/// straight past a guard that says four per ten minutes, and Soulseek did the refusing instead.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_slsk_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  File guardFile() =>
      File('${scratch.path}${Platform.pathSeparator}soulseek_guard.json');

  Map<String, dynamic> readGuard() =>
      jsonDecode(guardFile().readAsStringSync()) as Map<String, dynamic>;

  test('a refused login is written down, not only remembered', () async {
    final a = SoulseekClient();
    a.noteLoginRefused();
    expect(a.blocked, isTrue);

    // A new process, same folder.
    await a.guardSaved();
    final b = SoulseekClient();
    expect(b.blocked, isFalse, reason: 'nog niets geladen');
    await b.loadGuard();
    expect(b.blocked, isTrue, reason: 'anders wist een herstart de wachttijd die net was opgelegd');
  });

  test('a kick is written down too', () async {
    // noteConnectionLost sets a five-minute stand-down of its own, and did not save it — so the
    // screen said "wait 6 more minutes" while the file on disk said nothing was wrong.
    final a = SoulseekClient();
    a.noteLoggedIn();
    a.noteConnectionLost();
    expect(a.blocked, isTrue, reason: 'binnen een minuut na inloggen weggevallen is een kick');
    await a.guardSaved();
    expect(guardFile().existsSync(), isTrue, reason: 'en die hoort op schijf te staan');

    final b = SoulseekClient();
    await b.loadGuard();
    expect(b.blocked, isTrue);
  });

  test('the login budget is counted across restarts', () async {
    final a = SoulseekClient();
    for (var i = 0; i < 4; i++) {
      a.noteLoginAttempt();
    }
    expect(a.mustNotLogin, isTrue, reason: 'vier in tien minuten is de rem');
    await a.guardSaved();

    final b = SoulseekClient();
    await b.loadGuard();
    expect(b.mustNotLogin, isTrue,
        reason: 'vier keer opstarten hoort niet dwars door een rem van vier te kunnen');
  });

  test('a wait that has already run out is not carried forward', () async {
    guardFile().writeAsStringSync(jsonEncode({
      'blockedUntil': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      'refusals': 1,
      'logins': <String>[],
    }));
    final c = SoulseekClient();
    await c.loadGuard();
    expect(c.blocked, isFalse);
  });

  test('a clock that jumped cannot lock the account out for a day', () async {
    guardFile().writeAsStringSync(jsonEncode({
      'blockedUntil': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      'refusals': 3,
      'logins': <String>[],
    }));
    final c = SoulseekClient();
    await c.loadGuard();
    expect(c.blocked, isFalse, reason: 'meer dan een uur vooruit is geen geldige wachttijd');
  });

  test('logins older than the window do not count', () async {
    final old = DateTime.now().subtract(const Duration(minutes: 30));
    guardFile().writeAsStringSync(jsonEncode({
      'blockedUntil': null,
      'refusals': 0,
      'logins': [for (var i = 0; i < 4; i++) old.toIso8601String()],
    }));
    final c = SoulseekClient();
    await c.loadGuard();
    expect(c.mustNotLogin, isFalse, reason: 'een half uur oud is geen recente login');
  });

  test('after a quiet hour the escalation starts over', () async {
    // Without this the counter only ever went up: it used to reset because closing the app cleared
    // it, and once it survived a restart nothing but a successful login could. One bad afternoon
    // would leave you on half-hour waits for good.
    guardFile().writeAsStringSync(jsonEncode({
      'blockedUntil': null,
      'refusals': 3,
      'lastRefusalAt': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
      'logins': <String>[],
    }));
    final c = SoulseekClient();
    await c.loadGuard();
    c.noteLoginRefused();
    // Back to the first step of the back-off, which is two minutes — not the thirty it was on.
    expect(c.blockedFor!.inMinutes, lessThan(5));
  });

  test('a refusal that keeps coming does escalate', () async {
    final c = SoulseekClient();
    c.noteLoginRefused();
    final first = c.blockedFor!;
    c.noteLoginRefused();
    final second = c.blockedFor!;
    expect(second, greaterThan(first), reason: 'blijft het misgaan, dan langer wachten');
    await c.guardSaved();
    expect(readGuard()['refusals'], 2);
  });

  test('a successful login clears everything, on disk as well', () async {
    final c = SoulseekClient();
    c.noteLoginRefused();
    expect(c.blocked, isTrue);
    c.noteLoggedIn();
    expect(c.blocked, isFalse);
    await c.guardSaved();
    expect(readGuard()['refusals'], 0);
    expect(readGuard()['blockedUntil'], isNull);
  });

  test('"toch proberen" lets exactly one attempt through', () async {
    final c = SoulseekClient();
    for (var i = 0; i < 4; i++) {
      c.noteLoginAttempt();
    }
    c.noteLoginRefused();
    expect(c.mustNotLogin, isTrue);

    c.allowOneRetry();
    expect(c.mustNotLogin, isFalse, reason: 'de gebruiker weet dat het account vrij is');
    await c.guardSaved();
    // And that is on disk too, or closing the app would bring the wait back.
    final b = SoulseekClient();
    await b.loadGuard();
    expect(b.mustNotLogin, isFalse);
  });
}
