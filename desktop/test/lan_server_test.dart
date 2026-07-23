import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/ids.dart';
import 'package:debridmusic/lan/range.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A library backed by real files on disk, so the stream route has something to serve.
({LibraryStore library, Directory root}) _fixture() {
  final root = Directory.systemTemp.createTempSync('debridmusic_lan_');
  final albumDir = Directory('${root.path}/Portishead/Dummy')..createSync(recursive: true);

  final one = File('${albumDir.path}/01 Mysterons.flac')
    ..writeAsBytesSync(List<int>.generate(4096, (i) => i % 256));
  final two = File('${albumDir.path}/02 Sour Times.flac')
    ..writeAsBytesSync(List<int>.generate(2048, (i) => (i * 3) % 256));

  final library = LibraryStore()..rootPath = root.path;
  library.tracks.addAll([
    Track(
      path: one.path,
      title: 'Mysterons',
      artist: 'Portishead',
      album: 'Dummy',
      trackNo: 1,
      duration: const Duration(seconds: 305),
      isFlac: true,
      sizeBytes: 4096,
      sampleRate: 44100,
      bitsPerSample: 16,
    ),
    Track(
      path: two.path,
      title: 'Sour Times',
      artist: 'Portishead',
      album: 'Dummy',
      trackNo: 2,
      duration: const Duration(seconds: 254),
      isFlac: true,
      sizeBytes: 2048,
      sampleRate: 96000,
      bitsPerSample: 24,
    ),
  ]);
  library.rebuildAlbums();
  return (library: library, root: root);
}

