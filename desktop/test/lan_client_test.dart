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
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/remote_services.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
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
({LibraryStore library, RemoteClient client, List<String> requests, List<Map<String, dynamic>> edits}) _client(
  LibraryStore pc, {
  Map<String, Uint8List> art = const {},
  int catalogStatus = 200,
  int editStatus = 200,
}) {
  final catalog = LanCatalog(pc);
  final requests = <String>[];
  final edits = <Map<String, dynamic>>[];
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
    if (req.url.path == '/api/corrections') {
      edits.add(jsonDecode(req.body) as Map<String, dynamic>);
      if (editStatus != 200) {
        return http.Response(jsonEncode({'error': 'de pc wilde niet'}), editStatus);
      }
      return http.Response(jsonEncode({'ok': true}), 200);
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
  return (library: library, client: client, requests: requests, edits: edits);
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
    test('an edit becomes a request to the PC, naming the album by id', () async {
      final pc = _pc();
      final c = _client(pc.library);
      await c.library.loadRemote();
      final album = c.library.albums.firstWhere((a) => a.title == 'Dummy');
      final id = c.library.remoteAlbumId(album);

      expect(c.library.canEdit, isTrue);
      await c.library.applyCorrection(album, AppSettings(), artist: 'Iets anders');
      await c.library.mergeEditions(c.library.albums.firstWhere((a) => a.title == 'Dummy'));

      expect(c.edits.map((e) => e['op']), ['correction', 'merge']);
      // By id, not by title: the library can hold two pressings of one record, and a title would
      // be ambiguous exactly where it matters most.
      expect(c.edits.first['albumId'], id);
      expect(c.edits.first['artist'], 'Iets anders');
    });

    test('removing a track sends the id the PC issued', () async {
      final pc = _pc();
      final c = _client(pc.library);
      await c.library.loadRemote();
      final track = c.library.tracks.firstWhere((t) => t.title == 'Sour Times');

      await c.library.removeTracks([track.path], fromDisk: false);

      final ids = (c.edits.single['trackIds'] as List).cast<String>();
      expect(ids.single, isNotEmpty);
      // The path is a stream URL; the id has to be recovered from it, extension and all.
      expect(track.path, contains(ids.single));
      expect(c.edits.single['fromDisk'], isFalse);
    });

    test('an edit the PC refuses changes nothing here', () async {
      final pc = _pc(twoPressings: true);
      final c = _client(pc.library, editStatus: 500);
      await c.library.loadRemote();
      final before = _shape(c.library);

      // The danger is not the failure, it is a HALF success: a local edit would end in
      // rebuildAlbums(), which regroups from tags and would throw away the pressings the PC sent.
      // Nothing is applied here at all — the PC's answer is the only truth.
      await expectLater(
        c.library.mergeEditions(c.library.albums.firstWhere((a) => a.title == 'Millennium')),
        throwsA(isA<RemoteException>()),
      );
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

  group('editing from a device without the files', _editingTests);

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

/// Editing from a device that holds none of the files.
///
/// Over a real socket against a real [LanServer], because the promise is round-trip: the change
/// lands in the PC's own library and comes back through the catalogue everyone reads — not into
/// some local copy that quietly drifts.
void _editingTests() {
  late Directory scratch;
  late Directory pcRoot;
  late LibraryStore pcLibrary;
  late LanServer server;
  late LibraryStore mac;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_edit_');
    setAppDirForTest(scratch.path);

    pcRoot = Directory.systemTemp.createTempSync('dm_editpc_');
    final dir = Directory('${pcRoot.path}/Portishead/Dummy')..createSync(recursive: true);
    File('${dir.path}/01.flac').writeAsBytesSync(List<int>.generate(2048, (i) => i % 256));
    File('${dir.path}/02.flac').writeAsBytesSync(List<int>.generate(1024, (i) => i % 256));
    pcLibrary = LibraryStore()
      ..rootPath = pcRoot.path
      ..configDirOverride = pcRoot.path;
    pcLibrary.tracks.addAll([
      _t('${dir.path}/01.flac', 'Mysterons', 'Portishead', 'Dummy', no: 1, total: 2),
      _t('${dir.path}/02.flac', 'Sour Times', 'Portishead', 'Dummy', no: 2, total: 2),
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
    // Both, even if the first one throws — otherwise a failure here leaves the second temp folder
    // behind on every run. A failure is still a failure: it is rethrown once both are attempted.
    Object? failure;
    for (final d in [pcRoot, scratch]) {
      try {
        d.deleteSync(recursive: true);
      } catch (e) {
        failure ??= e;
      }
    }
    if (failure != null) throw failure;
  });

  test('a correction typed on the Mac lands on the PC and comes back', () async {
    final album = mac.albums.firstWhere((a) => a.title == 'Dummy');
    await mac.applyCorrection(album, AppSettings(), artist: 'Portishead (UK)');

    // On the PC, where the file is.
    expect(pcLibrary.albums.map((a) => a.artist), contains('Portishead (UK)'));
    // And back on the Mac, through the catalogue rather than by editing a local copy.
    expect(mac.albums.map((a) => a.artist), contains('Portishead (UK)'));
  });

  test('the pressing you pinned travels, so the Mac finds the same disc', () async {
    // The sleeve looks its disc scan up by RELEASE. Without this the Mac searches by artist and
    // title and lands on a different pressing — wrong for exactly the records that were pinned
    // because the automatic guess was wrong. A pin also changes not a single track, so the
    // catalogue fingerprint has to notice it or no device would ever hear about it.
    await mac.applyCorrection(
        mac.albums.firstWhere((a) => a.title == 'Dummy'), AppSettings(), discogsRelease: 987654);
    expect(mac.pinnedRelease(mac.albums.firstWhere((a) => a.title == 'Dummy')), 987654);
  });

  test('a MusicBrainz pin travels too, and clears the Discogs one', () async {
    await mac.applyCorrection(
        mac.albums.firstWhere((a) => a.title == 'Dummy'), AppSettings(), discogsRelease: 987654);
    // The two are alternative authorities: exactly one wins, and the PC decides which. The client
    // has to end up agreeing with it rather than keeping a stale release alongside.
    await mac.applyCorrection(
        mac.albums.firstWhere((a) => a.title == 'Dummy'), AppSettings(), mbid: 'abc-123');

    final after = mac.albums.firstWhere((a) => a.title == 'Dummy');
    expect(mac.pinnedMbid(after), 'abc-123');
    expect(mac.pinnedRelease(after), isNull);
  });

  test('what the PC knows that the tags do not, comes down with the catalogue', () async {
    // Three things that live only in the PC's own files and change not a single track: whether a
    // record was told to keep its pressings together, what it sounds like, and which portrait was
    // picked for the artist. Each one was missing on a client, and each one made a screen there
    // quietly wrong rather than obviously broken.
    final onPc = pcLibrary.albums.firstWhere((a) => a.title == 'Dummy');
    await pcLibrary.mergeEditions(onPc);
    await pcLibrary.rememberStyles('Portishead', 'Dummy', ['Trip Hop', 'Downtempo']);
    await pcLibrary.setArtistArt('Portishead', 'portrait', 'https://example.test/p.jpg');
    pcLibrary.notifyListeners();

    await mac.loadRemote();
    final onMac = mac.albums.firstWhere((a) => a.title == 'Dummy');

    // The merge control read false here and offered to merge a record that already was.
    expect(mac.isMerged(onMac), isTrue);
    // Ontdek is fed by these, and was simply empty.
    expect(mac.stylesOf(onMac), ['Trip Hop', 'Downtempo']);
    // The picture you chose, instead of the app going off and finding its own.
    expect(mac.chosenArtistArt('Portishead', 'portrait'), 'https://example.test/p.jpg');
    expect(mac.chosenArtistArt('Portishead', 'backdrop'), isNull);
  });

  test('unmerging on the PC reaches the Mac as well', () async {
    final onPc = pcLibrary.albums.firstWhere((a) => a.title == 'Dummy');
    await pcLibrary.mergeEditions(onPc);
    pcLibrary.notifyListeners();
    await mac.loadRemote();
    expect(mac.isMerged(mac.albums.firstWhere((a) => a.title == 'Dummy')), isTrue);

    // The fingerprint has to move for this too, or the client keeps answering "merged" for ever.
    await pcLibrary.unmergeEditions(pcLibrary.albums.firstWhere((a) => a.title == 'Dummy'));
    pcLibrary.notifyListeners();
    await mac.loadRemote();
    expect(mac.isMerged(mac.albums.firstWhere((a) => a.title == 'Dummy')), isFalse);
  });

  test('a cover chosen on the Mac is the cover the PC serves', () async {
    final art = Uint8List.fromList(List.generate(900, (i) => (i * 5) % 256));
    final album = mac.albums.firstWhere((a) => a.title == 'Dummy');
    await mac.applyCorrection(album, AppSettings(), coverBytes: art);

    expect(pcLibrary.albums.firstWhere((a) => a.title == 'Dummy').cover, art);
  });

  test('a pinned pressing reaches the PC', () async {
    final album = mac.albums.firstWhere((a) => a.title == 'Dummy');
    await mac.applyCorrection(album, AppSettings(), discogsRelease: 123456);
    expect(pcLibrary.correctionForTest('${pcRoot.path}/Portishead/Dummy/01.flac')?['release'],
        '123456');
  });

  test('merging and splitting editions travel too', () async {
    final album = mac.albums.firstWhere((a) => a.title == 'Dummy');
    await mac.mergeEditions(album);
    expect(pcLibrary.isMerged(pcLibrary.albums.firstWhere((a) => a.title == 'Dummy')), isTrue);

    await mac.unmergeEditions(mac.albums.firstWhere((a) => a.title == 'Dummy'));
    expect(pcLibrary.isMerged(pcLibrary.albums.firstWhere((a) => a.title == 'Dummy')), isFalse);
  });

  test('removing a track removes it on the PC, and the file stays put', () async {
    final track = mac.tracks.firstWhere((t) => t.title == 'Sour Times');
    await mac.removeTracks([track.path], fromDisk: false);

    expect(pcLibrary.tracks.map((t) => t.title), isNot(contains('Sour Times')));
    expect(mac.tracks.map((t) => t.title), isNot(contains('Sour Times')));
    // "Uit bibliotheek" is not "van schijf" — the file is still there.
    expect(File('${pcRoot.path}/Portishead/Dummy/02.flac').existsSync(), isTrue);
  });

  test('an album the PC no longer has says so, rather than editing the wrong one', () async {
    final album = mac.albums.firstWhere((a) => a.title == 'Dummy');
    // The PC moves on: this record is gone by the time the Mac's edit arrives.
    pcLibrary.tracks.clear();
    pcLibrary.rebuildAlbums();
    pcLibrary.notifyListeners();

    await expectLater(
      mac.applyCorrection(album, AppSettings(), artist: 'Iets'),
      throwsA(isA<RemoteException>().having((e) => e.message, 'message', contains('niet (meer)'))),
    );
  });

  test('the move plan comes from the PC, where the files actually are', () async {
    // A second record to move a track into.
    final other = Directory('${pcRoot.path}/Portishead/Roseland')..createSync(recursive: true);
    File('${other.path}/01.flac').writeAsBytesSync(List<int>.generate(512, (i) => i % 256));
    pcLibrary.tracks.add(_t('${other.path}/01.flac', 'Sour Times (Live)', 'Portishead', 'Roseland'));
    pcLibrary.rebuildAlbums();
    pcLibrary.notifyListeners();
    await mac.loadRemote();

    final target = mac.albums.firstWhere((a) => a.title == 'Roseland');
    final track = mac.tracks.firstWhere((t) => t.title == 'Mysterons');
    final plan = await mac.planMoveAsync([track], target);

    // The dialog has to say what will happen to WHICH file. A stream URL would tell nobody that.
    expect(plan.folder, other.path);
    expect(plan.items.single.from, '${pcRoot.path}/Portishead/Dummy/01.flac');
    expect(plan.items.single.to, contains(other.path));
  });

  test('a move approved here happens there', () async {
    final other = Directory('${pcRoot.path}/Portishead/Roseland')..createSync(recursive: true);
    File('${other.path}/01.flac').writeAsBytesSync(List<int>.generate(512, (i) => i % 256));
    pcLibrary.tracks.add(_t('${other.path}/01.flac', 'Sour Times (Live)', 'Portishead', 'Roseland'));
    pcLibrary.rebuildAlbums();
    pcLibrary.notifyListeners();
    await mac.loadRemote();

    final target = mac.albums.firstWhere((a) => a.title == 'Roseland');
    final track = mac.tracks.firstWhere((t) => t.title == 'Mysterons');
    final plan = await mac.planMoveAsync([track], target);

    final moved = await mac.moveTracksToAlbum([track], target, AppSettings(), plan: plan.items);

    expect(moved, 1);
    // The file really moved, on the PC, into the folder the plan named.
    expect(File('${pcRoot.path}/Portishead/Dummy/01.flac').existsSync(), isFalse);
    expect(File(plan.items.single.to!).existsSync(), isTrue);
    // Not asserted here: what the PC's album list looks like afterwards. moveTracksToAlbum ends in
    // a full rescan, and these fixtures are bytes with no tags in them — a real PC reads its real
    // files back. What this test is for is that the move CROSSED, and it did.
  });

  test('a move can leave the files where they are', () async {
    final other = Directory('${pcRoot.path}/Portishead/Roseland')..createSync(recursive: true);
    File('${other.path}/01.flac').writeAsBytesSync(List<int>.generate(512, (i) => i % 256));
    pcLibrary.tracks.add(_t('${other.path}/01.flac', 'Sour Times (Live)', 'Portishead', 'Roseland'));
    pcLibrary.rebuildAlbums();
    pcLibrary.notifyListeners();
    await mac.loadRemote();

    final target = mac.albums.firstWhere((a) => a.title == 'Roseland');
    final track = mac.tracks.firstWhere((t) => t.title == 'Mysterons');
    await mac.moveTracksToAlbum([track], target, AppSettings(), moveFiles: false);

    expect(File('${pcRoot.path}/Portishead/Dummy/01.flac').existsSync(), isTrue,
        reason: 'alleen de groepering verandert, het bestand blijft staan');
  });

  _downloadTests();
}

/// Downloading from a device that holds no files, and the identity that has to travel with it.
///
/// Soulseek supplies audio and nothing else — the numbering, the album, the year and above all the
/// track TOTAL come from whoever asked for the download. On Windows that has been true for a while.
/// Over the LAN it was not: the client took an authority and dropped it, and the PC never asked for
/// one, so a download started on a Mac was filed under the uploader's tags. A wrong track number
/// collides with one the album already uses, and a collision is what the library reads as two
/// pressings — which is how a single album becomes four tiles.
///
/// Nothing covered this. That is why it went unnoticed, so it is covered now.
void _downloadTests() {
  late Directory pcRoot;
  late LanServer server;
  late _RecordingDownloads pc;
  late RemoteDownloadManager mac;

  setUp(() async {
    pcRoot = Directory.systemTemp.createTempSync('dm_dl_');
    final settings = AppSettings();
    final soulseek = SoulseekService(settings);
    pc = _RecordingDownloads(OnlineService(settings), soulseek, pcRoot.path, () async {});
    server = LanServer(
      library: LibraryStore()..rootPath = pcRoot.path,
      token: 'sleutel',
      state: LanStateStore(File('${pcRoot.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      settings: settings,
      downloads: pc,
    );
    expect(await server.start(), isNull);

    final endpoint = RemoteEndpoint(
        baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel');
    mac = RemoteDownloadManager(
        OnlineService(settings), soulseek, pcRoot.path, () async {}, () => endpoint);
  });

  tearDown(() async {
    mac.dispose();
    await server.dispose();
    try {
      pcRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  SoulseekFile file(String name) =>
      SoulseekFile(username: 'peer', filename: r'peer\music\' '$name', size: 4096);

  const authority = TrackTags(
    title: 'Missing You',
    artist: 'Backstreet Boys',
    album: "Backstreet's Back",
    albumArtist: 'Backstreet Boys',
    trackNo: 12,
    trackTotal: 13,
    year: 1997,
  );

  test('the numbering crosses the wire with the download', () async {
    expect(await mac.enqueueSoulseekBest([file('missing you.flac')],
            key: 'own:x:11', authority: authority),
        isTrue);

    final got = pc.lastAuthority;
    expect(got, isNotNull, reason: 'de pc kreeg geen autoriteit — dan tagt de uploader het bestand');
    expect(got!.title, 'Missing You');
    expect(got.artist, 'Backstreet Boys');
    expect(got.album, "Backstreet's Back");
    expect(got.albumArtist, 'Backstreet Boys');
    expect(got.trackNo, 12);
    expect(got.trackTotal, 13, reason: 'het totaal is de tag waar uitgaves op splitsen');
    expect(got.year, 1997);
    expect(pc.lastKey, 'own:x:11');
  });

  test('de pc laat de vrager niet op de download staan wachten', () async {
    // Anders houdt een gsm of iPad per nummer een HTTP-verzoek minutenlang open, en start hij het
    // volgende nummer pas als het vorige binnen is. Gemeten op 07-08-2026: zeven nummers achter
    // elkaar aangevraagd startten twintig tot veertig seconden na elkaar, keurig serieel, terwijl
    // er twaalf tegelijk hadden gekund. De app kon het wel; de vrager stond te wachten.
    await mac.enqueueSoulseekBest([file('b.flac')], key: 'own:x:12');
    expect(pc.lastWacht, isFalse,
        reason: 'de route moet antwoorden zodra de taak is aangenomen, niet als hij klaar is');
  });

  test('and arrives still authoritative — the property that steers where it lands', () async {
    await mac.enqueueSoulseekBest([file('a.flac')], authority: authority);
    // isAuthoritative is derived from trackTotal/year/albumArtist, so losing any of the three in
    // transit silently re-enables the fuzzy comparison placeFileDetailed skips for a known track.
    expect(pc.lastAuthority!.isAuthoritative, isTrue);
  });

  test('a client that sends none still downloads, exactly as before', () async {
    expect(await mac.enqueueSoulseekBest([file('b.flac')], key: 'k'), isTrue);
    expect(pc.calls, 1);
    expect(pc.lastAuthority, isNull);
  });

  test('a whole album is downloaded BY THE PC, with every track named', () async {
    // Soulseek allows one login per account. Run locally this would open a second session on the
    // Mac and fight the PC for it.
    final started = await mac.enqueueSoulseekAlbum(
      [
        [file('01.flac')],
        [file('02.flac')],
      ],
      authorities: [authority, null],
    );

    expect(started, 2);
    expect(pc.albumTracks, hasLength(2));
    expect(pc.albumTracks!.first.single.filename, endsWith('01.flac'));
    expect(pc.albumAuthorities!.first?.trackNo, 12, reason: 'op de juiste index');
    expect(pc.albumAuthorities!.last, isNull, reason: 'en een gat blijft een gat');
  });
}

/// A PC that writes down what it was asked to do instead of doing it.
class _RecordingDownloads extends DownloadManager {
  _RecordingDownloads(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged);

  int calls = 0;
  String? lastKey;
  TrackTags? lastAuthority;
  bool? lastWacht;
  List<List<SoulseekFile>>? albumTracks;
  List<TrackTags?>? albumAuthorities;

  @override
  Future<bool> enqueueSoulseekBest(List<SoulseekFile> candidates,
      {String? key, TrackTags? authority, SoulseekFile? exact, bool wachtOpAfloop = true}) async {
    calls++;
    lastKey = key;
    lastAuthority = authority;
    lastWacht = wachtOpAfloop;
    return true;
  }

  @override
  Future<int> enqueueSoulseekAlbum(List<List<SoulseekFile>> tracks,
      {List<TrackTags?> authorities = const []}) async {
    albumTracks = tracks;
    albumAuthorities = authorities;
    return tracks.length;
  }
}
