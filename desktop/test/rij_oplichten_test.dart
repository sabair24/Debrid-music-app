// Een rij licht op onder de muis, of onder de focus als je met toetsen bedient — nooit twee rijen door muis plus een
// achtergebleven focus (Saber, 25-10-2026: "het hoveren met een muis over de lijst is niet goed, soms 2 rijen in eens").
import 'dart:io';

import 'package:debridmusic/tv.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rij extends StatefulWidget {
  const _Rij(this.naam, this.focus);
  final String naam;
  final FocusNode focus;
  @override
  State<_Rij> createState() => _RijState();
}

class _RijState extends State<_Rij> with LichtBijMuisOfFocus {
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => muisErop(true),
        onExit: (_) => muisErop(false),
        child: Focus(
          focusNode: widget.focus,
          onFocusChange: focusErop,
          child: Container(
            key: ValueKey(widget.naam),
            height: 40,
            color: oplichten ? Colors.grey : Colors.transparent,
          ),
        ),
      );
}

bool _aan(WidgetTester t, String naam) => (t.widget<Container>(find.byKey(ValueKey(naam))).color) == Colors.grey;

void main() {
  tearDown(() => merkInvoer(toetsen: false));

  testWidgets('met de muis: de focus op rij A en de muis op rij B — alleen B licht op', (t) async {
    final a = FocusNode(), b = FocusNode();
    await t.pumpWidget(MaterialApp(home: Column(children: [_Rij('A', a), _Rij('B', b)])));
    merkInvoer(toetsen: false);
    a.requestFocus(); // bv. teruggekomen na een menu
    await t.pump();
    final muis = await t.createGesture(kind: PointerDeviceKind.mouse);
    await muis.addPointer(location: t.getCenter(find.byKey(const ValueKey('B'))));
    await t.pump();
    expect(_aan(t, 'A'), isFalse, reason: 'de focus telt niet als je met de muis bedient');
    expect(_aan(t, 'B'), isTrue);
    await muis.moveTo(t.getCenter(find.byKey(const ValueKey('A'))));
    await t.pump();
    expect(_aan(t, 'A'), isTrue);
    expect(_aan(t, 'B'), isFalse, reason: 'de muis is weg: meteen uit');
    await muis.removePointer();
  });

  testWidgets('met toetsen: de focus licht op', (t) async {
    final a = FocusNode(), b = FocusNode();
    await t.pumpWidget(MaterialApp(home: Column(children: [_Rij('A', a), _Rij('B', b)])));
    merkInvoer(toetsen: true);
    b.requestFocus();
    await t.pump();
    expect(_aan(t, 'B'), isTrue);
    expect(_aan(t, 'A'), isFalse);
  });

  test('aangesloten: de tracklijst en de kaarten, de muis en de toetsen gemeld, de rij zonder overgang', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    for (final k in [
      '_TrackRowState extends State<TrackRow>',
      '_MissingTrackRowState extends State<MissingTrackRow>',
      '_CreditChipState extends State<_CreditChip>',
      '_RelatedArtistCardState extends State<_RelatedArtistCard>',
      '_ArtistCardState extends State<_ArtistCard>',
    ]) {
      expect(main, contains('class $k with LichtBijMuisOfFocus {'), reason: k);
    }
    expect(main, isNot(contains('onFocusChange: (v) => setState(() => _hover = v),')),
        reason: 'één vlag voor muis en focus liet een rij aan staan');
    expect(main, contains('    if (!isTv) HardwareKeyboard.instance.addHandler(_merkToetsen);'));
    expect(main, contains('                      merkInvoer(toetsen: false);\n                    },'));
    final i = main.indexOf('class _TrackRowState');
    expect(main.substring(i, i + 6000), contains('          duration: Duration.zero,'));
  });
}
