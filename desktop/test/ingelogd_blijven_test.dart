/// Ingelogd blijven, en een geweigerde sleutel die zichzelf vervangt.
///
/// **Waarom dit bestaat.** Op 01-09-2026 op de Shield gemeten: bij het opstarten uit slaapstand
/// mislukte de naamopzoeking van `securetoken.googleapis.com`, en dan stond je op het inlogscherm.
/// De verversingssleutel stond gewoon op schijf; het was alleen het netwerk dat nog niet terug was.
/// `restore()` ving élke fout in één `catch`, liet `user` op null en zette de staat op
/// `signedOut` -- dus loggen wij de gebruiker uit omdat de wifi even niet meewilde.
///
/// Dezelfde afweging stond al goed in `_fresh`: alleen een WEIGERING betekent dat je sessie weg is.
/// Deze toetsen leggen die regel vast op allebei de plekken, en de derde legt vast dat een toestel
/// waarvan de pc de sleutel niet meer aanvaardt er via het account weer in komt, zonder dat er
/// iemand zes cijfers hoeft over te tikken.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/cloud/auth.dart';
import 'package:debridmusic/cloud/cloud_session.dart';
import 'package:debridmusic/cloud/config.dart';
import 'package:debridmusic/cloud/device_identity.dart';
import 'package:debridmusic/cloud/firestore.dart';

import 'package:debridmusic/paths.dart';

const _config = CloudConfig(projectId: 'test-project', apiKey: 'test-key');

/// Firestore in een Map — genoeg om het toekennen echt te laten lopen.
class FakeFirestore {
  final Map<String, Map<String, dynamic>> docs = {};
  final List<String> writes = [];

  http.Client client() => MockClient((req) async {
        final path = Uri.decodeFull(req.url.path)
            .split('/documents/')
            .last
            .replaceAll(RegExp(r'\?.*$'), '');

        if (req.method == 'GET') {
          final children = docs.entries
              .where((e) =>
                  e.key.startsWith('$path/') && !e.key.substring(path.length + 1).contains('/'))
              .toList();
          if (docs.containsKey(path)) {
            return http.Response(jsonEncode(_wire(path, docs[path]!)), 200);
          }
          if (children.isEmpty) return http.Response('{}', 404);
          return http.Response(
            jsonEncode({'documents': [for (final c in children) _wire(c.key, c.value)]}),
            200,
          );
        }
        if (req.method == 'PATCH') {
          writes.add(path);
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final fields = (body['fields'] as Map).cast<String, dynamic>();
          docs.putIfAbsent(path, () => {}).addAll(fields);
          return http.Response(jsonEncode(_wire(path, docs[path]!)), 200);
        }
        return http.Response('{}', 404);
      });

  Map<String, dynamic> _wire(String path, Map<String, dynamic> fields) => {
        'name': 'projects/test-project/databases/(default)/documents/$path',
        'fields': fields,
        'updateTime': DateTime.now().toUtc().toIso8601String(),
      };

  Future<void> seed(String path, Map<String, dynamic> data) async {
    final store = Firestore(token: 't', config: _config, client: client());
    await store.set(path, data);
  }
}

/// Inloggen lukt; verversen doet wat de proef vraagt.
http.Client _auth({required http.Response Function() ververs}) => MockClient((req) async {
      if (req.url.path.contains('signInWithPassword') || req.url.path.contains('signUp')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'localId': 'user-1',
              'email': body['email'],
              'idToken': 'id-token',
              'refreshToken': 'refresh-token',
              'expiresIn': '3600',
            }),
            200);
      }
      if (req.url.host.startsWith('securetoken')) return ververs();
      return http.Response('{}', 404);
    });

/// Een net verversende server: de gewone gang van zaken.
http.Response _versGoed() => http.Response(
    jsonEncode({
      'user_id': 'user-1',
      'id_token': 'id-token-2',
      'refresh_token': 'refresh-token-2',
      'expires_in': '3600',
    }),
    200);

