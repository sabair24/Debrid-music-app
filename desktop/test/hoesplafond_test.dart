library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:debridmusic/artwork.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// **GEMETEN OP 13-09-2026, op de bibliotheek van de pc, met de telefoon op 5G.**
///
/// De klacht was "het laden van metadata moet sneller van pc naar smartphone". De metadata was het
/// niet: de hele catalogus komt over 5G binnen in 0,27 s (204,8 KiB gezipt, 1112 KiB onverpakt,
/// eerste byte na 68 ms). De hoezen waren het wel - 544 albums, waarvan 541 een hoes geven:
///
///     samen 172,4 MiB
///     mediaan 120,6 KiB / 600 pixel   -- prima
///     grootste 14,70 MiB / 4000x4000 pixel
///     156 stuks (29 %) boven 1024 pixel
///
/// En de VORM is net zo goed het probleem als de maat: er staan zeven PNG's in, samen 32,6 MiB
/// tegen 1,3 MiB als JPEG - achttien keer zo zwaar per stuk.
///
/// Met [kHoesPlafond] over de hele bibliotheek geteld: **172,4 MiB -> 57,0 MiB**, zevenenzestig
/// procent minder, 533 van de 541 kleiner, en de grootste van 14,7 MiB naar 203 KiB.
///
/// Wat deze toets vasthoudt is niet dat getal maar de regels eronder: verkleinen boven het plafond,
/// hercoderen ook eronder, het merkteken moet het plafond MEETELLEN, de 304 mag niet rekenen, en
/// wat niets oplevert blijft het origineel.

/// Een plaatje dat zich als HOES gedraagt: vloeiende verlopen met een beetje korrel.
///
/// **Niet met pure ruis, en dat is geen detail.** Willekeurige pixels zijn onsamendrukbaar voor
/// JPEG en juist wel voor PNG met een palet — daarmee zou deze toets het tegenovergestelde bewijzen
/// van wat er op de echte bibliotheek gemeten is. Een hoes is een foto: grote gelijkmatige vlakken
/// met wat korrel erover.
Uint8List _foto(int breedte, int hoogte, {bool alsPng = true, int kwaliteit = 92}) {
  final im = img.Image(width: breedte, height: hoogte);
  final r = Random(7);
  for (var y = 0; y < hoogte; y++) {
    for (var x = 0; x < breedte; x++) {
      final rood = sin(x / breedte * pi) * 110 + 110 + r.nextInt(8);
      final groen = (x + y) / (breedte + hoogte) * 200 + r.nextInt(8);
      final blauw = cos(y / hoogte * pi) * 100 + 120 + r.nextInt(8);
      im.setPixelRgb(x, y, rood.clamp(0, 255).toInt(), groen.clamp(0, 255).toInt(),
          blauw.clamp(0, 255).toInt());
    }
  }
  return Uint8List.fromList(alsPng
      ? img.encodePng(im)
      : img.encodeJpg(im, quality: kwaliteit, chroma: img.JpegChroma.yuv420));
}

({LibraryStore library, Directory root}) _bibliotheekMetHoes(Uint8List hoes) {
  final root = Directory.systemTemp.createTempSync('dm_hoesplafond_');
  final albumDir = Directory('${root.path}/Portishead/Dummy')..createSync(recursive: true);
  final f = File('${albumDir.path}/01 Mysterons.flac')
    ..writeAsBytesSync(List<int>.generate(4096, (i) => i % 256));
  final library = LibraryStore()..rootPath = root.path;
  library.tracks.add(Track(
    path: f.path,
    title: 'Mysterons',
    artist: 'Portishead',
    album: 'Dummy',
    trackNo: 1,
    duration: const Duration(seconds: 305),
    isFlac: true,
    sizeBytes: 4096,
    sampleRate: 44100,
    bitsPerSample: 16,
  ));
  library.rebuildAlbums();
  library.albums.first.embeddedCover = hoes;
  return (library: library, root: root);
}

Future<({int status, Uint8List bytes, String? etag})> _haal(HttpClient c, String url, String token,
    {String? ifNoneMatch}) async {
  final req = await c.getUrl(Uri.parse(url));
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  if (ifNoneMatch != null) req.headers.set(HttpHeaders.ifNoneMatchHeader, ifNoneMatch);
  final res = await req.close();
  final b = <int>[];
  await for (final d in res) {
    b.addAll(d);
  }
  return (
    status: res.statusCode,
    bytes: Uint8List.fromList(b),
    etag: res.headers.value(HttpHeaders.etagHeader)
  );
}

