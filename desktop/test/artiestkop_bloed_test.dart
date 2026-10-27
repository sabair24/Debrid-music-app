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
///
/// **Sinds 27-10-2026 staat de tekst onderaan** (Saber: "als ik die hoger maak, dan creeer ik heel veel
/// lege nutteloze ruimte"). Het verloop dat de tekst draagt is daarom een vaste strook onderaan, in
/// punten: een hogere kop is meer foto boven de naam, geen groter vervaagd vlak onder de knoppen.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/beeldvorm.dart' show KopInstelling;
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

EditorialeKop kop({double bovenBloed = 0, KopInstelling? uitsnede}) => EditorialeKop(
      naam: 'Michael Jackson',
      soort: 'Person · USA · 1958–2009',
      bibliotheek: '6 albums · 74 nummers · 5u 12m',
      genres: const ['Pop', 'Soul'],
      bovenBloed: bovenBloed,
      uitsnede: uitsnede,
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

/// Het verloop dat de tekst draagt: een vaste strook onderaan, van doorzichtig naar de achtergrond.
final bandOnderaan = verloop((g) => g.colors.length == 3 && g.colors.first.a == 0 && g.colors.last.a == 1);

/// De donkere rand achter de zwevende balk (85 procent zwart bovenaan).
final randAchterDeBalk = verloop((g) => g.colors.first == const Color(0xD9000000));

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
        'naam': t.getRect(find.textContaining('MICHAEL')),
        'knop': t.getRect(find.widgetWithText(FilledButton, 'Radio')),
      };
    }

    final zonder = await meet(bloed: 0);
    final met = await meet(bloed: 64);

    expect(met['kop']!.top, zonder['kop']!.top, reason: 'de kop zelf begint op dezelfde plek');
    expect(met['kop']!.height - zonder['kop']!.height, 64,
        reason: 'de foto groeit precies met het stuk achter de balk — niet meer, niet minder');
    for (final deel in ['naam', 'knop']) {
      expect(met[deel]!.top - zonder[deel]!.top, 64,
          reason: '"$deel" staat op een andere plek in het venster dan vóór de balk ging zweven');
    }
  });

  testWidgets('DE VAL: het verloop onderaan is een vaste strook, ook met bloeding', (t) async {
    // Het verloop is er om de tekst leesbaar te houden, en de tekst staat onderaan. In procenten van de
    // kop werd het met elke punt hoogte groter — precies de lege ruimte uit Sabers schermafdruk.
    pc(t);
    await t.pumpWidget(omhulsel(kop(bovenBloed: 64)));
    await t.pump();
    final vak = t.getRect(find.byType(EditorialeKop));
    final band = t.getRect(bandOnderaan);
    expect(band.bottom, vak.bottom, reason: 'onderaan hoort de kop nog steeds op te lossen');
    expect(band.height, 160, reason: 'in punten, niet in procenten');
  });

  testWidgets('DE KERN: een hogere kop is meer foto boven de naam, geen leegte onder de knoppen', (t) async {
    // Saber, 27-10-2026: "ik kan de kop aanpassen maar als ik die hoger maak, dan creeer ik heel veel lege
    // nutteloze ruimte". De tekst stond bovenaan, dus kwam elke punt extra onder de knoppen terecht.
    pc(t);
    Future<(Rect, Rect, Rect)> meet(KopInstelling? i) async {
      await t.pumpWidget(omhulsel(kop(uitsnede: i)));
      await t.pump();
      return (
        t.getRect(find.byType(EditorialeKop)),
        t.getRect(find.widgetWithText(FilledButton, 'Radio')),
        t.getRect(bandOnderaan),
      );
    }

    final gewoon = await meet(null);
    final hoog = await meet(const KopInstelling(fx: .5, fy: .3, hoogte: 1000));
    expect(hoog.$1.height - gewoon.$1.height, greaterThan(300), reason: 'de kop is echt hoger');
    expect(hoog.$1.bottom - hoog.$2.bottom, gewoon.$1.bottom - gewoon.$2.bottom,
        reason: 'de knoppen blijven onderaan; de extra hoogte gaat naar de foto erboven');
    expect(hoog.$3.height, gewoon.$3.height, reason: 'het vervaagde vlak groeit niet mee');
  });

  testWidgets('DE KERN: achter de balk ligt een donkere rand, die naar de foto toe oplost', (t) async {
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

  testWidgets('DE VAL: op een gsm staat de naam onder de terugknop, onderaan op de foto',
      (t) async {
    // De ronde terugknop staat op 8 punten en is 44 hoog (`GlasKnop.rond`). Op 44 viel het kopje er
    // half onder — gezien op de S26, 11-10-2026.
    //
    // Sinds 27-10-2026 de foto met de naam erop, en de feiten en de knoppen eronder op de achtergrond —
    // het ontwerp dat Saber goedkeurde.
    t.view.physicalSize = const Size(411, 914);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(omhulsel(kop()));
    await t.pump();
    final vak = t.getRect(find.byType(EditorialeKop));
    // Geen "[ Artiest ]" meer (Saber, 27-10-2026: "dit moet weg").
    expect(find.text('[ Artiest ]'), findsNothing);
    expect(t.getRect(find.textContaining('MICHAEL')).top - vak.top, greaterThanOrEqualTo(8 + 44 + 4),
        reason: 'de naam valt onder de knop');
    // De laatste regel van de naam: in de lettervorm van de toetsen past hij niet op één regel.
    expect(t.getRect(find.textContaining('JACKSON')).bottom, closeTo(vak.top + kGsmKopFoto - 14, 1),
        reason: 'de naam staat onderaan op de foto');
    expect(t.getRect(find.text('6 albums · 74 nummers · 5u 12m')).top, greaterThan(vak.top + kGsmKopFoto),
        reason: 'de feiten staan onder de foto');
    expect(t.getRect(bandOnderaan).bottom, vak.top + kGsmKopFoto, reason: 'het verloop hoort bij de foto');
  });

  testWidgets('DE GRENS: zonder bloeding is alles zoals het was', (t) async {
    // Telefoon, televisie, en de pc zolang de offline-melding er staat: daar zweeft niets.
    pc(t);
    await t.pumpWidget(omhulsel(kop()));
    await t.pump();
    expect(randAchterDeBalk, findsNothing);
    expect(t.getRect(bandOnderaan).bottom, t.getRect(find.byType(EditorialeKop)).bottom);
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
