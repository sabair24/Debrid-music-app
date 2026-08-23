/// End to end over a real socket: a real [LanServer] on one side, the pairing screen's own code
/// path on the other, and a FLAC actually fetched at the end of it.
///
/// The rest of the client is tested against a stub. This one is not: pairing, the token, the
/// catalogue and the stream all have to line up across a genuine HTTP connection, and every one of
/// those has been where a mistake hid — a header a renderer cannot set, a body Dart sent chunked,
/// a port already taken.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/client_mode.dart';
import 'package:debridmusic/lan/client_session.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

/// A PC with two real files on disk, so /stream serves something with bytes in it.
({LibraryStore library, Directory root}) _pc() {
  final root = Directory.systemTemp.createTempSync('dm_e2e_');
  final dir = Directory('${root.path}/Portishead/Dummy')..createSync(recursive: true);
  final one = File('${dir.path}/01 Mysterons.flac')
    ..writeAsBytesSync(List<int>.generate(4096, (i) => i % 256));
  final two = File('${dir.path}/02 Sour Times.flac')
    ..writeAsBytesSync(List<int>.generate(2048, (i) => (i * 3) % 256));

  final library = LibraryStore()
    ..rootPath = root.path
    ..configDirOverride = root.path;
  library.tracks.addAll([
    Track(
      path: one.path,
      title: 'Mysterons',
      artist: 'Portishead',
      album: 'Dummy',
      trackNo: 1,
      trackTotal: 11,
      duration: const Duration(seconds: 305),
      isFlac: true,
      sizeBytes: 4096,
      sampleRate: 44100,
      bitsPerSample: 16,
      year: 1994,
    ),
    Track(
      path: two.path,
      title: 'Sour Times',
      artist: 'Portishead',
      album: 'Dummy',
      trackNo: 2,
      trackTotal: 11,
      duration: const Duration(seconds: 254),
      isFlac: true,
      sizeBytes: 2048,
      sampleRate: 96000,
      bitsPerSample: 24,
      year: 1994,
    ),
  ]);
  library.rebuildAlbums();
  return (library: library, root: root);
}

