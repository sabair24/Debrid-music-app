/// De doorgever op de telefoon (stap 6 van "verbinden zoals Roon ARC", 14-10-2026): mpv praat gewone
/// HTTP met 127.0.0.1, de doorgever vastgepinde TLS met de pc. En de pc-kant ervan: een merkteken en
/// `If-Range` op elke stroom.
///
/// Wat hier vastligt is wat ffmpeg nodig heeft om niet stil te vallen: een exacte lengte en Range, een
/// storing wordt vastgehouden in plaats van een 5xx, een afgebroken of stilgevallen stroom sluit naar
/// mpv zodat hij hervat, en een hervatting na een verandering op de pc stopt in plaats van twee
/// bestanden aan elkaar te plakken.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/certificaat.dart';
import 'package:debridmusic/lan/doorgever.dart';
import 'package:debridmusic/lan/range.dart';

import 'hulp_tls.dart';

const _sleutel = 'tls-sleutel-van-de-gsm-0001';

/// Een nep-pc op loopback met het proefcertificaat. Hij serveert [bestand] op elke `/stream/…` en
/// `/art/…` zoals de echte (serveFile), en alleen met de sleutel in de kop. [voorElk] mag een verzoek
/// zelf afhandelen (true = afgehandeld).
class _NepPc {
  _NepPc(this.bestand);
  File bestand;
  late HttpServer server;
  final verzoeken = <HttpRequest>[];
  final koppen = <Map<String, String?>>[];
  Future<bool> Function(HttpRequest req)? voorElk;

  int get poort => server.port;
  Uri get basis => Uri.parse('https://127.0.0.1:$poort');

  Future<void> start() async {
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, proefCertificaat.context());
    server.listen((req) async {
      verzoeken.add(req);
      koppen.add({
        'range': req.headers.value(HttpHeaders.rangeHeader),
        'if-range': req.headers.value(HttpHeaders.ifRangeHeader),
        'authorization': req.headers.value(HttpHeaders.authorizationHeader),
        'query': req.uri.query,
      });
      if (await (voorElk?.call(req) ?? Future.value(false))) return;
      if (req.headers.value(HttpHeaders.authorizationHeader) != 'Bearer $_sleutel') {
        req.response.statusCode = 401;
        return req.response.close();
      }
      await serveFile(req, bestand, contentType: 'audio/flac');
    });
  }

  Future<void> stop() => server.close(force: true);
}

Uint8List _bytes(int n) => Uint8List.fromList(List<int>.generate(n, (i) => (i * 31 + 7) % 251));

/// Eén verzoek naar de doorgever, zoals mpv het doet.
Future<({int status, Uint8List lijf, HttpHeaders? koppen, bool afgebroken})> _mpv(Uri url,
    {String? range, String methode = 'GET', Duration? pauze}) async {
  final c = HttpClient();
  try {
    final req = await c.openUrl(methode, url);
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close();
    final b = BytesBuilder(copy: false);
    var afgebroken = false;
    final klaar = Completer<void>();
    late StreamSubscription<List<int>> sub;
    var gepauzeerd = false;
    sub = res.listen((d) {
      b.add(d);
      if (pauze != null && !gepauzeerd && b.length > 256 * 1024) {
        gepauzeerd = true;
        sub.pause();
        Timer(pauze, sub.resume);
      }
    }, onError: (Object _) {
      afgebroken = true;
      if (!klaar.isCompleted) klaar.complete();
    }, onDone: () {
      if (!klaar.isCompleted) klaar.complete();
    }, cancelOnError: true);
    await klaar.future;
    final lijf = b.takeBytes();
    if (res.contentLength >= 0 && lijf.length < res.contentLength) afgebroken = true;
    return (status: res.statusCode, lijf: lijf, koppen: res.headers, afgebroken: afgebroken);
  } on HttpException {
    return (status: -1, lijf: Uint8List(0), koppen: null, afgebroken: true);
  } on SocketException {
    return (status: -1, lijf: Uint8List(0), koppen: null, afgebroken: true);
  } finally {
    c.close(force: true);
  }
}

