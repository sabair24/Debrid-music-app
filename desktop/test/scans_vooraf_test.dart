// De hoezen en scans van de hele bibliotheek vooraf op dit toestel, thuis op wifi (Saber, 02-11-2026: "er moet een manier
// gevonden worden dat de hoezen ook op de gsm staan" — "Je hele bibliotheek", "Volle resolutie"; zonder pc zocht de gsm ze
// zelf op internet: 103 MB mobiele data in twee uur).
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/paths.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:debridmusic/scans_vooraf.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(int n, [int lengte = 400]) => Uint8List.fromList(List.filled(lengte, n));

void main() {
  group('een ronde', () {
    test('wat er al ligt kost niets, de rest komt van de pc, en wat de pc niet heeft telt apart', () async {
      final gevraagd = <String>[];
      final v = ScansVooraf<String>(
        albums: () => ['al', 'nieuw', 'leeg', 'nieuw2'],
        mag: () => true,
        haal: (a) async {
          gevraagd.add(a);
          return switch (a) {
            'al' => Voorafstand.al,
            'leeg' => Voorafstand.nietOpPc,
            _ => Voorafstand.gehaald,
          };
        },
        adem: Duration.zero,
      );
      final r = await v.ronde();
      expect(gevraagd, ['al', 'nieuw', 'leeg', 'nieuw2']);
      expect((r.al, r.gehaald, r.nietOpPc, r.onderbroken), (1, 2, 1, false));
      expect(v.stand.value, (klaar: 3, totaal: 4));
    });

    test('van wifi naar mobiele data midden in een ronde: hij houdt op', () async {
      var mag = true;
      final gevraagd = <String>[];
      final v = ScansVooraf<String>(
        albums: () => ['a', 'b', 'c'],
        mag: () => mag,
        haal: (a) async {
          gevraagd.add(a);
          if (a == 'a') mag = false;
          return Voorafstand.gehaald;
        },
        adem: Duration.zero,
      );
      final r = await v.ronde();
      expect(gevraagd, ['a'], reason: 'geen album meer over mobiele data');
      expect(r.onderbroken, isTrue);
    });

    test('geen pc: de ronde houdt op in plaats van 1500 keer te vragen', () async {
      final gevraagd = <String>[];
      final v = ScansVooraf<String>(
        albums: () => ['a', 'b', 'c'],
        mag: () => true,
        haal: (a) async {
          gevraagd.add(a);
          return Voorafstand.geenPc;
        },
        adem: Duration.zero,
      );
      expect((await v.ronde()).onderbroken, isTrue);
      expect(gevraagd, ['a']);
    });

    test('niet op mobiele data: geen ronde; en een kijk tijdens een ronde geeft er meteen nog een', () async {
      var mag = false;
      var rondes = 0;
      final v = ScansVooraf<String>(
        albums: () {
          rondes++;
          return ['a'];
        },
        mag: () => mag,
        haal: (a) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return Voorafstand.al;
        },
        adem: Duration.zero,
      );
      v.kijk();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rondes, 0);
      mag = true;
      v.kijk();
      v.kijk();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(rondes, 2, reason: 'de tweede kijk kwam tijdens de eerste ronde');
    });
  });

  test('onderbroken (geen pc): na een paar minuten opnieuw, niet pas na zes uur', () async {
    var pc = false;
    var rondes = 0;
    final v = ScansVooraf<String>(
      albums: () {
        rondes++;
        return ['a'];
      },
      mag: () => true,
      haal: (a) async => pc ? Voorafstand.al : Voorafstand.geenPc,
      adem: Duration.zero,
      opnieuwNa: const Duration(milliseconds: 60),
    );
    v.kijk();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rondes, 1);
    pc = true;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(rondes, 2, reason: 'de pc is terug: de volgende ronde kwam vanzelf');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(rondes, 2, reason: 'en niet blijven herhalen als het lukte');
    v.stop();
  });

  test('de pc zegt 404 (nog geen scans van dit album): dat is geen storing', () async {
    final c = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://pc.invalid:47820'), token: 'x'),
        client: MockClient((req) async => http.Response('', req.url.path == '/api/releaseart' ? 404 : 500)));
    expect(await c.releaseArtJson('abc'), isNull,
        reason: 'als storing stopte "vooraf op dit toestel" bij het eerste album zonder scans (03-11-2026: 1 van 962)');
    final kapot = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://pc.invalid:47820'), token: 'x'),
        client: MockClient((req) async => http.Response('', 500)));
    expect(() => kapot.releaseArtJson('abc'), throwsA(isA<RemoteException>()), reason: 'een echte storing blijft er een');
  });

  group('van de pc naar dit toestel', () {
    late Directory krab;
    setUp(() {
      krab = Directory.systemTemp.createTempSync('dm_scans_vooraf_');
      setAppDirForTest(krab.path);
    });
    tearDown(() {
      DiscogsArtwork.vanDePc = null;
      DiscogsArtwork.zuinig = null;
      try {
        krab.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('op volle grootte, één keer; wat in gsm-formaat lag, wordt vervangen', () async {
      final vol = ReleaseArt(front: _b(1), back: _b(2), disc: _b(3));
      final gevraagd = <bool>[];
      DiscogsArtwork.vanDePc = (artist, album, {bool klein = false, String? plaat}) async {
        gevraagd.add(klein);
        return (art: klein ? ReleaseArt(front: _b(1, 50), back: _b(2, 50), disc: _b(3, 50)) : vol, klaar: true);
      };
      const rollen = {'front': 'https://voorbeeld.invalid/voor.jpg'};
      final dienst = DiscogsService(AppSettings());
      // Eerst onderweg in gsm-formaat (zoals op mobiele data).
      DiscogsArtwork.zuinig = () => true;
      await dienst.releaseArt('Ed Sheeran', 'Azizam', expectedTracks: 1, roles: rollen);
      DiscogsArtwork.zuinig = null;
      expect(await dienst.scansVooraf('Ed Sheeran', 'Azizam', expectedTracks: 1, roles: rollen), Voorafstand.gehaald);
      expect(gevraagd, [true, false], reason: 'het gsm-formaat telt niet als af');
      expect((await dienst.cachedReleaseArt('Ed Sheeran', 'Azizam', expectedTracks: 1, roles: rollen))?.disc, vol.disc);
      expect(await dienst.scansVooraf('Ed Sheeran', 'Azizam', expectedTracks: 1, roles: rollen), Voorafstand.al);
      expect(gevraagd, [true, false], reason: 'wat er af ligt, vraagt hij niet opnieuw');
    });

    test('heeft de pc niets, dan niets; zonder pc houdt het op', () async {
      final dienst = DiscogsService(AppSettings());
      expect(await dienst.scansVooraf('A', 'B'), Voorafstand.geenPc);
      DiscogsArtwork.vanDePc = (artist, album, {bool klein = false, String? plaat}) async => null;
      expect(await dienst.scansVooraf('A', 'B'), Voorafstand.nietOpPc);
      DiscogsArtwork.vanDePc = (artist, album, {bool klein = false, String? plaat}) async => throw const SocketException('weg');
      expect(await dienst.scansVooraf('A', 'B'), Voorafstand.geenPc);
    });
  });

  test('aangesloten: thuis op wifi, de hele bibliotheek, de digitale voorkant erbij, en niet weggesnoeid', () {
    String lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final main = lees('lib/main.dart');
    expect(main, contains('            settings.scansVooraf && library.remote != null && netStore.net == Netsoort.wifi && !netStore.onderweg,\n'));
    expect(main, contains('        albums: () => [...library.albums],\n'));
    expect(main, contains('await CoverEnricher(settings).digitaleVoorkant(v.artist, v.album,\n'
        '                titels: [for (final t in al.tracks) t.title], plaat: v.plaat, jaar: v.jaar);'));
    expect(main, contains('          maxBytes: !isTv && settings.scansVooraf ? kReleaseartVooraf : kReleaseartToestel,\n'));
    expect(main, contains('      netStore.addListener(vooraf.kijk);\n'));
    expect(lees('lib/settings.dart'), contains("        scansVooraf = (m['scans_vooraf'] ?? Platform.isAndroid) as bool;\n"));
  });
}
