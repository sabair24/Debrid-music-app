/// Een regel in de downloadlijst, op de breedte van een telefoon.
///
/// **Waarom dit bestaat.** Op de S26 (1440 px bij dichtheid 600 = 384 dp breed) toonde een
/// afgeronde download een groene balk en verder niets: geen titel van het nummer, en geen "Klaar".
/// De regel was één `Row` met een balk van 190 dp, een stopknop van 34 en een statuslabel van 74
/// erin. Samen met de marges stond er 360 dp vast waar 300 dp te verdelen viel, dus de `Expanded`
/// met de titel kwam op NUL breedte uit en de stand werd het scherm afgeduwd.
///
/// Dat is het gemene aan deze fout: een `Expanded` die nul wordt geeft geen rode streep en geen
/// uitzondering — hij toont gewoon niets. Vandaar dat deze toets niet alleen naar de tekst zoekt
/// maar ook meet hoe breed die tekst daadwerkelijk is; "gevonden" zei hier niets.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';

const _naam = 'Whitney Houston - My Love Is Your Love.flac';

/// Zoals het scherm hem zet: in de lijst met 28 dp marge links en rechts.
Widget _omhulsel(DownloadJob job) => MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 30),
          children: [DlRow(job: job)],
        ),
      ),
    );

DownloadJob _klaar() => DownloadJob(_naam, status: 'done')..progress = 1;

void main() {
  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('dlregel').path));

  group('op een telefoon (384 dp)', () {
    Future<void> pompTelefoon(WidgetTester tester, DownloadJob job) async {
      tester.view.physicalSize = const Size(384, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_omhulsel(job));
      await tester.pump();
    }

    testWidgets('een afgeronde download toont zijn titel én "Klaar"', (tester) async {
      await pompTelefoon(tester, _klaar());

      expect(tester.takeException(), isNull, reason: 'de regel liep 60 dp over de rand');
      expect(find.text('Klaar'), findsOneWidget,
          reason: 'dit stond buiten beeld: je zag alleen een groene balk');
      expect(find.text(_naam), findsOneWidget);
    });

    testWidgets('en de titel krijgt echt breedte, niet nul', (tester) async {
      await pompTelefoon(tester, _klaar());

      // Waar het werkelijk op stukging. De tekst BESTOND ook in de kapotte versie; hij was alleen
      // nul dp breed. Zoeken op tekst zou dus groen zijn gebleven.
      final breedte = tester.getSize(find.text(_naam)).width;
      expect(breedte, greaterThan(150),
          reason: 'een titel van 0 dp is precies wat de gebruiker meldde: een lege regel');
    });

    testWidgets('een lopende download toont zijn percentage', (tester) async {
      await pompTelefoon(tester, DownloadJob(_naam)..progress = .42);

      expect(tester.takeException(), isNull);
      expect(find.text('Bezig 42%'), findsOneWidget);
      expect(tester.getSize(find.text(_naam)).width, greaterThan(150));
    });

    testWidgets('een download die je zelf stopte heet "Gestopt" en is niet rood', (tester) async {
      // De pc weet dit onderscheid al ('failed' + cancelled). Het ging alleen niet over de lijn
      // naar de telefoon, en daar stond dus "Mislukt" in het rood boven een download die de
      // gebruiker net zelf had afgezet. Gemeten op 17-08 door hem op het toestel te stoppen.
      final job = DownloadJob(_naam, status: 'failed')
        ..cancelled = true
        ..detail = 'geannuleerd';
      await pompTelefoon(tester, job);

      expect(find.text('Gestopt'), findsOneWidget);
      expect(find.text('Mislukt'), findsNothing);
      final stand = tester.widget<Text>(find.text('Gestopt'));
      expect(stand.style?.color, isNot(Colors.redAccent),
          reason: 'rood is voor iets wat misging, niet voor een knop die jij indrukte');
      expect(find.byIcon(Icons.error_rounded), findsNothing);
    });

    testWidgets('en een echte mislukking blijft wél rood', (tester) async {
      final job = DownloadJob(_naam, status: 'failed')..detail = 'Uploader reageert niet';
      await pompTelefoon(tester, job);

      expect(find.text('Mislukt'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Mislukt')).style?.color, Colors.redAccent);
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    });

    testWidgets('en een lange stand duwt de titel niet weg', (tester) async {
      // "Wacht op peer · plaats 369" is het langste dat hier kan staan. Mag krap worden, mag niet
      // hetzelfde doen als de balk deed.
      final job = DownloadJob(_naam, status: 'waiting')..queuePlace = 369;
      await pompTelefoon(tester, job);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text(_naam)).width, greaterThan(120));
    });
  });

  testWidgets('op een pc blijft het één regel naast elkaar', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_omhulsel(_klaar()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Klaar'), findsOneWidget);
    // Naast elkaar, niet gestapeld: de balk staat op dezelfde hoogte als de titel.
    final titel = tester.getCenter(find.text(_naam));
    final balk = tester.getCenter(find.byType(LinearProgressIndicator));
    expect((titel.dy - balk.dy).abs(), lessThan(4));
  });
}
