/// Het lijntje is er alleen als er iets gebeurt.
///
/// Klein, maar precies daarom de moeite: een balk die blijft staan als er niets loopt is erger dan
/// geen balk, want dan geloof je hem niet meer.
library;

import 'package:debridmusic/facts_warmer.dart';
import 'package:debridmusic/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _omhulsel(Widget kind) => MaterialApp(home: Scaffold(body: Center(child: kind)));

/// Het lopende streepje van [BusyLine].
final _streep = find.byKey(const ValueKey('werkstreep'));

void main() {
  setUp(() => FactsWarmer.busyAlbum.value = null);
  tearDown(() => FactsWarmer.busyAlbum.value = null);

  testWidgets('niets aan de hand, dus geen balk en geen ruimte', (t) async {
    await t.pumpWidget(_omhulsel(const BusyLine(busy: false)));
    expect(_streep, findsNothing);
    // Geen hoogte: anders verschuift een tegel twee pixels op het moment dat hij aan de beurt komt.
    expect(t.getSize(find.byType(SizedBox).first).height, 0);
  });

  testWidgets('bezig, dus een balk van twee pixels', (t) async {
    await t.pumpWidget(_omhulsel(const BusyLine(busy: true)));
    expect(_streep, findsOneWidget);
    expect(t.getSize(_streep).height, 2);
  });

  testWidgets('de warmer stuurt hem aan, en alleen voor de juiste plaat', (t) async {
    await t.pumpWidget(_omhulsel(const WarmingLine(uid: 'abc')));
    expect(_streep, findsNothing);

    FactsWarmer.busyAlbum.value = 'xyz'; // een andere plaat
    await t.pump();
    expect(_streep, findsNothing);

    FactsWarmer.busyAlbum.value = 'abc';
    await t.pump();
    expect(_streep, findsOneWidget);

    FactsWarmer.busyAlbum.value = null;
    await t.pump();
    expect(_streep, findsNothing,
        reason: 'klaar is klaar — de balk hoort te verdwijnen, niet te blijven staan');
  });

  testWidgets('een plaat zonder uid krijgt nooit een balk', (t) async {
    // uidOf() geeft een lege string voor een plaat die er nog geen heeft; zonder deze regel zouden
    // die allemaal tegelijk oplichten zodra de warmer null is.
    await t.pumpWidget(_omhulsel(const WarmingLine(uid: '')));
    FactsWarmer.busyAlbum.value = '';
    await t.pump();
    expect(_streep, findsNothing);
  });

  testWidgets('het streepje vraagt geen beeld per schermtik', (t) async {
    // Een LinearProgressIndicator liet op 144 Hz het hele scherm 144 keer per seconde tekenen.
    await t.pumpWidget(_omhulsel(const BusyLine(busy: true)));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(_streep, findsOneWidget);
    await t.pumpWidget(_omhulsel(const BusyLine(busy: false)));
  });
}
