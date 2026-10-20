// Spelen terwijl het binnenkomt (groeistroom.dart): de server tegen een echte HTTP-client, met een bestand
// dat groeit, een uploader die afhaakt, en opbergen terwijl het klinkt. De proef met de echte libmpv staat
// in de kladmap (`stroomproef/groei_mpv.dart`); hier wat de bouwstraat zonder mpv kan nagaan.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/groeistroom.dart';
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/radiobestand.dart';
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

    test('een ruim snellere uploader: na drie seconden meten, niet eerder', () {
      bool mag(Duration gemeten) => magBeginnen(
          binnen: 2000000, totaal: totaal, duur: duur, snelheid: 500000, gemeten: gemeten);
      expect(mag(const Duration(seconds: 2)), isFalse);
      expect(mag(const Duration(seconds: 3)), isTrue);
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
      expect(einde.indexOf('Groeistroom.gedeeld.van(current?.path'), lessThan(einde.indexOf('_hervatpogingen++;')));
      expect(player, contains('await g.speelbaarVanaf(plek);'));
      expect(player, contains('Media(_bron(verder), start: plek)'));
      expect(player, contains('geborgen != null && nu?.path == geborgen ? geborgen : null'),
          reason: 'intussen geland: verder in het opgeborgen bestand, niet stil blijven staan');
      expect(player, contains("if (position <= Duration.zero || !Groeistroom.isAdres(mpvAdres ?? '')) return false;"),
          reason: 'het halve laatste frame ("Error decoding audio") is geen openfout');
      expect(player, contains('if (_breukInGroeistroom(e)) return;'), reason: 'in de foutluisteraar, vóór de poort');
    });

    test('een tik op een nieuw nummer: klinkt het al, dan wordt het je nummer zonder opnieuw te openen', () {
      final speel = main.substring(main.indexOf('class NieuwSpeler'), main.indexOf('File get _nieuwOpToestel'));
      expect(speel, contains('instellingen.vroegLuisteren'));
      expect(speel, contains('speler.wordtLokaal(vroeg.adres, t);'));
      expect(speel, contains('if (vroeg != null && vroeg.geborgen == null) vroeg.opgegeven();'));
      expect(main, contains('..inGebruik = (a) => player.mpvAdres == a || player.current?.path == a;'));
    });
  });
}
