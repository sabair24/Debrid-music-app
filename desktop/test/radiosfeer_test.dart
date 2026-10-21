/// "Past / past niet in deze radio" (Saber, 21-10-2026).
///
/// *"als er een radio van de vengaboys speelt, moet daar niet een liedje van sade die traag en meer jazz is
/// in komen … maar als er een radio is van michael bublé, dan mag sade daar wel weer inkomen."* Een oordeel
/// hoort bij de sfeer van een radio — dezelfde zaadartiest of dezelfde familie — niet bij het nummer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/radiolijst.dart';
import 'package:debridmusic/radiosfeer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een toestel zonder eigen winkel: wat het zet, staat er meteen (en gaat als op naar de pc).
RadioSfeer toestel([List<List<Map<String, dynamic>>>? verstuurd]) =>
    RadioSfeer()..duwOps = (ops) async => verstuurd?.add(ops);

void main() {
  group('het oordeel hoort bij de sfeer van de radio', () {
    test('DE KERN: past niet in een Vengaboys-radio, wel in een Michael Bublé-radio', () async {
      final s = toestel();
      await s.zet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans', naar: Sfeeroordeel.pastNiet);
      expect(s.pastNiet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans'), isTrue);
      expect(s.pastNiet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Michael Bublé', familie: 'jazz'), isFalse);
    });

    test('dezelfde familie telt ook: een andere dansradio', () async {
      final s = toestel();
      await s.zet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans', naar: Sfeeroordeel.pastNiet);
      expect(s.pastNiet(artiest: 'Sade', titel: 'Smooth Operator', zaad: '2 Unlimited', familie: 'dans'), isTrue);
      expect(s.pastNiet(artiest: 'Sade', titel: 'Smooth Operator', zaad: '2 Unlimited', familie: ''), isFalse,
          reason: 'familie nog onbekend en een andere zaadartiest: geen verband');
    });

    test('het laatste oordeel wint, en weghalen kan', () async {
      final s = toestel();
      await s.zet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans', naar: Sfeeroordeel.pastNiet);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await s.zet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans', naar: Sfeeroordeel.past);
      expect(s.oordeel(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans'), Sfeeroordeel.past);
      await s.zet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans', naar: null);
      expect(s.oordeel(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans'), isNull);
    });

    test('een akoestische versie is een ander nummer; hoofdletters en een "The" niet', () async {
      final s = toestel();
      await s.zet(artiest: 'Charlie Puth', titel: 'Light Switch', zaad: 'Sabrina Carpenter', familie: 'popsoul', naar: Sfeeroordeel.pastNiet);
      expect(s.pastNiet(artiest: 'Charlie Puth', titel: 'Light Switch (Acoustic)', zaad: 'Sabrina Carpenter', familie: 'popsoul'), isFalse);
      expect(s.pastNiet(artiest: 'CHARLIE PUTH', titel: 'light switch', zaad: 'sabrina carpenter', familie: 'popsoul'), isTrue);
    });

    test('een radio uit een zin is zijn eigen context', () async {
      final s = toestel();
      await s.zet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'zin:maak me een radio met eurodance', familie: '', naar: Sfeeroordeel.pastNiet);
      expect(s.pastNiet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'zin:Maak me een radio met eurodance', familie: ''), isTrue);
      expect(s.pastNiet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'zin:jazz voor de zondag', familie: ''), isFalse);
    });

    test('een toestel stuurt het als op naar de pc', () async {
      final verstuurd = <List<Map<String, dynamic>>>[];
      final s = toestel(verstuurd);
      await s.zet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans', naar: Sfeeroordeel.pastNiet);
      final op = verstuurd.single.single;
      expect(op['type'], 'radio.sfeer');
      expect(op['v'], 'pastniet');
      expect(op['key'], sfeerSleutel('Sade', 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans'));
    });

    test('voorbeelden voor het model: alleen van radio\'s als deze, het nieuwste eerst', () async {
      final s = toestel();
      await s.zet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans', naar: Sfeeroordeel.pastNiet);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await s.zet(artiest: 'Norah Jones', titel: "Don't Know Why", zaad: '2 Unlimited', familie: 'dans', naar: Sfeeroordeel.pastNiet);
      await s.zet(artiest: 'Adele', titel: 'Hello', zaad: 'Michael Bublé', familie: 'jazz', naar: Sfeeroordeel.pastNiet);
      final niet = s.voorbeelden(zaad: 'Vengaboys', familie: 'dans', soort: Sfeeroordeel.pastNiet);
      expect([for (final n in niet) n.artiest], ['Norah Jones', 'Sade']);
    });
  });

  group('op de pc, in de gedeelde staat', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_radiosfeer_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Map<String, dynamic> op(String v, int at) => {
          'type': 'radio.sfeer',
          'key': sfeerSleutel('Sade', 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans'),
          'v': v,
          'n': sfeerNummer('Sade', 'Smooth Operator'),
          'a': 'Sade',
          't': 'Smooth Operator',
          'z': sfeerZaad('Vengaboys'),
          'f': 'dans',
          'at': at,
        };

    test('bewaard, meegestuurd naar de toestellen, en gelezen zoals op een toestel', () {
      final w = LanStateStore(File('${map.path}${Platform.pathSeparator}state.json'));
      w.applyOps([op('pastniet', 1000)]);
      final pc = RadioSfeer()..winkel = w;
      expect(pc.pastNiet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans'), isTrue);
      final gsm = RadioSfeer()..vanServer((jsonDecode(jsonEncode(w.snapshot()))['radioSfeer'] as Map).cast<String, dynamic>());
      expect(gsm.pastNiet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans'), isTrue);
    });

    test('DE VAL: een late op van een toestel dat offline was zet een nieuwer oordeel niet terug', () {
      final w = LanStateStore(File('${map.path}${Platform.pathSeparator}state.json'));
      w.applyOps([op('past', 2000)]);
      w.applyOps([op('pastniet', 1000)]);
      final pc = RadioSfeer()..winkel = w;
      expect(pc.oordeel(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans'), Sfeeroordeel.past);
    });

    test('overleeft een herstart', () async {
      final f = File('${map.path}${Platform.pathSeparator}state.json');
      final w = LanStateStore(f)..applyOps([op('pastniet', DateTime.now().millisecondsSinceEpoch)]);
      await f.writeAsString(jsonEncode(w.toJson()));
      final na = LanStateStore(f);
      await na.load();
      expect((RadioSfeer()..winkel = na).pastNiet(artiest: 'Sade', titel: 'Smooth Operator', zaad: 'Vengaboys', familie: 'dans'),
          isTrue);
    });
  });

  group('wat het model te horen krijgt', () {
    const kandidaten = [(artiest: 'Haddaway', titel: 'What Is Love')];
    test('de sfeervraag noemt wat niet paste en wat wel', () {
      final p = sfeerPrompt(
          artiest: 'Vengaboys',
          kandidaten: kandidaten,
          pastNiet: const [(artiest: 'Sade', titel: 'Smooth Operator')],
          pastWel: const [(artiest: 'Aqua', titel: 'Barbie Girl')]);
      expect(p, contains('NIET pasten'));
      expect(p, contains('- Sade - Smooth Operator'));
      expect(p, contains('- Aqua - Barbie Girl'));
    });

    test('zonder oordelen blijft de vraag zoals hij was', () {
      final p = sfeerPrompt(artiest: 'Vengaboys', kandidaten: kandidaten);
      expect(p, isNot(contains('NIET pasten')));
    });
  });

  test('aangesloten: twee paar knoppen in Nu speelt, en de radio kent het oordeel', () {
    final m = File('lib/main.dart').readAsStringSync();
    final knop = m.substring(m.indexOf('class _RadioOordeel extends StatelessWidget {'));
    final bouw = knop.substring(0, knop.indexOf('\n}\n'));
    expect(bouw, contains("kop('Past in deze radio?')"));
    expect(bouw.indexOf("kop('Past in deze radio?')"), lessThan(bouw.indexOf('if (gehaald) ...[')),
        reason: 'past/past niet bij elk nummer; houden/weg alleen bij wat de radio haalde');
    expect(bouw, contains("kop('Houden of weg?')"));
    expect(m, contains('radio.sfeer = radioSfeer;'));
    expect(m, contains("radioSfeer.vanServer(\n              (s['radioSfeer'] as Map?)"));
    expect(m, contains('radioSfeer.duwOps = duw;'));
    expect(m, contains('if (radio.sessie == s) radio.familie = z.familie?.name ?? \'\';'));
    expect(m, contains('pastNiet: voorbeelden(Sfeeroordeel.pastNiet),'), reason: 'de sfeerkeuring leert mee');
    expect(m, contains('pastNiet: keuring.voorbeelden(Sfeeroordeel.pastNiet),'), reason: 'en de lijstvraag');
  });
}
