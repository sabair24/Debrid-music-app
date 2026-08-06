/// Bestaat deze plaat écht in hi-res, of heeft iemand opgeschaald?
///
/// Die vraag valt niet aan één bestand te beantwoorden — meten kan pas na het binnenhalen. Wat wél
/// gratis is: wat álle peers samen aanbieden. Deze test legt vast dat die redenering klopt op de
/// vijf gevallen waar de spectrumproef achteraf het antwoord van weet.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/quality.dart';

void main() {
  group('gemeten op 06-08-2026, waarheid uit de spectrumproef', () {
    // De drie Stromae-nummers waren alle drie opgeschaald: 24/96 in de kop, niets boven 22 kHz in
    // het spectrum, en een muur rond 17,5 kHz van de mp3 waar ze uit kwamen.
    test('Stromae — Ta fête: 5 tegen 258, de 96 kHz-claim telt niet', () {
      expect(hiResIsMinderheidsclaim(hiRes: 5, cdRate: 258), isTrue);
    });
    test('Stromae — Formidable: 8 tegen 475', () {
      expect(hiResIsMinderheidsclaim(hiRes: 8, cdRate: 475), isTrue);
    });
    test('Stromae — Papaoutai: 14 tegen 580', () {
      expect(hiResIsMinderheidsclaim(hiRes: 14, cdRate: 580), isTrue);
    });

    // En de tegenproef. Deze twee zijn aantoonbaar écht: de proef vond inhoud bóven 22 kHz, en dat
    // laat opschalen nooit achter. Hier moet de regel dus juist ZWIJGEN.
    test('Adele — Rolling in the Deep: 76 tegen 808, echte hi-res blijft staan', () {
      expect(hiResIsMinderheidsclaim(hiRes: 76, cdRate: 808), isFalse);
    });
    test('Michael Jackson — The Way You Make Me Feel: 585 tegen 1627', () {
      expect(hiResIsMinderheidsclaim(hiRes: 585, cdRate: 1627), isFalse);
    });

    test('de drempel ligt tussen de twee groepen in, met marge naar beide kanten', () {
      // hoogste neppe 14/580 = 0,024 · laagste echte 76/808 = 0,094 · drempel 0,05.
      expect(14 / 580, lessThan(hiResMinderheidsDeel / 2));
      expect(76 / 808, greaterThan(hiResMinderheidsDeel * 1.8));
    });
  });

  group('waar de regel bewust zwijgt', () {
    test('zonder hi-res-aanbod valt er niets te betwisten', () {
      expect(hiResIsMinderheidsclaim(hiRes: 0, cdRate: 500), isFalse);
    });

    test('op kleine getallen zegt een aandeel niets', () {
      // Een zeldzame plaat met vier aanbieders: één op drie is daar geen meerderheid maar toeval.
      // Liever een gemiste opschaling dan een échte hi-res weggezet op grond van te weinig bewijs.
      expect(hiResIsMinderheidsclaim(hiRes: 1, cdRate: 19), isFalse);
      expect(hiResIsMinderheidsclaim(hiRes: 1, cdRate: 3), isFalse);
      expect(hiResIsMinderheidsclaim(hiRes: 0, cdRate: 0), isFalse);
    });

    test('vanaf het minimum doet hij weer mee', () {
      expect(hiResIsMinderheidsclaim(hiRes: 1, cdRate: minimumCdRate + 1), isTrue);
    });
  });

  group('de sample rates omzetten naar dat oordeel', () {
    test('telt boven en onder 48 kHz uit elkaar', () {
      final veel441 = [for (var i = 0; i < 100; i++) 44100];
      expect(hiResClaimTeltNiet([...veel441, 96000]), isTrue);
      expect(hiResClaimTeltNiet([...veel441, for (var i = 0; i < 20; i++) 96000]), isFalse);
    });

    test('48 kHz hoort bij de cd-kant, niet bij hi-res', () {
      // 24/48 is geen hi-res: de bovenband loopt tot 24 kHz en daar zit niets bijzonders.
      final ratesMet48 = [for (var i = 0; i < 30; i++) 48000, 96000];
      expect(hiResClaimTeltNiet(ratesMet48), isTrue,
          reason: '48 kHz moet als cd-kant meetellen, anders is er geen bevolking om mee te vergelijken');
    });

    test('onbekende rates tellen aan geen van beide kanten mee', () {
      // Een peer die niets meldt zegt niets. Zou je die bij de cd-kant optellen, dan zou een lijst
      // vol zwijgende peers elke hi-res wegdrukken op grond van ontbrekende gegevens.
      expect(hiResClaimTeltNiet([null, null, null, 96000, 96000]), isFalse);
      expect(hiResClaimTeltNiet([for (var i = 0; i < 50; i++) 0, 96000]), isFalse);
      expect(hiResClaimTeltNiet([for (var i = 0; i < 50; i++) 22050, 96000]), isFalse);
    });
  });
}
