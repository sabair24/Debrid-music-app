/// Automatisch kiezen = de uitvoering met de officiële lengte, en nooit een live-opname die er toevallig
/// dicht bij zit.
///
/// Saber op 30-09-2026, bij Sam Smith — I'm Not The Only One: *"ik merk dat er regelmatig eens een live
/// versie of verkeerde liedje binnenkomt … dit nummer moet 3:59 zijn en deze is 3:54. De app moet leren
/// om het nummer te downloaden het meest dichte met de officiele tijd … enkel als ik kies natuurlijk is
/// het mijn fout of bedoeling."*
///
/// Gemeten die dag: in de bibliotheek stond een 24/48 van 234,8 s, met in zijn tags de URL van Qobuz'
/// album *Gloria* en DISC=2 — de live-opname uit de Royal Albert Hall. De peers boden ook 3:59 (24/96 en
/// 24/44,1), 3:43 en 3:40. Waarschijnlijke weg: "Ontbrekende downloaden" vond geen leverende peer, dus
/// werd het een wens, en de verlanglijst keek alleen naar de lengte (±6 s) en nooit naar de titel.
library;

import 'dart:io';

import 'package:debridmusic/ffmpeg.dart';
import 'package:debridmusic/integriteit.dart';
import 'package:debridmusic/lossless_want.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

SoulseekFile _f(String pad, {required int dur, int mb = 50, String user = 'peer'}) => SoulseekFile(
      username: user,
      filename: pad,
      size: mb * 1024 * 1024,
      speed: 0,
      queueLength: 0,
      freeSlots: true,
      durationSec: dur,
    );

// Het aanbod van 30-09-2026, zoals het in de bronnenlijst stond.
final _studio96 = _f(r'@@a\Sam Smith\In The Lonely Hour (24bit-96kHz)\01 - I’m Not The Only One.flac'
        .replaceAll(r'’', "'"),
    dur: 239, mb: 82, user: 'a');
final _live = _f(r"@@b\Sam Smith\Gloria\CD 02\04 - I'm Not The Only One (Live From The Royal Albert Hall _ 2022).flac",
    dur: 234, mb: 53, user: 'b');
final _studio44 = _f(r"@@c\Sam Smith\In The Lonely Hour (24bit-44.1kHz)\04 - I'm Not The Only One.flac",
    dur: 239, mb: 48, user: 'c');
final _kort = _f(r"@@d\Sam Smith\The Thrill Of It All\24 - I'm Not The Only One.flac", dur: 223, mb: 43, user: 'd');
final _liveMap = _f(r"@@e\Sam Smith\Gloria (Live From The Royal Albert Hall)\CD 02\04 - I'm Not The Only One.flac",
    dur: 234, mb: 53, user: 'e');
final _anderNummer = _f(r'@@f\Sam Smith\In The Lonely Hour\02 - Good Thing.flac', dur: 238, mb: 50, user: 'f');

const _titel = "I'm Not The Only One";

