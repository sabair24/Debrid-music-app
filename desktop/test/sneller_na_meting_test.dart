// Drie dingen die op 11-11-2026 op de gsm gemeten werden, na de zoekrem (telling_voorrang_test.dart). Saber: "pak die
// dingen ook aan".
//
// 1. ⬇ Milow — You Don't Know: het bestand stond na 4,6 s op de pc, de gsm toonde het pas na 13,8 s. De gsm vroeg de
//    catalogus alleen in zijn ronde van vijftien seconden, en tijdens het keuren op de pc (ruim vier seconden) stond er
//    een zandloper.
// 2. De kopfoto van Zornik, geopend via "Klinkt als" bij Milow, kwam pas na 5 tot 20 s: de tegels van die rij vroegen hun
//    portret op de gewone rij van TheAudioDB (een vraag per 3 s), en de bio en de foto vroegen elk apart hetzelfde.
// 3. Uploaders vielen af als "niet bereikbaar (firewall)": zeventien tegelijk, 15 s nadat de wedloop al gewonnen was, en
//    de eerste vrije (h3b) in de wedloop, die vijftien seconden later wél leverde.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/klinkt_als.dart';
import 'package:debridmusic/online.dart' show kBinnenKeuren, landenRegel;
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

/// Een init-bericht zoals een peer het stuurt: lengte, code, dan de rest.
Uint8List _init(int code, List<int> rest) {
  final lijf = [code, ...rest];
  final n = lijf.length;
  return Uint8List.fromList([n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF, ...lijf]);
}

List<int> _u32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _str(String s) => [..._u32(utf8.encode(s).length), ...utf8.encode(s)];

