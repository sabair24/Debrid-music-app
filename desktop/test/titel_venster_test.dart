/// De twee vensters van "titel rechtzetten", écht getekend.
///
/// **Waarom dit apart staat van `titel_rechtzetten_test.dart`.** Dat bestand toetst de regels: welke
/// titel voorgesteld wordt, waar de gastnaam heen gaat, wat er botst. Geen van die toetsen tekent
/// ook maar één pixel — dus geen ervan zou merken dat het venster bij het openen stukloopt, dat een
/// rij buiten zijn kader valt, of dat de schakelaar blijft staan terwijl hij weg hoort.
///
/// Op deze machine kan de app niet gebouwd worden (geen Visual Studio) en het scherm overnemen is
/// geen weg: dit ís hier de manier om te zien dat het venster het doet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/editions.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';

/// Het gemelde geval, letterlijk: het bestand draagt de gast in de TITEL, de uitgave noemt hem niet.
Track bestand([String titel = 'One Minute Man (Feat Ludacris)']) => Track(
      path: 'D:\\m\\${titel.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')}.flac',
      title: titel,
      artist: 'Missy Elliott',
      album: '2001 Miss E... So Addictive',
      isFlac: true,
      duration: const Duration(seconds: 275),
    );

const uitgave = ChoiceTrack('7', 'One Minute Man', 275);

/// Een venster staat niet in een lijst maar los op het scherm; een echte schermmaat dus.
Future<void> toon(WidgetTester tester, Widget venster, {double breedte = 1280}) async {
  tester.view.physicalSize = Size(breedte, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: venster))));
  await tester.pump();
}

void main() {
  group('Titel rechtzetten — één nummer', () {
    testWidgets('DE KERN: de officiële titel staat er, en waar de gast heen gaat', (tester) async {
      await toon(tester, TitelRechtzettenDialog(track: bestand(), uitgave: uitgave));

      // De huidige titel, zodat te zien is waar het over gaat.
      expect(find.text('Nu: One Minute Man (Feat Ludacris)'), findsOneWidget);
      // Het voorstel — en het tekstveld dat er al mee gevuld is.
      expect(find.text('One Minute Man'), findsWidgets);
      expect(find.text('zoals de uitgave het noemt'), findsOneWidget);
      // En de gastnaam verdwijnt niet: hij verhuist.
      expect(find.text('Gastnaam naar het artiestveld'), findsOneWidget);
      expect(find.text('Missy Elliott feat. Ludacris'), findsOneWidget);
    });

    testWidgets('zonder MusicBrainz-persing blijft de knop voor andere persingen weg',
        (tester) async {
      // Anders zou hij mislukken zodra je erop drukt.
      await toon(tester, TitelRechtzettenDialog(track: bestand(), uitgave: uitgave));
      expect(find.text('Andere persingen bekijken'), findsNothing);

      await toon(
          tester,
          TitelRechtzettenDialog(
              track: bestand(), uitgave: uitgave, albumMbid: 'iets-van-musicbrainz'));
      expect(find.text('Andere persingen bekijken'), findsOneWidget);
    });

    testWidgets('typ je zelf een titel die de gast noemt, dan gaat de schakelaar weg',
        (tester) async {
      // Anders komt de naam er dubbel in: in de titel én in het artiestveld.
      await toon(tester, TitelRechtzettenDialog(track: bestand(), uitgave: uitgave));
      expect(find.text('Gastnaam naar het artiestveld'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'One Minute Man (feat. Ludacris)');
      await tester.pump();
      expect(find.text('Gastnaam naar het artiestveld'), findsNothing);
    });

    testWidgets('een leeg tekstveld maakt de knop dood', (tester) async {
      // Schrijven zou dan de titel uit het bestand halen.
      await toon(tester, TitelRechtzettenDialog(track: bestand(), uitgave: uitgave));
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final knop = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'In het bestand schrijven'));
      expect(knop.onPressed, isNull);
    });
  });

  group('Alle titels rechtzetten — de hele plaat', () {
    testWidgets('DE KERN: elke regel toont wat de titel en de artiest worden', (tester) async {
      final t = bestand();
      await toon(
          tester,
          AlleTitelsDialog(
            stappen: [(track: t, titel: 'One Minute Man', artiest: 'Missy Elliott feat. Ludacris')],
            opDePlaat: [t],
          ));

      expect(find.text('One Minute Man (Feat Ludacris)'), findsOneWidget);
      expect(find.text('One Minute Man'), findsOneWidget);
      expect(find.text('artiest wordt Missy Elliott feat. Ludacris'), findsOneWidget);
      expect(find.text('1 in de bestanden schrijven'), findsOneWidget);
    });

    testWidgets('DE VAL: twee regels op dezelfde titel blokkeren de knop', (tester) async {
      // En het zegt WELKE twee, want de vinkjes zijn er al — dan is uitvinken genoeg.
      final a = bestand('One Minute Man (Album Version)');
      final b = bestand('One Minute Man (Radio Edit)');
      await toon(
          tester,
          AlleTitelsDialog(
            stappen: [
              (track: a, titel: 'One Minute Man', artiest: null),
              (track: b, titel: 'One Minute Man', artiest: null),
            ],
            opDePlaat: [a, b],
          ));

      expect(
          find.text(
              'Geweigerd: twee nummers zouden dezelfde titel krijgen — dan verdwijnt er één uit de lijst.'),
          findsOneWidget);
      final knop = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(knop.onPressed, isNull);
    });

    testWidgets('en één uitvinken maakt hem weer levend', (tester) async {
      final a = bestand('One Minute Man (Album Version)');
      final b = bestand('One Minute Man (Radio Edit)');
      await toon(
          tester,
          AlleTitelsDialog(
            stappen: [
              (track: a, titel: 'One Minute Man', artiest: null),
              (track: b, titel: 'One Minute Man', artiest: null),
            ],
            opDePlaat: [a, b],
          ));

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(find.textContaining('Geweigerd'), findsNothing);
      final knop = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(knop.onPressed, isNotNull);
      expect(find.text('1 in de bestanden schrijven'), findsOneWidget);
    });

    testWidgets('zonder gastnamen is er geen schakelaar', (tester) async {
      final t = bestand('One Minute Man (Album Version)');
      await toon(
          tester,
          AlleTitelsDialog(
            stappen: [(track: t, titel: 'One Minute Man', artiest: null)],
            opDePlaat: [t],
          ));
      expect(find.text('Gastnamen naar het artiestveld'), findsNothing);
    });
  });

  group('op een telefoon past het ook', () {
    // Waar de Row het liet afweten. `dialogWidth` kapt af op schermbreedte min 32, dus op 360 blijft
    // er 288 over voor twee knoppen die er samen 545 vragen. Een overloop is in een toets een echte
    // fout — op een toestel tekent Flutter gewoon door, en dan sta je met een gestreepte balk.
    testWidgets('het losse venster', (tester) async {
      await toon(tester, TitelRechtzettenDialog(track: bestand(), uitgave: uitgave),
          breedte: 360);
      expect(find.text('In het bestand schrijven'), findsOneWidget);
    });

    testWidgets('en het overzicht', (tester) async {
      final t = bestand();
      await toon(
          tester,
          AlleTitelsDialog(
            stappen: [
              (track: t, titel: 'One Minute Man', artiest: 'Missy Elliott feat. Ludacris')
            ],
            opDePlaat: [t],
          ),
          breedte: 360);
      expect(find.text('1 in de bestanden schrijven'), findsOneWidget);
    });
  });
}
