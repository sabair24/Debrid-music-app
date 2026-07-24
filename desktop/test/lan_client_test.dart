/// The promise this whole change is for: on the Mac and the iPad you get the SAME library.
///
/// So these tests do not check a JSON shape. They build a library the way a disk scan leaves it,
/// serve it through the real [LanCatalog], read it back through the real [RemoteClient], and then
/// compare the two [LibraryStore]s album for album — titles, pressings, track order and covers.
/// Anything that would make a Mac show something a Windows PC does not has to fail here.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

/// One track, as the scanner would have produced it.
Track _t(
  String path,
  String title,
  String artist,
  String album, {
  int no = 1,
  int total = 0,
  int seconds = 200,
  int rate = 44100,
  int bits = 16,
  int size = 4096,
  int? year,
  String? genre,
}) =>
    Track(
      path: path,
      title: title,
      artist: artist,
      album: album,
      trackNo: no,
      trackTotal: total,
      duration: Duration(seconds: seconds),
      isFlac: true,
      sizeBytes: size,
      sampleRate: rate,
      bitsPerSample: bits,
      year: year,
      genre: genre,
      addedMs: 1700000000000 + no,
    );

/// A PC that owns the music: a library exactly as [LibraryStore.scan] leaves it.
({LibraryStore library, Directory root}) _pc({bool twoPressings = false}) {
  final root = Directory.systemTemp.createTempSync('dm_client_');
  Directory('${root.path}/Portishead/Dummy').createSync(recursive: true);
  final library = LibraryStore()
    ..rootPath = root.path
    ..configDirOverride = root.path;

  library.tracks.addAll([
    _t('${root.path}/Portishead/Dummy/01.flac', 'Mysterons', 'Portishead', 'Dummy',
        no: 1, total: 11, seconds: 305, year: 1994, genre: 'Trip Hop'),
    _t('${root.path}/Portishead/Dummy/02.flac', 'Sour Times', 'Portishead', 'Dummy',
        no: 2, total: 11, seconds: 254, rate: 96000, bits: 24, year: 1994, genre: 'Trip Hop'),
    // No album tag — a single, which the library groups on its own and must not fold into a
    // record named after the folder it happens to sit in.
    _t('${root.path}/losse/track.flac', 'Teardrop', 'Massive Attack', ''),
  ]);

  if (twoPressings) {
    // The same record twice, with different track counts. That is what makes the library split it
    // into two pressings and label them — and it is exactly the sort of thing that would quietly
    // come out different if the client regrouped from tags instead of adopting what the PC sent.
    Directory('${root.path}/BSB/deluxe').createSync(recursive: true);
    library.tracks.addAll([
      _t('${root.path}/BSB/a1.flac', 'Larger Than Life', 'Backstreet Boys', 'Millennium',
          no: 1, total: 12),
      _t('${root.path}/BSB/deluxe/b1.flac', 'Larger Than Life', 'Backstreet Boys', 'Millennium',
          no: 1, total: 16),
      _t('${root.path}/BSB/deluxe/b2.flac', 'I Want It That Way', 'Backstreet Boys', 'Millennium',
          no: 2, total: 16),
    ]);
  }

  library.rebuildAlbums();
  return (library: library, root: root);
}

/// A client bound to a MockClient that answers out of [pc]'s real catalogue.
({LibraryStore library, RemoteClient client, List<String> requests}) _client(
  LibraryStore pc, {
  Map<String, Uint8List> art = const {},
  int catalogStatus = 200,
}) {
  final catalog = LanCatalog(pc);
  final requests = <String>[];
  final base = Uri.parse('http://192.168.0.216:47820');

  final mock = MockClient((req) async {
    requests.add('${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}');
    if (req.url.path == '/api/catalog') {
      final snap = catalog.snapshot();
      // The real 304 behaviour: the PC answers "nothing changed" when the ETag still matches.
      if (req.headers['If-None-Match'] == snap.etag || catalogStatus == 304) {
        return http.Response('', 304, headers: {'etag': snap.etag});
      }
      return http.Response.bytes(snap.json, 200, headers: {'etag': snap.etag});
    }
    if (req.url.path.startsWith('/art/')) {
      final ref = req.url.pathSegments.last;
      final bytes = art[ref] ?? catalog.artwork(ref);
      if (bytes == null) return http.Response('', 404);
      return http.Response.bytes(bytes, 200);
    }
    return http.Response('', 404);
  });

  final client = RemoteClient(
    RemoteEndpoint(baseUrl: base, token: 'geheim'),
    client: mock,
  );
  final library = LibraryStore()..remote = client;
  return (library: library, client: client, requests: requests);
}

