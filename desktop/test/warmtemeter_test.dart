/// De meetlat voor een toestel dat heet wordt.
///
/// **Waarom.** 10-10-2026: de iPad werd "extreem warm, eigenlijk overal". Een iPad hangt niet aan adb
/// en stuurde geen logboeken; de reparatie van 3.9.454 rustte daardoor op redenering en hielp niet
/// genoeg. Wat hier vastligt: dat de meetlat de animaties ziet die elk schermbeeld een nieuw beeld
/// vragen (en de stilstaande niet), dat hij zegt waar ze staan, en dat er niets verloren gaat als de
/// pc even weg is. Dat de regels op de pc aankomen staat in `warmte_log_test.dart`.
library;

import 'dart:io';

import 'package:debridmusic/ui/langzame_draai.dart';
import 'package:debridmusic/warmtemeter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een eigen scherm met een draaiende plaat, zoals "Nu speelt".
class _ProefScherm extends StatefulWidget {
  const _ProefScherm({this.draait = true, this.metEindeloos = false, this.uitgezet = false});
  final bool draait;
  final bool metEindeloos;
  final bool uitgezet;
  @override
  State<_ProefScherm> createState() => _ProefSchermState();
}

class _ProefSchermState extends State<_ProefScherm> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void initState() {
    super.initState();
    if (widget.draait) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          TickerMode(
            enabled: !widget.uitgezet,
            child: _Plaat(animatie: CurvedAnimation(parent: _c, curve: Curves.linear)),
          ),
          if (widget.metEindeloos) const CircularProgressIndicator(),
          const CircularProgressIndicator(value: 0.4),
          const _Glas(),
        ]),
      );
}

class _Plaat extends StatelessWidget {
  const _Plaat({required this.animatie});
  final Animation<double> animatie;
  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: animatie, child: const SizedBox(width: 40, height: 40));
}

class _Glas extends StatelessWidget {
  const _Glas();
  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ColorFilter.mode(Colors.black.withValues(alpha: 0.1), BlendMode.srcOver),
          child: const SizedBox(width: 20, height: 20),
        ),
      );
}

