// TIDAL als reserve voor de FLAC-wens. Saber, 22-10-2026: "Dit vindt ik niet op soulseek in flac ... msc moet ik
// die in een wenslijst kunnen steken" en "Tidal is wel enkel als back-up e, soulseek blijft prio". Soulseek eerst;
// pas na drie rondes zonder FLAC zoekt de wens op TIDAL, kiest streng op titel en artiest, en keurt wat binnenkomt
// zoals een kandidaat van Soulseek.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lossless_want.dart';
import 'package:debridmusic/tidaler.dart';

/// Wat het zoekhulpje van tidaler ([kTidalZoekHulp]) teruggaf voor "DJ Massiv High Volume", gemeten op 22-10-2026 met
/// tidaler 0.1.8, plus de band High Volume en Phlegmatic Dogs uit de vroegere tiddl-meting — met de \r\n van Windows.
final _echt = [
  'Let us check if you are already logged in...',
  '{"id": "298793269", "artiest": "Phlegmatic Dogs", "titel": "High Volume", "stereo": true, "tags": ["LOSSLESS"]}',
  '{"id": "39195534", "artiest": "High Volume", "titel": "Our Secret", "stereo": true, "tags": ["LOSSLESS"]}',
  '{"id": "208442464", "artiest": "DJ Massiv", "titel": "High Volume", "seconden": 299, "stereo": true, "tags": ["LOSSLESS"]}',
  '{"id": "208442481", "artiest": "DJ Massiv", "titel": "High Volume (Furax Remix)", "stereo": true, "tags": ["LOSSLESS"]}',
  '{"id": "329212875", "artiest": "MI37", "titel": "High Volume", "stereo": true, "tags": ["LOSSLESS"]}',
  '{"id": "208442464", "artiest": "DJ Massiv", "titel": "High Volume", "stereo": true}',
  '',
].join('\r\n');

