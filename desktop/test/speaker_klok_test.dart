/// Waar een Sonos is, op enkele ms (groeperen, stap 3.3, Saber 21-10-2026: "pc + Sonos ongeveer, met een
/// schuif").
///
/// Wat hier vastligt: dat de doorsnede van de meetvensters tot een paar ms krimpt, en dat het ware
/// beginmoment er ALTIJD in ligt — ook vlak na de start (de Sonos buffert eerst en zegt dan "0"), na een
/// pauze (ongeacht waar in de seconde hij stilstond), na spoelen, bij een nieuw nummer en als de klok van
/// de Sonos een fractie anders loopt. Gemeten op de Move (22-10-2026, om de 47 ms gevraagd): 15 sprongen,
/// nul tegenspraak, na 9 s 15 ms breed; de Move begint ~430 ms na de play-opdracht.
library;

import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/speaker_klok.dart';

/// Een nagebootste Sonos: zijn plek loopt (met [snelheid]) vanaf [beginUs], of staat stil op [stilOpUs];
/// hij meldt hele seconden, naar beneden afgerond.
class _NepSonos {
  _NepSonos(this.beginUs);

  int beginUs;
  int? stilOpUs;
  double snelheid = 1.0;

  int positieUs(int t) => stilOpUs ?? ((t - beginUs) * snelheid).floor();
  int seconde(int t) => max(0, positieUs(t)) ~/ 1000000;

  /// Het beginmoment zoals het nu lijkt (bij een iets andere snelheid schuift het langzaam).
  int beginNu(int t) => t - positieUs(t);
}

/// Speelt [duurUs] vragen af tegen [sonos], zoals de klok dat doet (met de echte tussenpozen), en roept
/// [na] na elke meting. Geeft de tijd aan het eind terug.
int _speel(
  Plekschatting p,
  _NepSonos sonos,
  int vanUs,
  int duurUs,
  Random r, {
  void Function(int t, bool breuk)? na,
  void Function(int t)? voor,
}) {
  var t = vanUs;
  while (t < vanUs + duurUs) {
    voor?.call(t);
    final t0 = t;
    final antwoord = t0 + 1000 + r.nextInt(5000);
    final t1 = antwoord + 1000 + r.nextInt(5000);
    final breuk = p.voegToe((t0Us: t0, t1Us: t1, plekMs: sonos.seconde(antwoord) * 1000));
    na?.call(t1, breuk);
    t = p.volgendeVraag(t1, r);
  }
  return t;
}

/// Het ware beginmoment ligt in de doorsnede (afronding: 1 µs).
void _ligtErin(Plekschatting p, int waar, String waarom) {
  final b = p.beginUs!, w = p.breedteUs!;
  expect(
    (waar - b).abs(),
    lessThanOrEqualTo(w ~/ 2 + 1),
    reason: '$waarom: fout ${(waar - b) / 1000} ms, breedte ${w / 1000} ms',
  );
}

const _t = 1760000000000000; // een gewoon tijdstip, in µs

