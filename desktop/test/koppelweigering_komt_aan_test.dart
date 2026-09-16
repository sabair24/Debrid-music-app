/// Een weigering moet als weigering aankomen, mét de reden.
///
/// **Waarom dit bestaat.** Op 16-09-2026 kwam Saber zijn telefoon niet meer binnen. Op het scherm
/// stond *"De pc gaf geen sleutel terug"* — een zin die nergens heen wijst. In `koppeling.log` van
/// de pc stond zeven keer, tussen 07:27 en 07:42:
///
///     PAIR-CLOUD  geweigerd  sleutel van: …4B6kw2  deze pc: (niet ingelogd)
///
/// De pc wíst het dus, en zei het ook — `koppelweigering()` stuurt "Je pc is niet ingelogd. Log op
/// de pc in met hetzelfde account." mee. Alleen kwam het nooit aan. Met `curl` tegen de draaiende
/// pc gemeten:
///
///     HTTP 200  {"error":"Je pc is niet ingelogd. Log op de pc in met hetzelfde account."}
///
/// Tweehonderd, terwijl er in de code `statusCode = HttpStatus.forbidden` boven staat. De oorzaak
/// stond in `_json`: die had `{int status = HttpStatus.ok}` en zette `res.statusCode = status`
/// ONVOORWAARDELIJK, dus elke code die de aanroeper er vóór had gezet viel stil terug op 200. Zes
/// plekken in `server.dart` deden dat, waaronder alle drie de koppelweigeringen.
///
/// De telefoon zag een geslaagd antwoord zonder sleutel en kon niets beters verzinnen dan die ene
/// zin. Dezelfde storing als bij het taalmodel dat alleen "400" mocht zeggen: de uitleg was er, en
/// werd onderweg weggegooid.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory wortel;
  late LanServer server;
  late Uri basis;

  /// Zet een pc op met een gegeven accountstand.
  Future<void> zetOp({
    String? uidVanDePc,
    Future<String> Function(String)? opzoeker,
  }) async {
    wortel = Directory.systemTemp.createTempSync('weigering_');
    final library = LibraryStore()
      ..rootPath = wortel.path
      ..configDirOverride = wortel.path;
    library.rebuildAlbums();
    server = LanServer(
      library: library,
      token: 'gedeelde-sleutel',
      state: LanStateStore(File('${wortel.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      cloudUid: uidVanDePc == null ? null : () => uidVanDePc,
      uidVanSleutel: opzoeker,
    );
    expect(await server.start(), isNull);
    basis = Uri.parse('http://127.0.0.1:${server.boundPort}');
  }

  Future<HttpClientResponse> koppel() async {
    final c = HttpClient();
    final req = await c.postUrl(basis.replace(path: '/pair-cloud'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'idToken': 'wat-de-telefoon-liet-zien',
      'deviceId': 'toestel-1',
      'deviceName': 'Saber ultra 26',
      'platform': 'android',
    }));
    return req.close();
  }

  Future<(int, String)> antwoord() async {
    final res = await koppel();
    final lijf = await res.transform(utf8.decoder).join();
    final j = jsonDecode(lijf.isEmpty ? '{}' : lijf);
    return (res.statusCode, (j is Map ? (j['error'] ?? '') : '').toString());
  }

  group('de pc weigert, en dat komt ook zo aan', () {
    // Alleen deze groep zet een pc op; de andere twee niet. Stond dit op het hoogste niveau, dan
    // probeerde hij daar een map weg te gooien die er nooit was.
    tearDown(() async {
      await server.dispose();
      wortel.deleteSync(recursive: true);
    });

    test('DE KERN: een pc die niet ingelogd is geeft 403 MET de reden', () async {
      // Precies de stand van Sabers pc die ochtend: hij kent de account-weg wel, maar is zelf
      // nergens ingelogd.
      await zetOp(uidVanDePc: '', opzoeker: (_) async => 'uid-van-de-telefoon');
      final (code, reden) = await antwoord();
      expect(code, HttpStatus.forbidden,
          reason: 'bij 200 gaat de telefoon een sleutel zoeken die er niet is');
      expect(reden, contains('niet ingelogd'));
    });

    test('DE KERN: een ander account geeft 403 met een ANDERE reden', () async {
      // Twee heel verschillende problemen met twee heel verschillende oplossingen; ze mogen niet
      // op dezelfde zin uitkomen.
      await zetOp(uidVanDePc: 'uid-van-de-pc', opzoeker: (_) async => 'uid-van-iemand-anders');
      final (code, reden) = await antwoord();
      expect(code, HttpStatus.forbidden);
      expect(reden, contains('ander account'));
    });

    test('DE VAL: Google onbereikbaar is 503 en géén weigering', () async {
      // "Nu niet" is iets anders dan "nee". Wie dit als weigering leest gaat een wachtwoord zoeken
      // dat prima was.
      await zetOp(uidVanDePc: 'uid-van-de-pc', opzoeker: (_) async => throw 'geen net');
      final (code, reden) = await antwoord();
      expect(code, HttpStatus.serviceUnavailable);
      expect(reden, contains('Google'));
    });

    test('DE VAL: een pc zonder account-inlog weigert ook met 403', () async {
      await zetOp(uidVanDePc: null, opzoeker: null);
      final (code, reden) = await antwoord();
      expect(code, HttpStatus.forbidden);
      expect(reden, isNotEmpty);
    });

    test('DE GRENS: bij toestemming komt er 200 MET een sleutel', () async {
      await zetOp(uidVanDePc: 'zelfde-uid', opzoeker: (_) async => 'zelfde-uid');
      final res = await koppel();
      expect(res.statusCode, HttpStatus.ok);
      final j = jsonDecode(await res.transform(utf8.decoder).join());
      expect(((j as Map)['token'] ?? '').toString(), isNotEmpty);
      expect((j['error'] ?? '').toString(), isEmpty);
    });
  });

  group('de val zelf ligt er niet meer', () {
    test('DE KERN: geen enkele plek zet een code die _json daarna wegpoetst', () {
      // Deze storing is met GEEN netwerktoets te vangen zodra de aanroepplekken hun status
      // meegeven: de val blijft dan liggen voor de VOLGENDE aanroeper. Daarom kijkt deze toets naar
      // de brontekst — precies zoals het werktuig dat de zes plekken vond.
      //
      // Splitsen op beide regeleinden, want een verse werkboom krijgt CRLF en een brontekst-toets
      // die dat niet verdraagt valt om op iets wat met deze storing niets te maken heeft.
      final regels = File('lib/lan/server.dart').readAsStringSync().split(RegExp(r'\r?\n'));
      final fout = <String>[];
      for (var i = 0; i < regels.length; i++) {
        if (regels[i].trimLeft().startsWith('//')) continue;
        final m = RegExp(r'statusCode\s*=\s*HttpStatus\.(\w+)').firstMatch(regels[i]);
        if (m == null || m.group(1) == 'ok') continue;
        for (var k = i + 1; k < i + 7 && k < regels.length; k++) {
          if (regels[k].contains('close()')) break;
          if (!regels[k].contains('_json(')) continue;
          final eind = k + 4 < regels.length ? k + 4 : regels.length;
          if (!regels.sublist(k, eind).join(' ').contains('status:')) {
            fout.add('regel ${i + 1} zet ${m.group(1)}, _json op ${k + 1} krijgt niets mee');
          }
          break;
        }
      }
      expect(fout, isEmpty,
          reason: 'zo een code valt stil terug op 200, en de reden komt nooit aan: $fout');
    });

    test('DE VAL: _json laat een al gezette code staan', () {
      // Met een onvoorwaardelijke toewijzing is de toets hierboven te omzeilen door de status
      // ervóór te zetten — wat zes plekken deden. De handtekening moet dus nullable blijven.
      final bron = File('lib/lan/server.dart').readAsStringSync();
      expect(bron, contains('_json(HttpResponse res, Object body, {int? status})'),
          reason: 'een standaardwaarde hier overschrijft elke code die de aanroeper al zette');
      expect(bron, contains('if (status != null) res.statusCode = status;'));
    });
  });

  group('de telefoon leest de reden, ook van een pc die nog niet bijgewerkt is', () {
    late HttpServer oudePc;
    late int code;
    late String lijf;

    setUp(() async {
      code = 200;
      lijf = jsonEncode({'error': 'Je pc is niet ingelogd. Log op de pc in met hetzelfde account.'});
      oudePc = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(() async {
        await for (final req in oudePc) {
          await req.drain<void>();
          req.response.statusCode = code;
          req.response.write(lijf);
          await req.response.close();
        }
      }());
    });

    tearDown(() async => oudePc.close(force: true));

    Future<Object?> probeer() async {
      try {
        await RemoteClient.pairMetAccount(
          Uri.parse('http://127.0.0.1:${oudePc.port}'),
          idToken: 'x',
          deviceId: 'y',
          deviceName: 'z',
          platform: 'android',
        );
        return null;
      } catch (e) {
        return e;
      }
    }

    test('DE KERN: 200 met een `error` erin is een weigering, geen geslaagd antwoord', () async {
      // Dit is de stand van een pc die deze reparatie nog niet heeft. De telefoon wordt wél
      // bijgewerkt en praat voorlopig nog met zulke pc's.
      final e = await probeer();
      expect(e, isA<RemoteException>());
      expect((e as RemoteException).message, contains('niet ingelogd'),
          reason: 'anders staat er weer "De pc gaf geen sleutel terug"');
    });

    test('DE VAL: een 403 met dezelfde inhoud geeft dezelfde zin', () async {
      code = HttpStatus.forbidden;
      final e = await probeer();
      expect(e, isA<RemoteException>());
      expect((e as RemoteException).message, contains('niet ingelogd'));
    });

    test('DE GRENS: 200 zonder sleutel én zonder reden zegt dát tenminste', () async {
      lijf = jsonEncode({'name': 'pc'});
      final e = await probeer();
      expect(e, isA<RemoteException>());
      final m = (e as RemoteException).message;
      expect(m, contains('geen reden'));
      expect(m, contains('nieuwere versie'),
          reason: 'de enige overgebleven verklaring is een pc die deze weg anders invult');
    });
  });
}
