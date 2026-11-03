// Hoezen, scans, rollen en hartjes per PLAAT (Saber, 03-11-2026). Marc Lavoine is vanzelf twee tegels geworden (1985 en
// 2001, scheiden_op_plaat_test.dart), maar alles wat de app over een plaat onthoudt hing nog aan `artiest|titel`: de hoes
// die hij voor de ene koos stond op allebei, de hoesveger schreef die ook in het bestand van de andere plaat, en de
// digitale voorkant van Deezer (de plaat uit 2001) kwam op beide tegels. Seal (1991/1994, "Scheiden per jaar") net zo.
// Elke tegel van zo'n naam krijgt nu zijn eigen sleutels; elke andere plaat houdt precies de sleutel die hij had.
// Geen net: Deezer en de beelden komen uit een nep-client, de pc en het toestel praten via een MockClient.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/cachesleutel.dart' show fnv1a;
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/facts_warmer.dart';
import 'package:debridmusic/favorieten.dart';
import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/hoes_in_bestand.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/lan/ids.dart' show albumIdFor;
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/organize.dart' show artistKey, normKey;
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

/// Een JPEG-kop met maten en vulling: genoeg voor de hoesveger, en elk [zaad] een ander beeld.
Uint8List _jpeg(int zaad, {int lengte = 4000}) {
  final b = Uint8List(lengte);
  b.setAll(0, [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 600 >> 8, 600 & 0xFF, 600 >> 8, 600 & 0xFF, 0x03]);
  final r = Random(zaad);
  for (var i = 12; i < b.length - 2; i++) {
    b[i] = r.nextInt(256);
  }
  b[b.length - 2] = 0xFF;
  b[b.length - 1] = 0xD9;
  return b;
}

/// Een kleine echte FLAC met tags, een opvulblok en wat "audio".
Uint8List _flac(String titel) {
  final out = BytesBuilder()..add(ascii.encode('fLaC'));
  void blok(int soort, List<int> lijf, bool laatste) {
    out.add([(laatste ? 0x80 : 0) | soort, (lijf.length >> 16) & 0xFF, (lijf.length >> 8) & 0xFF, lijf.length & 0xFF]);
    out.add(lijf);
  }

  final si = Uint8List(34);
  si[10] = (44100 >> 12) & 0xFF;
  si[11] = (44100 >> 4) & 0xFF;
  si[12] = ((44100 & 0x0F) << 4) | (1 << 1);
  si[14] = 0x02;
  blok(0, si, false);
  final v = BytesBuilder();
  void u32(int x) => v.add([x & 0xFF, (x >> 8) & 0xFF, (x >> 16) & 0xFF, (x >> 24) & 0xFF]);
  final ven = utf8.encode('test');
  u32(ven.length);
  v.add(ven);
  final c = utf8.encode('TITLE=$titel');
  u32(1);
  u32(c.length);
  v.add(c);
  blok(4, v.toBytes(), false);
  blok(1, Uint8List(20000), true);
  out.add(List.filled(30000, 0x5A));
  return out.toBytes();
}

const _ml = 'Marc Lavoine';

