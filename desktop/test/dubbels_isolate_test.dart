/// De dubbelzoeker op een andere isolate — en of hij daar HETZELFDE zegt.
///
/// Dit is de enige toets die telt bij deze verhuizing. De afweging beslist welk bestand naar `_dubbel`
/// gaat en welk er blijft staan; wijkt de isolate ook maar in één paar af, dan verplaatst de app
/// muziek op andere gronden dan voorheen, zonder dat er iets klapt.
///
/// **De stille val die dit had kunnen worden.** `firstIsBetter` raadpleegt twee kaarten in het
/// geheugen: `isVasteKeuze` (wat de gebruiker zelf koos) en `bewezenNep` (wat als nagemaakt gemeten
/// is). Een isolate begint met een LEGE kopie van alle globale staat, dus daar zouden allebei overal
/// `false` teruggeven — en dan vallen precies de twee regels weg die BOVEN de kwaliteitsgronden
/// staan. Geen foutmelding, alleen een andere winnaar. Daarom gaan ze als [Voorkennis] mee, en daarom
/// staan er hieronder twee toetsen die alleen dáárover gaan.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/vaste_keuze.dart';

const echteBibliotheek = r'D:\Flac music 2024';
final slaOver = Directory(echteBibliotheek).existsSync() ? null : 'geen $echteBibliotheek';

void main() {
  group('firstIsBetter met meegegeven voorkennis', () {
    late Directory krab;

    setUp(() => krab = Directory.systemTemp.createTempSync('dm_dub_'));
    tearDown(() {
      try {
        krab.deleteSync(recursive: true);
      } catch (_) {}
    });

    File maak(String naam, int bytes) => File('${krab.path}${Platform.pathSeparator}$naam')
      ..writeAsBytesSync(List<int>.filled(bytes, 0));

    test('zonder voorkennis beslist de grootte', () {
      final groot = maak('a.flac', 2000);
      final klein = maak('b.flac', 1000);
      expect(firstIsBetter(groot, klein, kennis: (vast: <String>{}, nep: <String>{})), isTrue);
    });

    test('wat de gebruiker zelf koos verliest niet, ook niet van een groter bestand', () {
      // Dit is de regel die het hoogst staat. Zou de isolate hem missen, dan gooit een veegbeurt
      // precies de kopie weg die de gebruiker met de hand had uitgezocht.
      final groot = maak('a.flac', 2000);
      final gekozen = maak('b.flac', 1000);
      final kennis = (vast: <String>{sleutelVoor(gekozen.path)}, nep: <String>{});
      expect(firstIsBetter(groot, gekozen, kennis: kennis), isFalse);
      expect(firstIsBetter(gekozen, groot, kennis: kennis), isTrue);
    });

    test('wat bewezen nep is verliest, ook al is het groter', () {
      // Een mp3 die naar FLAC is omgezet is vaak GROTER dan het origineel; op grootte alleen zou de
      // nagemaakte kopie stelselmatig winnen.
      final nep = maak('a.flac', 2000);
      final echt = maak('b.flac', 1000);
      final kennis = (vast: <String>{}, nep: <String>{echtheidSleutelVoor(nep.path)});
      expect(firstIsBetter(nep, echt, kennis: kennis), isFalse);
      expect(firstIsBetter(echt, nep, kennis: kennis), isTrue);
    });
  });

  test('de isolate geeft exact hetzelfde antwoord als de hoofddraad', () async {
    // Over de ECHTE bibliotheek, want dit gaat over de data die er is: welke albums fragmenten van
    // elkaar zijn, en welke kopie per nummer wint. Een verzonnen opstelling raakt dat niet.
    final lib = LibraryStore()..rootPath = echteBibliotheek;
    await lib.scan();

    final opDeDraad = lib.redundantAlbums();
    final opDeIsolate = await lib.redundantAlbumsAsync();

    // ignore: avoid_print
    print('dubbels: ${opDeDraad.length} op de draad, ${opDeIsolate.length} op de isolate');

    expect(opDeIsolate.length, opDeDraad.length, reason: 'evenveel gevonden');

    String beschrijf(RedundantAlbum r) => '${r.source.artist}|${r.source.title} -> '
        '${r.target.artist}|${r.target.title} '
        '[${[for (final p in r.pairs) '${p.dup.path}>${p.owned.path}:${p.dupWins}'].join(',')}]';

    final a = [for (final r in opDeDraad) beschrijf(r)]..sort();
    final b = [for (final r in opDeIsolate) beschrijf(r)]..sort();
    expect(b, a, reason: 'elk paar, elke winnaar, exact hetzelfde');

    // En de objecten moeten de ECHTE zijn, niet kopieën die er hetzelfde uitzien: consolidate()
    // verplaatst hun bestanden en de dialoog vergelijkt met identical().
    for (final r in opDeIsolate) {
      expect(lib.albums.any((x) => identical(x, r.source)), isTrue,
          reason: 'source moet een album uit de winkel zijn');
      expect(lib.albums.any((x) => identical(x, r.target)), isTrue,
          reason: 'target moet een album uit de winkel zijn');
      for (final p in r.pairs) {
        expect(r.source.tracks.any((t) => identical(t, p.dup)), isTrue);
        expect(r.target.tracks.any((t) => identical(t, p.owned)), isTrue);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 6)), skip: slaOver);
}