void main() {
  group('de lengte', () {
    test('DE KERN: 3:59 heeft de lengte, 3:54 niet', () {
      expect(lengteKlopt(239, 239), isTrue);
      expect(lengteKlopt(239, 241), isTrue, reason: 'twee rips verschillen een tel of twee');
      expect(lengteKlopt(239, 234), isFalse, reason: 'de live-opname uit de Royal Albert Hall');
      expect(lengteKlopt(239, null), isFalse, reason: 'onbekend is geen voorrang');
      expect(lengteKlopt(null, 239), isFalse);
    });

    test('DE KERN: in de race doen eerst alleen de kopieën met de officiële lengte mee', () {
      final delen = DownloadManager.lengteDelen([_live, _studio96, _studio44, _kort], 239);
      expect(delen, hasLength(2));
      expect(delen.first, [_studio96, _studio44]);
      expect(delen.last, [_live, _kort], reason: 'niet fout, maar pas als de 3:59-kopieën niet leveren');
    });

    test('DE GRENS: zonder officiële lengte, of als niets (of alles) hem heeft: één race zoals vroeger', () {
      expect(DownloadManager.lengteDelen([_live, _studio96], null), [
        [_live, _studio96]
      ]);
      expect(DownloadManager.lengteDelen([_live, _kort], 239), [
        [_live, _kort]
      ]);
      expect(DownloadManager.lengteDelen([_studio96, _studio44], 239), [
        [_studio96, _studio44]
      ]);
    });

    test('in een lijst gaat de officiële lengte vóór de bits', () {
      // Tot 30-09-2026 won de 24/48 live-opname hier van de 24/44,1 studiokopie: meer bits per seconde.
      final lijst = [_live, _studio44, _kort]..sort(DownloadManager.opLengteDanRang(239));
      expect(lijst.first, _studio44);
    });

    test('DE VAL: een opwaardering mag nooit verder van de officiële lengte liggen', () {
      final hires96Live = _f(r"@@g\Sam Smith\Gloria\04 - I'm Not The Only One (Live).flac", dur: 234, mb: 110, user: 'g');
      expect(DownloadManager.magOpwaarderen(hires96Live, _studio44, 239), isFalse,
          reason: 'een 24/96 van 3:54 is geen opwaardering van een 24/44,1 van 3:59');
      expect(DownloadManager.magOpwaarderen(_studio96, _studio44, 239), isTrue);
      // Lag er zelf al iets van een andere lengte, dan telt alleen de kwaliteit.
      expect(DownloadManager.magOpwaarderen(_studio96, _kort, 239), isTrue);
    });
  });

  group('de titel en de map', () {
    test('DE KERN: een live-plaat in de MAP telt ook, als je het album kent', () {
      // "04 - I'm Not The Only One.flac" in een map die "Gloria (Live From The Royal Albert Hall)" heet.
      expect(fileOffersTitle(_titel, 239, 'Sam Smith', _liveMap.filename, 234, album: 'In The Lonely Hour'), isFalse);
      expect(fileOffersTitle(_titel, 239, 'Sam Smith', _studio44.filename, 239, album: 'In The Lonely Hour'), isTrue);
    });

    test('DE GRENS: zonder album blijft de mapcontrole uit, zoals voorheen', () {
      expect(fileOffersTitle(_titel, 239, 'Sam Smith', _liveMap.filename, 234), isTrue);
    });

    test('DE GRENS: een versiewoord dat in het album, de titel of de artiest staat, telt niet', () {
      expect(mapVerraadtAndereVersie('Layla', 'Unplugged', 'Eric Clapton', r'@@x\Eric Clapton - Unplugged\07 - Layla.flac'),
          isFalse, reason: 'wie MTV Unplugged aanvult hoort unplugged-kopieën te krijgen');
      expect(mapVerraadtAndereVersie('Lightning Crashes', 'Throwing Copper', 'Live', r'@@x\Live - Throwing Copper\05.flac'),
          isFalse, reason: 'de band Live heet nu eenmaal zo');
      expect(mapVerraadtAndereVersie('Blue (Remix)', 'Blue', 'Eiffel 65', r'@@x\Eiffel 65 - Remixes\01 - Blue.flac'),
          isFalse, reason: '"Remixes" in de map wordt verklaard door "(Remix)" in de titel');
      expect(mapVerraadtAndereVersie('Freed From Desire', 'Hitzone 5', 'Gala', r'@@x\Radio 538 Hitzone 5\03.flac'),
          isFalse, reason: '"radio" in een verzamelmap zegt niets over de uitvoering');
      expect(mapVerraadtAndereVersie('Freed From Desire', 'Come Into My Life', 'Gala', r'@@x\Gala - Live Sessions\03.flac'),
          isTrue);
    });

    test('meervouden tellen nu ook als versiewoord', () {
      // "Remixes" stond in de map, dus als extra woord was hij "verklaard" — en als versiewoord telde
      // alleen het enkelvoud.
      expect(fileOffersTitle('Blue (Da Ba Dee)', 212, 'Eiffel 65', r'@@x\Eiffel 65 - Blue (Remixes)\01 - Blue (Da Ba Dee) (Remixes).flac', 212),
          isFalse);
    });
  });

  group('de verlanglijst', () {
    LosslessWant wens() => LosslessWant(
          artist: 'Sam Smith',
          title: _titel,
          album: 'In The Lonely Hour',
          sinceMs: 0,
          authority: const TrackTags(
              title: _titel, artist: 'Sam Smith', album: 'In The Lonely Hour', trackNo: 5, seconds: 239),
        );

    test('DE KERN: een live-opname komt er niet meer door, ook al zit hij binnen de zes seconden', () {
      final k = DownloadManager.kandidatenVoorWens(wens(), [_live, _studio44, _studio96, _liveMap]);
      expect(k, isNot(contains(_live)), reason: '"(Live From The Royal Albert Hall)" in de naam');
      expect(k, isNot(contains(_liveMap)), reason: 'en in de map');
    });

    test('DE VAL: een ander nummer van dezelfde artiest en lengte evenmin', () {
      // De zoekladder valt terug op alleen de artiestnaam; dan kwam élk nummer van ongeveer 3:59 in aanmerking.
      expect(DownloadManager.kandidatenVoorWens(wens(), [_anderNummer, _studio44]), [_studio44]);
    });

    test('en de officiële lengte gaat voor', () {
      final ruim = _f(r"@@h\Sam Smith\In The Lonely Hour\05 - I'm Not The Only One.flac", dur: 243, mb: 90, user: 'h');
      final k = DownloadManager.kandidatenVoorWens(wens(), [ruim, _studio44]);
      expect(k.first, _studio44, reason: '3:59 vóór 4:03, ook al heeft die meer bits');
    });
  });

  group('na het binnenhalen, met ffmpeg', () {
    final ffmpeg = Ffmpeg().pad;
    late Directory map;
    // De decodeerproef bewaart zijn uitslag zonder erop te wachten, en die late schrijfbeurt zet de map
    // terug. Eén keer aan het eind wissen tot hij weg blijft — zie keuring_test.dart.
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
      map = Directory.systemTemp.createTempSync('dm_lengte_');
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

    test('DE KERN: een bestand van een andere lengte is een mislukte poging, de race gaat door', () async {
      final f = File('${map.path}${Platform.pathSeparator}binnen.flac');
      final r = await Process.run(ffmpeg!, [
        '-nostdin', '-v', 'error', '-f', 'lavfi', '-i', 'anoisesrc=d=40:c=pink:r=44100:a=0.3:seed=3',
        '-c:a', 'flac', f.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final regels = <String>[];

      final ander = await DownloadManager.keurOverdracht(SlskDone(f.path), spoor: regels.add, verwachtSeconden: 60);
      expect(ander, isA<SlskFail>());
      expect((ander as SlskFail).reason, contains('andere uitvoering'));
      expect(regels.single, contains('andere lengte'));

      expect(await DownloadManager.keurOverdracht(SlskDone(f.path), verwachtSeconden: 41), isA<SlskDone>(),
          reason: 'binnen de twaalf seconden: een andere persing, geen andere uitvoering');
      expect(await DownloadManager.keurOverdracht(SlskDone(f.path)), isA<SlskDone>(),
          reason: 'zonder officiële lengte geen lengtecontrole');
    }, skip: ffmpeg == null ? 'geen ffmpeg op deze machine' : false);
  });

  group('aangesloten', () {
    final bron = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('de race in _soulseekBest verdeelt elke bak op lengte', () {
      final i = bron.indexOf('  Future<bool> _soulseekBest(');
      final lijf = bron.substring(i, bron.indexOf('\n  }\n', i));
      expect(lijf, contains('await bak(stereo,'));
      expect(lijf, contains('await bak(surround,'));
      expect(lijf, contains('await bak(lossy,'));
      expect(lijf, contains('magOpwaarderen(f, from, officieel)'));
      // En nooit bij jouw eigen keuze.
      expect(lijf, contains('final officieel = keuze == null && !vast ? job.authority?.seconds : null;'));
    });

    test('de radio zet de officiële lengte ook voorop', () {
      // Zijn eigen marge (15 s, radiobestand.dart) blijft; alleen de volgorde binnen wat erdoor komt.
      final i = bron.indexOf('  Future<String?> _haalVoorRadio(');
      expect(i, greaterThan(0));
      final lijf = bron.substring(i, bron.indexOf('\n  }\n', i));
      expect(lijf, contains('passend..sort(opLengteDanRang(seconden))'));
    });

    test('elke automatische overdracht wordt op lengte gekeurd, jouw eigen keuze niet', () {
      expect(bron, contains('verwachtSeconden: job.exact == null && !job.jouwKeuze ? job.authority?.seconds : null'));
    });

    test('"Ontbrekende downloaden" en de catalogus geven het album mee aan de titelcontrole', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('f.durationSec, album: album.title)'));
      expect(RegExp(r'album: widget\.album\.title\)').allMatches(main).length, greaterThanOrEqualTo(2));
    });
  });
}
