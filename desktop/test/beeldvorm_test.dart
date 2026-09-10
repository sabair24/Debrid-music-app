/// Een iPad die je rechtop houdt hoort geen liggende foto te krijgen.
///
/// **Waarom dit bestaat.** De app kende één achtergrond per artiest en die is bijna altijd 16:9.
/// GEMETEN op 10-09-2026 door `EditorialeKop` op zes schermen te pompen: de kop is overal 682 tot
/// 738 punten hoog. Op een iPad rechtop is dat 834 × 738 — verhouding 1,13 — en een bron van 1,78
/// die daar met `BoxFit.cover` in gaat verliest 36% van zijn breedte. Je ziet een uitvergrote
/// middenstrook waar een foto hoorde te staan.
///
/// Deze toets bewaakt de som die bepaalt WELKE keuze getekend wordt, en de terugvalladder eromheen.
/// Allebei zijn ze puur, dus ze horen hier en niet in een widgettoets — en juist omdat ze puur zijn
/// kan een verkeerd getal er stil in blijven zitten tot iemand met een iPad in de hand staat.
library;

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/beeldvorm.dart';

void main() {
  group('welke vorm heeft dit scherm', () {
    test('DE KERN: de toestellen die deze app draait', () {
      // De maten komen van de echte toestellen, niet uit een ontwerpschets.
      expect(beeldvormVan(scherm: const Size(834, 1194), tv: false), Beeldvorm.staand,
          reason: 'een iPad rechtop krijgt anders de liggende foto uitgerekt tot een band');
      expect(beeldvormVan(scherm: const Size(1194, 834), tv: false), Beeldvorm.liggend,
          reason: 'draai je hem, dan hoort de liggende foto terug te komen');
      expect(beeldvormVan(scherm: const Size(411, 915), tv: false), Beeldvorm.staand,
          reason: 'een telefoon rechtop is het meest staande scherm dat er is');
      expect(beeldvormVan(scherm: const Size(915, 411), tv: false), Beeldvorm.liggend);
      expect(beeldvormVan(scherm: const Size(1456, 819), tv: false), Beeldvorm.liggend,
          reason: 'het venster op de pc is de gewone stand en die mag niet omslaan');
    });

    test('DE VAL: een televisie is ALTIJD liggend, hoe de maat ook binnenkomt', () {
      // Een toestel aan de muur draai je niet. Meldt het zich toch staand — en dat gebeurt: een
      // Shield die op een gedraaide monitor hangt, een emulator — dan is dat geen reden om de
      // achtergrond om te gooien, want van hieruit is niet na te kijken wat er echt staat.
      expect(beeldvormVan(scherm: const Size(960, 540), tv: true), Beeldvorm.liggend);
      expect(beeldvormVan(scherm: const Size(540, 960), tv: true), Beeldvorm.liggend,
          reason: 'een tv die zich staand meldt zou hier de staande achtergrond krijgen');
    });

    test('DE GRENS: de dode band, zodat een gesleept venster niet blijft omklappen', () {
      // Precies op de grens ligt 1,15. Eronder blijft het liggend, ook al is het scherm hoger dan
      // breed — dat is de bedoeling: zonder die band wisselt een venster dat je door het vierkant
      // sleept bij elke trilling van achtergrond, en elke wissel is een nieuwe decodering.
      expect(beeldvormVan(scherm: const Size(900, 1000), tv: false), Beeldvorm.liggend,
          reason: 'verhouding 1,11 zit in de dode band en hoort de vorige stand te houden');
      expect(beeldvormVan(scherm: const Size(900, 1035), tv: false), Beeldvorm.staand,
          reason: 'precies op 1,15 hoort hij wel om te slaan');
      expect(beeldvormVan(scherm: const Size(900, 1034), tv: false), Beeldvorm.liggend,
          reason: 'één punt onder de grens nog niet');
    });

    test('DE GRENS: een maat die er nog niet is valt niet om', () {
      // Een toets die pompt vóór de eerste frame krijgt Size.zero. Dat mag geen uitzondering geven.
      expect(beeldvormVan(scherm: Size.zero, tv: false), Beeldvorm.liggend);
      expect(beeldvormVan(scherm: const Size(double.infinity, 800), tv: false), Beeldvorm.liggend);
      expect(beeldvormVan(scherm: const Size(800, double.nan), tv: false), Beeldvorm.liggend);
      expect(beeldvormVan(scherm: const Size(-10, 800), tv: false), Beeldvorm.liggend);
    });
  });

  group('de terugvalladder', () {
    test('DE KERN: staand mag terugvallen op liggend, andersom niet', () {
      expect(achtergrondSoorten(Beeldvorm.staand), [kAchtergrondStaand, kAchtergrond],
          reason: 'zonder staande keuze hoort de foto die je zélf koos alsnog getoond te worden');
      expect(achtergrondSoorten(Beeldvorm.liggend), [kAchtergrond],
          reason: 'een staande 2:3 in een band van 2,5:1 is een reep voorhoofd, geen achtergrond');
    });

    test('DE VAL: de staande keuze staat VOORAAN bij een staand scherm', () {
      // Stond hij achteraan, dan zou de liggende altijd winnen en had het kiezen geen zin — het
      // soort storing waarbij de knop werkt en je nooit iets ziet veranderen.
      expect(achtergrondSoorten(Beeldvorm.staand).first, kAchtergrondStaand);
    });
  });

  group('de soortenlijst die over het net gaat', () {
    test('DE VAL: elke soort uit de ladder staat ook in de synchronisatielijst', () {
      // Dit is de stille storing die deze lijst moet tegenhouden: een soort toevoegen aan de ladder
      // en vergeten in `lan/catalog.dart`. De iPad maakt dan de keuze, de pc bewaart hem, en bij de
      // volgende catalogusduw is hij weg — want een cliënt leest uit de doorgestuurde map.
      for (final vorm in Beeldvorm.values) {
        for (final soort in achtergrondSoorten(vorm)) {
          expect(kArtSoorten, contains(soort),
              reason: '"$soort" wordt wel gekozen maar niet meegestuurd naar je iPad');
        }
      }
    });

    test('DE GRENS: de bestaande soorten blijven erin en houden hun naam', () {
      // Deze twee staan al in ieders artist_art_choice.json en in elke catalogus die al verstuurd
      // is. Ze hernoemen zou elke bestaande keuze onvindbaar maken.
      expect(kArtSoorten, containsAll(<String>['portrait', 'backdrop', 'logo']));
      expect(kAchtergrond, 'backdrop');
      expect(kArtSoorten.toSet().length, kArtSoorten.length, reason: 'geen dubbele soorten');
    });

    test('DE VAL: de staande soort heet geen "portrait"', () {
      // `'portrait'` betekent in deze app al iets anders: het ronde portret op de personenpagina.
      expect(kAchtergrondStaand, isNot('portrait'));
      expect(kAchtergrondStaand, isNot(kAchtergrond));
    });
  });
}
