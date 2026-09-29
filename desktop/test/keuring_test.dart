/// De keuring: alleen wat bewezen beter is komt erin, en wat kapot is nooit.
///
/// Elk geval hieronder is op 29-09-2026 aan Sabers eigen bibliotheek gemeten, na zijn melding bij Blood
/// On The Dance Floor: *"als er een slechtere binnenkomt dan wat ik heb moet die weg, en moet mijn
/// betere kwaliteit die ik al had blijven."* Van de 95 bestanden in `_dubbel` hadden er 47 een opvolger
/// met lagere getallen op de badge; een deel terecht, het grootste deel niet.
///
/// De foutregels van ffmpeg zijn letterlijk overgenomen van de bestanden die op 14-09-2026 bij het
/// volledig decoderen van alle 1404 bestanden als kapot — of als vals alarm — uit de bus kwamen.
library;

import 'dart:io';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/ffmpeg.dart';
import 'package:debridmusic/integriteit.dart';
import 'package:debridmusic/keuring.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

const _leeg = Echtheidsoordeel(
    bits: Bitdiepte.spreektNietTegen, boven: Bovenband.leeg, band: Bandbreedte.doorlopend);
const _vol = Echtheidsoordeel(
    bits: Bitdiepte.spreektNietTegen, boven: Bovenband.vol, band: Bandbreedte.doorlopend);
const _muur = Echtheidsoordeel(
    bits: Bitdiepte.spreektNietTegen, boven: Bovenband.onbekend, band: Bandbreedte.afgekapt, afkapHz: 16900);
const _schoon = Echtheidsoordeel(
    bits: Bitdiepte.spreektNietTegen, boven: Bovenband.onbekend, band: Bandbreedte.doorlopend);

Kwaliteit _flac(int rate, [Echtheidsoordeel? o]) =>
    kwaliteitUit(verliesvrij: true, kopRate: rate, formaat: 4, oordeel: o);

