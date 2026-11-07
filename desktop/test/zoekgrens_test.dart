// De zelf afgetaste zoekgrens (Saber, 07-11-2026: "verhoog systematisch, en kijk wat de grens is, wordt ik even van
// soulseek eruit gegooid dat geeft niets") en de snellere cd-jacht.
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/soulseek.dart' show Zoekrem, kJijZochtNet, kZoekVoorJouVijf, kZoekVoorJouVijfRustig;
import 'package:debridmusic/soortjacht.dart'
    show CdjachtStand, kCdjachtNummersTegelijk, kCdjachtTik, kSoortNummersTegelijk;
import 'package:debridmusic/zoekgrens.dart';

final _t0 = DateTime(2026, 11, 7, 9);

void main() {
  group('de grens zelf', () {
    late DateTime nu;
    late List<String> log;
    late Zoekgrens g;
    setUp(() {
      nu = _t0;
      log = [];
      g = Zoekgrens(klok: () => nu, log: log.add);
    });

    test('DE KERN: begint bij veertig, en gaat pas omhoog na twintig minuten druk zonder probleem', () {
      expect(g.perVijf, kZoekgrensStart);
      g.naZoeken(40);
      nu = nu.add(kZoekgrensStapNa - const Duration(seconds: 1));
      g.naZoeken(40);
      expect(g.perVijf, kZoekgrensStart, reason: 'nog geen twintig minuten');
      nu = nu.add(const Duration(seconds: 1));
      g.naZoeken(40);
      expect(g.perVijf, kZoekgrensStart + kZoekgrensStap);
      expect(log.single, contains('40 → 42'));
      g.naZoeken(42);
      expect(g.perVijf, kZoekgrensStart + kZoekgrensStap, reason: 'de nieuwe stand moet ook twintig minuten gelden');
    });

    test('niet omhoog als de rem niet vol zit: wat niet gebruikt wordt, is niet getoetst', () {
      g.naZoeken(1);
      nu = nu.add(const Duration(hours: 3));
      g.naZoeken((kZoekgrensStart * kZoekgrensVol).floor() - 1);
      expect(g.perVijf, kZoekgrensStart);
    });

    test('een probleem bij hoog tempo: dat is de grens, dan 80% ervan en een dag rust', () {
      g.naZoeken(1);
      g.probleem('verbinding weg', 38);
      expect(g.gemeten, 38);
      expect(g.perVijf, 30, reason: '38 × 0,8 = 30');
      expect(g.rustTot, _t0.add(kZoekgrensRust));
      expect(log.last, contains('dat is de grens'));
      nu = nu.add(const Duration(hours: 23));
      g.naZoeken(30);
      expect(g.perVijf, 30, reason: 'rust');
      nu = nu.add(const Duration(hours: 1));
      g.naZoeken(30);
      expect(g.perVijf, 32, reason: 'na de rust weer voorzichtig omhoog');
    });

    test('nooit omhoog door een probleem, nooit onder de bodem', () {
      g.probleem('de server zwijgt', 70);
      expect(g.perVijf, kZoekgrensStart, reason: '70 × 0,8 = 56 is meer dan wat er nu mag');
      g.probleem('de server zwijgt', 26);
      expect(g.perVijf, kZoekgrensBodem);
    });

    test('een probleem bij weinig zoeken telt niet: dat was wifi of een herstart', () {
      g.probleem('verbinding weg', 5);
      expect(g.gemeten, isNull);
      expect(g.perVijf, kZoekgrensStart);
      expect(g.rustTot, isNull);
      expect(log.single, contains('te weinig'));
    });

    test('nooit boven het plafond (de hoogste sluiting die ooit gemeten is)', () {
      for (var i = 0; i < 40; i++) {
        nu = nu.add(kZoekgrensStapNa);
        g.naZoeken(kZoekgrensPlafond);
      }
      expect(g.perVijf, kZoekgrensPlafond);
    });

    test('bewaard: een herstart begint niet weer bij veertig', () {
      final map = Directory.systemTemp.createTempSync('zoekgrens');
      addTearDown(() => map.deleteSync(recursive: true));
      final pad = '${map.path}${Platform.pathSeparator}soulseek_zoekgrens.json';
      final a = Zoekgrens(bestand: () => pad, klok: () => nu);
      a.naZoeken(40);
      nu = nu.add(kZoekgrensStapNa);
      a.naZoeken(40);
      a.probleem('verbinding weg', 50);
      final b = Zoekgrens(bestand: () => pad, klok: () => nu);
      expect(b.perVijf, 40);
      expect(b.gemeten, 50);
      expect(b.rustTot, a.rustTot);
    });
  });

  group('de rem met de grens', () {
    test('DE KERN: zoek je zelf niet, dan houdt de achtergrond er maar acht voor jou over', () {
      fakeAsync((fa) {
        final rem = Zoekrem(
          klok: () => _t0.add(fa.elapsed),
          grens: Zoekgrens(),
          voorJouVijfRustig: kZoekVoorJouVijfRustig,
        );
        var radio = 0;
        for (var i = 0; i < 80; i++) {
          unawaited(rem.neem(achtergrond: true).then((_) => radio++));
        }
        fa.elapse(const Duration(minutes: 4, seconds: 59));
        expect(radio, kZoekgrensStart - kZoekVoorJouVijfRustig, reason: '32 in plaats van 20');
        var jij = 0;
        for (var i = 0; i < kZoekVoorJouVijfRustig; i++) {
          unawaited(rem.neem().then((_) => jij++));
        }
        fa.flushMicrotasks();
        expect(jij, kZoekVoorJouVijfRustig, reason: 'een albumpagina wacht niet achter de radio');
      });
    });

    test('zocht je net zelf, dan blijft de oude ruimte voor jou vrij', () {
      fakeAsync((fa) {
        final rem = Zoekrem(
          klok: () => _t0.add(fa.elapsed),
          grens: Zoekgrens(),
          voorJouVijfRustig: kZoekVoorJouVijfRustig,
        );
        unawaited(rem.neem());
        fa.flushMicrotasks();
        var radio = 0;
        for (var i = 0; i < 80; i++) {
          unawaited(rem.neem(achtergrond: true).then((_) => radio++));
        }
        fa.elapse(kJijZochtNet - const Duration(seconds: 30));
        expect(radio, kZoekgrensStart - kZoekVoorJouVijf - 1, reason: 'jouw eigen zoekopdracht telt mee');
      });
    });

    test('de rem volgt de grens, en meldt een probleem met hoeveel er gezocht is', () {
      fakeAsync((fa) {
        final log = <String>[];
        final grens = Zoekgrens(klok: () => _t0.add(fa.elapsed), log: log.add);
        final rem = Zoekrem(klok: () => _t0.add(fa.elapsed), grens: grens);
        for (var i = 0; i < 30; i++) {
          unawaited(rem.neem());
        }
        fa.flushMicrotasks();
        expect(rem.inVijf, 20, reason: 'twintig per minuut');
        fa.elapse(const Duration(minutes: 1));
        expect(rem.inVijf, 30);
        rem.probleem('verbinding weg');
        expect(grens.gemeten, 30);
        expect(rem.perVijf, kZoekgrensBodem);
      });
    });
  });

  test('onder Kwaliteit, ook op een toestel: hoeveel er mag en waar de grens geraakt is', () {
    expect(const CdjachtStand(binnen: 3, zoekt: 5).zoekgrensZin, isNull, reason: 'een oude pc zegt het niet');
    final s = CdjachtStand.fromJson(const CdjachtStand(binnen: 3, zoekt: 5, zoekPerVijf: 44, zoekGemeten: 56).toJson());
    expect(s.zin, 'Cd erbij: 3 · zoekt nog 5');
    expect(s.zoekgrensZin, 'Soulseek: 44 zoekopdrachten per 5 min — grens geraakt bij 56');
    expect(const CdjachtStand(zoekPerVijf: 42).zoekgrensZin, contains('nog niet geraakt'));
    final o = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      o,
      contains(
        'binnen: c.binnen, zoekt: c.alle.length, zoekPerVijf: zoekrem.perVijf, zoekGemeten: zoekgrens.gemeten);',
      ),
    );
    final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(m, contains('(Icons.speed_outlined, s.zoekgrensZin)'));
  });

  test('de cd-jacht zoekt samen, zoals de knop, en kijkt elke minuut', () {
    expect(kCdjachtNummersTegelijk, greaterThan(1));
    expect(kCdjachtNummersTegelijk, lessThanOrEqualTo(kSoortNummersTegelijk));
    expect(kCdjachtTik, lessThan(const Duration(minutes: 10)));
  });

  test('aangesloten: de rem van de app tast af, problemen tellen, de cd-jacht loopt door', () {
    final s = File('lib/soulseek.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(s, contains('final zoekrem = Zoekrem(grens: zoekgrens, voorJouVijfRustig: kZoekVoorJouVijfRustig);'));
    expect(s, contains("bestand: () => '\$appDir\${Platform.pathSeparator}soulseek_zoekgrens.json',"));
    expect(
      s,
      contains("      if (!_relogged) zoekrem.probleem('verbinding weg (\$hoe)');\n"),
      reason: 'elders ingelogd is een andere client, geen tempo',
    );
    expect(s, contains("        zoekrem.probleem('de server zwijgt');\n"));
    final o = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(o, contains('    _cdjachtKlok ??= Timer.periodic(kCdjachtTik, (_) => unawaited(_cdjachtTik()));\n'));
    expect(
      o,
      contains('    if (!soulseek.available || soulseek.blocked || soulseek.waaromStil != null) return;\n'),
      reason: 'tijdens een pauze geen rondes die voor niets twee dagen laten wachten',
    );
    expect(o, contains('    if (_soortBezig.isNotEmpty) return;\n'), reason: 'niet meer wachten op de andere jachten');
    expect(o, contains('      if (_cdjachtNietVoor.containsKey(_soortSleutel(v.pad))) continue;\n'));
    expect(
      o,
      contains('          if (hits == null || _soortKandidaten(v, hits).isEmpty) {\n'),
      reason: 'niets in de plaat voor dit nummer: alsnog per nummer',
    );
    expect(
      o,
      contains(
        '        if (v.vanzelf && nietGezocht.contains(v) && nogNiet.contains(v) && !uitTorrents.contains(v)) {\n',
      ),
    );
  });
}