void main() {
  group('3. uploaders', () {
    test('DE KERN: boven de grens komt de terugbel waar we op wachten nog binnen; een zoektreffer niet', () async {
      setAppDirForTest(Directory.systemTemp.createTempSync('omweg').path);
      final oud = SoulseekClient.maxInbound;
      SoulseekClient.maxInbound = 2;
      addTearDown(() => SoulseekClient.maxInbound = oud);
      final proef = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final poort = proef.port;
      await proef.close();
      final client = SoulseekClient()..listenPort = poort;
      expect(await client.ensureListening(), poort);
      addTearDown(client.stopListening);
      final open = <Socket>[];
      addTearDown(() {
        for (final s in open) {
          s.destroy();
        }
      });
      // Twee zoektreffers die nog niets zeiden vullen de poort.
      for (var i = 0; i < 2; i++) {
        open.add(await Socket.connect(InternetAddress.loopbackIPv4, poort));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      expect(client.levendeInbound, 2);

      var terug = false;
      client.wachtOpTerugbelVoorToets(4242, () => terug = true);
      expect(client.wachtOpBinnenkomend, isTrue);
      // Eerst een zoektreffer, terwijl er nog op de terugbel gewacht wordt: binnengelaten om te zeggen wie hij is, en dan
      // dicht — niet als zoektreffer verwerkt.
      final zoeker = await Socket.connect(InternetAddress.loopbackIPv4, poort);
      open.add(zoeker);
      zoeker.add(_init(1, [..._str('iemand'), ..._str('P'), ..._u32(1)])); // PeerInit 'P': een zoektreffer
      await zoeker.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(client.geweigerdInbound, 1, reason: 'de zoektreffer boven de grens ging dicht na zijn eerste bericht');
      expect(client.wachtOpBinnenkomend, isTrue, reason: 'de terugbel wacht nog');
      // Dan de uploader.
      final h3b = await Socket.connect(InternetAddress.loopbackIPv4, poort);
      open.add(h3b);
      h3b.add(_init(0, _u32(4242))); // PierceFirewall(4242)
      await h3b.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(terug, isTrue, reason: 'de uploader die we lieten terugbellen, kwam binnen boven de grens');
    });

    test('zonder iemand die wacht, blijft de grens zoals hij was', () async {
      setAppDirForTest(Directory.systemTemp.createTempSync('omweg2').path);
      final client = SoulseekClient();
      expect(client.wachtOpBinnenkomend, isFalse);
      expect(SoulseekClient.maxInboundNood, greaterThan(SoulseekClient.maxInbound));
      expect(kBovenGrensKijktijd, lessThan(const Duration(seconds: 30)), reason: 'een gewone verbinding krijgt dertig');
    });

    test('wie verloor, stopt meteen: het adres en de omweg luisteren naar de stopknop', () {
      final s = _bron('lib/soulseek.dart');
      expect(s, contains('final rev = await _reverseConnect(file.username, cancel: cancel);\n'
          '        if (cancel != null && cancel.isCancelled) return SlskCancelled();\n'
          "        if (rev == null) return SlskFail('Uploader niet bereikbaar (firewall)');"));
      expect(s, contains('          if (cancel != null) cancel.whenCancelled.then((_) => (\'0.0.0.0\', 0)),'));
      expect(s, contains('      cancel?.whenCancelled.then((_) {\n        if (!got.isCompleted) got.complete(null);\n      });'));
    });

    test('een omweg zonder terugbel zegt hoe vol de poort was', () {
      expect(omwegZonderAntwoordRegel(peer: 'h3b', duur: const Duration(milliseconds: 15004), open: 612, geweigerd: 37),
          'omweg naar h3b: geen terugbel in 15.0 s — 612 binnenkomende verbindingen open, 37 geweigerd tijdens het wachten');
    });
  });

  group('2. de artiestpagina', () {
    test('DE KERN: "Klinkt als" zoekt niet verder als de pagina dicht is', () async {
      var open = true, gevraagd = 0;
      await klinktAlsAanvullen(
        artiest: 'Milow',
        deezer: const [],
        lastfm: () async => [for (var i = 0; i < 60; i++) (naam: 'Lastfm $i', maat: 1 - i / 100)],
        zoekArtiest: (n) async {
          gevraagd++;
          open = false; // na de eerste ronde ga je naar Zornik
          return [CatalogArtist(1, n, null, 1)];
        },
        verwanten: (_) async => throw 'niet nodig',
        nogNodig: () => open,
      );
      expect(gevraagd, kKlinktAlsTegelijk, reason: 'alleen de ronde die al weg was');
    });

    test('de bio en de kopfoto delen één vraag aan TheAudioDB', () async {
      setAppDirForTest(Directory.systemTemp.createTempSync('kopfoto').path);
      CoverEnricher.vergeetAudioDbZoeken();
      var zoekvragen = 0;
      final net = MockClient((req) async {
        if (req.url.path.endsWith('/search.php')) {
          zoekvragen++;
          return http.Response(
              jsonEncode({
                'artists': [
                  {
                    'strArtist': 'Heather Nova',
                    'strBiographyEN': 'Heather Nova is a singer-songwriter from Bermuda.',
                    'strArtistFanart': 'https://r2.theaudiodb.com/images/media/artist/fanart/hn.jpg',
                  }
                ]
              }),
              200);
        }
        return http.Response.bytes([0xFF, 0xD8, ...List.filled(2046, 7)], 200); // een jpg
      });
      final enr = CoverEnricher(AppSettings());
      final (bio, art) = await http.runWithClient(
          () async => (
                await enr.fetchArtistBio('Heather Nova', voorrang: true),
                await enr.artistArt('Heather Nova', voorrang: true),
              ),
          () => net);
      expect(bio, contains('Bermuda'));
      expect(art?.backdropBytes, isNotNull);
      expect(zoekvragen, 1, reason: 'tot 3.9.724 twee keer dezelfde vraag, met 3 s ertussen');
    });

    test('bedrading: de kop vraagt met voorrang, de beelden komen tegelijk, en geen "Albums laden…" meer', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('    final art = await enr.artistArt(naam, voorrang: true);'));
      expect(m, isNot(contains("? 'Albums laden…'")));
      expect(m, contains('        nogNodig: () => mounted && naam == widget.artist.name,'));
      final e = _bron('lib/enrichment.dart');
      expect(e, contains('    final beelden = await Future.wait(['));
      expect(e, contains('    if (loopt != null && (!voorrang || _metaMetVoorrang.contains(sleutel))) return loopt;'),
          reason: 'een vraag met voorrang wacht niet op een tegel die nog in de rij staat');
    });
  });

  group('1. na de download', () {
    test('de regel in downloads.log', () {
      expect(
          landenRegel('02 - Milow - You Don\'t Know.flac',
              keuren: const Duration(milliseconds: 2900),
              opbergen: const Duration(milliseconds: 1200),
              bibliotheek: const Duration(milliseconds: 700)),
          "   02 - Milow - You Don't Know.flac: in de bibliotheek na 4.8 s — keuren 2.9 s, opbergen 1.2 s, bibliotheek 0.7 s");
    });

    test('binnen: meteen "bezig op 100 %" met wat er gebeurt, vóór het keuren', () {
      final o = _bron('lib/online.dart');
      final begin = o.indexOf('    Future<bool> succeed(SlskDone res, SoulseekFile from) async {');
      final lijf = o.substring(begin, o.indexOf('    Future<SlskResult> attempt(', begin));
      expect(lijf.indexOf('job.detail = kBinnenKeuren;'), greaterThan(0));
      expect(lijf.indexOf('job.detail = kBinnenKeuren;'), lessThan(lijf.indexOf('_bereidVergelijkingVoor(')));
      expect(lijf, contains("      job.status = 'downloading';\n      job.progress = 1;"));
      expect(kBinnenKeuren, 'binnen — keuren en opbergen');
    });
  });
}
