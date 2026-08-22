/// De catalogus gaat ingepakt over de lijn.
///
/// **Wat hier misging.** De server zet `autoCompress = false`, met als reden "audio and covers are
/// already compressed". Dat klopt — audio en hoezen nóg eens door gzip halen kost alleen rekentijd.
/// Maar het zette het óók uit voor `/api/catalog`, en dat is precies het enige antwoord dat groot én
/// goed samendrukbaar is: JSON van megabytes.
///
/// De cloudkopie in ditzelfde project meet dat diezelfde tekst ongeveer vijfvoudig comprimeert. Vier
/// toestellen die na elke wijziging opnieuw synchroniseren betaalden dat dus vijfvoudig te veel over
/// wifi — en dat is de "hij bevriest even" op de iPad en de Shield na elke download op de pc.
///
/// Twee dingen moeten kloppen en allebei zijn ze stil als ze fout gaan: de inhoud moet ná uitpakken
/// letterlijk hetzelfde zijn, en de ETag moet die van de ONgecomprimeerde inhoud blijven — anders
/// betekent een 304 iets anders dan voorheen en synchroniseren de toestellen te veel of te weinig.
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
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory krab;
  late Directory wortel;
  late LanServer server;
  late Uri basis;

  const token = 'toets-token';

  setUp(() async {
    krab = Directory.systemTemp.createTempSync('dm_gzip_');
    setAppDirForTest(krab.path);
    wortel = Directory.systemTemp.createTempSync('dm_gzip_muziek_');

    final library = LibraryStore()
      ..rootPath = wortel.path
      ..configDirOverride = wortel.path;
    // Genoeg nummers dat inpakken iets betekent. Eén nummer comprimeert ook wel, maar dan meet je
    // vooral de gzip-kop en niet de winst waar dit voor bedoeld is.
    for (var a = 0; a < 12; a++) {
      final map = Directory('${wortel.path}/Artiest $a/Album $a')..createSync(recursive: true);
      for (var t = 0; t < 14; t++) {
        final pad = '${map.path}/${t + 1}.flac';
        File(pad).writeAsBytesSync(const [1, 2, 3, 4]);
        library.tracks.add(Track(
          path: pad,
          title: 'Een nummer met een redelijk gewone titel $t',
          artist: 'Artiest $a',
          album: 'Album $a',
          isFlac: true,
          sizeBytes: 4,
        ));
      }
    }
    library.rebuildAlbums();

    server = LanServer(
      library: library,
      token: token,
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

  /// Een verzoek waarbij wij zelf beslissen of er ingepakt mag worden, en zelf uitpakken. Via
  /// `HttpClient` met `autoUncompress: false`, want anders pakt Dart het onzichtbaar voor ons uit en
  /// meet deze toets niets.
  Future<({int status, String? codering, List<int> lijf, String? etag})> haal(
      {required bool magGzip, String? ifNoneMatch}) async {
    final c = HttpClient()..autoUncompress = false;
    try {
      final req = await c.getUrl(basis.replace(path: '/api/catalog'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.removeAll(HttpHeaders.acceptEncodingHeader);
      if (magGzip) req.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      if (ifNoneMatch != null) req.headers.set(HttpHeaders.ifNoneMatchHeader, ifNoneMatch);
      final res = await req.close();
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
      return (
        status: res.statusCode,
        codering: res.headers.value(HttpHeaders.contentEncodingHeader),
        lijf: bytes,
        etag: res.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      c.close(force: true);
    }
  }

  test('een client die gzip aankan krijgt het ingepakt, en het pakt weer precies uit', () async {
    final kaal = await haal(magGzip: false);
    final ingepakt = await haal(magGzip: true);

    expect(kaal.status, 200);
    expect(ingepakt.status, 200);
    expect(ingepakt.codering, 'gzip');
    expect(kaal.codering, isNull, reason: 'wie er niet om vraagt hoort het niet te krijgen');

    // DIT is de bewering die telt. Alles hierboven kan kloppen terwijl de inhoud stuk is.
    expect(gzip.decode(ingepakt.lijf), kaal.lijf);
    // En het is nog steeds leesbare JSON aan de andere kant.
    final json = jsonDecode(utf8.decode(gzip.decode(ingepakt.lijf))) as Map<String, dynamic>;
    expect((json['albums'] as List).length, 12);
  });

  test('en het scheelt werkelijk bytes — anders is de hele wijziging zinloos', () async {
    final kaal = await haal(magGzip: false);
    final ingepakt = await haal(magGzip: true);
    expect(ingepakt.lijf.length, lessThan(kaal.lijf.length ~/ 2),
        reason: 'kaal ${kaal.lijf.length} B, ingepakt ${ingepakt.lijf.length} B');
  });

  test('de ETag blijft die van de ONgecomprimeerde inhoud', () async {
    final kaal = await haal(magGzip: false);
    final ingepakt = await haal(magGzip: true);
    expect(ingepakt.etag, isNotNull);
    expect(ingepakt.etag, kaal.etag,
        reason: 'twee ETags voor één versie laat toestellen onnodig opnieuw synchroniseren');

    // En een 304 blijft een 304, ook met gzip erbij gevraagd — dat is de weg waarlangs een toestel
    // dat al bij is niets betaalt.
    final opnieuw = await haal(magGzip: true, ifNoneMatch: kaal.etag);
    expect(opnieuw.status, 304);
    expect(opnieuw.lijf, isEmpty);
  });
}
