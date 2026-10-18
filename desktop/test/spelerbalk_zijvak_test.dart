/// De knoppen in het midden van de brede spelerbalk passen tussen de twee zijvakken.
///
/// Op de Shield (18-10-2026) liepen ze aan beide kanten het vak in, en met "Verder op …" rechts lag de
/// wachtrijknop half en de speakerknop helemaal onder dat knopje. Zie [spelerZijvak].
library;

import 'dart:io';

import 'package:debridmusic/main.dart' show kSpelerKnoppen, spelerZijvak;
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Wat er voor de knoppen overblijft: de breedte min de randen en de twee vakken.
  double midden(double breedte, double rand) => breedte - rand - 2 * spelerZijvak(breedte, rand: rand);

  test('de Shield: 960 punten, 18 binnenmarge en 48 overscan aan elke kant', () {
    const rand = 36.0 + 96;
    expect(midden(960, rand), greaterThanOrEqualTo(kSpelerKnoppen),
        reason: 'hier bleef 268 over voor 340 aan knoppen');
    expect(spelerZijvak(960, rand: rand), greaterThan(200),
        reason: 'het nummer links en "Verder op …" rechts houden genoeg ruimte');
  });

  test('een pc-venster en een iPad: de knoppen passen, op elke breedte boven de ondergrens', () {
    for (var b = 700.0; b <= 2560; b += 10) {
      final v = spelerZijvak(b, rand: 36);
      if (v > 96) expect(midden(b, 36), greaterThanOrEqualTo(kSpelerKnoppen - .001), reason: 'breedte $b');
    }
  });

  test('een breed venster houdt zijn 280 aan elke kant', () {
    expect(spelerZijvak(1440, rand: 36), 280);
    expect(spelerZijvak(1920, rand: 36), 280);
  });

  test('aangesloten: de balk rekent met zijn eigen randen', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('final side = spelerZijvak(width, rand: 36 + tvOverscan.horizontal);'));
    expect(main, isNot(contains('(width - 336) / 2')));
  });
}
