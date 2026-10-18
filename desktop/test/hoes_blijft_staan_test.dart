// De hoes blijft dezelfde hoes tijdens omdraaien en kantelen (gsm 18-10-2026: "de hoes flipt niet om",
// op Nu speelt en de albumpagina). De oorzaak: drie lagen veranderden van vorm bij het begin en eind van
// een draai of een kanteling, en dan gooit Flutter de hoes eronder weg en bouwt hem opnieuw.
import 'dart:io';

import 'package:debridmusic/ui/draaihoes.dart';
import 'package:debridmusic/ui/kantel_hoes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _gebouwd = 0;

class _Hoes extends StatefulWidget {
  const _Hoes(this.tekst);
  final String tekst;
  @override
  State<_Hoes> createState() => _HoesState();
}

class _HoesState extends State<_Hoes> {
  @override
  void initState() {
    super.initState();
    _gebouwd++;
  }

  @override
  Widget build(BuildContext context) => ColoredBox(color: const Color(0xFF884422), child: Text(widget.tekst));
}

void main() {
  setUp(() => _gebouwd = 0);

  testWidgets('omdraaien en terug: voor- en achterkant worden één keer gebouwd', (t) async {
    final c = DraaiHoesController();
    await t.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 200,
          child: DraaiHoes(controller: c, voor: const _Hoes('voor'), achter: const _Hoes('achter')),
        ),
      ),
    ));
    expect(_gebouwd, 2);
    c.draai(heeftAchterkant: true);
    await t.pumpAndSettle();
    expect(find.text('achter'), findsOneWidget);
    c.draai(heeftAchterkant: true);
    await t.pumpAndSettle();
    expect(find.text('voor'), findsOneWidget);
    expect(_gebouwd, 2, reason: 'geen van beide kanten opnieuw gebouwd');
  });

  testWidgets('kantelen en weer recht: de hoes eronder blijft dezelfde', (t) async {
    Widget doos(bool aan) => MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 200,
              child: KantelHoes(bron: KantelBron.selectie, aan: aan, child: const _Hoes('hoes')),
            ),
          ),
        );
    await t.pumpWidget(doos(false));
    await t.pumpWidget(doos(true));
    await t.pump(kKantelVolg);
    await t.pumpWidget(doos(false));
    await t.pump(kKantelVolg);
    expect(_gebouwd, 1);
  });

  test('de lagen van de grote hoes hebben een sleutel', () {
    final bron = File('lib/main.dart').readAsStringSync();
    for (final k in ['albumart-spiegel', 'albumart-schijf', 'albumart-hoes']) {
      expect(bron, contains("key: const ValueKey('$k')"), reason: k);
    }
  });
}
