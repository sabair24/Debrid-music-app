// Spelen terwijl het binnenkomt (groeistroom.dart): de server tegen een echte HTTP-client, met een bestand
// dat groeit, een uploader die afhaakt, en opbergen terwijl het klinkt. De proef met de echte libmpv staat
// in de kladmap (`stroomproef/groei_mpv.dart`); hier wat de bouwstraat zonder mpv kan nagaan.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/groeistroom.dart';
import 'package:debridmusic/online.dart' show DownloadManager;
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/radiobestand.dart';
import 'package:debridmusic/soulseek.dart' show SoulseekFile;
import 'package:flutter_test/flutter_test.dart';

typedef _Antwoord = ({int status, HttpHeaders? kop, List<int> lijf, Object? fout});

Future<_Antwoord> _haal(String adres, {String? bereik, void Function(int binnen)? bijBytes}) async {
  final c = HttpClient();
  final lijf = <int>[];
  int status = 0;
  HttpHeaders? kop;
  try {
    final req = await c.getUrl(Uri.parse(adres));
    if (bereik != null) req.headers.set(HttpHeaders.rangeHeader, bereik);
    final res = await req.close();
    status = res.statusCode;
    kop = res.headers;
    await for (final b in res.timeout(const Duration(seconds: 10))) {
      lijf.addAll(b);
      bijBytes?.call(lijf.length);
    }
    return (status: status, kop: kop, lijf: lijf, fout: null);
  } catch (e) {
    return (status: status, kop: kop, lijf: lijf, fout: e);
  } finally {
    c.close(force: true);
  }
}

Uint8List _bytes(int n, {int zaad = 7}) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + zaad) & 0xFF]);

int _crc8(List<int> b) {
  var crc = 0;
  for (final x in b) {
    crc ^= x;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xFF : (crc << 1) & 0xFF;
    }
  }
  return crc;
}

/// Een zelfgebouwde FLAC (zie flac_frames_test.dart): STREAMINFO, opvulling, frames van 4096 monsters.
({Uint8List bytes, int audioBegin, List<int> frameBegin}) _flac({int frames = 60, int vulling = 0}) {
  final si = ByteData(34)
    ..setUint16(0, 4096)
    ..setUint16(2, 4096)
    ..setUint64(10, (44100 << 44) | (1 << 41) | (15 << 36) | (frames * 4096));
  final b = BytesBuilder()
    ..add('fLaC'.codeUnits)
    ..add([0x00, 0, 0, 34])
    ..add(si.buffer.asUint8List())
    ..add([0x81, 0, 0x10, 0x00])
    ..add(Uint8List(4096));
  final audioBegin = b.length;
  final begin = <int>[];
  for (var n = 0; n < frames; n++) {
    begin.add(b.length);
    final kop = [0xFF, 0xF8, 0xC9, 0x18, if (n < 0x80) n else ...[0xC0 | (n >> 6), 0x80 | (n & 0x3F)]];
    kop.add(_crc8(kop));
    b
      ..add(kop)
      ..add([0x00, 0x12, 0x34, 0x00, 0x12, 0x34])
      ..add(List.filled(vulling, 0x55))
      ..add([0x00, 0x00]);
  }
  return (bytes: b.toBytes(), audioBegin: audioBegin, frameBegin: begin);
}

