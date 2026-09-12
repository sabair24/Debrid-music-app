/// Op een telefoon staat er geen laag die het scherm terugleest.
///
/// **De klacht.** Saber op 12-09-2026: *"de ui ux op mijn smartphone is heel traag op album pagina,
/// ik vermoed dat de glass effect daarmee te maken heeft, het loopt heel stroef, ook bij artist
/// pagina scrollen heel stroef niet vloeiend, en het nu spelend venster ook heel stroef, cd draait
/// niet meer vloeiend"*.
///
/// **Hij had gelijk, en de reden stond al in dit huis opgeschreven.** Bij `glassSurface` in
/// `main.dart` staat over de `BackdropFilter`: *"Dat is de enige laag die Flutter niet mag
/// raster-cachen: hij leest de achtergrond terug en blurt hem opnieuw bij élke hertekening, en op
/// een telefoon is dat precies tijdens het scrollen."* Die les was toen toegepast op de zoekbalk —
/// en op niets anders. Van de eenentwintig vervagingen in de app gebruikte er ÉÉN de uitweg voor
/// een telefoon.
///
/// Tijdens het scrollen van een artiestpagina stonden er daardoor vijf van die lagen tegelijk: de
/// meeschuivende balk, die bij élke scrollstap opnieuw gebouwd wordt, plus elke glasknop apart.
///
/// Deze toetsen zeggen niet "het is snel" — dat meet je op het toestel. Ze zeggen: op een smal
/// scherm zit er geen `BackdropFilter` meer in de boom, en op een breed scherm nog wel.
library;

import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een scherm van een telefoon (onder de 600 punten) of van een pc.
Future<int> _lagen(WidgetTester t, Widget kind, {required double breed}) async {
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(size: Size(breed, 800)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(home: Scaffold(body: kind)),
    ),
  ));
  await t.pump();
  return t.widgetList(find.byType(BackdropFilter)).length;
}

void main() {
  testWidgets('DE KERN: de balk boven een pagina leest op een telefoon niets terug', (t) async {
    expect(await _lagen(t, balkGlas(const Color(0xFF07080C), 1, dicht: true, plat: true), breed: 390),
        0,
        reason: 'deze balk wordt bij ELKE scrollstap opnieuw gebouwd');
  });

  testWidgets('DE GRENS: op een pc blijft het echt glas', (t) async {
    expect(await _lagen(t, balkGlas(const Color(0xFF07080C), 1), breed: 1400), 1,
        reason: 'daar is het geen probleem en hoort het glas te blijven');
  });

  testWidgets('DE KERN: de vulling blijft staan, ook zonder vervaging', (t) async {
    // Anders wordt de balk doorzichtig en lees je de tracklijst dwars door de knoppen heen —
    // precies waar deze balk voor bestaat. Op een telefoon staat de vulling toch al op 78 %.
    await _lagen(t, balkGlas(const Color(0xFF07080C), 1, dicht: true, plat: true), breed: 390);
    expect(find.byType(DecoratedBox), findsWidgets);
  });

  testWidgets('DE VAL: bij nul deining staat er helemaal niets', (t) async {
    // Een BackdropFilter met sigma 0 is nog steeds een laag die het scherm terugleest.
    expect(await _lagen(t, balkGlas(const Color(0xFF07080C), 0), breed: 1400), 0);
  });

  testWidgets('DE KERN: een glasknop op een telefoon leest niets terug', (t) async {
    // Op de artiestpagina staan er drie naast elkaar, plus de terugpijl.
    expect(
        await _lagen(t, GlasKnop(icoon: Icons.radio_rounded, label: 'Radio', onPressed: () {}), breed: 390), 0);
  });

  testWidgets('DE GRENS: diezelfde knop op een pc houdt zijn glas', (t) async {
    expect(
        await _lagen(t, GlasKnop(icoon: Icons.radio_rounded, label: 'Radio', onPressed: () {}), breed: 1400), 1);
  });
}
