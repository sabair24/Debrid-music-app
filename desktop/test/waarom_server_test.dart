/// De pc-kant van `/waarom`: kijkt hij écht naar de bytes op schijf?
///
/// **Waarom dit apart staat van `waarom_vragen_test.dart`.** Die toets speelt de pc na met een
/// verzonnen antwoord en bewijst dat de telefoon het goed vraagt en goed verwerkt. Hier draait de
/// ECHTE server tegen ECHTE bestanden, want het hele punt van deze weg is dat er iemand naar de
/// bytes kijkt. Een toets waarin de pc een nepantwoord geeft zou groen blijven als de server dat
/// nooit doet.
///
/// Het afgekapte bestand hieronder draagt dezelfde verhouding als Stromae - Sommeil op schijf:
/// een kop die 3:38 belooft, en er staat niets in. Zie `kapot_bestand.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een geldige FLAC-kop die [seconden] aan 44,1 kHz stereo 16-bits belooft.
Uint8List flacKop(int seconden) {
  final monsters = seconden * 44100;
  final b = Uint8List(64);
  b.setRange(0, 4, 'fLaC'.codeUnits);
  b[7] = 34; // STREAMINFO is 34 bytes lang
  b[18] = (44100 >> 12) & 0xFF;
  b[19] = (44100 >> 4) & 0xFF;
  b[20] = ((44100 & 0x0F) << 4) | (1 << 1) | 0; // stereo, hoge bit van diepte 16 = 0
  b[21] = (15 << 4) | ((monsters >> 32) & 0x0F); // diepte 16 -> 15
  b[22] = (monsters >> 24) & 0xFF;
  b[23] = (monsters >> 16) & 0xFF;
  b[24] = (monsters >> 8) & 0xFF;
  b[25] = monsters & 0xFF;
  return b;
}

void main() {
  late Directory wortel;
  late LanServer server;
  late String basis;
  late Map<String, String> ids;

  setUp(() async {
    wortel = Directory.systemTemp.createTempSync('waarom_');
    final map = Directory('${wortel.path}/Stromae/Racine carree')..createSync(recursive: true);

    // Afgekapt: de kop belooft 3:38 (38,4 MB onverpakt), er staat 8 KB in. Dat is 0,02 %.
    final kapot = File('${map.path}/11 - Sommeil.flac')
      ..writeAsBytesSync([...flacKop(218), ...List.filled(8 * 1024, 0x42)]);
    // Gezond: een kop die ÉÉN seconde belooft (176 KB onverpakt) met 128 KB eronder. Dat is 74 %,
    // vlak bij de mediaan van 70 % die op de echte schijf gemeten is. Kort gehouden omdat een
    // eerlijke verhouding bij 3:38 een tijdelijk bestand van 27 MB zou kosten.
    final heel = File('${map.path}/01 - Ta fete.flac')
      ..writeAsBytesSync([...flacKop(1), ...List.filled(128 * 1024, 0x42)]);
    // Leeg, het duidelijkste geval en het meest voorkomende.
    final leeg = File('${map.path}/02 - Papaoutai.flac')..writeAsBytesSync(const []);

    final library = LibraryStore()
      ..rootPath = wortel.path
      ..configDirOverride = wortel.path;
    for (final e in [
      (kapot, 'Sommeil'),
      (heel, 'Ta fete'),
      (leeg, 'Papaoutai'),
    ]) {
      library.tracks.add(Track(
        path: e.$1.path,
        title: e.$2,
        artist: 'Stromae',
        album: 'Racine carree',
        isFlac: true,
        sizeBytes: e.$1.lengthSync(),
        duration: const Duration(seconds: 218),
      ));
    }
    library.rebuildAlbums();

    server = LanServer(
      library: library,
      token: 'sleutel',
      state: LanStateStore(File('${wortel.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
    );
    expect(await server.start(), isNull);
    basis = 'http://127.0.0.1:${server.boundPort}';

    // `streamPath` is `/stream/<id>.flac` — de extensie zit er AL in, want AVFoundation typeert
    // een bestand op zijn pad. Hier de kale id, zodat beide vormen los te toetsen zijn.
    ids = {
      for (final t in server.catalog.snapshot().catalog.tracks)
        t.title: t.streamPath.split('/').last.split('.').first,
    };
  });

  tearDown(() async {
    await server.dispose();
    wortel.deleteSync(recursive: true);
  });

  Future<HttpClientResponse> vraag(String id) async {
    final c = HttpClient();
    final req = await c.getUrl(Uri.parse('$basis/waarom/$id?token=sleutel'));
    return req.close();
  }

  Future<String?> reden(String titel) async {
    final res = await vraag(ids[titel]!);
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final body = jsonDecode(await res.transform(utf8.decoder).join());
    return (body as Map)['reden'] as String?;
  }

  group('de pc kijkt naar zijn eigen bytes', () {
    test('DE KERN: een afgekapt bestand levert de zin op', () async {
      expect(await reden('Sommeil'), contains('afgekapt'),
          reason: 'dit is wat de telefoon in plaats van "Error decoding audio" hoort te krijgen');
    });

    test('DE KERN: een leeg bestand ook', () async {
      expect(await reden('Papaoutai'), contains('leeg'));
    });

    test('DE VAL: over een gezond bestand zegt hij NIETS (204)', () async {
      // Verreweg de meeste mislukte openingen liggen aan de verbinding. Zou hier een zin komen,
      // dan kreeg de gebruiker een verklaring over zijn bestand terwijl zijn wifi het deed.
      final res = await vraag(ids['Ta fete']!);
      await res.drain<void>();
      expect(res.statusCode, HttpStatus.noContent);
    });

    test('DE GRENS: de extensie in het adres hoort er niet bij de id', () async {
      // `/stream/<id>.flac` bestaat omdat AVFoundation een bestand op zijn pad typeert. De
      // telefoon bouwt `/waarom/` uit precies die url, dus die punt komt hier gewoon mee.
      final res = await vraag('${ids['Sommeil']!}.flac');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.transform(utf8.decoder).join());
      expect((body as Map)['reden'], contains('afgekapt'));
    });

    test('DE GRENS: een onbekende id is 404 en geen verzonnen antwoord', () async {
      final res = await vraag('bestaat-niet');
      await res.drain<void>();
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('DE GRENS: zonder sleutel komt er niets uit', () async {
      // Deze weg leest bestandsnamen en groottes van de schijf van de gebruiker. Hij hoort achter
      // dezelfde deur te staan als de rest, en niet per ongeluk naast `/health` te belanden.
      final c = HttpClient();
      final req = await c.getUrl(Uri.parse('$basis/waarom/${ids['Sommeil']!}'));
      final res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, anyOf(HttpStatus.unauthorized, HttpStatus.forbidden));
    });

    test('DE GRENS: een bestand dat van de schijf verdween', () async {
      File(server.library.tracks.firstWhere((t) => t.title == 'Sommeil').path).deleteSync();
      expect(await reden('Sommeil'), contains('staat er niet meer'));
    });
  });
}
