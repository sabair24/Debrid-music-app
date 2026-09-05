/// Namen die de app verminkt toonde terwijl de goede spelling er gewoon stond.
///
/// **Gevonden bij het doorlichten van de bibliotheek op 05-09-2026**, op uitdrukkelijk verzoek:
/// *"ga verder blijf zoeken naar fouten [...] artiestnamen, titels, variaties erop, noem maar op."*
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/mojibake.dart';
import 'package:debridmusic/organize.dart';

void main() {
  group('een accent wint van de meerderheid', () {
    // Rippers en tagprogramma's STRIPPEN accenten, ze verzinnen ze niet. Staan twee spellingen van
    // dezelfde naam naast elkaar en schelen ze alleen in tekens, dan is de accentversie de echte --
    // hoe vaak de kale ook voorkomt. De meerderheid is juist het bewijs van de schade.
    test('DE KERN: de drie gevallen uit de bibliotheek', () {
      // Tien tegen één, en de ene heeft gelijk.
      expect(canonicalName({'Edith Piaf': 10, 'Édith Piaf': 1}), 'Édith Piaf');
      expect(canonicalName({'Hélène Segara': 4, 'Hélène Ségara': 3}), 'Hélène Ségara');
      expect(canonicalName({'Tiesto': 3, 'Tiësto': 2}), 'Tiësto');
    });

    test('meer accenten wint van minder', () {
      // Halfbakken herstel is ook schade: één accent terug en het andere niet.
      expect(canonicalName({'Hélène Segara': 5, 'Hélène Ségara': 1, 'Helene Segara': 9}),
          'Hélène Ségara');
    });

    test('en zonder accenten beslist het aantal nog gewoon', () {
      expect(canonicalName({'Lady Gaga': 7, 'Lady GaGa': 4}), 'Lady Gaga');
      expect(canonicalName({'P!nk': 23, 'P!NK': 1}), 'P!nk');
    });

    test('bij evenveel accenten wint de nette schrijfwijze', () {
      // De bestaande regels blijven eronder liggen: eerst het aantal, dan rare hoofdletters.
      expect(canonicalName({'Beyoncé': 3, 'BEYONCÉ': 3}), 'Beyoncé');
    });

    test('één spelling blijft één spelling', () {
      expect(canonicalName({'Adele': 12}), 'Adele');
    });
  });

  group('tekst die één keer te veel gecodeerd is', () {
    // `unmojibake` bestond al, maar werd alleen op CATALOGUSdata losgelaten -- nooit op de tags van
    // je eigen bestanden. Sinds 05-09-2026 loopt elke Track er langs, in `_trackFromMap`: dezelfde
    // trechter waar `zonderKantnummer` al stond, en om dezelfde reden ("werkt na de update" in
    // plaats van "werkt na een volledige herscan").
    //
    // Gemeten over de bibliotheek: 2 van 1255 nummers waren stuk, en na de wijziging 0.
    test('DE KERN: de twee gevallen uit de bibliotheek', () {
      expect(unmojibake('BeyoncÃ©'), 'Beyoncé');
      expect(unmojibake('Lâ€™Envie'), 'L’Envie');
    });

    test('en gezonde tekst blijft ongemoeid', () {
      for (final s in ['Beyoncé', 'L’Envie', 'Édith Piaf', 'Tiësto', 'Adele', '', 'P!nk']) {
        expect(unmojibake(s), s, reason: s);
      }
    });
  });
  artiestVoorop();
}

/// De eigen artiestnaam vooraan een titel: "Whigfield - Sexy Eyes".
///
/// **De strengheid IS de functie, en dat is gemeten.** Over de bibliotheek (1255 nummers) staat de
/// artiestnaam bij zeven nummers ergens in de titel — en zes daarvan horen daar thuis. Een regel op
/// "bevat" zou dus zes goede titels slopen om er één te repareren.
void artiestVoorop() {
  group('zonderArtiestVoorop', () {
    test('DE KERN: het ene echte geval uit de bibliotheek', () {
      expect(zonderArtiestVoorop("Whigfield - Sexy Eyes (David's Epic Edit)", 'Whigfield'),
          "Sexy Eyes (David's Epic Edit)");
    });

    test('DE TEGENPROEF: de zes die het NIET mogen raken', () {
      // Stuk voor stuk uit de doorlichting. Zou de regel op "bevat" gaan, dan gaan deze eraan.
      expect(zonderArtiestVoorop('Beyoncé Interlude', 'Beyoncé'), 'Beyoncé Interlude');
      expect(zonderArtiestVoorop('Ho Ho Vengaboys!', 'Vengaboys'), 'Ho Ho Vengaboys!');
      expect(zonderArtiestVoorop('This Beat is Technotronic (Dust Mix)', 'Technotronic'),
          'This Beat is Technotronic (Dust Mix)');
      expect(
          zonderArtiestVoorop(
              'Against All Odds (Take A Look at Me Now) (feat. Westlife)', 'Westlife'),
          'Against All Odds (Take A Look at Me Now) (feat. Westlife)');
      expect(
          zonderArtiestVoorop(
              'If I Lose Myself (Alesso vs. OneRepublic extended remix)', 'OneRepublic'),
          'If I Lose Myself (Alesso vs. OneRepublic extended remix)');
      expect(
          zonderArtiestVoorop(
              "C U When U Get There (Coolio's Album Version)", 'Coolio Featuring 40 Thevz'),
          "C U When U Get There (Coolio's Album Version)");
    });

    test('een ANDERE naam vooraan blijft staan', () {
      // "Moby - Porcelain" bij een bestand van Air is geen artiestprefix maar iets anders, en dan
      // weet deze regel het niet. Dan blijft de titel zoals hij is.
      expect(zonderArtiestVoorop('Moby - Porcelain', 'Air'), 'Moby - Porcelain');
    });

    test('en een gastcredit telt mee als dezelfde artiest', () {
      // De hoofdartiest wordt vergeleken, niet de hele credit.
      expect(zonderArtiestVoorop('Missy Elliott - One Minute Man', 'Missy Elliott feat. Ludacris'),
          'One Minute Man');
    });

    test('zonder streepje met spaties gebeurt er niets', () {
      expect(zonderArtiestVoorop('Whigfield-Sexy Eyes', 'Whigfield'), 'Whigfield-Sexy Eyes');
    });
  });
}
