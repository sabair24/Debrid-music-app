/// Van buiten (47821): een plafond per sleutel op duur werk, en strengere regels voor bewerkingen.
///
/// Stap 5.2 van "verbinden zoals Roon ARC" (14-10-2026). Wat hier vastligt:
/// * het quotum telt per sleutel, per uur en per dag, en zegt wat en tot wanneer;
/// * het telt alleen van buiten — thuis en via Tailscale nooit;
/// * omzetten en hoezen verkleinen worden nooit geweigerd: bij een geraakt plafond het origineel;
/// * van buiten gaat verwijderen altijd naar de prullenbak, en een adres in een bewerking moet naar
///   het internet wijzen.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:debridmusic/lan/certificaat.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/quota.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

final _cert = PcCertificaat.maak();

Future<({int status, String lijf, String? etag})> _vraag(int poort, String pad,
    {required String sleutel, String methode = 'GET', Object? json}) async {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = const Duration(seconds: 5)
    ..badCertificateCallback = (cert, host, port) => pinVan(cert.der) == _cert.pin;
  try {
    final req = await client.openUrl(methode, Uri.parse('https://127.0.0.1:$poort$pad'));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sleutel');
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    }
    final res = await req.close();
    final etag = res.headers.value(HttpHeaders.etagHeader);
    return (status: res.statusCode, lijf: await const Utf8Decoder(allowMalformed: true).bind(res).join(), etag: etag);
  } finally {
    client.close(force: true);
  }
}

/// Een bibliotheek die opschrijft hoe er verwijderd werd, zonder echt iets te wissen of naar de
/// prullenbak van de machine waar de toets draait te sturen.
class _Vanger extends LibraryStore {
  final weg = <({bool fromDisk, bool naarPrullenbak})>[];
  @override
  Future<int> removeTracks(Iterable<String> paths, {required bool fromDisk, bool naarPrullenbak = false}) async {
    weg.add((fromDisk: fromDisk, naarPrullenbak: naarPrullenbak));
    return paths.length;
  }
}

