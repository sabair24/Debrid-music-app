// De TIDAL-ronde over de hele bibliotheek (Saber, 24-10-2026: "als er een beter versie kwaliteit te vinden is op
// tidal, moet de app deze gebruiken" — hij koos de hele bibliotheek). Gemeten op TIDAL voor "Roy Orbison You Got It":
// het origineel (Mystery Girl, 29347905, 210 s) alleen LOSSLESS; 78580436 (A Love So Beautiful, met het Royal
// Philharmonic, 216 s) LOSSLESS+HIRES_LOSSLESS — een andere opname.
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/tidal.dart';
import 'package:debridmusic/tidal_beter.dart';
import 'package:flutter_test/flutter_test.dart';

Track _nr(String pad,
        {String artiest = 'Roy Orbison',
        String titel = 'You Got It',
        int sec = 210,
        int bits = 16,
        int hz = 44100,
        int erbij = 0}) =>
    Track(
        path: pad,
        title: titel,
        artist: artiest,
        album: 'Mystery Girl',
        duration: sec > 0 ? Duration(seconds: sec) : null,
        isFlac: pad.endsWith('.flac'),
        bitsPerSample: bits,
        sampleRate: hz,
        addedMs: erbij);

String _regel(String id, String artiest, String titel, int sec, List<String> tags,
        {String album = '', bool stereo = true, String soort = 'track'}) =>
    jsonEncode({
      'soort': soort,
      'id': id,
      'artiest': artiest,
      'titel': titel,
      'seconden': sec,
      'album': album,
      'stereo': stereo,
      'tags': tags,
    });

final _youGotIt = [
  _regel('29347905', 'Roy Orbison', 'You Got It', 210, ['LOSSLESS'], album: 'Mystery Girl'),
  _regel('78580436', 'Roy Orbison', 'You Got It', 216, ['LOSSLESS', 'HIRES_LOSSLESS'],
      album: 'A Love So Beautiful: Roy Orbison & The Royal Philharmonic Orchestra'),
  _regel('3392923', 'New Kids On The Block', 'You Got It (The Right Stuff)', 251, ['LOSSLESS']),
].join('\n');

