// Een cd die je vraagt, komt bijna meteen (Saber, 29-10-2026, bij Dangerous: "ik heb net op high res geklikt, hele plaat in
// cd kwaliteit ik zie niets binnen komen ?? … dit moet direct te vinden zijn en er heel snel staan toch ?" en daarna
// "zeker cd kwaliteit moet instant gaan bijna, studio en vinyl dat snap ik maar cd is echt basis"). Gemeten in
// downloads.log: Jam stond op plaats 16 in de rij van de eerste uploader (allthesongs), tot acht minuten wachten, en de
// vijf andere kandidaten en de andere dertien nummers wachtten erachter. Hier: nep-uploaders over een nep-sessie, en de
// echte wedloop van de app ertussen.
import 'dart:async';
import 'dart:io';

import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soortjacht.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/twijfel.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Gedrag { rij, firewall, snel }

/// Uploaders zoals in downloads.log van 29-10-2026: wie ons in zijn rij zet (plaats 16), wie onbereikbaar is, en wie
/// meteen levert (een echte FLAC, zodat de controle na het halen hem heel vindt).
class _NepSessie implements SlskSession {
  _NepSessie(this.gedrag);
  final Map<String, _Gedrag> gedrag;
  final begonnen = <String>[];
  final gestopt = <String>{};
  final toon = File('test/fixtures/tone.flac').readAsBytesSync();

  @override
  String get user => 'u';
  @override
  String get pass => 'p';

  @override
  Future<SlskResult> download(SoulseekFile file, File destFile, void Function(int, int) onProgress,
      {void Function(SlskQueued)? onStatus,
      bool waitInQueue = true,
      Duration maxWait = const Duration(minutes: 30),
      SlskCancel? cancel}) async {
    begonnen.add(file.username);
    bool stop() {
      if (cancel?.isCancelled ?? false) {
        gestopt.add(file.username);
        return true;
      }
      return false;
    }

    switch (gedrag[file.username]!) {
      case _Gedrag.rij:
        onStatus?.call(SlskQueued(16));
        await Future.any([cancel?.whenCancelled ?? Completer<void>().future, Future<void>.delayed(maxWait)]);
        return stop() ? SlskCancelled() : SlskFail('Geweigerd: Queued');
      case _Gedrag.firewall:
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return SlskFail('Uploader niet bereikbaar (firewall)');
      case _Gedrag.snel:
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (stop()) return SlskCancelled();
        onProgress(1, toon.length); // de eerste bytes: wie dit het eerst doet, wint
        if (stop()) return SlskCancelled();
        await destFile.parent.create(recursive: true);
        await destFile.writeAsBytes(toon);
        onProgress(toon.length, toon.length);
        return SlskDone(destFile.path);
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  late Directory map;
  late DownloadManager d;
  late int toonGrootte;

  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_cd_wedloop_');
    setAppDirForTest(map.path);
    toonGrootte = File('test/fixtures/tone.flac').lengthSync();
    d = DownloadManager(
        OnlineService(AppSettings()), SoulseekService(AppSettings()..soulseekUser = 'u'..soulseekPass = 'p'), map.path,
        () async {})
      ..twijfel = Twijfellijst('${map.path}/twijfel.json')
      ..soortvragen = Soortvragen('${map.path}/soortvragen.json');
  });

  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  Soortvraag vraag(String titel) {
    final v = Soortvraag(
        pad: '${map.path}/Albums/Michael Jackson/Dangerous/$titel.flac',
        soort: Kopiesoort.cd,
        artiest: 'Michael Jackson',
        titel: titel,
        album: 'Dangerous',
        seconden: 339,
        sindsMs: 1);
    d.soortvragen!.zet(v);
    return v;
  }

  SoulseekFile f(String wie, String titel) =>
      SoulseekFile(username: wie, filename: '@@$wie\\Dangerous (CD)\\$titel.flac', size: toonGrootte, durationSec: 339);

  _NepSessie sessie(Map<String, _Gedrag> gedrag) {
    final s = _NepSessie(gedrag);
    d.soulseek.sessieVoorToets = s;
    return s;
  }

  test('DE KERN: de eerste in een rij (plaats 16) houdt niets op — wie meteen levert, wint, en de rij stopt', () async {
    final s = sessie({'allthesongs': _Gedrag.rij, 'JFizDaWiz': _Gedrag.firewall, 'DanishBadger': _Gedrag.snel});
    final gekeurd = <String>[];
    d.keurSoortVoorToets = (v, binnen, bron) async {
      gekeurd.add(bron);
      expect(binnen.lengthSync(), toonGrootte, reason: 'het hele bestand, niet een stukje');
      return true;
    };
    final v = vraag('Jam');
    final klok = Stopwatch()..start();
    final klaar = await d
        .cdWedloopVoorToets(v, [f('allthesongs', 'Jam'), f('JFizDaWiz', 'Jam'), f('DanishBadger', 'Jam')])
        .timeout(const Duration(seconds: 20));
    expect(klaar, isTrue);
    expect(klok.elapsed, lessThan(const Duration(seconds: 5)), reason: 'was tot acht minuten per uploader');
    expect(gekeurd, ['Soulseek DanishBadger']);
    expect(s.begonnen.toSet(), {'allthesongs', 'JFizDaWiz', 'DanishBadger'}, reason: 'allemaal samen begonnen');
    expect(s.gestopt, contains('allthesongs'), reason: 'wie in de rij stond, stopt zodra een ander levert');
  });

