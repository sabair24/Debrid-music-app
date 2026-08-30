/// Per-device tokens, and the promise that nothing paired today stops working tomorrow.
///
/// Until now every device that ever paired received the same 32 hex characters, so "revoke one
/// device" did not exist — the only lever unpaired them all. These tests are about the replacement
/// and, above all, about the upgrade: the single most damaging thing this change could do is cut
/// off an iPad that was working a minute ago.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_grants_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  group('grants on their own', () {
    test('a minted token is accepted, and only that one', () {
      final store = GrantStore(file: File('${scratch.path}/grants.json'));
      final grant = store.mint(deviceId: 'ipad-1', deviceName: 'iPad van Saber', platform: 'ios');

      expect(grant.token.length, 32);
      expect(store.accepts(grant.token), isTrue);
      expect(store.accepts('${grant.token}x'), isFalse);
      expect(store.accepts(''), isFalse);
      expect(store.accepts(generateDeviceToken()), isFalse);
    });

    test('minting twice for one device does not orphan the first token', () {
      final store = GrantStore(file: File('${scratch.path}/grants.json'));
      final first = store.mint(deviceId: 'mac-1', deviceName: 'Mac');
      final second = store.mint(deviceId: 'mac-1', deviceName: 'Mac');

      // A second token would leave the device holding one the PC no longer lists, which reads as
      // a random logout days later.
      expect(second.token, first.token);
      expect(store.all.length, 1);
    });

    test('revoking one device leaves the others alone', () {
      final store = GrantStore(file: File('${scratch.path}/grants.json'));
      final ipad = store.mint(deviceId: 'ipad-1', deviceName: 'iPad');
      final mac = store.mint(deviceId: 'mac-1', deviceName: 'Mac');

      expect(store.revoke('ipad-1'), isTrue);
      expect(store.accepts(ipad.token), isFalse);
      // This is the thing that could not be done before today.
      expect(store.accepts(mac.token), isTrue);
      expect(store.revoke('ipad-1'), isFalse, reason: 'twee keer intrekken is niet twee keer iets');
    });

    test('grants survive a restart', () async {
      final file = File('${scratch.path}/grants.json');
      final store = GrantStore(file: file);
      final grant = store.mint(deviceId: 'shield-1', deviceName: 'Shield', platform: 'androidtv');
      await store.save();

      final reopened = GrantStore(file: file);
      await reopened.load();
      expect(reopened.accepts(grant.token), isTrue);
      expect(reopened.byDevice('shield-1')?.deviceName, 'Shield');
    });

    test('an unreadable file locks nobody out', () async {
      final file = File('${scratch.path}/grants.json')..writeAsStringSync('{niet eens json');
      final store = GrantStore(file: file);
      await store.load(); // must not throw
      expect(store.isEmpty, isTrue);
    });

    test('last-seen is debounced, because a stream asks on every range request', () {
      final store = GrantStore(file: File('${scratch.path}/grants.json'));
      final grant = store.mint(deviceId: 'mac-1', deviceName: 'Mac');

      expect(store.touch(grant.token), isTrue, reason: 'de eerste keer is nieuw');
      expect(store.touch(grant.token), isFalse, reason: 'binnen een minuut niet opnieuw wegschrijven');
      expect(store.touch('onbekend'), isFalse);
    });
  });

  group('the upgrade must not cut anyone off', () {
    /// A PC exactly as it exists before this change: one shared token, no grants file at all.
    ({LanServer server, Directory root}) legacyPc({GrantStore? grants}) {
      final root = Directory.systemTemp.createTempSync('dm_legacypc_');
      final dir = Directory('${root.path}/Portishead/Dummy')..createSync(recursive: true);
      File('${dir.path}/01.flac').writeAsBytesSync(List<int>.generate(2048, (i) => i % 256));
      final library = LibraryStore()
        ..rootPath = root.path
        ..configDirOverride = root.path;
      library.tracks.add(Track(
        path: '${dir.path}/01.flac',
        title: 'Mysterons',
        artist: 'Portishead',
        album: 'Dummy',
        isFlac: true,
        sizeBytes: 2048,
      ));
      library.rebuildAlbums();
      return (
        server: LanServer(
          library: library,
          token: 'de-oude-gedeelde-token',
          state: LanStateStore(File('${root.path}/state.json')),
          pairing: PairingStore(),
          port: 0,
          grants: grants,
        ),
        root: root,
      );
    }

    test('a device paired before this change still works, with an empty grants file', () async {
      final pc = legacyPc();
      expect(await pc.server.start(), isNull);
      final base = Uri.parse('http://127.0.0.1:${pc.server.boundPort}');

      // THE test. If this ever goes red, shipping the change strands every existing device.
      final res = await http.get(base.replace(path: '/api/catalog'),
          headers: {'Authorization': 'Bearer de-oude-gedeelde-token'});
      expect(res.statusCode, 200);

      // And through the query form, which is what libmpv and the speakers use.
      final stream = await http.get(
          base.replace(path: '/api/catalog', queryParameters: {'token': 'de-oude-gedeelde-token'}));
      expect(stream.statusCode, 200);

      await pc.server.dispose();
      pc.root.deleteSync(recursive: true);
    });

    test('a new grant and the old token work side by side', () async {
      final grants = GrantStore(file: File('${scratch.path}/grants.json'));
      final grant = grants.mint(deviceId: 'ipad-1', deviceName: 'iPad');
      final pc = legacyPc(grants: grants);
      expect(await pc.server.start(), isNull);
      final base = Uri.parse('http://127.0.0.1:${pc.server.boundPort}');

      for (final token in [grant.token, 'de-oude-gedeelde-token']) {
        final res = await http.get(base.replace(path: '/api/catalog'),
            headers: {'Authorization': 'Bearer $token'});
        expect(res.statusCode, 200, reason: 'token $token hoort te werken');
      }

      await pc.server.dispose();
      pc.root.deleteSync(recursive: true);
    });

    test('a revoked device is refused, and can tell that apart from a network failure', () async {
      final grants = GrantStore(file: File('${scratch.path}/grants.json'));
      final grant = grants.mint(deviceId: 'ipad-1', deviceName: 'iPad');
      final pc = legacyPc(grants: grants);
      expect(await pc.server.start(), isNull);
      final base = Uri.parse('http://127.0.0.1:${pc.server.boundPort}');

      grants.revoke('ipad-1');

      final client = RemoteClient(RemoteEndpoint(baseUrl: base, token: grant.token));
      await expectLater(
        client.catalog(),
        throwsA(isA<RemoteException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
      client.close();

      await pc.server.dispose();
      pc.root.deleteSync(recursive: true);
    });

    test('a wrong token is refused whatever it looks like', () async {
      final pc = legacyPc();
      expect(await pc.server.start(), isNull);
      final base = Uri.parse('http://127.0.0.1:${pc.server.boundPort}');

      for (final wrong in ['', 'x', 'de-oude-gedeelde-toke', 'de-oude-gedeelde-tokenn']) {
        final res = await http.get(base.replace(path: '/api/catalog'),
            headers: {'Authorization': 'Bearer $wrong'});
        expect(res.statusCode, 401, reason: 'token "$wrong" hoort geweigerd te worden');
      }

      await pc.server.dispose();
      pc.root.deleteSync(recursive: true);
    });

    test('the legacy token shows up as one revocable row, not as nothing', () {
      final store = GrantStore(file: File('${scratch.path}/grants.json'));
      store.adoptLegacyToken('de-oude-gedeelde-token');

      // Otherwise the device list on the PC would be empty while devices are demonstrably
      // connected, and the only way to cut them off would be the old all-or-nothing lever.
      expect(store.all.single.legacy, isTrue);
      expect(store.accepts('de-oude-gedeelde-token'), isTrue);
      expect(store.revoke('legacy'), isTrue);
      expect(store.accepts('de-oude-gedeelde-token'), isFalse);

      store.adoptLegacyToken('de-oude-gedeelde-token');
      store.adoptLegacyToken('de-oude-gedeelde-token');
      expect(store.all.length, 1, reason: 'twee keer adopteren maakt niet twee rijen');
    });
  });

  group('een server die met een lege administratie opkwam herstelt zichzelf', () {
    // **Waarom deze groep bestaat.** Op 30-08-2026 weigerde de pc élk verzoek — de telefoon 1189
    // keer op één dag — en ook de gedeelde sleutel die gewoon in settings.json stond werd afgewezen.
    // De koppelingen worden één keer ingelezen, bij het opstarten; gaat dat mis of te laat, dan komt
    // een toestel er uit zichzelf nooit meer in. En in `koppeling.log` stond die hele dag geen
    // enkele regel, dus van buiten viel er niets vast te stellen.

    ({LanServer server, Directory root}) pcMetLegeAdministratie(GrantStore leeg) {
      final root = Directory.systemTemp.createTempSync('dm_leegpc_');
      final dir = Directory('${root.path}/Portishead/Dummy')..createSync(recursive: true);
      File('${dir.path}/01.flac').writeAsBytesSync(List<int>.generate(2048, (i) => i % 256));
      final library = LibraryStore()
        ..rootPath = root.path
        ..configDirOverride = root.path;
      library.tracks.add(Track(
        path: '${dir.path}/01.flac',
        title: 'Mysterons',
        artist: 'Portishead',
        album: 'Dummy',
        isFlac: true,
        sizeBytes: 2048,
      ));
      library.rebuildAlbums();
      return (
        server: LanServer(
          library: library,
          // Leeg, zoals wanneer `applySettings` zijn werk niet (op tijd) deed.
          token: '',
          state: LanStateStore(File('${root.path}/state.json')),
          pairing: PairingStore(),
          port: 0,
          grants: leeg,
        ),
        root: root,
      );
    }

    test('DE KERN: een koppeling die op schijf staat maar niet in het geheugen komt er alsnog in',
        () async {
      // Op schijf staat een geldige koppeling...
      final bestand = File('${scratch.path}/grants.json');
      final opSchijf = GrantStore(file: bestand);
      final grant = opSchijf.mint(deviceId: 'gsm-1', deviceName: 'Saber ultra 26', platform: 'android');
      await opSchijf.save();

      // ...maar de server kwam op met een lege administratie.
      final leeg = GrantStore(file: bestand);
      final pc = pcMetLegeAdministratie(leeg);
      expect(leeg.all, isEmpty);
      expect(await pc.server.start(), isNull);
      final adres = 'http://127.0.0.1:${pc.server.boundPort}';

      final r = await http.get(Uri.parse('$adres/api/catalog'),
          headers: {'Authorization': 'Bearer ${grant.token}'});

      expect(r.statusCode, 200,
          reason: 'de koppeling stond op schijf; hem niet lezen mag geen toestel buitensluiten');
      expect(leeg.all, hasLength(1), reason: 'en hij is nu ook echt ingelezen');

      await pc.server.dispose();
      pc.root.deleteSync(recursive: true);
    });

    test('maar een sleutel die nergens staat komt er nog steeds niet in', () async {
      final leeg = GrantStore(file: File('${scratch.path}/leeg.json'));
      final pc = pcMetLegeAdministratie(leeg);
      expect(await pc.server.start(), isNull);

      final r = await http.get(
          Uri.parse('http://127.0.0.1:${pc.server.boundPort}/api/catalog'),
          headers: const {'Authorization': 'Bearer zomaar-iets'});

      expect(r.statusCode, 401);

      await pc.server.dispose();
      pc.root.deleteSync(recursive: true);
    });
  });
}
