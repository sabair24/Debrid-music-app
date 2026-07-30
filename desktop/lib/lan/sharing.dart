import 'dart:io';

import 'package:flutter/foundation.dart';

import '../cloud/device_identity.dart';
import '../library.dart';
import '../musicbrainz.dart';
import '../online.dart';
import '../settings.dart';
import 'discovery.dart';
import 'ids.dart';
import 'net.dart';
import 'pairing.dart';
import 'server.dart';
import 'state_store.dart';
import 'tokens.dart';

/// Owns the LAN server's lifecycle and everything the settings panel shows about it.
///
/// Separate from [LanServer] so the UI has one thing to listen to: whether sharing is on, which
/// address to type into the other device, and what went wrong if it didn't start.
class LanSharing extends ChangeNotifier {
  LanSharing({
    required this.library,
    required this.settings,
    this.online,
    this.soulseek,
    this.downloads,
    this.musicbrainz,
  }) : state = LanStateStore(File('${_appDir()}${Platform.pathSeparator}state.json'));

  final LibraryStore library;
  final AppSettings settings;

  /// Handed straight to the server so a Mac or an iPad can have this PC search and download for
  /// it. Null in a test, and on a PC where those were never set up — the routes say so.
  final OnlineService? online;
  final SoulseekService? soulseek;
  final DownloadManager? downloads;

  /// So this PC can work out an album's pressing when a phone or the television asks for it —
  /// once, here, instead of once per device.
  final MusicBrainzService? musicbrainz;

  /// Playlists, favourites, play position and counts — shared with every device. Lives here
  /// rather than in the server so switching sharing off doesn't drop what the PC itself knows.
  final LanStateStore state;

  /// One token per device. Same reason it lives here and not in the server: turning sharing off
  /// must not forget which devices you trust.
  final GrantStore grants = GrantStore();

  /// The six-digit code a new device types in. Outlives any one server instance so toggling
  /// sharing mid-pairing doesn't strand the device halfway.
  final PairingStore pairing = PairingStore();

  LanServer? _server;
  LanDiscovery? _discovery;
  String? _error;
  List<String> _addresses = const [];
  bool _stateLoaded = false;
  bool _adoptLegacy = false;
  String version = '';

  bool get running => _server?.running ?? false;
  String? get error => _error;
  List<String> get addresses => _addresses;
  String get token => settings.lanToken;
  int get port => settings.lanPort;
  LanServer? get server => _server;

  /// The line to type into the Mac, iPad or Shield when discovery can't find us.
  String? get primaryUrl => _addresses.isEmpty ? null : _addresses.first;

  /// Everything a device needs, in one string — what the QR code in settings encodes.
  String? get pairingCode {
    final url = primaryUrl;
    return url == null ? null : '$url#${settings.lanToken}';
  }

  /// Bring the server in line with the current settings. Safe to call repeatedly.
  Future<void> applySettings() async {
    if (!_stateLoaded) {
      _stateLoaded = true;
      await state.load();
      // The grants too. Without this the PC starts with an empty set of device tokens, so every
      // device that had been given access is refused after a restart — and does not recover by
      // itself, because the cloud only answers requests that are still pending.
      await grants.load();
      _adoptLegacy = true;
    }
    if (settings.lanToken.isEmpty) {
      settings.lanToken = generateLanToken();
      await settings.save();
    }
    if (_adoptLegacy) {
      _adoptLegacy = false;
      // After the token exists, not before: on a first run it is generated a few lines up, and
      // adopting an empty one silently does nothing.
      //
      // Everything paired before per-device tokens existed becomes one row you can revoke on
      // purpose, rather than an empty list while devices are demonstrably connected.
      grants.adoptLegacyToken(settings.lanToken);
    }

    final wanted = settings.lanEnabled;
    final current = _server;

    // A port change has to go through a full restart — you cannot rebind a listening socket.
    if (current != null && (!wanted || current.port != settings.lanPort)) {
      await _discovery?.stop();
      _discovery = null;
      await current.dispose();
      _server = null;
    }
    if (current != null && wanted && current.port == settings.lanPort) {
      current.token = settings.lanToken;
      await _refreshAddresses();
      return;
    }
    if (!wanted) {
      _error = null;
      _addresses = const [];
      notifyListeners();
      return;
    }

    final server = LanServer(
      library: library,
      token: settings.lanToken,
      state: state,
      pairing: pairing,
      port: settings.lanPort,
      version: version,
      online: online,
      soulseek: soulseek,
      downloads: downloads,
      settings: settings,
      musicbrainz: musicbrainz,
      grants: grants,
    );
    _error = await server.start();
    _server = _error == null ? server : null;
    if (_server != null) {
      final discovery = LanDiscovery(
        port: _server!.boundPort,
        deviceName: deviceName(),
        trackCount: () => library.tracks.length,
      );
      await discovery.start();
      _discovery = discovery;
    }
    await _refreshAddresses();
  }

