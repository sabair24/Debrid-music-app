/// Signed in, and what that means on each side.
///
/// Firebase decides **who** you are. The PC decides **what** you may fetch, and mints the opaque
/// token it has always minted. Those two halves meet in exactly one place: a device writes a
/// request into Firestore, and the PC — signed in as the same account — writes a token back.
///
/// Two properties fall out of that, and they are the reason it is shaped this way:
///
///   • **The PC serves music with the internet unplugged.** Its grant list is a local file. If
///     Firebase is unreachable it stops handing out NEW grants and stops publishing its address;
///     every device that already has a token keeps working exactly as before.
///   • **A Firebase token never touches the transport.** An ID token is a ~1 KB JWT that expires
///     hourly. libmpv caches a stream URL, so an album paused for an hour would refuse to resume —
///     and verifying such a token would mean the PC needed Google reachable to serve its own LAN.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../lan/tokens.dart';
import '../paths.dart';
import 'auth.dart';
import 'config.dart';
import 'device_identity.dart';
import 'firestore.dart';
import 'zuinig.dart';

enum CloudState {
  /// No Firebase project in this build — the app falls back to pairing codes.
  disabled,

  /// Nobody signed in yet.
  signedOut,

  restoring,
  signedIn,
}

/// A PC that published itself under this account.
class CloudServer {
  const CloudServer({
    required this.id,
    required this.name,
    required this.urls,
    required this.online,
    required this.lastSeen,
  });

  final String id;
  final String name;

  /// Every address this PC believes it is reachable at. More than one because a machine with a VPN
  /// or Hyper-V has several, and only the device trying them knows which one it can actually
  /// reach.
  final List<String> urls;
  final bool online;
  final DateTime? lastSeen;

  /// De pc bevestigt zijn aanwezigheid hoogstens eens per anderhalve minuut (zie [kHartslagRitme]);
  /// twee minuten stilte betekent dus slapen of uitgezet, niet een hapering. Mislukt een slag, dan
  /// gaat de volgende dertig seconden later alsnog — ruim binnen dit venster.
  bool get isFresh {
    final seen = lastSeen;
    if (seen == null) return false;
    return DateTime.now().difference(seen) < const Duration(minutes: 2);
  }
}

class CloudSession extends ChangeNotifier {
  CloudSession({CloudAuth? auth, CloudConfig? config, http.Client? firestoreClient})
      : config = config ?? CloudConfig.current,
        _auth = auth ?? CloudAuth(config: config),
        _firestoreClient = firestoreClient;

  final CloudConfig config;
  final CloudAuth _auth;

  /// Only ever set by a test. Without this seam the whole grant handshake could only be exercised
  /// against a real Firebase project, which means it would not be exercised.
  final http.Client? _firestoreClient;

  CloudState state = CloudState.signedOut;
  CloudUser? user;

  /// The last thing that went wrong, for the screen to show. Never thrown out of here into
  /// `main()` — a cloud that is down must not stop the app from starting.
  String? lastError;

  Timer? _heartbeat;
  Timer? _watch;

  String get uid => user?.uid ?? '';
  bool get isSignedIn => user != null;

  /// A Firestore client with a token that is good right now, or null when not signed in.
  /// Public so the download queue can be built on the same session rather than a second one.
  Future<Firestore?> db() => _db();

  Future<Firestore?> _db() async {
    final u = await _fresh();
    return u == null
        ? null
        : Firestore(token: u.idToken, config: config, client: _firestoreClient);
  }

  /// The current user with a token that is good for at least another minute, refreshing if not.
  Future<CloudUser?> _fresh() async {
    final u = user;
    if (u == null) return null;
    if (!u.isExpired) return u;
    try {
      final next = await _auth.refresh(u.refreshToken, uid: u.uid, email: u.email);
      user = next;
      await _persist(next);
      return next;
    } on CloudAuthException catch (e) {
      lastError = e.message;
      // Only a refusal means the session is really gone. A flat network must not sign you out —
      // that would log you out of your own PC every time the wifi hiccups.
      if (e.code != 'NETWORK') await signOut();
      notifyListeners();
      return null;
    }
  }

