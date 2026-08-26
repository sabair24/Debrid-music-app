/// Artiestennamen mogen nooit meer van het scherm af lopen.
///
/// **Waarom dit bestaat.** Op "Nu speelt" liep de artiestenregel bij drie namen aan BEIDE kanten van
/// het scherm af, zonder puntjes — hard afgeknipt. Gemeld op *At The Villa People · Etienne
/// Vandewiele · Bruno Quatresous*.
///
/// De oorzaak was geen smaakkwestie maar een meetfout in de indeling. [ArtistNames] is een `Row` met
/// `Flexible`-kinderen, precies gebouwd om namen in te korten. Maar `Flexible` doet alleen iets als
/// zijn `Row` een BEGRENSDE breedte krijgt, en de rij op het speelscherm gaf die niet: `ArtistLine`
/// stond daar als niet-flexibel kind, en zo'n kind krijgt in Flutter een onbegrensde breedte mee.
/// `Flexible` had dus niets om tegenaan te duwen en de namen werden op volle breedte getekend.
///
/// Zo'n fout is in Flutter zichtbaar te maken: een overloop gooit tijdens een toets een fout op. Dat
/// is precies wat deze toets aftast — vandaag zou hij zakken, straks niet meer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/settings.dart';

/// Drie namen die samen ver over een telefoonbreedte heen gaan. Het echte geval.
const drie = ['At The Villa People', 'Etienne Vandewiele', 'Bruno Quatresous'];

/// De namenrij leest de bibliotheek (voor een gecorrigeerde schrijfwijze); leeg is hier prima, want
/// het gaat om de meetkunde.
Widget inVak(Widget kind, {double breedte = 300}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: breedte, child: kind),
          ),
        ),
      ),
    );

const _stijl = TextStyle(fontSize: 15);

void main() {
  group('DE KERN: drie namen in een smal vak lopen nergens overheen', () {
    testWidgets('omgevouwen past het, en staan ze er alledrie', (tester) async {
      await tester.pumpWidget(inVak(
        ArtistNames(names: drie, style: _stijl, omvouwen: true),
      ));
      await tester.pump();

      // Een overloop meldt zich in een toets als een fout. Geen fout is dus het bewijs.
      expect(tester.takeException(), isNull);
      for (final naam in drie) {
        expect(find.text(naam), findsOneWidget, reason: 'namen horen niet te verdwijnen');
      }
    });

    testOverloop();

    testWidgets('en op één regel loopt hij ook nergens overheen', (tester) async {
      // De vorm die elke nummerlijst gebruikt. Daar hoort inkorten, niet omvouwen — maar afknippen
      // hoort er evenmin.
      await tester.pumpWidget(inVak(
        ArtistNames(names: drie, style: _stijl),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('de twee vormen blijven uit elkaar', () {
    testWidgets('omvouwen geeft een Wrap, standaard een Row', (tester) async {
      await tester.pumpWidget(inVak(
        ArtistNames(names: drie, style: _stijl, omvouwen: true),
      ));
      await tester.pump();
      expect(find.byType(Wrap), findsWidgets,
          reason: 'omgevouwen zakt een lange lijst naar een tweede regel');

      await tester.pumpWidget(inVak(
        ArtistNames(names: drie, style: _stijl),
      ));
      await tester.pump();
      // Geen Wrap van ONS; de rest van Material mag er zoveel hebben als het wil, dus wordt er op
      // de hoogte gemeten in plaats van op het soort widget — zie hieronder.
      final hoogte = tester.getSize(find.byType(ArtistNames)).height;
      expect(hoogte, lessThan(40),
          reason: 'één regel hoort één regel te blijven in een nummerlijst');
    });

    testWidgets('omgevouwen mag WEL hoger worden dan één regel', (tester) async {
      await tester.pumpWidget(inVak(
        ArtistNames(names: drie, style: _stijl, omvouwen: true),
      ));
      await tester.pump();
      final hoogte = tester.getSize(find.byType(ArtistNames)).height;
      expect(hoogte, greaterThan(30),
          reason: 'drie lange namen passen niet op 300 punten, dus hoort er een tweede regel');
    });
  });

  group('randgevallen', () {
    testWidgets('één naam blijft één naam', (tester) async {
      await tester.pumpWidget(inVak(
        const ArtistNames(names: ['Sia'], style: _stijl, omvouwen: true),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Sia'), findsOneWidget);
    });

    testWidgets('geen namen geeft geen fout', (tester) async {
      await tester.pumpWidget(inVak(
        const ArtistNames(names: [], style: _stijl, omvouwen: true),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('een naam die zelf al te lang is wordt ingekort, niet afgeknipt', (tester) async {
      const lang = 'Een Artiestennaam Die In Zijn Eentje Al Breder Is Dan Het Hele Vak';
      await tester.pumpWidget(inVak(
        const ArtistNames(names: [lang], style: _stijl, omvouwen: true),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ArtistNames)).width, lessThanOrEqualTo(300));
    });
  });
}

/// Het geval dat aantoonbaar fout ging: een SMAL vak, zoals een telefoon in staande stand.
void testOverloop() {
  testWidgets('ook op de breedte van een telefoon', (tester) async {
    await tester.pumpWidget(inVak(
      ArtistNames(names: drie, style: _stijl, omvouwen: true),
      breedte: 360,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ArtistNames)).width, lessThanOrEqualTo(360),
        reason: 'breder dan het vak betekent dat er iets buiten het scherm valt');
  });
}