void main() {
  group('Blood On The Dance Floor, zoals het op 29-09-2026 lag', () {
    test('DE KERN: Is It Scary — een eerlijke 24/48 duwt een opgeschaalde 24/96 niet weg', () {
      // Oud: 24/96, boven 22 kHz leeg (opgeschaald). Nieuw: 24/48, niets te bewijzen boven de cd.
      expect(vergelijkKwaliteit(_flac(48000), _flac(96000, _leeg)), 0,
          reason: 'gelijk — en dan blijft wat er stond');
    });

    test('Stranger In Moscow — een 24/44,1 tegen een opgeschaalde 24/96: gelijk', () {
      expect(vergelijkKwaliteit(_flac(44100, _schoon), _flac(96000, _leeg)), 0);
    });

    test('Earth Song — een ongemeten WavPack 24/96 bewijst niets tegen een FLAC', () {
      final wv = kwaliteitUit(verliesvrij: true, kopRate: 96000, formaat: 4);
      expect(wv.klasse, Klasse.onbewezenHires);
      expect(vergelijkKwaliteit(wv, _flac(96000, _leeg)), 0);
      expect(vergelijkKwaliteit(_flac(96000, _leeg), wv), 0, reason: 'en andersom evenmin');
    });
  });

  group('de terechte vervangingen blijven terecht', () {
    test('Material Girl — een GEMETEN echte 24/96 wint van een opgeschaalde 24/192', () {
      expect(vergelijkKwaliteit(_flac(96000, _vol), _flac(192000, _leeg)), greaterThan(0));
    });

    test('7 Years — een echte cd wint van een 24/48 die uit een mp3 kwam', () {
      expect(vergelijkKwaliteit(_flac(44100, _schoon), _flac(48000, _muur)), greaterThan(0));
    });

    test('tussen twee bewezen hi-res wint de hoogste bewezen bemonstering', () {
      expect(vergelijkKwaliteit(_flac(192000, _vol), _flac(96000, _vol)), greaterThan(0));
    });

    test('een verliesvrij bestand wint van een mp3, ook ongemeten', () {
      final mp3 = kwaliteitUit(verliesvrij: false, kopRate: 44100, formaat: 1);
      expect(vergelijkKwaliteit(_flac(44100), mp3), greaterThan(0));
      expect(vergelijkKwaliteit(kwaliteitUit(verliesvrij: true, kopRate: 96000, formaat: 4), mp3),
          greaterThan(0), reason: 'een ongemeten hi-res-claim is wél beter dan lossy');
    });
  });

  group('wat kapot is, verliest altijd', () {
    test('een heel mp3 wint van een kapotte FLAC', () {
      final kapot = kwaliteitUit(verliesvrij: true, kopRate: 96000, formaat: 4, oordeel: _vol, kapot: true);
      final mp3 = kwaliteitUit(verliesvrij: false, kopRate: 44100, formaat: 1);
      expect(kapot.klasse, Klasse.kapot);
      expect(vergelijkKwaliteit(mp3, kapot), greaterThan(0));
    });
  });

  group('het formaat telt alleen bij gelijke klasse, en alleen als het een echt verschil is', () {
    test('FLAC boven WAV — een WAV kan deze app niet taggen', () {
      final wav = kwaliteitUit(verliesvrij: true, kopRate: 44100, formaat: 3);
      expect(vergelijkKwaliteit(_flac(44100), wav), greaterThan(0));
    });

    test('WavPack en FLAC zijn gelijk: geen van beide duwt de ander weg', () {
      final wv = kwaliteitUit(verliesvrij: true, kopRate: 44100, formaat: 4);
      expect(vergelijkKwaliteit(wv, _flac(44100)), 0);
    });
  });

  group('heel of kapot — de decodeerproef', () {
    // Letterlijk wat ffmpeg die dag zei (het adres na de @ weggelaten).
    const sonOfAGun = [
      '[flac @ X] [error] invalid sync code',
      '[flac @ X] [error] invalid frame header',
      '[flac @ X] [error] decode_frame() failed',
      '[aist#0:0/flac @ X] [dec:flac @ X] [error] Decoding error: Invalid data found when processing input',
    ];

    test('DE VAL: Son Of A Gun — een ID3-tag achteraan is geen schade', () {
      // Vier foutregels, en toch heel: de decodering haalt de volle 356,3 s. Op 14-09-2026 gaf dit soort
      // gemopper 25 valse alarmen op 1404 bestanden.
      final h = beoordeelDecode(exitCode: 0, foutregels: sonOfAGun, kopSeconden: 356.3, gedecodeerdSeconden: 356.3);
      expect(h.heel, isTrue);
    });

    test('DE KERN: Just Dance — afgekapt, en dat zie je alleen door te decoderen', () {
      final h = beoordeelDecode(exitCode: 0, foutregels: const [
        '[flac @ X] [error] invalid residual',
        '[flac @ X] [error] decode_frame() failed',
        '[aist#0:0/flac @ X] [dec:flac @ X] [error] Decoding error: Invalid data found when processing input',
      ], kopSeconden: 242.8, gedecodeerdSeconden: 192.9);
      expect(h.heel, isFalse);
      expect(h.reden, contains('192.9'));
    });

    test('Sommeil — speelt 0,1 van 218,7 s, ook zonder één foutregel', () {
      final h = beoordeelDecode(exitCode: 0, foutregels: const [], kopSeconden: 218.7, gedecodeerdSeconden: 0.1);
      expect(h.heel, isFalse);
    });

    test('Give Me Some Love — volle lengte, maar 22 stukken niet te decoderen: rot in het midden', () {
      final h = beoordeelDecode(exitCode: 0, foutregels: [
        for (var i = 0; i < 22; i++)
          '[aist#0:0/flac @ X] [dec:flac @ X] [error] Decoding error: Invalid data found when processing input',
        for (var i = 0; i < 15; i++) '[flac @ X] [error] decode_frame() failed',
      ], kopSeconden: 217.0, gedecodeerdSeconden: 217.0);
      expect(h.heel, isFalse);
    });

    test('schade IN een frame is kapot, ook bij één enkele regel', () {
      final h = beoordeelDecode(exitCode: 0, foutregels: const ['[flac @ X] [error] invalid residual'],
          kopSeconden: 200, gedecodeerdSeconden: 200);
      expect(h.heel, isFalse);
    });

    test('Perfect — niet eens te openen', () {
      final h = beoordeelDecode(exitCode: 1, foutregels: const [
        '[in#0 @ X] [error] Error opening input: Invalid data found when processing input',
      ]);
      expect(h.heel, isFalse);
      expect(h.reden, 'niet te openen');
    });

    test('DE GRENS: een laatste frame dat een fractie korter uitvalt is geen afkap', () {
      final h = beoordeelDecode(exitCode: 0, foutregels: const [], kopSeconden: 336.17, gedecodeerdSeconden: 336.1);
      expect(h.heel, isTrue);
    });

    test('zonder bekende koplengte (een mp3) telt de lengte niet', () {
      final h = beoordeelDecode(exitCode: 0, foutregels: const [], gedecodeerdSeconden: 12);
      expect(h.heel, isTrue);
    });
  });

  group('op schijf, met ffmpeg', () {
    late Directory map;
    final ffmpeg = Ffmpeg().pad;
    // **Aan het eind alles nog eens wissen, tot het weg blijft.** De decodeerproef bewaart zijn uitslagen
    // zonder erop te wachten (`integriteit.json`), en die late schrijfbeurt houdt de map open of zet hem
    // terug: gemeten op 29-09-2026 bleven er zo 170 mappen in %TEMP% achter na een dag toetsen. Niet per
    // toets wachten — dat verschoof ooit de timing van een poorttoets —, maar één keer aan het eind.
    final teWissen = <Directory>[];
    tearDownAll(() async {
      for (var ronde = 0; ronde < 30 && teWissen.any((d) => d.existsSync()); ronde++) {
        for (final d in teWissen) {
          try {
            if (d.existsSync()) d.deleteSync(recursive: true);
          } catch (_) {/* nog in gebruik; volgende ronde */}
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_keuring_');
      teWissen.add(map);
      setAppDirForTest(map.path);
      resetIntegriteitVoorTest();
    });
    tearDown(() {
      resetIntegriteitVoorTest();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<File> maakFlac(String naam, int seconden) async {
      final f = File('${map.path}${Platform.pathSeparator}$naam');
      final r = await Process.run(ffmpeg!, [
        '-nostdin', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=$seconden:sample_rate=44100',
        '-c:a', 'flac', f.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return f;
    }

    test('DE KERN: een afgekapte FLAC wordt herkend, een hele niet', () async {
      final heel = await maakFlac('heel.flac', 20);
      final afgekapt = await maakFlac('afgekapt.flac', 20);
      final bytes = afgekapt.readAsBytesSync();
      afgekapt.writeAsBytesSync(bytes.sublist(0, bytes.length * 4 ~/ 10));

      expect((await controleerHeel(heel.path))!.heel, isTrue);
      final k = await controleerHeel(afgekapt.path);
      expect(k!.heel, isFalse, reason: 'de kop belooft 20 s, er staat 8');
      expect(bekendKapot(afgekapt.path), isTrue);
      expect(bekendKapot(heel.path), isFalse);
    }, skip: ffmpeg == null ? 'geen ffmpeg op deze machine' : false);

    test('de uitslag verhuist mee met het bestand', () async {
      final a = await maakFlac('a.flac', 5);
      final bytes = a.readAsBytesSync();
      a.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 3));
      await controleerHeel(a.path);
      final b = await a.rename('${map.path}${Platform.pathSeparator}b.flac');
      herNoemIntegriteit(a.path, b.path);
      expect(bekendKapot(b.path), isTrue);
    }, skip: ffmpeg == null ? 'geen ffmpeg op deze machine' : false);

    test('DE KERN: een kapotte Soulseek-overdracht wordt een mislukte poging', () async {
      // Dit is de doorgang waar élke Soulseek-download langskomt (`_cleanStaging`). Een mislukte
      // poging laat de race de volgende peer proberen, en het kapotte bestand ruimt diezelfde doorgang op.
      final f = await maakFlac('binnen.flac', 10);
      final bytes = f.readAsBytesSync();
      f.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      final regels = <String>[];
      final uit = await DownloadManager.keurOverdracht(SlskDone(f.path), spoor: regels.add);
      expect(uit, isA<SlskFail>());
      expect((uit as SlskFail).reason, contains('kapot'));
      expect(regels.single, contains('kapot binnengekomen'));

      final heel = await maakFlac('heel.flac', 10);
      expect(await DownloadManager.keurOverdracht(SlskDone(heel.path)), isA<SlskDone>());
      final mislukt = SlskFail('peer offline');
      expect(await DownloadManager.keurOverdracht(mislukt), same(mislukt), reason: 'wat al mislukte, blijft zo');
    }, skip: ffmpeg == null ? 'geen ffmpeg op deze machine' : false);

    test('DE KERN: wat al in je bibliotheek stond wordt nooit gewist, alleen opzij gezet', () async {
      // Op de gewone Soulseek-weg gaf de plaatsing geen parkeermap mee als de bibliotheek het nummer niet
      // herkende maar er wél een bestand op de doelplek lag — en dan werd dát gewist.
      final root = Directory('${map.path}${Platform.pathSeparator}muziek')..createSync();
      const tags = TrackTags(
          title: 'Is It Scary', artist: 'Michael Jackson', album: 'Blood On The Dance Floor', trackNo: 5, trackTotal: 13);
      final doel = File('${root.path}${Platform.pathSeparator}${relativePathFor(tags, ext: '.flac')}');
      doel.parent.createSync(recursive: true);
      final oud = await maakFlac('oud.flac', 10);
      final bytes = oud.readAsBytesSync();
      doel.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2)); // kapot: dan wint de nieuwe
      await controleerHeel(doel.path);
      final nieuw = await maakFlac('nieuw.flac', 10);
      await controleerHeel(nieuw.path);

      final uit = await placeFileDetailed(nieuw, root.path, tags: tags);
      expect(uit.how, Placement.moved);
      final dubbel = Directory('${root.path}${Platform.pathSeparator}$parkeerMap');
      expect(dubbel.existsSync(), isTrue, reason: 'de oude hoort opzij te staan, niet weg');
      expect(dubbel.listSync().whereType<File>(), hasLength(1));
    }, skip: ffmpeg == null ? 'geen ffmpeg op deze machine' : false);

    test('DE KERN: een kapotte kopie van jou verliest van een hele binnenkomer', () async {
      final kapot = await maakFlac('oud.flac', 10);
      final bytes = kapot.readAsBytesSync();
      kapot.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      final nieuw = await maakFlac('nieuw.flac', 10);
      await controleerHeel(kapot.path);
      await controleerHeel(nieuw.path);
      expect(firstIsBetter(nieuw, kapot), isTrue);
      expect(firstIsBetter(kapot, nieuw), isFalse);
    }, skip: ffmpeg == null ? 'geen ffmpeg op deze machine' : false);
  });
}