/// What a person actually sees of an album, in a form two libraries can be compared on.
List<String> _shape(LibraryStore s) => [
      for (final a in s.albums)
        [
          a.title,
          a.artist,
          a.edition ?? '-',
          a.isSingle ? 'single' : 'album',
          '${a.year ?? '-'}',
          a.genre ?? '-',
          a.tracks.map((t) => '${t.trackNo}/${t.trackTotal} ${t.title}').join(' | '),
        ].join(' · '),
    ];

void main() {
  late Directory scratch;

  setUp(() {
    // Never the real one: the cover cache and corrections.json live there, and those are months
    // of the user's own edits.
    scratch = Directory.systemTemp.createTempSync('dm_appdir_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  group('the library is the same on both sides', () {
    test('albums, singles, track order and quality come across unchanged', () async {
      final pc = _pc();
      final c = _client(pc.library);

      expect(await c.library.loadRemote(), isTrue);

      expect(_shape(c.library), _shape(pc.library));
      expect(c.library.tracks.length, pc.library.tracks.length);
      expect(c.library.albums.length, pc.library.albums.length);

      // The hi-res badge is read off these two, and getting them wrong is how a 24/96 record
      // silently ends up offered to a Sonos that will skip it.
      final sour = c.library.tracks.firstWhere((t) => t.title == 'Sour Times');
      expect(sour.sampleRate, 96000);
      expect(sour.bitsPerSample, 24);
      expect(sour.isFlac, isTrue);

      // A track with no album tag is its own single on both sides, not a record named after a
      // folder.
      expect(
        c.library.albums.where((a) => a.isSingle).map((a) => a.title),
        pc.library.albums.where((a) => a.isSingle).map((a) => a.title),
      );
    });

    test('two pressings of one record stay two, with the same labels', () async {
      final pc = _pc(twoPressings: true);
      final c = _client(pc.library);
      await c.library.loadRemote();

      final onPc = pc.library.albums.where((a) => a.title == 'Millennium').toList();
      final onMac = c.library.albums.where((a) => a.title == 'Millennium').toList();

      expect(onPc.length, 2, reason: 'de fixture moet de persingen splitsen, anders test dit niets');
      expect(onMac.length, onPc.length);
      expect(
        onMac.map((a) => a.edition).toList(),
        onPc.map((a) => a.edition).toList(),
      );
      expect(onMac.map((a) => a.tracks.length), onPc.map((a) => a.tracks.length));
    });

    test('the artist list uses one spelling, the same one', () async {
      final pc = _pc();
      pc.library.tracks.add(
        _t('${pc.root.path}/Portishead/Dummy/03.flac', 'Roads', 'PORTISHEAD', 'Dummy', no: 3, total: 11),
      );
      pc.library.rebuildAlbums();

      final c = _client(pc.library);
      await c.library.loadRemote();
      expect(c.library.artists, pc.library.artists);
    });

    test('the cover you chose on the PC is the cover on the Mac', () async {
      final pc = _pc();
      final chosen = Uint8List.fromList(List.generate(600, (i) => (i * 7) % 256));
      // Exactly what a hand-picked cover is on the PC: it wins over anything embedded.
      pc.library.albums.firstWhere((a) => a.title == 'Dummy').correctedCover = chosen;

      final c = _client(pc.library);
      await c.library.loadRemote();
      await c.library.loadRemoteCovers(AppSettings());

      expect(c.library.albums.firstWhere((a) => a.title == 'Dummy').cover, chosen);
    });

    test('a cover seen once comes from disk the next time, not over wifi', () async {
      final pc = _pc();
      pc.library.albums.firstWhere((a) => a.title == 'Dummy').embeddedCover =
          Uint8List.fromList(List.generate(600, (i) => i % 256));

      final first = _client(pc.library);
      await first.library.loadRemote();
      await first.library.loadRemoteCovers(AppSettings());
      final ref = first.library
          .remoteAlbumId(first.library.albums.firstWhere((a) => a.title == 'Dummy'))!;
      expect(first.requests.where((r) => r.startsWith('/art/$ref')), isNotEmpty);

      // A second device start, same on-disk cache. The cover has to appear without asking the PC —
      // that is the difference between a grid that fills instantly and one that fills over wifi.
      // Only for the record that HAS one: an album with no cover is asked about again, which is
      // right, because the PC's enricher may have found one since.
      final second = _client(pc.library);
      await second.library.loadRemote();
      await second.library.loadRemoteCovers(AppSettings());
      expect(second.requests.where((r) => r.startsWith('/art/$ref')), isEmpty);
      expect(second.library.albums.firstWhere((a) => a.title == 'Dummy').cover, isNotNull);
    });
  });

  group('playing from a PC', () {
    test('the stored path is the stream URL, without the token in it', () async {
      final pc = _pc();
      final c = _client(pc.library);
      await c.library.loadRemote();

      final t = c.library.tracks.first;
      expect(t.path, startsWith('http://192.168.0.216:47820/stream/'));
      // The path is the key for favourites, playlists and resume. A token baked into it would
      // break all three the moment you paired again — and would sit in a plain file on disk.
      expect(t.path, isNot(contains('geheim')));
      // The extension survives, because that is how a player types the stream.
      expect(t.ext, 'flac');
    });

    test('the token is added at the moment of playing', () async {
      final pc = _pc();
      final c = _client(pc.library);
      await c.library.loadRemote();

      final url = c.client.authorized(c.library.tracks.first.path);
      expect(url, contains('token=geheim'));
      expect(Uri.parse(url).path, startsWith('/stream/'));
    });

    test('someone else\'s URL is left alone', () async {
      final c = _client(_pc().library);
      // A Radio queue mixes library tracks with resolved TorBox streams. Appending our pairing
      // token to a stranger's URL would both fail and hand out the key to the library.
      const foreign = 'https://store.torbox.app/abc/track.flac?x=1';
      expect(c.client.authorized(foreign), foreign);
    });
  });

  group('a device that does not hold the files', () {
    test('editing refuses, and says where to go', () async {
      final pc = _pc();
      final c = _client(pc.library);
      await c.library.loadRemote();
      final album = c.library.albums.first;

      expect(c.library.canEdit, isFalse);
      expect(
        () => c.library.applyCorrection(album, AppSettings(), artist: 'Iets anders'),
        throwsA(isA<RemoteWriteException>()),
      );
      expect(() => c.library.mergeEditions(album), throwsA(isA<RemoteWriteException>()));
      expect(
        () => c.library.removeTracks([album.tracks.first.path], fromDisk: false),
        throwsA(isA<RemoteWriteException>()),
      );
    });

    test('a refused edit changes nothing at all', () async {
      final pc = _pc(twoPressings: true);
      final c = _client(pc.library);
      await c.library.loadRemote();
      final before = _shape(c.library);

      // The danger is not the failure, it is a HALF success: these all end in rebuildAlbums(),
      // which regroups from tags and would throw away the pressings the PC sent.
      try {
        await c.library.mergeEditions(
          c.library.albums.firstWhere((a) => a.title == 'Millennium'),
        );
      } on RemoteWriteException {
        // expected
      }
      expect(_shape(c.library), before);
    });

    test('the PC itself still edits normally', () async {
      final pc = _pc();
      expect(pc.library.canEdit, isTrue);
      expect(pc.library.isRemote, isFalse);
    });
  });

  group('talking to the PC', () {
    test('nothing changed means keep what we have, and do not rebuild', () async {
      final pc = _pc();
      final c = _client(pc.library);

      expect(await c.library.loadRemote(), isTrue);
      final albums = c.library.albums;

      // The second poll sends the ETag and gets a 304. Same objects, not equal ones: rebuilding
      // an identical library would blank every cover and refetch them all.
      expect(await c.library.loadRemote(), isFalse);
      expect(identical(c.library.albums, albums), isTrue);
    });

    test('a PC that has gone away keeps the library on screen', () async {
      final pc = _pc();
      final c = _client(pc.library);
      await c.library.loadRemote();
      final before = _shape(c.library);

      final dead = LibraryStore()
        ..remote = RemoteClient(
          RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.216:47820'), token: 'geheim'),
          client: MockClient((_) async => throw const SocketException('geen netwerk')),
        );
      dead.tracks.addAll(c.library.tracks);
      dead.albums = c.library.albums;

      expect(await dead.loadRemote(), isFalse);
      expect(_shape(dead), before, reason: 'een Mac die de pc kwijtraakt mag het scherm niet leegmaken');
      expect(dead.scanning, isFalse);
    });

    test('an expired pairing says so, distinctly from a network failure', () async {
      final client = RemoteClient(
        RemoteEndpoint(baseUrl: Uri.parse('http://pc:47820'), token: 'oud'),
        client: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(
        client.catalog(),
        throwsA(isA<RemoteException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
    });

    test('the token travels as a bearer header on API calls', () async {
      late String seen;
      final client = RemoteClient(
        RemoteEndpoint(baseUrl: Uri.parse('http://pc:47820'), token: 'geheim'),
        client: MockClient((req) async {
          seen = req.headers['Authorization'] ?? '';
          return http.Response(
            jsonEncode({'artists': [], 'albums': [], 'tracks': [], 'generatedAt': 0}),
            200,
          );
        }),
      );
      await client.catalog();
      expect(seen, 'Bearer geheim');
    });

    test('pairing hands back a usable endpoint, and a wrong code says so plainly', () async {
      final ok = await RemoteClient.pair(
        Uri.parse('http://192.168.0.216:47820'),
        '531610',
        deviceName: 'iPad van Saber',
        client: MockClient((_) async =>
            http.Response(jsonEncode({'token': 'abc123', 'name': 'pc-van-saber'}), 200)),
      );
      expect(ok.token, 'abc123');
      expect(ok.name, 'pc-van-saber');

      await expectLater(
        RemoteClient.pair(
          Uri.parse('http://192.168.0.216:47820'),
          '000000',
          deviceName: 'iPad',
          client: MockClient((_) async => http.Response('', 403)),
        ),
        throwsA(isA<RemoteException>().having((e) => e.message, 'message', contains('code'))),
      );
    });
  });

  group('typing an address', () {
    test('what a person types reaches the PC', () {
      expect(RemoteEndpoint.parseHost('192.168.0.216').toString(),
          'http://192.168.0.216:47820');
      expect(RemoteEndpoint.parseHost('192.168.0.216:1234').toString(),
          'http://192.168.0.216:1234');
      expect(RemoteEndpoint.parseHost(' http://pc-van-saber:47820 ').toString(),
          'http://pc-van-saber:47820');
      expect(RemoteEndpoint.parseHost(''), isNull);
    });

    test('a paired PC survives a restart', () {
      final saved = RemoteEndpoint(
        baseUrl: Uri.parse('http://192.168.0.216:47820'),
        token: 'geheim',
        name: 'pc-van-saber',
      );
      final back = RemoteEndpoint.fromJson(jsonDecode(jsonEncode(saved.toJson())));
      expect(back, saved);
      expect(back!.name, 'pc-van-saber');
      expect(RemoteEndpoint.fromJson({'baseUrl': 'http://pc', 'token': ''}), isNull);
    });
  });
}
