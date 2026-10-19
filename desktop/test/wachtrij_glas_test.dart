// De wachtrij op glas (Saber, 18-10-2026): pc een glazen paneel naast de inhoud, gsm een glazen blad,
// het spelende nummer een glazen eiland met een gekantelde hoes en een draaiend plaatje.
import 'dart:io';
import 'dart:math' as math;

import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/glas.dart';
import 'package:debridmusic/ui/wachtrij_eiland.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _eiland({required bool speelt, bool minderBeweging = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: minderBeweging),
        child: Scaffold(
          body: SizedBox(
            width: 340,
            child: WachtrijEiland(hoes: null, speelt: speelt, child: const Text('Soldier')),
          ),
        ),
      ),
    );

double _hoek(WidgetTester t) {
  final draai = t.widget<Transform>(
      find.descendant(of: find.byKey(const ValueKey('wachtrij-plaatje')), matching: find.byType(Transform)).first);
  final m = draai.transform;
  return math.atan2(m.entry(1, 0), m.entry(0, 0));
}

void main() {
  tearDown(() {
    setTvModeForTest(false);
    GlasKwaliteit.vergeet();
  });

  testWidgets('een glazen eiland met een hoes die zes graden kantelt', (t) async {
    await t.pumpWidget(_eiland(speelt: false));
    expect(find.descendant(of: find.byKey(const ValueKey('wachtrij-eiland')), matching: find.byType(GlasVlak)),
        findsOneWidget);
    final hoes = t.widget<Transform>(find.byKey(const ValueKey('wachtrij-hoes')));
    // rotateY(a): entry(0,2) = sin(a).
    expect(math.asin(hoes.transform.entry(0, 2)).abs(), closeTo(kEilandKanteling, 1e-6));
    expect(kEilandKanteling, closeTo(6 * math.pi / 180, 1e-9), reason: 'Saber: ±6°');
  });

  testWidgets('het plaatje draait zolang er muziek speelt, negen seconden per omwenteling', (t) async {
    await t.pumpWidget(_eiland(speelt: true));
    await t.pump(const Duration(milliseconds: 16));
    final a = _hoek(t);
    // In stapjes van een beeld: één tik telt hooguit een halve seconde (LangzameDraai).
    for (var i = 0; i < 45; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    final b = _hoek(t);
    // 720 ms van 9 s = 28,8 graden.
    final graden = ((b - a) * 180 / math.pi) % 360;
    expect(graden, closeTo(28.8, 2));
  });

  testWidgets('stil als er niets speelt', (t) async {
    await t.pumpWidget(_eiland(speelt: false));
    final a = _hoek(t);
    await t.pump(const Duration(seconds: 1));
    expect(_hoek(t), a);
    expect(t.binding.hasScheduledFrame, isFalse, reason: 'geen lus die om beelden vraagt');
  });

  testWidgets('stil op een tv, en stil bij minder beweging', (t) async {
    setTvModeForTest(true);
    await t.pumpWidget(_eiland(speelt: true));
    final a = _hoek(t);
    await t.pump(const Duration(seconds: 1));
    expect(_hoek(t), a, reason: 'de Shield betaalt elke lus');
    setTvModeForTest(false);
    await t.pumpWidget(_eiland(speelt: true, minderBeweging: true));
    final b = _hoek(t);
    await t.pump(const Duration(seconds: 1));
    expect(_hoek(t), b);
  });

  test('aangesloten: pc-paneel en gsm-blad op glas, het blad maakt het glas eronder dicht', () {
    final bron = File('lib/main.dart').readAsStringSync();
    final paneel = bron.indexOf("key: const ValueKey('wachtrij-glas'),");
    expect(paneel, greaterThan(0));
    expect(bron.substring(paneel, paneel + 300), contains('child: const WachtrijPaneelView(opGlas: true),'));
    final blad = bron.indexOf("key: const ValueKey('wachtrij-blad'),");
    expect(blad, greaterThan(0));
    final stuk = bron.substring(blad, blad + 300);
    expect(stuk, contains('bovenop: true,'));
    expect(stuk, contains('WachtrijPaneelView(inBlad: true, opGlas: true)'));
    expect(bron, contains('return WachtrijEiland('));
    // De echte cd, uit dezelfde map als Nu speelt, en anders de getekende plaat met de hoes als etiket
    // (Saber, 18-10-2026: "In de wachtrij wil ik ook de cd afbeelding zien, nu is het zwart").
    final regel = bron.indexOf('class _NuSpeeltRegelState extends State<_NuSpeeltRegel> {');
    expect(regel, greaterThan(0));
    final lijf = bron.substring(regel, regel + 3200);
    expect(lijf, contains('final v = albumArtVooruit(bib, al);'));
    expect(lijf, contains("key: const ValueKey('wachtrij-cd-scan'),"));
    expect(lijf, contains(': (m) => _GetekendeSchijf(label: cover, maat: m, vinyl: vinyl),'));
  });
}
