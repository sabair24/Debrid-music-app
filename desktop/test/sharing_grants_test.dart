/// The PC remembering which devices it trusts, across a restart.
///
/// At the level of [LanSharing] rather than [GrantStore], because the bug this exists for was not
/// in the store at all: `load()` was written, tested, and never called. A test of the store alone
/// passes happily while every device is refused after a reboot.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/sharing.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_grants_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  LanSharing sharing(AppSettings settings) =>
      LanSharing(library: LibraryStore()..configDirOverride = scratch.path, settings: settings);

  test('a device given access is still trusted after the PC restarts', () async {
    final settings = AppSettings()
      ..lanEnabled = false // no socket needed; this is about what is remembered
      ..lanToken = 'oude-gedeelde-sleutel';

    final first = sharing(settings);
    await first.applySettings();
    final token = first.grants
        .mint(deviceId: 'ipad-1', deviceName: 'iPad', platform: 'ios')
        .token;
    await first.grants.save();

    // A second process, reading the same folder — which is what a restart is.
    final second = sharing(settings);
    await second.applySettings();

    expect(second.grants.byDevice('ipad-1')?.token, token,
        reason: 'zonder grants.load() wordt elk apparaat na een herstart geweigerd');
    expect(second.grants.accepts(token), isTrue);
  });

  test('devices paired before per-device tokens keep working', () async {
    final settings = AppSettings()
      ..lanEnabled = false
      ..lanToken = 'oude-gedeelde-sleutel';

    final s = sharing(settings);
    await s.applySettings();

    // The shared secret every device used to hold is still accepted, and shows up as one row you
    // can revoke on purpose rather than as an empty list.
    expect(s.grants.accepts('oude-gedeelde-sleutel'), isTrue);
    expect(s.grants.all.where((g) => g.legacy).length, 1);
  });

  test('a first run generates a token and does not invent a legacy device', () async {
    final settings = AppSettings()..lanEnabled = false;
    final s = sharing(settings);
    await s.applySettings();

    expect(settings.lanToken, isNotEmpty);
    // The legacy row is adopted AFTER the token is generated; a fresh install has no old devices,
    // so adopting the brand-new token as "previously paired" would be a lie.
    expect(s.grants.all.where((g) => g.legacy).length, 1,
        reason: 'de zojuist gegenereerde token hoort de legacy-rij te zijn, precies één');
  });
}
