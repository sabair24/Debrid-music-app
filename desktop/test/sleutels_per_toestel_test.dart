import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Elk toestel een sleutel van zichzelf, koppelen geeft altijd een NIEUWE, en intrekken blijft
/// ingetrokken — ook na een herstart en ook als een tweede kopie van de app een oude momentopname
/// wegschrijft. Stap 2.2 en 2.3 van het plan "verbinden zoals Roon ARC" (14-10-2026).
const _gsm = '0123456789abcdef0123456789abcdef';

void main() {
  late Directory map;
  setUp(() => map = Directory.systemTemp.createTempSync('dm_sleutels_'));
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });
  File bestand() => File('${map.path}/grants.json');

  group('nieuweSleutel', () {
    test('twee keer koppelen: twee sleutels, één rij, en de vorige blijft geldig', () {
      final g = GrantStore(file: bestand());
      final eerste = g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26');
      final tweede = g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26');
      expect(tweede.token, isNot(eerste.token), reason: 'nooit de bestaande sleutel teruggeven');
      expect(g.all, hasLength(1));
      expect(g.accepts(tweede.token), isTrue);
      expect(g.accepts(eerste.token), isTrue, reason: 'een toestel dat zijn antwoord kwijtraakte mag erin');
      expect(tweede.oudereTokens.first, eerste.token, reason: 'de recentste vorige eerst');
      expect(tweede.grantedAt, greaterThan(eerste.grantedAt));
    });

    test('hoogstens drie vorige sleutels', () {
      final g = GrantStore(file: bestand());
      final sleutels = [for (var i = 0; i < 6; i++) g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token];
      final rij = g.all.single;
      expect(rij.oudereTokens, hasLength(3));
      expect(rij.oudereTokens, [sleutels[4], sleutels[3], sleutels[2]]);
      expect(g.accepts(sleutels[0]), isFalse);
    });

    test('een ingetrokken toestel komt met een nieuwe koppeling gewoon terug, ook na opslaan', () async {
      final g = GrantStore(file: bestand());
      g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26');
      await g.save();
      g.revoke(_gsm);
      await g.save();
      final weer = g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26');
      await g.save();
      expect(g.accepts(weer.token), isTrue,
          reason: 'de oude lijst ingetrokken toestellen op schijf mag het niet meteen weer intrekken');
      final na = GrantStore(file: bestand());
      await na.load();
      expect(na.accepts(weer.token), isTrue);
    });
  });

  group('intrekken', () {
    test('één sleutel intrekken laat de andere sleutels van het toestel werken', () {
      final g = GrantStore(file: bestand());
      final echt = g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      final kaper = g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      expect(g.trekSleutelIn(kaper), isTrue);
      expect(g.accepts(kaper), isFalse);
      expect(g.accepts(echt), isTrue, reason: 'je echte gsm blijft binnen');
    });

    test('de rij van de gedeelde sleutel intrekken blijft gelden, ook als hij opnieuw wordt opgenomen', () {
      // `adoptLegacyToken` draait bij elk opzetten van het delen; de enige weg waarlangs een
      // ingetrokken sleutel weer in de sleuteltabel komt. Het tweede slot in `accepts` vangt hem.
      final g = GrantStore(file: bestand());
      g.adoptLegacyToken('de-oude-gedeelde-sleutel');
      expect(g.accepts('de-oude-gedeelde-sleutel'), isTrue);
      g.revoke('legacy');
      g.adoptLegacyToken('de-oude-gedeelde-sleutel');
      expect(g.accepts('de-oude-gedeelde-sleutel'), isFalse);
    });

    test('een ingetrokken sleutel blijft ingetrokken na een herstart', () async {
      final g = GrantStore(file: bestand());
      g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26');
      final weg = g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      g.trekSleutelIn(weg);
      await g.save();
      final na = GrantStore(file: bestand());
      await na.load();
      expect(na.accepts(weg), isFalse);
      // En hij staat niet leesbaar op schijf, alleen als vingerafdruk.
      final ingetrokken = File('${map.path}/grants_ingetrokken.json').readAsStringSync();
      expect(ingetrokken, isNot(contains(weg)));
    });

    test('een tweede kopie met een oude momentopname zet de ingetrokken sleutel niet terug', () async {
      final a = GrantStore(file: bestand());
      final echt = a.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      final weg = a.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      await a.save();
      // Kopie B leest nu, en heeft dus beide sleutels in het geheugen.
      final b = GrantStore(file: bestand());
      await b.load();
      expect(b.accepts(weg), isTrue);

      a.trekSleutelIn(weg);
      await a.save();
      // B weet van niets en schrijft zijn momentopname weg.
      await b.save();

      final na = GrantStore(file: bestand());
      await na.load();
      expect(na.accepts(weg), isFalse, reason: 'koppelingen_overleven: samenvoegen mag intrekken niet terugdraaien');
      expect(na.accepts(echt), isTrue);
      expect(b.accepts(weg), isFalse, reason: 'ook B zelf weet het na zijn eigen opslaan');
    });

    test('een ingetrokken toestel komt via een oude kopie niet terug, ook niet na een herstart', () async {
      final a = GrantStore(file: bestand());
      final sleutel = a.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
      await a.save();
      final b = GrantStore(file: bestand());
      await b.load();
      a.revoke(_gsm);
      await a.save();
      expect(bestand().readAsStringSync(), isNot(contains(_gsm)),
          reason: 'het laatste toestel bewust ontkoppelen wordt nu ook echt weggeschreven');
      await b.save();
      expect(b.accepts(sleutel), isFalse, reason: 'de draaiende tweede kopie weet het na zijn opslaan ook');
      expect(bestand().readAsStringSync(), isNot(contains(_gsm)));
      final na = GrantStore(file: bestand());
      await na.load();
      expect(na.accepts(sleutel), isFalse);
      expect(na.all, isEmpty);
    });
  });

  group('toestel-id en naam', () {
    test('alleen letters, cijfers, _ en -, 8 tot 64 tekens', () {
      expect(geldigToestelId(_gsm), isTrue);
      expect(geldigToestelId('legacy'), isFalse, reason: 'de rij van de gedeelde sleutel');
      expect(geldigToestelId('a/b/c/d/e/f'), isFalse);
      expect(geldigToestelId('S26 Ultra van Saber'), isFalse);
      expect(geldigToestelId('x' * 65), isFalse);
      expect(geldigToestelId(''), isFalse);
    });

    test('een naam zonder stuurtekens, kort genoeg', () {
      expect(schoneToestelnaam('S26\nGEWEIGERD /api/catalog'), 'S26 GEWEIGERD /api/catalog');
      expect(schoneToestelnaam('x' * 100).length, 60);
      expect(schoneToestelnaam(42), 'Onbekend apparaat');
      expect(schoneToestelnaam('   '), 'Onbekend apparaat');
    });
  });

  group('de koppelroutes', () {
    late LanServer server;
    late GrantStore grants;
    late PairingStore pairing;
    final meldingen = <SleutelMelding>[];

    setUp(() async {
      grants = GrantStore(file: bestand());
      pairing = PairingStore();
      meldingen.clear();
      grants.nieuweSleutelMelding.addListener(() {
        final m = grants.nieuweSleutelMelding.value;
        if (m != null) meldingen.add(m);
      });
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'gedeelde-sleutel-van-32-tekens!!',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: pairing,
        grants: grants,
        port: 0,
        settings: AppSettings(),
        cloudUid: () => 'uid-saber',
        uidVanSleutel: (s) async => s == 'inlog-van-saber' ? 'uid-saber' : 'uid-iemand-anders',
      );
      expect(await server.start(), isNull);
    });

    tearDown(() => server.dispose());

    Future<(int, Map<String, dynamic>)> post(String pad, Map<String, dynamic> body) async {
      final http = HttpClient();
      try {
        final req = await http.postUrl(Uri.parse('http://127.0.0.1:${server.boundPort}$pad'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
        final res = await req.close();
        final tekst = await res.transform(utf8.decoder).join();
        return (res.statusCode, tekst.isEmpty ? <String, dynamic>{} : jsonDecode(tekst) as Map<String, dynamic>);
      } finally {
        http.close(force: true);
      }
    }

    Future<int> catalogus(String sleutel) async {
      final http = HttpClient();
      try {
        final req = await http.getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}/api/catalog'));
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sleutel');
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      } finally {
        http.close(force: true);
      }
    }

    test('koppelen met de code geeft een eigen sleutel, niet de gedeelde', () async {
      final (status, j) = await post('/pair', {'code': pairing.start(), 'deviceName': 'Shield', 'deviceId': _gsm});
      expect(status, 200);
      expect(j['token'], isNot('gedeelde-sleutel-van-32-tekens!!'));
      expect(grants.all.single.deviceId, _gsm);
      expect(await catalogus(j['token'] as String), 200);
      expect(meldingen.single.via, 'code');
      expect(meldingen.single.bestaand, isFalse);
    });

    test('een oud toestel zonder id krijgt er een van de pc', () async {
      final (status, j) = await post('/pair', {'code': pairing.start(), 'deviceName': 'Oude iPad'});
      expect(status, 200);
      expect(geldigToestelId(j['deviceId'] as String), isTrue);
      expect(grants.all.single.deviceName, 'Oude iPad');
    });

    test('een ongeldig id bij de code: 400, en de code blijft bruikbaar', () async {
      final code = pairing.start();
      final (status, _) = await post('/pair', {'code': code, 'deviceName': 'x', 'deviceId': 'a/b'});
      expect(status, 400);
      expect(grants.all, isEmpty);
      final (tweede, _) = await post('/pair', {'code': code, 'deviceName': 'x', 'deviceId': _gsm});
      expect(tweede, 200);
    });

    test('koppelen via het account: zonder geldig id of met "legacy" geen sleutel', () async {
      for (final id in [null, 'legacy', 'a/b', 'S26 Ultra']) {
        final (status, _) = await post('/pair-cloud',
            {'idToken': 'inlog-van-saber', 'deviceName': 'S26', if (id != null) 'deviceId': id});
        expect(status, 400, reason: 'deviceId $id');
      }
      expect(grants.all, isEmpty);
    });

    test('twee keer via het account: twee sleutels, één rij, twee meldingen, de oude werkt nog', () async {
      final (s1, j1) = await post('/pair-cloud', {'idToken': 'inlog-van-saber', 'deviceName': 'S26', 'deviceId': _gsm});
      final (s2, j2) = await post('/pair-cloud', {'idToken': 'inlog-van-saber', 'deviceName': 'S26', 'deviceId': _gsm});
      expect([s1, s2], [200, 200]);
      expect(j2['token'], isNot(j1['token']));
      expect(grants.all, hasLength(1));
      expect(meldingen, hasLength(2));
      expect(meldingen.last.bestaand, isTrue);
      expect(meldingen.last.tekst, contains('bestaand toestel'));
      expect(await catalogus(j1['token'] as String), 200);
      expect(await catalogus(j2['token'] as String), 200);
    });

    test('een ander account krijgt niets', () async {
      final (status, _) = await post('/pair-cloud', {'idToken': 'iets-anders', 'deviceName': 'S26', 'deviceId': _gsm});
      expect(status, 403);
      expect(grants.all, isEmpty);
      expect(meldingen, isEmpty);
    });

    test('[Intrekken] op de melding sluit precies die sleutel af', () async {
      final (_, j1) = await post('/pair-cloud', {'idToken': 'inlog-van-saber', 'deviceName': 'S26', 'deviceId': _gsm});
      final (_, j2) = await post('/pair-cloud', {'idToken': 'inlog-van-saber', 'deviceName': 'S26', 'deviceId': _gsm});
      grants.trekSleutelIn(meldingen.last.sleutel);
      await grants.save();
      expect(await catalogus(j2['token'] as String), 401);
      expect(await catalogus(j1['token'] as String), 200);
    });

    test('de gedeelde sleutel blijft werken (cast-URL’s van de pc zelf)', () async {
      expect(await catalogus('gedeelde-sleutel-van-32-tekens!!'), 200);
    });
  });

  group('waar het aan de app vastzit', () {
    test('de pc toont de gedeelde sleutel niet meer, ook niet als QR', () {
      final hoofd = File('lib/main.dart').readAsStringSync();
      final delen = File('lib/lan/sharing.dart').readAsStringSync();
      expect(hoofd, isNot(contains('QrImageView')));
      expect(hoofd, isNot(contains("_copy(sharing.token")));
      expect(delen, isNot(contains('get pairingCode {')));
    });

    test('elke nieuwe sleutel komt op het scherm van de pc, met Intrekken', () {
      final hoofd = File('lib/main.dart').readAsStringSync();
      expect(hoofd, contains('nieuweSleutelMelding.addListener(_toonSleutelMelding)'));
      final start = hoofd.indexOf('void _toonSleutelMelding()');
      expect(start, greaterThan(-1));
      final lijf = hoofd.substring(start, start + 1600);
      expect(lijf, contains("label: 'Intrekken'"));
      expect(lijf, contains('trekSleutelIn(m.sleutel)'));
    });

    test('de pc deelt geen sleutels meer uit via Firestore', () {
      final cloud = File('lib/cloud/cloud_session.dart').readAsStringSync();
      expect(cloud, isNot(contains("'status': 'granted'")));
      expect(cloud, isNot(contains('_grantPending')));
      expect(cloud, contains('_wisSleutelsUitDatabase'));
    });
  });
}
