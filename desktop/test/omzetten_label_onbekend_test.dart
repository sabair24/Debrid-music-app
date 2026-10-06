/// Op 5G: het label zegt wat er WERKELIJK speelt, en een bestand waarvan de catalogus de maat niet
/// weet wordt toch omgezet.
///
/// **Waarom dit bestaat.** Saber op 06-10-2026, met twee schermafdrukken vanaf mobiele data — *This
/// Time Around* met "FLAC · 24/96" en *Burn* met "FLAC · 24/48": *"sommige nummers worden nog altijd
/// niet omgezet naar 16/44.1 over mobile data?"* Het logboek van de pc (`stroom.log`) zei bij allebei
/// "omgezet naar 16/44100". Ze speelden als vooruit gehaalde KOPIE op het toestel, en die kopie is
/// een pad zonder `maxRate=` erin — dus las het scherm weer het bestand op de pc.
///
/// In hetzelfde logboek stonden wél twee echte gaten. *Mr. Vain* (APE, 24/192, catalogus `0/0`) ging
/// als 216 MB origineel de deur uit, en *Joe Le Taxi* (WavPack, 32 bit op 176,4 kHz, catalogus `32/0`)
/// werd "16/0": 16 bit maar nog op 176,4 kHz, 77 MB.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/ape_kop.dart';
import 'package:debridmusic/lan/stroomstand.dart';
import 'package:debridmusic/lan/transcode.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/library.dart' show moetOpnieuwGelezen;
import 'package:debridmusic/offline.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/wavpack_kop.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('het label boven een vooruit gehaalde kopie', () {
    late Directory map;
    late HttpServer server;
    late OfflineStore vooruit;
    final bytes = List<int>.generate(5000, (i) => i % 251);

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_label_');
      setAppDirForTest(map.path);
      vooruit = OfflineStore(map: 'vooruit', indexNaam: 'vooruit.json');
      await vooruit.load();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.contentLength = bytes.length;
        req.response.add(bytes);
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      vooruit.dispose();
      for (var i = 0; i < 10; i++) {
        try {
          map.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    });

    const pad = r'D:\Flac music 2024\Michael Jackson\Blood On The Dance Floor\This Time Around.flac';
    String adres(String vraag) =>
        'http://127.0.0.1:${server.port}/stream/abc.flac?token=geheim-sleutel$vraag';

    test('DE KERN: een kopie die omgezet binnenkwam weet waarnaar, ook na een herstart', () async {
      expect(
          await vooruit.download(
              libraryPath: pad,
              url: adres('&maxRate=44100&maxBits=16'),
              title: 'This Time Around',
              artist: 'Michael Jackson',
              album: 'Blood On The Dance Floor'),
          isTrue);
      expect(vooruit.grensVoor(pad), (rate: 44100, bits: 16),
          reason: 'zonder dit staat er "FLAC · 24/96" boven een kopie van 16/44.1');

      final opnieuw = OfflineStore(map: 'vooruit', indexNaam: 'vooruit.json');
      await opnieuw.load();
      expect(opnieuw.grensVoor(pad), (rate: 44100, bits: 16),
          reason: 'na een herstart van de app las het label weer het bestand op de pc');
      opnieuw.dispose();

      final index = File('${map.path}${Platform.pathSeparator}vooruit.json').readAsStringSync();
      expect(index, isNot(contains('geheim')),
          reason: 'het adres draagt een sleutel; in de index horen alleen de twee getallen');
    });

    test('DE GRENS: een kopie van het origineel heeft geen grens', () async {
      await vooruit.download(
          libraryPath: pad, url: adres(''), title: 't', artist: 'a', album: 'b');
      expect(vooruit.grensVoor(pad), isNull,
          reason: 'thuis op wifi is de kopie bit voor bit het bestand, en dan klopt het bestandslabel');
    });

    test('DE GRENS: een index van vóór deze versie leest gewoon, zonder grens', () {
      final t = OfflineTrack.fromJson({
        'path': pad,
        'file': '/data/x.flac',
        'bytes': 10,
        'title': 't',
        'artist': 'a',
        'album': 'b',
        'savedAt': '2026-10-05T10:00:00Z',
      });
      expect(t, isNotNull);
      expect(t!.grens, isNull);
      expect(t.toJson().containsKey('grensRate'), isFalse);
    });

    test('DE VAL: de speler vraagt de kopie alleen als er een pad speelt, en dan pas na offline', () {
      final speler = _bron('lib/player.dart');
      final bron = speler.substring(speler.indexOf('String _bron(String path) {'));
      final lijf = bron.substring(0, bron.indexOf('\n  }'));
      expect(lijf, contains("stroomGrens = opDeLijn ?? (url.startsWith('http') ? null : kopieGrens?.call(path));"));
      expect(lijf, contains('_omzetten = opDeLijn != null;'),
          reason: 'een kopie op het toestel hoeft niet omgezet te worden; 25 s geduld is dan te veel');

      final main = _bron('lib/main.dart');
      expect(main,
          contains('(path) => offline.localFor(path) != null ? null : vooruit.grensVoor(path);'),
          reason: 'een zelf bewaarde offline kopie is het origineel en gaat vóór de vooruit gehaalde');
    });
  });

  group('wat de catalogus niet weet', () {
    test('DE KERN: een toestel vraagt bij een onbekende maat om het plafond', () {
      // Mr. Vain: APE, catalogus 0/0.
      final ape = castGrenzen(
          sampleRate: 0, bits: 0, maxSampleRate: 44100, maxBitDepth: 16, onbekendIsTeVeel: true);
      expect(ape, (omzetten: true, rate: 44100, bits: 16),
          reason: 'anders gaat 216 MB op 24/192 onveranderd over 5G');
      // Joe Le Taxi: WavPack, catalogus 32/0.
      final wv = castGrenzen(
          sampleRate: 0, bits: 32, maxSampleRate: 44100, maxBitDepth: 16, onbekendIsTeVeel: true);
      expect(wv, (omzetten: true, rate: 44100, bits: 16),
          reason: '"16/0" was 16 bit op 176,4 kHz: 77 MB');
      // Drivers Seed: AIFF, catalogus 0/44100 — de frequentie zit al onder het plafond, de diepte
      // weet niemand. Ongecomprimeerd 73,5 MB.
      final aiff = castGrenzen(
          sampleRate: 44100, bits: 0, maxSampleRate: 44100, maxBitDepth: 16, onbekendIsTeVeel: true);
      expect(aiff, (omzetten: true, rate: 44100, bits: 16),
          reason: 'een onbekende diepte alleen liet 73,5 MB ongecomprimeerd over 5G gaan');
    });

    test('DE GRENS: voor een speaker blijft een onbekende maat geen reden', () {
      expect(castGrenzen(sampleRate: 44100, bits: 0, maxSampleRate: 48000, maxBitDepth: 24),
          (omzetten: false, rate: 44100, bits: 0));
      expect(castGrenzen(sampleRate: 0, bits: 0, maxSampleRate: 48000, maxBitDepth: 24).omzetten,
          isFalse);
    });

    test('DE KERN: metStand zet een onbekende maat om naar het plafond, op een .flac-adres', () {
      const url = 'http://pc:47820/stream/bdc112840426aa621451e621.ape?token=t';
      final uit = metStand(url, stand: Stroomstand.cd, sampleRate: 0, bits: 0, lossless: true);
      final u = Uri.parse(uit);
      expect(u.pathSegments.last, 'bdc112840426aa621451e621.flac');
      expect(u.queryParameters['maxRate'], '44100');
      expect(u.queryParameters['maxBits'], '16');
      expect(grensUitUrl(uit), (rate: 44100, bits: 16));
    });

    test('DE VAL: de pc meet een onbekende maat na en levert FLAC achter een .flac-adres', () {
      final s = _bron('lib/lan/server.dart');
      final stream = s.substring(s.indexOf('Future<void> _stream(HttpRequest req) async {'));
      final lijf = stream.substring(0, stream.indexOf('\n  }\n'));
      final meet = lijf.indexOf('await transcoder.meet(file)');
      final grens = lijf.indexOf('castGrenzen(');
      expect(meet, isNonNegative, reason: 'zonder nameten beslist de pc op een nul');
      expect(meet, lessThan(grens), reason: 'nameten hoort vóór de beslissing');
      expect(lijf, contains('onbekendIsTeVeel: toestelVraagt,'));
      expect(lijf, contains("toestelVraagt && !grens.omzetten && track.ext.toLowerCase() != 'flac'"),
          reason: 'een AIFF achter een .flac-adres weigert AVFoundation');
      expect(lijf, contains("final toestelVraagt = !vanSpeaker &&"),
          reason: 'een speaker hoort precies te blijven wat hij was');
    });

    test('ffmpeg -i: frequentie en diepte uit de drie vormen die op de pc staan', () {
      expect(
          maatUitFfmpeg('  Stream #0:0: Audio: ape (APE  / 0x20455041), 192000 Hz, stereo, s32p (24 bit)\n'),
          (rate: 192000, bits: 24));
      expect(maatUitFfmpeg('  Stream #0:0: Audio: wavpack, 176400 Hz, stereo, fltp\n'),
          (rate: 176400, bits: 32));
      expect(maatUitFfmpeg('  Stream #0:0: Audio: pcm_s16be, 48000 Hz, stereo, s16, 1536 kb/s\n'),
          (rate: 48000, bits: 16));
      expect(maatUitFfmpeg('  Stream #0:0[0x1](und): Audio: flac, 44100 Hz, stereo, s32 (24 bit)\n'),
          (rate: 44100, bits: 24));
      expect(maatUitFfmpeg('Invalid data found when processing input'), isNull);
      // Een hoes is ook een stroom, maar geen geluid.
      expect(maatUitFfmpeg('  Stream #0:1: Video: mjpeg, yuvj420p, 600x600\n'), isNull);
    });
  });

  group('de koppen zelf', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_kop_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    File schrijf(String naam, List<int> b) =>
        File('${map.path}${Platform.pathSeparator}$naam')..writeAsBytesSync(b);

    List<int> le(int waarde, int n) => [for (var i = 0; i < n; i++) (waarde >> (8 * i)) & 0xFF];

    test('DE KERN: WavPack op 176,4 kHz — de frequentie uit het metablok', () {
      // Zoals de vinylrip van 06-10-2026: tabelindex 15, zwevende komma, en het getal in metablok 0x67.
      final metablokken = <int>[
        0x02, 0x01, 0xAA, 0xBB, // iets anders vooraf
        0x67, 0x02, ...le(176400, 3), 0x00, // ID_SAMPLE_RATE, oneven: 3 echte bytes
        0x8A, 0x02, 0x00, 0x00, 0, 0, 0, 0, // een lang blok, zoals het geluid zelf
      ];
      final vlaggen = (15 << 23) | 0x80;
      final kop = <int>[
        ...'wvpk'.codeUnits, ...le(32 + metablokken.length - 8, 4),
        ...le(0x407, 2), 0, 0,
        ...le(176400 * 234, 4), ...le(0, 4), ...le(0, 4), ...le(vlaggen, 4), ...le(0, 4),
      ];
      final k = readWvKop(schrijf('b1.wv', [...kop, ...metablokken]));
      expect(k, isNotNull);
      expect(k!.sampleRate, 176400, reason: 'de catalogus zei "32/?", en dan kwam er "16/0" uit');
      expect(k.bitsPerSample, 32);
      expect(k.duration, const Duration(seconds: 234));
    });

    test('DE KERN: Monkey\'s Audio 3.99 — Mr. Vain, 24/192, 5:36', () {
      final beschrijving = <int>[
        ...'MAC '.codeUnits, ...le(3990, 2), 0, 0, ...le(52, 4),
        ...List<int>.filled(52 - 12, 0),
      ];
      final kop = <int>[
        ...le(2000, 2), ...le(0, 2), ...le(73728, 4), ...le(442, 4), ...le(878, 4),
        ...le(24, 2), ...le(2, 2), ...le(192000, 4),
      ];
      final k = readApeKop(schrijf('mr_vain.ape', [...beschrijving, ...kop, ...List<int>.filled(64, 0)]));
      expect(k, isNotNull, reason: 'zonder kop stond het als "ape 0/0" in de catalogus');
      expect((k!.sampleRate, k.bitsPerSample, k.channels), (192000, 24, 2));
      expect(k.duration, const Duration(milliseconds: 336770), reason: 'ffprobe zegt 336,770302 s');
    });

    test('DE GRENS: een oude APE (3.97) met een ID3-blok ervoor', () {
      final id3 = <int>[...'ID3'.codeUnits, 3, 0, 0, 0, 0, 0, 20, ...List<int>.filled(20, 0)];
      final kop = <int>[
        ...'MAC '.codeUnits, ...le(3970, 2), ...le(2000, 2), ...le(8, 2), ...le(2, 2),
        ...le(44100, 4), ...le(0, 4), ...le(0, 4), ...le(10, 4), ...le(1000, 4),
        ...List<int>.filled(96, 0),
      ];
      final k = readApeKop(schrijf('oud.ape', [...id3, ...kop]));
      expect(k, isNotNull);
      expect((k!.sampleRate, k.bitsPerSample), (44100, 24), reason: 'vlag 8 is 24 bit');
      // 9 volle frames van 4 x 73.728 plus 1000: 2.655.208 monsters.
      expect(k.duration, const Duration(milliseconds: 60209));
    });

    test('DE GRENS: geen APE is null, geen fout', () {
      expect(readApeKop(schrijf('nep.ape', Uint8List(200))), isNull);
      expect(readApeKop(File('${map.path}${Platform.pathSeparator}bestaat-niet.ape')), isNull);
    });

    test('DE VAL: rijen van vóór deze versie worden één keer opnieuw gelezen', () {
      expect(moetOpnieuwGelezen(r'D:\x\Mr. Vain.ape', {'sampleRate': 0, 'bitsPerSample': 0}), isTrue);
      expect(moetOpnieuwGelezen(r'D:\x\B1.Joe Le Taxi.wv', {'sampleRate': 0, 'bitsPerSample': 32}),
          isTrue, reason: 'anders blijft "32/0" staan tot iemand de map opnieuw inleest');
      expect(moetOpnieuwGelezen(r'D:\x\The Power.wv', {'sampleRate': 192000, 'bitsPerSample': 32}),
          isFalse, reason: 'een goede rij hoort uit de cache te komen');
      expect(moetOpnieuwGelezen(r'D:\x\a.mp3', {'sampleRate': 0, 'bitsPerSample': 0}), isFalse);
    });
  });
}
