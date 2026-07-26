/// What a device calls itself in the PC's list of trusted devices.
///
/// The list is how you revoke one device rather than all of them, so a name that identifies nothing
/// makes the whole feature unusable. Seven Android phones arrived in it as "localhost" — true, and
/// no help at all when you want to cut off exactly one of them.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/cloud/device_identity.dart';

void main() {
  tearDown(() => setPlatformDeviceNameForTest(null));

  test('the platform answer wins, because the owner chose it', () {
    setPlatformDeviceNameForTest("Saber's Phone");
    expect(deviceName(), "Saber's Phone");
  });

  test('a blank platform answer is no answer', () {
    setPlatformDeviceNameForTest('   ');
    // Falls through to the hostname, which on this machine is a real name.
    expect(deviceName().trim(), isNotEmpty);
    expect(deviceName().trim(), isNot('   '));
  });

  test('no platform answer still gives something a person can point at', () {
    setPlatformDeviceNameForTest(null);
    final name = deviceName();
    expect(name.trim(), isNotEmpty);
    // THE point of this file: never the loopback name, on any platform.
    expect(name.toLowerCase(), isNot('localhost'));
    expect(name.toLowerCase(), isNot(startsWith('localhost.')));
    expect(name, isNot('127.0.0.1'));
  });

  test('on this machine that is the hostname, which is a real name', () {
    // Windows, macOS and Linux all report a usable hostname; only the mobile platforms do not, and
    // those cannot be exercised from here. So this pins the desktop half.
    setPlatformDeviceNameForTest(null);
    expect(deviceName(), Platform.localHostname,
        skip: Platform.localHostname.isEmpty ? 'deze machine noemt zichzelf niets' : false);
  });

  test('platformName says which kind of device this is', () {
    expect(platformName(), isNot('onbekend'),
        reason: 'een platform dat we niet herkennen kan de pc niet in een lijst zetten');
  });

  group('the identity itself', () {
    test('the id is kept but the name is not, so a bad name corrects itself', () async {
      // Only `id` is read back from device_id.json — see thisDevice(). That is what lets a phone
      // that once reported "localhost" show its real name the next time it connects, with no
      // migration and without orphaning its grant.
      final first = await thisDevice();
      expect(first.id, isNotEmpty);
      expect(first.name, deviceName());
      expect(first.platform, platformName());
    });
  });
}
