// Scheiden op plaat (Saber, 03-11-2026: "Vanzelf, op de plaat"). Marc Lavoine heeft twee albums die "Marc Lavoine" heten:
// 1985 (Discogs-master 95856) en 2001 (master 697091). In zijn bibliotheek stonden "Elle a les yeux revolver" (vastgezet
// op 2436536, een cd uit 1987 van de plaat uit 1985) en "J'ai tout oublié" (vastgezet op 1441911, de cd uit 2001) op één
// tegel, met één uid. Hangen nummers met dezelfde naam aan persingen van verschillende PLATEN, dan krijgt elke plaat
// vanzelf een eigen tegel met het jaar van die plaat, en dat jaar komt ook in het bestand. Wat hij zelf samenvoegde
// blijft samen. Alles hier met een nep-opzoeker en een tijdelijke map: geen net, niets in de echte appmap.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/ids.dart' show albumIdFor;
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart' show artistKey, normKey;
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/plaat_indeling.dart';
import 'package:debridmusic/settings.dart';

/// Een kleine maar echte FLAC: STREAMINFO, VORBIS_COMMENT, PADDING en wat "audio" — genoeg voor de tagschrijver.
Uint8List _flac(Map<String, String> tags) {
  final out = BytesBuilder()..add(ascii.encode('fLaC'));
  void blok(int soort, List<int> inhoud, bool laatste) {
    out.add([(laatste ? 0x80 : 0) | soort, (inhoud.length >> 16) & 0xFF, (inhoud.length >> 8) & 0xFF, inhoud.length & 0xFF]);
    out.add(inhoud);
  }

  final si = Uint8List(34);
  const rate = 44100;
  si[10] = (rate >> 12) & 0xFF;
  si[11] = (rate >> 4) & 0xFF;
  si[12] = ((rate & 0x0F) << 4) | (1 << 1);
  si[14] = 0x02;
  blok(0, si, false);
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  final ven = utf8.encode('reference libFLAC 1.3.2');
  u32(ven.length);
  b.add(ven);
  u32(tags.length);
  for (final e in tags.entries) {
    final c = utf8.encode('${e.key}=${e.value}');
    u32(c.length);
    b.add(c);
  }
  blok(4, b.toBytes(), false);
  blok(1, List.filled(64, 0), true);
  out.add(List.filled(4096, 0x7F));
  return out.toBytes();
}

/// Een nep-opzoeker: wat hij weet staat in [antwoorden], en hij onthoudt wat er gevraagd werd.
class _Nep {
  _Nep(this.antwoorden);
  final Map<String, PlaatFeit?> antwoorden;
  final gevraagd = <String>[];
  Future<PlaatFeit?> call(String pin) async {
    gevraagd.add(pin);
    return antwoorden[pin];
  }
}