void main() {
  late Directory map;
  late File bestand;
  late _NepPc pc;
  late Doorgever d;
  final regels = <String>[];
  var storingen = 0;
  final veranderd = <String>[];
  var geweigerd = 0;

  Doorgever maak(
          {Duration wacht = const Duration(seconds: 3),
          Duration stilte = const Duration(milliseconds: 600),
          Duration opnieuw = const Duration(milliseconds: 100)}) =>
      Doorgever(
        wachtOpAdres: wacht,
        stilte: stilte,
        opnieuw: opnieuw,
        log: regels.add,
        storing: () => storingen++,
        veranderd: veranderd.add,
        geweigerd: () => geweigerd++,
      );

  setUp(() async {
    regels.clear();
    storingen = 0;
    veranderd.clear();
    geweigerd = 0;
    map = Directory.systemTemp.createTempSync('dm_doorgever_');
    bestand = File('${map.path}/nummer.flac')..writeAsBytesSync(_bytes(300 * 1024));
    pc = _NepPc(bestand);
    await pc.start();
    d = maak();
    await d.start();
    d.zetBron(DoorgeverBron(basis: pc.basis, sleutel: _sleutel, pin: proefCertificaat.pin));
  });

  tearDown(() async {
    await d.stop();
    await pc.stop();
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  Uri adres([String pad = '/stream/ab12cd.flac?maxRate=48000&token=geheim-van-47820']) =>
      d.adresVoor(Uri.parse('http://pc.invalid$pad'));

  group('pc-kant: merkteken en If-Range', () {
    test('een stroom heeft een merkteken en een datum; If-Range dat klopt geeft het stuk, anders alles', () async {
      final eerst = await _mpv(adres(), range: 'bytes=0-99');
      final etag = eerst.koppen!.value(HttpHeaders.etagHeader)!;
      expect(etag, startsWith('"'));
      expect(eerst.koppen!.value(HttpHeaders.lastModifiedHeader), isNotNull);
      final c = pinHttpClient();
      try {
        Future<int> vraag(String ifRange) async {
          final r = await c.getUrl(pc.basis.replace(path: '/stream/x.flac'));
          r.headers
            ..set(HttpHeaders.authorizationHeader, 'Bearer $_sleutel')
            ..set(HttpHeaders.rangeHeader, 'bytes=100-')
            ..set(HttpHeaders.ifRangeHeader, ifRange);
          final res = await r.close();
          await res.drain<void>();
          return res.statusCode;
        }

        expect(await vraag(etag), 206);
        expect(await vraag('"iets-anders"'), 200, reason: 'ander merkteken: het hele bestand, niet het stuk');
        expect(await vraag('W/$etag'), 200, reason: 'een zwak merkteken telt nooit voor If-Range');
        expect(await vraag(HttpDate.format(bestand.lastModifiedSync())), 206);
        expect(await vraag(HttpDate.format(DateTime.utc(2001))), 200);
      } finally {
        c.close(force: true);
      }
    });

    test('ifRangeKlopt als regel', () {
      final t = DateTime.utc(2026, 10, 14, 12, 0, 5, 300);
      expect(ifRangeKlopt('"a-1"', '"a-1"', t), isTrue);
      expect(ifRangeKlopt('"a-2"', '"a-1"', t), isFalse);
      expect(ifRangeKlopt(HttpDate.format(t), '"a-1"', t), isTrue, reason: 'tot op de seconde');
      expect(ifRangeKlopt('onzin', '"a-1"', t), isFalse);
    });
  });

  group('doorgeven', () {
    test('206, Content-Range en HEAD komen door; de sleutel in de kop en niet in het adres', () async {
      final heel = await _mpv(adres());
      expect(heel.status, 200);
      expect(heel.lijf, bestand.readAsBytesSync());
      expect(heel.koppen!.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(heel.koppen!.contentLength, bestand.lengthSync());
      expect(heel.koppen!.chunkedTransferEncoding, isFalse);

      final stuk = await _mpv(adres(), range: 'bytes=1000-1999');
      expect(stuk.status, 206);
      expect(stuk.koppen!.value(HttpHeaders.contentRangeHeader), 'bytes 1000-1999/${bestand.lengthSync()}');
      expect(stuk.lijf, bestand.readAsBytesSync().sublist(1000, 2000));

      final kop = await _mpv(adres(), methode: 'HEAD');
      expect(kop.status, 200);
      expect(kop.koppen!.contentLength, bestand.lengthSync());
      expect(kop.lijf, isEmpty);

      expect(pc.koppen.first['authorization'], 'Bearer $_sleutel');
      for (final k in pc.koppen) {
        expect(k['query'], isNot(contains('token')), reason: 'de sleutel van 47820 gaat nooit mee');
        expect(k['query'], contains('maxRate=48000'), reason: 'de rest van de vraag wel');
      }
    });

    test('zonder het geheim 403, en alleen /stream/ en /art/', () async {
      final zonder = Uri.parse('http://127.0.0.1:${d.poort}/stream/ab12cd.flac');
      expect((await _mpv(zonder)).status, 403);
      final verkeerd = Uri.parse('http://127.0.0.1:${d.poort}/${'0' * 32}/stream/ab12cd.flac');
      expect((await _mpv(verkeerd)).status, 403);
      expect((await _mpv(d.adresVoor(Uri.parse('http://pc.invalid/api/catalog')))).status, 404);
      expect((await _mpv(d.adresVoor(Uri.parse('http://pc.invalid/art/album-1')))).status, 200);
      expect(pc.verzoeken.length, 1, reason: 'alleen de hoes kwam bij de pc');
    });

    test('alleen het certificaat van de eigen pc: een ander krijgt geen sleutel te zien', () async {
      d.zetBron(DoorgeverBron(basis: pc.basis, sleutel: _sleutel, pin: 'b' * 64));
      final r = await _mpv(adres());
      expect(r.status, -1, reason: 'dicht zonder antwoord, na het wachten');
      expect(pc.koppen.where((k) => k['authorization'] != null), isEmpty);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('de pc geeft een 5xx: nooit doorgeven, opnieuw proberen', () async {
      var keer = 0;
      pc.voorElk = (req) async {
        if (keer++ > 0) return false;
        req.response.statusCode = 503;
        await req.response.close();
        return true;
      };
      final r = await _mpv(adres());
      expect(r.status, 200);
      expect(r.lijf.length, bestand.lengthSync());
    });

    test('de pc weigert de sleutel: 401 door, en de sessie hoort het', () async {
      d.zetBron(DoorgeverBron(basis: pc.basis, sleutel: 'verkeerd', pin: proefCertificaat.pin));
      expect((await _mpv(adres())).status, 401);
      expect(geweigerd, 1);
    });
  });

  group('storingen', () {
    test('pc onbereikbaar: de aanvraag wacht, de sessie hoort het, en met een nieuw adres gaat hij door', () async {
      final dood = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final doodPoort = dood.port;
      await dood.close();
      await d.stop();
      // Een lange tussenpoos: dan bewijst de toets dat een nieuw adres de wachtende aanvraag meteen
      // wekt, en niet pas bij de volgende poging.
      d = maak(wacht: const Duration(seconds: 15), opnieuw: const Duration(seconds: 8));
      await d.start();
      d.zetBron(DoorgeverBron(basis: Uri.parse('https://127.0.0.1:$doodPoort'), sleutel: _sleutel, pin: proefCertificaat.pin));
      final bezig = _mpv(adres(), range: 'bytes=0-');
      // Wachten op de melding en niet een vaste tijd: een dichte poort op loopback weigert op Linux
      // meteen, op Windows pas na ongeveer twee seconden.
      for (var i = 0; i < 100 && storingen == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(storingen, greaterThan(0), reason: 'de sessie mag een wedloop houden');
      // De wedloop vindt een adres: de wachtende aanvraag gaat meteen verder, zonder 5xx ertussen.
      final sinds = Stopwatch()..start();
      d.zetBron(DoorgeverBron(basis: pc.basis, sleutel: _sleutel, pin: proefCertificaat.pin));
      final r = await bezig;
      expect(sinds.elapsedMilliseconds, lessThan(3000), reason: 'het nieuwe adres wekt de aanvraag meteen');
      expect(r.status, 206);
      expect(r.lijf.length, bestand.lengthSync());
    });

    test('na de wachttijd zonder adres: dicht zonder antwoord (ffmpeg probeert dan zelf opnieuw)', () async {
      d.zetBron(null);
      await d.stop();
      d = maak(wacht: const Duration(milliseconds: 800));
      await d.start();
      final klok = Stopwatch()..start();
      final r = await _mpv(adres());
      expect(r.status, -1, reason: 'geen 5xx, gewoon geen antwoord');
      expect(klok.elapsedMilliseconds, greaterThanOrEqualTo(700));
      expect(regels.any((l) => l.contains('dicht zonder antwoord')), isTrue);
    });

    test('halverwege afgebroken: naar mpv dicht; hervatten via een ander adres geeft samen precies het bestand', () async {
      final alles = bestand.readAsBytesSync();
      // Eerste adres: een kale ingang die de kop met de volle lengte stuurt, de helft van de bytes, en
      // dan ophangt — zoals een verbinding die bij het verlaten van de wifi wegvalt. Het merkteken is
      // dat van serveFile, zodat de hervatting op de echte ingang erbij past.
      // Het tweede adres: een gewone pc-ingang met hetzelfde certificaat, waar de wedloop straks heen gaat.
      final ander = _NepPc(bestand);
      await ander.start();
      addTearDown(ander.stop);
      // Het merkteken letterlijk zoals serveFile het geeft, uit een HEAD — niet zelf nagerekend: op de
      // bouwstraat (Linux) gaf een eigen berekening uit `lastModifiedSync()` een ander getal, en dan
      // las de doorgever terecht "veranderd" (412). Gezien 14-10-2026.
      final c = pinHttpClient();
      final kop = await (await c.openUrl('HEAD', ander.basis.replace(path: '/stream/x.flac'))
            ..headers.set(HttpHeaders.authorizationHeader, 'Bearer $_sleutel'))
          .close();
      final etag = kop.headers.value(HttpHeaders.etagHeader)!;
      await kop.drain<void>();
      c.close(force: true);
      ander.koppen.clear();
      final rauw = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, proefCertificaat.context());
      addTearDown(rauw.close);
      rauw.listen((s) {
        final gelezen = <int>[];
        var beantwoord = false;
        s.listen((d) async {
          gelezen.addAll(d);
          if (beantwoord || !String.fromCharCodes(gelezen).contains('\r\n\r\n')) return;
          beantwoord = true;
          s.write('HTTP/1.1 200 OK\r\nContent-Type: audio/flac\r\nAccept-Ranges: bytes\r\n'
              'Content-Length: ${alles.length}\r\nETag: $etag\r\n\r\n');
          s.add(alles.sublist(0, alles.length ~/ 2));
          await s.flush();
          s.destroy();
        }, onError: (Object _) {});
      });
      d.zetBron(DoorgeverBron(basis: Uri.parse('https://127.0.0.1:${rauw.port}'), sleutel: _sleutel, pin: proefCertificaat.pin));
      final eerst = await _mpv(adres());
      expect(eerst.afgebroken, isTrue, reason: 'mpv moet merken dat het niet af is');
      expect(eerst.lijf.length, lessThan(alles.length));
      // De wedloop koos intussen het andere adres.
      d.zetBron(DoorgeverBron(basis: ander.basis, sleutel: _sleutel, pin: proefCertificaat.pin));
      final rest = await _mpv(adres(), range: 'bytes=${eerst.lijf.length}-');
      expect(rest.status, 206);
      expect([...eerst.lijf, ...rest.lijf], alles, reason: 'alle geleverde bytes samen = het bestand');
      expect(ander.koppen.single['if-range'], isNotNull, reason: 'hervatten met het merkteken van het eerste antwoord');
    });

    test('de pc valt stil terwijl mpv wacht: na de stilte dicht naar mpv', () async {
      final alles = bestand.readAsBytesSync();
      pc.voorElk = (req) async {
        if (req.headers.value(HttpHeaders.rangeHeader) != null) return false;
        final res = req.response
          ..contentLength = alles.length
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        res.add(alles.sublist(0, 64 * 1024));
        await res.flush();
        // ... en dan niets meer, zonder de verbinding te sluiten.
        await Future<void>.delayed(const Duration(seconds: 5));
        return true;
      };
      final klok = Stopwatch()..start();
      final r = await _mpv(adres());
      expect(r.afgebroken, isTrue);
      expect(klok.elapsedMilliseconds, lessThan(4000), reason: 'na ${d.stilte.inMilliseconds} ms stilte, niet pas als de pc opgeeft');
      expect(regels.any((l) => l.contains('geen bytes van de pc')), isTrue);
    });

    test('mpv leest even niet (buffer vol): dat is geen stilte van de pc', () async {
      await pc.stop();
      final groot = File('${map.path}/groot.flac')..writeAsBytesSync(_bytes(48 * 1024 * 1024));
      pc = _NepPc(groot);
      await pc.start();
      d.zetBron(DoorgeverBron(basis: pc.basis, sleutel: _sleutel, pin: proefCertificaat.pin));
      final r = await _mpv(adres(), pauze: const Duration(milliseconds: 2500));
      expect(r.afgebroken, isFalse, reason: 'de pauze lag bij mpv, niet bij de pc');
      expect(r.lijf.length, groot.lengthSync());
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('een oudere pc zonder merkteken: een ander totaal is ook een verandering', () async {
      var lengte = 4000;
      pc.voorElk = (req) async {
        final range = parseRange(req.headers.value(HttpHeaders.rangeHeader), lengte)!;
        final res = req.response
          ..statusCode = 206
          ..contentLength = range.length
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.start}-${range.end}/$lengte');
        res.add(List<int>.filled(range.length, 1));
        await res.close();
        return true;
      };
      expect((await _mpv(adres(), range: 'bytes=0-99')).status, 206);
      expect(pc.koppen.last['if-range'], isNull, reason: 'zonder merkteken valt er niets mee te sturen');
      lengte = 5000;
      expect((await _mpv(adres(), range: 'bytes=100-')).status, 412);
      expect(veranderd, hasLength(1));
    });

    test('een groei (/groei/) verandert wél onderweg: het lege einde komt door, geen 412, ?vanaf= mee', () async {
      // Zoals `_groei` op de pc en de groeistroom erachter: eerst 4000 bytes, dan haakt de uploader af na 100
      // en zegt een vervolg "het houdt hier op" (206, bytes 100-100/100, leeg).
      var afgehaakt = false;
      pc.voorElk = (req) async {
        final res = req.response;
        if (afgehaakt && req.headers.value(HttpHeaders.rangeHeader) != null) {
          res
            ..statusCode = 206
            ..contentLength = 0
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 100-100/100');
          await res.close();
          return true;
        }
        final range = parseRange(req.headers.value(HttpHeaders.rangeHeader), 4000) ?? const ByteRange(0, 3999);
        res
          ..statusCode = req.headers.value(HttpHeaders.rangeHeader) == null ? 200 : 206
          ..contentLength = range.length;
        if (res.statusCode == 206) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.start}-${range.end}/4000');
        res.add(List<int>.filled(range.length, 2));
        await res.close();
        return true;
      };
      final groei = adres('/groei/g7.flac');
      expect((await _mpv(groei, range: 'bytes=0-99')).status, 206);
      afgehaakt = true;
      final einde = await _mpv(groei, range: 'bytes=100-');
      expect(einde.status, 206, reason: 'geen 412: de speler moet dit einde horen');
      expect(einde.koppen!.contentLength, 0);
      expect(veranderd, isEmpty);
      // Verder op een plek: de vraag gaat mee, de sleutel niet.
      afgehaakt = false;
      final verder = await _mpv(adres('/groei/g7.flac?vanaf=83500&token=geheim'));
      expect(verder.status, 200);
      expect(pc.koppen.last['query'], 'vanaf=83500');
      // Een stroom blijft wél bewaakt.
      expect((await _mpv(adres('/stream/ab12cd.flac'), range: 'bytes=0-9')).status, isNot(412));
    });

    test('het nummer veranderde op de pc tussen twee stukken: stoppen, niet aan elkaar plakken', () async {
      final eerst = await _mpv(adres(), range: 'bytes=0-1023');
      expect(eerst.status, 206);
      // Opnieuw getagd of vervangen op de pc: andere bytes, ander tijdstip.
      bestand.writeAsBytesSync(_bytes(310 * 1024));
      bestand.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
      final daarna = await _mpv(adres(), range: 'bytes=1024-');
      expect(daarna.status, 412);
      expect(veranderd, ['/stream/ab12cd.flac']);
    });
  });

  test('in een eigen isolate: zelfde gedrag, meldingen komen terug', () async {
    final logs = <String>[];
    final iso = DoorgeverIsolaat(log: logs.add);
    await iso.start();
    addTearDown(iso.stop);
    expect(iso.poort, greaterThan(0));
    expect(iso.geheim, hasLength(32));
    iso.zetBron(DoorgeverBron(basis: pc.basis, sleutel: _sleutel, pin: proefCertificaat.pin));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final r = await _mpv(iso.adresVoor(Uri.parse('http://pc.invalid/stream/ab12cd.flac')), range: 'bytes=10-19');
    expect(r.status, 206);
    expect(r.lijf, bestand.readAsBytesSync().sublist(10, 20));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(logs.any((l) => l.startsWith('doorgever: ')), isTrue);
  });

  test('na het hervatten (iOS): dood? dan opnieuw op dezelfde poort, met hetzelfde geheim en dezelfde pc', () async {
    final iso = DoorgeverIsolaat();
    await iso.start();
    addTearDown(iso.stop);
    iso.zetBron(DoorgeverBron(basis: pc.basis, sleutel: _sleutel, pin: proefCertificaat.pin));
    final url = iso.adresVoor(Uri.parse('http://pc.invalid/stream/ab12cd.flac'));
    expect(await iso.nakijken(), isFalse, reason: 'hij leeft: niets doen');
    iso.doodVoorToets();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await iso.nakijken(), isTrue);
    final r = await _mpv(url, range: 'bytes=0-9');
    expect(r.status, 206, reason: 'het adres dat mpv al had, werkt weer');
    expect(r.lijf, bestand.readAsBytesSync().sublist(0, 10));
  });

  test('pin van het proefcertificaat is wat de pc ook gebruikt', () {
    expect(pinVan(proefCertificaat.der), proefCertificaat.pin);
  });
}
