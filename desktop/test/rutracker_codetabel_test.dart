/// Wat er werkelijk over de lijn gaat bij het aanmelden op RuTracker.
///
/// **Waarom dit een toets waard is.** RuTracker is een cp1251-site: `login.php` leest je aanmelding
/// als windows-1251. Deze app stuurde UTF-8. Dat is met het oog niet te zien — er staat gewoon
/// `login=вход` in de code — en het gevolg is een aanmelding die wordt afgewezen met een wachtwoord
/// dat klopt. Precies de fout waarvan de gebruiker zegt: "ik ben nochtans zeker van mijn wachtwoord".
///
/// De getallen hieronder zijn niet verzonnen maar de codetabel zelf. Ze staan er zodat een
/// toekomstige "opruiming" naar `Uri.encodeQueryComponent` meteen rood wordt.
library;

import 'package:debridmusic/rutracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('de bytes van windows-1251', () {
    test('ASCII blijft ASCII', () {
      expect(RuTrackerService.cp1251Byte('A'.codeUnitAt(0)), 0x41);
      expect(RuTrackerService.cp1251Byte('~'.codeUnitAt(0)), 0x7E);
    });

    test('de Russische letters liggen aaneengesloten vanaf 0xC0', () {
      expect(RuTrackerService.cp1251Byte('А'.runes.first), 0xC0);
      expect(RuTrackerService.cp1251Byte('я'.runes.first), 0xFF);
      expect(RuTrackerService.cp1251Byte('Ё'.runes.first), 0xA8, reason: 'die valt buiten de rij');
      expect(RuTrackerService.cp1251Byte('ё'.runes.first), 0xB8);
    });

    test('wat er niet in past levert null op, geen vraagteken', () {
      // Een teken stilletjes vervangen door iets anders is erger dan weigeren: dan verstuur je een
      // ánder wachtwoord dan de gebruiker intikte, en blijft het raadsel bestaan.
      expect(RuTrackerService.cp1251Byte('é'.runes.first), isNull);
      expect(RuTrackerService.cp1251Byte('€'.runes.first), isNull);
      expect(RuTrackerService.cp1251Byte('☃'.runes.first), isNull);
    });
  });

  group('de knopwaarde die de aanmelding compleet maakt', () {
    test('вход gaat als vier bytes, niet als twaalf', () {
      // In UTF-8 is dit %D0%B2%D1%85%D0%BE%D0%B4 — twaalf bytes onzin voor een cp1251-site. Dit is
      // de regel waar het al die tijd op stukliep.
      expect(RuTrackerService.cp1251Form('вход'), '%E2%F5%EE%E4');
    });
  });

  group('een waarde klaarmaken voor het formulier', () {
    test('gewone tekens blijven leesbaar', () {
      expect(RuTrackerService.cp1251Form('saber24'), 'saber24');
      expect(RuTrackerService.cp1251Form('a-b_c.d~e'), 'a-b_c.d~e');
    });

    test('een spatie wordt %20 en niet +', () {
      // Met `+` als spatie zou een wachtwoord met een echte plus erin stilletjes een spatie worden.
      expect(RuTrackerService.cp1251Form('een twee'), 'een%20twee');
      expect(RuTrackerService.cp1251Form('a+b'), 'a%2Bb');
    });

    test('leestekens die iets betekenen in een formulier gaan gecodeerd mee', () {
      expect(RuTrackerService.cp1251Form('a&b=c'), 'a%26b%3Dc');
      expect(RuTrackerService.cp1251Form('100%'), '100%25');
    });

    test('een wachtwoord met een letter die cp1251 niet kent wordt geweigerd', () {
      // Null betekent hier: hier valt niets te versturen. De app zegt dat dan, in plaats van een
      // aanmelding te doen die nooit kan lukken.
      expect(RuTrackerService.cp1251Form('wachtwoordé'), isNull);
      expect(RuTrackerService.cp1251Form('naïef'), isNull);
    });

    test('leeg blijft leeg', () {
      expect(RuTrackerService.cp1251Form(''), '');
    });
  });
}
