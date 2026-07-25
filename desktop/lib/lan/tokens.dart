/// Which devices may talk to this PC, and with which token.
///
/// Deliberately knows nothing about Firebase. Signing in decides *who you are*; this decides *what
/// you may fetch*, and it is the half that has to keep working with the internet unplugged. A PC
/// whose cloud session has expired must still serve music to every device already holding a grant
/// — so this is a plain file, read at startup, consulted on every request.
///
/// It replaces a single shared secret. Until today every device that ever paired received the same
/// 32 hex characters, which meant "revoke one device" did not exist: the only lever unpaired them
/// all at once.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../paths.dart';

/// One device's permission to use this library.
class DeviceGrant {
  DeviceGrant({
    required this.deviceId,
    required this.deviceName,
    required this.token,
    required this.platform,
    required this.grantedAt,
    this.lastSeenAt,
    this.legacy = false,
  });

  final String deviceId;
  final String deviceName;
  final String token;
  final String platform;
  final int grantedAt;
  int? lastSeenAt;

  /// True for the one synthetic grant that stands in for everything paired before grants existed.
  /// Shown in the device list as a single row the user can revoke on purpose, rather than silently
  /// cutting off an iPad that was working fine yesterday.
  final bool legacy;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'token': token,
        'platform': platform,
        'grantedAt': grantedAt,
        'lastSeenAt': lastSeenAt,
        'legacy': legacy,
      };

  static DeviceGrant? fromJson(Map<String, dynamic> j) {
    final id = (j['deviceId'] ?? '').toString();
    final token = (j['token'] ?? '').toString();
    if (id.isEmpty || token.isEmpty) return null;
    return DeviceGrant(
      deviceId: id,
      deviceName: (j['deviceName'] ?? '').toString(),
      token: token,
      platform: (j['platform'] ?? '').toString(),
      grantedAt: (j['grantedAt'] as num?)?.toInt() ?? 0,
      lastSeenAt: (j['lastSeenAt'] as num?)?.toInt(),
      legacy: j['legacy'] == true,
    );
  }
}

/// 32 hex characters from a secure source. Same shape as the token this replaces, so nothing that
/// carries one — a query string, a Retrofit header, a saved `paired_server.json` — has to change.
String generateDeviceToken() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class GrantStore {
  GrantStore({File? file}) : _file = file ?? appFile('grants.json');

  final File _file;
  final Map<String, DeviceGrant> _byDevice = {};

  /// token → deviceId. Rebuilt with the map, so accepting a request is a hash lookup rather than a
  /// walk: this runs on every single HTTP request, including every range request of a stream.
  final Map<String, String> _byToken = {};

  List<DeviceGrant> get all => _byDevice.values.toList()
    ..sort((a, b) => b.grantedAt.compareTo(a.grantedAt));

  bool get isEmpty => _byDevice.isEmpty;

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! List) return;
      _byDevice.clear();
      _byToken.clear();
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final g = DeviceGrant.fromJson(e);
        if (g == null) continue;
        _byDevice[g.deviceId] = g;
        _byToken[g.token] = g.deviceId;
      }
    } catch (e) {
      // A corrupt file must not lock you out of your own library — the legacy token below still
      // works, and a device can simply be granted again.
      debugPrint('grants.json unreadable: $e');
    }
  }

  Future<void> save() async {
    try {
      // Same tmp-then-rename as the rest of this app's state: a power cut halfway through a write
      // must not leave a truncated file that reads as "no devices".
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final g in _byDevice.values) g.toJson()]));
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Could not save grants.json: $e');
    }
  }

  /// The check on every request. Constant-time on the token so a wrong guess cannot be narrowed
  /// down by timing — cheap here, and the previous `==` had no such property.
  bool accepts(String token) {
    if (token.isEmpty) return false;
    final deviceId = _byToken[token];
    if (deviceId == null) return false;
    return _constantTimeEquals(token, _byDevice[deviceId]?.token ?? '');
  }

  DeviceGrant? grantFor(String token) {
    final id = _byToken[token];
    return id == null ? null : _byDevice[id];
  }

  DeviceGrant? byDevice(String deviceId) => _byDevice[deviceId];

  /// Issue a token for a device. Idempotent per device: asking twice returns the grant that is
  /// already out there rather than minting a second one and orphaning the first.
  DeviceGrant mint({
    required String deviceId,
    required String deviceName,
    String platform = '',
  }) {
    final existing = _byDevice[deviceId];
    if (existing != null) return existing;
    final grant = DeviceGrant(
      deviceId: deviceId,
      deviceName: deviceName,
      token: generateDeviceToken(),
      platform: platform,
      grantedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _byDevice[deviceId] = grant;
    _byToken[grant.token] = deviceId;
    return grant;
  }

  /// Cut off exactly one device. This is the thing that could not be done before.
  bool revoke(String deviceId) {
    final gone = _byDevice.remove(deviceId);
    if (gone == null) return false;
    _byToken.remove(gone.token);
    return true;
  }

  void revokeAll() {
    _byDevice.clear();
    _byToken.clear();
  }

  /// Stand in for everything paired before grants existed, so upgrading does not cut off a device
  /// that was working a minute ago. One row in the list, revocable on purpose.
  void adoptLegacyToken(String token) {
    if (token.isEmpty || _byToken.containsKey(token)) return;
    const id = 'legacy';
    final grant = DeviceGrant(
      deviceId: id,
      deviceName: 'Eerder gekoppelde apparaten',
      token: token,
      platform: '',
      grantedAt: 0,
      legacy: true,
    );
    _byDevice[id] = grant;
    _byToken[token] = id;
  }

  /// Remember that a token was used, for the device list. Debounced to a minute: this is reached
  /// from every range request of a stream, and a disk write per request would be absurd.
  bool touch(String token) {
    final grant = grantFor(token);
    if (grant == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (grant.lastSeenAt ?? 0) < 60000) return false;
    grant.lastSeenAt = now;
    return true;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
