/// Dezelfde plaat opnieuw aanwijzen moet de cd opnieuw uit de hoes laten komen.
///
/// **Waarom dit bestaat.** Het uitschuiven van [AlbumArt] start op twee manieren, en allebei doen
/// ze niets in precies het geval dat het jaarlint oplevert:
///
/// * `_sync()` roept `_slide.forward()` aan — een lege handeling zodra de schuif al op één staat.
/// * `didUpdateWidget` begint vanaf nul, maar alléén als de PLAAT veranderde.
///
/// Klik je in het lint een jaartal aan dat bij dezelfde plaat hoort als het vorige, dan gebeurt er
/// dus niets: je klikt, en er beweegt niets. Een gebaar dat af en toe dood is, is erger dan geen
/// gebaar — je gaat twijfelen of de klik wel aankwam.
///
/// [AlbumArt.uitschuifTeller] lost dat op. Deze toets legt vast dát hij dat doet, en — net zo
/// belangrijk — dat de aanwijslijst op de artiestpagina er niets van merkt: die schuift al sinds
/// 10-09-2026 uit bij HOVER, en dat is uitgeleverd gedrag dat niet mag verschuiven.
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

/// Een geldige PNG van één doorzichtige pixel.
///
/// Genoeg om `AlbumArt` een voorkant te geven, en daarmee de getekende schijf ernaast. Zonder
/// voorkant tekent hij helemaal geen schijf en valt er niets te meten.
final _pixel = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
  0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _omhulsel(Widget kind) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: kind))),
    );

/// De getekende schijf. Privé, dus op naam gezocht — dat is wat er te meten valt.
final _schijf = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_GetekendeSchijf');

double _schijfX(WidgetTester t) => t.getTopLeft(_schijf).dx;

void main() {
  setUpAll(() {
    setAppDirForTest(Directory.systemTemp.createTempSync('uitschuif').path);
  });

  testWidgets('DE KERN: dezelfde plaat opnieuw kiezen speelt het uitschuiven opnieuw af', (t) async {
    Widget bouw(int teller) => _omhulsel(AlbumArt(
          artist: 'Michael Jackson',
          album: 'Thriller',
          identity: 'mj-thriller',
          size: 200,
          fallback: _pixel,
          uitgeschoven: true,
          uitschuifTeller: teller,
          reisFactor: .62,
        ));

    await t.pumpWidget(bouw(0));
    await t.pumpAndSettle();
    final helemaalUit = _schijfX(t);

    // Zelfde plaat, teller omhoog: de schuif hoort vanaf nul te beginnen, dus de plaat staat het
    // volgende frame weer bijna helemaal in de hoes.
    await t.pumpWidget(bouw(1));
    await t.pump();
    expect(_schijfX(t), lessThan(helemaalUit - 40),
        reason: 'je klikt hetzelfde jaartal opnieuw aan en er beweegt niets');

    await t.pumpAndSettle();
    expect(_schijfX(t), closeTo(helemaalUit, .5),
        reason: 'na het opnieuw uitschuiven hoort hij weer even ver te staan als daarvoor');
  });

  testWidgets('DE VAL: zonder tellerwissel gebeurt er niets', (t) async {
    // Anders zou ELKE hertekening de plaat terug in de hoes laten springen — en een artiestpagina
    // hertekent bij elk antwoord van elk van de drie catalogi.
    Widget bouw() => _omhulsel(AlbumArt(
          artist: 'Michael Jackson',
          album: 'Thriller',
          identity: 'mj-thriller',
          size: 200,
          fallback: _pixel,
          uitgeschoven: true,
          uitschuifTeller: 7,
          reisFactor: .62,
        ));

    await t.pumpWidget(bouw());
    await t.pumpAndSettle();
    final uit = _schijfX(t);

    await t.pumpWidget(bouw());
    await t.pump();
    expect(_schijfX(t), closeTo(uit, .5),
        reason: 'de plaat springt terug in de hoes bij elke hertekening van de pagina');
  });

  testWidgets('DE GRENS: de aanwijslijst verandert niet — zonder teller blijft alles bij het oude',
      (t) async {
    // Precies de argumenten die `_GetrapteLijstState._paneel` meegeeft: geen `uitschuifTeller`. Het
    // uitschuiven hangt daar aan `uitgeschoven`, en dát gedrag is uitgeleverd en goedgekeurd.
    Widget bouw({required bool aangewezen}) => _omhulsel(AlbumArt(
          artist: 'Michael Jackson',
          album: 'Thriller',
          identity: 'mj-thriller',
          size: 200,
          fallback: _pixel,
          uitgeschoven: aangewezen,
          reisFactor: .85,
        ));

    await t.pumpWidget(bouw(aangewezen: false));
    await t.pumpAndSettle();
    final rust = _schijfX(t);

    // Aanwijzen: hij komt eruit.
    await t.pumpWidget(bouw(aangewezen: true));
    await t.pumpAndSettle();
    final uit = _schijfX(t);
    expect(uit, greaterThan(rust + 40),
        reason: 'aanwijzen hoort de cd uit de hoes te halen, zoals sinds 10-09-2026');

    // En van de lijst af: hij gaat terug.
    await t.pumpWidget(bouw(aangewezen: false));
    await t.pumpAndSettle();
    expect(_schijfX(t), closeTo(rust, .5),
        reason: 'weg van de lijst hoort de cd weer in de hoes te zitten');
  });

  testWidgets('DE GRENS: zonder uitschuiven blijft de teller zonder gevolg', (t) async {
    // Het speelscherm en de albumpagina geven `uitgeschoven` niet mee. Een teller die daar iets zou
    // doen, zou een draaiende plaat midden in een nummer terug in de hoes duwen.
    Widget bouw(int teller) => _omhulsel(AlbumArt(
          artist: 'Michael Jackson',
          album: 'Thriller',
          identity: 'mj-thriller',
          size: 200,
          fallback: _pixel,
          uitschuifTeller: teller,
        ));

    await t.pumpWidget(bouw(0));
    await t.pumpAndSettle();
    final rust = _schijfX(t);

    await t.pumpWidget(bouw(3));
    await t.pumpAndSettle();
    expect(_schijfX(t), closeTo(rust, .5),
        reason: 'de teller mag alleen iets doen waar de plaat ook echt uitgeschoven is');
  });
}
