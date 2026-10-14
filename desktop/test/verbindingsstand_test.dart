/// De regel bovenin: langs welke weg de pc bereikt wordt, en waarom niet als het niet lukt.
///
/// Stap 4d van "verbinden zoals Roon ARC" (14-10-2026). De reden komt uit de hartslag die de pc in
/// het account schrijft, met de klok van Firestore aan beide kanten — een gsm waarvan de klok een uur
/// verkeerd staat, zegt nog steeds het goede.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/cloud/firestore.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/client_session.dart';
import 'package:debridmusic/lan/discovery.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/verbindingsstand.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/netwerkwissel.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

final _nu = DateTime.utc(2026, 10, 14, 12, 0, 0);

Hartslag _slag({bool online = true, required Duration oud, DateTime? serverNu}) =>
    Hartslag(online: online, bijgewerkt: (serverNu ?? _nu).subtract(oud), serverNu: serverNu ?? _nu);

Future<int> _vrijePoort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final poort = s.port;
  await s.close();
  return poort;
}

Future<void> _wachtTot(bool Function() klaar, {Duration max = const Duration(seconds: 20)}) async {
  final eind = DateTime.now().add(max);
  while (!klaar() && DateTime.now().isBefore(eind)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('de weg naar een adres', () {
    test('thuis, Tailscale, rechtstreeks', () {
      expect(wegNaar(Uri.parse('http://192.168.0.10:47820')), Verbindingsweg.thuis);
      expect(wegNaar(Uri.parse('http://10.0.0.5:47820')), Verbindingsweg.thuis);
      expect(wegNaar(Uri.parse('http://127.0.0.1:47820')), Verbindingsweg.thuis);
      expect(wegNaar(Uri.parse('http://100.64.0.7:47820')), Verbindingsweg.tailscale);
      expect(wegNaar(Uri.parse('http://[fd7a:115c:a1e0::7]:47820')), Verbindingsweg.tailscale);
      expect(wegNaar(Uri.parse('https://203.0.113.9:47821')), Verbindingsweg.rechtstreeks);
    });

    test('een naam: *.ts.net is Tailscale, een kale naam thuis, de rest rechtstreeks', () {
      expect(wegNaar(Uri.parse('http://saber-pc.tail1234.ts.net:47820')), Verbindingsweg.tailscale);
      expect(wegNaar(Uri.parse('http://saber-pc:47820')), Verbindingsweg.thuis);
      expect(wegNaar(Uri.parse('http://saber-pc.local:47820')), Verbindingsweg.thuis);
      expect(wegNaar(Uri.parse('https://muziek.example.org:47821')), Verbindingsweg.rechtstreeks);
    });
  });

  group('waarom niet, uit de hartslag', () {
    test('online:false gaat voor, ook al is het document net geschreven', () {
      expect(waaromNiet(hartslag: _slag(online: false, oud: const Duration(seconds: 5))), Waarom.pcUit);
    });

    test('vers (≤ 3 min): de pc staat aan, de weg naar binnen ontbreekt', () {
      expect(waaromNiet(hartslag: _slag(oud: const Duration(minutes: 2))), Waarom.pcAanMaarDicht);
      expect(waaromNiet(hartslag: _slag(oud: const Duration(minutes: 3))), Waarom.pcAanMaarDicht);
    });

    test('drie tot vijf minuten: nog geen oordeel', () {
      expect(waaromNiet(hartslag: _slag(oud: const Duration(minutes: 4))), Waarom.twijfel);
      expect(waaromNiet(hartslag: _slag(oud: const Duration(minutes: 5))), Waarom.twijfel);
    });

    test('meer dan vijf minuten: de pc antwoordt niet', () {
      expect(waaromNiet(hartslag: _slag(oud: const Duration(minutes: 10))), Waarom.pcStil);
    });

    test('10 min oud is "antwoordt niet", ook als de klok van de gsm een uur verkeerd staat', () {
      final slag = _slag(oud: const Duration(minutes: 10));
      for (final scheef in [const Duration(hours: 1), const Duration(hours: -1)]) {
        expect(waaromNiet(hartslag: slag, toestelNu: _nu.add(scheef)), Waarom.pcStil,
            reason: 'de leeftijd hoort met de klok van Firestore gerekend te worden, niet met die van het toestel');
      }
      // En andersom: een verse regel blijft vers, hoe de gsm ook staat.
      expect(waaromNiet(hartslag: _slag(oud: const Duration(minutes: 1)), toestelNu: _nu.add(const Duration(hours: 1))),
          Waarom.pcAanMaarDicht);
    });

    test('zonder Date-kop telt de klok van het toestel', () {
      final slag = Hartslag(online: true, bijgewerkt: _nu.subtract(const Duration(minutes: 1)));
      expect(waaromNiet(hartslag: slag, toestelNu: _nu), Waarom.pcAanMaarDicht);
      expect(waaromNiet(hartslag: slag, toestelNu: _nu.add(const Duration(minutes: 9))), Waarom.pcStil);
    });

    test('een hartslag van meer dan een dag zegt niets (de pc is niet aangemeld bij je account)', () {
      // Gemeten 14-10-2026 op de gsm: 31 dagen oud en online:false gaf "staat uit" bij een draaiende pc.
      expect(waaromNiet(hartslag: _slag(online: false, oud: const Duration(days: 31))), Waarom.onbekend);
      expect(waaromNiet(hartslag: _slag(oud: const Duration(days: 2))), Waarom.onbekend);
      expect(waaromNiet(hartslag: _slag(online: false, oud: const Duration(hours: 3))), Waarom.pcUit,
          reason: 'afgesloten en sindsdien niet meer gestart');
      expect(waaromNiet(hartslag: _slag(oud: const Duration(hours: 3))), Waarom.pcStil);
    });

    test('geen netwerk gaat voor alles; geen hartslag is "onbekend"', () {
      expect(waaromNiet(hartslag: _slag(oud: Duration.zero), geenNetwerk: true), Waarom.geenInternet);
      expect(waaromNiet(), Waarom.onbekend);
      expect(waaromNiet(hartslag: const Hartslag(online: true)), Waarom.onbekend);
    });
  });

  group('de tekst', () {
    test('verbonden langs elke weg', () {
      expect(verbindingsTekst(const Verbindingsstand.verbonden(Verbindingsweg.thuis), nu: _nu), 'Thuis');
      expect(verbindingsTekst(const Verbindingsstand.verbonden(Verbindingsweg.tailscale), nu: _nu),
          'Onderweg — via Tailscale');
      expect(verbindingsTekst(const Verbindingsstand.verbonden(Verbindingsweg.rechtstreeks), nu: _nu),
          'Onderweg — rechtstreeks');
    });

    test('zoeken telt de seconden', () {
      expect(verbindingsTekst(Verbindingsstand.zoekt(_nu.subtract(const Duration(milliseconds: 3400))), nu: _nu),
          'Zoekt je pc… 3 s');
      expect(verbindingsTekst(Verbindingsstand.zoekt(_nu.add(const Duration(seconds: 2))), nu: _nu), 'Zoekt je pc… 0 s');
    });

    test('elke reden', () {
      String t(Waarom w, {bool eigenDeur = false, bool kort = false}) => verbindingsTekst(
          Verbindingsstand.weg(w), nu: _nu, eigenDeur: eigenDeur, kort: kort, toestel: 'je gsm');
      expect(t(Waarom.pcUit), 'DebridMusic staat uit op je pc');
      expect(t(Waarom.pcStil), 'Je pc antwoordt niet (staat hij aan of slaapt hij?)');
      expect(t(Waarom.geenInternet), 'Geen internet op je gsm');
      expect(t(Waarom.twijfel), 'Zoekt je pc…');
      expect(t(Waarom.onbekend), 'Je pc reageert niet');
      // Tot uitlevering B is Tailscale de enige weg van buitenaf, en dat zegt de tekst.
      expect(t(Waarom.pcAanMaarDicht), contains('Tailscale'));
      expect(t(Waarom.pcAanMaarDicht, kort: true), contains('Tailscale'));
      expect(t(Waarom.pcAanMaarDicht, eigenDeur: true), 'Je modem laat de verbinding niet door');
    });
  });

  group('de Date-kop van Firestore', () {
    MockClient firestore({required String datum}) => MockClient((r) async {
          final doc = {
            'name': 'projects/p/databases/(default)/documents/users/u/servers/pc-saber-0001',
            'fields': {
              'online': {'booleanValue': true},
            },
            'updateTime': '2026-10-14T11:50:00.000000Z',
          };
          final body = r.url.path.endsWith('/servers') ? {'documents': [doc]} : doc;
          return http.Response(jsonEncode(body), 200, headers: {'date': datum, 'content-type': 'application/json'});
        });

    test('get en list geven de servertijd mee; 10 min oud is "antwoordt niet"', () async {
      final db = Firestore(token: 't', client: firestore(datum: 'Wed, 14 Oct 2026 12:00:00 GMT'));
      final doc = await db.get('users/u/servers/pc-saber-0001');
      expect(doc!.serverTijd, DateTime.utc(2026, 10, 14, 12));
      expect(doc.updateTime, DateTime.utc(2026, 10, 14, 11, 50));
      final lijst = await db.list('users/u/servers');
      expect(lijst.single.serverTijd, DateTime.utc(2026, 10, 14, 12));
      final slag = Hartslag(online: doc.data['online'] == true, bijgewerkt: doc.updateTime, serverNu: doc.serverTijd);
      // De klok van de gsm een uur ernaast: maakt niets uit.
      expect(waaromNiet(hartslag: slag, toestelNu: DateTime.now().add(const Duration(hours: 1))), Waarom.pcStil);
    });

    test('een onleesbare Date-kop is geen fout, alleen geen servertijd', () async {
      final db = Firestore(token: 't', client: firestore(datum: 'gisteren'));
      final doc = await db.get('users/u/servers/pc-saber-0001');
      expect(doc!.serverTijd, isNull);
      expect(doc.data['online'], isTrue);
    });
  });

  group('geen netwerk, volgens de netwerkwacht', () {
    Future<Netwerkwacht> wacht(List<NetwerkGebeurtenis> reeks) async {
      final bron = StreamController<NetwerkGebeurtenis>();
      final w = Netwerkwacht(bron: bron.stream, bijWissel: (_) async {}, rust: const Duration(milliseconds: 1))..start();
      for (final g in reeks) {
        bron.add(g);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await w.stop();
      await bron.close();
      return w;
    }

    const wifi = NetwerkGebeurtenis(soort: 'fysiek-beschikbaar', netwerk: '100', transport: 'wifi', gevalideerd: true);
    const mobiel = NetwerkGebeurtenis(soort: 'fysiek-beschikbaar', netwerk: '101', transport: 'mobiel', gevalideerd: true);
    const wifiWeg = NetwerkGebeurtenis(soort: 'fysiek-weg', netwerk: '100');
    const mobielWeg = NetwerkGebeurtenis(soort: 'fysiek-weg', netwerk: '101');

    test('Android: wifi weg met mobiel erbij is nog netwerk; allebei weg niet', () async {
      expect((await wacht([wifi, mobiel, wifiWeg])).geenNetwerk, isFalse);
      expect((await wacht([wifi, mobiel, wifiWeg, mobielWeg])).geenNetwerk, isTrue,
          reason: 'met Tailscale aan blijft de VPN het standaardnetwerk; alleen de fysieke netwerken zeggen het');
      expect((await wacht([wifi, wifiWeg, mobiel])).geenNetwerk, isFalse);
    });

    test('Android: het standaardnetwerk weg en terug', () async {
      expect((await wacht([const NetwerkGebeurtenis(soort: 'standaard-weg', netwerk: '100')])).geenNetwerk, isTrue);
      expect(
          (await wacht([
            const NetwerkGebeurtenis(soort: 'standaard-weg', netwerk: '100'),
            const NetwerkGebeurtenis(soort: 'standaard-beschikbaar', netwerk: '101', transport: 'mobiel'),
          ]))
              .geenNetwerk,
          isFalse);
    });

    test('iOS en macOS: het pad zegt het zelf; niets gemeld is geen "geen internet"', () async {
      expect((await wacht([const NetwerkGebeurtenis(soort: 'pad', transport: 'weg')])).geenNetwerk, isTrue);
      expect(
          (await wacht([
            const NetwerkGebeurtenis(soort: 'pad', transport: 'weg'),
            const NetwerkGebeurtenis(soort: 'pad', transport: 'mobiel', gevalideerd: true),
          ]))
              .geenNetwerk,
          isFalse);
      expect((await wacht([])).geenNetwerk, isFalse);
    });
  });

  test('uitwijk: ook de thuisadressen van de pc doen mee', () async {
    // Gemeten 14-10-2026: een gsm die via Tailscale koppelde, kende zijn pc thuis alleen via Tailscale.
    final nep = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => nep.close(force: true));
    nep.listen((req) async {
      req.response.write(jsonEncode({
        'urls': ['http://100.64.0.7:47820'],
        'thuis': ['http://192.168.0.117:47820'],
      }));
      await req.response.close();
    });
    final u = await RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${nep.port}'), token: 'x')).uitwijk();
    expect(u.urls, ['http://100.64.0.7:47820', 'http://192.168.0.117:47820']);
  });

  group('de stand van een echte sessie', () {
    late Directory scratch, pcRoot;
    final servers = <LanServer>[];

    Future<Uri> pc(String serverId, {int poort = 0}) async {
      final map = Directory('${pcRoot.path}/$serverId-$poort/Portishead/Dummy')..createSync(recursive: true);
      final f = File('${map.path}/01.flac')..writeAsBytesSync(List<int>.filled(2048, 0));
      final lib = LibraryStore()..tracks.add(Track(path: f.path, title: 'Mysterons', artist: 'Portishead', album: 'Dummy'));
      lib.albums = [Album('Dummy', 'Portishead', lib.tracks.toList())];
      final s = LanServer(
        library: lib,
        token: 'gedeelde-$serverId',
        state: LanStateStore(File('${pcRoot.path}/$serverId-$poort/state.json')),
        pairing: PairingStore(),
        port: poort,
        settings: AppSettings()..serverId = serverId,
      );
      expect(await s.start(), isNull);
      servers.add(s);
      return Uri.parse('http://127.0.0.1:${s.boundPort}');
    }

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('dm_stand_');
      setAppDirForTest(scratch.path);
      pcRoot = Directory.systemTemp.createTempSync('dm_stand_pc_');
    });

    tearDown(() async {
      for (final s in servers) {
        await s.dispose();
      }
      servers.clear();
      for (final m in [pcRoot, scratch]) {
        try {
          m.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    ClientSession sessie({
      Future<Hartslag?> Function(String id)? hartslag,
      Future<List<FoundServer>> Function()? zoek,
    }) =>
        ClientSession(
          library: LibraryStore(),
          settings: AppSettings(),
          owner: false,
          applyMediaResolver: (_) {},
          zoekOpNetwerk: zoek ?? () async => const [],
          hartslagUitAccount: hartslag,
        );

    String logboek() {
      final f = File('${scratch.path}${Platform.pathSeparator}verbinding.log');
      return f.existsSync() ? f.readAsStringSync() : '';
    }

    test('de pc antwoordt: verbonden, thuis — en geen korte melding bij de eerste verbinding', () async {
      final adres = await pc('pc-saber-0001');
      final s = sessie();
      addTearDown(s.dispose);
      await s.connect(RemoteEndpoint(baseUrl: adres, token: 'gedeelde-pc-saber-0001', serverId: 'pc-saber-0001'),
          remember: false);
      expect(s.verbinding.soort, Verbindingssoort.verbonden);
      expect(s.verbinding.weg, Verbindingsweg.thuis);
      expect(s.wegGewisseld, isNull, reason: '"Thuis" bij elk openen van de app is ruis');
      expect(logboek(), contains('stand: Thuis'));
    });

    test('niemand antwoordt, de pc schreef net nog: "staat aan, maar niet bereikbaar"', () async {
      final dood = Uri.parse('http://127.0.0.1:${await _vrijePoort()}');
      final gevraagd = <String>[];
      final s = sessie(hartslag: (id) async {
        gevraagd.add(id);
        return Hartslag(online: true, bijgewerkt: DateTime.now().subtract(const Duration(seconds: 40)), serverNu: DateTime.now());
      });
      addTearDown(s.dispose);
      await s.connect(RemoteEndpoint(baseUrl: dood, token: 'x', serverId: 'pc-saber-0001'), remember: false);
      await _wachtTot(() => s.verbinding.soort == Verbindingssoort.weg);
      expect(s.verbinding.waarom, Waarom.pcAanMaarDicht);
      expect(gevraagd.first, 'pc-saber-0001', reason: 'de hartslag van DEZE pc, op zijn id');
      expect(logboek(), contains('waarom niet: pcAanMaarDicht (hartslag aan, '));
    });

    test('de app op de pc is afgesloten: "staat uit"', () async {
      final dood = Uri.parse('http://127.0.0.1:${await _vrijePoort()}');
      final s = sessie(hartslag: (_) async => Hartslag(online: false, bijgewerkt: DateTime.now(), serverNu: DateTime.now()));
      addTearDown(s.dispose);
      await s.connect(RemoteEndpoint(baseUrl: dood, token: 'x', serverId: 'pc-saber-0001'), remember: false);
      await _wachtTot(() => s.verbinding.soort == Verbindingssoort.weg);
      expect(s.verbinding.waarom, Waarom.pcUit);
    });

    test('Firestore onbereikbaar of geen netwerk: "geen internet", en zonder netwerk niet eens gevraagd', () async {
      final dood = Uri.parse('http://127.0.0.1:${await _vrijePoort()}');
      final s1 = sessie(hartslag: (_) async => throw const HartslagOnbereikbaar());
      addTearDown(s1.dispose);
      await s1.connect(RemoteEndpoint(baseUrl: dood, token: 'x', serverId: 'pc-saber-0001'), remember: false);
      await _wachtTot(() => s1.verbinding.soort == Verbindingssoort.weg);
      expect(s1.verbinding.waarom, Waarom.geenInternet);

      var gevraagd = 0;
      final s2 = sessie(hartslag: (_) async {
        gevraagd++;
        return null;
      })
        ..geenNetwerk = () => true;
      addTearDown(s2.dispose);
      await s2.connect(RemoteEndpoint(baseUrl: dood, token: 'x', serverId: 'pc-saber-0001'), remember: false);
      await _wachtTot(() => s2.verbinding.soort == Verbindingssoort.weg);
      expect(s2.verbinding.waarom, Waarom.geenInternet);
      expect(gevraagd, 0, reason: 'zonder netwerk kost een leesbeurt in je account alleen wachten');
    });

    test('een netwerkwissel zoekt eerst, en na een tijd zonder pc meldt hij kort de weg terug', () async {
      final later = await _vrijePoort();
      final dood = Uri.parse('http://127.0.0.1:${await _vrijePoort()}');
      final s = sessie(hartslag: (_) async => null);
      addTearDown(s.dispose);
      // Het uitwijkadres antwoordt nog niet: de pc staat er pas straks.
      await s.connect(
          RemoteEndpoint(
              baseUrl: dood, token: 'gedeelde-pc-saber-0001', serverId: 'pc-saber-0001', uitwijk: ['http://127.0.0.1:$later']),
          remember: false);
      await _wachtTot(() => s.verbinding.soort == Verbindingssoort.weg);
      expect(s.verbinding.waarom, Waarom.onbekend);
      expect(s.wegGewisseld, isNull);
      // Eerst de zoektocht laten aflopen die de mislukte eerste poll startte; een wissel tijdens die
      // zoektocht heeft een eigen toets hieronder. Op de sessie zelf, niet op het logboek: daar
      // schrijven ook sessies van een vorige toets in die nog zoeken.
      await _wachtTot(() => !s.zoektNu);

      await pc('pc-saber-0001', poort: later);
      final standen = <Verbindingssoort>[];
      s.addListener(() => standen.add(s.verbinding.soort));
      await s.netwerkVeranderd('test: wifi weg, mobiel erbij');
      expect(standen.first, Verbindingssoort.zoekt, reason: 'bij een wissel weet niemand iets tot de wedloop klaar is');
      expect(s.verbinding.soort, Verbindingssoort.verbonden);
      expect(s.wegGewisseld, isNotNull, reason: 'na een tijd zonder pc hoort de weg terug even in beeld');
    });

    test('een wissel tijdens een lopende zoektocht gaat niet verloren: daarna wordt alsnog gekozen', () async {
      final later = await _vrijePoort();
      final dood = Uri.parse('http://127.0.0.1:${await _vrijePoort()}');
      // Het zoeken op het netwerk houdt de zoektocht vast tot de toets hem loslaat.
      final hek = Completer<List<FoundServer>>();
      final s = sessie(hartslag: (_) async => null, zoek: () => hek.future);
      addTearDown(() {
        if (!hek.isCompleted) hek.complete(const []);
        s.dispose();
      });
      // Onthouden koppeling, geen wedloop bij het verbinden: de eerste poll mislukt en start de zoektocht.
      unawaited(s.connect(RemoteEndpoint(
          baseUrl: dood, token: 'gedeelde-pc-saber-0001', serverId: 'pc-saber-0001', uitwijk: ['http://127.0.0.1:$later'])));
      await _wachtTot(() => s.zoektNu);
      // Nu pas de pc, als de lopende zoektocht zijn bekende adressen zeker gehad heeft: een wedloop
      // duurt hoogstens 400 ms voorsprong plus drie seconden per poging. Daarna wacht hij op het hek.
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(s.zoektNu, isTrue, reason: 'de zoektocht hoort nog op het hek te wachten');
      await pc('pc-saber-0001', poort: later);
      await s.netwerkVeranderd('test: wifi weg, mobiel erbij');
      expect(logboek(), contains('er wordt al gekozen; daarna opnieuw'));
      hek.complete(const []);
      await _wachtTot(() => s.endpoint?.baseUrl.port == later, max: const Duration(seconds: 10));
      expect(s.verbinding.soort, Verbindingssoort.verbonden,
          reason: 'zonder tweede beurt bleef de app tot de volgende poll-zoektocht (≥ 30 s) op "geen pc" staan');
      expect(s.endpoint?.baseUrl.port, later);
      expect(logboek(), contains('na de lopende keuze'));
    });

    test('na een wissel zonder winnaar: één herkansing, die de pc alsnog vindt', () async {
      // Gemeten 14-10-2026: Tailscale had na wifi → mobiel ruim drie seconden nodig; de wedloop gaf het
      // na drie seconden op, en pas de volgende poll (tot vijftien seconden later) vond de pc.
      final later = await _vrijePoort();
      final dood = Uri.parse('http://127.0.0.1:${await _vrijePoort()}');
      final s = sessie(hartslag: (_) async => null)..herkansingNaWissel = const Duration(seconds: 2);
      addTearDown(s.dispose);
      await s.connect(RemoteEndpoint(
          baseUrl: dood, token: 'gedeelde-pc-saber-0001', serverId: 'pc-saber-0001', uitwijk: ['http://127.0.0.1:$later']));
      await _wachtTot(() => !s.zoektNu);
      unawaited(s.netwerkVeranderd('test: wifi weg, mobiel erbij'));
      expect(s.verbinding.soort, Verbindingssoort.zoekt);
      // De eerste wedloop is voorbij als de sessie "weg" zegt; pas dan staat de pc er ("Tailscale heeft de
      // weg gevonden"). Niet afhankelijk van hoe lang een geweigerde verbinding duurt: op Windows twee
      // seconden (SYN-herhalingen), op de Linux-bouwstraat meteen.
      await _wachtTot(() => s.verbinding.soort == Verbindingssoort.weg);
      await pc('pc-saber-0001', poort: later);
      await _wachtTot(() => s.endpoint?.baseUrl.port == later, max: const Duration(seconds: 8));
      expect(s.endpoint?.baseUrl.port, later, reason: 'zonder herkansing pas na de volgende poll-zoektocht');
      expect(logboek(), contains('herkansing na: test'));
    });

    test('"Opnieuw proberen" laat zien dat er gezocht wordt, ook als de reden er al stond', () async {
      final dood = Uri.parse('http://127.0.0.1:${await _vrijePoort()}');
      final s = sessie(hartslag: (_) async => null);
      addTearDown(s.dispose);
      await s.connect(RemoteEndpoint(baseUrl: dood, token: 'x', serverId: 'pc-saber-0001'), remember: false);
      await _wachtTot(() => s.verbinding.soort == Verbindingssoort.weg);
      final standen = <Verbindingssoort>[];
      s.addListener(() => standen.add(s.verbinding.soort));
      // `refreshNow` zoekt alleen meteen als de laatste poll "pc stil" zei; die poll komt na het verbinden.
      await _wachtTot(() => s.library.geenVerbinding != null);
      await s.refreshNow();
      expect(standen, contains(Verbindingssoort.zoekt));
    });
  });
}
