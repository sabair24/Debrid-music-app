/// De foto van een artiest loopt tot de bovenrand van het venster, en verder verschuift er niets.
///
/// **Wat hier gevraagd werd.** "ik wil gewoon af van die bovenbalk" (Saber, 11-09-2026). De balk
/// zweeft nu over de pagina's heen, en de artiestpagina laat de ruimte eronder weg zodat haar foto er
/// onderdoor loopt. Daarvoor krijgt [EditorialeKop] een `bovenBloed`: zoveel punten van het vak liggen
/// ACHTER de balk.
///
/// **De eis is dat alleen de foto groeit.** De pagina begint nu bij de bovenrand van het venster in
/// plaats van 64 punten lager. Alles wat IN de kop staat moet dus precies 64 punten omlaag om op
/// dezelfde plek in het venster te blijven — de naam, de knoppen, én het verloop dat de naam leesbaar
/// houdt. Blijft er één van de drie achter, dan staat de tekst op een ander stuk foto dan gisteren,
/// of begint het donkere verloop op een andere hoogte dan de tekst die het moet dragen.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

/// Dezelfde omhulling als `artiestkop_knoppen_test.dart`: lege bibliotheek, lege instellingen, en
/// de kop in een scroller zoals op de echte pagina.
Widget omhulsel(Widget kind) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(home: Scaffold(body: ListView(children: [kind]))),
    );

const _knoppen = ['Radio', 'Foto kiezen', 'Naam corrigeren'];

EditorialeKop kop({double bovenBloed = 0}) => EditorialeKop(
      naam: 'Michael Jackson',
      soort: 'Person · USA · 1958–2009',
      bibliotheek: '6 albums · 74 nummers · 5u 12m',
      genres: const ['Pop', 'Soul'],
      bovenBloed: bovenBloed,
      actions: [for (final n in _knoppen) FilledButton(onPressed: () {}, child: Text(n))],
    );

/// Een verloop van boven naar onder in de kop, herkend aan een van zijn kleuren.
Finder verloop(bool Function(LinearGradient) past) => find.byWidgetPredicate((w) {
      if (w is! DecoratedBox) return false;
      final d = w.decoration;
      if (d is! BoxDecoration) return false;
      final g = d.gradient;
      return g is LinearGradient && g.begin == Alignment.topCenter && past(g);
    });

/// Het verloop dat de naam draagt. Het begint op 27 procent zwart.
final waasVanBoven = verloop((g) => g.colors.first == const Color(0x44000000));

/// De donkere rand achter de zwevende balk. Hij eindigt waar het verloop hierboven begint.
final randAchterDeBalk = verloop(
    (g) => g.colors.last == const Color(0x44000000) && g.colors.first != g.colors.last);

