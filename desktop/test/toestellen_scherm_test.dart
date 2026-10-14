import 'dart:async';
import 'dart:io';

import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/toestellen_lijst.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// De toestellenlijst op de pc: één toestel intrekken, na bevestigen, en de rest blijft.
///
/// Apart van `toestellen_lijst_test`: een bestand met `testWidgets` krijgt een nep-HTTP-client die
/// altijd 400 antwoordt, en die toetsen praten met een echte server.
const _gsm = '0123456789abcdef0123456789abcdef';

void main() {
  late Directory map;
  setUp(() => map = Directory.systemTemp.createTempSync('dm_lijst_'));
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('een toestel intrekken, na bevestigen, en de rest blijft', (tester) async {
    final g = GrantStore(file: File('${map.path}/grants.json'));
    final gsm = g.nieuweSleutel(deviceId: _gsm, deviceName: 'S26').token;
    final ipad = g.nieuweSleutel(deviceId: 'ipad-van-saber-01', deviceName: 'iPad', metTls: true).token;
    g.adoptLegacyToken('de-gedeelde');
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ToestellenLijst(grants: g)))));

    expect(find.text('S26'), findsOneWidget);
    expect(find.text('iPad'), findsOneWidget);
    expect(find.text('Eerder gekoppelde apparaten'), findsOneWidget);
    // Tot elk toestel 'versleuteld' toont, laat je Tailscale staan: dus per toestel zichtbaar.
    expect(find.textContaining('versleuteld'), findsOneWidget, reason: 'alleen de iPad heeft een TLS-sleutel');
    expect(find.widgetWithText(TextButton, 'Intrekken'), findsNWidgets(2),
        reason: 'de gedeelde sleutel trek je in met "Nieuwe toegangscode", niet hier');

    // Eerst annuleren: er gebeurt niets.
    await tester.tap(find.widgetWithText(TextButton, 'Intrekken').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(g.accepts(gsm), isTrue);
    expect(g.accepts(ipad), isTrue);

    // Dan echt, op de rij van de iPad. Niet "de bovenste": de lijst staat op koppeltijd, en twee
    // sleutels uit dezelfde milliseconde hebben dezelfde — dan stond de gsm bovenaan en werd die
    // ingetrokken (rood in de volledige lijst op 14-10-2026, groen als losse toets).
    final rijVanIpad = find.ancestor(of: find.text('iPad'), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: rijVanIpad, matching: find.widgetWithText(TextButton, 'Intrekken')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Intrekken'));
    await tester.pump();
    // Het wegschrijven is echte schijf-IO, begonnen in de nep-tijd van de toets: afwisselend echte
    // tijd (voor de schijf) en een pomp (voor de microtaken die erachter wachten), tot het klaar is.
    var klaar = false;
    unawaited(g.wachtOpOpslaan().then((_) => klaar = true));
    for (var i = 0; i < 100 && !klaar; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(klaar, isTrue, reason: 'het opslaan na intrekken kwam niet rond');
    await tester.pumpAndSettle();

    expect(g.accepts(ipad), isFalse);
    expect(g.accepts(gsm), isTrue, reason: 'je andere toestellen merken niets');
    expect(find.text('iPad'), findsNothing);
    expect(find.text('S26'), findsOneWidget);
  });
}
