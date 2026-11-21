/// Een radiohaal die het toestel opgeeft, laat de pc ook vallen — en wat een radio binnenhaalt, staat op proef (21-11-2026).
///
/// Een radio op de Shield, live gemeten: de tv gaf een haal na acht minuten op, terwijl de vraag tot dertig minuten in de
/// zoekrem stond. De pc haalde gewoon door: van de 67 nummers die die ochtend voor de radio binnenkwamen, stonden er 51
/// nergens op proef. Ze kwamen nooit in het opruimoverzicht en mengden zich ongemerkt tussen de bibliotheek — en een
/// tweede vraag ernaar kreeg "eigen" terug, als was het je eigen muziek.
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/groeistroom.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pc_radiobron.dart';
import 'package:debridmusic/lan/radiohaler.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radioladder.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Future<void> _totDat(bool Function() klaar) async {
  for (var i = 0; i < 300 && !klaar(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(klaar(), isTrue);
}

/// Een haal die wacht tot de toets hem laat landen, en die zegt of hij gestopt werd.
class _Wacht extends DownloadManager {
  _Wacht(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged);
  final landen = Completer<String?>();
  var gestopt = 0;
  var stopGekregen = false;

  @override
  Future<String?> haalEnLaatHoren(
      {required String artiest,
      required String titel,
      int? seconden,
      int? jaar,
      Groei? vroeg,
      bool zoekDaarnaBeter = false,
      bool losVanDeRadio = false,
      String? album,
      void Function(void Function() stop)? bijStop}) {
    stopGekregen = bijStop != null;
    bijStop?.call(() => gestopt++);
    return landen.future;
  }

  @override
  Future<String?> haalVoorRadio({required String artiest, required String titel, int? seconden, int? jaar}) =>
      fail('met de proef aan de snelle weg');
}

/// Een haal die landt op wat er al is.
class _AlBinnen extends DownloadManager {
  _AlBinnen(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged, this.pad);
  final String pad;

  @override
  Future<String?> haalEnLaatHoren(
      {required String artiest,
      required String titel,
      int? seconden,
      int? jaar,
      Groei? vroeg,
      bool zoekDaarnaBeter = false,
      bool losVanDeRadio = false,
      String? album,
      void Function(void Function() stop)? bijStop}) async {
    throw RadioAlGehad(pad);
  }
}

/// De bibliotheek van de pc, met vaste id's.
class _Lib extends LibraryStore {
  _Lib(this.ids);
  final Map<String, String> ids;

  @override
  String? gedeeldId(String path) => ids[path];
}

/// Een pc die antwoordt wat de toets wil, en onthoudt wat hem gevraagd werd.
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

void main() {
  late Directory map;
  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_loslaten_');
    setAppDirForTest(map.path);
  });
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  AppSettings cfg() => AppSettings()..vroegLuisteren = true;

  group('de pc laat een haal vallen', () {
    test('DE KERN: laatVallen breekt de haal ook in de downloadmanager af — één keer', () async {
      final c = cfg();
      final d = _Wacht(OnlineService(c), SoulseekService(c), map.path, () async {});
      final h = Radiohaler(d, null, _Lib({})..configDirOverride = map.path, c);
      final haal = h.haal(artiest: 'Billie Holiday', titel: 'My Man');
      await _totDat(() => d.stopGekregen);
      expect(h.laatVallen(haal.id), isTrue);
      expect(d.gestopt, 1);
      expect(h.laatVallen(haal.id), isFalse, reason: 'een tweede keer doet niets');
      expect(d.gestopt, 1);
      expect(h.laatVallen('bestaat-niet'), isFalse);
      d.landen.complete(null);
      await _totDat(() => h.stand(haal.id)['stand'] != 'onderweg');
      expect(h.stand(haal.id)['stand'], 'mislukt');
    });

    test('losgelaten en toch geland: op proef (bijWees), en een gewone landing niet', () async {
      final c = cfg();
      final pad = '${map.path}${Platform.pathSeparator}My Man.flac';
      File(pad).writeAsStringSync('x');
      final wees = <String>[];
      final d1 = _Wacht(OnlineService(c), SoulseekService(c), map.path, () async {});
      final h1 = Radiohaler(d1, null, _Lib({pad: 'w1'})..configDirOverride = map.path, c)..bijWees = wees.add;
      final los = h1.haal(artiest: 'Billie Holiday', titel: 'My Man');
      await _totDat(() => d1.stopGekregen);
      h1.laatVallen(los.id);
      d1.landen.complete(pad);
      await _totDat(() => h1.stand(los.id)['stand'] != 'onderweg');
      expect(wees, ['w1'], reason: 'anders staat hij voorgoed ongemerkt in je bibliotheek');

      final d2 = _Wacht(OnlineService(c), SoulseekService(c), map.path, () async {});
      final h2 = Radiohaler(d2, null, _Lib({pad: 'w2'})..configDirOverride = map.path, c)..bijWees = wees.add;
      final gewoon = h2.haal(artiest: 'Billie Holiday', titel: 'My Man');
      await _totDat(() => d2.stopGekregen);
      d2.landen.complete(pad);
      await _totDat(() => h2.stand(gewoon.id)['stand'] != 'onderweg');
      expect(wees, ['w1'], reason: 'een landing waar het toestel nog op wacht, kent de radio al');
    });

    test('DE KERN: wat op proef staat, is bij een tweede vraag "klaar" en niet "eigen"', () async {
      final c = cfg();
      final pad = '${map.path}${Platform.pathSeparator}All Of Me.flac';
      File(pad).writeAsStringSync('x');
      Future<Map<String, dynamic>> stand({required bool opProef}) async {
        final d = _AlBinnen(OnlineService(c), SoulseekService(c), map.path, () async {}, pad);
        final h = Radiohaler(d, null, _Lib({pad: 'p1'})..configDirOverride = map.path, c)
          ..opProef = ((id) => opProef && id == 'p1');
        final haal = h.haal(artiest: 'Frank Sinatra', titel: 'All Of Me');
        await _totDat(() => h.stand(haal.id)['stand'] != 'onderweg');
        return h.stand(haal.id);
      }

      final proef = await stand(opProef: true);
      expect(proef['stand'], 'klaar');
      expect(proef['trackId'], 'p1');
      expect((await stand(opProef: false))['stand'], 'eigen', reason: 'echt van jou blijft van jou');
    });
  });

  group('het toestel zegt het als het opgeeft', () {
    test('DE KERN: na de wachttijd vraagt het de pc de haal te laten vallen', () async {
      final pc = _Pc((v) async => v['op'] == 'haal' ? {'id': 'r9'} : {'stand': 'onderweg'});
      final bron = PcRadiobron(
          library: LibraryStore(),
          clientOf: () => pc,
          peilritme: Duration.zero,
          catalogusRitme: Duration.zero,
          geduld: const Duration(milliseconds: 40));
      expect(await bron.haal(Radioplek(artiest: 'Helen Merrill', titel: 'A Cigarette for Company')), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(pc.vragen.where((v) => v['op'] == 'laatvallen').map((v) => v['id']), ['r9']);
    });
  });

  group('aangesloten', () {
    test('twintig vooruit, en het bijvullen hoort daar gelijk aan te zijn', () {
      expect(kMaxVooruit, 20);
      expect(kBijvulOnder, kMaxVooruit.toDouble());
    });

    test('de server kent "laatvallen" en vertelt de radiohaler wat op proef staat', () {
      final s = _bron('lib/lan/server.dart');
      expect(s, contains("        return _json(req.response, {'ok': radiohaler.laatVallen('\${body['id'] ?? ''}')});"));
      expect(s, contains('    ..opProef = ((id) => state.radioOpProefIds.contains(id))\n    ..bijWees = _radioWees;'));
      final o = _bron('lib/online.dart');
      expect(o, contains('    bijStop?.call(() => laatRadiohaalVallen(job));\n'));
      expect(o, contains('    _radiohalen.remove(job);\n    _log.line('), reason: 'uit de lijst: dan vervalt ook de vraag in de zoekrem');
      expect(_bron('lib/lan/radiohaler.dart'), contains('                bijStop: (s) => haal.stop = s);'));
    });
  });
}
