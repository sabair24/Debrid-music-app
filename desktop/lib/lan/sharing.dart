import 'dart:io';

import 'package:flutter/foundation.dart';

import '../cloud/device_identity.dart';
import '../library.dart';
import '../musicbrainz.dart';
import '../online.dart';
import '../settings.dart';
import '../warm_log.dart';
import '../paths.dart';
import 'certificaat.dart';
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
    this.cloudUid,
    this.uidVanSleutel,
    this.firebaseProject,
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

  /// Met welk account deze pc is ingelogd, en hoe je een inlogsleutel nakijkt. Samen laten ze een
  /// toestel op hetzelfde netwerk binnen op grond van het ACCOUNT, zonder Firestore. Zie
  /// `accountkoppeling.dart`.
  final String Function()? cloudUid;
  final Future<String> Function(String idToken)? uidVanSleutel;

  /// Zie [LanServer.firebaseProject].
  final String Function()? firebaseProject;

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

  /// Het eigen certificaat voor de versleutelde ingang 47822 (`certificaat.dart`). Eén keer geladen of
  /// gemaakt; zonder certificaat draait alleen 47820, zoals voorheen.
  PcCertificaat? _certificaat;

  /// De pin van dit certificaat, voor de hartslag in het account (geen geheim). Leeg zonder certificaat.
  String get pin => _certificaat?.pin ?? '';

  /// Een rode melding voor op de pc (misbruik van een sleutel). Leeft hier en niet in de server, zodat
  /// het scherm er één keer naar luistert, ook als de server herstart.
  final ValueNotifier<String?> rodeMelding = ValueNotifier(null);
  String? _error;
  List<String> _home = const [];
  /// De eenmalige laadbeurt van state + grants. Een tweede aanroep wacht hierop.
  Future<void>? _laden;
  bool _adoptLegacy = false;
  String version = '';

  bool get running => _server?.running ?? false;

  /// Waar de versleutelde ingang voor thuis luistert, of null (noodrem uit, of geen certificaat).
  int? get tlsBoundPort => _server?.tlsBoundPort;
  String? get error => _error;

  /// Every address this PC answers on, the ones that survive leaving the house first. That order
  /// is what makes [primaryUrl] and the cloud relay hand out the useful one without either of them
  /// having to know what Tailscale is.
  List<String> get addresses => [..._remote, ..._home];

  /// Only the ones that stop at the front door — so the settings panel can label them honestly.
  List<String> get homeAddresses => _home;
  String get token => settings.lanToken;
  int get port => settings.lanPort;
  LanServer? get server => _server;

  /// The addresses that also answer when the device is not on this network. See [isRemoteReachable]
  /// — in practice, Tailscale.
  List<String> _remote = const [];

  /// The one to give a phone that leaves the house, or null when there is no such address.
  String? get remoteUrl => _remote.isEmpty ? null : _remote.first;

  /// The line to type into the Mac, iPad or Shield when discovery can't find us.
  ///
  /// Prefers an address that works everywhere. A phone paired with `192.168.0.117` works until it
  /// walks out the door and then simply stops, with nothing on screen explaining why — while the
  /// address that survives the walk works at home too, direct over the same network. So when there
  /// is one, it is the answer to "which address" in every case, not only the away case.
  String? get primaryUrl => remoteUrl ?? (_home.isEmpty ? null : _home.first);

  /// Bring the server in line with the current settings. Safe to call repeatedly.
  Future<void> applySettings() async {
    // Eén keer laden, maar een tweede aanroep WACHT erop in plaats van het over te slaan.
    //
    // De vlag stond hiervoor omhoog vóór de twee awaits. Wie tijdens het opstarten de schakelaar
    // "Delen" omzette — main.dart roept dit dan opnieuw aan — liet die tweede aanroep het laden
    // overslaan en even verderop een server starten met een LEGE koppelingenwinkel. Elk toestel
    // krijgt dan 401, en er is geen enkel pad dat dat later nog herstelt: `load()` staat achter
    // precies deze vlag.
    _laden ??= () async {
        // Waar het inlezen van de koppelingen zijn uitkomst kwijt kan — naast start.log, want een
        // stille mislukking hier weigert de rest van de sessie élk toestel.
        final dir = library.configDir;
        if (dir.isNotEmpty) {
          final log = WarmLog('$dir${Platform.pathSeparator}koppeling.log');
          grants.meldlog = log.line;
        }
        await state.load();
        // The grants too. Without this the PC starts with an empty set of device tokens, so every
        // device that had been given access is refused after a restart — and does not recover by
        // itself, because the cloud only answers requests that are still pending.
        await grants.load();
        _adoptLegacy = true;
      }();
    await _laden;
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
    // De noodrem om (`settings.versleuteld`): ook dat kan alleen met een volledige herstart, want de
    // versleutelde ingangen gaan open of dicht met de server.
    final remOm = current != null && (current.certificaat != null) != (settings.versleuteld && _certificaat != null);
    if (current != null && (!wanted || current.port != settings.lanPort || remOm)) {
      await _discovery?.stop();
      _discovery = null;
      await current.dispose();
      _server = null;
    }
    if (current != null && wanted && current.port == settings.lanPort && !remOm) {
      current.token = settings.lanToken;
      await _refreshAddresses();
      return;
    }
    if (!wanted) {
      _error = null;
      _home = const [];
      _remote = const [];
      notifyListeners();
      return;
    }

    // Een vaste id voor deze pc, ook als hij niet bij een account is aangemeld: een toestel herkent
    // er zijn pc aan als het tussen adressen kiest (`adreswedloop.dart`).
    if (settings.serverId.isEmpty) {
      settings.serverId = generateDeviceToken().substring(0, 16);
      await settings.save();
    }
    // Het certificaat, één keer. Mislukt het, dan geen versleutelde ingang — 47820 draait gewoon.
    if (_certificaat == null) {
      try {
        _certificaat = await PcCertificaat.laadOfMaak(appFile('tls_cert.pem').parent, log: grants.meldlog);
      } catch (e) {
        grants.meldlog?.call('certificaat niet te laden of te maken: $e — alleen 47820');
      }
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
      cloudUid: cloudUid,
      uidVanSleutel: uidVanSleutel,
      firebaseProject: firebaseProject,
      // De noodrem: zonder certificaat geen versleutelde ingang, en vallen de toestellen terug op 47820.
      certificaat: settings.versleuteld ? _certificaat : null,
      // Poort 0 in een toets: dan ook hier vrij kiezen, en nooit de echte 47822 van de draaiende app.
      tlsPoort: settings.lanPort == 0 ? 0 : kTlsPoort,
      // De deur naar buiten (47821) gaat pas open met stap 7, als jij hem aanzet.
      rodeMelding: rodeMelding,
      grants: grants,
    );
    _error = await server.start();
    _server = _error == null ? server : null;
    if (_server != null) {
      final discovery = LanDiscovery(
        port: _server!.boundPort,
        deviceName: deviceName(),
        trackCount: () => library.tracks.length,
        serverId: settings.serverId,
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
    if (_server == null) {
      _home = const [];
      _remote = const [];
      notifyListeners();
      return;
    }
    final port = _server!.port;
    final split = await addressesByReach();
    _remote = [for (final ip in split.overal) 'http://$ip:$port'];
    _home = [for (final ip in split.thuis) 'http://$ip:$port'];
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

  // `reportPlayed` stond hier, en is op 28-08-2026 weggehaald. Hij telde een beluistering bij het
  // OPENEN van een nummer, hij hing alleen op de pc ingehangen, en hij was een tweede schrijver naar
  // dezelfde gedeelde staat naast `GedeeldeOps`. Alle drie de bezwaren worden opgelost door
  // `Speelstanden` (`speelstanden.dart`), die op elk toestel werkt en pas telt als er werkelijk
  // geluisterd is.

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