void main() {
  group('loopt deze animatie?', () {
    testWidgets('een herhalende controller loopt, een stilgezette niet', (tester) async {
      final c = AnimationController(vsync: const TestVSync(), duration: const Duration(seconds: 1));
      addTearDown(c.dispose);
      expect(animatieLoopt(c), isFalse);
      c.repeat();
      expect(animatieLoopt(c), isTrue);
      expect(animatieLoopt(CurvedAnimation(parent: c, curve: Curves.ease)), isTrue,
          reason: 'door de curve heen naar de controller');
      expect(animatieLoopt(ReverseAnimation(c)), isTrue);
      expect(animatieLoopt(Tween(begin: 0.0, end: 1.0).animate(c)), isTrue);
      c.stop();
      expect(animatieLoopt(CurvedAnimation(parent: c, curve: Curves.ease)), isFalse,
          reason: 'een stilgezette controller blijft op "forward" staan — dat is geen lopen');
    });

    test('een altijd-stilstaande animatie staat op forward, maar loopt niet', () {
      const a = AlwaysStoppedAnimation<double>(0.5);
      expect(a.status, AnimationStatus.forward);
      expect(animatieLoopt(a), isFalse);
    });

    testWidgets('de draaiende cd telt mee', (tester) async {
      final d = LangzameDraai(const TestVSync(), omwenteling: const Duration(seconds: 9));
      addTearDown(d.dispose);
      expect(animatieLoopt(d), isFalse);
      d.start();
      expect(animatieLoopt(d), isTrue);
      d.stop();
      expect(animatieLoopt(d), isFalse);
    });
  });

  group('DE KERN: de boom zegt welke animaties lopen, en waar', () {
    testWidgets('de draaiende plaat, met zijn eigen widget en zijn scherm', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _ProefScherm()));
      await tester.pump(const Duration(milliseconds: 50));
      final t = lopendeAnimaties(tester.binding.rootElement!);
      expect(t.animaties.keys.where((k) => k.startsWith('RotationTransition')), hasLength(1),
          reason: '${t.animaties}');
      final plek = t.animaties.keys.firstWhere((k) => k.startsWith('RotationTransition'));
      expect(plek.contains('_Plaat'), isTrue, reason: plek);
      expect(plek.contains('_ProefScherm'), isTrue, reason: plek);
      expect(t.glas, 1);
    });

    testWidgets('stil is stil', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _ProefScherm(draait: false)));
      await tester.pumpAndSettle();
      expect(lopendeAnimaties(tester.binding.rootElement!).animaties, isEmpty,
          reason: 'een voortgangsbalk mét waarde en een stilstaande plaat vragen geen beelden');
    });

    testWidgets('een eindeloze draaier telt, een met waarde niet', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _ProefScherm(draait: false, metEindeloos: true)));
      await tester.pump(const Duration(milliseconds: 50));
      final keys = lopendeAnimaties(tester.binding.rootElement!).animaties.keys.toList();
      expect(keys, hasLength(1), reason: '$keys');
      expect(keys.single.startsWith('CircularProgressIndicator (eindeloos)'), isTrue, reason: keys.single);
    });

    testWidgets('onder een uitgezette TickerMode tikt niets', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _ProefScherm(uitgezet: true)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(lopendeAnimaties(tester.binding.rootElement!).animaties, isEmpty);
    });
  });

  group('de regel', () {
    test('alles wat erin moet', () {
      final r = warmteRegel(const Warmtestaal(
        ms: 10000,
        beelden: 600,
        buildGemUs: 1200,
        buildMaxUs: 4500,
        rasterGemUs: 6100,
        rasterMaxUs: 15200,
        draadVertraagdMs: 340,
        tikkers: 2,
        animaties: {'RotationTransition in _Plaat': 1, 'Skelet in _Lijst': 3},
        glas: 4,
        extra: 'speelt',
        toestel: 'warmte normaal, batterij 54 % laadt',
      ));
      expect(
          r,
          '60.0 beelden/s (600 in 10.0 s) | bouwen 1.2/4.5 ms | rasteren 6.1/15.2 ms | '
          'draad vertraagd 340 ms | tikkers 2 | glas 4 | '
          'animaties: Skelet in _Lijst ×3, RotationTransition in _Plaat | speelt | '
          'warmte normaal, batterij 54 % laadt');
    });

    test('de warmtestand van iOS in woorden', () {
      expect(toestelstandTekst(warmte: 0, batterij: 0.54, laden: 2), 'warmte normaal, batterij 54 % laadt');
      expect(toestelstandTekst(warmte: 2, batterij: 0.9, laden: 1),
          'warmte WARM (iOS remt af), batterij 90 % op batterij');
      expect(toestelstandTekst(warmte: 3, batterij: -1, laden: 0), 'warmte HEET (kritiek), batterij ?');
    });
  });

  group('versturen', () {
    testWidgets('na drie vensters één zending, en een mislukte zending blijft bewaard', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _ProefScherm(draait: false)));
      final zendingen = <List<String>>[];
      var pcWeg = true;
      final m = Warmtemeter(
        stuur: (r) async {
          if (pcWeg) throw const SocketException('pc slaapt');
          zendingen.add(r);
        },
        toestelstand: () async => null,
      );
      final wortel = tester.binding.rootElement!;
      await tester.runAsync(() async {
        for (var i = 0; i < 3; i++) {
          await m.sluitVenster(wortel: wortel);
        }
      });
      expect(zendingen, isEmpty);
      expect(m.wachtend, hasLength(3), reason: 'de pc was weg: niets kwijt');
      pcWeg = false;
      await tester.runAsync(() async {
        for (var i = 0; i < 3; i++) {
          await m.sluitVenster(wortel: wortel);
        }
      });
      expect(zendingen.single, hasLength(6));
      expect(m.wachtend, isEmpty);
    });

    testWidgets('een pc die lang weg is laat hoogstens 60 regels wachten', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _ProefScherm(draait: false)));
      final m = Warmtemeter(
          stuur: (_) async => throw const SocketException('weg'), toestelstand: () async => null);
      final wortel = tester.binding.rootElement!;
      await tester.runAsync(() async {
        for (var i = 0; i < Warmtemeter.kBewaar + 9; i++) {
          await m.sluitVenster(wortel: wortel);
        }
      });
      expect(m.wachtend, hasLength(Warmtemeter.kBewaar));
    });
  });
}
