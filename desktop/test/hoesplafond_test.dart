library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:debridmusic/artwork.dart';
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
/// niet: de hele catalogus komt over 5G binnen in 0,27 s (211 KB gezipt, 1146 KB onverpakt, eerste
/// byte na 68 ms). De hoezen waren het wel:
///
///     548 hoezen, samen 174 MB
///     mediaan 121 KB / 600 pixel   -- prima
///     grootste 14,7 MB / 2815 pixel
///     58 stuks boven 500 KB
///
/// En de VORM is net zo goed het probleem als de maat: een hoes van 1024x1024 woog 2696 KB omdat hij
/// als PNG was opgeslagen. Datzelfde plaatje als JPEG is ongeveer 120 KB, zonder ook maar een pixel
/// te verliezen.
///
/// Met [kHoesPlafond] over de hele bibliotheek nagemeten: **172,4 MB -> 70,1 MB**, negenenvijftig
/// procent minder, 472 van de 544 hoezen kleiner, en de grootste van 14,7 MB naar 306 KB.
///
/// Wat deze toets vasthoudt is niet dat getal maar de drie regels eronder: verkleinen boven het
/// plafond, hercoderen ook eronder, en - de val - het merkteken moet het plafond MEETELLEN.

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
  return Uint8List.fromList(
      alsPng ? img.encodePng(im) : img.encodeJpg(im, quality: kwaliteit));
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
      // Een kleine hoes die al zuinig bewaard is wordt van hercoderen alleen maar groter. Null
      // betekent hier "niets doen", en dat is beter dan hem nog een generatie door de encoder halen
      // - elke generatie kost zichtbaar detail en levert niets op.
      final zuinig = _foto(300, 300, alsPng: false, kwaliteit: 45);
      expect(verkleindeHoes(zuinig, kHoesPlafond), isNull,
          reason: 'kleiner wordt hij niet, en slechter wel');
      // En wat niet te ontcijferen is ook niet.
      expect(verkleindeHoes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), kHoesPlafond),
          isNull);
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
