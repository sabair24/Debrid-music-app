/// De regels van het bijvullen — wanneer, hoeveel, en wat er herhaald wordt (plan van 08-10-2026).
///
/// Zuiver: geen speler, geen Deezer. Wat hier fout gaat hoor je als een radio die stilvalt terwijl er
/// honderd plekken wachten, of als een radio die na twee uur nog steeds dezelfde drie artiesten speelt.
library;

import 'dart:math';

import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiokeuze.dart';
import 'package:debridmusic/radioladder.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:flutter_test/flutter_test.dart';

Bijvulbesluit _besluit({
  bool loopt = true,
  bool speelt = true,
  bool droog = false,
  bool wilVerder = false,
  double verwacht = 5,
  int? rest = 600,
  int gelandOfKlaar = 0,
  int onderweg = 0,
  double opbrengst = 0.5,
  bool bezig = false,
  int droogSeconden = 0,
  Duration? sindsVorige,
}) {
  final nu = DateTime(2026, 10, 8, 18);
  return bijvulBesluit(
    loopt: loopt,
    speelt: speelt,
    droog: droog,
    wilVerder: wilVerder,
    verwacht: verwacht,
    restSeconden: rest,
    gelandOfKlaar: gelandOfKlaar,
    onderweg: onderweg,
    opbrengst: opbrengst,
    bezig: bezig,
    droogSeconden: droogSeconden,
    vorige: sindsVorige == null ? null : nu.subtract(sindsVorige),
    nu: nu,
  );
}

Herhaalkandidaat _k(String artiest,
        {int? laatst,
        bool gehoord = true,
        bool groen = false,
        bool eigen = false,
        bool opSchijf = false,
        bool zaad = false,
        bool rood = false}) =>
    (
      artiest: artiest,
      laatstVoorbij: laatst,
      gehoord: gehoord,
      groen: groen,
      eigen: eigen,
      opSchijf: opSchijf,
      zaadOfAnker: zaad,
      rood: rood
    );

