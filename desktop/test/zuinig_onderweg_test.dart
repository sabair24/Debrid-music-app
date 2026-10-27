// Zuinig onderweg (Saber, 27-10-2026: "Ja doe maar, en kijk ook eens hoe tidal en Spotify dit doen, om kwaliteit van de
// liedjes te houden, en toch zuinig te zijn, cache geheugen??"): de wachtrij alleen als hij verandert, grote antwoorden
// ingepakt, de catalogus onderweg hoogstens om de vijf minuten, en een cache van nummers op het toestel.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/lan/certificaat.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/doorgever.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/range.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/stroomcache.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'hulp_tls.dart';

Map<String, dynamic> _progress(List<String> rij, {String? merk, int at = 1000, bool zonderRij = false}) => {
      'type': 'progress',
      'trackId': rij.first,
      'positionMs': 1000,
      if (!zonderRij) 'queue': rij,
      if (merk != null) 'queueMerk': merk,
      'index': 0,
      'playing': true,
      'at': at,
    };

void main() {
  group('de wachtrij alleen als hij verandert', () {
    final rij = [for (var i = 0; i < 1805; i++) 'id${i.toString().padLeft(6, '0')}'];

    test('het merkteken: zelfde rij, zelfde merk; één nummer anders, ander merk', () {
      expect(rijMerk(rij), rijMerk([...rij]));
      expect(rijMerk(rij), isNot(rijMerk([...rij]..[100] = 'anders')));
      expect(rijMerk(rij), startsWith('1805-'));
    });

    test('DE KERN: een stand met alleen het merkteken houdt de rij van de vorige keer', () {
      final dir = Directory.systemTemp.createTempSync('dm_rij_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final s = LanStateStore(File('${dir.path}/state.json'));
      final a = s.applyOps([_progress(rij, merk: rijMerk(rij))], deviceId: 'gsm', deviceName: 'S26');
      expect(a['rijApart'], 1, reason: 'zo weet het toestel dat het mag');
      final b = s.applyOps([_progress(rij, merk: rijMerk(rij), at: 6000, zonderRij: true)], deviceId: 'gsm', deviceName: 'S26');
      expect(b['rijNodig'], isNull);
      expect(s.progress.queue, rij);
      expect(s.progress.positionMs, 1000);
      // Een merkteken dat de pc niet kent (na een herstart): hij vraagt de rij.
      final leeg = LanStateStore(File('${dir.path}/state2.json'));
      expect(leeg.applyOps([_progress(rij, merk: rijMerk(rij), zonderRij: true)], deviceId: 'gsm')['rijNodig'], 1);
    });

    test('de stand voor wie de rij al heeft: zonder rij, met merkteken', () {
      final p = PlaybackProgress(trackId: rij.first, queue: rij);
      final vol = standVoor(p);
      expect(vol['queue'], rij);
      final kaal = standVoor(p, heeftAl: rijMerk(rij));
      expect(kaal.containsKey('queue'), isFalse);
      expect(kaal['rijMerk'], rijMerk(rij));
      expect(jsonEncode(kaal).length, lessThan(1000), reason: 'was 48 KB');
      expect(standVoor(p, heeftAl: 'iets-anders')['queue'], rij);
    });

    test('DE KERN: het toestel zet de rij terug, en een onbekend merkteken laat de stand zoals hij is', () {
      final g = RijGeheugen();
      final vol = g.herstel(standVoor(PlaybackProgress(trackId: 'a', queue: rij)))!;
      expect(g.merk, rijMerk(rij));
      expect(vol['queue'], rij);
      final terug = g.herstel(standVoor(PlaybackProgress(trackId: 'b', queue: rij), heeftAl: g.merk))!;
      expect(terug['queue'], rij);
      expect(terug['trackId'], 'b');
      final vreemd = g.herstel({'trackId': 'c', 'rijMerk': '3-abc'})!;
      expect(vreemd.containsKey('queue'), isFalse);
    });
  });

  group('de pc: kleinere antwoorden', () {
    late Directory root;
    late LanServer server;
    late String base;
    final client = HttpClient()..autoUncompress = false;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('dm_zuinig_');
      final f = File('${root.path}/01 Mysterons.flac')..writeAsBytesSync(List<int>.generate(4096, (i) => i % 256));
      final library = LibraryStore()..rootPath = root.path;
      library.tracks.add(Track(
          path: f.path,
          title: 'Mysterons',
          artist: 'Portishead',
          album: 'Dummy',
          trackNo: 1,
          isFlac: true,
          sizeBytes: 4096,
          sampleRate: 44100,
          bitsPerSample: 16));
      library.rebuildAlbums();
      server = LanServer(
          library: library,
          token: 'test-token',
          state: LanStateStore(File('${root.path}/state.json')),
          pairing: PairingStore(),
          port: 0,
          version: '1');
      expect(await server.start(), isNull);
      base = 'http://127.0.0.1:${server.boundPort}';
    });
    tearDown(() async {
      await server.dispose();
      root.deleteSync(recursive: true);
    });

    Future<HttpClientResponse> get(String pad, {Map<String, String>? koppen}) async {
      final req = await client.getUrl(Uri.parse('$base$pad'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer test-token');
      koppen?.forEach(req.headers.set);
      return req.close();
    }

    test('DE KERN: de speelstand zonder rij voor wie hem al heeft', () async {
      final rij = [for (var i = 0; i < 1000; i++) 'id$i'];
      server.state.applyOps([_progress(rij)], deviceId: 'tv', deviceName: 'Tv');
      final rev = server.state.rev;
      final vol = jsonDecode(await (await get('/api/state?since=$rev')).transform(utf8.decoder).join());
      expect((vol['progress'] as Map)['queue'], hasLength(1000));
      final merk = (vol['progress'] as Map)['rijMerk'] as String;
      final kaal = jsonDecode(await (await get('/api/state?since=$rev&rijMerk=$merk')).transform(utf8.decoder).join());
      expect((kaal['progress'] as Map).containsKey('queue'), isFalse);
      expect((kaal['progress'] as Map)['rijMerk'], merk);
    });

    test('een groot JSON-antwoord gaat ingepakt naar wie gzip vraagt', () async {
      final rij = [for (var i = 0; i < 2000; i++) 'id$i'];
      server.state.applyOps([_progress(rij)], deviceId: 'tv', deviceName: 'Tv');
      final ingepakt = await get('/api/state', koppen: {HttpHeaders.acceptEncodingHeader: 'gzip'});
      expect(ingepakt.headers.value(HttpHeaders.contentEncodingHeader), 'gzip');
      final bytes = await ingepakt.fold<List<int>>([], (a, b) => a..addAll(b));
      final kaal = await get('/api/state', koppen: {HttpHeaders.acceptEncodingHeader: 'identity'});
      expect(kaal.headers.value(HttpHeaders.contentEncodingHeader), isNull);
      final kaalBytes = await kaal.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(bytes.length, lessThan(kaalBytes.length ~/ 3));
      expect(utf8.decode(gzip.decode(bytes)), utf8.decode(kaalBytes));
    });

    test('DE KERN: onderweg alleen het merkteken van de catalogus, zonder de catalogus', () async {
      final eerst = await get('/api/catalog');
      final etag = eerst.headers.value(HttpHeaders.etagHeader)!;
      await eerst.drain<void>();
      final zelfde = await get('/api/catalog?alleenMerk=1', koppen: {HttpHeaders.ifNoneMatchHeader: etag});
      expect(zelfde.statusCode, 304);
      await zelfde.drain<void>();
      final anders = await get('/api/catalog?alleenMerk=1', koppen: {HttpHeaders.ifNoneMatchHeader: '"oud"'});
      expect(anders.statusCode, 200);
      expect(anders.headers.value('x-alleen-merk'), '1');
      expect(anders.headers.value(HttpHeaders.etagHeader), etag);
      expect(await anders.fold<int>(0, (n, b) => n + b.length), 0);
    });
  });

  test('de client: een uitgestelde catalogus komt niet binnen, het merkteken blijft', () async {
    final c = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://pc'), token: 't'),
        client: MockClient((req) async {
      expect(req.url.queryParameters['alleenMerk'], '1');
      return http.Response('', 200, headers: {'etag': '"nieuw"', 'x-alleen-merk': '1'});
    }));
    final r = await c.catalog(etag: '"oud"', alleenMerk: true);
    expect(r.uitgesteld, isTrue);
    expect(r.catalog, isNull);
  });

  group('de cache van nummers', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_stroomcache_'));
    tearDown(() => map.deleteSync(recursive: true));

    Future<void> leg(Stroomcache c, String wat, int n) async {
      final s = c.begin(wat)!;
      s.add(Uint8List(n));
      await c.klaar(wat, s, totaal: n, etag: '"e"', soort: 'audio/flac');
    }

    test('bewaren en vinden; de vraag hoort bij de sleutel (thuis het origineel, onderweg de cd)', () async {
      final c = Stroomcache(map.path);
      await leg(c, '/stream/a.flac?maxRate=44100&maxBits=16', 1000);
      expect(c.zoek('/stream/a.flac?maxRate=44100&maxBits=16')?.totaal, 1000);
      expect(c.zoek('/stream/a.flac'), isNull, reason: 'het origineel is een ander adres');
    });

    test('een half stuk wordt niet bewaard', () async {
      final c = Stroomcache(map.path);
      final s = c.begin('/stream/b.flac')!;
      s.add(Uint8List(10));
      await c.laatVallen('/stream/b.flac', s);
      expect(c.zoek('/stream/b.flac'), isNull);
      final s2 = c.begin('/stream/b.flac')!;
      s2.add(Uint8List(10));
      await c.klaar('/stream/b.flac', s2, totaal: 20);
      expect(c.zoek('/stream/b.flac'), isNull, reason: 'minder dan het totaal');
    });

    test('DE KERN: boven de grens gaat het langst niet gebruikte eerst weg', () async {
      final c = Stroomcache(map.path, maxBytes: 2500);
      await leg(c, '/stream/1.flac', 1000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await leg(c, '/stream/2.flac', 1000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.zoek('/stream/1.flac'), isNotNull, reason: 'nu het recentst gebruikt');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await leg(c, '/stream/3.flac', 1000);
      expect(c.zoek('/stream/2.flac'), isNull);
      expect(c.zoek('/stream/1.flac'), isNotNull);
      expect(c.zoek('/stream/3.flac'), isNotNull);
      expect(c.grootte, 2000);
    });
  });

  test('DE KERN: de doorgever haalt een nummer één keer van de pc; daarna komt het van de eigen schijf, ook met Range',
      () async {
    final map = Directory.systemTemp.createTempSync('dm_doorgever_cache_');
    final f = File('${map.path}${Platform.pathSeparator}n.flac')
      ..writeAsBytesSync(Uint8List.fromList(List<int>.generate(300 * 1024, (i) => i % 251)));
    var vragen = 0;
    final pc = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, proefCertificaat.context());
    pc.listen((req) {
      if (req.method == 'GET') vragen++;
      serveFile(req, f, contentType: 'audio/flac');
    });
    final geleverd = <int>[], uitCache = <int>[];
    final d = Doorgever(
        cache: Stroomcache('${map.path}${Platform.pathSeparator}cache'),
        geleverd: (_, n) => geleverd.add(n),
        uitCache: (_, n) => uitCache.add(n));
    await d.start();
    d.zetBron(DoorgeverBron(basis: Uri.parse('https://127.0.0.1:${pc.port}'), sleutel: 's', pin: proefCertificaat.pin));
    addTearDown(() async {
      await d.stop();
      await pc.close(force: true);
      map.deleteSync(recursive: true);
    });
    final adres = d.adresVoor(Uri.parse('http://pc.invalid/stream/ab12.flac?maxRate=44100'));
    final c = HttpClient();
    Future<List<int>> vraag({String? range}) async {
      final r = await c.getUrl(adres);
      if (range != null) r.headers.set(HttpHeaders.rangeHeader, range);
      final res = await r.close();
      return res.fold<List<int>>([], (a, b) => a..addAll(b));
    }

    expect(await vraag(range: 'bytes=0-'), f.readAsBytesSync());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(vragen, 1);
    expect(geleverd, [300 * 1024]);
    // Nu zonder de pc: herhalen, en spoelen.
    expect(await vraag(), f.readAsBytesSync());
    expect(await vraag(range: 'bytes=1000-1999'), f.readAsBytesSync().sublist(1000, 2000));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(vragen, 1, reason: 'niets meer van de pc; alleen een HEAD om na te kijken');
    expect(uitCache, [300 * 1024, 1000]);
    c.close(force: true);
  });

  test('aangesloten: de gsm stuurt de rij alleen als hij veranderde; de cache en de catalogus onderweg', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final main = bron('lib/main.dart');
    expect(main, contains("              if (!zonderRij) 'queue': rij,"));
    expect(main, contains("    session.stroomcacheMap = '\$appDir\${Platform.pathSeparator}stroomcache';"));
    expect(main, contains('  library.zuinigeCatalogus = () => netStore.onderweg;'));
    expect(main, contains('      vooruit.cancel(nu);'));
    expect(bron('lib/zone_lijst.dart'), contains('opStand?.call(rijGeheugen.herstel('));
    expect(bron('lib/lan/client.dart'), contains("              'rijApart': '1',"));
  });
}
