/// Welke velden een correctie mag zetten — en waarom dat van drie dingen tegelijk afhangt.
///
/// **Waarvoor dit bestaat.** Onder "Niet op deze uitgave" op een albumpagina staan de bestanden die
/// je wél hebt maar die niet op de aangewezen persing staan. Die horen vaak bij een ANDERE plaat die
/// je nog niet hebt — "La Salsa" staat niet op *Partir un jour* van 2 Be 3 — en dan valt er niets te
/// verplaatsen: "Naar ander album…" kan alleen kiezen uit albums die er al zijn. Gevraagd op
/// 27-08-2026: *"liedjes die niet op de uitgave staan moet ik dan wel kunnen metadata voor zoeken,
/// zodanig dat die wel in de goeie uitgave zit"*.
///
/// Daarvoor kan `applyCorrection` nu op één aangewezen nummer werken in plaats van op de hele plaat.
/// En dat verandert precies twee beslissingen, die alle drie op dezelfde manier moeten luiden:
///
///   1. in de TAGS die naar het bestand geschreven worden;
///   2. in de correctie die de app op schijf bewaart;
///   3. in de naam waaronder de plaat daarna in de bibliotheek komt te staan.
///
/// Lopen die uit de pas, dan wordt een bestand anders getagd dan het in de app heet — en dat merk je
/// pas als je buiten de app kijkt. Vandaar één regel op één plek, en deze toets eromheen.
///
/// Zuiver: twee ja/nee-vragen in, twee ja/nee-antwoorden uit. Geen schijf, geen netwerk, dus na te
/// meten zonder toestel.
library;

import 'package:debridmusic/library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ({bool album, bool titel}) velden({required bool isSingle, required bool perNummer}) =>
      LibraryStore.veldenBijCorrectie(isSingle: isSingle, perNummer: perNummer);

  group('een hele plaat corrigeren — zoals het altijd al was', () {
    test('een gewoon album: de plaatnaam wél, de titel niet', () {
      // De titel zou anders op ELK nummer landen. Dat is geen bewerking maar schade.
      final v = velden(isSingle: false, perNummer: false);
      expect(v.album, isTrue);
      expect(v.titel, isFalse);
    });

    test('een single: de titel wél, de plaatnaam niet', () {
      // Een single heeft geen album om te zetten; zijn titel ís waar hij onder staat.
      final v = velden(isSingle: true, perNummer: false);
      expect(v.album, isFalse);
      expect(v.titel, isTrue);
    });
  });

  group('DE KERN: één aangewezen nummer', () {
    test('uit een gewoon album mag allebei', () {
      // De plaatnaam is hier het hele punt — je wijst het nummer aan om het naar de juiste plaat te
      // sturen. En er is precies één nummer, dus de titel kan nergens anders landen.
      final v = velden(isSingle: false, perNummer: true);
      expect(v.album, isTrue);
      expect(v.titel, isTrue);
    });

    test('uit een single mag óók allebei', () {
      // Ook hier: één nummer aangewezen betekent dat de plaat gezet mag worden. Zonder deze
      // uitzondering zou een los nummer nooit uit zijn eigen single kunnen wegkomen.
      final v = velden(isSingle: true, perNummer: true);
      expect(v.album, isTrue);
      expect(v.titel, isTrue);
    });

    test('één nummer aanwijzen neemt nooit iets WEG', () {
      // De belangrijkste eigenschap van de hele regel: wat je bij een hele plaat mocht zetten, mag
      // je bij één nummer ook. Zou dat niet zo zijn, dan deed dezelfde knop op het ene scherm iets
      // anders dan op het andere.
      for (final single in [false, true]) {
        final heel = velden(isSingle: single, perNummer: false);
        final los = velden(isSingle: single, perNummer: true);
        expect(los.album || !heel.album, isTrue, reason: 'album, single=$single');
        expect(los.titel || !heel.titel, isTrue, reason: 'titel, single=$single');
      }
    });

    test('er wordt altijd íets gezet, anders doet de knop niets', () {
      // Een correctie die geen enkel veld mag zetten is een venster dat "Toepassen" toont en
      // vervolgens niets doet. Dat mag geen van de vier gevallen opleveren.
      for (final single in [false, true]) {
        for (final los in [false, true]) {
          final v = velden(isSingle: single, perNummer: los);
          expect(v.album || v.titel, isTrue, reason: 'single=$single, perNummer=$los');
        }
      }
    });
  });
}