void main() {
  group('parseRange', () {
    test('no header means the whole file', () {
      expect(parseRange(null, 1000), isNull);
      expect(parseRange('', 1000), isNull);
    });

    test('a plain range', () {
      expect(parseRange('bytes=0-499', 1000), const ByteRange(0, 499));
      expect(parseRange('bytes=500-999', 1000), const ByteRange(500, 999));
    });

    test('an open-ended range runs to the last byte', () {
      expect(parseRange('bytes=500-', 1000), const ByteRange(500, 999));
    });

    test('a suffix range counts back from the end', () {
      expect(parseRange('bytes=-200', 1000), const ByteRange(800, 999));
      // Asking for more than there is yields the whole file, not an error.
      expect(parseRange('bytes=-5000', 1000), const ByteRange(0, 999));
    });

    test('an end past the file is clamped, not refused', () {
      expect(parseRange('bytes=900-5000', 1000), const ByteRange(900, 999));
    });

    test('a start past the end is 416 territory', () {
      expect(parseRange('bytes=1000-', 1000), rangeNotSatisfiable);
      expect(parseRange('bytes=1500-1600', 1000), rangeNotSatisfiable);
      expect(parseRange('bytes=300-200', 1000), rangeNotSatisfiable);
    });

    test('multipart and nonsense fall back to the whole file', () {
      expect(parseRange('bytes=0-99,200-299', 1000), isNull);
      expect(parseRange('items=0-99', 1000), isNull);
    });
  });

  group('ids', () {
    test('a path keeps its id across scans', () {
      const root = r'D:\Flac music 2024';
      final first = trackIdFor(r'D:\Flac music 2024\Portishead\Dummy\01.flac', root);
      final again = trackIdFor(r'D:\Flac music 2024\Portishead\Dummy\01.flac', root);
      expect(first, again);
    });

    test('ids survive the library moving to another drive', () {
      // The whole reason ids are relative: move the folder and every favourite would otherwise
      // point at a track nobody issues any more.
      final onD = trackIdFor(r'D:\Flac music 2024\Portishead\Dummy\01.flac', r'D:\Flac music 2024');
      final onE = trackIdFor(r'E:\Music\Portishead\Dummy\01.flac', r'E:\Music');
      expect(onD, onE);
    });

    test('separators and case do not change identity', () {
      expect(
        trackIdFor(r'D:\Music\a\b.flac', r'D:\Music'),
        trackIdFor('D:/Music/a/b.flac', 'D:/Music'),
      );
    });

    test('two editions of one record are two albums', () {
      expect(
        albumIdFor('backstreetboys', 'backstreets back', '12 nummers'),
        isNot(albumIdFor('backstreetboys', 'backstreets back', '16 nummers')),
      );
    });
  });

  group('LanServer', () {
    late LibraryStore library;
    late Directory root;
    late LanServer server;
    late String base;
    final client = HttpClient();

    setUp(() async {
      final f = _fixture();
      library = f.library;
      root = f.root;
      // Port 0: the OS picks a free one, so a test run never collides with the real app.
      server = LanServer(
        library: library,
        token: 'test-token',
        state: LanStateStore(File('${root.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        version: '1.2.3',
      );
      expect(await server.start(), isNull);
      base = 'http://127.0.0.1:${server.boundPort}';
    });

    tearDown(() async {
      await server.dispose();
      root.deleteSync(recursive: true);
    });

    Future<HttpClientResponse> get(String path, {String? token, Map<String, String>? headers}) async {
      final req = await client.getUrl(Uri.parse('$base$path'));
      if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      headers?.forEach(req.headers.set);
      return req.close();
    }

    test('/health answers without a token, so a device can find us', () async {
      final res = await get('/health');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      expect(body['status'], 'ok');
      expect(body['version'], '1.2.3');
      expect(body['trackCount'], 2);
    });

    test('everything else needs the token', () async {
      expect((await get('/api/catalog')).statusCode, 401);
      expect((await get('/api/catalog', token: 'wrong')).statusCode, 401);
      expect((await get('/api/catalog', token: 'test-token')).statusCode, 200);
    });

    test('a token in the query works too — renderers cannot set headers', () async {
      expect((await get('/api/catalog?token=test-token')).statusCode, 200);
    });

    test('the catalogue carries the library, in the shape the clients expect', () async {
      final res = await get('/api/catalog', token: 'test-token');
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;

      expect((body['artists'] as List).single['name'], 'Portishead');
      expect((body['albums'] as List).single['title'], 'Dummy');

      final tracks = (body['tracks'] as List).cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['trackNo'] as int).compareTo(b['trackNo'] as int));
      expect(tracks, hasLength(2));
      expect(tracks.first['title'], 'Mysterons');
      expect(tracks.first['lossless'], isTrue);
      expect(tracks.first['sampleRate'], 44100);
      expect(tracks.first['mime'], 'audio/flac');
      // The extension is on the stream path so AVFoundation can type the asset.
      expect(tracks.first['streamPath'], endsWith('.flac'));
      expect(tracks.first['albumId'], (body['albums'] as List).single['id']);
    });

    test('an unchanged library re-syncs for free', () async {
      final first = await get('/api/catalog', token: 'test-token');
      final etag = first.headers.value(HttpHeaders.etagHeader);
      expect(etag, isNotNull);
      await first.drain<void>();

      final second = await get('/api/catalog',
          token: 'test-token', headers: {HttpHeaders.ifNoneMatchHeader: etag!});
      expect(second.statusCode, 304);
      await second.drain<void>();
    });

    test('a changed library issues a new tag', () async {
      final before = await get('/api/catalog', token: 'test-token');
      final etag = before.headers.value(HttpHeaders.etagHeader);
      await before.drain<void>();

      library.tracks.removeLast();
      library.rebuildAlbums();
      library.notifyListeners();

      final after = await get('/api/catalog', token: 'test-token');
      expect(after.headers.value(HttpHeaders.etagHeader), isNot(etag));
      await after.drain<void>();
    });

    test('a whole track streams with the right type', () async {
      final id = await _firstTrackId(get);
      final res = await get('/stream/$id.flac', token: 'test-token');
      expect(res.statusCode, 200);
      expect(res.headers.contentType.toString(), startsWith('audio/flac'));
      expect(res.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect((await _bytes(res)).length, 4096);
    });

    test('a range request gets 206 and exactly those bytes', () async {
      final id = await _firstTrackId(get);
      final res = await get('/stream/$id',
          token: 'test-token', headers: {HttpHeaders.rangeHeader: 'bytes=100-199'});
      expect(res.statusCode, 206);
      expect(res.headers.value(HttpHeaders.contentRangeHeader), 'bytes 100-199/4096');

      final body = await _bytes(res);
      expect(body, hasLength(100));
      // The fixture's bytes are i % 256, so byte 100 must be 100 — proof we seeked, not restarted.
      expect(body.first, 100);
      expect(body.last, 199);
    });

    test('an impossible range is refused, not answered with the whole file', () async {
      final id = await _firstTrackId(get);
      final res = await get('/stream/$id',
          token: 'test-token', headers: {HttpHeaders.rangeHeader: 'bytes=99999-'});
      expect(res.statusCode, 416);
      expect(res.headers.value(HttpHeaders.contentRangeHeader), 'bytes */4096');
      await res.drain<void>();
    });

    test('HEAD tells a renderer the size without sending the track', () async {
      final id = await _firstTrackId(get);
      final req = await client.headUrl(Uri.parse('$base/stream/$id'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer test-token');
      final res = await req.close();
      expect(res.statusCode, 200);
      expect(res.headers.contentLength, 4096);
      expect(await _bytes(res), isEmpty);
    });

    test('a missing track is a 404, not a crash', () async {
      final res = await get('/stream/deadbeefdeadbeefdeadbeef', token: 'test-token');
      expect(res.statusCode, 404);
      await res.drain<void>();
    });

    test('search finds a track by title', () async {
      final res = await get('/api/search?q=sour', token: 'test-token');
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      expect((body['tracks'] as List).single['title'], 'Sour Times');
    });

    test('a playlist made on one device is there for the next', () async {
      final post = await client.postUrl(Uri.parse('$base/api/state/ops'));
      post.headers.set(HttpHeaders.authorizationHeader, 'Bearer test-token');
      post.write(jsonEncode({
        'deviceId': 'ipad',
        'deviceName': 'iPad',
        'ops': [
          {'type': 'playlist.create', 'id': 'p1', 'name': 'Zondag', 'at': 1000},
          {'type': 'playlist.add', 'id': 'p1', 'trackIds': ['t1'], 'at': 1001},
        ],
      }));
      final posted = await post.close();
      expect(posted.statusCode, 200);
      await posted.drain<void>();

      final res = await get('/api/state', token: 'test-token');
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final playlists = (body['playlists'] as List).cast<Map<String, dynamic>>();
      expect(playlists.single['name'], 'Zondag');
      expect(playlists.single['trackIds'], ['t1']);
    });

    test('a device that is already up to date is told so, and still gets the position', () async {
      final first = await get('/api/state', token: 'test-token');
      final body = jsonDecode(await first.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final rev = body['rev'] as int;

      final again = await get('/api/state?since=$rev', token: 'test-token');
      final second = jsonDecode(await again.transform(utf8.decoder).join()) as Map<String, dynamic>;
      expect(second['unchanged'], isTrue);
      expect(second['progress'], isA<Map>());
    });

    test('the event feed pushes a change instead of being polled', () async {
      final req = await client.getUrl(Uri.parse('$base/api/events?token=test-token'));
      final res = await req.close();
      expect(res.headers.contentType!.mimeType, 'text/event-stream');

      final events = <Map<String, dynamic>>[];
      final done = Completer<void>();
      final sub = res.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (!line.startsWith('data: ')) return;
        events.add(jsonDecode(line.substring(6)) as Map<String, dynamic>);
        if (events.length >= 2 && !done.isCompleted) done.complete();
      });

      // The first event is the current state, sent on connect so a client never starts blind.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      server.state.applyOps([
        {'type': 'favorite', 'kind': 'track', 'id': 'abc', 'on': true}
      ], deviceId: 'mac');

      await done.future.timeout(const Duration(seconds: 5));
      expect(events.first['rev'], 0);
      expect(events.last['rev'], 1);
      expect(events.last['from'], 'mac');
      await sub.cancel();
    });

    test('a device with no token trades a code for one', () async {
      final code = server.pairing.start();

      final req = await client.postUrl(Uri.parse('$base/pair'));
      req.write(jsonEncode({'code': code, 'device': 'Shield'}));
      final res = await req.close();
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      expect(body['token'], 'test-token');

      // And that token really does open the door.
      expect((await get('/api/catalog', token: body['token'] as String)).statusCode, 200);
    });

    test('a wrong code gets nothing, and looks the same as no code at all', () async {
      server.pairing.start();
      Future<int> attempt(String code) async {
        final req = await client.postUrl(Uri.parse('$base/pair'));
        req.write(jsonEncode({'code': code}));
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      }

      expect(await attempt('000000'), 403);
      server.pairing.stop();
      expect(await attempt('000000'), 403, reason: 'pairing closed must not be distinguishable');
    });

    test('tracks can be narrowed to one album', () async {
      final catalog = await get('/api/catalog', token: 'test-token');
      final body = jsonDecode(await catalog.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final albumId = (body['albums'] as List).single['id'] as String;

      final res = await get('/api/library/tracks?albumId=$albumId', token: 'test-token');
      final tracks = jsonDecode(await res.transform(utf8.decoder).join()) as List;
      expect(tracks, hasLength(2));
    });
  });
}

Future<String> _firstTrackId(
  Future<HttpClientResponse> Function(String, {String? token, Map<String, String>? headers}) get,
) async {
  final res = await get('/api/catalog', token: 'test-token');
  final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  final tracks = (body['tracks'] as List).cast<Map<String, dynamic>>()
    ..sort((a, b) => (a['trackNo'] as int).compareTo(b['trackNo'] as int));
  return tracks.first['id'] as String;
}

Future<List<int>> _bytes(HttpClientResponse res) async {
  final out = <int>[];
  await for (final chunk in res) {
    out.addAll(chunk);
  }
  return out;
}
