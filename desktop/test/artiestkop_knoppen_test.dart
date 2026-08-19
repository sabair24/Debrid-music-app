/// De knoppen op de artiestpagina moeten BINNEN de kop vallen.
///
/// **Waarom dit bestaat.** Deze fout is twee keer gemaakt, met precies hetzelfde gevolg. De kop had
/// een vaste hoogte die berekend was op wat er toen in stond; kwam er een knop bij, dan zakte de rij
/// een regel en viel hij eronder uit. Flutter tekent dat gewoon door — je ziet een knop staan — maar
/// `RenderBox.hitTest` slaat alles buiten `size` over, dus hij vangt geen tik. Een knop die er staat
/// en aantoonbaar niets doet, zonder enige aanwijzing waarom.
///
/// De eerste keer was het "Foto kiezen" en "Radio" op de S26. De tweede keer kwam "Naam corrigeren"
/// erbij, zakte die naar een tweede regel, en stond er weer een knop buiten het vak.
///
/// Deze toets meet daarom niet de hoogte, maar de twee dingen die er echt toe doen: elke knop ligt
/// binnen de kop, en elke knop is aan te tikken.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

/// De kop leest de bibliotheek (voor een zelf gekozen foto) en de instellingen (voor het ophalen
/// van artiestafbeeldingen). Allebei leeg: het gaat hier om de meetkunde, niet om de inhoud. Zonder
/// netwerk levert het ophalen `null` en blijft er een kop zonder foto over — precies het geval waar
/// de knoppen het krapst zitten.
Widget omhulsel(Widget kind) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      // In een ListView, zoals op de echte pagina: de kop staat daar in een scroller en heeft naar
      // beneden dus geen begrenzing om op terug te vallen.
      child: MaterialApp(home: Scaffold(body: ListView(children: [kind]))),
    );

const _knoppen = ['Radio', 'Foto kiezen', 'Naam corrigeren'];

void main() {
  setUpAll(() {
    // Nooit in de echte appmap schrijven tijdens een toets.
    setAppDirForTest(Directory.systemTemp.createTempSync('artiestkop').path);
  });

  testWidgets('drie knoppen blijven op een telefoon binnen de kop', (tester) async {
    // 411 punten breed: een Galaxy S26, en het toestel waarop dit twee keer misging.
    tester.view.physicalSize = const Size(411 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final getikt = <String>[];
    await tester.pumpWidget(omhulsel(ArtistHero(
      name: 'Enrique Iglesias',
      subtitle: '2 in je bibliotheek · 244 albums',
      actions: [
        for (final naam in _knoppen)
          FilledButton(onPressed: () => getikt.add(naam), child: Text(naam)),
      ],
    )));
    await tester.pump();

    final kop = tester.getRect(find.byType(ArtistHero));
    for (final naam in _knoppen) {
      final knop = tester.getRect(find.widgetWithText(FilledButton, naam));
      expect(knop.bottom, lessThanOrEqualTo(kop.bottom),
          reason: '"$naam" steekt onder de kop uit en vangt daar geen tik meer');
      expect(knop.right, lessThanOrEqualTo(kop.right),
          reason: '"$naam" loopt rechts van het scherm af');
    }

    // De tik zelf, want dát is wat de gebruiker merkt. `tap` weigert een plek die niet raakbaar is,
    // dus deze regel faalt uit zichzelf als de knop weer buiten het vak ligt.
    for (final naam in _knoppen) {
      await tester.tap(find.text(naam));
    }
    expect(getikt, _knoppen);
  });

  testWidgets('op een breed scherm houdt de kop zijn vaste 400', (tester) async {
    // Daar staan de foto en de tekst NAAST elkaar en is de hoogte een keuze over hoeveel van de
    // achtergrond je ziet — niet iets wat de inhoud mag bepalen.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(omhulsel(ArtistHero(
      name: 'Enrique Iglesias',
      actions: [
        for (final naam in _knoppen)
          FilledButton(onPressed: () {}, child: Text(naam)),
      ],
    )));
    await tester.pump();

    expect(tester.getRect(find.byType(ArtistHero)).height, 400);
  });
}