void main() {
  group('wat TIDAL minstens moet hebben', () {
    test('een mp3 wint al bij cd-kwaliteit', () {
      expect(tidalMinstens(_nr('a/You Got It.mp3', bits: 0)), TidalMinstens.cd);
    });
    test('een FLAC van 16 bit, of zonder gekende diepte, alleen bij hi-res', () {
      expect(tidalMinstens(_nr('a/You Got It.flac')), TidalMinstens.hires);
      expect(tidalMinstens(_nr('a/You Got It.flac', bits: 0)), TidalMinstens.hires);
    });
    test('een verdachte FLAC (muur in het spectrum) wint al bij cd-kwaliteit', () {
      expect(tidalMinstens(_nr('a/You Got It.flac'), verdacht: true), TidalMinstens.cd);
    });
    test('24 bit: niets te winnen', () {
      expect(tidalMinstens(_nr('a/You Got It.flac', bits: 24, hz: 96000)), TidalMinstens.geenWinst);
    });
  });

  test('de uitvoer van het zoekhulpje: alleen nummers, alleen stereo, elk id één keer', () {
    final n = tidalStereoNummers([
      _regel('1', 'A', 'X', 200, ['LOSSLESS']),
      _regel('2', 'A', 'X', 200, ['HIRES_LOSSLESS'], stereo: false),
      _regel('3', 'A', 'Plaat', 0, ['HIRES_LOSSLESS'], soort: 'album'),
      _regel('1', 'A', 'X', 200, ['LOSSLESS']),
      'geen json',
    ].join('\r\n'));
    expect([for (final x in n) x.id], ['1']);
    expect(n.single.seconden, 200);
    expect(n.single.kwaliteit, TidalKwaliteit.cd);
  });

  group('het nummer op TIDAL dat dezelfde opname is en beter klinkt', () {
    final treffers = tidalStereoNummers(_youGotIt);

    test('You Got It in 16/44,1: niets — het origineel is daar ook cd, de hi-res is de orkestversie', () {
      final t = _nr('a/You Got It.flac');
      expect(beterOpTidal(t, treffers, minstens: tidalMinstens(t)), isNull);
    });

    test('You Got It als mp3: het origineel in cd-kwaliteit', () {
      final t = _nr('a/You Got It.mp3', bits: 0);
      expect(beterOpTidal(t, treffers, minstens: tidalMinstens(t))?.id, '29347905');
    });

    test('een hi-res remaster van dezelfde lengte wel; neutrale haakjes en gasten tellen niet', () {
      final lijst = tidalStereoNummers([
        _regel('10', 'Roy Orbison', 'You Got It (2015 Remaster)', 211, ['LOSSLESS', 'HIRES_LOSSLESS']),
        ..._youGotIt.split('\n'),
      ].join('\n'));
      final t = _nr('a/You Got It.flac');
      expect(beterOpTidal(t, lijst, minstens: TidalMinstens.hires)?.id, '10');
      final gast = _nr('a/Song.flac', artiest: 'Adele', titel: 'Song (feat. X)', sec: 180);
      final metGast = tidalStereoNummers(_regel('11', 'Adele', 'Song', 180, ['HIRES_LOSSLESS']));
      expect(beterOpTidal(gast, metGast, minstens: TidalMinstens.hires)?.id, '11');
    });

    test('een andere versie, een andere artiest of een te grote lengteafwijking niet', () {
      final t = _nr('a/You Got It.flac');
      final lijst = tidalStereoNummers([
        _regel('20', 'Roy Orbison', 'You Got It (Live)', 210, ['HIRES_LOSSLESS']),
        _regel('21', 'John Stephan', 'You Got It', 210, ['HIRES_LOSSLESS']),
        _regel('22', 'Roy Orbison', 'You Got It', 213, ['HIRES_LOSSLESS']),
        _regel('23', 'Roy Orbison', 'You Got It', 0, ['HIRES_LOSSLESS']),
      ].join('\n'));
      expect(beterOpTidal(t, lijst, minstens: TidalMinstens.hires), isNull);
    });

    test('tot 6 s alleen van hetzelfde album: Africa (Toto IV, 295 tegen 301 s) wel, de orkestversie (ander album) niet',
        () {
      final africa = _nr('a/10 - Africa.flac', artiest: 'Toto', titel: 'Africa', sec: 301);
      final toto = Track(
          path: africa.path,
          title: 'Africa',
          artist: 'Toto',
          album: 'Toto IV',
          duration: const Duration(seconds: 301),
          isFlac: true,
          bitsPerSample: 16,
          sampleRate: 44100);
      final lijst = tidalStereoNummers([
        _regel('40', 'TOTO', 'Africa', 295, ['LOSSLESS', 'HIRES_LOSSLESS'], album: 'Toto IV'),
      ].join('\n'));
      expect(beterOpTidal(toto, lijst, minstens: TidalMinstens.hires)?.id, '40');
      expect(beterOpTidal(africa, lijst, minstens: TidalMinstens.hires), isNull, reason: 'Mystery Girl is een ander album');
      final orkest = _nr('a/You Got It.flac', sec: 216 - 6);
      expect(beterOpTidal(orkest, tidalStereoNummers(_youGotIt), minstens: TidalMinstens.hires), isNull,
          reason: '216 tegen 210 s, maar op A Love So Beautiful');
      final zonderAlbum = tidalStereoNummers(_regel('41', 'TOTO', 'Africa', 295, ['HIRES_LOSSLESS']));
      expect(beterOpTidal(toto, zonderAlbum, minstens: TidalMinstens.hires), isNull,
          reason: 'zegt TIDAL het album niet, dan 2 s');
      final teVer = tidalStereoNummers(_regel('42', 'TOTO', 'Africa', 294, ['HIRES_LOSSLESS'], album: 'Toto IV'));
      expect(beterOpTidal(toto, teVer, minstens: TidalMinstens.hires), isNull, reason: '7 s');
    });

    test('hi-res gaat voor cd, en een afgewezen id komt niet terug', () {
      final t = _nr('a/You Got It.mp3', bits: 0);
      final lijst = tidalStereoNummers([
        _regel('30', 'Roy Orbison', 'You Got It', 210, ['LOSSLESS']),
        _regel('31', 'Roy Orbison', 'You Got It', 211, ['LOSSLESS', 'HIRES_LOSSLESS']),
      ].join('\n'));
      expect(beterOpTidal(t, lijst, minstens: TidalMinstens.cd)?.id, '31');
      expect(beterOpTidal(t, lijst, minstens: TidalMinstens.cd, nee: ['31'])?.id, '30');
    });

    test('zonder gekende lengte van je eigen bestand: niets (dezelfde opname is niet na te gaan)', () {
      final t = _nr('a/You Got It.mp3', bits: 0, sec: 0);
      expect(beterOpTidal(t, treffers, minstens: TidalMinstens.cd), isNull);
    });
  });

  group('de volgorde van de ronde', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_tidal_beter_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('eerst wat cd al beter maakt, dan 16 bit; binnen elk het nieuwste eerst; 24 bit en vaste keuze niet', () {
      final g = TidalBeterGeheugen('${map.path}/tidal_beter.json');
      final oudeFlac = _nr('a/1.flac', erbij: 1);
      final nieuweFlac = _nr('a/2.flac', erbij: 5);
      final mp3 = _nr('a/3.mp3', bits: 0, erbij: 2);
      final hoog = _nr('a/4.flac', bits: 24, erbij: 9);
      final vast = _nr('a/5.mp3', bits: 0, erbij: 9);
      final alle = [oudeFlac, nieuweFlac, mp3, hoog, vast];
      Track? volgende() => volgendeVoorTidal(alle, g,
          nuMs: 1000, minstens: (t) => tidalMinstens(t), overslaan: (t) => t.path == vast.path);
      expect(volgende()?.path, mp3.path);
      g.zet(mp3.path, TidalBeterUitslag.geen, 1000);
      expect(volgende()?.path, nieuweFlac.path);
      g.zet(nieuweFlac.path, TidalBeterUitslag.geen, 1000);
      expect(volgende()?.path, oudeFlac.path);
      g.zet(oudeFlac.path, TidalBeterUitslag.geen, 1000);
      expect(volgende(), isNull);
    });

    test('opnieuw: mislukt na een dag, de rest na zestig dagen', () {
      final g = TidalBeterGeheugen('${map.path}/tidal_beter.json');
      const dag = 24 * 3600 * 1000;
      g.zet('a/1.flac', TidalBeterUitslag.mislukt, 0);
      g.zet('a/2.flac', TidalBeterUitslag.geen, 0);
      expect(g.aanDeBeurt('a/1.flac', dag - 1), isFalse);
      expect(g.aanDeBeurt('a/1.flac', dag), isTrue);
      expect(g.aanDeBeurt('a/2.flac', 59 * dag), isFalse);
      expect(g.aanDeBeurt('a/2.flac', kTidalBeterOpnieuwDagen * dag), isTrue);
      expect(g.aanDeBeurt(r'A\2.FLAC', 59 * dag), isFalse, reason: 'een pad met andere schuine strepen of hoofdletters');
    });

    test('het geheugen overleeft een herstart, met de afgewezen ids', () async {
      final pad = '${map.path}/tidal_beter.json';
      final g = TidalBeterGeheugen(pad)
        ..zet('a/1.flac', TidalBeterUitslag.afgewezen, 5, afgewezenId: '78580436')
        ..zet('a/1.flac', TidalBeterUitslag.afgewezen, 6, afgewezenId: '10')
        ..zet('a/2.mp3', TidalBeterUitslag.vervangen, 7);
      await g.bewaar();
      final h = TidalBeterGeheugen(pad);
      await h.laad();
      expect(h.aantal, 2);
      expect(h.van('a/1.flac')?.nee, ['78580436', '10']);
      expect(h.van('a/1.flac')?.ms, 6);
      expect(h.van('a/2.mp3')?.uit, TidalBeterUitslag.vervangen);
    });
  });

  group('de ronde zelf', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_tidal_beter_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('You Got It: zoekt, haalt niets, onthoudt "geen"', () async {
      final regels = <String>[];
      final gehaald = <String>[];
      final vragen = <String>[];
      final r = TidalBeterRonde(
        geheugen: TidalBeterGeheugen('${map.path}/g.json'),
        nummers: () => [_nr('a/You Got It.flac')],
        zoek: (v) async {
          vragen.add(v);
          return _youGotIt;
        },
        haal: (t, k) async {
          gehaald.add(k.id);
          return TidalBeterUitslag.vervangen;
        },
        overslaan: (_) => false,
        log: regels.add,
        klok: () => DateTime(2026, 10, 24, 15),
      );
      expect(await r.stap(), TidalBeterUitslag.geen);
      expect(vragen, ['Roy Orbison You Got It']);
      expect(gehaald, isEmpty);
      expect(regels.single, contains('niets beters van deze opname'));
      expect(regels.single, contains('FLAC 16/44,1'));
      expect(await r.stap(), isNull, reason: 'onthouden: niet meteen opnieuw');
    });

    test('een afgewezen kopie wordt niet opnieuw gehaald, de volgende wel', () async {
      var nu = DateTime(2026, 10, 24, 15);
      final gehaald = <String>[];
      final uitvoer = [
        _regel('40', 'Roy Orbison', 'You Got It', 210, ['HIRES_LOSSLESS']),
        _regel('41', 'Roy Orbison', 'You Got It', 211, ['HIRES_LOSSLESS']),
      ].join('\n');
      final r = TidalBeterRonde(
        geheugen: TidalBeterGeheugen('${map.path}/g.json'),
        nummers: () => [_nr('a/You Got It.flac')],
        zoek: (_) async => uitvoer,
        haal: (t, k) async {
          gehaald.add(k.id);
          return TidalBeterUitslag.afgewezen;
        },
        overslaan: (_) => false,
        klok: () => nu,
      );
      expect(await r.stap(), TidalBeterUitslag.afgewezen);
      nu = nu.add(const Duration(days: kTidalBeterOpnieuwDagen));
      expect(await r.stap(), TidalBeterUitslag.afgewezen);
      expect(gehaald, ['40', '41']);
    });

    test('tidaler antwoordt niet: een uur rust, daarna opnieuw', () async {
      var nu = DateTime(2026, 10, 24, 15);
      var zoeken = 0;
      final r = TidalBeterRonde(
        geheugen: TidalBeterGeheugen('${map.path}/g.json'),
        nummers: () => [_nr('a/1.mp3', bits: 0), _nr('a/2.mp3', bits: 0, titel: 'Crying')],
        zoek: (_) async {
          zoeken++;
          return null;
        },
        haal: (t, k) async => TidalBeterUitslag.vervangen,
        overslaan: (_) => false,
        klok: () => nu,
      );
      expect(await r.stap(), TidalBeterUitslag.mislukt);
      nu = nu.add(const Duration(minutes: 30));
      expect(await r.stap(), isNull);
      expect(zoeken, 1);
      nu = nu.add(const Duration(minutes: 31));
      expect(await r.stap(), TidalBeterUitslag.mislukt);
      expect(zoeken, 2);
    });

    test('op jouw vraag ("Zoek hi-res", 👍): meteen, ook als de ronde hem net bekeek; 24 bit en vaste keuze niet',
        () async {
      final bekeken = <String>[];
      final g = TidalBeterGeheugen('${map.path}/g.json')..zet('a/1.flac', TidalBeterUitslag.geen, 1000);
      final r = TidalBeterRonde(
        geheugen: g,
        nummers: () => const [],
        zoek: (v) async {
          bekeken.add(v);
          return '';
        },
        haal: (t, k) async => TidalBeterUitslag.vervangen,
        overslaan: (t) => t.path == 'a/vast.mp3',
        klok: () => DateTime(2026, 10, 24, 15),
      );
      final gevraagd = r.nu([
        _nr('a/1.flac', titel: 'Een'),
        _nr('a/2.mp3', bits: 0, titel: 'Twee'),
        _nr('a/hoog.flac', bits: 24),
        _nr('a/vast.mp3', bits: 0),
        _nr('a/geenlengte.mp3', bits: 0, sec: 0),
      ]);
      expect(gevraagd, {'a/1.flac', 'a/2.mp3'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bekeken, ['Roy Orbison Een', 'Roy Orbison Twee'], reason: 'één voor één, in de gevraagde volgorde');
      expect(r.nu([_nr('a/hoog.flac', bits: 24)]), isEmpty);
    });

    test('op jouw vraag: wat nu speelt komt als laatste, als het niet meer speelt', () async {
      final bekeken = <String>[];
      var speelt = 'a/1.flac';
      final r = TidalBeterRonde(
        geheugen: TidalBeterGeheugen('${map.path}/g.json'),
        nummers: () => const [],
        zoek: (v) async {
          bekeken.add(v);
          return '';
        },
        haal: (t, k) async => TidalBeterUitslag.vervangen,
        overslaan: (_) => false,
        klok: () => DateTime(2026, 10, 24, 15),
      )
        ..speeltNu = ((p) => p == speelt)
        ..wachtNaSpelen = const Duration(milliseconds: 10);
      r.nu([_nr('a/1.flac', titel: 'Een'), _nr('a/2.flac', titel: 'Twee')]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bekeken, ['Roy Orbison Twee'], reason: 'Een speelt nog: wacht');
      speelt = '';
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bekeken, ['Roy Orbison Twee', 'Roy Orbison Een']);
    });

    test('"Zoek hi-res" vraagt TIDAL vóór het kijkt of Soulseek er is', () {
      final bron = File('lib/online.dart').readAsStringSync();
      final begin = bron.indexOf('  Future<int> zoekBeterVoor(');
      final tidal = bron.indexOf('tidalNu?.call(te)', begin);
      final soulseek = bron.indexOf('if (!soulseek.available)', begin);
      expect(begin, greaterThan(0));
      expect(tidal, greaterThan(begin));
      expect(tidal, lessThan(soulseek), reason: 'zonder Soulseek moet TIDAL nog steeds nakijken');
      expect(File('lib/main.dart').readAsStringSync(), contains('downloads.tidalNu = tidalBeter.nu;'));
    });

    test('wat speelt of in de wachtrij staat, slaat hij over', () async {
      final r = TidalBeterRonde(
        geheugen: TidalBeterGeheugen('${map.path}/g.json'),
        nummers: () => [_nr(r'C:\Muziek\a.mp3', bits: 0)],
        zoek: (_) async => '',
        haal: (t, k) async => TidalBeterUitslag.vervangen,
        overslaan: (_) => false,
        inGebruik: () => ['c:/muziek/A.mp3'],
        klok: () => DateTime(2026, 10, 24, 15),
      );
      expect(await r.stap(), isNull);
    });
  });
}
