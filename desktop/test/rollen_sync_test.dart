/// De scans die je aanwijst reizen mee naar je andere toestellen.
///
/// **Wat hier misging.** `album_art_roles.json` — welke scan de hoes is, welke de achterkant, welke
/// de cd — stond op het toestel waar de keuze gemaakt was, en nergens anders. Er was geen veld voor
/// in de catalogus en geen bewerking om het naar de pc te sturen.
///
/// Dus: wees je op de iPad de juiste cd-scan aan, dan wist de pc daar niets van, en de Shield en de
/// telefoon dus ook niet. Terwijl een vastgezette persing, een samengevoegde editie, een gekozen
/// artiestportret en de gekozen hoes hier allemaal wél al in zaten. Dat was geen ontwerpkeuze maar
/// een gat, en op vier toestellen valt het meteen op.
///
/// Twee kanten moeten kloppen, en allebei zijn ze stil als ze het niet doen:
///
///   * de bewerking moet op de pc AANKOMEN en daar worden opgeslagen,
///   * en de catalogus moet hem TERUGGEVEN, met een ETag die beweegt — want zonder dat laatste
///     krijgt elk toestel een 304 en hoort het nooit dat er iets veranderd is. Dat is exact de bug
///     die in augustus 2026 al eens met de hoezen gemeten werd.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late Directory krab;
  late Directory wortel;
  late LibraryStore library;
  late LanServer server;
  late Uri basis;

  const token = 'toets-token';
  const artiest = 'Portishead';
  const titel = 'Dummy';
  const cdScan = 'https://coverartarchive.org/release/abc-123/98765.jpg';

  setUp(() async {
    krab = Directory.systemTemp.createTempSync('dm_rollen_');
    setAppDirForTest(krab.path);
    wortel = Directory.systemTemp.createTempSync('dm_rollen_muziek_');
    final map = Directory('${wortel.path}/$artiest/$titel')..createSync(recursive: true);
    final pad = '${map.path}/01.flac';
    File(pad).writeAsBytesSync(const [1, 2, 3, 4]);

    library = LibraryStore()
      ..rootPath = wortel.path
      ..configDirOverride = wortel.path;
    library.tracks.add(Track(
      path: pad,
      title: 'Mysterons',
      artist: artiest,
      album: titel,
      isFlac: true,
      sizeBytes: 4,
    ));
    library.rebuildAlbums();

    server = LanServer(
      library: library,
      token: token,
      // Zonder deze weigert `/api/corrections` élke bewerking met 503 — "Deze pc kan geen
      // wijzigingen aannemen." In de app is hij er altijd; in een toets moet je eraan denken.
      settings: AppSettings(),
      state: LanStateStore(File('${wortel.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      grants: GrantStore(file: File('${krab.path}/grants.json')),
    );
    expect(await server.start(), isNull);
    basis = Uri.parse('http://127.0.0.1:${server.boundPort}');
  });

  tearDown(() async {
    await server.dispose();
    wortel.deleteSync(recursive: true);
    krab.deleteSync(recursive: true);
  });

  Future<http.Response> bewerk(Map<String, dynamic> op) => http.post(
        basis.replace(path: '/api/corrections'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(op),
      );

  Future<({Map<String, dynamic> album, String? etag})> catalogus() async {
    final res = await http.get(basis.replace(path: '/api/catalog'),
        headers: {'Authorization': 'Bearer $token'});
    expect(res.statusCode, 200);
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (album: (j['albums'] as List).first as Map<String, dynamic>, etag: res.headers['etag']);
  }

  test('een cd die op een ander toestel is aangewezen komt aan én komt terug', () async {
    final voor = await catalogus();
    expect(voor.album['artRoles'], anyOf(isNull, isEmpty),
        reason: 'zonder keuze hoort er niets te staan');

    final res = await bewerk(
        {'op': 'albumArtRole', 'artist': artiest, 'album': titel, 'role': 'disc', 'url': cdScan});
    expect(res.statusCode, 200, reason: res.body);

    // Aangekomen op de pc.
    expect(library.albumArtRoles(artiest, titel), {'disc': cdScan});

    // En teruggegeven aan elk ander toestel.
    final na = await catalogus();
    expect((na.album['artRoles'] as Map)['disc'], cdScan);

    // DIT is de helft die stil faalt. Beweegt de ETag niet, dan krijgt elk toestel een 304 en ziet
    // het de keuze nooit — hoe correct hij verder ook opgeslagen is.
    expect(na.etag, isNotNull);
    expect(na.etag, isNot(voor.etag),
        reason: 'een aangewezen scan verandert geen enkel nummer, dus de vingerafdruk moet hem apart meetellen');
  });

  test('wissen reist ook mee', () async {
    await bewerk(
        {'op': 'albumArtRole', 'artist': artiest, 'album': titel, 'role': 'disc', 'url': cdScan});
    expect(library.albumArtRoles(artiest, titel), isNotEmpty);

    final res =
        await bewerk({'op': 'albumArtRole', 'artist': artiest, 'album': titel, 'clear': true});
    expect(res.statusCode, 200, reason: res.body);
    expect(library.albumArtRoles(artiest, titel), isEmpty);

    // Anders wist een iPad zijn eigen lege lijstje terwijl de pc de oude rollen hield, en stonden ze
    // er na de eerstvolgende synchronisatie gewoon weer.
    final na = await catalogus();
    expect(na.album['artRoles'], anyOf(isNull, isEmpty));
  });

  test('zonder artiest of album is het een nette fout, geen stille mislukking', () async {
    final res = await bewerk({'op': 'albumArtRole', 'role': 'disc', 'url': cdScan});
    expect(res.statusCode, 400);
  });

  test('één scan kan niet twee dingen zijn', () async {
    // Bestaand gedrag van setAlbumArtRole, en het hoort ook over de lijn te gelden.
    await bewerk(
        {'op': 'albumArtRole', 'artist': artiest, 'album': titel, 'role': 'back', 'url': cdScan});
    await bewerk(
        {'op': 'albumArtRole', 'artist': artiest, 'album': titel, 'role': 'disc', 'url': cdScan});
    expect(library.albumArtRoles(artiest, titel), {'disc': cdScan});
  });
}