void main() {
  late Directory scratch;
  late String muziek;
  final sep = Platform.pathSeparator;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_op_plaat_');
    setAppDirForTest(scratch.path);
    muziek = '${scratch.path}${sep}muziek';
  });
  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Een nummer, met een echt bestand eronder (zodat het jaartal geschreven kan worden).
  Track nummer(String rel, String titel, int? jaar, {String album = 'Marc Lavoine', String artiest = 'Marc Lavoine'}) {
    final pad = '$muziek$sep${rel.replaceAll('/', sep)}';
    File(pad)
      ..createSync(recursive: true)
      ..writeAsBytesSync(_flac({
        'TITLE': titel,
        'ARTIST': artiest,
        'ALBUM': album,
        if (jaar != null) 'DATE': '$jaar',
      }));
    return Track(path: pad, title: titel, artist: artiest, album: album, year: jaar, isFlac: true);
  }

  Future<LibraryStore> maak(List<Track> ts, Map<Track, String> pins, {_Nep? nep}) async {
    File('${scratch.path}${sep}corrections.json').writeAsStringSync(jsonEncode({
      for (final e in pins.entries)
        e.key.path: {
          'artist': e.key.artist,
          'album': e.key.album,
          if (e.value.startsWith('mb:')) 'mbid': e.value.substring(3) else 'release': e.value.substring(8),
        },
    }));
    final lib = LibraryStore()..configDirOverride = scratch.path;
    addTearDown(lib.uids.dispose);
    await lib.loadCorrections();
    await lib.loadPlaten();
    await lib.loadMerged();
    lib.plaatOpzoeker = nep?.call;
    lib.tracks.addAll(ts);
    lib.rebuildAlbums();
    return lib;
  }

  List<Album> tegels(LibraryStore lib, [String titel = 'Marc Lavoine']) =>
      lib.albums.where((a) => a.title == titel).toList()..sort((a, b) => (a.year ?? 0).compareTo(b.year ?? 0));

  String titels(Album a) => [for (final t in a.tracks) t.title].join(' + ');

  const lavoine1985 = PlaatFeit('master:95856', 1985);
  const lavoine2001 = PlaatFeit('master:697091', 2001);

  test('Marc Lavoine: twee masters worden twee tegels, elk met het jaar van de plaat, een eigen id en een eigen uid',
      () async {
    final revolver = nummer('Compilaties/Marc Lavoine/Best Of 85-95/02 - Elle a les yeux revolver.flac',
        'Elle a les yeux revolver', 1994);
    final oublie = nummer("Albums/Marc Lavoine/Marc Lavoine/11 - J'ai tout oublié.flac", "J'ai tout oublié", 1985);
    final nep = _Nep({'discogs:2436536': lavoine1985, 'discogs:1441911': lavoine2001});
    final lib = await maak([revolver, oublie], {revolver: 'discogs:2436536', oublie: 'discogs:1441911'}, nep: nep);

    // Voor het antwoord er is: één tegel, zoals het was — onbekend is geen reden om te splitsen.
    expect(tegels(lib), hasLength(1));
    final oudeUid = lib.uidOf(tegels(lib).single);
    expect(oudeUid, isNotEmpty);

    await lib.zoekPlatenOp();
    expect(nep.gevraagd.toSet(), {'discogs:2436536', 'discogs:1441911'});
    final twee = tegels(lib);
    expect(twee, hasLength(2));
    expect([for (final a in twee) titels(a)], ['Elle a les yeux revolver', "J'ai tout oublié"]);
    expect([for (final a in twee) a.year], [1985, 2001], reason: 'het masterjaar, niet dat van de persing of de tags');
    expect([for (final a in twee) a.edition], ['1985', '2001']);
    final ids = {for (final a in twee) albumIdFor(artistKey(a.artist), normKey(a.title), a.edition)};
    expect(ids, hasLength(2), reason: 'met één id voegt een toestel ze weer samen');
    final uids = {for (final a in twee) lib.uidOf(a)};
    expect(uids, hasLength(2), reason: 'de feiten en scans van de ene plaat mogen niet op de andere landen');
    expect(uids.contains(oudeUid), isTrue, reason: 'één van de twee houdt zijn naam; de ander krijgt een nieuwe');
    for (final a in twee) {
      expect([for (final t in LibraryNormalise(lib).recordTracks(a)) t.title], [a.tracks.single.title],
          reason: 'de andere plaat is geen persing van deze ("Tags gelijktrekken" zou hem mee hernummeren)');
    }

    // En de jaartallen in de bestanden, mét de weg terug.
    expect(readFlacRawFields(File(revolver.path))['date'], '1985');
    expect(readFlacRawFields(File(oublie.path))['date'], '2001');
    final undo = jsonDecode(File('${scratch.path}${sep}tag_undo.json').readAsStringSync()) as Map<String, dynamic>;
    expect((undo[revolver.path] as Map)['DATE'], '1994');
    expect((undo[oublie.path] as Map)['DATE'], '1985');
    expect({for (final t in lib.tracks) t.title: t.year}, {'Elle a les yeux revolver': 1985, "J'ai tout oublié": 2001});

    // Het antwoord staat op schijf: na een herstart meteen twee tegels, zonder iets op te zoeken.
    final opnieuw = LibraryStore()..configDirOverride = scratch.path;
    addTearDown(opnieuw.uids.dispose);
    await opnieuw.loadCorrections();
    await opnieuw.loadPlaten();
    opnieuw.tracks.addAll([revolver, oublie]);
    opnieuw.rebuildAlbums();
    expect(tegels(opnieuw).map((a) => a.edition), ['1985', '2001']);
  });

  test('vanzelf: na een herbouw zoekt de pc het zelf op, zonder dat iemand erom vraagt', () async {
    final revolver = nummer('Compilaties/Best Of/02 - Elle a les yeux revolver.flac', 'Elle a les yeux revolver', 1994);
    final oublie = nummer("Albums/Marc Lavoine/Marc Lavoine/11 - J'ai tout oublié.flac", "J'ai tout oublié", 1985);
    final nep = _Nep({'discogs:2436536': lavoine1985, 'discogs:1441911': lavoine2001});
    final lib = await maak([revolver, oublie], {revolver: 'discogs:2436536', oublie: 'discogs:1441911'}, nep: nep);
    for (var i = 0; i < 250 && readFlacRawFields(File(oublie.path))['date'] != '2001'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(tegels(lib).map((a) => a.edition), ['1985', '2001']);
    expect(readFlacRawFields(File(oublie.path))['date'], '2001');
    await lib.zoekPlatenOp(); // de ronde netjes laten uitlopen voordat de map weg gaat
  });

  test('twee persingen van dezelfde master blijven één tegel, en er wordt niets geschreven', () async {
    final a = nummer('Albums/Marc Lavoine/Marc Lavoine/01 - Le Parking des anges.flac', 'Le Parking des anges', 1987);
    final b = nummer('Albums/Marc Lavoine/Marc Lavoine/04 - Elle a les yeux revolver.flac', 'Elle a les yeux revolver', 1985);
    final nep = _Nep({'discogs:2436536': lavoine1985, 'discogs:111': lavoine1985});
    final lib = await maak([a, b], {a: 'discogs:111', b: 'discogs:2436536'}, nep: nep);
    await lib.zoekPlatenOp();
    expect(nep.gevraagd.toSet(), {'discogs:111', 'discogs:2436536'});
    expect(tegels(lib), hasLength(1));
    expect(tegels(lib).single.edition, isNull);
    expect(readFlacRawFields(File(a.path))['date'], '1987', reason: 'alleen op een gescheiden plaat gaat het jaar het bestand in');
  });

  test('eerst gescheiden en dan samengevoegd: één tegel, en dat blijft zo, ook na een herstart', () async {
    final revolver = nummer('Compilaties/Best Of/02 - Elle a les yeux revolver.flac', 'Elle a les yeux revolver', 1994);
    final oublie = nummer("Albums/Marc Lavoine/Marc Lavoine/11 - J'ai tout oublié.flac", "J'ai tout oublié", 1985);
    final pins = {revolver: 'discogs:2436536', oublie: 'discogs:1441911'};
    final nep = _Nep({'discogs:2436536': lavoine1985, 'discogs:1441911': lavoine2001});
    final lib = await maak([revolver, oublie], pins, nep: nep);
    await lib.zoekPlatenOp();
    expect(tegels(lib), hasLength(2));
    await lib.mergeEditions(tegels(lib).first);
    expect(tegels(lib), hasLength(1));
    lib.rebuildAlbums();
    await lib.zoekPlatenOp();
    expect(tegels(lib), hasLength(1));
    expect(lib.isMerged(tegels(lib).single), isTrue);
    expect(tegels(lib).single.edition, isNull);

    // Herstart: samenvoeging én register staan op schijf, en de samenvoeging wint.
    final opnieuw = await maak([revolver, oublie], pins, nep: _Nep({}));
    expect(tegels(opnieuw), hasLength(1));
  });

  test('samengevoegd voordat de platen bekend waren: er wordt niet eens gezocht', () async {
    final revolver = nummer('Compilaties/Best Of/02 - Elle a les yeux revolver.flac', 'Elle a les yeux revolver', 1994);
    final oublie = nummer("Albums/Marc Lavoine/Marc Lavoine/11 - J'ai tout oublié.flac", "J'ai tout oublié", 1985);
    final lib = await maak([revolver, oublie], {revolver: 'discogs:2436536', oublie: 'discogs:1441911'});
    await lib.mergeEditions(tegels(lib).single);
    final nep = _Nep({'discogs:2436536': lavoine1985, 'discogs:1441911': lavoine2001});
    lib.plaatOpzoeker = nep.call;
    lib.rebuildAlbums();
    await lib.zoekPlatenOp();
    expect(tegels(lib), hasLength(1));
    expect(nep.gevraagd, isEmpty);
    expect(readFlacRawFields(File(revolver.path))['date'], '1994');
  });

  test('een nummer zonder pin gaat naar de plaat met zijn jaar, anders naar de grootste', () async {
    final p85 = nummer('A/01 - Pas besoin de toi.flac', 'Pas besoin de toi', 1987);
    final p01a = nummer('B/01 - Le Pont Mirabeau.flac', 'Le Pont Mirabeau', 2001);
    final p01b = nummer('B/02 - Toi mon amour.flac', 'Toi mon amour', 2001);
    final los85 = nummer('C/03 - Lunatique.flac', 'Lunatique', 1985);
    final losZonder = nummer('C/04 - Zonder jaar.flac', 'Zonder jaar', null);
    final losAnders = nummer('C/05 - Ander jaar.flac', 'Ander jaar', 1999);
    final nep = _Nep({'discogs:1': lavoine1985, 'discogs:2': lavoine2001, 'discogs:3': lavoine2001});
    final lib = await maak([p85, p01a, p01b, los85, losZonder, losAnders],
        {p85: 'discogs:1', p01a: 'discogs:2', p01b: 'discogs:3'},
        nep: nep);
    await lib.zoekPlatenOp();
    final twee = tegels(lib);
    expect(twee.map((a) => a.edition), ['1985', '2001']);
    expect(twee.first.tracks.map((t) => t.title).toSet(), {'Pas besoin de toi', 'Lunatique'});
    expect(twee.last.tracks.map((t) => t.title).toSet(), {'Le Pont Mirabeau', 'Toi mon amour', 'Zonder jaar', 'Ander jaar'});
    expect(readFlacRawFields(File(p85.path))['date'], '1985');
    expect(readFlacRawFields(File(losAnders.path))['date'], '1999', reason: 'zonder pin is de plaat een gok: niet schrijven');
    expect(readFlacRawFields(File(losZonder.path))['date'], isNull);
  });

  test('binnen één plaat blijven botsende uitgaves gescheiden, en een MusicBrainz-pin telt net zo goed', () async {
    Track metNr(String rel, String titel, int nr, int totaal) {
      final t = nummer(rel, titel, 1985);
      return Track(path: t.path, title: titel, artist: t.artist, album: t.album, year: 1985, trackNo: nr, trackTotal: totaal);
    }

    final a12 = metNr('A/01 - Pas besoin de toi.flac', 'Pas besoin de toi', 1, 12);
    final a14 = metNr('B/01 - Pas besoin de toi.flac', 'Pas besoin de toi', 1, 14);
    final b = nummer('C/11 - J ai tout oublie.flac', "J'ai tout oublié", 2001);
    final nep = _Nep({
      'discogs:2436536': lavoine1985,
      'mb:9a98c78d-0000-4000-8000-000000002001': const PlaatFeit('rg:9a98c78d-831e-3c6f-a467-767e50ca89b5', 2001),
    });
    final lib = await maak([a12, a14, b],
        {a12: 'discogs:2436536', a14: 'discogs:2436536', b: 'mb:9a98c78d-0000-4000-8000-000000002001'},
        nep: nep);
    await lib.zoekPlatenOp();
    expect(tegels(lib).map((a) => a.edition).toSet(), {'1985 · 12 nummers', '1985 · 14 nummers', '2001'});
  });

  test('is de plaat van één persing onbekend, dan blijft het één tegel (en de ronde loopt niet eeuwig door)', () async {
    final revolver = nummer('Compilaties/Best Of/02 - Elle a les yeux revolver.flac', 'Elle a les yeux revolver', 1994);
    final oublie = nummer("Albums/Marc Lavoine/Marc Lavoine/11 - J'ai tout oublié.flac", "J'ai tout oublié", 1985);
    final nep = _Nep({'discogs:2436536': lavoine1985, 'discogs:1441911': null});
    final lib = await maak([revolver, oublie], {revolver: 'discogs:2436536', oublie: 'discogs:1441911'}, nep: nep);
    await lib.zoekPlatenOp();
    expect(tegels(lib), hasLength(1));
    expect(readFlacRawFields(File(revolver.path))['date'], '1994');
    lib.rebuildAlbums();
    await lib.zoekPlatenOp();
    expect(nep.gevraagd.where((p) => p == 'discogs:1441911'), hasLength(1), reason: 'één keer per sessie, niet bij elke herbouw');
  });

  test('zonder opzoeker (een toestel, elke andere toets) wordt niets gevraagd en niets gesplitst', () async {
    final revolver = nummer('Compilaties/Best Of/02 - Elle a les yeux revolver.flac', 'Elle a les yeux revolver', 1994);
    final oublie = nummer("Albums/Marc Lavoine/Marc Lavoine/11 - J'ai tout oublié.flac", "J'ai tout oublié", 1985);
    final lib = await maak([revolver, oublie], {revolver: 'discogs:2436536', oublie: 'discogs:1441911'});
    await lib.zoekPlatenOp();
    expect(tegels(lib), hasLength(1));
    expect(readFlacRawFields(File(oublie.path))['date'], '1985');
  });

  group('welke platen verschillen', () {
    test('Discogs-master naast MusicBrainz-groep: pas verschillend bij twee jaar uiteen', () {
      expect(zelfdePlaat(const PlaatFeit('master:95856', 1985), const PlaatFeit('rg:fee0a356', 1985)), isTrue);
      expect(zelfdePlaat(const PlaatFeit('master:95856', 1985), const PlaatFeit('rg:9a98c78d', 2001)), isFalse);
      expect(zelfdePlaat(const PlaatFeit('master:95856', 1985), const PlaatFeit('rg:x', null)), isTrue,
          reason: 'onbekend jaar: liever niet splitsen');
    });

    test('twee masters zijn twee platen, ook in hetzelfde jaar; twee groepen ook', () {
      expect(zelfdePlaat(const PlaatFeit('master:1', 1977), const PlaatFeit('master:2', 1977)), isFalse);
      expect(zelfdePlaat(const PlaatFeit('rg:a', 1977), const PlaatFeit('rg:b', 1978)), isFalse);
    });

    test("Betty 'Come To Me': een persing zonder master (2001) naast master 2918149 (2000) is één plaat", () {
      final a = Track(path: '/a.flac', title: 'Come To Me', artist: 'Betty', album: 'Come To Me', year: 2001);
      final b = Track(path: '/b.flac', title: 'Come To Me (Radio)', artist: 'Betty', album: 'Come To Me', year: 2000);
      final uit = deelOpPlaat([a, b],
          pinVan: (t) => t == a ? 'discogs:1067694' : 'discogs:1756040',
          feitVan: (p) => p == 'discogs:1067694'
              ? const PlaatFeit('release:1067694', 2001)
              : const PlaatFeit('master:2918149', 2000));
      expect(uit.indeling, isNull);
      expect(uit.onbekend, isEmpty);
    });

    test('dezelfde jaren bij twee platen: het nummer van de plaat komt in de editie, zodat de ids verschillen', () {
      final a = Track(path: '/a.flac', title: 'A', artist: 'X', album: 'X', year: 1977);
      final b = Track(path: '/b.flac', title: 'B', artist: 'X', album: 'X', year: 1977);
      final uit = deelOpPlaat([a, b],
          pinVan: (t) => t == a ? 'discogs:1' : 'discogs:2',
          feitVan: (p) => p == 'discogs:1' ? const PlaatFeit('master:10', 1977) : const PlaatFeit('master:20', 1977));
      final edities = {for (final g in uit.indeling!.groepen.values) g.editie};
      expect(edities, {'1977 · plaat 10', '1977 · plaat 20'});
    });
  });

  test('het jaar van de plaat (1985), niet dat van de persing (1987) — Discogs en MusicBrainz, uit de cache, zonder net',
      () async {
    void leg(String map, String url, Map<String, dynamic> body) {
      final d = Directory('${scratch.path}$sep$map')..createSync(recursive: true);
      File('${d.path}$sep${sha1.convert(utf8.encode(url))}.json').writeAsStringSync(jsonEncode(body));
    }

    leg('discogs', 'https://api.discogs.com/releases/2436536', {'id': 2436536, 'master_id': 95856, 'year': 1987});
    leg('discogs', 'https://api.discogs.com/masters/95856', {'id': 95856, 'year': 1985});
    leg('discogs', 'https://api.discogs.com/releases/1067694', {'id': 1067694, 'year': 2001});
    const mbid = '0b3c2a1d-0000-4000-8000-000000001987';
    leg('musicbrainz', 'https://musicbrainz.org/ws/2/release/$mbid?fmt=json&inc=recordings+artist-credits+labels+release-groups', {
      'id': mbid,
      'title': 'Marc Lavoine',
      'date': '1987-03-01',
      'release-group': {'id': 'fee0a356-d014-4a5b-81e1-ca4c6b94ba78', 'first-release-date': '1985'},
    });
    final s = AppSettings()..discogsToken = 'proef';
    await HttpOverrides.runZoned(() async {
      final zoek = plaatOpzoekerVoor(s);
      final a = await zoek('discogs:2436536');
      expect(a?.plaat, 'master:95856');
      expect(a?.jaar, 1985);
      final b = await zoek('discogs:1067694');
      expect(b?.plaat, 'release:1067694', reason: 'een persing zonder master is haar eigen plaat');
      expect(b?.jaar, 2001);
      expect(await DiscogsService(s).plaatVan(2436536), (master: 95856, jaar: 1985));
      final c = await zoek('mb:$mbid');
      expect(c?.plaat, 'rg:fee0a356-d014-4a5b-81e1-ca4c6b94ba78');
      expect(c?.jaar, 1985);
    }, createHttpClient: (_) => throw StateError('geen net in deze toets'));
  });

  test('een toestel krijgt dezelfde twee tegels, met het jaar van de plaat — ook als het bestand dat nog niet zegt',
      () async {
    // .m4a: daar schrijft de app geen tags in, dus de nummers houden hun verkeerde jaar en alleen de plaat weet beter.
    Track m4a(String rel, String titel, int jaar) {
      final pad = '$muziek$sep${rel.replaceAll('/', sep)}';
      File(pad)
        ..createSync(recursive: true)
        ..writeAsBytesSync([0, 0, 0, 0]);
      return Track(path: pad, title: titel, artist: 'Marc Lavoine', album: 'Marc Lavoine', year: jaar);
    }

    final revolver = m4a('Compilaties/Best Of/02 - Elle a les yeux revolver.m4a', 'Elle a les yeux revolver', 1994);
    final oublie = m4a('Albums/Marc Lavoine/Marc Lavoine/11 - J ai tout oublie.m4a', "J'ai tout oublié", 1985);
    final nep = _Nep({'discogs:2436536': lavoine1985, 'discogs:1441911': lavoine2001});
    final pc = await maak([revolver, oublie], {revolver: 'discogs:2436536', oublie: 'discogs:1441911'}, nep: nep);
    pc.rootPath = muziek;
    await pc.zoekPlatenOp();
    expect(tegels(pc).map((a) => a.year), [1985, 2001]);
    expect({for (final t in pc.tracks) t.year}, {1994, 1985}, reason: 'in een .m4a schrijft de app niets');

    final catalogus = LanCatalog(pc);
    final mock = MockClient((req) async {
      if (req.url.path != '/api/catalog') return http.Response('', 404);
      final snap = catalogus.snapshot();
      return http.Response.bytes(snap.json, 200, headers: {'etag': snap.etag});
    });
    final toestel = LibraryStore()
      ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.216:47820'), token: 'geheim'),
          client: mock);
    addTearDown(toestel.stopHoesHerkansing);
    expect(await toestel.loadRemote(), isTrue);
    final daar = tegels(toestel);
    expect([for (final a in daar) a.edition], ['1985', '2001']);
    expect([for (final a in daar) a.year], [1985, 2001]);
    expect([for (final a in daar) titels(a)], ['Elle a les yeux revolver', "J'ai tout oublié"]);
  });

  test('de pc zoekt op, een toestel neemt het jaar van de pc over', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('await library.loadPlaten();'));
    expect(main, contains('library.plaatOpzoeker = plaatOpzoekerVoor(settings);'));
    final lib = File('lib/library.dart').readAsStringSync();
    expect(lib, contains('..plaatJaar = dto.year'));
  });
}
