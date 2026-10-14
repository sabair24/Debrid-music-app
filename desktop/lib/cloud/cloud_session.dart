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
import '../lan/verbindingsstand.dart';
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

  /// De pc bevestigt zijn aanwezigheid hoogstens eens per minuut (zie [kHartslagRitme]); twee
  /// minuten stilte betekent dus slapen of uitgezet, niet een hapering. Mislukt een slag, dan gaat
  /// de volgende dertig seconden later alsnog — een halve minuut binnen dit venster.
  ///
  /// Het venster staat als getal in `zuinig.dart`, naast het ritme, want die twee horen bij elkaar:
  /// verruim je er één zonder de ander, dan flikkert een pc op het koppelscherm of blijft hij juist
  /// te lang "aan" staan.
  bool get isFresh {
    final seen = lastSeen;
    if (seen == null) return false;
    return DateTime.now().difference(seen) < kOnlineVenster;
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

  /// Klaar met herstellen — of dat nu lukte of niet.
  ///
  /// **Waarom dit bestaat.** Het zelfherstel van een geweigerde sleutel vuurde op 11-09-2026 om
  /// 17:15:56,244, nog geen drie tiende seconde na het opstarten. [restore] wordt bewust niet
  /// afgewacht voor het eerste beeld, dus stond [user] toen nog op null, gaf [idToken] een lege
  /// sleutel, en viel de accountweg af met "niet ingelogd" -- over een toestel dat gewoon ingelogd
  /// was. Wie kort na het opstarten een inlogsleutel nodig heeft, wacht hierop.
  ///
  /// Voltooit ook als [restore] niets te herstellen vond of de cloud uit staat: "klaar" betekent
  /// "je weet nu wat er is", niet "ingelogd".
  Future<void> get hersteld => _hersteld.future;
  final _hersteld = Completer<void>();

  void _klaarMetHerstellen() {
    if (!_hersteld.isCompleted) _hersteld.complete();
  }

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

  /// Een inlogsleutel die NU geldig is, of leeg als we niet ingelogd zijn.
  ///
  /// Dit is wat een toestel aan de pc laat zien om op grond van het account binnen te komen
  /// (`lan/accountkoppeling.dart`). Verlopen wordt hij eerst ververst — een sleutel van een uur oud
  /// wordt door Google geweigerd, en dan zou de pc denken dat je een ander account had.
  Future<String> idToken() async {
    final u = await _fresh();
    return u?.idToken ?? '';
  }

  /// Van welk account is deze inlogsleutel? Zie `CloudAuth.uidVanIdToken`.
  ///
  /// Doorgegeven en niet zelf uitgevoerd: de LAN-server heeft dit nodig om een toestel op grond van
  /// het account binnen te laten, en die kent `CloudAuth` niet.
  Future<String> uidVanSleutel(String idToken) => _auth.uidVanIdToken(idToken);

  // ── Signing in ─────────────────────────────────────────────────────────────

  Future<void> restore() async {
    if (!config.isConfigured) {
      state = CloudState.disabled;
      notifyListeners();
      _klaarMetHerstellen();
      return;
    }
    state = CloudState.restoring;
    notifyListeners();
    ({String uid, String email, String refreshToken})? bewaard;
    try {
      final file = appFile('cloud_session.json');
      if (await file.exists()) {
        bewaard = CloudUser.fromJson(
            (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>());
        if (bewaard != null) {
          user = await _auth.refresh(bewaard.refreshToken, uid: bewaard.uid, email: bewaard.email);
          await _persist(user!);
        }
      }
    } on CloudAuthException catch (e) {
      // EEN PLAT NETWERK LOGT JE NIET UIT. Dezelfde regel die [_fresh] al hanteert, en die hier
      // ontbrak: alles wat de verversing liet struikelen kwam in één `catch` terecht, `user` bleef
      // null, en de staat werd `signedOut`. Dus stond je op het inlogscherm omdat de wifi net niet
      // mee wilde — met je verversingssleutel nog gewoon op schijf.
      //
      // Gemeten op de Shield, 01-09-2026: bij het opstarten uit slaapstand mislukt de naamopzoeking
      // van `securetoken.googleapis.com` en meldt hij "Cloud restore failed". Een tv die uit
      // slaapstand komt heeft zijn netwerk simpelweg nog niet terug; dat is geen uitlogsignaal.
      //
      // We houden de sessie dan vast met een id-sleutel die AL verlopen is. Dat is geen truc: het
      // is precies wat er waar is -- we weten wie je bent, we hebben nog geen verse sleutel. De
      // eerste de beste [_fresh] haalt hem op zodra het netwerk er weer is, en die weet zelf al dat
      // NETWORK niet uitloggen betekent.
      if (e.code == 'NETWORK' && bewaard != null) {
        user = CloudUser(
          uid: bewaard.uid,
          email: bewaard.email,
          idToken: '',
          refreshToken: bewaard.refreshToken,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
      } else {
        // Een echte weigering: de sleutel is ingetrokken, het account uitgezet. Dán ben je uit.
        lastError = e.message;
      }
    } catch (e) {
      // Een onleesbaar of half geschreven bestand. Daar valt niets aan te herstellen.
      debugPrint('Cloud restore failed: $e');
    }
    state = user == null ? CloudState.signedOut : CloudState.signedIn;
    notifyListeners();
    _klaarMetHerstellen();
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
        if (!_sleutelsGewist) await _wisSleutelsUitDatabase(db, serverId);
        lastError = null;
      } catch (e) {
        // Losing Firestore is not losing the library. Say it once and carry on serving.
        lastError = '$e';
      }
    }

    unawaited(beat());
    // De tik gebruikt hetzelfde getal waar `kHartslagRitme` mee uitgerekend is. Zouden die twee uit
    // elkaar lopen, dan klopt de speling voor een gemiste slag niet meer — en dat is precies wat de
    // toets bewaakt.
    _heartbeat = Timer.periodic(kHartslagTik, (_) => unawaited(beat()));
  }

  /// Of de sleutels in de accountdatabase deze sessie al gewist zijn. Zie [_wisSleutelsUitDatabase].
  bool _sleutelsGewist = false;

  /// Elke sleutel die ooit via de accountdatabase uitgedeeld werd, daar weghalen. Eén keer per
  /// sessie, en opnieuw geprobeerd bij de volgende slag als het niet lukte.
  ///
  /// **Waarom.** Tot 14-10-2026 beantwoordde de pc een aanvraag in Firestore door de sleutel van het
  /// toestel er leesbaar in te zetten (`grants/<toestel>`: `status: granted, token: …`). De regels van
  /// die database zijn niet in deze repository te zien, en wie ze kan lezen had dan elke sleutel. Een
  /// toestel komt nu binnen door de pc rechtstreeks te vragen, op grond van het account
  /// (`/pair-cloud`, `accountkoppeling.dart`); Firestore is alleen nog een adresboek.
  ///
  /// De rij blijft staan (met `verlopen`), zodat een oudere app die nog wacht een antwoord ziet en
  /// niet blijft vragen; alleen de sleutel gaat eruit.
  Future<void> _wisSleutelsUitDatabase(Firestore db, String serverId) async {
    final rijen = await db.list('users/$uid/servers/$serverId/grants');
    for (final doc in rijen) {
      final sleutel = (doc.data['token'] ?? '').toString();
      if (sleutel.isEmpty) continue;
      await db.set('users/$uid/servers/$serverId/grants/${doc.id}', {
        'status': 'verlopen',
        'token': '',
        'verlopenOp': DateTime.now().toUtc(),
      });
    }
    _sleutelsGewist = true;
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

  /// Wat de pc met deze id het laatst over zichzelf schreef, voor de reden in de statusregel
  /// (`lan/verbindingsstand.dart`). Eén document, dus één leesbeurt. Zonder id (een koppeling van
  /// vóór de id): de enige pc onder je account, anders niets. Null = niet aangemeld of geen regel.
  ///
  /// Gooit [HartslagOnbereikbaar] als Firestore helemaal niet antwoordde — dan heeft dit toestel
  /// vrijwel zeker zelf geen internet. Een antwoord met een foutcode (429, 503) gooit gewoon door.
  Future<Hartslag?> hartslag(String serverId) async {
    if (!isSignedIn) return null;
    try {
      final db = await _db();
      if (db == null) return null;
      final FirestoreDoc? doc;
      if (serverId.isNotEmpty) {
        doc = await db.get('users/$uid/servers/$serverId');
      } else {
        final alle = await db.list('users/$uid/servers');
        doc = alle.length == 1 ? alle.single : null;
      }
      if (doc == null) return null;
      return Hartslag(online: doc.data['online'] == true, bijgewerkt: doc.updateTime, serverNu: doc.serverTijd);
    } on FirestoreException catch (e) {
      if (e.statusCode == null) throw const HartslagOnbereikbaar();
      rethrow;
    }
  }

  // Hier stonden `verseSleutelVoor`, `requestAccess` en `awaitAccess`: een toestel vroeg zijn sleutel
  // aan via een rij in de accountdatabase, en de pc zette hem daar leesbaar in. Weg sinds 14-10-2026;
  // zie [_wisSleutelsUitDatabase]. Een toestel vraagt het nu de pc zelf (`RemoteClient.pairMetAccount`).

  @override
  void dispose() {
    _heartbeat?.cancel();
    _watch?.cancel();
    _auth.close();
    super.dispose();
  }
}
