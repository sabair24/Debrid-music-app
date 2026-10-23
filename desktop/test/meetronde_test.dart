/// De meetronde (Saber, 23-10-2026: "het is tijd om eens de performance te meten, begin eens op men mac" en "zorg er
/// dan voor, zo kan je het beste meten").
///
/// Wat hier vastligt:
/// - de cijfers per rij beelden: gemiddeld, p90 en maximum rasteren, bouwen, en hoeveel beelden te laat waren voor
///   een scherm van 120 Hz;
/// - alleen beelden die ná het eerste merkteken begonnen tellen;
/// - de opdracht `meet` over de zonelijn start de ronde, en zonder ronde zegt het toestel dat het niet kan;
/// - een ronde: begin, één melding per variant, het glas per variant en terug, de schakelaars weer uit, en "klaar";
/// - de kantelhoes geeft de grootste hoes voor de muis, en staat stil in een variant zonder kantelen.
library;

import 'package:debridmusic/meetronde.dart';
import 'package:debridmusic/player.dart' show Rijbediening, Speelbron;
import 'package:debridmusic/ui/kantel_hoes.dart';
import 'package:debridmusic/zone_opdracht.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('de cijfers', () {
    test('gemiddeld, p90, maximum, en te laat op 120 Hz (8,3 ms)', () {
      final c = Beeldcijfers.uit([1000, 2000, 12000], [5000, 9000, 3000], hz: 120);
      expect(c.aantal, 3);
      expect(c.rasterGemMs, closeTo(5.67, .01));
      expect(c.rasterP90Ms, 9.0);
      expect(c.rasterMaxMs, 9.0);
      expect(c.bouwMaxMs, 12.0);
      expect(c.teLaat, 2, reason: 'eentje te traag gerasterd, eentje te traag gebouwd');
      expect(c.budgetMs, closeTo(8.33, .01));
      expect(c.regel('kantel', ['glas', 'spiegel']),
          '[meet] kantel | zonder glas+spiegel | 3 beelden | rasteren gem 5.7 · p90 9.0 · max 9.0 ms | '
          'bouwen gem 5.0 · max 12.0 ms | te laat 2 (>8.3 ms)');
      expect(Beeldcijfers.uit(const [], const [], hz: 120).regel('stil', const []), contains('alles aan | 0 beelden'));
    });

    test('alleen wat ná het merkteken begon', () {
      expect(binnen(100, 100, 200), isFalse, reason: 'het beeld van het merkteken zelf');
      expect(binnen(101, 100, 200), isTrue);
      expect(binnen(200, 100, 200), isTrue);
      expect(binnen(201, 100, 200), isFalse);
    });
  });

  group('op afstand', () {
    test('de opdracht "meet" start de ronde; zonder ronde zegt het toestel dat het niet kan', () async {
      final s = _NepSpeler();
      final gevraagd = <Map<String, dynamic>>[];
      final u = ZoneUitvoerder(speler: s, rij: s, nummer: (_) => null, meet: (op) async => gevraagd.add(op));
      expect(await u.voerUit({'id': '1', 'cmd': 'meet', 'scenarios': ['open']}), isNull);
      expect(gevraagd.single['scenarios'], ['open']);
      final zonder = ZoneUitvoerder(speler: s, rij: s, nummer: (_) => null);
      expect(await zonder.voerUit({'id': '2', 'cmd': 'meet'}), isNotNull);
    });

    test('een ronde: begin, per variant een melding, het glas per variant en terug, en klaar', () async {
      final gemeld = <String>[];
      final glas = <String>[];
      var bereid = 0, klaar = 0;
      Set<String>? tijdens;
      await voerMeetrondeUit({
        'scenarios': <String>[],
        'varianten': [
          <String>[],
          ['glas'],
          ['glasmat', 'spiegel'],
          ['bestaat-niet'],
        ],
      }, MeetHaken(
        openNuSpeelt: () {},
        sluitNuSpeelt: () {},
        meld: (r) async {
          gemeld.addAll(r);
          tijdens ??= meetZonder.value.contains('spiegel') ? {...meetZonder.value} : null;
        },
        zetGlas: (stand, {klaar = false}) => glas.add('${stand ?? '-'}${klaar ? ' klaar' : ''}'),
        bereid: ({required spelen}) async {
          bereid++;
          return 'klaargezet';
        },
        klaar: () async => klaar++,
      ), hz: 120);
      expect(gemeld.first, startsWith('[meet] begin:'));
      expect(gemeld.first, contains('4 varianten, 120 Hz — klaargezet'));
      expect(gemeld.last, '[meet] klaar');
      expect(glas, ['-', 'plat', 'mat', '-', '- klaar'],
          reason: 'per variant de stand, een onbekend effect telt niet, en op het einde terug');
      expect(tijdens, {'glasmat', 'spiegel'}, reason: 'de effecten staan uit terwijl die variant meet');
      expect(meetZonder.value, isEmpty, reason: 'na de ronde staat alles weer aan');
      expect(bereid, 1);
      expect(klaar, 1);
      expect(meetrondeLoopt, isFalse);
    });
  });

  group('de kantelhoes', () {
    testWidgets('de grootste hoes voor de muis; zonder kantelen geen muis en geen draai', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Column(children: [
          SizedBox(width: 80, height: 80, child: KantelHoes(child: ColoredBox(color: Colors.red))),
          SizedBox(width: 300, height: 300, child: KantelHoes(child: ColoredBox(color: Colors.blue))),
        ]),
      ));
      expect(KantelHoes.grootsteVak()?.size, const Size(300, 300));
      expect(find.descendant(of: find.byType(KantelHoes), matching: find.byType(MouseRegion)), findsWidgets);
      meetZonder.value = {'kantel'};
      addTearDown(() => meetZonder.value = const {});
      await t.pumpWidget(const MaterialApp(home: KantelHoes(child: ColoredBox(color: Colors.red))));
      expect(find.descendant(of: find.byType(KantelHoes), matching: find.byType(MouseRegion)), findsNothing);
      expect(find.descendant(of: find.byType(KantelHoes), matching: find.byType(Transform)), findsNothing);
    });
  });
}

class _NepSpeler implements Speelbron, Rijbediening {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

