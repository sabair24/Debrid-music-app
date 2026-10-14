import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verplaatsen via een toestel blijft binnen de bibliotheek.
///
/// Tot 14-10-2026 voerde de pc het meegestuurde `to` letterlijk uit: wie een sleutel had, kon een
/// bestand uit de bibliotheek naar elke plek op de pc laten schrijven. Nu rekent de pc het plan
/// zelf opnieuw uit, en wat daar niet exact mee overeenkomt wordt geweigerd met 409.
Track _t(String path, String title, String album) => Track(
      path: path,
      title: title,
      artist: 'Portishead',
      album: album,
      trackNo: 1,
      duration: const Duration(seconds: 200),
      isFlac: true,
      sizeBytes: 512,
      sampleRate: 44100,
      bitsPerSample: 16,
    );

void main() {
  group('approvedAfwijkend', () {
    final t = _t('/m/a/01.flac', 'X', 'A');
    final eigen = {t.path: MovePlan(t, t.path, '/m/b/01.flac', MoveFate.moves)};

    test('precies het eigen plan: niets afwijkend', () {
      expect(approvedAfwijkend([MovePlan(t, t.path, '/m/b/01.flac', MoveFate.moves)], eigen), 0);
    });

    test('een ander doel, een andere uitkomst of een onbekend nummer telt elk', () {
      expect(approvedAfwijkend([MovePlan(t, t.path, '/elders/01.flac', MoveFate.moves)], eigen), 1);
      expect(approvedAfwijkend([MovePlan(t, t.path, '/m/b/01.flac', MoveFate.toDupes)], eigen), 1);
      final ander = _t('/m/c/09.flac', 'Y', 'C');
      expect(approvedAfwijkend([MovePlan(ander, ander.path, '/m/b/09.flac', MoveFate.moves)], eigen), 1);
    });
  });

  group('/api/move/apply', () {
    late Directory pcRoot;
    late Directory buiten;
    late LibraryStore pcLibrary;
    late LanServer server;
    late LibraryStore mac;

    setUp(() async {
      pcRoot = Directory.systemTemp.createTempSync('dm_verplaats_');
      buiten = Directory.systemTemp.createTempSync('dm_buiten_');
      final dummy = Directory('${pcRoot.path}/Portishead/Dummy')..createSync(recursive: true);
      final roseland = Directory('${pcRoot.path}/Portishead/Roseland')..createSync(recursive: true);
      File('${dummy.path}/01.flac').writeAsBytesSync(List<int>.generate(512, (i) => i % 256));
      File('${roseland.path}/01.flac').writeAsBytesSync(List<int>.generate(512, (i) => (i * 7) % 256));
      pcLibrary = LibraryStore()
        ..rootPath = pcRoot.path
        ..configDirOverride = pcRoot.path;
      pcLibrary.tracks.addAll([
        _t('${dummy.path}/01.flac', 'Mysterons', 'Dummy'),
        _t('${roseland.path}/01.flac', 'Sour Times (Live)', 'Roseland'),
      ]);
      pcLibrary.rebuildAlbums();
      server = LanServer(
        library: pcLibrary,
        token: 'sleutel',
        state: LanStateStore(File('${pcRoot.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        settings: AppSettings(),
      );
      expect(await server.start(), isNull);
      mac = LibraryStore()
        ..remote = RemoteClient(RemoteEndpoint(
            baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel'));
      await mac.loadRemote();
    });

    tearDown(() async {
      await server.dispose();
      Object? fout;
      for (final d in [pcRoot, buiten]) {
        try {
          d.deleteSync(recursive: true);
        } catch (e) {
          fout ??= e;
        }
      }
      if (fout != null) throw fout;
    });

    Future<({MovePlan item, Album target, Track track})> plan() async {
      final target = mac.albums.firstWhere((a) => a.title == 'Roseland');
      final track = mac.tracks.firstWhere((t) => t.title == 'Mysterons');
      final p = await mac.planMoveAsync([track], target);
      return (item: p.items.single, target: target, track: track);
    }

    test('een doel buiten de bibliotheek wordt geweigerd en er verhuist niets', () async {
      final p = await plan();
      final kwaad = '${buiten.path}${Platform.pathSeparator}gestolen.flac';
      final vervalst = MovePlan(p.item.track, p.item.from, kwaad, MoveFate.moves);

      Object? fout;
      try {
        await mac.moveTracksToAlbum([p.track], p.target, AppSettings(), plan: [vervalst]);
      } catch (e) {
        fout = e;
      }
      expect(fout, isA<RemoteException>());
      expect((fout as RemoteException).statusCode, 409);
      expect(fout.message, contains('niets verplaatst'));
      expect(File(kwaad).existsSync(), isFalse);
      expect(File('${pcRoot.path}/Portishead/Dummy/01.flac').existsSync(), isTrue);
    });

    test('een andere uitkomst dan de pc zelf zou kiezen wordt ook geweigerd', () async {
      final p = await plan();
      // Wat de pc zelf koos, en dan net de andere uitkomst (hier staat er al een 01.flac in
      // Roseland, dus de pc kiest zelf "naar dubbels").
      final andere = p.item.fate == MoveFate.moves ? MoveFate.toDupes : MoveFate.moves;
      final anders = MovePlan(p.item.track, p.item.from, p.item.to, andere);
      await expectLater(
        mac.moveTracksToAlbum([p.track], p.target, AppSettings(), plan: [anders]),
        throwsA(isA<RemoteException>().having((e) => e.statusCode, 'statusCode', 409)),
      );
      expect(File('${pcRoot.path}/Portishead/Dummy/01.flac').existsSync(), isTrue);
    });

    test('rechtstreeks gepost, zonder app ertussen: zelfde weigering', () async {
      final p = await plan();
      final http = HttpClient();
      try {
        final req = await http.postUrl(Uri.parse('http://127.0.0.1:${server.boundPort}/api/move/apply'));
        req.headers
          ..set(HttpHeaders.authorizationHeader, 'Bearer sleutel')
          ..contentType = ContentType.json;
        req.write(jsonEncode({
          'albumId': mac.remoteAlbumId(p.target),
          'plan': [
            {
              'trackId': (await _trackId(server, p.item.from)),
              'to': '${buiten.path}${Platform.pathSeparator}x.flac',
              'fate': 'moves',
            }
          ],
        }));
        final res = await req.close();
        await res.drain<void>();
        expect(res.statusCode, 409);
      } finally {
        http.close(force: true);
      }
      expect(File('${buiten.path}${Platform.pathSeparator}x.flac').existsSync(), isFalse);
    });

    test('het eerlijke plan verhuist nog gewoon', () async {
      final p = await plan();
      final moved = await mac.moveTracksToAlbum([p.track], p.target, AppSettings(), plan: [p.item]);
      expect(moved, 1);
      expect(File('${pcRoot.path}/Portishead/Dummy/01.flac').existsSync(), isFalse);
      expect(File(p.item.to!).existsSync(), isTrue);
      expect(p.item.to, startsWith(pcRoot.path));
    });
  });
}

/// Het id dat de pc voor dit pad gebruikt, opgevraagd zoals een toestel het ziet.
Future<String> _trackId(LanServer server, String pad) async {
  final id = server.catalog.snapshot().trackById.entries.firstWhere((e) => e.value.path == pad).key;
  return id;
}
