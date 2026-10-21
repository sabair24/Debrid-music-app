// ▶ op de gsm (en iPad, Mac, Shield) met dezelfde snelle weg als op de pc (Saber, 20-10-2026: "dit allemaal
// mogelijk maken maar via de gsm en andere toestellen"). Gemeten vóór deze stap: de pc haalde voor een
// toestel nog langs de oude weg — geen wedloop, geen vroege start — en de gsm speelde pas na het landen.
//
// Nu: de pc haalt met een groeistroom, zegt in de stand wanneer het kan klinken, en geeft de stroom door
// (`/groei/<id>.flac`). Breekt een uploader af, dan wacht de gsm via `groeiwacht` op de volgende en gaat op
// dezelfde plek verder. Hier de lijn: een echte LanServer, een echte groeistroom, een nagebootste gsm.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/groeistroom.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/pc_radiobron.dart';
import 'package:debridmusic/lan/radiohaler.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/settings.dart';

Uint8List _bytes(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + 7) & 0xFF]);

typedef _Antwoord = ({int status, HttpHeaders? kop, List<int> lijf, Object? fout});

Future<_Antwoord> _haal(Uri adres, {String? bereik, void Function(int binnen)? bijBytes}) async {
  final c = HttpClient();
  final lijf = <int>[];
  var status = 0;
  HttpHeaders? kop;
  try {
    final req = await c.getUrl(adres);
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

Future<void> _totDat(bool Function() klopt) async {
  final eind = DateTime.now().add(const Duration(seconds: 5));
  while (!klopt()) {
    if (DateTime.now().isAfter(eind)) fail('wachtte te lang');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Een pc die antwoordt wat de toets wil.
class _Pc extends RemoteClient {
  _Pc(this.antwoord) : super(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.2:47820'), token: 't'));
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> vraag) antwoord;
  final vragen = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> ask(String path, Map<String, dynamic> body) {
    vragen.add(body);
    return antwoord(body);
  }
}

/// Een catalogus waarin het gehaalde nummer meteen staat.
class _Catalogus extends LibraryStore {
  _Catalogus(this.t, this.id);
  final Track t;
  final String id;

  @override
  Future<bool> loadRemote({bool quiet = false, bool naEen304 = false}) async {
    tracks
      ..clear()
      ..add(t);
    return true;
  }

  @override
  String? gedeeldId(String path) => path == t.path ? id : null;
}

/// De haal op de pc: het hele bestand meteen, goedgekeurd, en landen pas op [landen].
class _Groeiend extends DownloadManager {
  _Groeiend(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged, this.map);
  final String map;
  final landen = Completer<void>();
  Groei? gekregen;
  bool? zoekBeterGevraagd;
  final losGevraagd = <String, bool>{};
  final albumGevraagd = <String, String?>{};

  @override
  Future<String?> haalEnLaatHoren(
      {required String artiest,
      required String titel,
      int? seconden,
      int? jaar,
      Groei? vroeg,
      bool zoekDaarnaBeter = false,
      bool losVanDeRadio = false,
      String? album}) async {
    gekregen = vroeg;
    zoekBeterGevraagd = zoekDaarnaBeter;
    losGevraagd[titel] = losVanDeRadio;
    albumGevraagd[titel] = album;
    final pad = '$map${Platform.pathSeparator}in.flac';
    File(pad).writeAsBytesSync(_bytes(300 * 1024));
    vroeg?.poging(pad: pad, totaal: 300 * 1024);
    vroeg?.goedgekeurd(const Duration(seconds: 30));
    await landen.future;
    return null;
  }

  @override
  Future<String?> haalVoorRadio({required String artiest, required String titel, int? seconden, int? jaar}) =>
      fail('met de proef aan hoort de pc voor een toestel de snelle weg te nemen');
}

void main() {
  group('de pc: halen voor een toestel met de snelle weg', () {
    late Directory map;
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_groeitoestel_');
      setAppDirForTest(map.path);
    });
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('met de proef aan een groei, en de stand noemt hem zodra het kan klinken', () async {
      final cfg = AppSettings()..vroegLuisteren = true;
      final d = _Groeiend(OnlineService(cfg), SoulseekService(cfg), map.path, () async {}, map.path);
      final h = Radiohaler(d, null, LibraryStore()..configDirOverride = map.path, cfg);
      final haal = h.haal(artiest: 'Gorki', titel: 'Anja', zoekBeter: true, luistertMee: true, album: 'Gorki');
      await _totDat(() => d.gekregen != null);
      expect(d.zoekBeterGevraagd, isTrue, reason: '▶ op het toestel: daarna op jacht naar beter');
      expect(d.albumGevraagd['Anja'], 'Gorki', reason: 'het album waarop je het zag, tot in de haal');
      final g = d.gekregen!;
      // Zonder dat iemand op de pc het vraagt: de pc wacht zelf tot het kan klinken.
      await _totDat(() => g.kanKlinken);
      expect(h.stand(haal.id)['groei'], g.id);
      expect(h.groeiVoor(g.id), same(g));
      expect(h.groeiVoor('iets-anders'), isNull, reason: 'een toestel komt nooit bij wat de pc zelf speelt');
      d.landen.complete();
      await _totDat(() => h.stand(haal.id)['stand'] != 'onderweg');
      expect(h.stand(haal.id).containsKey('groei'), isFalse, reason: 'na de haal geen groei meer in de stand');
    });

    test('▶ hoort niet bij de radio: een radio die stopt, laat hem staan (Stargazing, 20-10-2026)', () async {
      final cfg = AppSettings()..vroegLuisteren = true;
      final d = _Groeiend(OnlineService(cfg), SoulseekService(cfg), map.path, () async {}, map.path);
      final h = Radiohaler(d, null, LibraryStore()..configDirOverride = map.path, cfg);
      final speel = h.haal(artiest: 'Myles Smith', titel: 'Stargazing', zoekBeter: true, luistertMee: true);
      final radio = h.haal(artiest: 'Madison Beer', titel: 'Home To Another One');
      await _totDat(() => d.losGevraagd.length == 2);
      expect(d.losGevraagd['Stargazing'], isTrue, reason: 'de pc zet ▶ niet bij de radiohalen');
      expect(d.losGevraagd['Home To Another One'], isFalse);
      h.staak();
      expect(h.stand(speel.id)['stand'], 'onderweg', reason: 'het sluiten van een radio brak ▶ af: 404, niets te horen');
      expect(h.stand(radio.id)['stand'], 'mislukt');
      d.landen.complete();
    });

    test('met de proef uit: de oude weg, en geen groei in de stand', () async {
      final cfg = AppSettings()..vroegLuisteren = false;
      final d = _Oud(OnlineService(cfg), SoulseekService(cfg), map.path, () async {});
      final h = Radiohaler(d, null, LibraryStore()..configDirOverride = map.path, cfg);
      final haal = h.haal(artiest: 'Gorki', titel: 'Anja');
      await _totDat(() => d.gevraagd);
      expect(h.stand(haal.id).containsKey('groei'), isFalse);
    });
  });

  group('de lijn: de pc geeft de groeistroom door', () {
    late Directory map;
    late LanServer server;
    late Groeistroom stroom;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_groeilijn_');
      setAppDirForTest(map.path);
      final library = LibraryStore()
        ..rootPath = map.path
        ..configDirOverride = map.path;
      server = LanServer(
        library: library,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await server.start(), isNull);
      stroom = Groeistroom(
          wachtOpPoging: const Duration(seconds: 2),
          stilGrens: const Duration(seconds: 3),
          peil: const Duration(milliseconds: 20));
    });

    tearDown(() async {
      await server.dispose();
      await stroom.stop();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Uri groeiAdres(Groei g, {Map<String, String>? vraag}) => Uri.parse('http://127.0.0.1:${server.boundPort}')
        .replace(path: '/groei/${g.id}.flac', queryParameters: {'token': 'sleutel', ...?vraag});

    test('het hele bestand en een stuk, met de lengte en Content-Range van de groeistroom', () async {
      final alles = _bytes(300 * 1024);
      final f = File('${map.path}/in.flac')..writeAsBytesSync(alles);
      final g = await stroom.nieuw('lijn');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 30));
      server.radiohaler.haalVoorToets(g);
      final heel = await _haal(groeiAdres(g));
      expect(heel.status, 200);
      expect(heel.kop!.contentLength, alles.length);
      expect(heel.lijf, alles);
      final stuk = await _haal(groeiAdres(g), bereik: 'bytes=1000-1999');
      expect(stuk.status, 206);
      expect(stuk.kop!.value(HttpHeaders.contentRangeHeader), 'bytes 1000-1999/${alles.length}');
      expect(stuk.lijf, alles.sublist(1000, 2000));
    });

    test('een uploader die afhaakt: de breuk komt door, en het lege einde daarna ook', () async {
      final alles = _bytes(400 * 1024);
      final f = File('${map.path}/in.flac')..writeAsBytesSync(alles.sublist(0, 200 * 1024));
      final g = await stroom.nieuw('afgehaakt');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 40));
      server.radiohaler.haalVoorToets(g);
      var binnen = 0;
      final antwoord = _haal(groeiAdres(g), bijBytes: (n) => binnen = n);
      await _totDat(() => binnen >= 200 * 1024);
      g.afgebroken();
      final a = await antwoord;
      expect(a.fout, isNotNull, reason: 'minder dan beloofd: een breuk, zodat mpv opnieuw vraagt');
      final weer = await _haal(groeiAdres(g), bereik: 'bytes=${200 * 1024}-');
      expect(weer.status, 206);
      expect(weer.kop!.contentLength, 0, reason: 'het einde van wat er was: mpv speelt uit en de speler gaat verder');
    });

    test('een onbekende groei: 404; zonder sleutel: niets', () async {
      final g = await stroom.nieuw('niet van een toestel');
      expect((await _haal(groeiAdres(g))).status, 404, reason: 'alleen een groei van een haal voor een toestel');
      server.radiohaler.haalVoorToets(g);
      final zonder = await _haal(Uri.parse('http://127.0.0.1:${server.boundPort}/groei/${g.id}.flac'));
      expect(zonder.status, 401);
    });

    test('groeiwacht: ja als het verder kan, nee als er geen uploader meer komt, weg als hij onbekend is', () async {
      final alles = _bytes(100 * 1024);
      final f = File('${map.path}/in.flac')..writeAsBytesSync(alles);
      final g = await stroom.nieuw('wacht');
      g.poging(pad: f.path, totaal: alles.length);
      g.goedgekeurd(const Duration(seconds: 10));
      await g.binnen();
      server.radiohaler.haalVoorToets(g);
      final c = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel'));
      expect(await c.ask('/api/radio', {'op': 'groeiwacht', 'groei': g.id, 'vanaf': 5000}), {'kan': true});
      expect(await GroeiOpPc(() => c, g.id).speelbaarVanaf(const Duration(seconds: 5)), isTrue);

      final weg = await stroom.nieuw('weg');
      server.radiohaler.haalVoorToets(weg);
      weg.opgegeven();
      expect(await c.ask('/api/radio', {'op': 'groeiwacht', 'groei': weg.id, 'vanaf': 0}), {'kan': false});
      expect(await GroeiOpPc(() => c, weg.id).speelbaarVanaf(Duration.zero), isFalse);
      expect((await c.ask('/api/radio', {'op': 'groeiwacht', 'groei': 'onbekend'}))['weg'], isTrue);
    });

    test('van buiten (mobiele data) mag /groei/ ook', () {
      expect(weigerVanBuiten('/groei/abc.flac', 'GET'), isNull);
    });
  });

  group('de gsm', () {
    test('GroeiOpPc vraagt opnieuw zolang de pc nog wacht, met de plek', () async {
      var n = 0;
      final pc = _Pc((v) async => ++n < 3 ? {'kan': false, 'nogBezig': true} : {'kan': true});
      final g = GroeiOpPc(() => pc, 'g7');
      expect(g.pad, 'http://pc.invalid/groei/g7.flac');
      expect(await g.speelbaarVanaf(const Duration(milliseconds: 83500)), isTrue);
      expect(pc.vragen, hasLength(3));
      expect(pc.vragen.first, {'op': 'groeiwacht', 'groei': 'g7', 'vanaf': 83500});
    });

    test('GroeiOpPc: een paar fouten zijn nog geen nee; vijf wel', () async {
      var n = 0;
      final eventjes = _Pc((v) async => ++n < 3 ? throw RemoteException('wifi weg') : {'kan': true});
      expect(await GroeiOpPc(() => eventjes, 'g1', ritme: Duration.zero).speelbaarVanaf(Duration.zero), isTrue);
      final dood = _Pc((v) async => throw RemoteException('weg'));
      expect(await GroeiOpPc(() => dood, 'g1', ritme: Duration.zero).speelbaarVanaf(Duration.zero), isFalse);
      expect(dood.vragen, hasLength(5));
    });

    test('PcRadiobron meldt één keer dat het klinkt, peilt dan rustiger, en geeft het gelande nummer', () async {
      final t = Track(path: 'http://pc.invalid/stream/abc.flac', title: 'Anja', artist: 'Gorki', album: 'Gorki');
      var peil = 0;
      final pc = _Pc((v) async {
        switch (v['op']) {
          case 'haal':
            return {'id': 'r1'};
          case 'stand':
            peil++;
            if (peil == 1) return {'stand': 'onderweg'};
            if (peil < 4) return {'stand': 'onderweg', 'groei': 'g9'};
            return {'stand': 'klaar', 'trackId': 'abc'};
        }
        return {};
      });
      final bron = PcRadiobron(
          library: _Catalogus(t, 'abc'), clientOf: () => pc, peilritme: const Duration(milliseconds: 5));
      final gemeld = <String>[];
      final klok = Stopwatch()..start();
      final uit = await bron.haal(Radioplek(artiest: 'Gorki', titel: 'Anja', album: 'Gorki'),
          zoekBeter: true, klinkt: gemeld.add);
      expect(uit?.path, t.path);
      expect(gemeld, ['g9'], reason: 'één keer, ook al noemt de stand hem vaker');
      final haal = pc.vragen.firstWhere((v) => v['op'] == 'haal');
      expect(haal['zoekBeter'], isTrue);
      expect(haal['meeluisteren'], isTrue);
      expect(haal['album'], 'Gorki', reason: 'de pc tagt het bestand met het album waarop je het zag');
      // Tot het klinkt elke halve seconde: één peiling (de eerste) op dat ritme, daarna het gewone.
      expect(klok.elapsed, greaterThanOrEqualTo(kPeilritmeVoorGeluid * 2));
      expect(klok.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('de radio op het toestel vraagt niet om mee te luisteren', () async {
      final pc = _Pc((v) async => v['op'] == 'haal' ? {'id': 'r1'} : {'stand': 'mislukt'});
      final bron = PcRadiobron(
          library: LibraryStore(), clientOf: () => pc, peilritme: const Duration(milliseconds: 5));
      await bron.haal(Radioplek(artiest: 'Gorki', titel: 'Anja'));
      final haal = pc.vragen.firstWhere((v) => v['op'] == 'haal');
      expect(haal.containsKey('meeluisteren'), isFalse);
      expect(haal.containsKey('zoekBeter'), isFalse);
      expect(haal.containsKey('album'), isFalse);
    });
  });

  group('aangesloten', () {
    test('de speler behandelt een groei op de pc als een eigen groei', () {
      final p = File('lib/player.dart').readAsStringSync();
      final einde = p.substring(p.indexOf('  void _onCompleted() {'));
      expect(einde, contains("if (_groeiVan(current?.path ?? '') != null &&"));
      final verder = p.substring(p.indexOf('  Future<void> _hervatGroei(Track t, Duration plek) async {'));
      expect(verder, contains('final g = _groeiVan(t.path);'));
      expect(verder, contains('if (Groeistroom.isAdres(verder) || _groeiElders.containsKey(verder)) {'),
          reason: 'verder met ?vanaf= en niet springen, ook via de pc');
      expect(p, contains('if (position <= Duration.zero || !_speeltGroei) return false;'));
      expect(p, contains('if (vast && _speeltGroei) {'));
    });

    test('▶ los van de radio, op de pc en via de pc', () {
      final online = File('lib/online.dart').readAsStringSync();
      expect(online, contains('if (!losVanDeRadio) _radiohalen.add(job);'));
      final radio = File('lib/radio.dart').readAsStringSync();
      expect(radio, contains('losVanDeRadio: los,'));
      final m = File('lib/main.dart').readAsStringSync();
      expect(m, contains('.haal(plek, vroeg: vroeg, zoekBeter: true, los: true)'));
      final rh = File('lib/lan/radiohaler.dart').readAsStringSync();
      expect(rh, contains("if (h.stand != 'onderweg' || h.los) continue;"));
      expect(rh, contains('losVanDeRadio: luistertMee'));
    });

    test('ging de groei nooit open, dan neemt de volgende ronde over, en speelt het gelande nummer', () {
      final m = File('lib/main.dart').readAsStringSync();
      final s = m.substring(m.indexOf('  Future<void> speelNummer(BuildContext context,'));
      expect(s, contains('if (klinkt && opende(elders?.pad)) return;'),
          reason: 'niet op playing: dat blijft na een mislukte opening waar');
      expect(s, contains('bool opende(String? adres) => adres != null && speler.current?.path == adres && speler.duration > Duration.zero;'));
      final landen = s.substring(s.indexOf('final klinkendAdres = vroeg?.adres ?? elders?.pad;'));
      expect(landen, contains('if (klinkendAdres != null && klinkt && opende(klinkendAdres)) {'));
      expect(landen.indexOf('speler.playQueue([t], 0);'), lessThan(landen.indexOf('} else if (magNog()) {')),
          reason: 'nooit geopend: het gelande nummer spelen, niet stil een regel vervangen');
    });

    test('▶ op een toestel: laten klinken zodra de pc het meldt, en na het landen je eigen nummer', () {
      final m = File('lib/main.dart').readAsStringSync();
      final s = m.substring(m.indexOf('  Future<void> speelNummer(BuildContext context,'));
      expect(s, contains('? await bron.haal(plek, zoekBeter: true, klinkt: klinktOpPc)'));
      expect(s, contains('speler.groeitElders(g.pad, g);'));
      expect(s, contains("speler.playUrl(g.pad, title: titel, artist: artiest, album: album ?? '');"));
      expect(s, contains('elders?.geborgen = t.path;'));
      expect(s, contains('speler.wordtLokaal(klinkendAdres, t);'));
    });

    test('de doorgever laat /groei/ door, zonder hem tegen het eerste antwoord te houden', () {
      final d = File('lib/lan/doorgever.dart').readAsStringSync();
      expect(d, contains("final groei = pad.startsWith('/groei/');"));
      expect(d, contains('final eerste = groei ? null : _eerste[wat];'));
      expect(d, contains('if (eerste == null && totaal >= 0 && !groei) {'));
    });

    test('een groei die een toestel speelt, blijft na het landen nog even staan', () {
      final g = File('lib/groeistroom.dart').readAsStringSync();
      expect(g, contains('(toestel != null && nu.difference(toestel) < kToestelGeduld)'));
      final s = File('lib/lan/server.dart').readAsStringSync();
      final groei = s.substring(s.indexOf('  Future<void> _groei(HttpRequest req) async {'));
      expect(groei.substring(0, 900), contains('g.opToestel();'));
    });
  });
}

/// De oude weg (proef uit): alleen [haalVoorRadio].
class _Oud extends DownloadManager {
  _Oud(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged);
  bool gevraagd = false;

  @override
  Future<String?> haalVoorRadio({required String artiest, required String titel, int? seconden, int? jaar}) async {
    gevraagd = true;
    return null;
  }

  @override
  Future<String?> haalEnLaatHoren(
          {required String artiest,
          required String titel,
          int? seconden,
          int? jaar,
          Groei? vroeg,
          bool zoekDaarnaBeter = false,
      bool losVanDeRadio = false,
      String? album}) =>
      fail('met de proef uit de oude weg');
}
