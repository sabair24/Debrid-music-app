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

import 'dart:io';

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

  test('een herscan die maar één album vraagt, wist de rest van de cache NIET', () async {
    // Dit ging mis en het was aan de code niet te zien. Het opruimen ging op de lijst die GELEZEN
    // moest worden, en die is bij een herscan bijna leeg: de albums dragen hun hoes al in het
    // geheugen mee, dus wordt er alleen naar de nieuwe gevraagd. Alles wat er niet in zat vloog eruit.
    //
    // Een herscan volgt op elke voltooide download, dus in de praktijk sloopte één binnengehaald
    // nummer de hele cache. Gemeten op de echte pc: van 236 bestanden en 125 MB naar 76 lege
    // merkbestanden en 0 MB, waarna de eerstvolgende start weer 9 seconden hoezen las.
    final krab = Directory.systemTemp.createTempSync('dm_hoes_');
    addTearDown(() {
      try {
        krab.deleteSync(recursive: true);
      } catch (_) {}
    });
    final cache = '${krab.path}${Platform.pathSeparator}hoescache';

    File nummer(String naam) => File('${krab.path}${Platform.pathSeparator}$naam')
      ..writeAsBytesSync(List<int>.filled(64, 0));

    final a = nummer('a.flac').path;
    final b = nummer('b.flac').path;

    // Ronde 1: allebei gevraagd. Geen van beide is een echte FLAC, dus er komt geen hoes uit — maar
    // er hoort wel voor allebei een merk "hier zit er geen in" te staan.
    await readCoversInIsolate([a, b], cache, [a, b]);
    expect(Directory(cache).listSync().length, 2);

    // Ronde 2: alleen a gevraagd (b had zijn hoes al), maar beide albums bestaan nog.
    await readCoversInIsolate([a], cache, [a, b]);
    expect(Directory(cache).listSync().length, 2,
        reason: 'b staat nog in de bibliotheek, dus zijn regel hoort te blijven');

    // En wat er ECHT niet meer is, gaat wel weg.
    await readCoversInIsolate([a], cache, [a]);
    expect(Directory(cache).listSync().length, 1);
  });
}
