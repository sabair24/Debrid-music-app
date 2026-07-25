/// What this device calls itself, and how it is told apart from every other one.
///
/// The id is random and written once, deliberately not derived from the hostname: two Macs are
/// both called `MacBook-Pro` often enough, and a name is the thing a person is allowed to change.
/// If the id moved when the name did, renaming your iPad would silently orphan its grant and the
/// PC would show two rows for one device.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../paths.dart';

class DeviceIdentity {
  const DeviceIdentity({required this.id, required this.name, required this.platform});

  final String id;
  final String name;
  final String platform;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'platform': platform};
}

DeviceIdentity? _cached;

/// Read once, kept for the run. Written to `device_id.json` the first time.
Future<DeviceIdentity> thisDevice() async {
  final cached = _cached;
  if (cached != null) return cached;

  final file = appFile('device_id.json');
  String? id;
  try {
    if (await file.exists()) {
      final j = jsonDecode(await file.readAsString());
      if (j is Map && (j['id'] ?? '').toString().isNotEmpty) id = '${j['id']}';
    }
  } catch (e) {
    debugPrint('device_id.json unreadable: $e');
  }

  id ??= _randomId();
  final identity = DeviceIdentity(id: id, name: deviceName(), platform: platformName());

  try {
    await file.writeAsString(jsonEncode(identity.toJson()));
  } catch (e) {
    // A read-only disk means a new id next start — annoying (a duplicate row in the device list)
    // but not fatal, so this is not worth refusing to start over.
    debugPrint('Could not save device_id.json: $e');
  }
  _cached = identity;
  return identity;
}

/// What the PC lists this device as. Its own name, because "iPad van Saber" is what you look for
/// in a list — not a serial number.
String deviceName() {
  try {
    final host = Platform.localHostname;
    if (host.isNotEmpty) return host;
  } catch (_) {/* sandboxed iOS can refuse this */}
  return switch (platformName()) {
    'ios' => 'iPad',
    'macos' => 'Mac',
    'windows' => 'Windows-pc',
    _ => 'Apparaat',
  };
}

String platformName() {
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isLinux) return 'linux';
  return 'onbekend';
}

String _randomId() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// For tests, which must not read or write the real device file.
@visibleForTesting
void setDeviceIdentityForTest(DeviceIdentity? identity) => _cached = identity;