void main() {
  setUpAll(() {
    // Nooit in de echte appmap schrijven tijdens een toets.
    setAppDirForTest(Directory.systemTemp.createTempSync('artiestbloed').path);
  });

  void pc(WidgetTester t) {
    t.view.physicalSize = const Size(1440, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('DE KERN: de tekst zakt precies zo ver als de foto doorloopt', (t) async {
    pc(t);
    Future<Map<String, Rect>> meet({required double bloed}) async {
      await t.pumpWidget(omhulsel(kop(bovenBloed: bloed)));
      await t.pump();
      return {
        'kop': t.getRect(find.byType(EditorialeKop)),
        'label': t.getRect(find.text('[ Artiest ]')),
        'naam': t.getRect(find.text('MICHAEL')),
        'knop': t.getRect(find.widgetWithText(FilledButton, 'Radio')),
      };
    }

    final zonder = await meet(bloed: 0);
    final met = await meet(bloed: 64);

    expect(met['kop']!.top, zonder['kop']!.top, reason: 'de kop zelf begint op dezelfde plek');
    expect(met['kop']!.height - zonder['kop']!.height, 64,
        reason: 'de foto groeit precies met het stuk achter de balk — niet meer, niet minder');
    for (final deel in ['label', 'naam', 'knop']) {
      expect(met[deel]!.top - zonder[deel]!.top, 64,
          reason: '"$deel" staat op een andere plek in het venster dan vóór de balk ging zweven');
    }
  });

  testWidgets('DE VAL: het verloop zakt mee, anders draagt het de naam niet meer', (t) async {
    // Het verloop is er om de naam leesbaar te houden. Begint het bovenaan het vak terwijl de naam 64
    // punten zakt, dan ligt het donkerste deel ervan 64 punten te hoog en staat de naam op een
    // lichter stuk foto dan gisteren.
    pc(t);
    await t.pumpWidget(omhulsel(kop(bovenBloed: 64)));
    await t.pump();
    final vak = t.getRect(find.byType(EditorialeKop));
    final waas = t.getRect(waasVanBoven);
    expect(waas.top, vak.top + 64);
    expect(waas.bottom, vak.bottom, reason: 'onderaan hoort de kop nog steeds op te lossen');
  });

  testWidgets('DE KERN: achter de balk ligt een donkere rand, en hij sluit naadloos aan', (t) async {
    // Zonder die rand staan de pillen, de tellingen en de vensterknoppen op een onbewerkte foto, en
    // die is bij veel artiesten bovenaan juist licht: lucht, een studiowand.
    pc(t);
    await t.pumpWidget(omhulsel(kop(bovenBloed: 64)));
    await t.pump();
    final vak = t.getRect(find.byType(EditorialeKop));
    final rand = t.getRect(randAchterDeBalk);
    expect(rand.top, vak.top);
    expect(rand.height, 64);

    final boven = t.widget<DecoratedBox>(randAchterDeBalk).decoration as BoxDecoration;
    final g = boven.gradient! as LinearGradient;
    expect(g.colors.first.a, greaterThan(g.colors.last.a),
        reason: 'donkerder bovenaan, waar de balk staat, en lichter naar de foto toe');
  });

  testWidgets('DE GRENS: zonder bloeding is alles zoals het was', (t) async {
    // Telefoon, televisie, en de pc zolang de offline-melding er staat: daar zweeft niets.
    pc(t);
    await t.pumpWidget(omhulsel(kop()));
    await t.pump();
    expect(randAchterDeBalk, findsNothing);
    expect(t.getRect(waasVanBoven).top, t.getRect(find.byType(EditorialeKop)).top);
  });

  testWidgets('DE VAL: de knoppen blijven ook mét bloeding binnen de kop', (t) async {
    // `artiestkop_knoppen_test.dart` vertelt hoe deze fout twee keer gemaakt is: een knop die buiten
    // het vak valt staat er wel, maar vangt geen tik. De bloeding verandert de rekensom van de hoogte,
    // dus de garantie moet opnieuw bewezen worden — op de krapste brede stand, een iPad rechtop, met
    // de statusbalk erbij.
    t.view.physicalSize = const Size(834 * 2, 1194 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    final getikt = <String>[];
    await t.pumpWidget(omhulsel(EditorialeKop(
      naam: 'Michael Jackson',
      soort: 'Person · USA · 1958–2009',
      bibliotheek: '6 albums · 74 nummers · 5u 12m',
      genres: const ['Pop', 'Soul', 'R&B'],
      bovenBloed: 64 + 24,
      actions: [
        for (final n in _knoppen) FilledButton(onPressed: () => getikt.add(n), child: Text(n)),
      ],
    )));
    await t.pump();

    final vak = t.getRect(find.byType(EditorialeKop));
    for (final n in _knoppen) {
      final knop = t.getRect(find.widgetWithText(FilledButton, n));
      expect(knop.bottom, lessThanOrEqualTo(vak.bottom),
          reason: '"$n" steekt onder de kop uit en vangt daar geen tik meer');
    }
    for (final n in _knoppen) {
      await t.tap(find.text(n));
    }
    expect(getikt, _knoppen);
  });
}