void main() {
  group('het quotum zelf', () {
    var nu = DateTime(2026, 10, 14, 14, 0, 0);
    late Quota q;
    setUp(() {
      nu = DateTime(2026, 10, 14, 14, 0, 0);
      q = Quota(klok: () => nu);
    });

    test('tot het plafond mag het, daarna een zin met wat en vanaf hoe laat', () {
      for (var i = 0; i < kQuotumRadioplan.perUur; i++) {
        expect(q.boek('sleutel-a', kQuotumRadioplan), isNull);
        nu = nu.add(const Duration(seconds: 30));
      }
      final nee = q.boek('sleutel-a', kQuotumRadioplan);
      expect(nee, contains('${kQuotumRadioplan.perUur} per uur'));
      expect(nee, contains(kQuotumRadioplan.wat));
      // De eerste boeking was om 14:00:00: om 15:00:00 is er weer plaats.
      expect(nee, contains('om 15:00'));
      expect(q.inLaatsteUur('sleutel-a', kQuotumRadioplan), kQuotumRadioplan.perUur, reason: 'een nee boekt niets');
      nu = DateTime(2026, 10, 14, 15, 0, 1);
      expect(q.boek('sleutel-a', kQuotumRadioplan), isNull, reason: 'het venster schuift mee');
    });

    test('per sleutel: wat het ene toestel opgebruikt, mist het andere niet', () {
      expect(q.boek('sleutel-a', kQuotumDownloads, kQuotumDownloads.perUur), isNull);
      expect(q.boek('sleutel-a', kQuotumDownloads), isNotNull);
      expect(q.boek('sleutel-b', kQuotumDownloads), isNull);
      expect(q.boek('sleutel-a', kQuotumRadioplan), isNull, reason: 'elke soort telt apart');
    });

    test('ook per dag, en het tijdstip wordt naar boven afgerond', () {
      // Elk uur onder het uurplafond, samen boven het dagplafond.
      final perKeer = kQuotumPrullenbak.perUur;
      var geboekt = 0;
      nu = DateTime(2026, 10, 14, 8, 0, 20);
      while (geboekt + perKeer <= kQuotumPrullenbak.perDag) {
        expect(q.boek('s', kQuotumPrullenbak, perKeer), isNull);
        geboekt += perKeer;
        nu = nu.add(const Duration(hours: 1));
      }
      final nee = q.boek('s', kQuotumPrullenbak, perKeer);
      expect(nee, contains('${kQuotumPrullenbak.perDag} per dag'));
      expect(nee, contains('morgen om 08:01'), reason: '08:00:20 + een dag, naar boven afgerond');
    });

    test('meer in één keer dan er in een uur past: geen tijdstip, wel "in delen"', () {
      final nee = q.boek('s', kQuotumDownloads, kQuotumDownloads.perUur + 1);
      expect(nee, contains('in delen'));
      expect(nee, isNot(contains(' om ')));
    });
  });

  group('adressen in een bewerking van buiten', () {
    test('alleen https naar het internet', () {
      for (final goed in ['', 'https://i.discogs.com/abc.jpg', 'https://8.8.8.8/x.png', 'https://coverartarchive.org/release/1/front']) {
        expect(adresVanBuitenMag(goed), isTrue, reason: goed);
      }
      for (final fout in [
        'http://i.discogs.com/abc.jpg', // onversleuteld
        'file:///C:/Users/saber/AppData/Roaming/DebridMusic/settings.json',
        r'C:\Users\saber\Music\hoes.jpg',
        'https://192.168.0.1/', // de modem
        'https://100.97.101.113:47820/art/x', // Tailscale
        'https://127.0.0.1/', 'https://localhost/', 'https://[::1]/', 'https://169.254.1.1/',
        'https://0.1.2.3/', 'https://224.0.0.1/',
        'https://pc.invalid/art/x', 'https://modem/', 'https://router.home/', 'https://nas.local/',
        'https://iemand@i.discogs.com/x.jpg',
      ]) {
        expect(adresVanBuitenMag(fout), isFalse, reason: fout);
      }
    });
  });

  group('via de deuren van de pc', () {
    late Directory scratch, pcRoot;
    late LanServer server;
    late GrantStore grants;
    late _Vanger lib;
    late int thuis, buiten;
    late String tls;
    late String nummer;
    late File bestand;

    setUp(() async {
      scratch = Directory.systemTemp.createTempSync('dm_quota_');
      setAppDirForTest(scratch.path);
      pcRoot = Directory.systemTemp.createTempSync('dm_quota_pc_');
      final map = Directory('${pcRoot.path}/Portishead/Dummy')..createSync(recursive: true);
      bestand = File('${map.path}/01.flac')..writeAsBytesSync(List<int>.filled(4096, 7));
      lib = _Vanger()..tracks.add(Track(path: bestand.path, title: 'Mysterons', artist: 'Portishead', album: 'Dummy'));
      lib.albums = [Album('Dummy', 'Portishead', lib.tracks.toList())];
      lib.albums.first.embeddedCover = Uint8List.fromList(img.encodeJpg(img.Image(width: 600, height: 600)));
      grants = GrantStore(file: File('${scratch.path}/grants.json'));
      server = LanServer(
        library: lib,
        token: 'gedeelde-sleutel',
        state: LanStateStore(File('${pcRoot.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        settings: AppSettings()..serverId = 'pc-saber-0001',
        certificaat: _cert,
        tlsPoort: 0,
        publiekPoort: 0,
        grants: grants,
      )..prullenbakAanwezig = () => true;
      expect(await server.start(), isNull);
      thuis = server.tlsBoundPort!;
      buiten = server.publiekBoundPort!;
      tls = grants.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26', metTls: true).tlsToken!;
      nummer = server.catalog.snapshot().catalog.tracks.single.id;
    });

    tearDown(() async {
      await server.dispose();
      for (final m in [pcRoot, scratch]) {
        try {
          m.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('een radio uit een zin: van buiten 429 met de zin, thuis telt het niet', () async {
      expect(server.quota.boek(tls, kQuotumRadioplan, kQuotumRadioplan.perUur), isNull);
      final b = await _vraag(buiten, '/api/radio', sleutel: tls, methode: 'POST', json: {'op': 'plan', 'zin': 'iets rustigs'});
      expect(b.status, 429);
      expect((jsonDecode(b.lijf) as Map)['error'], contains('per uur'));
      // Thuis: geen quotum. Zonder AI-sleutel zegt de pc dat, en niet "te veel".
      final t = await _vraag(thuis, '/api/radio', sleutel: tls, methode: 'POST', json: {'op': 'plan', 'zin': 'iets rustigs'});
      expect(t.status, isNot(429));
      expect(server.quota.inLaatsteUur(tls, kQuotumRadioplan), kQuotumRadioplan.perUur, reason: 'thuis boekt niets');
    });

    test('een nummer laten halen telt als download, alleen van buiten', () async {
      final h1 = await _vraag(buiten, '/api/radio', sleutel: tls, methode: 'POST', json: {'op': 'haal', 'artiest': 'Portishead', 'titel': 'Roads'});
      expect(h1.status, 200);
      expect(server.quota.inLaatsteUur(tls, kQuotumDownloads), 1);
      await _vraag(thuis, '/api/radio', sleutel: tls, methode: 'POST', json: {'op': 'haal', 'artiest': 'Portishead', 'titel': 'Glory Box'});
      expect(server.quota.inLaatsteUur(tls, kQuotumDownloads), 1);
      server.quota.boek(tls, kQuotumDownloads, kQuotumDownloads.perUur - 1);
      final h2 = await _vraag(buiten, '/api/radio', sleutel: tls, methode: 'POST', json: {'op': 'haal', 'artiest': 'Portishead', 'titel': 'Sour Times'});
      expect(h2.status, 429);
    });

    test('van buiten gaat verwijderen altijd naar de prullenbak; thuis zoals gevraagd', () async {
      final b = await _vraag(buiten, '/api/corrections', sleutel: tls, methode: 'POST',
          json: {'op': 'removeTracks', 'trackIds': [nummer], 'fromDisk': true});
      expect(b.status, 200, reason: b.lijf);
      expect(lib.weg.single, (fromDisk: true, naarPrullenbak: true));
      expect(server.quota.inLaatsteUur(tls, kQuotumPrullenbak), 1);
      final t = await _vraag(thuis, '/api/corrections', sleutel: tls, methode: 'POST',
          json: {'op': 'removeTracks', 'trackIds': [nummer], 'fromDisk': true});
      expect(t.status, 200);
      expect(lib.weg.last, (fromDisk: true, naarPrullenbak: false), reason: 'thuis beslist het toestel zelf');
      // Alleen uit de bibliotheek (niet van schijf) telt niet mee.
      await _vraag(buiten, '/api/corrections', sleutel: tls, methode: 'POST',
          json: {'op': 'removeTracks', 'trackIds': [nummer], 'fromDisk': false});
      expect(server.quota.inLaatsteUur(tls, kQuotumPrullenbak), 1);
    });

    test('zonder prullenbak kan wissen van schijf alleen thuis', () async {
      server.prullenbakAanwezig = () => false;
      final b = await _vraag(buiten, '/api/corrections', sleutel: tls, methode: 'POST',
          json: {'op': 'removeTracks', 'trackIds': [nummer], 'fromDisk': true});
      expect(b.status, 403);
      expect((jsonDecode(b.lijf) as Map)['error'], contains('prullenbak'));
      expect(lib.weg, isEmpty);
    });

    test('een adres naar het eigen netwerk in een bewerking: van buiten 403, thuis gewoon', () async {
      final b = await _vraag(buiten, '/api/corrections', sleutel: tls, methode: 'POST',
          json: {'op': 'artistArt', 'artist': 'Portishead', 'kind': 'portrait', 'url': 'http://192.168.0.1/'});
      expect(b.status, 403);
      expect((jsonDecode(b.lijf) as Map)['error'], contains('https'));
      final t = await _vraag(thuis, '/api/corrections', sleutel: tls, methode: 'POST',
          json: {'op': 'artistArt', 'artist': 'Portishead', 'kind': 'portrait', 'url': 'http://192.168.0.1/'});
      expect(t.status, 200, reason: t.lijf);
    });

    test('hoezen verkleinen met een geraakt plafond: de volle hoes, met haar eigen merkteken', () async {
      final ref = server.catalog.snapshot().catalog.albums.single.artworkRef!;
      final klein = await _vraag(buiten, '/art/$ref?w=200', sleutel: tls);
      expect(klein.status, 200);
      expect(klein.etag, contains('-w200'));
      expect(server.quota.inLaatsteUur(tls, kQuotumHoezen), 1, reason: 'een nieuwe verkleining van buiten telt');
      expect(server.quota.boek(tls, kQuotumHoezen, kQuotumHoezen.perUur - 1), isNull);
      // Nieuw werk boven het plafond: geen weigering, wel de volle hoes (zodat het toestel later
      // alsnog de kleine vraagt: het merkteken klopt niet met wat het vroeg).
      final vol = await _vraag(buiten, '/art/$ref?w=300', sleutel: tls);
      expect(vol.status, 200);
      expect(vol.etag, isNot(contains('-w')));
      // Wat al klaarligt kost niets en komt gewoon.
      expect((await _vraag(buiten, '/art/$ref?w=200', sleutel: tls)).etag, contains('-w200'));
      // En thuis telt het niet.
      expect((await _vraag(thuis, '/art/$ref?w=300', sleutel: tls)).etag, contains('-w300'));
    });

    test('omzetten met een geraakt plafond: het origineel, nooit een weigering', () async {
      server.quota.boek(tls, kQuotumOmzetten, kQuotumOmzetten.perUur);
      final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
        ..badCertificateCallback = (cert, host, port) => pinVan(cert.der) == _cert.pin;
      try {
        final req = await client.getUrl(Uri.parse('https://127.0.0.1:$buiten/stream/$nummer.flac?maxRate=48000&maxBits=16'));
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $tls');
        final res = await req.close();
        final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
        expect(res.statusCode, 200);
        expect(bytes.length, bestand.lengthSync(), reason: 'het origineel, onveranderd');
        // En om die reden, niet omdat het omzetten van dit nepbestand mislukte.
        final log = File('$logDir${Platform.pathSeparator}stroom.log').readAsStringSync();
        expect(log, contains('quotum omzetten geraakt'));
      } finally {
        client.close(force: true);
      }
    });
  });
}