void main() {
  group('een hoes die klein genoeg is om te versturen', () {
    test('DE KERN: boven het plafond wordt er verkleind, en de verhouding blijft', () {
      final groot = _foto(2400, 1800, alsPng: false);
      final klein = verkleindeHoes(groot, kHoesPlafond);

      expect(klein, isNotNull, reason: '2400 pixel hoort onder het plafond gebracht te worden');
      final im = img.decodeImage(klein!)!;
      expect(im.width, kHoesPlafond);
      // 2400x1800 is 4:3; op 1024 breed hoort dat 768 hoog te zijn. Een pixel speling voor het
      // afronden - een scheve hoes valt meteen op, een pixel niet.
      expect((im.height - 768).abs(), lessThanOrEqualTo(1),
          reason: 'een uitgerekte hoes is erger dan een grote');
      expect(klein.length, lessThan(groot.length));
    });

    test('DE VAL: een PNG die NIET te groot is wordt toch hercodeerd', () {
      // Dit is het geval dat een plafond alleen niet vangt: 1024x1024 zit precies OP het plafond en
      // woog toch 2696 KB, puur omdat het een PNG was.
      final png = _foto(kHoesPlafond, kHoesPlafond);
      final klein = verkleindeHoes(png, kHoesPlafond);

      expect(klein, isNotNull, reason: 'een PNG op ware grootte is nog steeds de verkeerde vorm');
      final im = img.decodeImage(klein!)!;
      expect(im.width, kHoesPlafond, reason: 'er mag hier GEEN pixel af');
      expect(im.height, kHoesPlafond);
      expect(klein.length * 4, lessThan(png.length),
          reason: 'minder dan een kwart, anders is de hercodering de moeite niet');
    });

    test('DE GRENS: levert het niets op, dan blijft het origineel staan', () {
      // Een kleine hoes die al zuiniger bewaard is dan waar wij op coderen wordt van hercoderen
      // alleen maar groter. Null betekent hier "niets doen", en dat is beter dan hem nog een
      // generatie door de encoder halen - elke generatie kost zichtbaar detail en levert niets op.
      // Zeventig van de 541 hoezen in de echte bibliotheek zitten in dit geval.
      //
      // Dezelfde chroma-subsampling aan beide kanten, anders vergelijk je twee dingen tegelijk.
      final zuinig = _foto(300, 300, alsPng: false, kwaliteit: 25);
      expect(verkleindeHoes(zuinig, kHoesPlafond), isNull,
          reason: 'kleiner wordt hij niet, en slechter wel');
      // En wat niet te ontcijferen is ook niet.
      expect(verkleindeHoes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), kHoesPlafond),
          isNull);
    });

    test('DE VAL: echte doorzichtigheid blijft het origineel', () async {
      // JPEG kent geen doorzichtigheid en maakt er wit van. Een hoes die op de pc doorzichtig over
      // de achtergrond ligt zou op de telefoon op een wit vlak staan - en omdat er ook zonder
      // verkleinen gehercodeerd wordt, trof dat ook hoezen die al onder het plafond zitten.
      final im = img.Image(width: 1600, height: 1600, numChannels: 4);
      for (final p in im) {
        p.setRgba(200, 100, 50, p.x < 40 ? 0 : 255);
      }
      final doorzichtig = Uint8List.fromList(img.encodePng(im));
      expect(verkleindeHoes(doorzichtig, kHoesPlafond), isNull,
          reason: 'liever groot en goed dan klein met een witte rand');

      // DE GRENS eronder: een alfakanaal dat nergens gebruikt wordt hoort juist WEL mee te gaan.
      // Dat zijn de zwaarste bestanden in de bibliotheek.
      final dekkend = img.Image(width: 1600, height: 1600, numChannels: 4);
      final r = Random(3);
      for (final p in dekkend) {
        p.setRgba((p.x % 200) + r.nextInt(8), (p.y % 200) + r.nextInt(8), 90 + r.nextInt(8), 255);
      }
      expect(verkleindeHoes(Uint8List.fromList(img.encodePng(dekkend)), kHoesPlafond), isNotNull,
          reason: 'een ongebruikt alfakanaal is geen doorzichtigheid');
    });

    test('DE GRENS: een extreme verhouding levert geen hoes van niets', () {
      // copyResize(height:) rekent de breedte uit als round(plafond * b/h). Bij 8x20000 is dat nul,
      // en die JPEG van nul pixels breed was kleiner dan de bron en werd dus verstuurd: de telefoon
      // kreeg een geldig bestand waar niets in stond.
      final streep = img.Image(width: 8, height: 20000);
      for (final p in streep) {
        p.setRgb(p.y % 256, 40, 200);
      }
      expect(verkleindeHoes(Uint8List.fromList(img.encodeJpg(streep)), kHoesPlafond), isNull);
    });
  });

  group('/art/ met een plafond', () {
    late Directory root;
    late LanServer server;
    late String basis;
    late String ref;
    final client = HttpClient();

    setUp(() async {
      final f = _bibliotheekMetHoes(_foto(2000, 2000));
      root = f.root;
      server = LanServer(
        library: f.library,
        token: 'test-token',
        state: LanStateStore(File('${root.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        version: '1.2.3',
      );
      expect(await server.start(), isNull);
      basis = 'http://127.0.0.1:${server.boundPort}';
      final res = await _haal(client, '$basis/api/catalog', 'test-token');
      final cat = jsonDecode(utf8.decode(res.bytes)) as Map<String, dynamic>;
      ref = ((cat['albums'] as List).first as Map)['artworkRef'] as String;
    });

    tearDown(() async {
      await server.dispose();
      root.deleteSync(recursive: true);
    });

    test('DE KERN: zonder w komt onveranderd het origineel', () async {
      final zonder = await _haal(client, '$basis/art/$ref', 'test-token');
      final met = await _haal(client, '$basis/art/$ref?w=$kHoesPlafond', 'test-token');

      expect(zonder.status, 200);
      expect(met.status, 200);
      // Een oudere app en de pc zelf vragen zonder plafond, en die horen te krijgen wat ze altijd al
      // kregen.
      expect(img.decodeImage(zonder.bytes)!.width, 2000);
      expect(img.decodeImage(met.bytes)!.width, kHoesPlafond);
      expect(met.bytes.length * 2, lessThan(zonder.bytes.length));
    });

    test('DE VAL: het merkteken telt het plafond mee', () async {
      final zonder = await _haal(client, '$basis/art/$ref', 'test-token');
      final met = await _haal(client, '$basis/art/$ref?w=$kHoesPlafond', 'test-token');

      expect(zonder.etag, isNotNull);
      expect(met.etag, isNotNull);
      // **Zonder dit houdt een toestel zijn grote hoes voor altijd.** Het heeft de volle bytes al in
      // zijn cache, met het merkteken daarvan; vraagt het daarna om de kleine met datzelfde
      // merkteken in If-None-Match, dan zou het een lege 304 krijgen en niets vervangen.
      expect(met.etag, isNot(zonder.etag));

      final opnieuw =
          await _haal(client, '$basis/art/$ref?w=$kHoesPlafond', 'test-token', ifNoneMatch: met.etag);
      expect(opnieuw.status, 304, reason: 'hetzelfde plafond hoort wel gewoon een 304 te geven');

      final metOud = await _haal(client, '$basis/art/$ref?w=$kHoesPlafond', 'test-token',
          ifNoneMatch: zonder.etag);
      expect(metOud.status, 200, reason: 'het oude merkteken mag de kleine hoes niet tegenhouden');
    });

    test('DE VAL: de 304 doet het verkleinwerk NIET', () async {
      // **Gemeten op 13-09-2026, en dit was de duurste fout in deze hele wijziging.** Het verkleinen
      // stond voor de If-None-Match-vergelijking, terwijl het merkteken op dat moment al bekend is.
      // Een telefoon die opstart vraagt elke hoes na - bij 544 albums zijn dat 544 lege antwoorden,
      // en die kostten de pc 292 ms per stuk in plaats van 2. Ruim veertig seconden rekenen om
      // niets te versturen.
      //
      // Op een VERSE server, dus met een koude cache: het merkteken valt hier zelf uit te rekenen,
      // want het hangt aan de bron en aan het plafond. Er is geen eerder verzoek voor nodig.
      final bron = await _haal(client, '$basis/art/$ref', 'test-token');
      final verwacht = '"${CoverEnricher.hoesMerk(bron.bytes)}-w$kHoesPlafond"';

      final klok = Stopwatch()..start();
      final r = await _haal(client, '$basis/art/$ref?w=$kHoesPlafond', 'test-token',
          ifNoneMatch: verwacht);
      klok.stop();

      expect(r.status, 304);
      expect(r.bytes, isEmpty);
      // Honderd milliseconden is ruim: de verkleining van deze hoes van 2000 pixels kost er
      // honderden. Het gaat om de orde van grootte, niet om het getal.
      expect(klok.elapsedMilliseconds, lessThan(100),
          reason: 'een 304 die eerst verkleint is geen goedkope 304');
    });

    test('DE VAL: een hoes die niets oplevert wordt maar EEN keer berekend', () async {
      // Het lege antwoord werd niet onthouden, alleen het geslaagde. Een hoes die niet kleiner
      // wordt - acht van de 541 hier - betaalde daardoor bij elk verzoek opnieuw een volledige
      // decode plus hercodering, voor altijd.
      final een = Stopwatch()..start();
      await _haal(client, '$basis/art/$ref?w=1900', 'test-token');
      een.stop();
      final twee = Stopwatch()..start();
      await _haal(client, '$basis/art/$ref?w=1900', 'test-token');
      twee.stop();

      expect(twee.elapsedMilliseconds * 4, lessThan(een.elapsedMilliseconds + 40),
          reason: 'het tweede verzoek hoort uit de cache te komen, ook als er niets te winnen viel');
    });

    test('DE GRENS: een onzinnig plafond verandert niets', () async {
      for (final w in ['0', '-5', 'abc', '7']) {
        final r = await _haal(client, '$basis/art/$ref?w=$w', 'test-token');
        expect(r.status, 200, reason: 'w=$w hoort geen fout te geven');
        expect(img.decodeImage(r.bytes)!.width, 2000,
            reason: 'w=$w is geen plafond en hoort het origineel te laten staan');
      }
    });
  });
}