  test('keurt de keuring de winnaar af, dan een nieuwe wedloop met wie overblijft', () async {
    final s = sessie({'allthesongs': _Gedrag.rij, 'DanishBadger': _Gedrag.snel, 'misterclock': _Gedrag.snel});
    final gekeurd = <String>[];
    d.keurSoortVoorToets = (v, binnen, bron) async {
      gekeurd.add(bron);
      return gekeurd.length == 2; // de eerste winnaar is een nep-cd
    };
    final klaar = await d
        .cdWedloopVoorToets(vraag('Jam'), [f('allthesongs', 'Jam'), f('DanishBadger', 'Jam'), f('misterclock', 'Jam')])
        .timeout(const Duration(seconds: 20));
    expect(klaar, isTrue);
    expect(gekeurd, hasLength(2));
    expect(gekeurd.toSet(), hasLength(2), reason: 'de afgekeurde doet niet opnieuw mee');
    expect(s.begonnen.where((u) => u == 'allthesongs').length, 2, reason: 'wie stopte omdat een ander won, mag weer');
  });

  test('levert niemand, dan geeft hij het snel op (TIDAL, torrents, en later opnieuw)', () async {
    sessie({'a': _Gedrag.firewall, 'b': _Gedrag.firewall});
    var gekeurd = 0;
    d.keurSoortVoorToets = (v, binnen, bron) async => ++gekeurd > 0;
    final klok = Stopwatch()..start();
    expect(await d.cdWedloopVoorToets(vraag('Jam'), [f('a', 'Jam'), f('b', 'Jam')]).timeout(const Duration(seconds: 20)),
        isFalse);
    expect(gekeurd, 0);
    expect(klok.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('nummers zoeken samen, maar de keuring en het bewaren gaan één tegelijk', () async {
    sessie({for (var i = 0; i < 4; i++) 'snel$i': _Gedrag.snel});
    var bezig = 0, hoogst = 0;
    d.keurSoortVoorToets = (v, binnen, bron) async {
      hoogst = ++bezig > hoogst ? bezig : hoogst;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      bezig--;
      return true;
    };
    final titels = ['Jam', 'Why You Wanna Trip On Me', 'In The Closet', 'She Drives Me Wild'];
    final uit = await Future.wait([
      for (var i = 0; i < 4; i++) d.cdWedloopVoorToets(vraag(titels[i]), [f('snel$i', titels[i])]),
    ]).timeout(const Duration(seconds: 20));
    expect(uit, everyElement(isTrue));
    expect(hoogst, 1, reason: 'het bewaren verplaatst bestanden en schrijft lijsten: dat liep altijd na elkaar');
  });

  group('metHoogstens', () {
    test('DE KERN: hoogstens n tegelijk, in volgorde begonnen, en alles gedaan', () async {
      var bezig = 0, hoogst = 0;
      final begonnen = <int>[], klaar = <int>[];
      await metHoogstens(kSoortNummersTegelijk, List.generate(14, (i) => i), (i) async {
        begonnen.add(i);
        hoogst = ++bezig > hoogst ? bezig : hoogst;
        await Future<void>.delayed(Duration(milliseconds: 10 + (i % 3) * 5));
        bezig--;
        klaar.add(i);
      });
      expect(hoogst, kSoortNummersTegelijk);
      expect(begonnen, List.generate(14, (i) => i));
      expect(klaar.toSet(), Set.of(List.generate(14, (i) => i)));
    });

    test('één tegelijk is na elkaar; een lege rij doet niets', () async {
      var bezig = 0, hoogst = 0;
      await metHoogstens(1, [1, 2, 3], (_) async {
        hoogst = ++bezig > hoogst ? bezig : hoogst;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bezig--;
      });
      expect(hoogst, 1);
      await metHoogstens(4, const <int>[], (_) async => fail('niets te doen'));
    });

    test('een fout stopt de rest niet, en komt daarna terug', () async {
      final klaar = <int>[];
      await expectLater(
          metHoogstens(2, [1, 2, 3, 4, 5], (i) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            if (i == 2) throw StateError('nummer 2');
            klaar.add(i);
          }),
          throwsA(isA<StateError>()));
      expect(klaar, containsAll([1, 3, 4, 5]));
    });
  });

  test('aangesloten: wat je vraagt zoekt voor en samen; een cd via de wedloop, studio en vinyl de beste eerst', () {
    final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(online, contains('unawaited(_soortRonde(nieuw, album: nieuw.length > 1 ? album : null, gevraagd: true));'));
    expect(online, contains('unawaited(_soortRonde([v], gevraagd: true));'), reason: 'Weg… zoekt meteen de volgende');
    final ronde = online.substring(online.indexOf('  Future<void> _soortRonde('));
    final lijf = ronde.substring(0, ronde.indexOf('\n  }\n'));
    expect(RegExp(r'achtergrond: !gevraagd').allMatches(lijf).length, 2, reason: 'plaat en nummer: voor bij de zoekrem');
    expect(lijf, contains('await metHoogstens(gevraagd ? kSoortNummersTegelijk : 1, open, (v) async {'));
    expect(lijf, contains('klaar = v.soort == Kopiesoort.cd ? await _cdWedloop(v, kandidaten) : await _soortVanSoulseek(v, kandidaten);'));
    expect(online, contains('.take(v.soort == Kopiesoort.cd ? kCdKandidaten : kSoortKandidaten)'));
    expect(kCdKandidaten, greaterThan(kSoortKandidaten));
    final wedloop = online.substring(online.indexOf('  Future<bool> _cdWedloop('));
    expect(wedloop.substring(0, wedloop.indexOf('\n  }\n')),
        contains("kop: '\"\${v.artiest} — \${v.titel}\": cd-wedloop',"));
  });
}
