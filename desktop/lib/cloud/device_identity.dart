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
import 'package:flutter/services.dart';

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

/// The same channel `tv.dart` uses. A MethodChannel is only a name, so a second handle to it costs
/// nothing and keeps this module out of the UI layer.
const _platform = MethodChannel('debridmusic/device');

/// What Android says this device is called. Null everywhere else, and until [initDeviceName] runs.
String? _platformName;

/// Ask Android for this device's name, before anything publishes one.
///
/// Same shape and the same reason as [initTvMode]: `audio_service` warms an engine up front, so
/// Dart can be running before the activity has registered the channel. Bounded, and a device that
/// never answers simply falls back below.
Future<void> initDeviceName() async {
  if (!Platform.isAndroid) return;
  for (var attempt = 0; attempt < 20; attempt++) {
    try {
      final name = await _platform.invokeMethod<String>('deviceName');
      final trimmed = name?.trim() ?? '';
      if (trimmed.isNotEmpty) _platformName = trimmed;
      return;
    } on MissingPluginException {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    } catch (e) {
      debugPrint('Device name unavailable: $e');
      return;
    }
  }
}

/// A hostname that names no device. Android and iOS both answer `localhost`, and it is true and
/// useless: seven phones listed as "localhost" is a device list you cannot revoke anything from.
bool _namesNobody(String host) {
  final h = host.toLowerCase();
  return h == 'localhost' || h.startsWith('localhost.') || h == '127.0.0.1' || h == 'android';
}

/// What the PC lists this device as. Its own name, because "iPad van Saber" is what you look for
/// in a list — not a serial number.
///
/// Only the id is read back from disk, never the name, so a device that used to report a poor one
/// corrects itself the next time it connects.
String deviceName() {
  // Trimmed here as well as where it is stored: "is this a usable name" belongs with the answer,
  // not with whoever happened to set it.
  final fromPlatform = _platformName?.trim();
  if (fromPlatform != null && fromPlatform.isNotEmpty) return fromPlatform;
  try {
    final host = Platform.localHostname;
    if (host.isNotEmpty && !_namesNobody(host)) return host;
  } catch (_) {/* sandboxed iOS can refuse this */}
  return switch (platformName()) {
    'ios' => 'iPad',
    'macos' => 'Mac',
    'windows' => 'Windows-pc',
    // Reached only when the channel stayed silent — an Android build without the native side, or
    // an engine that came up without an activity. Still better than "localhost".
    'android' => 'Android-toestel',
    'linux' => 'Linux-pc',
    _ => 'Apparaat',
  };
}

/// For tests: pretend the platform answered (or didn't).
@visibleForTesting
void setPlatformDeviceNameForTest(String? name) => _platformName = name;

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
