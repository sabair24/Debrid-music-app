/// Nu speelt dekt het scherm eronder af zodra het open is.
///
/// **Saber op 08-10-2026:** *"ik teste gisteren de app op de ipad en die werd enorm heet bij de now
/// playing screen"*. De route stond op `opaque: false`, "zodat het scherm eronder blijft staan
/// terwijl dit omhoog schuift". Dan blijft dat scherm ook ná het schuiven meedoen: Flutter tekent de
/// startpagina, de glazen bovenbalk en de hoezen bij elk beeld van de draaiende cd opnieuw, achter
/// een scherm dat ze volledig bedekt, en hun animaties lopen door op het schermritme. Op de iPad
/// (120 Hz, veel pixels, en het glas vervaagt daar echt) is dat warmte zonder één zichtbaar pixel.
///
/// Wat hier vastligt: tijdens het open- en dichtschuiven staat het scherm eronder er (de reden
/// waarom de route ooit doorzichtig werd), en zodra hij open is staat het uit beeld en stil.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart' show nuSpeeltRoute;

/// Een scherm met een animatie die altijd doorloopt — zoals de glans van de laadtegels.
class _Onder extends StatefulWidget {
  const _Onder({required this.opTik});
  final VoidCallback opTik;
  @override
  State<_Onder> createState() => _OnderState();
}

class _OnderState extends State<_Onder> with SingleTickerProviderStateMixin {
  late final Ticker _t;

  @override
  void initState() {
    super.initState();
    _t = createTicker((_) => widget.opTik())..start();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: Key('onder'));
}

void main() {
  late GlobalKey<NavigatorState> nav;
  late int tikken;

  Future<void> start(WidgetTester tester) async {
    nav = GlobalKey<NavigatorState>();
    tikken = 0;
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: _Onder(opTik: () => tikken++)));
    nav.currentState!.push(nuSpeeltRoute(
        scherm: (_) => const ColoredBox(color: Colors.black, child: SizedBox.expand(key: Key('nu')))));
    await tester.pump();
  }

  testWidgets('DE GRENS: tijdens het omhoog schuiven staat het scherm eronder er nog', (tester) async {
    await start(tester);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('onder')), findsOneWidget,
        reason: 'anders schuift Nu speelt over een zwart vlak omhoog');
    expect(find.byKey(const Key('nu')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('DE KERN: open = het scherm eronder uit beeld, en zijn animaties staan stil', (tester) async {
    await start(tester);
    await tester.pump(const Duration(milliseconds: 400)); // ruim voorbij de 320 ms van de overgang
    await tester.pump();
    expect(find.byKey(const Key('onder')), findsNothing,
        reason: 'een bedekt scherm dat bij elk beeld meegetekend wordt, is de warmte op de iPad');
    final na = tikken;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tikken, na, reason: 'de glans van de laadtegels eronder liep door op 120 Hz');
  });

  testWidgets('DE GRENS: bij het dichtschuiven is het scherm eronder er meteen weer, en loopt het', (tester) async {
    await start(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('onder')), findsOneWidget);
    final tijdens = tikken;
    await tester.pump(const Duration(milliseconds: 16));
    expect(tikken, greaterThan(tijdens));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('nu')), findsNothing);
  });

  test('DE KERN: de echte route is ondoorzichtig', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final begin = main.indexOf('Route<void> nuSpeeltRoute(');
    expect(begin, isNonNegative);
    final lijf = main.substring(begin, main.indexOf('\n    );\n', begin));
    expect(lijf, contains('opaque: true,'));
    expect(lijf, isNot(contains('opaque: false')));
  });
}