void main() {
  late Directory scratch;
  late LibraryStore pcLibrary;
  late Directory pcRoot;
  late LanServer server;
  late PairingStore pairing;
  late Uri base;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_appdir_');
    setAppDirForTest(scratch.path);

    final pc = _pc();
    pcLibrary = pc.library;
    pcRoot = pc.root;
    pairing = PairingStore();
    server = LanServer(
      library: pcLibrary,
      token: 'de-echte-sleutel',
      state: LanStateStore(File('${pcRoot.path}/state.json')),
      pairing: pairing,
      port: 0, // the OS picks one, so a test never collides with the real app
      version: '1.2.3',
      settings: AppSettings()
        ..discogsToken = 'discogs-leestoken'
        ..lastfmKey = 'lastfm-sleutel'
        ..soulseekPass = 'geheim-wachtwoord'
        ..rutrackerPass = 'ook-geheim',
    );
    expect(await server.start(), isNull);
    base = Uri.parse('http://127.0.0.1:${server.boundPort}');
  });

  tearDown(() async {
    await server.dispose();
    // Windows houdt na de laatste sluiting nog even een greep op deze mappen, dus een rechte
    // `deleteSync` faalde met "het proces heeft geen toegang" — en dan is een toets rood die zijn
    // punt allang gemaakt had. Even opnieuw proberen, en anders laten liggen: een achtergebleven
    // tijdelijke map is geen reden om een geslaagde meting te laten mislukken. Zelfde aanpak als in
    // `offline_test.dart`.
    for (final map in [pcRoot, scratch]) {
      for (var poging = 0; poging < 10; poging++) {
        try {
          map.deleteSync(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    }
  });

  test('six digits off the PC screen, and the library is there', () async {
    // Exactly what the pairing screen does, in order.
    final health = await RemoteClient.health(base);
    expect(health, isNotNull, reason: 'de pc moet zichzelf voorstellen zonder token');
    expect(health!.trackCount, 2);

    final code = pairing.start();
    final endpoint = await RemoteClient.pair(base, code, deviceName: 'iPad van Saber');
    expect(endpoint.token, 'de-echte-sleutel');

    final client = RemoteClient(endpoint);
    final mac = LibraryStore()..remote = client;
    expect(await mac.loadRemote(), isTrue);

    expect(mac.albums.map((a) => a.title), pcLibrary.albums.map((a) => a.title));
    expect(mac.tracks.length, 2);

    // And the music actually arrives — the token in the query, because that is the only place
    // libmpv and a Sonos can carry it.
    final url = client.authorized(mac.tracks.first.path);
    final res = await http.get(Uri.parse(url));
    expect(res.statusCode, 200);
    expect(res.bodyBytes.length, 4096);

    client.close();
  });

  test('a wrong code is refused, and does not burn the right one', () async {
    final code = pairing.start();
    await expectLater(
      RemoteClient.pair(base, '000000', deviceName: 'iPad'),
      throwsA(isA<RemoteException>()),
    );
    // The real code still works: a typo must not force a new one to be generated on the PC.
    final endpoint = await RemoteClient.pair(base, code, deviceName: 'iPad');
    expect(endpoint.token, isNotEmpty);
  });

  test('without a token the library stays shut', () async {
    final res = await http.get(base.replace(path: '/api/catalog'));
    expect(res.statusCode, 401);
  });

  test('the session pairs, remembers, and comes back paired', () async {
    final settings = AppSettings();
    final library = LibraryStore();
    var resolver = (String p) => p;
    final session = ClientSession(
      library: library,
      settings: settings,
      owner: false,
      applyMediaResolver: (r) => resolver = r,
    );
    expect(session.ready, isFalse, reason: 'ongekoppeld hoort het koppelscherm te tonen');

    final endpoint = await RemoteClient.pair(base, pairing.start(), deviceName: 'Mac');
    await session.connect(endpoint);

    expect(session.ready, isTrue);
    expect(library.albums, isNotEmpty);
    expect(library.isRemote, isTrue);

    // The next start: no pairing screen, straight into the library.
    //
    // Asked of the pairing store itself, because that is what "comes back paired" means. Going
    // through resolveMode() would be asking the wrong question on Windows: ownsTheMusic() answers
    // yes there whatever is on disk, deliberately, so a PC whose drive has not spun up cannot
    // become a client of itself — see client_mode.dart. The two mode tests below guard for it too.
    final remembered = await loadPairedServer();
    expect(remembered?.token, endpoint.token);
    expect(remembered?.baseUrl, endpoint.baseUrl);
    if (!Platform.isWindows) {
      final again = await resolveMode(settings);
      expect(again.owner, isFalse);
      expect(again.needsPairing, isFalse);
      expect(again.endpoint?.token, endpoint.token);
    }

    await session.unpair();
    expect(session.ready, isFalse);
    expect(library.isRemote, isFalse);
    // Unpairing really deletes it, rather than merely being ignored at startup.
    expect(await loadPairedServer(), isNull);
    if (!Platform.isWindows) {
      expect((await resolveMode(settings)).needsPairing, isTrue);
    }
    session.dispose();
  });

  test('the PC shares its read-only keys, and only those', () async {
    final settings = AppSettings();
    final library = LibraryStore();
    final session = ClientSession(
      library: library,
      settings: settings,
      owner: false,
      applyMediaResolver: (_) {},
    );
    expect(settings.discogsToken, isEmpty);

    await session.connect(
        await RemoteClient.pair(base, pairing.start(), deviceName: 'iPad'));

    // Looking a record up is something this device can now do for itself, without a hop through
    // the PC for every request.
    expect(settings.discogsToken, 'discogs-leestoken');
    expect(settings.lastfmKey, 'lastfm-sleutel');
    // Passwords are NOT shared. These sign into accounts, and the calls that need them run on the
    // PC anyway — there is no reason for them to be on an iPad.
    expect(settings.soulseekPass, isEmpty);
    expect(settings.rutrackerPass, isEmpty);

    // Unpairing takes them with it.
    await session.unpair();
    expect(settings.discogsToken, isEmpty);
    expect(settings.lastfmKey, isEmpty);
    session.dispose();
  });

  test('a track that lands on the PC shows up here by itself', () async {
    final endpoint = await RemoteClient.pair(base, pairing.start(), deviceName: 'Mac');
    final library = LibraryStore();
    final session = ClientSession(
      library: library,
      settings: AppSettings(),
      owner: false,
      applyMediaResolver: (_) {},
    );
    await session.connect(endpoint);
    final before = library.tracks.length;

    // A download finishing on the PC: a new record in the library there.
    final extra = File('${pcRoot.path}/Portishead/Dummy/03 Strangers.flac')
      ..writeAsBytesSync(List<int>.generate(1024, (i) => i % 256));
    pcLibrary.tracks.add(Track(
      path: extra.path,
      title: 'Strangers',
      artist: 'Portishead',
      album: 'Dummy',
      trackNo: 3,
      trackTotal: 11,
      duration: const Duration(seconds: 238),
      isFlac: true,
      sizeBytes: 1024,
    ));
    pcLibrary.rebuildAlbums();
    pcLibrary.notifyListeners();

    await session.refreshNow();
    expect(library.tracks.length, before + 1);
    expect(library.tracks.map((t) => t.title), contains('Strangers'));
    session.dispose();
  });

  test('the PC decides what a device is called, from what the device said', () async {
    final endpoint = await RemoteClient.pair(base, pairing.start(), deviceName: 'iPad van Saber');
    expect(endpoint.name, isNotEmpty, reason: 'de pc noemt zichzelf, voor het instellingenscherm');

    // And the descriptor a client finds before pairing carries no token — pairing is deliberate.
    final res = await http.get(base.replace(path: '/health'));
    expect(jsonDecode(res.body)['status'], 'ok');
    expect(res.body, isNot(contains('de-echte-sleutel')));
  });

  group('which mode this is', () {
    test('a device with no music folder reads someone else\'s library', () async {
      final settings = AppSettings()..musicRoot = '';
      // On Windows the answer is always "owner" — the PC IS the library, even when the drive has
      // not spun up yet. Elsewhere it comes down to whether there is a folder to scan.
      expect(ownsTheMusic(settings), Platform.isWindows);
    });

    test('a Mac with a music folder is an owner like any other', () {
      if (Platform.isWindows) return;
      final music = Directory('${scratch.path}/muziek')..createSync();
      expect(ownsTheMusic(AppSettings()..musicRoot = music.path), isTrue);
      // A folder that is not there is not a library — a typo must not silently scan nothing.
      expect(ownsTheMusic(AppSettings()..musicRoot = '${scratch.path}/bestaat-niet'), isFalse);
    });
  });
}
