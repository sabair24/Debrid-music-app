/// De cd komt uit de hoes, en de plaat gaat pas open als hij eruit is.
///
/// **Waarvoor dit bestaat.** Gevraagd op 10-09-2026: *"bij artiesten pagina bij hun albums wil ik
/// als ik op een album klik, de cd uit de albumhoes schuift. nu is er enkel de album hoes."*
///
/// De twee dingen die hier stuk kunnen gaan zonder dat iemand het merkt:
///
/// * **de tik opent de pagina niet meer**, omdat de animatie ervoor gaat staan — dan is een tegel
///   een plaatje geworden;
/// * **het geheel loopt buiten de cel**, want een rastercel is precies zo breed als de hoes. Daarom
///   schaalt het terug terwijl de plaat naar buiten komt; zonder dat tekent de cd over de buurtegel
///   heen, en welke van de twee bovenop komt hangt af van de volgorde in het raster.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';

const _maat = 160.0;

Widget _hoes(double m) => SizedBox(width: m, height: m, child: const ColoredBox(color: Colors.red));

Future<int> _toon(WidgetTester t, {required void Function() bijOpen}) async {
  var n = 0;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _maat,
          height: _maat,
          child: SchuivendeHoes(
            maat: _maat,
            hoes: _hoes,
            onOpen: () {
              n++;
              bijOpen();
            },
          ),
        ),
      ),
    ),
  ));
  return n;
}

void main() {
  testWidgets('in rust steekt er niets uit', (t) async {
    await _toon(t, bijOpen: () {});
    // De hoes vult de cel precies; alles wat de schijf is zit erachter.
    final vak = t.getSize(find.byType(SchuivendeHoes));
    expect(vak.width, _maat);
    expect(vak.height, _maat);
  });

  testWidgets('een tik schuift de cd eruit en opent DAARNA pas', (t) async {
    var geopend = 0;
    await _toon(t, bijOpen: () => geopend++);

    await t.tap(find.byType(SchuivendeHoes));
    await t.pump(); // de animatie start
    await t.pump(const Duration(milliseconds: 120));
    expect(geopend, 0, reason: 'halverwege de schuif hoort er nog niets open te gaan');

    await t.pump(const Duration(milliseconds: 260));
    await t.pumpAndSettle();
    expect(geopend, 1, reason: 'zodra de cd eruit is gaat de plaat open');
  });

  testWidgets('twee keer tikken opent één keer', (t) async {
    var geopend = 0;
    await _toon(t, bijOpen: () => geopend++);
    await t.tap(find.byType(SchuivendeHoes));
    await t.pump(const Duration(milliseconds: 40));
    await t.tap(find.byType(SchuivendeHoes));
    await t.pumpAndSettle();
    expect(geopend, 1);
  });

  testWidgets('hoes én cd blijven binnen de cel', (t) async {
    // Dit is de reden dat het geheel terugschaalt. Loopt het buiten de cel, dan tekent de cd over de
    // buurtegel heen — en in een raster is dat soms wél en soms niet zichtbaar.
    await _toon(t, bijOpen: () {});
    await t.tap(find.byType(SchuivendeHoes));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    final vak = t.getRect(find.byType(SchuivendeHoes));
    // Elke getekende laag binnen de tegel moet binnen dat vak blijven.
    for (final f in [find.byType(SizedBox), find.byType(ColoredBox)]) {
      for (final e in t.elementList(f)) {
        final r = t.getRect(find.byElementPredicate((x) => identical(x, e)));
        if (r.isEmpty) continue;
        expect(r.left, greaterThanOrEqualTo(vak.left - 0.5));
        expect(r.right, lessThanOrEqualTo(vak.right + 0.5),
            reason: 'niets mag rechts uit de cel steken');
      }
    }
  });
}
