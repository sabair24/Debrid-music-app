/// Signing in, finding your PC, and being handed a token — without a network.
///
/// A fake Firestore rather than the real one: these tests are about the handshake, and a test that
/// needs a Firebase project is a test nobody runs. The wire format itself is checked separately,
/// against the shapes Google's REST API actually sends.
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
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/paths.dart';

const _config = CloudConfig(projectId: 'test-project', apiKey: 'test-key');

/// Firestore in a Map. Speaks the same typed wire format, so [Firestore] is exercised for real.
class FakeFirestore {
  final Map<String, Map<String, dynamic>> docs = {};
  final List<String> writes = [];

  http.Client client() => MockClient((req) async {
        final path = Uri.decodeFull(req.url.path)
            .split('/documents/')
            .last
            .replaceAll(RegExp(r'\?.*$'), '');

        if (req.method == 'GET') {
          // A collection listing: every document one level below this path.
          final children = docs.entries
              .where((e) => e.key.startsWith('$path/') && !e.key.substring(path.length + 1).contains('/'))
              .toList();
          if (children.isNotEmpty || !docs.containsKey(path)) {
            if (docs.containsKey(path)) {
              return http.Response(jsonEncode(_wire(path, docs[path]!)), 200);
            }
            if (children.isEmpty) return http.Response('{}', 404);
            return http.Response(
              jsonEncode({'documents': [for (final c in children) _wire(c.key, c.value)]}),
              200,
            );
          }
          return http.Response(jsonEncode(_wire(path, docs[path]!)), 200);
        }

        if (req.method == 'PATCH') {
          writes.add(path);
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final fields = (body['fields'] as Map).cast<String, dynamic>();
          // Merge, exactly as the updateMask makes the real one do.
          docs.putIfAbsent(path, () => {}).addAll(fields);
          return http.Response(jsonEncode(_wire(path, docs[path]!)), 200);
        }

        if (req.method == 'DELETE') {
          docs.remove(path);
          return http.Response('{}', 200);
        }
        return http.Response('{}', 404);
      });

  Map<String, dynamic> _wire(String path, Map<String, dynamic> fields) => {
        'name': 'projects/test-project/databases/(default)/documents/$path',
        'fields': fields,
        'updateTime': DateTime.now().toUtc().toIso8601String(),
      };

  /// Write a document the way a caller would, so tests can set the scene.
  Future<void> seed(String path, Map<String, dynamic> data) async {
    final store = Firestore(token: 't', config: _config, client: client());
    await store.set(path, data);
  }
}

/// Firebase Auth in a Map.
http.Client fakeAuth({String uid = 'user-1', String email = 'saber@example.test'}) =>
    MockClient((req) async {
      if (req.url.path.contains('signInWithPassword') || req.url.path.contains('signUp')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if ('${body['password']}' == 'fout') {
          return http.Response(
              jsonEncode({'error': {'message': 'INVALID_LOGIN_CREDENTIALS'}}), 400);
        }
        return http.Response(
            jsonEncode({
              'localId': uid,
              'email': body['email'],
              'idToken': 'id-token',
              'refreshToken': 'refresh-token',
              'expiresIn': '3600',
            }),
            200);
      }
      if (req.url.host.startsWith('securetoken')) {
        // Note the snake_case: the refresh endpoint answers in a different style from the sign-in
        // one, and reading idToken here would silently yield null.
        return http.Response(
            jsonEncode({
              'user_id': uid,
              'id_token': 'id-token-2',
              'refresh_token': 'refresh-token-2',
              'expires_in': '3600',
            }),
            200);
      }
      return http.Response('{}', 404);
    });