void main() {
  group('de opbrengst', () {
    test('zonder geschiedenis een kwart, en nooit nul', () {
      expect(recenteOpbrengst(const []), closeTo(0.25, 1e-9));
      expect(recenteOpbrengst(List.filled(100, false), venster: 100), 0.02);
    });

    test('DE KERN: één op de twintig is weinig, en dat ziet hij', () {
      final u = [for (var i = 0; i < 20; i++) i == 0];
      expect(recenteOpbrengst(u), closeTo(2 / 24, 1e-9));
    });

    test('alleen de laatste dertig tellen', () {
      final u = [...List.filled(100, true), ...List.filled(30, false)];
      expect(recenteOpbrengst(u), closeTo(1 / 34, 1e-9));
    });
  });

  group('wat er naar verwachting nog vóór je staat', () {
    test('DE KERN: honderd wachtend bij vijf procent is vijf, niet honderd', () {
      final v = verwachtVooruit(
          rijVooruit: 0, geland: 0, klaarArtiesten: const [], onderweg: 0, wacht: 100, opbrengst: 0.05);
      expect(v, closeTo(5, 1e-9));
    });

    test('eigen muziek per artiest hoogstens drie, de zaadartiest één', () {
      final v = verwachtVooruit(
        rijVooruit: 2,
        geland: 1,
        klaarArtiesten: const ['Niels Destadsbader', 'Niels Destadsbader', 'Niels Destadsbader', 'Bazart', 'Bazart', 'Bazart', 'Bazart'],
        zaad: 'Niels Destadsbader',
        onderweg: 8,
        wacht: 0,
        opbrengst: 0.05,
      );
      expect(v, closeTo(2 + 1 + 1 + 3 + 8 * 0.05, 1e-9));
    });
  });

  group('het besluit', () {
    test('DE KERN: een droge rij vult bij — ook al speelt er niets', () {
      final b = _besluit(speelt: false, droog: true, verwacht: 2, onderweg: 8, opbrengst: 0.5);
      expect(b.nu, isTrue);
    });

    test('"volgende" op het laatste nummer telt als droog', () {
      expect(_besluit(speelt: false, wilVerder: true, verwacht: 2).nu, isTrue);
    });

    test('DE GRENS: gepauzeerd midden in een nummer vult niet bij', () {
      final b = _besluit(speelt: false, verwacht: 0, rest: 30);
      expect(b.nu, isFalse);
      expect(b.nood, isFalse);
    });

    test('nood: droog, niets klaar, en acht kansloze haaltjes onderweg', () {
      final b = _besluit(droog: true, speelt: false, onderweg: 8, opbrengst: 0.1, verwacht: 20, sindsVorige: const Duration(seconds: 40));
      expect(b.nood, isTrue);
      expect(b.nu, isTrue, reason: 'nood wacht niet op de gewone adem van anderhalve minuut');
    });

    test('ook bij nood niet elke tik een ronde: hoogstens één per dertig seconden', () {
      final b = _besluit(droog: true, speelt: false, onderweg: 8, opbrengst: 0.1, sindsVorige: const Duration(seconds: 10));
      expect(b.nu, isFalse);
      expect(b.nood, isTrue, reason: 'de noodvulling zelf (reserve of herhalen) gaat wel door');
      expect(_besluit(droog: true, speelt: false, sindsVorige: kNoodAdem).nu, isTrue);
    });

    test('geen nood als er iets klaarstaat, of als het onderweg er waarschijnlijk komt', () {
      expect(_besluit(droog: true, speelt: false, gelandOfKlaar: 1, onderweg: 8, opbrengst: 0.1).nood, isFalse);
      expect(_besluit(droog: true, speelt: false, onderweg: 8, opbrengst: 0.5).nood, isFalse);
    });

    test('de stilte duurt uiterlijk tien seconden: gezien bij de eerste tik, nood vijf seconden later', () {
      // De tik van de radio is vijf seconden; de droogte wordt bij de eerste tik gezien.
      expect(kDroogTotNood, lessThanOrEqualTo(5));
    });

    test('DE VAL: droog met kansrijke haaltjes onderweg — na een paar seconden toch nood', () {
      // Acht onderweg × 0,2 = 1,6: volgens de som komt er wel iets, en dan was het één tot twee
      // minuten stil (beoordeling van 08-10-2026).
      expect(_besluit(droog: true, speelt: false, onderweg: 8, opbrengst: 0.2).nood, isFalse);
      expect(_besluit(droog: true, speelt: false, onderweg: 8, opbrengst: 0.2, droogSeconden: kDroogTotNood).nood, isTrue);
      expect(_besluit(droog: true, speelt: false, onderweg: 8, opbrengst: 0.2, droogSeconden: 60, gelandOfKlaar: 1).nood,
          isFalse, reason: 'er staat iets klaar: dat speelt zo');
    });

    test('krap is ook: minder dan vier minuten muziek over', () {
      expect(_besluit(rest: 200, onderweg: 1, opbrengst: 0.5).nood, isTrue);
      expect(_besluit(rest: 300, onderweg: 1, opbrengst: 0.5).nood, isFalse);
      expect(_besluit(rest: null, onderweg: 0).nood, isFalse, reason: 'een onbekende resttijd is niet krap');
    });

    test('genoeg vooruit, of net een ronde gehad: niet', () {
      expect(_besluit(verwacht: 15).nu, isFalse);
      expect(_besluit(verwacht: 14.9).nu, isTrue);
      expect(_besluit(verwacht: 5, sindsVorige: const Duration(seconds: 30)).nu, isFalse);
      expect(_besluit(verwacht: 5, sindsVorige: const Duration(seconds: 90)).nu, isTrue);
    });

    test('er loopt al een ronde: geen tweede, maar de nood blijft zichtbaar', () {
      final b = _besluit(droog: true, speelt: false, bezig: true);
      expect(b.nu, isFalse);
      expect(b.nood, isTrue);
    });
  });

  group('wat er herhaald wordt', () {
    test('DE KERN: wat je hoorde, minstens 25 geleden, gaat eerst', () {
      final k = [_k('A', laatst: 0, eigen: true), _k('B', laatst: 10, eigen: true), _k('C', laatst: 2, opSchijf: true)];
      final r = kiesHerhaling(k, teller: 30, hoeveel: 1);
      expect(r.niveau, 1);
      expect(r.keuze, [0]);
    });

    test('DE VAL: wat je oversloeg komt niet terug zolang er iets anders is — groen wel', () {
      final k = [_k('A', laatst: 0, eigen: true, gehoord: false), _k('B', laatst: 5, eigen: true)];
      expect(kiesHerhaling(k, teller: 60, hoeveel: 2).keuze, [1]);
      expect(kiesHerhaling([_k('A', laatst: 0, groen: true, gehoord: false)], teller: 60).niveau, 1);
    });

    test('het allerlaatste vangnet, liever dan stilte: ook overgeslagen, minstens tien geleden', () {
      final k = [_k('A', laatst: 0, eigen: true, gehoord: false)];
      expect(kiesHerhaling(k, teller: 9).keuze, isEmpty);
      final r = kiesHerhaling(k, teller: 10);
      expect(r.niveau, 3);
      expect(r.keuze, [0]);
      // Maar niet wat er niet meer staat, en nooit rood.
      expect(kiesHerhaling([_k('B', laatst: 0, gehoord: false)], teller: 60).keuze, isEmpty);
      expect(kiesHerhaling([_k('C', laatst: 0, eigen: true, gehoord: false, rood: true)], teller: 60).keuze, isEmpty);
    });

    test('dan stap voor stap dichterbij: 10, dan 3', () {
      final k = [_k('A', laatst: 0, eigen: true)];
      expect(kiesHerhaling(k, teller: 15).niveau, 2);
      expect(kiesHerhaling(k, teller: 5).niveau, 5);
      expect(kiesHerhaling(k, teller: 2).keuze, isEmpty, reason: 'twee nummers geleden is geen herhaling, dat is een plaat die hapert');
    });

    test('een download die er nog staat telt even zwaar als eigen: geen kring van zes eigen nummers', () {
      // Eigen, 3 geleden, tegen een download van 30 geleden: de download eerst.
      final k = [_k('A', laatst: 27, eigen: true), _k('B', laatst: 0, opSchijf: true)];
      final r = kiesHerhaling(k, teller: 30, hoeveel: 1);
      expect(r.niveau, 1);
      expect(r.keuze, [1]);
      // En een download die er niet meer staat (en niet eigen of groen is) komt niet terug.
      expect(kiesHerhaling([_k('B', laatst: 0)], teller: 30).keuze, isEmpty);
    });

    test('binnen een niveau groen eerst, dan het langst niet gehoorde', () {
      final k = [_k('X', laatst: 0, eigen: true), _k('Y', laatst: 5, eigen: true, groen: true), _k('Z', laatst: 2, eigen: true)];
      expect(kiesHerhaling(k, teller: 60, hoeveel: 3).keuze, [1, 0, 2]);
    });

    test('het vangnet: eigen nummers van de zaadartiest, ook ongespeeld', () {
      final k = [_k('Niels Destadsbader', zaad: true), _k('B', laatst: 0, eigen: true)];
      final r = kiesHerhaling(k, teller: 1);
      expect(r.niveau, 4);
      expect(r.keuze, [0]);
    });

    test('een overgeslagen nummer van de zaadartiest is geen vangnet', () {
      final k = [_k('Niels Destadsbader', laatst: 0, eigen: true, zaad: true, gehoord: false)];
      expect(kiesHerhaling(k, teller: 5).keuze, isEmpty, reason: 'pas als allerlaatste, na tien');
      expect(kiesHerhaling(k, teller: 10).niveau, 3);
    });

    test('DE VAL: geen kringetje van drie — eenmaal overgeslagen en 10 geleden gaat vóór gehoord en 3 geleden', () {
      final k = [
        _k('Gehoord', laatst: 55, eigen: true), // 5 geleden
        _k('Overgeslagen', laatst: 40, eigen: true, gehoord: false), // 20 geleden
      ];
      final r = kiesHerhaling(k, teller: 60, hoeveel: 1);
      expect(r.keuze, [1]);
      expect(r.niveau, 3);
    });

    test('het vangnet geeft hoogstens één nummer van de zaadartiest per keer', () {
      final k = [_k('Niels Destadsbader', zaad: true), _k('Niels Destadsbader', zaad: true), _k('Niels Destadsbader', zaad: true)];
      final r = kiesHerhaling(k, teller: 1, hoeveel: 2);
      expect(r.niveau, 4);
      expect(r.keuze, hasLength(1));
    });

    test('DE VAL: klonk de zaadartiest net, dan eerst wat je hoorde — het vangnet pas daarna', () {
      final k = [_k('Niels Destadsbader', zaad: true), _k('X', laatst: 55, eigen: true)];
      final vol = {artiestSleutel('Niels Destadsbader')};
      final r = kiesHerhaling(k, teller: 60, vol: vol, hoeveel: 1);
      expect(r.niveau, 5);
      expect(r.keuze, [1]);
      // Is er niets anders, dan toch het vangnet: stilte mag niet.
      final alleen = kiesHerhaling([k[0]], teller: 60, vol: vol);
      expect(alleen.niveau, 4);
      expect(alleen.keuze, [0]);
    });

    test('in de uitgeputte fase gaan eenmaal overgeslagen nummers vóór het vangnet', () {
      final k = [_k('Niels Destadsbader', zaad: true), _k('Y', laatst: 40, eigen: true, gehoord: false)];
      final r = kiesHerhaling(k, teller: 60, hoeveel: 1);
      expect(r.niveau, 3);
      expect(r.keuze, [1]);
    });

    test('nooit rood', () {
      final k = [_k('A', laatst: 0, eigen: true, groen: true, rood: true), _k('Z', zaad: true, rood: true)];
      expect(kiesHerhaling(k, teller: 100).keuze, isEmpty);
    });

    test('niet wie net klonk of aan zijn plafond zit — tenzij er niemand anders is', () {
      final k = [_k('X', laatst: 0, eigen: true), _k('Y', laatst: 10, eigen: true), _k('Z', laatst: 5, eigen: true)];
      expect(kiesHerhaling(k, teller: 60, hoeveel: 3).keuze, [0, 2, 1]);
      expect(kiesHerhaling(k, teller: 60, hoeveel: 1, recenteArtiesten: const ['X']).keuze, [2]);
      expect(kiesHerhaling(k, teller: 60, hoeveel: 1, vol: {artiestSleutel('X'), artiestSleutel('Z')}).keuze, [1]);
      // Is er niets anders, dan toch.
      expect(kiesHerhaling([k[0]], teller: 60, recenteArtiesten: const ['X']).keuze, [0]);
      expect(kiesHerhaling([k[0]], teller: 60, vol: {artiestSleutel('X')}).keuze, [0]);
    });

    test('twee keer dezelfde artiest pas als er niemand anders is', () {
      final k = [_k('X', laatst: 0, eigen: true), _k('X', laatst: 1, eigen: true), _k('Y', laatst: 2, eigen: true)];
      expect(kiesHerhaling(k, teller: 60, hoeveel: 2).keuze, [0, 2]);
    });
  });

  group('het plafond per artiest, met een venster', () {
    Radioplek plek(String a, {Haalstand stand = Haalstand.wacht, int? voorbij, bool reserve = false}) =>
        Radioplek(artiest: a, titel: '$a ${Random().nextInt(1 << 30)}', reserve: reserve)
          ..stand = stand
          ..voorbijOp = voorbij;

    test('DE KERN: drie afgekeurde nummers sluiten een artiest niet uit', () {
      final plan = [for (var i = 0; i < 3; i++) plek('Clouseau', stand: Haalstand.mislukt)];
      expect(artiestenVoorPlafond(plan, voorbijteller: 10), isEmpty);
    });

    test('wat lang geleden voorbij kwam telt niet meer, wat net klonk wel', () {
      final plan = [plek('A', stand: Haalstand.inRij, voorbij: 1), plek('B', stand: Haalstand.inRij, voorbij: 30)];
      expect(artiestenVoorPlafond(plan, voorbijteller: 45), ['B']);
    });

    test('wat nog komt telt altijd, de reserve die klaarstaat niet', () {
      final plan = [
        plek('A'),
        plek('B', stand: Haalstand.onderweg),
        plek('C', stand: Haalstand.geland),
        plek('D', stand: Haalstand.inRij),
        plek('E', stand: Haalstand.klaar, reserve: true),
      ];
      expect(artiestenVoorPlafond(plan, voorbijteller: 0), ['A', 'B', 'C', 'D']);
    });

    test('DE VAL: tweehonderd nummers, en in elke veertig hoogstens drie van één artiest', () {
      final r = Random(7);
      final artiesten = [for (var i = 0; i < 25; i++) 'Artiest $i'];
      final plan = <Radioplek>[];
      var teller = 0;
      final gespeeld = <String>[];
      var n = 0;
      while (gespeeld.length < 200) {
        if (plan.where((p) => p.voorbijOp == null).length < 10) {
          final kandidaten = [for (final a in (artiesten.toList()..shuffle(r)).take(8)) for (var j = 0; j < 3; j++) a];
          final al = artiestenVoorPlafond(plan, voorbijteller: teller);
          for (final i in spreidArtiesten(kandidaten, al: al)) {
            plan.add(Radioplek(artiest: kandidaten[i], titel: 'nummer ${n++}'));
          }
        }
        final volgende = plan.firstWhere((p) => p.voorbijOp == null);
        volgende.voorbijOp = ++teller;
        gespeeld.add(volgende.artiest);
      }
      for (var i = 0; i + 40 <= gespeeld.length; i++) {
        final tel = <String, int>{};
        for (final a in gespeeld.sublist(i, i + 40)) {
          tel[a] = (tel[a] ?? 0) + 1;
        }
        final meest = tel.values.reduce(max);
        expect(meest, lessThanOrEqualTo(kMaxPerArtiest), reason: 'venster vanaf $i: $tel');
      }
    });
  });

  group('steeds geweigerd', () {
    Radioplek geweerd(String a, Weerreden w, {Haalstand stand = Haalstand.mislukt}) =>
        Radioplek(artiest: a, titel: '$a ${Random().nextInt(1 << 30)}')
          ..stand = stand
          ..weer = w;

    test('DE KERN: drie keer om tijdvak of stijl, dan niet meer laten keuren', () {
      final plan = [
        geweerd('Clouseau', Weerreden.tijdvak),
        geweerd('Clouseau', Weerreden.stijl),
        geweerd('Clouseau', Weerreden.tijdvak),
        geweerd('Bazart', Weerreden.tijdvak),
        geweerd('Bazart', Weerreden.tijdvak),
      ];
      expect(steedsGeweigerd(plan), {artiestSleutel('Clouseau')});
    });

    test('niet te vinden of de sfeer telt niet: dat zegt niets over het tijdvak', () {
      final plan = [for (var i = 0; i < 3; i++) geweerd('K3', i == 0 ? Weerreden.sfeer : Weerreden.nietGevonden)];
      expect(steedsGeweigerd(plan), isEmpty);
    });

    test('DE GRENS: een reden op een plek die toch landde telt niet', () {
      final plan = [for (var i = 0; i < 3; i++) geweerd('Natalia', Weerreden.tijdvak, stand: Haalstand.geland)];
      expect(steedsGeweigerd(plan), isEmpty);
    });
  });

  group('de reserve blijft achteraan', () {
    test('DE KERN: nakomers komen vóór de reserve', () {
      final plan = [
        Radioplek(artiest: 'A', titel: 'a')..stand = Haalstand.inRij,
        Radioplek(artiest: 'B', titel: 'b'),
        Radioplek(artiest: 'R', titel: 'r', reserve: true)..stand = Haalstand.klaar,
      ];
      // Drie nakomers tegen één wachtende: zonder de regel kwam R tussen M en O terecht.
      final uit = mengNakomers(plan, [
        Radioplek(artiest: 'N', titel: 'n'),
        Radioplek(artiest: 'M', titel: 'm'),
        Radioplek(artiest: 'O', titel: 'o'),
      ]);
      expect(uit.map((p) => p.artiest), ['A', 'N', 'B', 'M', 'O', 'R']);
    });
  });
}
