/// The PC answering "what IS this record" for every other device.
///
/// Before this, a phone, an iPad and the television each ran their own MusicBrainz search on every
/// album open — three independent six-request chains against one anonymous per-second budget, each
/// with a private cache that helped nobody else. The whole point of the endpoint is that the answer
/// is worked out once, on the machine that holds the music, and handed round.
///
/// Against a real socket, because the shapes on the wire are the contract.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

void main() {
  late Directory root;
  late LibraryStore library;
  late LanServer server;
  late String base;
  late String albumId;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dm_lanfacts_');
    setAppDirForTest(root.path);
    final albumDir = Directory('${root.path}/Portishead/Dummy')..createSync(recursive: true);

    library = LibraryStore()
      ..configDirOverride = root.path
      ..rootPath = root.path;
    library.tracks.addAll([
      for (var i = 1; i <= 2; i++)
        Track(
          path: '${albumDir.path}/0$i.flac',
          title: i == 1 ? 'Mysterons' : 'Sour Times',
          artist: 'Portishead',
          album: 'Dummy',
          trackNo: i,
          isFlac: true,
        ),
    ]);
    library.rebuildAlbums();

    server = LanServer(
      library: library,
      token: 'test-token',
      state: LanStateStore(File('${root.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      version: '1.6.1',
      // No MusicBrainz: this test is about what happens with the answers, not about fetching them.
      // Leaving it out also proves the absence is a slower client, not a broken one.
    );
    expect(await server.start(), isNull);
    base = 'http://127.0.0.1:${server.boundPort}';
    albumId = LanCatalog(library).snapshot().catalog.albums.single.id;
  });

  tearDown(() async {
    await server.dispose();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<HttpClientResponse> get(String path, {String? etag}) async {
    final c = HttpClient();
    try {
      final req = await c.getUrl(Uri.parse('$base$path'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer test-token');
      if (etag != null) req.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      return await req.close();
    } finally {
      c.close();
    }
  }

  /// Put an answer in, as the PC's own album page would have.
  AlbumFacts seed() {
    final album = library.albums.single;
    final f = AlbumFacts(
      uid: library.uidOf(album),
      trackSetHash: library.trackSetHashFor(album),
      updatedMs: 1730000000000,
      source: 'MusicBrainz',
      mbid: 'e5f6-abc',
      tracklist: const [
        ChoiceTrack('1', 'Mysterons', 306),
        ChoiceTrack('2', 'Sour Times', 254),
        ChoiceTrack('3', 'Strangers', 238),
      ],
      year: 1994,
    );
    library.facts.put(f);
    return f;
  }

  group('a device asking what a record is', () {
    test('gets the tracklist the PC worked out', () async {
      seed();
      final res = await get('/api/album/facts?albumId=$albumId');
      expect(res.statusCode, 200);
      final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>;

      expect(body['mbid'], 'e5f6-abc');
      expect(body['year'], 1994);
      expect((body['tracks'] as List).length, 3,
          reason: 'ook het nummer dat je NIET hebt — dat is het hele punt van de lijst');
      expect((body['tracks'] as List).last['t'], 'Strangers');
    });

    test('and the client turns it back into the same thing', () async {
      seed();
      final client = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse(base), token: 'test-token'));
      final f = await client.albumFacts(albumId);

      expect(f, isNotNull);
      expect(f!.tracklist.map((t) => t.title), ['Mysterons', 'Sour Times', 'Strangers']);
      expect(f.mbid, 'e5f6-abc');
      expect(f.source, 'MusicBrainz');
    });

    test('a second ask costs a 304, not the tracklist again', () async {
      seed();
      final first = await get('/api/album/facts?albumId=$albumId');
      final etag = first.headers.value(HttpHeaders.etagHeader);
      await first.drain<void>();
      expect(etag, isNotNull);

      final again = await get('/api/album/facts?albumId=$albumId', etag: etag);
      expect(again.statusCode, 304);
      await again.drain<void>();
    });

    test('an album nobody has looked at yet is a 404, not a hang', () async {
      // No MusicBrainz on this server, so it has nothing to say and must say so quickly.
      final res = await get('/api/album/facts?albumId=$albumId');
      expect(res.statusCode, 404);
      await res.drain<void>();
    });

    test('an album that does not exist is a 404', () async {
      final res = await get('/api/album/facts?albumId=nonsense');
      expect(res.statusCode, 404);
      await res.drain<void>();
    });

    test('without a token it is refused like everything else', () async {
      seed();
      final c = HttpClient();
      final res = await (await c.getUrl(Uri.parse('$base/api/album/facts?albumId=$albumId'))).close();
      expect(res.statusCode, 401);
      await res.drain<void>();
      c.close();
    });
  });

  group('the client keeps what it was told', () {
    test('so opening the same album twice asks the PC once', () async {
      seed();
      // What the client does with the answer: files it under the album id, which is its uid on
      // this side. The second visit is then a map lookup and no request at all.
      final client = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse(base), token: 'test-token'));
      final f = await client.albumFacts(albumId);

      final store = AlbumFactsStore(dir: () => '${root.path}/client');
      store.put(AlbumFacts(
        uid: albumId,
        trackSetHash: 'client-hash',
        updatedMs: f!.updatedMs,
        source: f.source,
        mbid: f.mbid,
        tracklist: f.tracklist,
        year: f.year,
      ));

      expect(
          needsResolve(store.get(albumId),
              trackSetHash: 'client-hash', nowMs: DateTime.now().millisecondsSinceEpoch),
          isFalse);
      store.dispose();
    });
  });
}
