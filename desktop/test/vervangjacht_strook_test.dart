/// Wat de strook op de Kwaliteitspagina ZEGT, in de standen die er echt voorkomen.
///
/// Geen gouden plaatje maar de tekst: die is wat er te lezen valt en wat er misging. De strook is
/// gebouwd omdat de knop "Laat de app zoeken" 173 nummers op de verlanglijst zette en daarna
/// zweeg — alles wat er gebeurde stond alleen in `downloads.log`. De valkuil die hier vastgepind
/// wordt is de STILTE: verreweg de meeste tijd loopt er geen ronde, en juist dan moet er iets
/// staan.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';
import 'package:debridmusic/vervangjacht.dart';

final _nu = DateTime(2026, 9, 8, 18, 40);

Future<void> _toon(WidgetTester t, VervangJacht j) => t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [VervangJachtStrook(jacht: j, nu: _nu)]),
      ),
    ));

void main() {
  testWidgets('tijdens een ronde: wie er aan de beurt is en waar de balk staat', (t) async {
    await _toon(
        t,
        VervangJacht(
          opDeLijst: 165,
          dezeBeurt: 6,
          gedaan: 2,
          poging: 3,
          maxPoging: 6,
          bezigMet: 'Vengaboys — Uncle John From Jamaica',
          regel: 'Vervalsing betrapt bij diamondbyte.org — weggegooid.',
          binnen: 2,
          weggegooid: 10,
          volgendeOm: _nu.add(const Duration(minutes: 12)),
        ));

    expect(find.text('Zoekt een echte kopie — 3 van 6 deze ronde'), findsOneWidget);
    expect(find.text('165 op de verlanglijst'), findsOneWidget);
    expect(find.text('Vengaboys — Uncle John From Jamaica · kandidaat 3 van 6'), findsOneWidget);
    expect(find.text('Vervalsing betrapt bij diamondbyte.org — weggegooid.'), findsOneWidget);
    expect(find.text('2 echte kopieën binnen · 10 vervalsingen betrapt en weggegooid'),
        findsOneWidget);

    final balk = t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(balk.value, closeTo((2 + 2 / 6) / 6, 0.0001));
  });

  testWidgets('tussen twee rondes telt dezelfde balk af', (t) async {
    // Dit is de stand die het vaakst op het scherm staat: zes wensen per ronde, twintig minuten
    // ertussen. Een strook die dan verdwijnt laat precies in die stilte niets zien.
    await _toon(
        t,
        VervangJacht(
          opDeLijst: 164,
          regel: 'Echte kopie binnen voor Gorki — Anja.',
          binnen: 1,
          weggegooid: 11,
          volgendeOm: _nu.add(const Duration(minutes: 5)),
        ));

    expect(find.text('Volgende ronde over 5 min'), findsOneWidget);
    expect(find.text('164 op de verlanglijst'), findsOneWidget);
    expect(find.text('1 echte kopie binnen · 11 vervalsingen betrapt en weggegooid'), findsOneWidget,
        reason: 'één is geen "kopie(ën)"');

    // Driekwart van de twintig minuten is om.
    final balk = t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(balk.value, closeTo(0.75, 0.0001));
  });

  testWidgets('af is af: volle balk, geen aftelling', (t) async {
    await _toon(t, const VervangJacht(opDeLijst: 0, binnen: 44, weggegooid: 96));
    expect(find.text('Niets meer te vervangen'), findsOneWidget);
    expect(find.textContaining('op de verlanglijst'), findsNothing);
    final balk = t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(balk.value, 1.0, reason: 'een lege balk onder "niets meer te vervangen" leest als nul');
  });

  testWidgets('niets te melden is geen strook', (t) async {
    // Wie nooit gemeten heeft hoort hier geen leeg kadertje te zien.
    await _toon(t, const VervangJacht(opDeLijst: 0));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