void main() {
  late Directory scratch;
  late FakeFirestore db;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_ingelogd_');
    setAppDirForTest(scratch.path);
    db = FakeFirestore();
    setDeviceIdentityForTest(
        const DeviceIdentity(id: 'shield-1', name: 'Shield van Saber', platform: 'android'));
  });

  tearDown(() {
    setDeviceIdentityForTest(null);
    scratch.deleteSync(recursive: true);
  });

  CloudSession sessie({required http.Response Function() ververs}) => CloudSession(
        config: _config,
        auth: CloudAuth(config: _config, client: _auth(ververs: ververs)),
        firestoreClient: db.client(),
      );

  /// Eerst een echte aanmelding, zodat er een bewaarde sessie op schijf staat om te herstellen.
  Future<void> meldAan() async {
    final s = sessie(ververs: _versGoed);
    await s.signIn('saber@example.test', 'goed');
    expect(File('${scratch.path}/cloud_session.json').existsSync(), isTrue,
        reason: 'zonder bewaarde sessie toetst het herstel hieronder niets');
  }

  group('een plat netwerk logt je niet uit', () {
    test('de naamopzoeking mislukt — je blijft ingelogd', () async {
      await meldAan();

      // Precies wat de Shield deed: geen adres voor securetoken.googleapis.com.
      final s = sessie(
          ververs: () => throw SocketException(
              'Failed host lookup: securetoken.googleapis.com'));
      await s.restore();

      expect(s.state, CloudState.signedIn,
          reason: 'een wifi die nog niet terug is, is geen uitlogsignaal');
      expect(s.isSignedIn, isTrue);
      expect(s.uid, 'user-1');
      // En de bewaarde sessie staat er nog, dus de volgende start kan het gewoon opnieuw proberen.
      expect(File('${scratch.path}/cloud_session.json').existsSync(), isTrue);
    });

    test('de sleutel wordt geweigerd — dán ben je uit', () async {
      await meldAan();

      final s = sessie(
          ververs: () => http.Response(
              jsonEncode({'error': {'message': 'TOKEN_EXPIRED'}}), 400));
      await s.restore();

      expect(s.state, CloudState.signedOut,
          reason: 'een ingetrokken sleutel is wél een uitlogsignaal');
      expect(s.isSignedIn, isFalse);
    });

    test('zonder bewaarde sessie blijf je gewoon uitgelogd', () async {
      final s = sessie(
          ververs: () => throw SocketException('geen netwerk'));
      await s.restore();
      expect(s.state, CloudState.signedOut,
          reason: 'er valt niets vast te houden als er nooit iemand ingelogd heeft');
    });
  });

  group('een geweigerde sleutel haalt zichzelf een nieuwe', () {
    test('de pc op dit adres kent de toegang toe', () async {
      final s = sessie(ververs: _versGoed);
      await s.signIn('saber@example.test', 'goed');

      await db.seed('users/user-1/servers/pc-1', {
        'name': 'Saber',
        'urls': ['http://192.168.0.117:47820'],
        'online': true,
      });
      // De pc heeft het verzoek al toegekend — dat is wat `awaitAccess` bij de eerste peiling ziet.
      await db.seed('users/user-1/servers/pc-1/grants/shield-1', {
        'status': 'granted',
        'token': 'verse-sleutel-32',
      });

      final sleutel = await s.verseSleutelVoor(Uri.parse('http://192.168.0.117:47820'));
      expect(sleutel, 'verse-sleutel-32');
    });

    test('bij twee pcs telt het adres, en een vreemd adres krijgt niets', () async {
      final s = sessie(ververs: _versGoed);
      await s.signIn('saber@example.test', 'goed');

      await db.seed('users/user-1/servers/pc-1', {
        'name': 'Woonkamer',
        'urls': ['http://192.168.0.117:47820'],
        'online': true,
      });
      await db.seed('users/user-1/servers/pc-2', {
        'name': 'Zolder',
        'urls': ['http://192.168.0.9:47820'],
        'online': true,
      });

      final voor = db.writes.length;
      final sleutel = await s.verseSleutelVoor(Uri.parse('http://10.0.0.5:47820'));

      expect(sleutel, isNull);
      // En er is geen verzoek blijven staan bij een pc waar dit toestel niets te zoeken heeft.
      expect(db.writes.length, voor,
          reason: 'een onbekend adres mag bij géén enkele pc gaan aankloppen');
    });

    test('niet ingelogd vraagt niets', () async {
      final s = sessie(ververs: _versGoed);
      expect(s.state, CloudState.signedOut);
      expect(await s.verseSleutelVoor(Uri.parse('http://192.168.0.117:47820')), isNull);
    });
  });
}