  // ── Signing in ─────────────────────────────────────────────────────────────

  Future<void> restore() async {
    if (!config.isConfigured) {
      state = CloudState.disabled;
      notifyListeners();
      return;
    }
    state = CloudState.restoring;
    notifyListeners();
    try {
      final file = appFile('cloud_session.json');
      if (await file.exists()) {
        final saved = CloudUser.fromJson(
            (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>());
        if (saved != null) {
          user = await _auth.refresh(saved.refreshToken, uid: saved.uid, email: saved.email);
          await _persist(user!);
        }
      }
    } catch (e) {
      debugPrint('Cloud restore failed: $e');
    }
    state = user == null ? CloudState.signedOut : CloudState.signedIn;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    user = await _auth.signIn(email, password);
    await _persist(user!);
    state = CloudState.signedIn;
    lastError = null;
    notifyListeners();
  }

  Future<void> register(String email, String password) async {
    user = await _auth.register(email, password);
    await _persist(user!);
    state = CloudState.signedIn;
    lastError = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    _heartbeat?.cancel();
    _watch?.cancel();
    _heartbeat = null;
    _watch = null;
    user = null;
    state = config.isConfigured ? CloudState.signedOut : CloudState.disabled;
    try {
      final f = appFile('cloud_session.json');
      if (await f.exists()) await f.delete();
    } catch (_) {/* nothing to forget */}
    notifyListeners();
  }

  Future<void> _persist(CloudUser u) async {
    try {
      await appFile('cloud_session.json').writeAsString(jsonEncode(u.toJson()));
    } catch (e) {
      debugPrint('Could not save the cloud session: $e');
    }
  }

  // ── On the PC: publish where I am, and hand out tokens ─────────────────────

  /// Start behaving like the machine that owns the music.
  ///
  /// [addresses] is asked for on every beat rather than captured once: a laptop that moves between
  /// wifi and ethernet changes address without restarting, and a stale address is exactly the
  /// "Geen pc gevonden" this is meant to end.
  void startAsOwner({
    required String serverId,
    required String serverName,
    required int port,
    required List<String> Function() addresses,
    required GrantStore grants,
    required int Function() trackCount,
  }) {
    _heartbeat?.cancel();
    // Wat er de vorige keer werkelijk geschreven is, en wanneer. Alleen hierdoor kan de slag
    // hieronder overgeslagen worden — zie `zuinig.dart` voor wat dat kostte.
    Map<String, dynamic>? gezet;
    DateTime? geschrevenOm;

    Future<void> beat() async {
      if (!isSignedIn) return;
      try {
        final db = await _db();
        if (db == null) return;
        final nu = DateTime.now().toUtc();
        final regel = <String, dynamic>{
          'name': serverName,
          'platform': platformName(),
          'port': port,
          'urls': addresses(),
          'online': true,
          'trackCount': trackCount(),
        };
        // NIET elke slag schrijven. Deze regel bevatte een tijdstempel en werd daarom altijd
        // opnieuw weggeschreven — 2880 keer per dag voor een pc die niets doet, tegen een gratis
        // daglimiet van 20 000. Verandert er iets aan het adres, de poort of het aantal nummers,
        // dan gaat het meteen; anders eens per anderhalve minuut, ruim binnen het venster van twee
        // minuten waarin een pc als online telt.
        final veranderd = serverRegelVeranderd(gezet, regel);
        if (moetServerSchrijven(
          veranderd: veranderd,
          sindsLaatsteSchrijf:
              geschrevenOm == null ? const Duration(days: 1) : nu.difference(geschrevenOm!),
        )) {
          await db.set('users/$uid/servers/$serverId', {...regel, 'lastSeenAt': nu});
          gezet = regel;
          geschrevenOm = nu;
        }
        await _grantPending(db, serverId, grants);
        lastError = null;
      } catch (e) {
        // Losing Firestore is not losing the library. Say it once and carry on serving.
        lastError = '$e';
      }
    }

    unawaited(beat());
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(beat()));
  }

