/// "Ik heb deze hoes al — is hij nog steeds de jouwe?"
///
/// **Waarom deze toets bestaat.** Twee toestellen hielden hardnekkig twee verschillende hoezen van
/// hetzelfde album vast. Drie oorzaken zijn er al uit; dit is de vierde en de algemeenste.
///
/// De hoescache van een toestel heet naar `artiest|titel`, en die naam beweegt nooit. Wat er één
/// keer in beland is blijft er dus staan. Er was maar één ding om dat tegenaan te houden —
/// `AlbumDto.artTag` — en dat merkteken bestaat alléén voor een hoes die de eigenaar BEWUST gekozen
/// heeft. Met opzet: het reist mee in de vingerafdruk van de catalogus, en zou het bij elke
/// automatisch gevonden hoes bewegen, dan duwde het verrijken van een verse bibliotheek de hele
/// catalogus honderden keren naar elk toestel.
///
/// Gevolg: kwam de hoes op de pc uit de tags van het bestand of uit het verrijken — het gewóne geval
/// — dan stond er nergens iets waaraan een Mac kon zien dat zijn cachebestand achterhaald was. Hij
/// keek er niet eens meer naar.
///
/// De uitweg is de gewone HTTP-uitweg, en hij kost niets omdat hij per verzoek gaat in plaats van
/// per catalogus: `/art/` geeft een ETag over de bytes die er NU liggen, en een toestel dat er al
/// een heeft vraagt met `If-None-Match` na. Klopt het, dan komt er een lege 304 terug; klopt het
/// niet, dan meteen de juiste bytes — nooit meer dan één rit.
///
/// Wat hier vastligt:
///
///   * er komt een ETag mee, en die hoort bij de bytes en niet bij de bewuste keuze;
///   * hetzelfde merkteken levert 304 en géén bytes;
///   * verandert de hoes op de pc, dan verandert de ETag en komen de nieuwe bytes meteen mee;
///   * een verkeerd merkteken krijgt gewoon de juiste hoes, geen 304.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/enrichment.dart';
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
  // Een echte JPEG-kop; de app kijkt op meer plekken of iets wel een afbeelding is.
  Uint8List plaatje(int zaad) => Uint8List.fromList(
      [0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.generate(3000, (i) => (i * zaad) % 256)]);

  final clown = plaatje(7);
  final juiste = plaatje(11);

  setUp(() async {
    krab = Directory.systemTemp.createTempSync('dm_navraag_');
    setAppDirForTest(krab.path);
    wortel = Directory.systemTemp.createTempSync('dm_navraag_muziek_');
    final map = Directory('${wortel.path}/Various Artists/Thunderdome VIII')
      ..createSync(recursive: true);
    final pad = '${map.path}/01.flac';
    File(pad).writeAsBytesSync(const [1, 2, 3, 4]);

    library = LibraryStore()
      ..rootPath = wortel.path
      ..configDirOverride = wortel.path;
    library.tracks.add(Track(
      path: pad,
      title: 'The Devil in Disguise',
      artist: 'Various Artists',
      album: 'Thunderdome VIII',
      isFlac: true,
      sizeBytes: 4,
    ));
    library.rebuildAlbums();
    // Uit de tags van het bestand, dus NIET uit een bewuste keuze: `artTag` blijft leeg en dit is
    // precies het geval waar de oude controle blind voor was.
    library.albums.first.embeddedCover = clown;

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

  /// Het id waaronder de pc dit album kent, én wat hij als bewuste keuze meldt.
  Future<({String id, String artTag})> uitCatalogus() async {
    final res = await http.get(basis.replace(path: '/api/catalog'),
        headers: {'Authorization': 'Bearer $token'});
    expect(res.statusCode, 200);
    final album = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['albums'] as List).first as Map;
    return (id: album['id'] as String, artTag: (album['artTag'] as String?) ?? '');
  }

  Future<http.Response> haal(String ref, {String? merk}) => http.get(
        basis.replace(path: '/art/$ref'),
        headers: {
          'Authorization': 'Bearer $token',
          if (merk != null) 'If-None-Match': '"$merk"',
        },
      );

  test('er komt een merkteken mee, ook zonder dat de eigenaar iets gekozen heeft', () async {
    final cat = await uitCatalogus();
    // De kern van het gat: hier valt niets aan af te lezen.
    expect(cat.artTag, isEmpty,
        reason: 'een hoes uit de tags is geen bewuste keuze — dus geen artTag, met opzet');

    final res = await haal(cat.id);
    expect(res.statusCode, 200);
    expect(res.bodyBytes, clown);
    // En hier wél. Dit is het enige waaraan een toestel kan zien wat het vasthoudt.
    expect(res.headers['etag'], isNotNull);
    expect(res.headers['etag']?.replaceAll('"', ''), CoverEnricher.hoesMerk(clown));
  });

  test('hetzelfde merkteken levert een lege 304 op', () async {
    final cat = await uitCatalogus();
    final merk = CoverEnricher.hoesMerk(clown);

    final res = await haal(cat.id, merk: merk);
    expect(res.statusCode, 304);
    expect(res.bodyBytes, isEmpty, reason: 'daar is het navragen voor: geen bytes over de lijn');
    expect(res.headers['etag']?.replaceAll('"', ''), merk);
  });

  test('verandert de hoes op de pc, dan komt hij er meteen uit', () async {
    final cat = await uitCatalogus();
    final oudMerk = CoverEnricher.hoesMerk(clown);

    // Wat de eigenaar op de pc doet — hier zonder bewuste keuze, gewoon een andere afbeelding uit
    // de tags. Precies het geval dat vroeger onzichtbaar bleef.
    library.albums.first.embeddedCover = juiste;

    final res = await haal(cat.id, merk: oudMerk);
    expect(res.statusCode, 200, reason: 'het merkteken klopt niet meer, dus geen 304');
    expect(res.bodyBytes, juiste);
    expect(res.headers['etag']?.replaceAll('"', ''), CoverEnricher.hoesMerk(juiste));
    expect(res.headers['etag']?.replaceAll('"', ''), isNot(oudMerk));
  });

  test('een merkteken dat nergens op slaat krijgt gewoon de hoes', () async {
    final cat = await uitCatalogus();
    final res = await haal(cat.id, merk: 'onzin');
    expect(res.statusCode, 200);
    expect(res.bodyBytes, clown);
  });

  test('een bewuste keuze en de bytes die eruit komen dragen hetzelfde merkteken', () async {
    // Deze twee sporen moeten op elkaar blijven passen: `artTag` uit de catalogus is het merkteken
    // van de gekozen hoes, en de ETag is dat van wat `/art/` werkelijk uitlevert. Zou een van beide
    // ooit anders gaan rekenen, dan houdt een toestel zijn hoes voor achterhaald bij elke ronde en
    // haalt hij hem eindeloos opnieuw op.
    library.albums.first.correctedCover = juiste;
    final cat = await uitCatalogus();
    expect(cat.artTag, CoverEnricher.hoesMerk(juiste));

    final res = await haal(cat.id);
    expect(res.headers['etag']?.replaceAll('"', ''), cat.artTag);
  });
}