void main() {
  late Directory scratch;
  late String muziek;
  final sep = Platform.pathSeparator;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_hoes_plaat_');
    setAppDirForTest(scratch.path);
    muziek = '${scratch.path}${sep}muziek';
  });
  tearDown(() {
    CoverEnricher.gedeeldeNamen = const {};
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  Track nummer(String rel, String titel, int jaar, {String album = _ml, String artiest = _ml}) {
    final pad = '$muziek$sep${rel.replaceAll('/', sep)}';
    File(pad)
      ..createSync(recursive: true)
      ..writeAsBytesSync(_flac(titel));
    return Track(path: pad, title: titel, artist: artiest, album: album, year: jaar, isFlac: true);
  }

  void schrijfJson(String naam, Object inhoud) =>
      File('${scratch.path}$sep$naam').writeAsStringSync(jsonEncode(inhoud));

  const register = {
    'discogs:2436536': {'plaat': 'master:95856', 'jaar': 1985},
    'discogs:1441911': {'plaat': 'master:697091', 'jaar': 2001},
  };

  late Track revolver, oublie;

  /// Marc Lavoine (twee platen, vastgezet), Seal (per jaar gescheiden) en een gewone plaat. [platenBekend] uit: de
  /// platen zijn nog niet opgezocht, dus Marc Lavoine is nog één tegel.
  Future<LibraryStore> bib({bool platenBekend = true}) async {
    revolver = nummer('Compilaties/Best Of/02 - Elle a les yeux revolver.flac', 'Elle a les yeux revolver', 1985);
    oublie = nummer('Albums/Marc Lavoine/Marc Lavoine/11 - J ai tout oublie.flac', "J'ai tout oublié", 2001);
    schrijfJson('corrections.json', {
      revolver.path: {'artist': _ml, 'album': _ml, 'release': '2436536'},
      oublie.path: {'artist': _ml, 'album': _ml, 'release': '1441911'},
    });
    if (platenBekend) schrijfJson('plaat_register.json', register);
    schrijfJson('split_albums.json', ['album::seal|seal']);
    final lib = LibraryStore()..configDirOverride = scratch.path;
    addTearDown(lib.uids.dispose);
    await lib.loadCorrections();
    await lib.loadPlaten();
    await lib.loadGesplitst();
    await lib.loadMerged();
    lib.tracks.addAll([
      revolver,
      oublie,
      nummer('Albums/Seal/Seal/04 - Killer.flac', 'Killer', 1991, album: 'Seal', artiest: 'Seal'),
      nummer('Albums/Seal/Seal (1994)/06 - Kiss from a Rose.flac', 'Kiss from a Rose', 1994, album: 'Seal', artiest: 'Seal'),
      nummer('Albums/MJ/Thriller/01 - Wanna Be Startin.flac', "Wanna Be Startin' Somethin'", 1982,
          album: 'Thriller', artiest: 'Michael Jackson'),
    ]);
    lib.rebuildAlbums();
    return lib;
  }

  Album tegel(LibraryStore lib, String titel, int jaar) => lib.albums.firstWhere((a) => a.title == titel && a.year == jaar);

  test('een tegel zonder plaat houdt precies zijn oude sleutels; elke gescheiden tegel krijgt de zijne', () async {
    final lib = await bib();
    final e = CoverEnricher(AppSettings());
    final thriller = lib.albums.firstWhere((a) => a.title == 'Thriller');
    expect(thriller.plaat, isNull);
    expect(e.keyFor(thriller), fnv1a('michael jackson|thriller'), reason: 'geen hoes van 900 platen opnieuw ophalen');
    expect(LibraryStore.albumArtKey('Michael Jackson', 'Thriller'), '${artistKey('Michael Jackson')}|${normKey('Thriller')}');

    final m85 = tegel(lib, _ml, 1985), m01 = tegel(lib, _ml, 2001);
    final s91 = tegel(lib, 'Seal', 1991), s94 = tegel(lib, 'Seal', 1994);
    expect([m85.plaat, m01.plaat, s91.plaat, s94.plaat], ['master:95856', 'master:697091', 'jaar:1991', 'jaar:1994']);
    final samen = Album(_ml, _ml, const []);
    expect({e.keyFor(m85), e.keyFor(m01), e.keyFor(samen)}, hasLength(3));
    expect({e.keyFor(s91), e.keyFor(s94), e.keyFor(Album('Seal', 'Seal', const []))}, hasLength(3));
    expect(CoverEnricher.gedeeldeNamen, {CoverEnricher.naamSleutel(_ml, _ml), CoverEnricher.naamSleutel('Seal', 'Seal')});

    // En elk zijn eigen vastgezette persing — niet de eerste die de oude tegel tegenkwam.
    expect(lib.pinnedRelease(m85), 2436536);
    expect(lib.pinnedRelease(m01), 1441911);
  });

  test('aangewezen scans per tegel, en zo ook op een toestel', () async {
    final lib = await bib();
    final m85 = tegel(lib, _ml, 1985), m01 = tegel(lib, _ml, 2001);
    await lib.setAlbumArtRole(_ml, _ml, 'disc', 'https://scan.invalid/cd85.jpg', plaat: m85.plaat);
    await lib.setAlbumArtRole('Michael Jackson', 'Thriller', 'back', 'https://scan.invalid/mj.jpg');
    expect(lib.albumArtRoles(_ml, _ml, plaat: m85.plaat), {'disc': 'https://scan.invalid/cd85.jpg'});
    expect(lib.albumArtRoles(_ml, _ml, plaat: m01.plaat), isEmpty, reason: 'de cd van 1985 is niet die van 2001');
    expect(lib.albumArtRoles(_ml, _ml), isEmpty);
    expect(lib.albumArtRoles('Michael Jackson', 'Thriller'), {'back': 'https://scan.invalid/mj.jpg'});

    // Over de lijn: de plaat en de rollen per tegel.
    lib.rootPath = muziek;
    final catalogus = LanCatalog(lib);
    final dto = AlbumDto.fromJson(jsonDecode(jsonEncode(const AlbumDto(
            id: 'a', artistId: 'b', artistName: _ml, title: _ml, plaat: 'master:95856')
        .toJson())) as Map<String, dynamic>);
    expect(dto.plaat, 'master:95856');
    expect(const AlbumDto(id: 'a', artistId: 'b', artistName: 'X', title: 'Y').toJson().containsKey('plaat'), isFalse,
        reason: 'een gewone plaat stuurt precies wat hij stuurde');
    final bewerkingen = <Map<String, dynamic>>[];
    final mock = MockClient((req) async {
      if (req.url.path == '/api/corrections') {
        bewerkingen.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      if (req.url.path != '/api/catalog') return http.Response('', 404);
      final snap = catalogus.snapshot();
      return http.Response.bytes(snap.json, 200, headers: {'etag': snap.etag});
    });
    final toestel = LibraryStore()
      ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.216:47820'), token: 'geheim'),
          client: mock);
    addTearDown(toestel.stopHoesHerkansing);
    expect(await toestel.loadRemote(), isTrue);
    final daar85 = toestel.albums.firstWhere((a) => a.title == _ml && a.year == 1985);
    final daar01 = toestel.albums.firstWhere((a) => a.title == _ml && a.year == 2001);
    expect([daar85.plaat, daar01.plaat], ['master:95856', 'master:697091']);
    expect(toestel.albumArtRoles(_ml, _ml, plaat: daar85.plaat), {'disc': 'https://scan.invalid/cd85.jpg'});
    expect(toestel.albumArtRoles(_ml, _ml, plaat: daar01.plaat), isEmpty);
    expect(toestel.pinnedRelease(daar85), 2436536);
    expect(toestel.pinnedRelease(daar01), 1441911);
    expect(CoverEnricher.gedeeldeNamen, contains(CoverEnricher.naamSleutel(_ml, _ml)));

    // Een rol die op het toestel gekozen wordt, gaat met zijn plaat naar de pc.
    await toestel.setAlbumArtRole(_ml, _ml, 'back', 'https://scan.invalid/achter01.jpg', plaat: daar01.plaat);
    expect(bewerkingen.where((b) => b['op'] == 'albumArtRole').single['plaat'], 'master:697091');
  });

  test('een gescheiden tegel die een eigen naam krijgt, neemt zijn rollen en zijn hoes mee', () async {
    final lib = await bib();
    final s = AppSettings();
    final m85 = tegel(lib, _ml, 1985);
    await lib.setAlbumArtRole(_ml, _ml, 'disc', 'https://scan.invalid/cd85.jpg', plaat: m85.plaat);
    await lib.setAlbumCover(m85, s, _jpeg(85));
    await lib.applyCorrection(m85, s, albumTitle: '$_ml (1985)');
    expect(lib.albumArtRoles(_ml, '$_ml (1985)'), {'disc': 'https://scan.invalid/cd85.jpg'});
    expect(await CoverEnricher(s).fixedCover(Album('$_ml (1985)', _ml, const [])), _jpeg(85));
    expect(lib.albumArtRoles(_ml, _ml, plaat: 'master:697091'), isEmpty, reason: 'de andere plaat houdt de hare');
  });

  test('een gevonden hoes landt op zijn eigen tegel; zonder plaat op geen van beide', () async {
    final lib = await bib();
    final s = AppSettings();
    final h85 = _jpeg(85), h01 = _jpeg(1);
    expect(lib.adoptAlbumCover(_ml, _ml, h85, from: 'rel:2436536', settings: s, plaat: 'master:95856'), isTrue);
    expect(lib.adoptAlbumCover(_ml, _ml, h01, from: 'rel:1441911', settings: s, plaat: 'master:697091'), isTrue);
    expect(tegel(lib, _ml, 1985).resolvedCover, h85);
    expect(tegel(lib, _ml, 2001).resolvedCover, h01);
    expect(lib.adoptAlbumCover(_ml, _ml, _jpeg(7), from: 'dz:109504', settings: s), isFalse,
        reason: 'een hoes op naam weet niet van welke plaat hij is');
    expect(tegel(lib, _ml, 1985).resolvedCover, h85);
    // En een gewone plaat zoals altijd.
    expect(lib.adoptAlbumCover('Michael Jackson', 'Thriller', _jpeg(3), from: 'dz:1', settings: s), isTrue);
  });

  test('bij het scheiden neemt geen tegel de hoes van de oude over; weer samen komt die terug', () async {
    final lib = await bib(platenBekend: false);
    final s = AppSettings();
    expect(lib.albums.where((a) => a.title == _ml), hasLength(1));
    final h01 = _jpeg(1);
    // Zoals Saber op 03-11-2026: de hoes van 2001 gekozen voor de ene tegel waar beide platen op stonden.
    await lib.setAlbumCover(lib.albums.firstWhere((a) => a.title == _ml), s, h01);

    schrijfJson('plaat_register.json', register);
    await lib.loadPlaten();
    lib.rebuildAlbums();
    await lib.hoezenNaPlaatwissel;
    final m85 = tegel(lib, _ml, 1985), m01 = tegel(lib, _ml, 2001);
    expect(m85.correctedCover, isNull, reason: 'de hoes van 2001 hoort niet op de plaat van 1985');
    expect(m01.correctedCover, isNull, reason: 'gekozen voor de oude tegel, niet voor deze');
    expect(hoesVoorBestanden(m85)?.alleenAlsLeeg ?? true, isTrue, reason: 'dus schrijft de veger niets in het bestand');

    // Een keuze per tegel blijft per tegel, ook na een herstart.
    final h85 = _jpeg(85);
    await lib.setAlbumCover(m85, s, h85);
    expect(tegel(lib, _ml, 2001).correctedCover, isNull);
    final opnieuw = LibraryStore()..configDirOverride = scratch.path;
    addTearDown(opnieuw.uids.dispose);
    await opnieuw.loadCorrections();
    await opnieuw.loadPlaten();
    opnieuw.tracks.addAll([revolver, oublie]);
    opnieuw.rebuildAlbums();
    await HttpOverrides.runZoned(() => opnieuw.enrich(s), createHttpClient: (_) => throw StateError('geen net'));
    expect(tegel(opnieuw, _ml, 1985).correctedCover, h85);
    expect(tegel(opnieuw, _ml, 2001).correctedCover, isNull);

    // Samengevoegd: weer één tegel op de oude sleutel, met de hoes die daar gekozen was.
    await opnieuw.mergeEditions(tegel(opnieuw, _ml, 1985));
    await opnieuw.hoezenNaPlaatwissel;
    final samen = opnieuw.albums.singleWhere((a) => a.title == _ml);
    expect(samen.plaat, isNull);
    expect(samen.correctedCover, h01);
  });

  group('de digitale voorkant', () {
    late List<String> gevraagd;
    late MockClient deezer;
    setUp(() {
      gevraagd = [];
      deezer = MockClient((req) async {
        final u = req.url.toString();
        gevraagd.add(u);
        if (u.contains('/search/album')) {
          return http.Response(
              jsonEncode({
                'data': [
                  {'id': 109504, 'title': _ml, 'artist': {'name': _ml}, 'cover_xl': 'https://beeld.invalid/2001.jpg'},
                  {'id': 85, 'title': _ml, 'artist': {'name': _ml}, 'cover_xl': 'https://beeld.invalid/1985.jpg'},
                  {'id': 9, 'title': 'Les Duos De Marc', 'artist': {'name': _ml}, 'cover_xl': 'https://beeld.invalid/9.jpg'},
                ]
              }),
              200);
        }
        if (u.endsWith('/album/109504')) return http.Response(jsonEncode({'id': 109504, 'release_date': '2001-05-14'}), 200);
        if (u.endsWith('/album/85')) return http.Response(jsonEncode({'id': 85, 'release_date': '1985-09-01'}), 200);
        if (u.contains('beeld.invalid/2001')) return http.Response.bytes(_jpeg(2001), 200);
        if (u.contains('beeld.invalid/1985')) return http.Response.bytes(_jpeg(1985), 200);
        return http.Response('', 404);
      });
    });

    test('op naam niets voor een gedeelde naam; per plaat die van het juiste jaar', () async {
      final e = CoverEnricher(AppSettings(), client: deezer);
      CoverEnricher.gedeeldeNamen = {CoverEnricher.naamSleutel(_ml, _ml)};
      expect(await e.digitaleVoorkant(_ml, _ml), isNull);
      expect(gevraagd, isEmpty, reason: 'op naam is het een gok tussen twee platen');

      final a = await e.digitaleVoorkant(_ml, _ml, plaat: 'master:95856', jaar: 1985);
      expect(a?.bron, 'dz:85');
      expect(a?.bytes, _jpeg(1985));
      final b = await e.digitaleVoorkant(_ml, _ml, plaat: 'master:697091', jaar: 2001);
      expect(b?.bron, 'dz:109504');
      expect(b?.bytes, _jpeg(2001));
      expect(await e.digitaleVoorkant(_ml, _ml, plaat: 'master:1', jaar: 1993), isNull,
          reason: 'geen plaat uit dat jaar: geen digitale voorkant');

      // Op schijf onder de eigen sleutel, en daarna zonder net.
      final telling = gevraagd.length;
      final zonderNet = CoverEnricher(AppSettings(), client: MockClient((_) async => fail('niet nog eens vragen')));
      expect((await zonderNet.digitaleVoorkant(_ml, _ml, plaat: 'master:95856', jaar: 1985, netwerk: false))?.bron, 'dz:85');
      expect(gevraagd, hasLength(telling));
    });

    test('een gok op naam voor een gescheiden tegel wordt niet eens gevraagd', () async {
      final lib = await bib();
      final e = CoverEnricher(AppSettings(), client: deezer);
      expect(await e.fetchAndCache(tegel(lib, _ml, 1985)), isNull);
      expect(gevraagd, isEmpty);
    });

    test('kiezen op jaar: precies dezelfde titel eerst, en Deezer zegt "0000" als het niets weet', () {
      final data = [
        {'id': 1, 'title': '$_ml (Deluxe)', 'artist': {'name': _ml}},
        {'id': 2, 'title': _ml, 'artist': {'name': 'Iemand anders'}},
        {'id': 3, 'title': _ml, 'artist': {'name': _ml}},
      ];
      expect([for (final d in digitaleAlbumsMetNaam(data, _ml, _ml)) d['id']], [3, 1]);
      expect(deezerJaar('2001-05-14'), 2001);
      expect(deezerJaar('0000-00-00'), isNull);
      expect(deezerJaar(null), isNull);
    });
  });

  test('de hoesveger: elk bestand de hoes van zijn eigen plaat, en een tweede ronde schrijft niets', () async {
    final lib = await bib();
    final s = AppSettings();
    final h85 = _jpeg(85), h01 = _jpeg(1);
    lib.adoptAlbumCover(_ml, _ml, h85, from: 'rel:2436536', settings: s, plaat: 'master:95856');
    lib.adoptAlbumCover(_ml, _ml, h01, from: 'rel:1441911', settings: s, plaat: 'master:697091');
    final veger = HoesInBestandVeger(library: lib, tussenpoos: Duration.zero, startNa: const Duration(hours: 1));
    await veger.ronde();
    expect(readFlacPicture(File(revolver.path)).hoes, h85);
    expect(readFlacPicture(File(oublie.path)).hoes, h01);
    final log = File('${scratch.path}${sep}hoes_in_bestand.log');
    final geschreven = RegExp('geschreven').allMatches(log.readAsStringSync()).length;
    await veger.ronde();
    await veger.ronde();
    expect(RegExp('geschreven').allMatches(log.readAsStringSync()).length, geschreven,
        reason: '03-11-2026 schreef hij beide bestanden drie rondes na elkaar');
    expect(readFlacPicture(File(revolver.path)).hoes, h85);
  });

  test('het hartje gaat mee: naar beide platen bij het scheiden, en terug bij het samenvoegen', () async {
    final lib = await bib(platenBekend: false);
    final winkel = LanStateStore(File('${scratch.path}${sep}state.json'));
    final fav = Favorieten()..winkel = winkel;
    final samenId = albumIdFor(artistKey(_ml), normKey(_ml), null);
    expect(fav.idVanAlbum(lib.albums.firstWhere((a) => a.title == _ml)), samenId);
    await fav.wisselAlbum(lib.albums.firstWhere((a) => a.title == _ml));
    expect(fav.volgTegels(lib.albums), 0, reason: 'er is niets verschoven');

    schrijfJson('plaat_register.json', register);
    await lib.loadPlaten();
    lib.rebuildAlbums();
    expect(fav.volgTegels(lib.albums), 2);
    final m85 = tegel(lib, _ml, 1985), m01 = tegel(lib, _ml, 2001);
    expect(fav.isFavorietAlbum(m85), isTrue);
    expect(fav.isFavorietAlbum(m01), isTrue);
    expect(winkel.favoriteAlbums.contains(samenId), isFalse, reason: 'geen wees die het telgetal ophoogt');

    // Wie er zelf één weghaalt, ziet het niet terugkomen.
    await fav.wisselAlbum(m85);
    expect(fav.volgTegels(lib.albums), 0);
    expect(fav.isFavorietAlbum(tegel(lib, _ml, 1985)), isFalse);

    // Weer samen: de tegel zonder editie neemt het hartje van de plaat die er nog een had.
    await lib.mergeEditions(m01);
    expect(fav.volgTegels(lib.albums), 1);
    expect(fav.isFavorietAlbum(lib.albums.singleWhere((a) => a.title == _ml)), isTrue);
    expect(winkel.favoriteAlbums, {samenId});
    await winkel.save();
  });

  test('ook als de gedeelde staat pas na de tegels binnenkomt (de hartjes laden later dan de scan)', () async {
    final lib = await bib();
    final winkel = LanStateStore(File('${scratch.path}${sep}state.json'));
    final fav = Favorieten()..winkel = winkel;
    winkel.favoriteAlbums.add('iets-anders');
    expect(fav.volgTegels(lib.albums), 0);
    // Nu pas het hartje van de oude tegel, met dezelfde lijst tegels.
    winkel.favoriteAlbums.add(albumIdFor(artistKey(_ml), normKey(_ml), null));
    expect(fav.volgTegels(lib.albums), 2);
    expect(fav.isFavorietAlbum(tegel(lib, _ml, 1985)), isTrue);
    await winkel.save();
  });

  test('de opwarmer legt een digitale voorkant op zijn eigen tegel, en niet op de andere plaat', () async {
    final lib = await bib();
    final h85 = _jpeg(1985);
    final w = FactsWarmer(
      library: lib,
      settings: AppSettings(),
      mb: MusicBrainzService(),
      enabled: true,
      volledigTussen: Duration.zero,
      voorkant: (artist, album, titels) async => (bytes: h85, bron: 'dz:85'),
      resolve: (album, {required uid, required trackSetHash, required mb, required settings, pinnedMbid, pinned,
              discogs}) async =>
          AlbumFacts(
            uid: uid,
            trackSetHash: trackSetHash,
            source: 'MusicBrainz',
            mbid: 'mb-$uid',
            tracklist: const [ChoiceTrack('1', 'Elle a les yeux revolver', 220)],
          ),
      warmArt: (artist, album,
              {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async =>
          null,
    );
    await w.voorrang(revolver.path);
    expect(tegel(lib, _ml, 1985).resolvedCover, h85);
    expect(tegel(lib, _ml, 1985).resolvedFrom, 'dz:85');
    expect(tegel(lib, _ml, 2001).resolvedCover, isNull, reason: 'de hoes van 1985 hoort niet op de plaat van 2001');

    // En de scan van de vastgezette persing net zo: op de tegel van 2001, niet op die van 1985.
    final scan01 = _jpeg(2001);
    final w2 = FactsWarmer(
      library: lib,
      settings: AppSettings(),
      mb: MusicBrainzService(),
      enabled: true,
      volledigTussen: Duration.zero,
      voorkant: (artist, album, titels) async => null,
      resolve: (album, {required uid, required trackSetHash, required mb, required settings, pinnedMbid, pinned,
              discogs}) async =>
          AlbumFacts(
            uid: uid,
            trackSetHash: trackSetHash,
            source: 'MusicBrainz',
            mbid: 'mb-$uid',
            tracklist: const [ChoiceTrack('11', "J'ai tout oublié", 245)],
          ),
      warmArt: (artist, album,
              {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async =>
          ReleaseArt(front: scan01, bron: 'rel:$pinned'),
    );
    await w2.voorrang(oublie.path);
    expect(tegel(lib, _ml, 2001).resolvedCover, scan01);
    expect(tegel(lib, _ml, 1985).resolvedCover, h85);
  });

  test('de scans van de pc: elk toestel vraagt die van zijn eigen tegel, ook als ze tegelijk gevraagd worden', () async {
    final antwoord = {
      'master:95856': ReleaseArt(front: _jpeg(1), back: _jpeg(2), disc: _jpeg(3), bron: 'rel:2436536'),
      'master:697091': ReleaseArt(front: _jpeg(4), back: _jpeg(5), disc: _jpeg(6), bron: 'rel:1441911'),
    };
    final gevraagdMet = <String?>[];
    DiscogsArtwork.vanDePc = (artist, album, {bool klein = false, String? plaat}) async {
      gevraagdMet.add(plaat);
      return (art: antwoord[plaat]!, klaar: true);
    };
    addTearDown(() => DiscogsArtwork.vanDePc = null);
    // Een aangewezen voorkant houdt de digitale zoektocht (en dus het net) buiten deze toets.
    const rollen = {'front': 'https://scan.invalid/voor.jpg'};
    final d = DiscogsService(AppSettings());
    final a = d.releaseArt(_ml, _ml, roles: rollen, plaat: 'master:95856', jaar: 1985);
    final b = d.releaseArt(_ml, _ml, roles: rollen, plaat: 'master:697091', jaar: 2001);
    expect((await a)?.disc, antwoord['master:95856']!.disc);
    expect((await b)?.disc, antwoord['master:697091']!.disc, reason: 'niet meegelift op de keten van de andere plaat');
    expect(gevraagdMet.toSet(), {'master:95856', 'master:697091'});
  });

  test('aangesloten: de pc laat de hartjes volgen, het toestel vraagt de scans van zijn eigen tegel', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('library.addListener(() => favorieten.volgTegels(library.albums));'));
    expect(main, contains('a.artist == artist && a.title == album && a.plaat == plaat'));
    final server = File('lib/lan/server.dart').readAsStringSync();
    expect(server, contains('await library.clearAlbumArtRoles(rolArtiest, rolAlbum, plaat: rolPlaat);'));
    expect(server, contains('(body[\'url\'] ?? \'\') as String, plaat: rolPlaat);'));
    expect(server, contains('final rollen = library.albumArtRoles(al.artist, al.title, plaat: al.plaat);'));
    final catalogus = File('lib/lan/catalog.dart').readAsStringSync();
    expect(catalogus, contains("if (a.plaat != null) fingerprint.add('P\${a.plaat}');"));
  });
}