void main() {
  group('de treffers van het zoekhulpje', () {
    test('DE KERN: elk id één keer, artiest en titel apart, de versie in de titel', () {
      final t = tidalZoektreffers(_echt);
      expect(t.length, 5, reason: 'zes regels JSON, één id dubbel; de begroeting telt niet');
      expect(t.first, (id: '298793269', artiest: 'Phlegmatic Dogs', titel: 'High Volume'));
      expect(t.where((x) => x.id == '208442464').single, (id: '208442464', artiest: 'DJ Massiv', titel: 'High Volume'));
      expect(t[1], (id: '39195534', artiest: 'High Volume', titel: 'Our Secret'));
      expect(t[3].titel, 'High Volume (Furax Remix)');
    });

    test('geen treffers: niets, en geen uitzondering', () {
      expect(tidalZoektreffers(''), isEmpty);
      expect(tidalZoektreffers('{"fout": "niet ingelogd"}\r\n'), isEmpty);
    });
  });

  group('kiezen', () {
    test(
      'DE KERN: "DJ Massiv vs the Rebel — High Volume" vindt DJ Massiv, en niet Phlegmatic Dogs of de band High Volume',
      () {
        final t = tidalZoektreffers(_echt);
        expect(kiesTidalTreffers(t, artiest: 'DJ Massiv vs the Rebel', titel: 'High Volume'), ['208442464']);
        expect(
          kiesTidalTreffers(t, artiest: 'DJ Massiv vs the Rebel', titel: 'High Volume', nee: ['208442464']),
          isEmpty,
          reason: 'wat de keuring afwees, komt niet terug',
        );
      },
    );

    test('de artiest woord voor woord vanaf het begin; de titel gelijk, met of zonder gast', () {
      const t = <TidalTreffer>[
        (id: '1', artiest: 'Sam', titel: 'Touch Me'),
        (id: '2', artiest: 'Samantha Fox', titel: 'Touch Me'),
        (id: '3', artiest: 'The Doors', titel: 'Touch Me'),
        (id: '4', artiest: 'Samantha Fox', titel: 'Touch Me (feat. X)'),
        (id: '5', artiest: 'Samantha Fox', titel: 'Touch Me (Remix)'),
        (id: '6', artiest: '', titel: 'Touch Me'),
      ];
      expect(kiesTidalTreffers(t, artiest: 'Samantha Fox', titel: 'Touch Me'), ['2', '4']);
      expect(kiesTidalTreffers(t, artiest: 'Doors', titel: 'touch me'), ['3'], reason: '"The" telt niet mee');
      expect(kiesTidalTreffers(t, artiest: 'Samantha Fox feat. Y', titel: 'Touch Me (feat. Y)'), ['2', '4']);
    });
  });

  group('wanneer TIDAL meedoet', () {
    const w = LosslessWant(artist: 'DJ Massiv vs the Rebel', title: 'High Volume');

    test('DE KERN: pas in de derde ronde zonder FLAC van Soulseek, en alleen als tidaler er is', () {
      expect(kSoulseekRondesVoorTidal, 3);
      expect(wensMagNaarTidal(w, tidalErIs: true), isFalse, reason: 'de eerste ronde is van Soulseek');
      expect(wensMagNaarTidal(w.met(tries: 1), tidalErIs: true), isFalse);
      expect(wensMagNaarTidal(w.met(tries: 2), tidalErIs: true), isTrue);
      expect(wensMagNaarTidal(w.met(tries: 11), tidalErIs: true), isTrue);
      expect(wensMagNaarTidal(w.met(tries: 5), tidalErIs: false), isFalse);
    });

    test('een wens om één bepaald bestand nooit', () {
      const vast = LosslessWant(
        artist: 'A',
        title: 'B',
        tries: 5,
        exact: VasteBron(username: 'peer', filename: r'x\B.flac', size: 30000000),
      );
      expect(wensMagNaarTidal(vast, tidalErIs: true), isFalse);
    });

    test('wat de keuring afwees, blijft onthouden over een herstart', () {
      final n = w.met(tries: 3, tidalNee: ['208442464']);
      expect(n.met(tries: 4).tidalNee, ['208442464'], reason: 'met() houdt hem vast');
      final terug = LosslessWant.fromJson(n.toJson())!;
      expect(terug.tidalNee, ['208442464']);
      expect(w.toJson().containsKey('tidalNee'), isFalse, reason: 'leeg schrijft niets');
    });
  });

  group('de instellingen van tidaler', () {
    test('de keuringsmap wordt de downloadmap, en hij slaat niets over', () {
      final m = {
        for (final x in tidalerInstellingen(map: r'D:\k\tidal-wens-1', kwaliteit: 'max')) x[0]: x[1],
      };
      expect(m['download_base_path'], r'D:\k\tidal-wens-1');
      expect(m['skip_existing'], 'False', reason: 'een eerder gehaald nummer leverde anders niets en toch afloopcode 0');
      expect(m['quality_audio'], 'HI_RES_LOSSLESS');
      expect(tidalerUrl('track/208442464'), 'https://tidal.com/browse/track/208442464');
    });
  });

  group('aangesloten', () {
    final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    String lijf(String kop) {
      final i = online.indexOf(kop);
      expect(i, greaterThanOrEqualTo(0), reason: kop);
      return online.substring(i, online.indexOf('\n  }\n', i));
    }

    test('DE KERN: Soulseek eerst; TIDAL alleen in het einde van de ronde, en alleen als Soulseek niets gaf', () {
      final jacht = lijf('  Future<bool> _chaseWant(LosslessWant w) async {');
      expect(jacht.indexOf('soulseek.search(w.query, achtergrond: true, extra: kHiresZoekwoorden)'), allOf(greaterThan(0), lessThan(jacht.indexOf('_rondWensAf('))));
      expect(jacht, contains('if (lossless.isEmpty) return _rondWensAf(w, goed: false,'));
      expect(jacht, contains('return _rondWensAf(w, goed: goed,'));
      expect(jacht, isNot(contains('_wensViaTidal')));
      final einde = lijf('  Future<bool> _rondWensAf(');
      expect(einde, contains('if (!goed && wensMagNaarTidal(w, tidalErIs: Tidaler.beschikbaar)) {'));
      expect(einde, contains('tidalNee: tidalNee));'), reason: 'de afgewezen nummers gaan mee op schijf');
    });

    test('wat van TIDAL komt, gaat door dezelfde keuring als wat van Soulseek komt', () {
      expect(
        lijf('  Future<bool> _chaseWant(LosslessWant w) async {'),
        contains('final uitslag = await _keurVoorWens(w, staged, f.username);'),
      );
      final tidal = lijf('  Future<bool> _wensViaTidal(');
      expect(tidal, contains("await _keurVoorWens(w, binnen.single, 'TIDAL \$id');"));
      expect(tidal, contains("haalVanTidal(doel: 'track/\$id', map: map.path, zoekMap: map.path)"));
      expect(tidal, contains('if (uitslag == _Wenskeuring.afgewezen) nee.add(id);'));
      expect(tidal, contains('_geefKeuringsmapVrij(map);'));
      final keur = lijf('  Future<_Wenskeuring> _keurVoorWens(');
      for (final stap in [
        'magBlijven(oordeel)',
        'zelfdeLengte(w.authority?.seconds, lengte)',
        // Dezelfde opname: sinds 25-10-2026 met de score, zodat een twijfel bewaard kan worden (twijfel.dart).
        '_opnameScore(staged.path, bestaand)',
        'opnameOordeel(score)',
        'firstIsBetter(staged',
        'placeFileDetailed(staged',
      ]) {
        expect(keur, contains(stap));
      }
    });
  });
}