/// Wacht tot [klopt] waar is, of faalt na twee seconden.
Future<void> _totDat(bool Function() klopt) async {
  final eind = DateTime.now().add(const Duration(seconds: 5));
  while (!klopt()) {
    if (DateTime.now().isAfter(eind)) fail('wachtte te lang');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory map;
  late Groeistroom server;
  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_groei_');
    server = Groeistroom(
        wachtOpPoging: const Duration(seconds: 2),
        stilGrens: const Duration(seconds: 3),
        peil: const Duration(milliseconds: 20));
  });
  tearDown(() async {
    await server.stop();
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  String pad(String naam) => '${map.path}${Platform.pathSeparator}$naam';

  group('de server', () {
    test('een bestand dat nog groeit: het antwoord belooft de volle grootte, wacht, en levert alles', () async {
      final alles = _bytes(600 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles.sublist(0, 100 * 1024));
      final g = await server.nieuw('groeit');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 60));
      final antwoord = _haal(g.adres);
      for (var i = 2; i <= 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        f.writeAsBytesSync(alles.sublist(0, i * 100 * 1024));
      }
      final a = await antwoord;
      expect(a.fout, isNull);
      expect(a.status, 200);
      expect(a.kop!.contentLength, alles.length, reason: 'de volle grootte, vooraf: anders stopt mpv bij wat er staat');
      expect(a.lijf, alles);
    });

    test('een sprong midden in het bestand krijgt die bytes, met Content-Range', () async {
      final alles = _bytes(300 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles);
      final g = await server.nieuw('sprong');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 30));
      await _haal(g.adres); // eerst de kop, zoals mpv
      final a = await _haal(g.adres, bereik: 'bytes=1000-');
      expect(a.status, 206);
      expect(a.kop!.value(HttpHeaders.contentRangeHeader), 'bytes 1000-${alles.length - 1}/${alles.length}');
      expect(a.lijf, alles.sublist(1000));
    });

    test('een sprong voorbij wat er al binnen is: meteen nee (ffmpeg zoekt dan verder terug), niet wachten',
        () async {
      final alles = _bytes(400 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles.sublist(0, 100 * 1024));
      final g = await server.nieuw('vooruit');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 40));
      await _haal(g.adres, bereik: 'bytes=0-1023');
      final klok = Stopwatch()..start();
      final eind = await _haal(g.adres, bereik: 'bytes=${alles.length - 1024}-');
      expect(eind.status, 416, reason: 'gemeten: anders 9 s wachten op het einde van de download');
      expect(klok.elapsed, lessThan(const Duration(seconds: 1)));
      // Binnen wat er staat: gewoon de bytes.
      final binnen = await _haal(g.adres, bereik: 'bytes=50000-50999');
      expect(binnen.lijf, alles.sublist(50000, 51000));
      // Compleet: dan bestaat het einde wel.
      f.writeAsBytesSync(alles);
      await g.binnen();
      expect((await _haal(g.adres, bereik: 'bytes=${alles.length - 1024}-')).lijf, alles.sublist(alles.length - 1024));
    });

    test('verder op een plek (?vanaf=): de kop en dan de frames vanaf het frame van die tijd — zonder sprong',
        () async {
      final fl = _flac(frames: 60, vulling: 2000);
      final f = File(pad('in.flac'))..writeAsBytesSync(fl.bytes.sublist(0, fl.frameBegin[40]));
      final g = await server.nieuw('vanaf');
      g.poging(pad: f.path, totaal: fl.bytes.length);
      g.goedgekeurd(const Duration(milliseconds: 60 * 4096 * 1000 ~/ 44100), kopBytes: fl.audioBegin);
      // 1,9 s = monster 83790: in frame 20 (81920–86015).
      var binnen = 0;
      final antwoord = _haal('${g.adres}?vanaf=1900', bijBytes: (n) => binnen = n);
      await _totDat(() => binnen > 0);
      f.writeAsBytesSync(fl.bytes); // de rest komt binnen
      final a = await antwoord;
      final verwacht = [...fl.bytes.sublist(0, fl.audioBegin), ...fl.bytes.sublist(fl.frameBegin[20])];
      expect(a.kop!.contentLength, verwacht.length);
      expect(a.lijf, verwacht, reason: 'de kop van het bestand, en dan meteen frame 20');
      // Een sprong daarbinnen wordt omgerekend naar het echte bestand.
      final sprong = await _haal(g.adres, bereik: 'bytes=${fl.audioBegin + 10}-');
      expect(sprong.lijf, fl.bytes.sublist(fl.frameBegin[20] + 10));
    });

    test('een uploader die afhaakt: een breuk, en daarna een leeg EINDE voor ffmpeg — geen 410', () async {
      final alles = _bytes(400 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles.sublist(0, 200 * 1024));
      final g = await server.nieuw('afgehaakt');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 40));
      var binnen = 0;
      final antwoord = _haal(g.adres, bijBytes: (n) => binnen = n);
      await _totDat(() => binnen >= 200 * 1024);
      g.afgebroken();
      final a = await antwoord;
      expect(a.fout, isA<HttpException>(), reason: 'minder dan beloofd = een breuk, geen netjes einde');
      expect(a.lijf.length, 200 * 1024);
      // ffmpeg verbindt opnieuw op dezelfde byte. Op 410 bleef hij het een minuut proberen; dit zegt dat
      // het bestand hier ophoudt.
      final weer = await _haal(g.adres, bereik: 'bytes=${200 * 1024}-');
      expect(weer.status, 206);
      expect(weer.kop!.contentLength, 0);
      expect(weer.kop!.value(HttpHeaders.contentRangeHeader), 'bytes ${200 * 1024}-${200 * 1024}/${200 * 1024}');
    });

    test('na het binnenkomen uit het geheugen: verplaatsen en tags schrijven raken een lopende stroom niet',
        () async {
      final alles = _bytes(500 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles.sublist(0, 300 * 1024));
      final g = await server.nieuw('opbergen');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 50));
      var binnen = 0;
      final antwoord = _haal(g.adres, bijBytes: (n) => binnen = n);
      await _totDat(() => binnen >= 300 * 1024);
      f.writeAsBytesSync(alles); // compleet
      await g.binnen();
      // Opbergen: verplaatsen (op Windows alleen als niemand hem open heeft) en de audio verschuiven.
      final bib = File(pad('bib.flac'));
      f.renameSync(bib.path);
      bib.writeAsBytesSync([...List.filled(4096, 0), ...alles]);
      g.geland(bib.path);
      final a = await antwoord;
      expect(a.fout, isNull);
      expect(a.lijf, alles, reason: 'mpv las de kop van HET OUDE bestand: dus ook de rest van dat bestand');
      // En een sprong daarna komt ook uit het geheugen.
      final sprong = await _haal(g.adres, bereik: 'bytes=${400 * 1024}-');
      expect(sprong.lijf, alles.sublist(400 * 1024));
    });

    test('niemand luisterde: niets in het geheugen, en wie daarna opent krijgt het opgeborgen bestand',
        () async {
      final alles = _bytes(200 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles);
      final g = await server.nieuw('stil');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 20));
      await g.binnen();
      final bib = File(pad('bib.flac'));
      f.renameSync(bib.path);
      final getagd = [...List.filled(1000, 1), ...alles];
      bib.writeAsBytesSync(getagd);
      g.geland(bib.path);
      final a = await _haal(g.adres);
      expect(a.lijf, getagd);
    });

    test('compleet vóór de speler opent, maar iemand wil het meteen horen: uit het geheugen, niet wachten',
        () async {
      // Gemeten op de pc (3.9.522, Do I Wanna Know?): 50 MB in één tel, 145 ms vóór mpv opende; mpv's
      // verzoek wachtte op het opbergen en begon daarna opnieuw — een seconde te laat.
      final alles = _bytes(300 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles);
      final g = await server.nieuw('snel');
      g.zalKlinken();
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 30));
      await g.binnen(); // nog niemand die luistert
      final klok = Stopwatch()..start();
      final antwoord = _haal(g.adres);
      // De keuring en het opbergen duren even; intussen hoort mpv al te krijgen wat er is.
      final a = await antwoord.timeout(const Duration(milliseconds: 1200), onTimeout: () => fail('wachtte op het opbergen'));
      expect(klok.elapsed, lessThan(const Duration(milliseconds: 1200)));
      expect(a.fout, isNull);
      expect(a.lijf, alles);
      final bib = File(pad('bib.flac'));
      f.renameSync(bib.path);
      bib.writeAsBytesSync([...List.filled(700, 3), ...alles]);
      g.geland(bib.path);
      final sprong = await _haal(g.adres, bereik: 'bytes=${200 * 1024}-');
      expect(sprong.lijf, alles.sublist(200 * 1024), reason: 'een sprong daarna: dezelfde bytes als de kop die mpv las');
    });

    test('een stroom zonder geheugen die het opbergen meemaakt: breuk, en een vervolg krijgt het einde', () async {
      final klein = Groeistroom(peil: const Duration(milliseconds: 20), vastPlafond: 1024);
      addTearDown(klein.stop);
      final alles = _bytes(300 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles.sublist(0, 100 * 1024));
      final g = await klein.nieuw('te groot');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 30));
      var binnen = 0;
      final antwoord = _haal(g.adres, bijBytes: (n) => binnen = n);
      await _totDat(() => binnen >= 100 * 1024);
      f.writeAsBytesSync(alles);
      await g.binnen(); // te groot: niet vastgehouden
      final bib = File(pad('bib.flac'));
      f.renameSync(bib.path);
      bib.writeAsBytesSync([...List.filled(500, 2), ...alles]);
      g.geland(bib.path);
      final a = await antwoord;
      expect(a.fout, isNotNull, reason: 'nooit verder op dezelfde byte van een ánder bestand');
      final weer = await _haal(g.adres, bereik: 'bytes=${a.lijf.length}-');
      expect(weer.kop!.contentLength, 0);
      // Opnieuw openen vanaf nul: het opgeborgen bestand, helemaal.
      final opnieuw = await _haal(g.adres);
      expect(opnieuw.lijf.length, alles.length + 500);
    });

    test('tijdens het stromen houdt de server het bestand niet open (Windows weigert dan te verplaatsen)',
        () async {
      final alles = _bytes(300 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles.sublist(0, 150 * 1024));
      final g = await server.nieuw('handvat');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 30));
      var binnen = 0;
      final antwoord = _haal(g.adres, bijBytes: (n) => binnen = n);
      await _totDat(() => binnen >= 150 * 1024);
      // De stroom wacht nu op meer. Verplaatsen moet kunnen — en terug.
      final elders = pad('elders.flac');
      f.renameSync(elders);
      File(elders).renameSync(f.path);
      f.writeAsBytesSync(alles);
      final a = await antwoord;
      expect(a.lijf, alles);
    });

    test('openen wacht op een goedgekeurde uploader; zonder uploader een nee', () async {
      final alles = _bytes(100 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles);
      final g = await server.nieuw('later');
      final antwoord = _haal(g.adres);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      g.poging(pad: f.path, totaal: alles.length);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      g.goedgekeurd(const Duration(seconds: 10));
      final a = await antwoord;
      expect(a.lijf, alles, reason: 'pas na de goedkeuring, en dan alles');

      final niets = await server.nieuw('niets');
      final wacht = _haal(niets.adres);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      niets.opgegeven();
      expect((await wacht).status, 404);
      expect(await niets.speelbaar, isFalse);
    });

    test('een afgekeurde kop klinkt nooit: niet goedgekeurd = geen bytes', () async {
      final f = File(pad('in.flac'))..writeAsBytesSync(_bytes(50 * 1024));
      final g = await server.nieuw('afgekeurd');
      g.poging(pad: f.path, totaal: 50 * 1024);
      final a = await _haal(g.adres);
      expect(a.status, 503, reason: 'na wachtOpPoging (2 s): nog steeds niets goedgekeurd');
      expect(a.lijf, isEmpty);
    });

    test('speelbaarVanaf: compleet = meteen ja; de volgende uploader telt; sluiten = nee', () async {
      final alles = _bytes(100 * 1024);
      final f = File(pad('in.flac'))..writeAsBytesSync(alles);
      final g = await server.nieuw('vanaf');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 10));
      await g.binnen();
      expect(await g.speelbaarVanaf(const Duration(seconds: 5)), isTrue);

      final h = await server.nieuw('gesloten');
      final w = h.speelbaarVanaf(const Duration(seconds: 3));
      h.sluit();
      expect(await w, isFalse);
    });

    test('van(adres) vindt de groei terug; een ander adres niet', () async {
      final g = await server.nieuw('terug');
      expect(server.van(g.adres), same(g));
      expect(server.van('http://127.0.0.1:47820/stream/1'), isNull);
      expect(Groeistroom.isAdres(g.adres), isTrue);
      expect(Groeistroom.isAdres(r'D:\Muziek\a.flac'), isFalse);
    });
  });

  group('wanneer het mag klinken', () {
    const duur = Duration(seconds: 200);
    const totaal = 20 * 1000 * 1000; // 100 kB/s verbruik

    test('een snellere uploader met weinig vooruit: na drie seconden meten, niet eerder', () {
      // 1 MB = 10 s muziek: te weinig om een wissel te overbruggen, dus de volle drie seconden.
      bool mag(Duration gemeten) => magBeginnen(
          binnen: 1000000, totaal: totaal, duur: duur, snelheid: 500000, gemeten: gemeten);
      expect(mag(const Duration(seconds: 2)), isFalse);
      expect(mag(const Duration(seconds: 3)), isTrue);
    });

    test('ruim vlot en ruim vooruit (15 s muziek): al na driekwart seconde', () {
      bool mag(int binnen, Duration gemeten, {double snelheid = 3000000}) => magBeginnen(
          binnen: binnen, totaal: totaal, duur: duur, snelheid: snelheid, gemeten: gemeten);
      expect(mag(1600000, const Duration(milliseconds: 750)), isTrue, reason: '16 s vooruit, 30× het verbruik');
      expect(mag(1600000, const Duration(milliseconds: 500)), isFalse, reason: 'een halve tel is geen meting');
      expect(mag(1400000, const Duration(milliseconds: 750)), isFalse, reason: '14 s: niet genoeg voor een wissel');
      expect(mag(1600000, const Duration(milliseconds: 750), snelheid: 150000), isFalse,
          reason: 'anderhalf keer het verbruik is niet ruim vlot');
    });

    test('een tragere uploader: pas als de voorsprong het hele nummer overbrugt, met 30 % marge', () {
      // 85 kB/s tegen 100 kB/s verbruik: 15 % van 20 MB = 3 MB achterstand, ×1,3 = 3,9 MB, + 8 s reserve.
      bool mag(int binnen) => magBeginnen(
          binnen: binnen, totaal: totaal, duur: duur, snelheid: 85000, gemeten: const Duration(seconds: 30));
      expect(mag(4000000), isFalse);
      expect(mag(3900000 + 800000 + 1000), isTrue);
      expect(mag(3900000 + 700000), isFalse, reason: 'de reserve van 8 s telt mee');
    });

    test('vanaf een plek midden in het nummer: wat vóór die plek staat, telt niet als voorsprong', () {
      bool mag(int binnen, Duration vanaf) => magBeginnen(
          binnen: binnen,
          totaal: totaal,
          duur: duur,
          snelheid: 500000,
          gemeten: const Duration(seconds: 10),
          vanaf: vanaf);
      // Op 100 s staat de speelplek op 10 MB: 10,1 MB binnen is maar 100 kB voorsprong.
      expect(mag(10100000, const Duration(seconds: 100)), isFalse);
      expect(mag(10500000, const Duration(seconds: 100)), isTrue);
      expect(mag(totaal, const Duration(seconds: 150)), isTrue, reason: 'compleet = altijd');
    });

    test('een hoes in de kop telt niet als audio', () {
      // 5 MB kop (een hoes) en pas 100 kB audio: bij een snelle uploader zou de kop anders als 50 s
      // voorsprong tellen, terwijl er nog geen seconde muziek staat.
      bool mag(int binnen) => magBeginnen(
          binnen: binnen,
          totaal: totaal + 5000000,
          duur: duur,
          snelheid: 500000,
          gemeten: const Duration(seconds: 10),
          kop: 5000000);
      expect(mag(5000000 + 100 * 1024), isFalse);
      expect(mag(5000000 + 300 * 1024), isTrue);
    });

    test('een stilgevallen uploader nooit', () {
      expect(
          magBeginnen(
              binnen: 15000000, totaal: totaal, duur: duur, snelheid: 0, gemeten: const Duration(seconds: 9)),
          isFalse);
    });

    test('de snelheid: de traagste van het gemiddelde en de laatste drie seconden', () {
      final m = [
        (t: Duration.zero, bytes: 0),
        (t: const Duration(seconds: 5), bytes: 5000000), // 1 MB/s
        (t: const Duration(seconds: 8), bytes: 5300000), // daarna 100 kB/s
      ];
      expect(voorzichtigeSnelheid(m), closeTo(100000, 1));
    });
  });

  group('vroeg beginnen terwijl het zoeken loopt', () {
    SoulseekFile f(String naam,
            {String peer = 'p', bool vrij = true, int snelheid = 2000000, int? sec = 230, int grootte = 30000000}) =>
        SoulseekFile(
            username: peer,
            filename: 'Muziek\\Kygo\\Singles\\$naam',
            size: grootte,
            freeSlots: vrij,
            speed: snelheid,
            durationSec: sec,
            sampleRate: 44100,
            bitDepth: 16);
    SoulseekFile? kies(List<SoulseekFile> l, {Set<String> nietBij = const {}}) => DownloadManager.vroegeKandidaat(l,
        artiest: 'Kygo', titel: 'Before You Know It', seconden: 231, nietBij: nietBij);

    test('alleen FLAC, met een vrije plek, vlot, door de zeef — anders wachten op de hele uitslag', () {
      expect(kies([f('01 - Kygo - Before You Know It.flac')])?.username, 'p');
      expect(kies([f('01 - Kygo - Before You Know It.mp3')]), isNull, reason: 'alleen FLAC klinkt al terwijl het binnenkomt');
      expect(kies([f('01 - Kygo - Before You Know It.flac', vrij: false)]), isNull, reason: 'een wachtrij is geen vroeg begin');
      expect(kies([f('01 - Kygo - Before You Know It.flac', snelheid: 100000)]), isNull, reason: 'te traag opgegeven');
      expect(kies([f('01 - Kygo - Before You Know It (Live).flac')]), isNull, reason: 'dezelfde zeef: geen live');
      expect(kies([f('01 - Kygo - Before You Know It.flac', sec: 300)]), isNull, reason: 'een andere lengte');
      expect(kies([f('01 - Kygo - Before You Know It.flac', peer: 'weg')], nietBij: {'weg'}), isNull);
    });

    test('binnen wat mag: de officiële lengte voorop', () {
      final k = kies([
        f('01 - Kygo - Before You Know It.flac', peer: 'lang', sec: 240),
        f('01 - Kygo - Before You Know It.flac', peer: 'juist', sec: 231),
      ]);
      expect(k?.username, 'juist');
    });

    test('alleen de officiële lengte (±2 s) begint vroeg — in een wedloop wint wie het eerst stuurt', () {
      // Saber, 20-10-2026: "wel letten dat hij de juiste song binnenhaalt, zoals in de app al zit".
      expect(kies([f('01 - Kygo - Before You Know It.flac', sec: 233)])?.username, 'p', reason: '2 s scheelt: dezelfde opname');
      expect(kies([f('01 - Kygo - Before You Know It.flac', peer: 'lang', sec: 240)]), isNull,
          reason: 'binnen de radiomarge (15 s), maar niet de lengte: pas in de hele uitslag, en dan pas na de juiste');
      expect(kies([f('01 - Kygo - Before You Know It.flac', sec: null)]), isNull, reason: 'onbekend is geen voorrang');
      expect(
          DownloadManager.vroegeKandidaat([f('01 - Kygo - Before You Know It.flac', sec: 240)],
                  artiest: 'Kygo', titel: 'Before You Know It', seconden: null)
              ?.username,
          'p',
          reason: 'zonder officiële lengte valt er niets te kiezen');
      final online = File('lib/online.dart').readAsStringSync();
      final haal = online.substring(online.indexOf('  Future<String?> _haalVoorRadio('));
      expect(haal, contains('for (final deel in lengteDelen(flac, seconden)) {'),
          reason: 'de hele uitslag: eerst de juiste lengte als wedloop, dan pas de rest');
      expect(haal, contains('final over = deel.where(vrij).toList();\n            if (over.isEmpty) break;'));
    });

    test('de haal begint vroeg en valt terug op de hele uitslag zonder wie afviel', () {
      final online = File('lib/online.dart').readAsStringSync();
      final haal = online.substring(online.indexOf('  Future<String?> _haalVoorRadio('));
      expect(haal, contains('final eerste = vroeg == null ? null : await vroegeKeus.future;'));
      expect(haal, contains('if (wedloop != _Uit.volgende) return;'));
      expect(haal, contains('viel: (u) => (_radioNietBij[sleutel] ??= {}).add(u));'));
      expect(haal, contains('onPartial: vroeg == null'), reason: 'zonder groeistroom zoals altijd: de hele uitslag');
    });

    test('▶ naast elke downloadknop: Online zoeken, een albumpagina, een ontbrekend nummer — dezelfde weg', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(RegExp(r'SpeelNuKnop\(').allMatches(main).length, greaterThanOrEqualTo(3));
      expect(main, contains('SpeelNuKnop(artiest: t.artist, titel: t.title, seconden: t.seconden, album: t.album, hoes: t.cover),'),
          reason: 'Online zoeken, met album en hoes');
      expect(main, contains("artiest: t.artist.isEmpty ? widget.artistName : t.artist,"), reason: 'een albumpagina');
      expect(main, contains('artiest: widget.artiest, titel: s.title, seconden: s.seconds, grootte: 20, album: widget.tags?.album),'),
          reason: 'een ontbrekend nummer van een album dat je hebt');
      expect(main, contains('artiest: artiest, titel: titel, seconden: seconden, album: album, hoesUrl: hoes),'));
      // De hoes tijdens het streamen (20-10-2026): het album gaat mee, en de hoes staat er zodra het klinkt.
      expect(main, contains("speler.playUrl(vroeg.adres, title: titel, artist: artiest, album: album ?? '');"));
      expect(main, contains('toonHoes(vroeg.adres);'));
      expect(main, contains('toonHoes(g.pad);'));
      expect(main, contains('hoes: widget.album.cover),'), reason: 'een albumpagina, met de hoes van de uitgave');
      expect(main, contains('Future<void> speel(BuildContext context, NieuwNummer n) => speelNummer(context,'),
          reason: 'een nieuw nummer gaat door dezelfde functie');
    });

    test('de vroege start is een wedloop: dertig tegelijk vanaf de start, de eerste wint', () {
      final online = File('lib/online.dart').readAsStringSync();
      final w = online.substring(online.indexOf('  Future<({SoulseekFile f, SlskResult res, bool afgekeurd})?> _wedloop('));
      final lijf = w.substring(0, w.indexOf('\n  }\n'));
      expect(online, contains('static const kWedloopTegelijk = 30;'), reason: 'elke loper erbij vergroot de kans');
      expect(online, contains('static const kWedloopLopers = 60;'), reason: 'wie in een rij staat, neemt geen plaats in');
      expect(online, contains('static const _maxLosslessTries = 20;'));
      expect(online, isNot(contains('kWedloopTussen')), reason: 'niet meer na elkaar, maar samen');
      expect(lijf, contains('if (winnaar != null) return false;'), reason: 'maar één winnaar');
      expect(lijf, contains('if (e.key != f) e.value.stop.cancel();'), reason: 'de verliezers stoppen meteen');
      expect(lijf, contains('while (winnaar == null && lopers.length < kWedloopLopers && bezig() < kWedloopTegelijk) {'));
      expect(lijf, contains('int bezig() => lopers.keys.where((l) => !klaar.contains(l) && !inRij.contains(l)).length;'),
          reason: 'Beautiful Things: negen in een rij hielden dertig plaatsen 17,7 s bezet');
      expect(lijf, contains('final res = _rawTransfer(session, f, job, () => inRij.add(f),'));
      expect(lijf, contains('start(eerste);\n    vulAan();\n    while'), reason: 'meteen samen, niet pas na een wachttijd');
      expect(lijf, contains('      vulAan();\n      if (lopers.length == klaar.length) break;'),
          reason: 'wie afvalt maakt plaats; niemand meer over = opgeven');
      expect(lijf.indexOf('_vroegKeuren('), greaterThan(lijf.indexOf('final w = winnaar;')),
          reason: 'alleen de winnaar meldt zich bij de groeistroom');
      final haal = online.substring(online.indexOf('  Future<String?> _haalVoorRadio('));
      expect(haal, contains('final wedloop = await probeer(eerste,'));
      expect(haal, contains('final uit = await probeer(over.first, mee: (al) {'), reason: 'ook de volledige lijst als wedloop');
      expect(haal, contains('if (vroeg == null) {\n          for (final f in kandidaten.take(3)) {'),
          reason: 'zonder groeistroom zoals altijd');
    });

    test('met een groeistroom nooit een mp3: alleen FLAC in de wedloop, mp3-alleen = niets bruikbaars', () {
      final online = File('lib/online.dart').readAsStringSync();
      final haal = online.substring(online.indexOf('  Future<String?> _haalVoorRadio('));
      expect(haal, contains('if (vroeg == null) ...bruikbaar.where((f) => !isLossless(f)),'),
          reason: 'in een wedloop wint wie het eerst stuurt — een mp3 zou een FLAC kunnen verslaan');
      expect(haal, contains('final flac = kandidaten.where(stroombaar).toList();'));
      expect(haal, contains('for (final deel in lengteDelen(flac, seconden)) {'), reason: 'de wedloop loopt alleen over FLAC');
      expect(haal, contains('for (final f in kandidaten.where(isLossless).take(3)) {'),
          reason: 'zonder FLAC nog een AIFF of WAV, nooit lossy');
      expect(haal, contains('if (kandidaten.isEmpty && alleenMp3 > 0) {'), reason: 'na te lezen in het logboek');
    });

    test('een volgende ronde: wie uit zichzelf afviel blijft weg, wie stopte omdat een ander won doet weer mee', () {
      final online = File('lib/online.dart').readAsStringSync();
      final w = online.substring(online.indexOf('  Future<({SoulseekFile f, SlskResult res, bool afgekeurd})?> _wedloop('));
      final lijf = w.substring(0, w.indexOf('\n  }\n'));
      expect(lijf, contains('if (winnaar == null && !job.cancelled) {\n          viel?.call(f.username);'));
      expect(lijf, contains(r"_log.line('   $u');"), reason: 'zonder winnaar: per uploader waarom hij afviel');
      final haal = online.substring(online.indexOf('  Future<String?> _haalVoorRadio('));
      expect(haal, contains('bool vrij(SoulseekFile k) => !(_radioNietBij[sleutel]?.contains(k.username) ?? false);'));
      expect(haal, isNot(contains('geprobeerd.add(')),
          reason: 'met twintig tegelijk zou "al geprobeerd" na één mislukte winnaar de hele lijst opmaken');
      expect(lijf, contains(r"'(loper #${lopers.keys.toList().indexOf(w) + 1} van $lopend, $afgevallen al afgevallen)"),
          reason: 'meten of de lopers achteraan ooit winnen');
    });

    test('zuinig zoeken: vond een ronde niets wat dit nummer is, dan geen tweede en derde ronde', () {
      final online = File('lib/online.dart').readAsStringSync();
      expect(online, contains('if (kandidaten.isEmpty && nietBij.isEmpty) {\n        _radioZonderKandidaat.add(sleutel);'));
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('if (t == null && dm != null && dm.vondGeenKandidaat(artiest, titel)) break;'));
    });

    test('de laatste tik wint: een eerder nummer neemt de speler niet meer over', () {
      final main = File('lib/main.dart').readAsStringSync();
      final speel = main.substring(main.indexOf('class NieuwSpeler'), main.indexOf('File get _nieuwOpToestel'));
      expect(speel, contains('bool magNog() => mijnTik == _tikken && speler.keuzes == keuzes;'));
      expect(speel, contains('if (!kan || klaar || !magNog()) return;'), reason: 'niet gaan klinken');
      expect(speel, contains('} else if (magNog()) {\n          speler.playQueue([t], 0);'), reason: 'niet na het landen');
      final player = File('lib/player.dart').readAsStringSync();
      for (final m in ['Future<void> playQueue(', 'Future<void> playUrl(', 'Future<void> playRadio(']) {
        final lijf = player.substring(player.indexOf(m), player.indexOf(m) + 160);
        expect(lijf, contains('keuzes++;'), reason: m);
      }
      final volgende = player.substring(player.indexOf('  Future<void> next() async {'), player.indexOf('  Future<void> next() async {') + 400);
      expect(volgende, isNot(contains('keuzes++')), reason: 'vanzelf doorgaan is geen keuze');
    });

    test('een tik met de proef aan: Soulseek eerst, TorBox pas als Soulseek niets heeft', () {
      final main = File('lib/main.dart').readAsStringSync();
      final speel = main.substring(main.indexOf('class NieuwSpeler'), main.indexOf('File get _nieuwOpToestel'));
      expect(speel, contains('if (lib.remote == null && instellingen.vroegLuisteren) {'));
      expect(speel.indexOf('if (t == null && vroeg != null && magNog()) {'), greaterThan(speel.indexOf('for (var ronde = 0;')));
    });
  });

  group('de kop terwijl het binnenkomt', () {
    test('vroegeAfkeur: een ander nummer, een andere lengte, geen looptijd', () {
      const tags = TrackTags(title: 'Before You Know It', artist: 'Kygo', album: '', trackNo: 1);
      String? af({TrackTags? t = tags, int? bestand = 230, int? gevraagd = 231}) => vroegeAfkeur(
          artiest: 'Kygo', titel: 'Before You Know It', seconden: gevraagd, tags: t, bestandSeconden: bestand, pad: 'x.flac');
      expect(af(), isNull);
      expect(af(t: const TrackTags(title: 'Levels', artist: 'Avicii', album: '', trackNo: 1)), contains('ander nummer'));
      expect(af(bestand: 300), contains('andere versie'));
      expect(af(bestand: null), contains('looptijd'));
      expect(af(t: null), isNull, reason: 'geen tags is geen tegenspraak (en FLAC krijgt ze er later in)');
    });

    test('flacAudioBegin: pas met de hele kop en een eerste byte audio', () {
      final kop = BytesBuilder()
        ..add('fLaC'.codeUnits)
        ..add([0x00, 0, 0, 34])
        ..add(List.filled(34, 0))
        ..add([0x84, 0, 0, 8])
        ..add(List.filled(8, 0x41));
      final heel = kop.toBytes();
      final f = File(pad('kop.flac'));
      f.writeAsBytesSync(heel.sublist(0, 50));
      expect(flacAudioBegin(f), isNull, reason: 'het laatste blok is nog niet compleet');
      f.writeAsBytesSync(heel);
      expect(flacAudioBegin(f), isNull, reason: 'nog geen audio');
      f.writeAsBytesSync([...heel, 0xFF, 0xF8]);
      expect(flacAudioBegin(f), heel.length);
    });
  });

  group('aangesloten', () {
    final online = File('lib/online.dart').readAsStringSync();
    final player = File('lib/player.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final haal = online.substring(
        online.indexOf('  Future<String?> _haalVoorRadio('), online.indexOf('  /// Eén wens om PRECIES dit bestand'));

    test('de haal: vroeg keuren alleen bij FLAC, vasthouden vóór de tweede keuring, landen na de tags', () {
      expect(haal, contains("f.filename.toLowerCase().endsWith('.flac')"));
      expect(haal.indexOf('await vroeg?.binnen();'), lessThan(haal.indexOf('final t = readTags(binnen);')),
          reason: 'vasthouden vóór er iets met het bestand gebeurt');
      expect(haal, contains('vroeg?.geland(uit.path);\n          geland = uit.path;'));
      expect(haal, contains('vroeg?.geland(uit.path);\n              throw RadioAlGehad(uit.path);'));
      expect(RegExp(r'vroeg\?\.afgebroken\(\);').allMatches(haal).length, greaterThanOrEqualTo(6),
          reason: 'elke afkeuring, en het vangnet in finally');
    });

    test('de speler: een breuk in een groeistroom wacht op de volgende uploader en opent met een startpositie',
        () {
      final einde = player.substring(player.indexOf('  void _onCompleted() {'));
      expect(einde.indexOf("_groeiVan(current?.path ?? '') != null"), allOf(greaterThan(0), lessThan(einde.indexOf('_hervatpogingen++;'))));
      expect(player, contains('Groeiend? _groeiVan(String pad) => Groeistroom.gedeeld.van(pad) ?? _groeiElders[pad];'));
      expect(player, contains('await g.speelbaarVanaf(plek);'));
      expect(player, contains('if (_groeiZelfdePlek < 3) {'), reason: 'nooit eindeloos op dezelfde plek opnieuw');
      expect(einde, contains("duration - position > const Duration(seconds: 1)"), reason: 'ook in de laatste tien seconden');
      expect(player, contains(r"Media(_bron('$verder?vanaf=${plek.inMilliseconds}'))"),
          reason: 'niet springen: een stroom die op de plek begint');
      expect(player, contains("setProperty('rebase-start-time', 'no')"));
      expect(player, contains('geborgen != null && nu?.path == geborgen ? geborgen : null'),
          reason: 'intussen geland: verder in het opgeborgen bestand, niet stil blijven staan');
      expect(player, contains('if (position <= Duration.zero || !_speeltGroei) return false;'),
          reason: 'het halve laatste frame ("Error decoding audio") is geen openfout');
      expect(player, contains('if (_breukInGroeistroom(e)) return;'), reason: 'in de foutluisteraar, vóór de poort');
    });

    test('een tik op een nieuw nummer: klinkt het al, dan wordt het je nummer zonder opnieuw te openen', () {
      final speel = main.substring(main.indexOf('class NieuwSpeler'), main.indexOf('File get _nieuwOpToestel'));
      expect(speel, contains('instellingen.vroegLuisteren'));
      expect(speel, contains('final klinkendAdres = vroeg?.adres ?? elders?.pad;'));
      expect(speel, contains('speler.wordtLokaal(klinkendAdres, t);'));
      expect(speel, contains('if (vroeg != null && vroeg.geborgen == null) vroeg.opgegeven();'));
      expect(main, contains("..inGebruik = (a) => (player.mpvAdres ?? '').split('?').first == a || player.current?.path == a;"));
      expect(speel, contains('vroeg.zalKlinken();\n        unawaited(vroeg.speelbaar.then((kan) {'),
          reason: '▶ wil het meteen horen: ook een bestand dat binnen is vóór mpv opent, in het geheugen');
      final radio = File('lib/radio.dart').readAsStringSync();
      expect(radio, contains('p.stroomItem = it;\n        g.zalKlinken();'),
          reason: 'de radio alleen als hij een stroomregel inzet — vooruit halen houdt niets vast');
    });
  });
}
