/// Een albumraster dat IN een andere lijst staat.
///
/// **Waarom dit bestaat.** Het Favorieten-scherm zet `AlbumsGrid` als kind in een `ListView`, en dat
/// raster is een `CustomScrollView` — een verticale viewport in een verticale lijst. Zonder
/// `shrinkWrap` krijgt die een onbegrensde hoogte en gooit Flutter meteen:
///
///     Vertical viewport was given unbounded height.
///
/// Een rode pagina, zodra je één album favoriet maakt. Er stond geen enkele widgettoets op dat
/// scherm — de bestaande favorieten-toets gaat over de opslag, niet over het beeld.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

Album alb(String titel) => Album(titel, 'Een artiest', [
      Track(path: 'D:\\m\\$titel.flac', title: 'Nummer', artist: 'Een artiest', album: titel),
    ]);

/// De kaartjes lezen de bibliotheek uit (voor dubbelen en gekozen hoezen), dus die moet erboven
/// hangen. Een lege winkel volstaat: het gaat hier om de layout, niet om de inhoud.
Widget omhulsel(Widget kind) => ChangeNotifierProvider<LibraryStore>(
      create: (_) => LibraryStore(),
      child: MaterialApp(home: Scaffold(body: kind)),
    );

void main() {
  setUpAll(() {
    // Nooit in de echte appmap schrijven tijdens een toets.
    setAppDirForTest(Directory.systemTemp.createTempSync('raster').path);
  });

  testWidgets('ingebed in een ListView valt hij niet om', (tester) async {
    await tester.pumpWidget(omhulsel(ListView(
      children: [
        const Text('kop'),
        AlbumsGrid(albums: [alb('Een'), alb('Twee')], title: 'Albums', ingebed: true),
      ],
    )));
    await tester.pump();

    expect(tester.takeException(), isNull, reason: 'dit is precies waar Favorieten op stukliep');
    expect(find.text('Een'), findsOneWidget);
  });

  testWidgets('en op zichzelf scrollt hij nog gewoon', (tester) async {
    // De ingebedde stand mag het normale gebruik niet veranderen: op Albums is dit raster zélf de
    // scroller.
    await tester.pumpWidget(omhulsel(AlbumsGrid(albums: [alb('Een')], title: 'Albums')));
    await tester.pump();

    final lijst = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    expect(lijst.shrinkWrap, isFalse);
    // Niet op null toetsen: `ScrollView` vult zelf `AlwaysScrollableScrollPhysics` in zodra hij de
    // hoofdscroller is. Waar het om gaat is dat hij niet vastgezet is.
    expect(lijst.physics, isNot(isA<NeverScrollableScrollPhysics>()),
        reason: 'op Albums is dit raster zélf de scroller');
  });
}
