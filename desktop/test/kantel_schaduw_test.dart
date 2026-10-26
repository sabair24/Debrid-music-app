// De hoes stilzetten, en een schaduw en spiegeling die realistisch meebewegen met de kanteling (Saber, 26-10-2026: "de
// tilt van de album kunnen lokken, want zeker met de gsm en ik rijd met de auto of camionette, beweegt die hoes
// constant … Plus als ik tilt, gaat de schaduw en reflectie niet mee. Moet realistisch zijn. Dus dat is dan een
// reflectie en schaduw die bewegen anders dan de hoes en cd e").
import 'dart:async';
import 'dart:io';

import 'package:debridmusic/ui/kantel_hoes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _vak = Rect.fromLTWH(0, 0, 200, 200);

Offset _naar(Matrix4 m, Offset p) => MatrixUtils.transformPoint(m, p);

Widget _doos(Widget k) => MaterialApp(home: Center(child: SizedBox.square(dimension: 200, child: k)));

const _hoes = ColoredBox(color: Color(0xFF884422));

void main() {
  tearDown(() {
    KantelHoes.toestelVoorToets = null;
    KantelKeuze.vast.value = false;
  });

  group('de schaduw op de wand', () {
    test('DE KERN: de kant die naar je toe komt, werpt zijn schaduw verder; de kant die wegzakt dichtbij', () {
      // o.dx > 0: de rechterkant komt naar je toe (kantelMatrix: hij wordt groter).
      Offset hoek(Matrix4 m, Offset p) => MatrixUtils.transformPoint(
          Matrix4.identity()..translateByDouble(100, 100, 0, 1)..multiply(m)..translateByDouble(-100, -100, 0, 1), p);
      final h = kantelMatrix(const Offset(1, 0));
      expect(hoek(h, const Offset(200, 200)).dy - hoek(h, const Offset(200, 0)).dy,
          greaterThan(hoek(h, const Offset(0, 200)).dy - hoek(h, const Offset(0, 0)).dy),
          reason: 'de rechterrand is groter: hij komt naar je toe');
      final m = kantelSchaduwMatrix(const Offset(1, 0), _vak);
      const k = kKantelSchaduwHoogte * kKantelSchaduwDiepte;
      expect(_naar(m, const Offset(200, 100)).dy, closeTo(100 + k, 1e-9), reason: 'rechts verder van de wand');
      expect(_naar(m, const Offset(0, 100)).dy, closeTo(100 - k, 1e-9), reason: 'links dichter bij de wand');
      expect(_naar(m, const Offset(100, 100)), const Offset(100, 100), reason: 'het midden blijft');
      // Voorover en achterover: o.dy > 0, de onderkant komt naar je toe → zijn schaduw valt verder.
      final v = kantelSchaduwMatrix(const Offset(0, 1), _vak);
      expect(_naar(v, const Offset(100, 200)).dy, closeTo(200 + k, 1e-9));
      expect(_naar(v, const Offset(100, 0)).dy, closeTo(-k, 1e-9));
    });

    test('hij ligt op de wand: geen perspectief, niets verschuift opzij, en in rust niets', () {
      final m = kantelSchaduwMatrix(const Offset(.7, -.4), _vak);
      for (final c in [0, 1, 2]) {
        expect(m.entry(3, c), 0, reason: 'geen diepte');
      }
      for (final p in [Offset.zero, const Offset(200, 0), const Offset(37, 160)]) {
        expect(_naar(m, p).dx, p.dx, reason: 'het licht komt van boven: de schaduw valt alleen naar onder');
      }
      expect(kantelSchaduwMatrix(Offset.zero, _vak), Matrix4.identity());
      // En anders dan de hoes zelf, die wel in de diepte draait.
      expect(kantelMatrix(const Offset(.7, -.4)).entry(3, 2), isNot(0));
    });

    test('de spiegeling: dezelfde draai om de staande as, de omgekeerde om de liggende', () {
      const o = Offset(.6, -.8);
      expect(spiegelKantelMatrix(o), kantelMatrix(const Offset(.6, .8)));
      // De onderrand van de hoes en de bovenrand van zijn spiegelbeeld liggen gespiegeld rond de vloerlijn (y = 200): wat
      // de rand van de hoes omhoog gaat, gaat die van het spiegelbeeld omlaag, zoals bij een hoes die boven een vloer zweeft.
      final hoes = Matrix4.identity()
        ..translateByDouble(100, 100, 0, 1)
        ..multiply(kantelMatrix(o))
        ..translateByDouble(-100, -100, 0, 1);
      final spiegel = Matrix4.identity()
        ..translateByDouble(100, 300, 0, 1)
        ..multiply(spiegelKantelMatrix(o))
        ..translateByDouble(-100, -300, 0, 1);
      for (final x in [0.0, 100.0, 200.0]) {
        final onder = _naar(hoes, Offset(x, 200));
        final boven = _naar(spiegel, Offset(x, 200));
        expect(boven.dx, closeTo(onder.dx, 1e-6));
        expect(boven.dy - 200, closeTo(200 - onder.dy, 1e-6), reason: 'gespiegeld in de vloerlijn y = 200');
      }
    });

    testWidgets('VolgtKanteling: volgt de stand, en bouwt zijn kind nooit opnieuw', (t) async {
      final stand = ValueNotifier<Offset>(Offset.zero);
      var gebouwd = 0;
      final kind = Builder(builder: (_) {
        gebouwd++;
        return const SizedBox.square(dimension: 200);
      });
      await t.pumpWidget(_doos(VolgtKanteling.schaduw(stand: stand, hoes: _vak, child: kind)));
      Matrix4 nu() => t.widget<Transform>(find.byType(Transform).first).transform;
      expect(nu(), Matrix4.identity());
      stand.value = const Offset(1, 0);
      await t.pump();
      expect(nu(), kantelSchaduwMatrix(const Offset(1, 0), _vak));
      stand.value = Offset.zero;
      await t.pump();
      expect(nu(), Matrix4.identity());
      expect(gebouwd, 1);
    });
  });

  group('stilzetten', () {
    testWidgets('DE KERN: stilgezet luistert er geen melder en staat de hoes recht; weer aan: hij luistert', (t) async {
      final melder = StreamController<Offset>.broadcast();
      KantelHoes.toestelVoorToets = () => melder.stream;
      KantelKeuze.vast.value = true;
      await t.pumpWidget(_doos(const KantelHoes(bron: KantelBron.toestel, child: _hoes)));
      expect(melder.hasListener, isFalse, reason: 'vast = ook geen bewegingsmelder (batterij)');
      KantelKeuze.vast.value = false;
      await t.pump();
      expect(melder.hasListener, isTrue);
    });

    testWidgets('stilzetten terwijl hij schuin staat: hij gaat recht, en een wachtende stand kantelt hem niet terug',
        (t) async {
      final melder = StreamController<Offset>.broadcast();
      KantelHoes.toestelVoorToets = () => melder.stream;
      await t.pumpWidget(_doos(const KantelHoes(bron: KantelBron.toestel, child: _hoes)));
      for (var i = 0; i < 5; i++) {
        melder.add(const Offset(0, .5));
        await t.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 16; i++) {
        melder.add(const Offset(.17, .5));
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey('kantel-glans')), findsOneWidget, reason: 'hij staat schuin');
      melder.add(const Offset(.2, .5)); // een stand die nog wacht
      KantelKeuze.vast.value = true;
      // De animatie begint een beeld later; na ruim een kantelvolgtijd staat hij recht.
      await t.pump();
      await t.pump(kKantelVolg);
      await t.pump(const Duration(milliseconds: 100));
      expect(melder.hasListener, isFalse);
      expect(find.byKey(const ValueKey('kantel-glans')), findsNothing, reason: 'recht, ook na de wachtende stand');
    });

    test('aangesloten: in het ⋯-menu van Nu speelt op gsm en iPad, geladen bij het starten; schaduw en spiegeling volgen',
        () {
      final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(m, contains("        if (!isTv && !_isDesktop)\n          KantelKeuze.vast.value\n"));
      expect(m, contains("MenuRegel(Icons.lock_outline_rounded, 'Hoes stilzetten', () => KantelKeuze.zet(true))"));
      expect(m, contains("MenuRegel(Icons.screen_rotation_rounded, 'Hoes laten meebewegen', () => KantelKeuze.zet(false))"));
      expect(m, contains('  StapelKeuze.laad();\n  KantelKeuze.laad();\n'));
      final schaduw = m.indexOf("key: const ValueKey('albumart-schaduw'),");
      expect(m.substring(schaduw, schaduw + 700), contains('child: VolgtKanteling.schaduw(\n                  stand: _kantel,'));
      expect(m, contains('child: meeMetDeHoes(VolgtKanteling.spiegel(\n                    stand: _kantel, midden: Offset(s / 2, s / 2), child: HoesSpiegel(beeld: front, maat: s)))),'));
      expect(m, contains('transform: rust ? Matrix4.identity() : kantelSchaduwMatrix(o, hoesVak),\n                      child: grondschaduw,'));
    });
  });
}