void main() {
  group('de doorsnede', () {
    test('krimpt tot een paar ms, en het ware begin ligt er altijd in', () {
      final r = Random(1);
      final p = Plekschatting();
      final sonos = _NepSonos(_t - 30000000);
      var gezien = 0;
      int? na5;
      _speel(
        p,
        sonos,
        _t,
        15000000,
        r,
        na: (t, breuk) {
          expect(breuk, isFalse);
          if (p.sprongen == 0) return;
          gezien++;
          if (t > _t + 5000000) na5 ??= p.breedteUs;
          _ligtErin(p, sonos.beginUs, 'na ${(t - _t) ~/ 1000} ms');
        },
      );
      // Gericht vragen kost twee à drie vragen per seconde, geen tien.
      expect(gezien, greaterThanOrEqualTo(25));
      // Gericht vragen: na vijf seconden al smal, na vijftien bijna zo smal als de rondgang toelaat. Gemeten
      // over 300 zaden (22-10-2026, met de vragen om de beurt binnen en naast het venster): na 5 s mediaan
      // 13 ms, ergst 27; na 15 s mediaan 9 ms, ergst 14.
      expect(na5, lessThan(30000));
      expect(p.breedteUs, lessThan(15000));
      expect(p.standOp(_t + 15000000), PlekStand.speelt);
    });

    test('bufferen bij de start ("0" voor hij speelt) trekt de schatting niet te vroeg', () {
      // Veel starts op willekeurige momenten: zonder het wissen na stilte viel het ware begin in ruim de
      // helft van de metingen buiten het venster, tot 114 ms (nagespeeld 22-10-2026, 2000 starts); vijf
      // vaste starts zagen dat niet.
      for (var seed = 0; seed < 300; seed++) {
        final r = Random(seed);
        final p = Plekschatting();
        // Gevraagd vanaf _t; hij zegt 0 tot hij echt begint, ergens tussen 0,3 en 3,3 s later.
        final start = _t + 300000 + r.nextInt(3000000);
        final sonos = _NepSonos(start)..stilOpUs = 0;
        _speel(
          p,
          sonos,
          _t,
          start - _t + 5000000,
          r,
          voor: (t) {
            if (t >= start) sonos.stilOpUs = null;
          },
          na: (t, _) {
            if (p.sprongen > 0 && t > start) _ligtErin(p, start, 'zaad $seed na ${(t - start) ~/ 1000} ms');
            if (t < start) expect(p.standOp(t), isNot(PlekStand.speelt));
          },
        );
        expect(p.standOp(start + 5000000), PlekStand.speelt);
      }
    });

    for (final f in [50, 500, 950]) {
      test('pauze op $f ms in de seconde: stil na 1,3 s, en daarna weer binnen het venster', () {
        final r = Random(f);
        final p = Plekschatting();
        final sonos = _NepSonos(_t - 10000000);
        // Tot vlak voor de pauze spelen, zodat hij op 40,f s stilstaat.
        final pauzeOp = sonos.beginUs + 40000000 + f * 1000;
        var t = _speel(p, sonos, _t, pauzeOp - _t, r);
        sonos.stilOpUs = sonos.positieUs(pauzeOp);
        t = _speel(
          p,
          sonos,
          t,
          4000000,
          r,
          na: (t, _) {
            if (t > pauzeOp + 1500000) {
              expect(p.standOp(t), PlekStand.stil, reason: 'stil na ${(t - pauzeOp) ~/ 1000} ms');
            }
          },
        );
        // Verder spelen: vanaf daar loopt de plek weer.
        final stil = sonos.stilOpUs!;
        sonos
          ..stilOpUs = null
          ..beginUs = t - stil;
        var sprong = false;
        _speel(
          p,
          sonos,
          t,
          6000000,
          r,
          na: (t, _) {
            if (p.standOp(t) == PlekStand.speelt) sprong = true;
            if (sprong) _ligtErin(p, sonos.beginUs, 'na verder spelen');
          },
        );
        expect(sprong, isTrue);
      });
    }

    test('spoelen breekt de reeks: even onbekend, dan het nieuwe begin', () {
      final r = Random(7);
      final p = Plekschatting();
      final sonos = _NepSonos(_t - 20000000);
      var t = _speel(p, sonos, _t, 5000000, r);
      sonos.beginUs -= 30000000; // 30 s vooruit
      var breuken = 0;
      int? breukOp;
      _speel(
        p,
        sonos,
        t,
        6000000,
        r,
        na: (t, breuk) {
          if (breuk) {
            breuken++;
            breukOp = t;
            expect(p.standOp(t), PlekStand.onbekend);
          }
          if (breukOp != null && p.sprongen > 0) _ligtErin(p, sonos.beginUs, 'na spoelen');
        },
      );
      expect(breuken, 1);
      expect(p.standOp(t + 6000000), PlekStand.speelt);
    });

    test('een nieuw nummer (naadloos, de plek valt terug naar 0) breekt de reeks', () {
      final r = Random(8);
      final p = Plekschatting();
      final sonos = _NepSonos(_t - 235000000);
      final eind = _t + 3000000;
      var breuken = 0;
      _speel(
        p,
        sonos,
        _t,
        8000000,
        r,
        voor: (t) {
          if (t >= eind && sonos.beginUs < eind) sonos.beginUs = eind;
        },
        na: (t, breuk) {
          if (breuk) breuken++;
          if (t > eind && p.sprongen > 0) _ligtErin(p, eind, 'nieuw nummer');
        },
      );
      expect(breuken, 1);
    });

    // Gemeten op de Move (22-10-2026, 40 s om de 15 ms): de sprongmomenten wandelen tot ±15 ms van een
    // rechte lijn en springen soms in één keer ~30 ms terug — de Sonos stelt zijn klok bij. Met een
    // speling van 30 ms las de klok zo'n sprong als een pauze en begon opnieuw: de Shield kreeg een anker
    // dat 227 ms verschoven was.
    test('de klok van de speaker springt 30 ms (de Move stelt bij): geen pauze, geen breuk, hij loopt mee', () {
      for (final sprong in [30000, -30000, 60000, -60000]) {
        final r = Random(sprong);
        final p = Plekschatting();
        final sonos = _NepSonos(_t - 20000000);
        var gesprongen = false;
        int? vorigeT;
        var twijfel = 0;
        _speel(p, sonos, _t, 30000000, r, voor: (t) {
          if (!gesprongen && t > _t + 12000000) {
            gesprongen = true;
            sonos.beginUs += sprong;
          }
        }, na: (t, breuk) {
          final waarom = 'sprong ${sprong ~/ 1000} ms na ${(t - _t) ~/ 1000} ms';
          expect(breuk, isFalse, reason: waarom);
          // Even twijfelen mag (bijstelling of pauze?), stil worden niet.
          if (p.sprongen > 0) expect(p.standOp(t), isNot(PlekStand.stil), reason: waarom);
          if (vorigeT != null && p.standOp(t) == PlekStand.onbekend) twijfel += t - vorigeT!;
          vorigeT = t;
        });
        // Zo lang geen nieuw anker (volgers spelen door op het vorige). Gemeten over 200 zaden per jump: mediaan
        // 3–4 s, ergst 5,9 s; daarna binnen 8 ms.
        expect(twijfel, lessThan(6500000), reason: 'sprong ${sprong ~/ 1000} ms: zo lang onbekend');
        expect((p.beginUs! - sonos.beginUs).abs(), lessThan(10000), reason: 'sprong ${sprong ~/ 1000} ms');
      }
    });

    // De Move zoals gemeten: sprongen die ±15 ms van een rechte lijn wandelen (hier traag heen en weer, 25 s)
    // en één jump van ±30 ms. Nagespeeld over 300 zaden (22-10-2026): mediaan 7 ms, 90 % 16, 99 % 42, ergst
    // 50 ms (zonder de herstelstand: ergst 243 ms, het midden van een ineens breed venster; met willekeurig
    // gekozen vragen naast het venster: 57 ms weggelopen in 7 s).
    test('een wandelende klok (de Move): nooit stil of een breuk, en de schatting blijft in de buurt', () {
      final fouten = <int>[];
      for (var z = 0; z < 100; z++) {
        final r = Random(z);
        final b0 = _t - 20000000;
        final fase = r.nextDouble() * 2 * pi;
        final jumpOp = _t + 5000000 + r.nextInt(30000000);
        final jump = (r.nextBool() ? 1 : -1) * 30000;
        int begin(int t) => b0 + (15000 * sin(fase + 2 * pi * (t - _t) / 25000000)).round() + (t > jumpOp ? jump : 0);
        final p = Plekschatting();
        var t = _t;
        while (t < _t + 40000000) {
          final a = t + 1000 + r.nextInt(5000);
          final t1 = a + 1000 + r.nextInt(5000);
          expect(p.voegToe((t0Us: t, t1Us: t1, plekMs: (a - begin(a)) ~/ 1000000 * 1000)), isFalse, reason: 'zaad $z');
          final stand = p.standOp(t1);
          if (p.sprongen > 0) expect(stand, isNot(PlekStand.stil), reason: 'zaad $z');
          if (t1 > _t + 8000000 && stand == PlekStand.speelt) fouten.add((p.beginUs! - begin(t1)).abs());
          t = p.volgendeVraag(t1, r);
        }
      }
      fouten.sort();
      expect(fouten[(fouten.length * 0.9).floor()], lessThan(20000), reason: '90 %');
      expect(fouten.last, lessThan(60000), reason: 'ergst');
    });

    // De KEF zoals gemeten (22-10-2026): hij werkt zijn plek bij op een eigen klokje (1008 ms ± 30), naar
    // beneden op 48 ms. Nagespeeld over 300 zaden: het ware begin in 0 van 66.783 metingen buiten het
    // venster; na 20 s fout mediaan 4 ms, 90 % 11, ergst 19 (het venster zelf blijft breder: mediaan 44 ms).
    test('een KEF (eigen klokje, blokjes van 48 ms): het ware begin altijd in het venster, de schatting dichtbij', () {
      final fouten = <int>[];
      for (var z = 0; z < 100; z++) {
        final r = Random(z);
        final begin = _t - 30000000 - r.nextInt(1000000);
        var bijgewerkt = _t - r.nextInt(1000000);
        var volgende = bijgewerkt + 1008000;
        var gemeld = ((bijgewerkt - begin) ~/ 48000) * 48;
        int plek(int t) {
          while (t >= volgende) {
            bijgewerkt = volgende;
            gemeld = ((bijgewerkt - begin) ~/ 48000) * 48;
            volgende = bijgewerkt + 1008000 + (r.nextInt(61) - 30) * 1000;
          }
          return gemeld;
        }

        final p = Plekschatting(houdMs: 1150, korrelMs: 48, gericht: false);
        var t = _t;
        while (t < _t + 20000000) {
          final a = t + 1000 + r.nextInt(6000);
          final t1 = a + 1000 + r.nextInt(6000);
          expect(p.voegToe((t0Us: t, t1Us: t1, plekMs: plek(a))), isFalse, reason: 'zaad $z');
          if (p.sprongen > 0) _ligtErin(p, begin, 'zaad $z na ${(t1 - _t) ~/ 1000} ms');
          t = p.volgendeVraag(t1, r);
        }
        fouten.add((p.beginUs! - begin).abs());
      }
      fouten.sort();
      expect(fouten[(fouten.length * 0.9).floor()], lessThan(15000), reason: '90 %');
      expect(fouten.last, lessThan(30000), reason: 'ergst');
    });

    test('een klok die 50 ppm anders loopt: twee minuten geen breuk, en de schatting loopt mee', () {
      final r = Random(9);
      final p = Plekschatting();
      final sonos = _NepSonos(_t - 5000000)..snelheid = 1.00005;
      var breuken = 0;
      final eind = _speel(
        p,
        sonos,
        _t,
        120000000,
        r,
        na: (t, breuk) {
          if (breuk) breuken++;
        },
      );
      expect(breuken, 0);
      expect((p.beginUs! - sonos.beginNu(eind)).abs(), lessThan(10000));
    });
  });

  test('wanneer hij vraagt: gericht bij de sprong en midden in de seconde als hij speelt, anders op tijd', () {
    final r = Random(10);
    const begin = _t - 7300000;
    int fase(int start, int halve) => (start + halve - begin) % 1000000;
    for (var i = 0; i < 200; i++) {
      final nu = _t + r.nextInt(1000000);
      // Heel breed (160 ms): een kwart voor de sprong, een kwart erna, of het midden.
      final a = volgendeVraagOp(
        stand: PlekStand.speelt,
        beginUs: begin,
        breedteUs: 160000,
        stilUs: 0,
        nuUs: nu,
        toeval: r,
        halveRondgangUs: 4000,
      );
      expect(a - nu, inInclusiveRange(25000, 1000000));
      expect(fase(a, 4000), isIn([960000, 40000, 500000]));
      // Breed (40 ms): rond het midden van het venster (± 5 ms), of het midden van de seconde.
      final m = volgendeVraagOp(
        stand: PlekStand.speelt,
        beginUs: begin,
        breedteUs: 40000,
        stilUs: 0,
        nuUs: nu,
        toeval: r,
        halveRondgangUs: 4000,
      );
      final fm = fase(m, 4000);
      expect(fm == 500000 || fm <= 5000 || fm >= 995000, isTrue, reason: 'fase $fm');
      // Smal (9 ms): ergens binnen het venster rond de sprong, of het midden.
      final b = volgendeVraagOp(
        stand: PlekStand.speelt,
        beginUs: begin,
        breedteUs: 9000,
        stilUs: 0,
        nuUs: nu,
        toeval: r,
        halveRondgangUs: 4000,
      );
      final f = fase(b, 4000);
      // Binnen het venster, of er net naast (± de helft plus 8 ms: zie kProefNaast), of het midden.
      expect(f == 500000 || f <= 4500 || f >= 995500 || f == 12500 || f == 987500, isTrue, reason: 'fase $f');
    }
    for (var i = 0; i < 50; i++) {
      int na(PlekStand s, int stil) =>
          (volgendeVraagOp(stand: s, beginUs: null, breedteUs: null, stilUs: stil, nuUs: _t, toeval: r) - _t) ~/ 1000;
      expect(na(PlekStand.onbekend, 500000), inInclusiveRange(70, 130));
      expect(na(PlekStand.stil, 2000000), inInclusiveRange(70, 130));
      expect(na(PlekStand.stil, 20000000), inInclusiveRange(150, 250));
      expect(na(PlekStand.stil, 90000000), inInclusiveRange(800, 1000));
    }
  });

  group('de klok', () {
    test('meldt pas als hij speelt, dan alleen bij een echte verschuiving, en stil bij een pauze', () {
      fakeAsync((fa) {
        int nu() => _t + fa.elapsed.inMicroseconds;
        final sonos = _NepSonos(_t - 12000000);
        final meldingen = <({bool speelt, int fout})>[];
        late final SpeakerKlok klok;
        klok = SpeakerKlok(
          klokUs: nu,
          toeval: Random(11),
          vraag: () async {
            await Future<void>.delayed(const Duration(milliseconds: 3));
            final s = sonos.seconde(nu()) * 1000;
            await Future<void>.delayed(const Duration(milliseconds: 3));
            return s;
          },
          bijVerandering: () {
            final p = klok.plekNu!;
            meldingen.add((speelt: p.speelt, fout: p.positieMs - sonos.positieUs(nu()) ~/ 1000));
          },
        )..start();
        // Eerst onbekend: niets.
        fa.elapse(const Duration(milliseconds: 600));
        expect(klok.plekNu, isNull);
        expect(meldingen, isEmpty);
        fa.elapse(const Duration(seconds: 2));
        expect(meldingen, isNotEmpty);
        expect(meldingen.first.speelt, isTrue);
        expect(meldingen.first.fout.abs(), lessThan(120));
        // Daarna wordt hij smaller (een paar meldingen), en dan klopt het: niets meer te melden.
        fa.elapse(const Duration(seconds: 10));
        final na10 = meldingen.length;
        expect(na10, lessThan(12));
        expect((klok.plekNu!.positieMs - sonos.positieUs(nu()) ~/ 1000).abs(), lessThan(8));
        fa.elapse(const Duration(seconds: 10));
        expect(meldingen.length - na10, lessThan(3));
        // Pauze: binnen anderhalve seconde "stil", en geen sprong in de plek ervoor.
        sonos.stilOpUs = sonos.positieUs(nu());
        final voor = meldingen.length;
        fa.elapse(const Duration(milliseconds: 1500));
        final erna = meldingen.sublist(voor);
        expect(erna, isNotEmpty);
        expect(erna.last.speelt, isFalse);
        expect(
          erna.where((m) => m.speelt),
          everyElement(predicate<({bool speelt, int fout})>((m) => m.fout.abs() < 40)),
        );
        expect(erna.length, lessThanOrEqualTo(2));
        fa.elapse(const Duration(seconds: 3));
        expect(meldingen.length, voor + erna.length);
        // Verder: weer "speelt", op de goede plek.
        final stil = sonos.stilOpUs!;
        sonos
          ..stilOpUs = null
          ..beginUs = nu() - stil;
        fa.elapse(const Duration(seconds: 3));
        expect(meldingen.last.speelt, isTrue);
        expect((klok.plekNu!.positieMs - sonos.positieUs(nu()) ~/ 1000).abs(), lessThan(60));
        klok.stop();
        fa.elapse(const Duration(seconds: 5));
        expect(fa.pendingTimers, isEmpty);
      });
    });
  });
}
