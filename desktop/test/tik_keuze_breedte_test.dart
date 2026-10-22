// "Tikken op een nummer, als er al een wachtrij is" op de gsm: één letter per regel naast de keuzelijst (Saber,
// 22-10-2026, schermafdruk van de instellingen). De lijst is zo breed als zijn langste keuze. Op een smal scherm
// staan ze nu onder elkaar; en de keuze staat ook in de instellingen van de pc ("Staat deze button overal?").
import 'dart:io';

import 'package:debridmusic/main.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _op(double breedte) => ChangeNotifierProvider<AppSettings>(
  create: (_) => AppSettings(),
  child: MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: breedte, child: const TikKeuzeInstelling()),
      ),
    ),
  ),
);

void main() {
  testWidgets('DE KERN: in het venster op de gsm krijgt de tekst de hele breedte, de lijst eronder', (t) async {
    await t.pumpWidget(_op(330));
    expect(t.takeException(), isNull, reason: 'geen overloop');
    final tekst = t.getSize(find.text('Tikken op een nummer, als er al een wachtrij is'));
    expect(tekst.width, greaterThan(250), reason: 'op de gsm was dit één letter breed');
    final lijst = t.getRect(find.byType(DropdownButton<TikKeuze>));
    final rTekst = t.getRect(find.text('Tikken op een nummer, als er al een wachtrij is'));
    expect(lijst.top, greaterThanOrEqualTo(rTekst.bottom - 1), reason: 'onder de tekst');
    expect(lijst.width, closeTo(330, 1), reason: 'de keuzelijst over de hele breedte');
  });

  testWidgets('op de pc naast elkaar, zoals voorheen', (t) async {
    await t.pumpWidget(_op(640));
    expect(t.takeException(), isNull);
    final lijst = t.getRect(find.byType(DropdownButton<TikKeuze>));
    final rTekst = t.getRect(find.text('Tikken op een nummer, als er al een wachtrij is'));
    expect(lijst.left, greaterThan(rTekst.right - 1), reason: 'rechts van de tekst');
    expect((lijst.center.dy - rTekst.center.dy).abs(), lessThan(20), reason: 'op dezelfde regel');
    expect(kTikKeuzeNaastElkaar, 460);
  });

  test('aangesloten: ook in de instellingen van de pc, en op een toestel bij de koppeling', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect('const TikKeuzeInstelling(),'.allMatches(main).length, 2);
    expect(
      main.contains(
        '                    if (!context.read<LibraryStore>().isRemote) ...[\n'
        '                      const SizedBox(height: 14),\n'
        '                      const TikKeuzeInstelling(),\n',
      ),
      isTrue,
      reason: 'op de pc, niet dubbel op een toestel',
    );
  });
}
