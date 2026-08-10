/// De naam waaronder een ingebedde hoes bewaard wordt — over een HERSTART heen.
///
/// **Waarom deze toets bestaat.** De eerste versie van de hoescache zag er binnen één proces perfect
/// uit en deed in de app niets. De sleutel werd gebouwd met `Object.hash`, en die is per proces
/// geseed. Drie processen achter elkaar, met exact dezelfde invoer:
///
///     Object.hash(pad, mtime, grootte)  ->  1c67de33 / 1ec744fb / 106b7271
///     pad.hashCode                      ->  28c5c741 / 28c5c741 / 28c5c741
///
/// De meetbank draaide drie scans in hetzelfde proces, dus dezelfde seed, dus alles groen en de
/// hoezen "uit cache" in 72 ms. De app schreef intussen bij élke start 238 nieuwe bestanden, las
/// alles opnieuw en ruimde de vorige lichting op: 17,4 seconden, elke keer. Zie de les
/// "groen is niet goed" — de bank klopte en de meting aan de bron niet.
///
/// **Waarom een vaste verwachte uitkomst en geen berekening.** Een toets die de sleutel zelf
/// uitrekent en met zichzelf vergelijkt, draait in hetzelfde proces en zou dus precies deze fout
/// weer missen. Het getal hieronder is in een ÁNDER proces bepaald en staat hier hard. Een sleutel
/// die van een seed afhangt kan het per definitie niet halen.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/library.dart';

void main() {
  const pad = r'D:\Flac music 2024\Adele\21\01 - Rolling in the Deep.flac';
  const mtime = 1786182445506;
  const grootte = 51234567;

  test('dezelfde hoes krijgt altijd dezelfde naam, ook na een herstart', () {
    expect(
      hoesSleutel(pad, mtime, grootte),
      '893c6115_ui4uf_msk6wrlu',
      reason: 'buiten dit proces bepaald — wijkt dit af, dan hangt de naam van iets vluchtigs af '
          'en vindt de app na een herstart zijn eigen hoezen niet terug',
    );
  });

  test('een bewerkt of vervangen bestand krijgt een andere naam', () {
    final basis = hoesSleutel(pad, mtime, grootte);
    expect(hoesSleutel(pad, mtime + 1, grootte), isNot(basis), reason: 'andere mtime');
    expect(hoesSleutel(pad, mtime, grootte + 1), isNot(basis), reason: 'andere grootte');
    expect(hoesSleutel('${pad}x', mtime, grootte), isNot(basis), reason: 'ander pad');
  });

  test('de naam is bruikbaar als bestandsnaam', () {
    final s = hoesSleutel(pad, mtime, grootte);
    expect(RegExp(r'^[a-z0-9_]+$').hasMatch(s), isTrue, reason: 'geen \\ / : * ? " < > |');
  });
}