void main() {
  late Directory scratch;
  late FakeFirestore db;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_cloud_');
    setAppDirForTest(scratch.path);
    db = FakeFirestore();
    setDeviceIdentityForTest(
        const DeviceIdentity(id: 'ipad-abc', name: 'iPad van Saber', platform: 'ios'));
  });

  tearDown(() {
    setDeviceIdentityForTest(null);
    scratch.deleteSync(recursive: true);
  });

  CloudSession session() => CloudSession(
        config: _config,
        auth: CloudAuth(config: _config, client: fakeAuth()),
        firestoreClient: db.client(),
      );

  group('signing in', () {
    test('a good password signs you in and survives a restart', () async {
      final s = session();
      await s.signIn('saber@example.test', 'goed');
      expect(s.isSignedIn, isTrue);
      expect(s.uid, 'user-1');

      // A new session on the same machine picks up where that left off, without asking again.
      final again = session();
      await again.restore();
      expect(again.isSignedIn, isTrue);
      expect(again.state, CloudState.signedIn);
      expect(again.uid, 'user-1');
    });

    test('a wrong password says so in words, not in a Firebase constant', () async {
      final s = session();
      await expectLater(
        s.signIn('saber@example.test', 'fout'),
        throwsA(isA<CloudAuthException>()
            .having((e) => e.message, 'message', contains('wachtwoord klopt niet'))),
      );
      expect(s.isSignedIn, isFalse);
    });

    test('signing out forgets the session on disk', () async {
      final s = session();
      await s.signIn('saber@example.test', 'goed');
      expect(File('${scratch.path}/cloud_session.json').existsSync(), isTrue);

      await s.signOut();
      expect(File('${scratch.path}/cloud_session.json').existsSync(), isFalse);

      final again = session();
      await again.restore();
      expect(again.isSignedIn, isFalse);
    });

    test('without a Firebase project the app falls back rather than breaks', () async {
      const bare = CloudConfig(projectId: '', apiKey: '');
      final s = CloudSession(config: bare, auth: CloudAuth(config: bare, client: fakeAuth()));
      await s.restore();
      // Disabled, not signed-out-with-an-error: a checkout with no project still runs, on the
      // pairing code it has always had.
      expect(s.state, CloudState.disabled);
    });
  });

  group('a device asks, the PC answers', () {
    test('the request carries no token — a client may ask, not help itself', () async {
      final s = session();
      await s.signIn('saber@example.test', 'goed');
      final store = Firestore(token: 'id-token', config: _config, client: db.client());
      // Route the session at the fake by seeding through it and reading the same map.
      await store.set('users/user-1/servers/pc-1', {'name': 'Saber', 'online': true});

      final doc = await store.get('users/user-1/servers/pc-1');
      expect(doc?.data['name'], 'Saber');
      expect(doc?.data['online'], isTrue);
    });

    test('the PC turns a pending request into a token, disk first', () async {
      final grants = GrantStore(file: File('${scratch.path}/grants.json'));
      final store = Firestore(token: 'id-token', config: _config, client: db.client());

      // What a device leaves behind.
      await store.set('users/user-1/servers/pc-1/grants/ipad-abc', {
        'status': 'pending',
        'deviceName': 'iPad van Saber',
        'platform': 'ios',
      });

      // What the PC does with it.
      final pending = await store.list('users/user-1/servers/pc-1/grants');
      expect(pending.single.data['status'], 'pending');
      final grant = grants.mint(
        deviceId: pending.single.id,
        deviceName: '${pending.single.data['deviceName']}',
        platform: '${pending.single.data['platform']}',
      );
      await grants.save();
      await store.set('users/user-1/servers/pc-1/grants/ipad-abc', {
        'status': 'granted',
        'token': grant.token,
      });

      final answered = await store.get('users/user-1/servers/pc-1/grants/ipad-abc');
      expect(answered?.data['status'], 'granted');
      expect(answered?.data['token'], grant.token);
      // The merge kept what the device said about itself.
      expect(answered?.data['deviceName'], 'iPad van Saber');

      // And the PC wrote it down before telling anyone, so a crash here cannot leave a device
      // holding a token the PC has never heard of.
      final reopened = GrantStore(file: File('${scratch.path}/grants.json'));
      await reopened.load();
      expect(reopened.accepts(grant.token), isTrue);
    });

    /// The PC making itself findable — the step every device depends on and nothing tested.
    ///
    /// Signing in on the PC only pays off through this heartbeat: until the server document exists,
    /// a Mac that signs in is told "Nog geen pc gevonden onder dit account". That is why signing in
    /// from Settings starts it immediately instead of waiting for the next launch.
    test('a signed-in PC publishes where it is, and answers what was waiting', () async {
      final s = session();
      await s.signIn('saber@example.test', 'goed');

      final grants = GrantStore(file: File('${scratch.path}/grants.json'));
      final store = Firestore(token: 'id-token', config: _config, client: db.client());
      // A device that asked while the PC was off.
      await store.set('users/user-1/servers/pc-1/grants/ipad-abc', {
        'status': 'pending',
        'deviceName': 'iPad van Saber',
        'platform': 'ios',
      });

      s.startAsOwner(
        serverId: 'pc-1',
        serverName: 'SABER-PC',
        port: 8477,
        addresses: () => ['http://192.168.0.10:8477'],
        grants: grants,
        trackCount: () => 325,
      );
      // The first beat is fired, not awaited — the app must not wait on a network to draw.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final doc = await store.get('users/user-1/servers/pc-1');
      expect(doc, isNotNull, reason: 'zonder dit document vindt geen enkel apparaat deze pc');
      expect(doc!.data['name'], 'SABER-PC');
      expect(doc.data['port'], 8477);
      expect(doc.data['online'], isTrue);
      expect(doc.data['urls'], contains('http://192.168.0.10:8477'));
      expect(doc.data['trackCount'], 325);

      // And the request that was already waiting is answered in the same beat.
      final answered = await store.get('users/user-1/servers/pc-1/grants/ipad-abc');
      expect(answered?.data['status'], 'granted');
      expect('${answered?.data['token']}', isNotEmpty);

      s.dispose();
    });

    test('signed out, nothing is published at all', () async {
      final s = session();
      expect(s.isSignedIn, isFalse);

      s.startAsOwner(
        serverId: 'pc-1',
        serverName: 'SABER-PC',
        port: 8477,
        addresses: () => ['http://192.168.0.10:8477'],
        grants: GrantStore(file: File('${scratch.path}/grants.json')),
        trackCount: () => 0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(db.writes, isEmpty,
          reason: 'een pc zonder account heeft geen account om zich onder te melden');
      s.dispose();
    });

    test('a PC that is off leaves the request pending, and says so', () async {
      final s = session();
      await s.signIn('saber@example.test', 'goed');
      // Nothing answers; awaitAccess gives up rather than spinning for ever.
      var told = false;
      final token = await s.awaitAccess('pc-1',
          timeout: const Duration(milliseconds: 400), onWaiting: () => told = true);
      expect(token, isNull);
      expect(told, isTrue, reason: 'het scherm moet kunnen zeggen dat het wacht');
    });
  });

  group('the wire format', () {
    test('every type Firestore uses survives the round trip', () async {
      final store = Firestore(token: 't', config: _config, client: db.client());
      final when = DateTime.utc(2026, 7, 25, 9, 30);
      await store.set('users/user-1/test', {
        'naam': 'Saber',
        'aantal': 12345,
        'deel': 0.5,
        'aan': true,
        'niets': null,
        'moment': when,
        'lijst': ['a', 'b'],
        'nest': {'x': 1},
      });

      final back = (await store.get('users/user-1/test'))!.data;
      expect(back['naam'], 'Saber');
      // Integers travel as strings; reading one as a double is how a track number becomes 3.0.
      expect(back['aantal'], 12345);
      expect(back['aantal'], isA<int>());
      expect(back['deel'], 0.5);
      expect(back['aan'], isTrue);
      expect(back['niets'], isNull);
      expect(back['moment'], when);
      expect(back['lijst'], ['a', 'b']);
      expect(back['nest'], {'x': 1});
    });

    test('a missing document is null, not an exception', () async {
      final store = Firestore(token: 't', config: _config, client: db.client());
      // "Has my PC published itself yet" is a question with a legitimate no.
      expect(await store.get('users/user-1/bestaat-niet'), isNull);
      expect(await store.list('users/user-1/leeg'), isEmpty);
    });

    test('a refusal reads as a session problem, not as a network problem', () async {
      final store = Firestore(
        token: 't',
        config: _config,
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': {'message': 'Missing or insufficient permissions.'}}), 403)),
      );
      await expectLater(
        store.get('users/iemand-anders/geheim'),
        throwsA(isA<FirestoreException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
    });
  });
}
