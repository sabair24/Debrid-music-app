/// Kiezen stopt: na je keuze nooit meer vragen, twijfel alleen voor een soort die mist, en "Genoeg" per plaat of artiest.
///
/// Saber, 28-11-2026, na Thriller: *"gaat de hunt nu stoppen ? want ik blijf maar nummers krijgen bij kiezen, vooral
/// adele, het moet eens stoppen e. zit er een begrenzer op ?"* Gemeten: de blijvende jacht zoekt een niet-bewezen nummer
/// elke dag; Bewaren maakte van de kopie een versie maar liet de jacht doorgaan, en elke andere rip die beter klonk met
/// een twijfelende vingerafdruk werd een nieuw geval — 20 in 13 uur. Zijn keuzes: na een keuze nooit meer vragen; geen
/// grens per dag; twijfel alleen voor een soort die je nog niet hebt; een Genoeg-knop per plaat en per artiest.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/twijfel.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

/// Een kleine FLAC met een echte kop: [bps] 24 is een studiokopie, 16 een cd; [som] vult de controlesom.
File _flac(String pad, {required int som, int extra = 0, int totaal = 441000, int bps = 16}) {
  const sr = 44100, ch = 2;
  final s = Uint8List(34);
  s[0] = 0x10;
  s[2] = 0x10;
  s[10] = (sr >> 12) & 0xff;
  s[11] = (sr >> 4) & 0xff;
  s[12] = ((sr & 0x0f) << 4) | (((ch - 1) & 0x07) << 1) | (((bps - 1) >> 4) & 0x01);
  s[13] = ((bps - 1) & 0x0f) << 4;
  ByteData.sublistView(s).setUint32(14, totaal);
  for (var i = 18; i < 34; i++) {
    s[i] = som;
  }
  final b = BytesBuilder()
    ..add('fLaC'.codeUnits)
    ..add([0x80, 0, 0, 34])
    ..add(s)
    ..add(List.filled(extra, 7));
  return File(pad)
    ..createSync(recursive: true)
    ..writeAsBytesSync(b.toBytes());
}

const _thriller = TrackTags(title: 'Thriller', artist: 'Michael Jackson', album: 'Thriller', albumArtist: 'Michael Jackson', trackNo: 4);
const _adele = TrackTags(title: 'Hold On', artist: 'Adele', album: '30', albumArtist: 'Adele', trackNo: 10);

