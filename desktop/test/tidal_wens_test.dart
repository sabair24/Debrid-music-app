// TIDAL als reserve voor de FLAC-wens. Saber, 22-10-2026: "Dit vindt ik niet op soulseek in flac ... msc moet ik
// die in een wenslijst kunnen steken" en "Tidal is wel enkel als back-up e, soulseek blijft prio". Soulseek eerst;
// pas na drie rondes zonder FLAC zoekt de wens op TIDAL, kiest streng op titel en artiest, en keurt wat binnenkomt
// zoals een kandidaat van Soulseek.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lossless_want.dart';
import 'package:debridmusic/tiddl.dart';

/// Wat `tiddl download search -t track -n 10 "High Volume"` echt afdrukte op 22-10-2026 (tiddl 3.4.4), met de
/// \r\n van Windows.
final _echt = [
  'Auth token expires in 0d 3h 49m',
  '┌────────────────────────────── Search Results ───────────────────────────────┐',
  '│                                 High Volume                                 │',
  '│ ┌──────┬──────┬───────────────────────────────────────────────┬───────────┐ │',
  '│ │ #    │ Type │ Title                                         │ ID        │ │',
  '│ ├──────┼──────┼───────────────────────────────────────────────┼───────────┤ │',
  '│ │ 1    │ Tra… │ Phlegmatic Dogs - High Volume [STEREO]        │ 298793269 │ │',
  '│ │ 2    │ Tra… │ High Volume - Our Secret [STEREO]             │ 39195534  │ │',
  '│ │ 3    │ Tra… │ High Volume - Our Secret [STEREO]             │ 15311933  │ │',
  '│ │ 4    │ Tra… │ Phlegmatic Dogs - High Volume [STEREO]        │ 298793269 │ │',
  '│ │ 5    │ Tra… │ High Volume - Our Secret [STEREO]             │ 15311929  │ │',
  '│ │ 6    │ Tra… │ High Volume - Our Secret [STEREO]             │ 15311927  │ │',
  '│ │ 7    │ Tra… │ High Volume - Our Secret [STEREO]             │ 15524009  │ │',
  '│ │ 8    │ Tra… │ High Volume - Our Secret [STEREO]             │ 15311930  │ │',
  '│ │ 9    │ Tra… │ DJ Massiv - High Volume [STEREO]              │ 208442464 │ │',
  '│ │ 10   │ Tra… │ High Volume - Our Secret [STEREO]             │ 15311932  │ │',
  '│ │ 11   │ Tra… │ Junkie Kid - High Volume [STEREO]             │ 390624198 │ │',
  '│ └──────┴──────┴───────────────────────────────────────────────┴───────────┘ │',
  '└─────────────────────────────────────────────────────────────────────────────┘',
  'Enter the number of the resource to add to your list (comma-separated for ',
  'multiple, q/empty = quit): Total downloads: 0',
  '',
  'Aborted.',
  '',
].join('\r\n');

void main() {
  group('de zoektabel van tiddl', () {
    test('DE KERN: elk id één keer, artiest en titel apart, zonder [STEREO]', () {
      final t = tidalZoektreffers(_echt);
      expect(t.length, 10, reason: 'elf regels, één id dubbel');
      expect(t.first, (id: '298793269', artiest: 'Phlegmatic Dogs', titel: 'High Volume'));
      expect(t.where((x) => x.id == '208442464').single, (id: '208442464', artiest: 'DJ Massiv', titel: 'High Volume'));
      expect(t[1], (id: '39195534', artiest: 'High Volume', titel: 'Our Secret'));
    });

    test('een lange titel loopt door op de volgende regel; alleen Atmos valt weg; kleuren en | tellen niet', () {
      const uit =
          '│ │ 1  │ Track │ Gorillaz - Feel Good Inc. (Stanton │ 2001 │ │\n'
          '│ │    │       │ Warriors Remix) [STEREO]           │      │ │\n'
          '│ │ 2  │ Track │ Gorillaz - Feel Good Inc [DOLBY_ATMOS] │ 2002 │ │\n'
          '\x1B[1m│ │ 3  │ Track │ Gorillaz - Feel Good Inc [STEREO, DOLBY_ATMOS] │ 2003 │ │\x1B[0m\n'
          '| | 4  | Track | Gorillaz - DARE              | 2004 | |\n';
      final t = tidalZoektreffers(uit);
      expect(t.map((x) => x.id), ['2001', '2003', '2004']);
      expect(t.first.titel, 'Feel Good Inc. (Stanton Warriors Remix)');
      expect(t[1].titel, 'Feel Good Inc');
      expect(t.last.titel, 'DARE', reason: 'zonder modus blijft de titel zoals hij is');
    });

    test('geen tabel: niets, en geen uitzondering', () {
      expect(tidalZoektreffers(''), isEmpty);
      expect(tidalZoektreffers('Aborted.\r\n'), isEmpty);
      expect(tidalZoektreffers('│ │ #    │ Type │ Title │ ID        │ │'), isEmpty, reason: 'de kopregel');
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

    test('DE KERN: pas in de derde ronde zonder FLAC van Soulseek, en alleen als tiddl er is', () {
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

  group('de opdrachtregel', () {
    test('--sp wijst de keuringsmap aan, vóór url; de kwaliteit blijft op zijn plek', () {
      final r = tiddlOpdracht(
        tool: 'tiddl',
        doel: 'track/208442464',
        map: r'D:\k\tidal-wens-1',
        zoekMap: r'D:\k\tidal-wens-1',
      );
      expect(r[r.indexOf('--sp') + 1], r'D:\k\tidal-wens-1');
      expect(r.indexOf('--sp'), lessThan(r.indexOf('url')));
      expect(r[3], 'max');
      expect(r.last, 'track/208442464');
      expect(
        tiddlOpdracht(tool: 'tiddl', doel: 'album/1', map: 'm'),
        isNot(contains('--sp')),
        reason: 'de link plakken blijft zoals hij was',
      );
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
      expect(jacht.indexOf('soulseek.search(w.query)'), lessThan(jacht.indexOf('_rondWensAf(')));
      expect(jacht, contains('if (lossless.isEmpty) return _rondWensAf(w, goed: false,'));
      expect(jacht, contains('return _rondWensAf(w, goed: goed,'));
      expect(jacht, isNot(contains('_wensViaTidal')));
      final einde = lijf('  Future<bool> _rondWensAf(');
      expect(einde, contains('if (!goed && wensMagNaarTidal(w, tidalErIs: Tiddl.beschikbaar)) {'));
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
        '_zelfdeOpname(',
        'firstIsBetter(staged',
        'placeFileDetailed(staged',
      ]) {
        expect(keur, contains(stap));
      }
    });
  });
}
