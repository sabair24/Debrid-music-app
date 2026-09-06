/// Er draait nu ook een plaat achter de hoes als er géén cd-scan is.
///
/// **Waarom dit erbij kwam.** De albumpagina draait al de ECHTE cd-scan van de persing —
/// `RotationTransition` van negen seconden, uitgesneden op de cd-gatverhouding 15/120, die achter
/// de hoes vandaan schuift. Alleen: zonder scan deed hij helemaal niets, en dat is vaker dan je
/// denkt. Gemeten op Sabers bibliotheek: van de 1481 opgeslagen uitgaven hebben er 487 een
/// `disc`-bestand, en van veertien platen bij Cover Art Archive hadden er zes er een — zes op de
/// tien platen miste dus het gebaar waar de hele pagina om draait.
///
/// **Wat er NIET gebeurt.** De oude regel *"een achterkant een cd noemen laat de verkeerde foto
/// ronddraaien"* (`artwork.dart`) blijft staan: er wordt geen scan verzonnen. Wat er draait is een
/// getekende schijf met de hoes als klein etiket — zichtbaar iets anders, niet voor een scan aan te
/// zien.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

/// Een geldige 1×1 PNG. Klein genoeg om in een toets te staan, echt genoeg om te decoderen.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget omhulsel(Widget kind) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: kind))),
    );

void main() {
  setUpAll(() {
    setAppDirForTest(Directory.systemTemp.createTempSync('schijf').path);
  });

  testWidgets('DE KERN: met alleen een hoes komt er tóch een schijf achter vandaan', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(omhulsel(AlbumArt(artist: 'Michael Jackson', album: 'Thriller', size: 200, fallback: _png)));
    await tester.pump();

    // De schijf krijgt breedte NAAST de hoes — dat is de uitschuifruimte. Zonder terugval was het
    // vak precies 200 breed en zag je alleen de hoes.
    final vak = tester.getRect(find.byType(AlbumArt));
    expect(vak.width, greaterThan(200),
        reason: 'er is geen ruimte voor een schijf gereserveerd, dus er draait er geen');
    expect(tester.takeException(), isNull);
  });

  testWidgets('en zonder énig beeld blijft het bij niets — er wordt niets verzonnen', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(omhulsel(const AlbumArt(artist: 'Niemand', album: 'Niets', size: 200)));
    await tester.pump();

    // Geen hoes, geen etiket, dus ook geen schijf: een lege cirkel is geen gebaar maar een fout.
    expect(tester.getRect(find.byType(AlbumArt)).width, 200);
    expect(tester.takeException(), isNull);
  });
}