void main() {
  group('GenoegStand', () {
    test('een artiest geldt voor elk nummer van hem, ook als albumartiest; een plaat alleen voor die plaat', () {
      final s = GenoegStand(artiesten: {genoegArtiest('Adele')}, platen: {genoegPlaat('Michael Jackson', 'Thriller')});
      expect(s.artiest('ADELE'), isTrue, reason: 'hoofdletters en leestekens tellen niet');
      expect(s.voorNummer(artiest: 'Adele', album: '30'), isTrue);
      expect(s.voorNummer(artiest: 'Adele feat. X', albumArtiest: 'Adele', album: '25'), isTrue);
      expect(s.voorNummer(artiest: 'Michael Jackson', albumArtiest: 'Michael Jackson', album: 'Thriller'), isTrue);
      expect(s.voorNummer(artiest: 'Michael Jackson', albumArtiest: 'Michael Jackson', album: 'Bad'), isFalse);
      expect(s.voorNummer(artiest: 'Paul McCartney', albumArtiest: 'Michael Jackson', album: 'Thriller'), isTrue,
          reason: 'een duet op de plaat');
      expect(s.plaat('Michael Jackson', ''), isFalse);
      expect(s.artiest(''), isFalse);
      // Een plaat zonder titel is geen plaat, ook niet als er zo'n sleutel in de lijst zou staan.
      expect(GenoegStand(platen: {genoegPlaat('Adele', '')}).plaat('Adele', ''), isFalse);
    });

    test('een nummer zonder artiest of titel wordt nooit "gekozen" (anders zou het voor alle zulke nummers gelden)', () {
      final l = Twijfellijst('${Directory.systemTemp.path}/nooit_bewaard_twijfel.json')
        ..onthoudGekozen('', 'Intro')
        ..onthoudGekozen('Adele', '');
      expect(l.gekozen('', 'Intro'), isFalse);
      expect(l.gekozen('Adele', ''), isFalse);
      expect(l.keuzesNogNooitBewaard, isTrue);
    });

    test('heen en terug als JSON; rommel geeft een lege stand', () {
      final s = GenoegStand(artiesten: {genoegArtiest('Adele')}, platen: {genoegPlaat('Michael Jackson', 'Thriller')});
      final terug = GenoegStand.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(terug.artiesten, s.artiesten);
      expect(terug.platen, s.platen);
      expect(GenoegStand.fromJson('rommel').artiesten, isEmpty);
      expect(GenoegStand.fromJson({'platen': [1, '', 'a|b']}).platen, {'a|b'});
    });
  });

  group('soortOntbreekt: alleen een soort die het nummer nog niet heeft', () {
    test('de soort van het nummer, of van een versie: nee; een soort die mist: ja; geen soort: nooit', () {
      expect(soortOntbreekt(Kopiesoort.studio, Kopiesoort.studio, const []), isFalse);
      expect(soortOntbreekt(Kopiesoort.studio, Kopiesoort.cd, const [Kopiesoort.studio]), isFalse);
      expect(soortOntbreekt(Kopiesoort.vinyl, Kopiesoort.cd, const [Kopiesoort.studio]), isTrue);
      expect(soortOntbreekt(Kopiesoort.studio, Kopiesoort.cd, const []), isTrue);
      expect(soortOntbreekt(null, Kopiesoort.cd, const []), isFalse);
      expect(soortOntbreekt(Kopiesoort.cd, null, const [Kopiesoort.vinyl]), isTrue, reason: 'een nummer zonder soort');
    });
  });

  group('Twijfellijst: wat je koos en Genoeg, bewaard', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('kiezen_genoeg_'));
    tearDown(() {
      genoegVanPc.value = const GenoegStand();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('de keuzes uit downloads.log (zoals ze er op 28-11 stonden)', () {
      final l = Twijfellijst('${map.path}/twijfel.json');
      expect(l.keuzesNogNooitBewaard, isTrue);
      const log = '08:25:03.227  "Michael Jackson — Baby Be Mine": twijfelkopie bewaard als versie (Soulseek chris89, Studio · 24/192)\n'
          '08:25:19.382  "Michael Jackson — Human Nature": twijfelkopie gekozen (Soulseek nicotinestain, FLAC 24/176,4) — vervangen\n'
          '08:25:17.545  "Michael Jackson — P.Y.T. (Pretty Young Thing)": twijfelkopie gekozen (Soulseek nicotinestain), maar …\n'
          '21:32:32.484  "Peyote — Alcatraz": vinyl-kopie bewaard als versie (Soulseek SeanOfTheKrakens)\n'
          '20:19:26.206     Soulseek x: twijfel (0,85) voor "Beastie Boys — Intergalactic", maar er wacht al een twijfelgeval\n'
          '07:59:10.040  "Phil Collins — In The Air Tonight": TWIJFEL — Soulseek aout klinkt beter\n';
      expect(l.neemKeuzesUitLog(log), 4);
      expect(l.gekozen('Michael Jackson', 'Baby Be Mine'), isTrue);
      expect(l.gekozen('michael jackson', 'human nature'), isTrue);
      expect(l.gekozen('Michael Jackson', 'P.Y.T. (Pretty Young Thing)'), isTrue);
      expect(l.gekozen('Peyote', 'Alcatraz'), isTrue);
      expect(l.gekozen('Beastie Boys', 'Intergalactic'), isFalse, reason: 'een aangeboden kopie is geen keuze');
      expect(l.gekozen('Phil Collins', 'In The Air Tonight'), isFalse, reason: 'een nieuw geval is geen keuze');
      expect(l.keuzesNogNooitBewaard, isFalse);
      expect(l.neemKeuzesUitLog(log), 0, reason: 'twee keer hetzelfde telt één keer');
    });

    test('keuzes en Genoeg blijven bewaard over een herstart; Genoeg staat meteen in genoegVanPc', () async {
      final l = Twijfellijst('${map.path}/twijfel.json')
        ..onthoudGekozen('Michael Jackson', 'Thriller')
        ..zetGenoeg(artiest: 'Adele', aan: true)
        ..zetGenoeg(artiest: 'Michael Jackson', album: 'Thriller', aan: true);
      expect(genoegVanPc.value.artiest('Adele'), isTrue);
      await l.bewaar();
      genoegVanPc.value = const GenoegStand();
      final weer = Twijfellijst('${map.path}/twijfel.json');
      await weer.laad();
      expect(weer.keuzesNogNooitBewaard, isFalse);
      expect(weer.gekozen('Michael Jackson', 'Thriller'), isTrue);
      expect(weer.genoeg.artiest('Adele'), isTrue);
      expect(weer.genoeg.plaat('Michael Jackson', 'Thriller'), isTrue);
      expect(genoegVanPc.value.plaat('Michael Jackson', 'Thriller'), isTrue);
      weer.zetGenoeg(artiest: 'Adele', aan: false);
      expect(weer.genoeg.artiest('Adele'), isFalse);
      expect(genoegVanPc.value.artiest('Adele'), isFalse);
    });

    test('een lijst van vóór 3.9.766 (zonder keuzes) vraagt om de keuzes uit het logboek', () async {
      File('${map.path}/twijfel.json').writeAsStringSync(jsonEncode({'versie': 1, 'gevallen': [], 'nee': {}}));
      final l = Twijfellijst('${map.path}/twijfel.json');
      await l.laad();
      expect(l.keuzesNogNooitBewaard, isTrue);
      final m = _bron('lib/main.dart');
      expect(m, contains('      if (twijfels.keuzesNogNooitBewaard) {'));
      expect(m, contains("twijfels.neemKeuzesUitLog(await logboek.readAsString())"));
    });
  });

  group('de jacht vraagt niet meer', () {
    late Directory map;
    late DownloadManager d;
    late List<String> nietGevraagd;
    setUp(() {
      map = Directory.systemTemp.createTempSync('kiezen_jacht_');
      d = DownloadManager(OnlineService(AppSettings()), SoulseekService(AppSettings()), map.path, () async {})
        ..twijfel = Twijfellijst('${map.path}/twijfel.json');
      nietGevraagd = [];
      DownloadManager.prullenbak = (paden) async {
        for (final p in paden) {
          File(p).deleteSync();
        }
        return paden.toSet();
      };
    });
    tearDown(() {
      versies.wis();
      genoegVanPc.value = const GenoegStand();
      DownloadManager.prullenbak = (_) async => {};
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: na een keuze (Bewaren) komt er voor dat nummer niets meer bij Kiezen, en de jacht onthoudt de kopie',
        () async {
      final eigen = _flac('${map.path}/Albums/Michael Jackson/Thriller/04 - Thriller.flac', som: 1);
      final studio = _flac('${map.path}/_keuring/a/04 - Thriller.flac', som: 3, bps: 24);
      expect(await d.bewaarAlsTwijfel(studio, eigen.path, .86, 'Soulseek antonerism', _thriller), isTrue);
      expect(d.twijfel!.van(eigen.path), isNotNull, reason: 'een studio die mist: gevraagd');
      await d.vervangDoorTwijfel(eigen.path, alsVersie: true);
      expect(d.twijfel!.gekozen('Michael Jackson', 'Thriller'), isTrue);
      // Morgen: een vinylrip (ook een soort die mist), maar je koos al.
      final vinyl = _flac('${map.path}/_keuring/b/04 - Thriller.flac', som: 5, totaal: 452333);
      expect(
          await d.bewaarAlsTwijfel(vinyl, eigen.path, .86, 'Soulseek x', _thriller,
              bronpad: r'music\Michael Jackson\Thriller (Vinyl LP 1982)\04.flac', nietGevraagd: () => nietGevraagd.add('x')),
          isTrue);
      expect(d.twijfel!.van(eigen.path), isNull);
      expect(vinyl.existsSync(), isFalse, reason: 'weg uit de keuringsmap');
      expect(nietGevraagd, ['x'], reason: 'de jacht onthoudt hem: morgen niet opnieuw binnenhalen');
      // Weg is geen keuze: dan zoekt de app juist verder.
      final eigen2 = _flac('${map.path}/Albums/Michael Jackson/Thriller/05 - Beat It.flac', som: 2);
      const beatIt = TrackTags(title: 'Beat It', artist: 'Michael Jackson', album: 'Thriller', trackNo: 5);
      await d.bewaarAlsTwijfel(_flac('${map.path}/_keuring/c/05.flac', som: 6, bps: 24), eigen2.path, .86, 'S y', beatIt);
      await d.gooiTwijfelWeg(eigen2.path);
      expect(d.twijfel!.gekozen('Michael Jackson', 'Beat It'), isFalse);
    });

    test('alleen een soort die mist: een tweede studio niet, een vinylrip wel', () async {
      final eigen = _flac('${map.path}/Albums/Adele/30/10 - Hold On.flac', som: 1);
      final studio = _flac('${map.path}/Albums/Adele/30 (studio)/10 - Hold On.flac', som: 2, bps: 24);
      versies.voegToe(eigen.path, Versie(pad: studio.path, soort: Kopiesoort.studio), ankerSoort: Kopiesoort.cd);
      final nogEen = _flac('${map.path}/_keuring/a/10 - Hold On.flac', som: 4, bps: 24, totaal: 441500);
      expect(
          await d.bewaarAlsTwijfel(nogEen, eigen.path, .87, 'Soulseek a', _adele, nietGevraagd: () => nietGevraagd.add('a')),
          isTrue);
      expect(d.twijfel!.van(eigen.path), isNull, reason: 'je hebt al een studio');
      expect(nietGevraagd, ['a']);
      final vinyl = _flac('${map.path}/_keuring/b/10 - Hold On.flac', som: 5, totaal: 452333);
      expect(
          await d.bewaarAlsTwijfel(vinyl, eigen.path, .87, 'Soulseek b', _adele,
              bronpad: r'music\Adele\30 (Vinyl LP 2021)\10 - Hold On.flac', nietGevraagd: () => nietGevraagd.add('b')),
          isTrue);
      expect(d.twijfel!.van(eigen.path), isNotNull, reason: 'vinyl mist nog: gevraagd');
      expect(nietGevraagd, ['a']);
    });

    test('Genoeg voor Adele: wat wachtte gaat weg (wat je zelf vroeg blijft), en er komt niets nieuws; uit = weer vragen',
        () async {
      final eigen = _flac('${map.path}/Albums/Adele/30/10 - Hold On.flac', som: 1);
      await d.bewaarAlsTwijfel(_flac('${map.path}/_keuring/a/10.flac', som: 3, bps: 24), eigen.path, .86, 'S a', _adele);
      final kandidaat = d.twijfel!.van(eigen.path)!.kandidaat;
      // Iets wat je zelf vroeg (een cd-kopie): blijft staan.
      final eigen2 = _flac('${map.path}/Albums/Adele/30/07 - I Drink Wine.flac', som: 1);
      final gevraagd = File('${map.path}/_twijfel/v1.flac')..createSync(recursive: true);
      d.twijfel!.zet(Twijfelgeval(
          id: 'v1', pad: eigen2.path, kandidaat: gevraagd.path, bron: 'Soulseek z', score: .95, kwaliteit: 'CD',
          ms: 1, grootte: 1, soort: Kopiesoort.cd,
          gezag: const TrackTags(title: 'I Drink Wine', artist: 'Adele', album: '30', albumArtist: 'Adele', trackNo: 7)
              .toJson()));

      final uit = await d.zetGenoeg(artiest: 'Adele', aan: true);
      expect(uit.weg, 1);
      expect(uit.stand.artiest('Adele'), isTrue);
      expect(d.twijfel!.van(eigen.path), isNull);
      expect(File(kandidaat).existsSync(), isFalse);
      expect(d.twijfel!.van(eigen2.path), isNotNull, reason: 'wat je zelf vroeg, beslis jij');
      expect(genoegVanPc.value.artiest('Adele'), isTrue);

      final nieuw = _flac('${map.path}/_keuring/b/10.flac', som: 4, bps: 24);
      expect(await d.bewaarAlsTwijfel(nieuw, eigen.path, .86, 'S b', _adele, nietGevraagd: () => nietGevraagd.add('b')),
          isTrue);
      expect(d.twijfel!.van(eigen.path), isNull);
      expect(nietGevraagd, ['b']);

      await d.zetGenoeg(artiest: 'Adele', aan: false);
      final daarna = _flac('${map.path}/_keuring/c/10.flac', som: 6, bps: 24);
      await d.bewaarAlsTwijfel(daarna, eigen.path, .86, 'S c', _adele);
      expect(d.twijfel!.van(eigen.path), isNotNull, reason: 'Genoeg uit: weer vragen');
    });

    test('Genoeg voor één plaat: een andere plaat van dezelfde artiest blijft gewoon', () async {
      await d.zetGenoeg(artiest: 'Michael Jackson', album: 'Thriller', aan: true);
      final thriller = _flac('${map.path}/Albums/Michael Jackson/Thriller/04 - Thriller.flac', som: 1);
      await d.bewaarAlsTwijfel(_flac('${map.path}/_keuring/a/t.flac', som: 3, bps: 24), thriller.path, .86, 'S a', _thriller);
      expect(d.twijfel!.van(thriller.path), isNull);
      final bad = _flac('${map.path}/Albums/Michael Jackson/Bad/01 - Bad.flac', som: 1);
      const badTags = TrackTags(title: 'Bad', artist: 'Michael Jackson', album: 'Bad', albumArtist: 'Michael Jackson', trackNo: 1);
      await d.bewaarAlsTwijfel(_flac('${map.path}/_keuring/b/b.flac', som: 4, bps: 24), bad.path, .86, 'S b', badTags);
      expect(d.twijfel!.van(bad.path), isNotNull);
    });
  });

  group('/api/genoeg', () {
    late Directory map;
    late LanServer server;
    late DownloadManager d;
    setUp(() async {
      map = Directory.systemTemp.createTempSync('kiezen_api_');
      final settings = AppSettings();
      d = DownloadManager(OnlineService(settings), SoulseekService(settings), map.path, () async {})
        ..twijfel = Twijfellijst('${map.path}/twijfel.json');
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        settings: settings,
        downloads: d,
        online: OnlineService(settings),
      );
      expect(await server.start(), isNull);
    });
    tearDown(() async {
      genoegVanPc.value = const GenoegStand();
      await server.dispose();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<(int, Map<String, dynamic>)> vraag(String methode, [Map<String, dynamic>? body]) async {
      final http = HttpClient();
      try {
        final uri = Uri.parse('http://127.0.0.1:${server.boundPort}/api/genoeg');
        final req = methode == 'GET' ? await http.getUrl(uri) : await http.postUrl(uri);
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer sleutel');
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final res = await req.close();
        final tekst = await res.transform(utf8.decoder).join();
        if (tekst.isEmpty) fail('leeg antwoord op $methode: ${res.statusCode}');
        return (res.statusCode, jsonDecode(tekst) as Map<String, dynamic>);
      } finally {
        http.close(force: true);
      }
    }

    test('aan, opvragen, uit — en zonder artiest een 400', () async {
      final (s1, aan) = await vraag('POST', {'artiest': 'Adele', 'aan': true});
      expect(s1, 200);
      expect(GenoegStand.fromJson(aan['genoeg']).artiest('Adele'), isTrue);
      expect(aan['weg'], 0);
      final (_, plaat) = await vraag('POST', {'artiest': 'Michael Jackson', 'album': 'Thriller', 'aan': true});
      expect(GenoegStand.fromJson(plaat['genoeg']).plaat('Michael Jackson', 'Thriller'), isTrue);
      final (s2, stand) = await vraag('GET');
      expect(s2, 200);
      expect(GenoegStand.fromJson(stand).artiest('Adele'), isTrue);
      expect(GenoegStand.fromJson(stand).plaat('Michael Jackson', 'Thriller'), isTrue);
      final (_, uit) = await vraag('POST', {'artiest': 'Adele', 'aan': false});
      expect(GenoegStand.fromJson(uit['genoeg']).artiest('Adele'), isFalse);
      final (s3, _) = await vraag('POST', {'artiest': ' ', 'aan': true});
      expect(s3, 400);
    });

    test('ook van buitenshuis, en het toestel vraagt het zelf', () {
      expect(_bron('lib/lan/server.dart'), contains("    '/api/genoeg',\n  };"));
      expect(_bron('lib/lan/client.dart'), contains("final res = await _get('/api/genoeg');"));
    });
  });
}