  /// Answer every device that asked for access while we were looking the other way.
  Future<void> _grantPending(Firestore db, String serverId, GrantStore grants) async {
    final requests = await db.list('users/$uid/servers/$serverId/grants');
    for (final doc in requests) {
      if (doc.data['status'] != 'pending') continue;
      final grant = grants.mint(
        deviceId: doc.id,
        deviceName: (doc.data['deviceName'] ?? 'Onbekend apparaat').toString(),
        platform: (doc.data['platform'] ?? '').toString(),
      );
      // Disk before cloud, deliberately. A crash between the two must not leave a device holding a
      // token this PC has never heard of — that device would be refused with no way to tell why.
      await grants.save();
      await db.set('users/$uid/servers/$serverId/grants/${doc.id}', {
        'status': 'granted',
        'token': grant.token,
        'grantedAt': DateTime.now().toUtc(),
      });
    }
  }

  /// Cut one device off everywhere: locally, and in the request document it is watching.
  Future<void> revokeDevice(String serverId, String deviceId, GrantStore grants) async {
    grants.revoke(deviceId);
    await grants.save();
    try {
      final db = await _db();
      await db?.set('users/$uid/servers/$serverId/grants/$deviceId', {
        'status': 'revoked',
        'token': '',
        'revokedAt': DateTime.now().toUtc(),
      });
    } catch (e) {
      // The local revocation is the one that counts — the PC refuses that token from now on
      // whatever Firestore thinks.
      debugPrint('Could not mirror the revocation: $e');
    }
  }

  /// Mark ourselves offline on a clean shutdown, so a device does not spend thirty seconds trying
  /// an address that stopped answering a moment ago.
  Future<void> goOffline(String serverId) async {
    try {
      final db = await _db();
      await db?.set('users/$uid/servers/$serverId', {'online': false});
    } catch (_) {/* the freshness check catches this anyway */}
  }

  // ── On a client: find my PC, and ask it for a token ────────────────────────

  Future<List<CloudServer>> servers() async {
    final db = await _db();
    if (db == null) return const [];
    final docs = await db.list('users/$uid/servers');
    return [
      for (final d in docs)
        CloudServer(
          id: d.id,
          name: (d.data['name'] ?? d.id).toString(),
          urls: [
            for (final u in (d.data['urls'] as List? ?? const []))
              if (u is String && u.isNotEmpty) u,
          ],
          online: d.data['online'] == true,
          lastSeen: d.data['lastSeenAt'] is DateTime ? d.data['lastSeenAt'] as DateTime : null,
        ),
    ];
  }

  /// Ask a PC for access. Returns the token once it has been granted, or null while we are still
  /// waiting — which is the ordinary state when the PC is simply switched off.
  Future<String?> requestAccess(String serverId) async {
    final db = await _db();
    if (db == null) return null;
    final me = await thisDevice();
    final path = 'users/$uid/servers/$serverId/grants/${me.id}';

    final existing = await db.get(path);
    final status = existing?.data['status'];
    if (status == 'granted') {
      final token = (existing?.data['token'] ?? '').toString();
      if (token.isNotEmpty) return token;
    }
    if (status == 'revoked') return null;

    if (existing == null || status != 'pending') {
      // Deliberately without a token field: the rules refuse a client that tries to hand itself
      // one, so a bug here fails loudly instead of quietly granting access.
      await db.set(path, {
        'status': 'pending',
        'deviceName': me.name,
        'platform': me.platform,
        'requestedAt': DateTime.now().toUtc(),
      });
    }
    return null;
  }

  /// Poll until the PC answers. [onWaiting] fires once so a screen can say what is going on rather
  /// than spinning silently.
  Future<String?> awaitAccess(
    String serverId, {
    Duration timeout = const Duration(minutes: 3),
    void Function()? onWaiting,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var announced = false;
    while (DateTime.now().isBefore(deadline)) {
      final token = await requestAccess(serverId);
      if (token != null) return token;
      if (!announced) {
        announced = true;
        onWaiting?.call();
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return null;
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _watch?.cancel();
    _auth.close();
    super.dispose();
  }
}
