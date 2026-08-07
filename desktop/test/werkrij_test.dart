/// De wachtrij die de opwaardeerjachten parallel laat lopen.
///
/// Dit is code die stil kapotgaat. Een teller die één keer niet zakt en de rij loopt nooit meer
/// leeg — geen foutmelding, geen crash, gewoon een app die niets meer opwaardeert en waarvan je dat
/// pas dagen later merkt. Daarom staan de foutgevallen hier net zo hard in als de gewone.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/werkrij.dart';

void main() {
  test('laat er niet meer dan het maximum tegelijk lopen', () async {
    final rij = Werkrij(3);
    var tegelijk = 0, hoogste = 0, klaar = 0;
    final poorten = <Completer<void>>[];

    for (var i = 0; i < 10; i++) {
      final poort = Completer<void>();
      poorten.add(poort);
      rij.voegToe(() async {
        tegelijk++;
        if (tegelijk > hoogste) hoogste = tegelijk;
        await poort.future;
        tegelijk--;
        klaar++;
      });
    }

    await Future<void>.delayed(Duration.zero);
    expect(rij.lopend, 3, reason: 'drie lopen, de rest wacht');
    expect(rij.wachtend, 7);
    expect(hoogste, 3);

    // Eén afmaken maakt precies één plaats vrij.
    poorten[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(rij.lopend, 3);
    expect(rij.wachtend, 6);

    for (final p in poorten) {
      if (!p.isCompleted) p.complete();
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
    expect(klaar, 10, reason: 'alles moet uiteindelijk gelopen hebben');
    expect(hoogste, 3, reason: 'en nooit meer dan drie tegelijk');
    expect(rij.lopend, 0);
    expect(rij.wachtend, 0);
  });

  test('werk dat gooit vergiftigt de rij niet', () async {
    // Zonder de `finally` zakt de teller bij elke fout met één en beweegt er na drie fouten
    // helemaal niets meer. Dat is de storing die je pas dagen later opmerkt.
    final rij = Werkrij(2);
    var gelukt = 0;
    for (var i = 0; i < 6; i++) {
      rij.voegToe(() async {
        if (i.isEven) throw StateError('kapot werkstuk $i');
        gelukt++;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gelukt, 3, reason: 'de drie oneven werkstukken horen gewoon gelopen te hebben');
    expect(rij.lopend, 0, reason: 'de teller moet weer op nul staan');
    expect(rij.wachtend, 0);
  });

  test('werk dat er tijdens het lopen bij komt wordt opgepikt', () async {
    // Zo werkt het in het echt: elke landing zet zijn eigen jacht in de rij, één voor één, terwijl
    // er al jachten lopen.
    final rij = Werkrij(2);
    var klaar = 0;
    for (var i = 0; i < 2; i++) {
      rij.voegToe(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        klaar++;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
    rij.voegToe(() async => klaar++);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(klaar, 3);
    expect(rij.lopend, 0);
  });

  test('met maximum één gedraagt hij zich als vroeger: strikt na elkaar', () async {
    final rij = Werkrij(1);
    final volgorde = <int>[];
    for (var i = 0; i < 4; i++) {
      rij.voegToe(() async {
        volgorde.add(i);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(volgorde, [0, 1, 2, 3], reason: 'in de rijvolgorde, één voor één');
  });

  test('een lege rij aantrekken doet niets en laat de teller met rust', () async {
    final rij = Werkrij(3);
    expect(rij.lopend, 0);
    expect(rij.wachtend, 0);
    rij.voegToe(() async {});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(rij.lopend, 0);
    expect(rij.wachtend, 0);
  });
}
