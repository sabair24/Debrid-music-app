/// normKey onthoudt zijn uitkomst (Shield, 17-10-2026: de artiestpagina rekende bij elke herbouw voor
/// duizenden albums artistKey uit). Onthouden mag alleen als het antwoord precies hetzelfde blijft.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/organize.dart';

void main() {
  test('dezelfde antwoorden, de eerste en de tweede keer', () {
    for (final (in_, uit) in const [
      ('Beyoncé', 'beyonce'),
      ("Guns N' Roses", 'guns n roses'),
      ('The Jackson 5', 'the jackson 5'),
      ('  Lady   GaGa ', 'lady gaga'),
    ]) {
      expect(normKey(in_), uit);
      expect(normKey(in_), uit, reason: 'uit het geheugen');
    }
    expect(artistKey('The Jacksons'), 'jacksons');
  });

  test('voorbij de grens wordt er gewoon weer gerekend, met hetzelfde antwoord', () {
    final eerst = normKey('Céline Dion');
    for (var i = 0; i < kNormGeheugenMax + 50; i++) {
      normKey('naam nummer $i');
    }
    expect(normKey('Céline Dion'), eerst);
    expect(normKey('Naam Nummer 7'), 'naam nummer 7');
  });
}
