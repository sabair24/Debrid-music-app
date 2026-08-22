/// Een hoes die je op een ander toestel kiest, hoort overal te veranderen.
///
/// **Wat hier misging.** `setAlbumCover` had geen tak voor een client. Op een Mac, een iPad of een
/// telefoon schreef hij alleen naar het geheugen en de cache van dát toestel. Corrigeerde je de hoes
/// op de Mac, dan bleef de pc de oude houden — en de telefoon toont wat de pc zegt.
///
/// Zo stonden er van hetzelfde album twee verschillende hoezen op twee schermen, en hielp corrigeren
/// niet: de correctie kwam nooit aan op de plek waar hij gelezen wordt.
///
/// Anders dan bij een rol gaan hier BYTES over de lijn en geen adres, want een gekozen hoes komt
/// niet altijd van het web — hij kan uit een bestand of uit de tags komen.
///
/// Twee dingen moeten kloppen:
///
///   * de bytes moeten AANKOMEN en op de pc de hoes van dat album worden,
///   * en de ETag moet bewegen, want anders krijgt elk ander toestel een 304 en blijft het de oude
///     hoes tonen — hoe goed de correctie hier ook geland is.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  // Een echte JPEG-kop, want de app kijkt op meer plekken of iets wel een afbeelding is.
  final nieuweHoes = Uint8List.fromList(
      [0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.generate(3000, (i) => (i * 7) % 256)]);
  final oudeHoes = Uint8List.fromList(
      [0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.generate(3000, (i) => (i * 3) % 256)]);

  setUp(() async {
    krab = Directory.systemTemp.createTempSync('dm_hoes_');
    setAppDirForTest(krab.path);
    wortel = Directory.systemTemp.createTempSync('dm_hoes_muziek_');
    final map = Directory('${wortel.path}/Michael Jackson/Bad')..createSync(recursive: true);
    final pad = '${map.path}/01.flac';
    File(pad).writeAsBytesSync(const [1, 2, 3, 4]);

    library = LibraryStore()
      ..rootPath = wortel.path
      ..configDirOverride = wortel.path;
    library.tracks.add(Track(
      path: pad,
      title: 'Speed Demon',
      artist: 'Michael Jackson',
      album: 'Bad',
      isFlac: true,
      sizeBytes: 4,
    ));
    library.rebuildAlbums();
    // Wat de pc nu heeft: de verkeerde hoes.
    library.albums.first.embeddedCover = oudeHoes;

    server = LanServer(
      library: library,
      token: token,
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

  Future<({String id, String? artTag, String? etag})> catalogus() async {
    final res = await http.get(basis.replace(path: '/api/catalog'),
        headers: {'Authorization': 'Bearer $token'});
    expect(res.statusCode, 200);
    final album = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['albums'] as List).first as Map;
    return (
      id: album['id'] as String,
      artTag: album['artTag'] as String?,
      etag: res.headers['etag']
    );
  }

  test('een hoes gekozen op de Mac landt op de pc en komt bij de telefoon terug', () async {
    final voor = await catalogus();

    final res = await http.post(
      basis.replace(path: '/api/corrections'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(
          {'op': 'albumCover', 'albumId': voor.id, 'cover': base64Encode(nieuweHoes)}),
    );
    expect(res.statusCode, 200, reason: res.body);

    // Aangekomen, en het is werkelijk de nieuwe.
    expect(library.albums.first.correctedCover, nieuweHoes);
    expect(library.albums.first.cover, nieuweHoes,
        reason: 'een gekozen hoes hoort boven de ingebedde te gaan');

    // En de telefoon haalt hem nu ook echt op: hij krijgt de bytes via /art/…
    final art = await http.get(basis.replace(path: '/art/${voor.id}'),
        headers: {'Authorization': 'Bearer $token'});
    expect(art.statusCode, 200);
    expect(art.bodyBytes, nieuweHoes);

    // …en hij hoort te MERKEN dat er iets veranderd is. Zonder een bewegende ETag krijgt elk toestel
    // een 304 en blijft de oude hoes staan — precies de bug die dit alles veroorzaakte.
    final na = await catalogus();
    expect(na.etag, isNot(voor.etag));
    expect(na.artTag, isNotNull);
    expect(na.artTag, isNot(voor.artTag),
        reason: 'het merkteken van de gekozen hoes moet mee bewegen');
  });

  test('een leeg bericht is een nette fout, geen stille mislukking', () async {
    final voor = await catalogus();
    final res = await http.post(
      basis.replace(path: '/api/corrections'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'op': 'albumCover', 'albumId': voor.id, 'cover': ''}),
    );
    expect(res.statusCode, 400);
    expect(library.albums.first.cover, oudeHoes, reason: 'er mag niets gewist zijn');
  });

  test('een album dat de pc niet kent geeft 404 en verandert niets', () async {
    final res = await http.post(
      basis.replace(path: '/api/corrections'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(
          {'op': 'albumCover', 'albumId': 'bestaat-niet', 'cover': base64Encode(nieuweHoes)}),
    );
    expect(res.statusCode, 404);
    expect(library.albums.first.cover, oudeHoes);
  });
}
