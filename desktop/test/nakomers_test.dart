/// De namen van het taalmodel komen ná de start binnen, en schuiven er dan bij.
///
/// **Waarom dat zo moest.** Saber vulde op 12-09-2026 zijn AI-sleutel in en de eerste echte radio
/// leek te werken: `warm.log` meldde *"24 namen van het model, 8 bekend — Janet Jackson, Quincy
/// Jones, Rockwell*, Toto*, Patrice Rushen*…"*. Maar in de wachtrij stond er geen énkele van. De
/// oorzaak stond in de tijdstempels: de radio startte om 19:37:00 en het antwoord kwam om 19:37:30.
/// De eerste opzet liet `mixRadio` acht seconden wachten — een grens die dus élke keer afliep,
/// waarna er met een lege lijst werd doorgelopen. Een tijdslimiet die altijd afloopt is geen
/// tijdslimiet maar een uitschakelaar, en hij was stil.
///
/// Langer wachten kan niet: een radio die na de knop een halve minuut zwijgt is stuk. Dus begint hij
/// met wat Deezer meteen geeft en schuiven de namen van het model erbij zodra ze er zijn.
library;

import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:flutter_test/flutter_test.dart';

Radioplek _p(String artiest, String titel) => Radioplek(artiest: artiest, titel: titel);

void main() {
  test('DE KERN: wat nog niet in het plan staat, mag erbij', () {
    final plan = [_p('Michael Jackson', 'Billie Jean'), _p('Prince', 'Kiss')];
    final extra = [_p('Toto', 'Africa'), _p('Patrice Rushen', 'Forget Me Nots')];

    final uit = nieuweNakomers(plan, extra);

    expect([for (final p in uit) p.artiest], ['Toto', 'Patrice Rushen']);
  });

  test('DE VAL: wat er al staat komt er niet twee keer in', () {
    // Een dubbel nummer levert geen foutmelding op — je hoort het gewoon twee keer.
    final plan = [_p('Prince', 'Kiss')];
    final extra = [_p('prince', 'KISS'), _p('  Prince  ', ' Kiss '), _p('Toto', 'Africa')];

    final uit = nieuweNakomers(plan, extra);

    expect([for (final p in uit) p.artiest], ['Toto']);
  });

  test('DE VAL: nakomers onderling ook maar één keer', () {
    final uit = nieuweNakomers(const [], [_p('Toto', 'Africa'), _p('Toto', 'Africa')]);

    expect(uit, hasLength(1));
  });

  test('DE GRENS: een halve naam schuift niet mee', () {
    final uit = nieuweNakomers(const [], [_p('', 'Africa'), _p('Toto', '   '), _p('Toto', 'Rosanna')]);

    expect([for (final p in uit) p.titel], ['Rosanna']);
  });

  test('DE GRENS: niets erbij is niets erbij', () {
    expect(nieuweNakomers([_p('Prince', 'Kiss')], const []), isEmpty);
  });

  group('waar ze terechtkomen', () {
    Radioplek gedaan(String a, String t) => Radioplek(artiest: a, titel: t)..stand = Haalstand.inRij;

    test('DE KERN: nakomers schuiven om en om tussen wat nog moet komen', () {
      // Achteraan zou betekenen: pas na veertig nummers - ruim twee uur - hoor je de eerste. En
      // met de bekende vooraan kwam er in zeven minuten radio precies EEN van de twaalf voorbij.
      final plan = [_p('Deezer 1', 'a'), _p('Deezer 2', 'b'), _p('Deezer 3', 'c')];
      final nieuw = [_p('Toto', 'Africa'), _p('Rockwell', 'Somebody')];

      final uit = mengNakomers(plan, nieuw);

      expect([for (final p in uit) p.artiest],
          ['Toto', 'Deezer 1', 'Rockwell', 'Deezer 2', 'Deezer 3'],
          reason: 'op de nakomer heb je gewacht; die hoort niet achter de bekende aan te sluiten');
    });

    test('DE VAL: wat al speelt of in de rij staat blijft onaangeroerd', () {
      // Dat is de volgorde die je op dit moment hoort; daar mag niets tussen springen.
      final plan = [gedaan('Nu', 'x'), gedaan('Straks', 'y'), _p('Deezer', 'z')];

      final uit = mengNakomers(plan, [_p('Toto', 'Africa')]);

      expect([for (final p in uit) p.artiest], ['Nu', 'Straks', 'Toto', 'Deezer'],
          reason: 'Nu en Straks staan al in de rij en mogen niet verschuiven');
    });

    test('DE GRENS: meer nakomers dan plekken - dan volgen ze gewoon', () {
      final uit = mengNakomers([_p('Deezer', 'z')],
          [_p('Toto', 'Africa'), _p('Rockwell', 'Somebody'), _p('Shalamar', 'A Night')]);

      expect([for (final p in uit) p.artiest], ['Toto', 'Deezer', 'Rockwell', 'Shalamar']);
    });

    test('DE GRENS: niets erbij laat het plan precies zoals het was', () {
      final plan = [_p('Deezer 1', 'a'), _p('Deezer 2', 'b')];

      expect(mengNakomers(plan, const []), same(plan));
    });
  });
}
