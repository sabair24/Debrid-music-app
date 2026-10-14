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

  test('de noodrem "Versleutelde verbinding": uit sluit de versleutelde ingang, aan opent hem weer', () async {
    // Poort 0: de server kiest zelf, en vecht nooit met de draaiende app om 47820 of 47822.
    final settings = AppSettings()
      ..lanEnabled = true
      ..lanPort = 0;
    final s = sharing(settings);
    addTearDown(() async {
      settings.lanEnabled = false;
      await s.applySettings();
    });
    await s.applySettings();
    expect(s.running, isTrue);
    expect(s.tlsBoundPort, isNotNull, reason: 'standaard aan');
    expect(s.pin, isNotEmpty);

    final oud = s.tlsBoundPort!;
    settings.versleuteld = false;
    await s.applySettings();
    expect(s.running, isTrue, reason: '47820 blijft draaien: de toestellen vallen daarop terug');
    expect(s.tlsBoundPort, isNull);
    // En de oude ingang is echt dicht: niet een nieuwe server naast een oude die blijft luisteren.
    Future<bool> open(int poort) async {
      try {
        final sock = await Socket.connect(InternetAddress.loopbackIPv4, poort, timeout: const Duration(seconds: 3));
        sock.destroy();
        return true;
      } catch (_) {
        return false;
      }
    }

    expect(await open(oud), isFalse, reason: 'de noodrem sluit 47822, hij zet er niets naast');
    expect(s.pin, isNotEmpty, reason: 'de pin blijft dezelfde, ook met de rem aan');

    settings.versleuteld = true;
    await s.applySettings();
    expect(s.tlsBoundPort, isNotNull);
  });

  test('de noodrem overleeft een herstart van de app', () {
    final a = AppSettings()..versleuteld = false;
    final b = AppSettings()..applyJson(a.toJson());
    expect(b.versleuteld, isFalse);
    expect((AppSettings()..applyJson(const {})).versleuteld, isTrue, reason: 'standaard aan');
  });
}
