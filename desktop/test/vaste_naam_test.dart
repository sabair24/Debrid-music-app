import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/vaste_naam.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/offline.dart';
import 'package:debridmusic/paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Een nummer van de pc heet op een toestel overal hetzelfde, welk adres je ook gebruikt.
/// Stap 3 van "verbinden zoals Roon ARC" (14-10-2026); zie `lan/vaste_naam.dart`.
void main() {
  group('normaliseerPcPad', () {
    test('een oud pad met het adres van de pc wordt de vaste naam', () {
      for (final oud in [
        'http://192.168.0.117:47820/stream/abc123.flac',
        'http://100.97.101.113:47820/stream/abc123.flac',
        'http://127.0.0.1:51234/stream/abc123.flac',
        'http://saber-pc:47820/stream/abc123.flac',
      ]) {
        expect(normaliseerPcPad(oud), 'http://pc.invalid/stream/abc123.flac', reason: oud);
      }
    });

    test('al de rest blijft zoals het is', () {
      for (final ander in [
        r'D:\Muziek\Portishead\Dummy\01.flac',
        'http://icecast.omroep.nl/stream/radio1.mp3', // een radio op poort 80
        'https://xyz.tb-cdn.st/dld/abc/1.flac',
        'http://192.168.0.117:47820/art/abc', // geen stream
        'http://192.168.0.117:47820/stream/a/b.flac', // dieper
        'http://pc.invalid/stream/abc.flac', // al vast
      ]) {
        expect(normaliseerPcPad(ander), ander, reason: ander);
      }
    });
  });

  group('authorized: de vaste naam wordt het adres van nu', () {
    final client = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://100.97.101.113:47820'), token: 'sleutel'));
    test('de vaste naam', () {
      expect(client.authorized('http://pc.invalid/stream/abc.flac'),
          'http://100.97.101.113:47820/stream/abc.flac?token=sleutel');
    });
    test('een ander adres krijgt nooit onze sleutel', () {
      expect(client.authorized('https://xyz.tb-cdn.st/dld/1.flac'), 'https://xyz.tb-cdn.st/dld/1.flac');
      expect(client.authorized('http://192.168.0.9:47820/stream/abc.flac'), 'http://192.168.0.9:47820/stream/abc.flac',
          reason: 'een oud adres van een ándere verbinding is niet dit adres');
    });
    tearDownAll(client.close);
  });

  group('op een toestel', () {
    late Directory pcRoot;
    late LanServer server;

    setUp(() async {
      pcRoot = Directory.systemTemp.createTempSync('dm_vastenaam_');
      final dir = Directory('${pcRoot.path}/Portishead/Dummy')..createSync(recursive: true);
      File('${dir.path}/01.flac').writeAsBytesSync(List<int>.generate(4096, (i) => i % 256));
      final pc = LibraryStore()
        ..rootPath = pcRoot.path
        ..configDirOverride = pcRoot.path;
      pc.tracks.add(Track(
        path: '${dir.path}/01.flac',
        title: 'Mysterons',
        artist: 'Portishead',
        album: 'Dummy',
        trackNo: 1,
        duration: const Duration(seconds: 200),
        isFlac: true,
        sizeBytes: 4096,
      ));
      pc.rebuildAlbums();
      server = LanServer(
        library: pc,
        token: 'sleutel',
        state: LanStateStore(File('${pcRoot.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await server.start(), isNull);
    });

    tearDown(() async {
      await server.dispose();
      try {
        pcRoot.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<LibraryStore> via(String host) async {
      final mac = LibraryStore()
        ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://$host:${server.boundPort}'), token: 'sleutel'));
      expect(await mac.loadRemote(), isTrue);
      return mac;
    }

    test('een nummer heet hetzelfde langs elk adres van de pc', () async {
      final thuis = await via('127.0.0.1');
      final anders = await via('localhost');
      expect(thuis.tracks.single.path, startsWith('http://pc.invalid/stream/'));
      expect(anders.tracks.single.path, thuis.tracks.single.path,
          reason: 'anders vinden offline kopie en wachtrij hun nummer niet terug na een adreswissel');
    });

    test('een bewaarde wachtrij met het oude adres vindt zijn nummer terug', () async {
      final mac = await via('127.0.0.1');
      final id = mac.remoteTrackId(mac.tracks.single.path);
      final oud = 'http://192.168.0.117:47820/stream/$id.flac';
      expect(mac.trackByPath(oud)?.title, 'Mysterons');
    });

    test('het nummer speelt nog gewoon: de vaste naam wordt het adres van deze verbinding', () async {
      final mac = await via('127.0.0.1');
      final client = mac.remote!;
      final url = client.authorized(mac.tracks.single.path);
      expect(url, contains('127.0.0.1:${server.boundPort}'));
      final http = HttpClient();
      try {
        final res = await (await http.getUrl(Uri.parse(url))).close();
        expect(res.statusCode, 200);
        expect((await res.fold<List<int>>([], (a, b) => a..addAll(b))).length, 4096);
      } finally {
        http.close(force: true);
      }
    });
  });

  group('offline: het adres bij de poging, niet bij het vragen', () {
    late Directory scratch;
    late HttpServer bron;
    setUp(() async {
      scratch = Directory.systemTemp.createTempSync('dm_vastenaam_off_');
      setAppDirForTest(scratch.path);
      bron = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      bron.listen((req) {
        req.response
          ..headers.contentLength = 1000
          ..add(List<int>.filled(1000, 7));
        req.response.close();
      });
    });
    tearDown(() async {
      await bron.close(force: true);
      try {
        scratch.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('zonder verbinding mislukt het met die reden; met een nieuw adres lukt het daarna', () async {
      final store = OfflineStore();
      await store.load();
      const pad = 'http://pc.invalid/stream/abc.flac';
      String? adres;
      store.adresVoor = (_) => adres;
      store.bewaarAlles([const OfflineRequest(libraryPath: pad, title: 't', artist: 'a', album: 'b')]);
      for (var i = 0; i < 100 && store.mislukt == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.foutVoor(pad), contains('geen verbinding met de pc'));

      // Onderweg: een ander adres van dezelfde pc. Opnieuw proberen pakt dát, niet het oude.
      adres = 'http://127.0.0.1:${bron.port}/stream/abc.flac?token=x';
      store.opnieuw(pad);
      for (var i = 0; i < 200 && !store.has(pad); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.has(pad), isTrue);
      store.dispose();
    });

    test('een vaste naam die niet vertaald werd (geen pc), wordt niet opgevraagd', () async {
      final gevraagd = <Uri>[];
      final store = OfflineStore(
          client: MockClient((r) async {
        gevraagd.add(r.url);
        return http.Response('', 500);
      }));
      addTearDown(() => expect(gevraagd, isEmpty, reason: 'pc.invalid hoort nooit het netwerk op te gaan'));
      await store.load();
      const pad = 'http://pc.invalid/stream/xyz.flac';
      // Zoals `authorized` zonder verbinding: hij geeft de naam ongewijzigd terug.
      store.adresVoor = (p) => p;
      store.bewaarAlles([const OfflineRequest(libraryPath: pad, title: 't', artist: 'a', album: 'b')]);
      for (var i = 0; i < 100 && store.mislukt == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.foutVoor(pad), contains('geen verbinding met de pc'));
      store.dispose();
    });

    test('een offline-index van vóór deze versie, met het adres in het pad, blijft werken', () async {
      final bestand = File('${scratch.path}/kopie.flac')..writeAsBytesSync([1, 2, 3]);
      File('${scratch.path}/offline.json').writeAsStringSync(jsonEncode([
        {
          'path': 'http://192.168.0.117:47820/stream/abc.flac',
          'file': bestand.path,
          'bytes': 3,
          'title': 't',
          'artist': 'a',
          'album': 'b',
          'savedAt': '2026-10-01T10:00:00Z',
        }
      ]));
      final store = OfflineStore();
      await store.load();
      expect(store.localFor('http://pc.invalid/stream/abc.flac'), bestand.path);
      store.dispose();
    });
  });
}