  /// True when the PC is announcing itself, so the settings panel can say whether a device should
  /// find it on its own or needs the address typed in.
  bool get discoverable => _discovery?.advertising ?? false;

  Future<void> _refreshAddresses() async {
    _addresses = _server == null
        ? const []
        : [for (final ip in await lanAddresses()) 'http://$ip:${_server!.port}'];
    notifyListeners();
  }

  /// This PC reporting where it is, so the iPad can carry on from the same second.
  ///
  /// Goes through the same op path the other devices use — there is no privileged local route,
  /// which is why "who is furthest along" resolves the same way wherever playback happens.
  void reportProgress(
    String trackPath,
    Duration position,
    bool playing,
    List<String> queuePaths,
    int index,
  ) {
    final id = _trackId(trackPath);
    if (id == null) return;
    state.applyOps([
      {
        'type': 'progress',
        'trackId': id,
        'positionMs': position.inMilliseconds,
        'queue': [for (final p in queuePaths) _trackId(p) ?? ''],
        'index': index,
        'playing': playing,
        'at': DateTime.now().millisecondsSinceEpoch,
      }
    ], deviceId: 'pc-${deviceName()}', deviceName: deviceName());
  }

  void reportPlayed(String trackPath) {
    final id = _trackId(trackPath);
    if (id == null) return;
    state.applyOps([
      {'type': 'played', 'trackId': id, 'at': DateTime.now().millisecondsSinceEpoch}
    ], deviceId: 'pc-${deviceName()}');
  }

  /// A file path back to the id the other devices know it by. Null for anything that isn't a
  /// library file — a radio item resolved to a TorBox URL has no place in the shared state.
  String? _trackId(String path) {
    if (path.isEmpty || path.startsWith('http')) return null;
    return trackIdFor(path, library.rootPath);
  }

  /// Show a pairing code, and return it. Valid for [PairingStore.codeLifetime].
  String startPairing() {
    final code = pairing.start();
    notifyListeners();
    return code;
  }

  /// Stop showing it — on a successful pair, or when the user closes the panel.
  void stopPairing() {
    pairing.stop();
    notifyListeners();
  }

  String? get pairingCodeDigits => pairing.code;

  /// Issue a new token — the deliberate way to unpair every device at once.
  Future<void> rotateToken() async {
    settings.lanToken = generateLanToken();
    await settings.save();
    _server?.token = settings.lanToken;
    notifyListeners();
  }

  @override
  void dispose() {
    _discovery?.stop();
    _server?.dispose();
    state.dispose();
    super.dispose();
  }
}

/// `%APPDATA%\DebridMusic` on Windows, the home folder elsewhere — the same place the library's
/// corrections and the player's resume file already live.
String _appDir() {
  final base = Platform.environment['APPDATA'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  return '$base${Platform.pathSeparator}DebridMusic';
}
