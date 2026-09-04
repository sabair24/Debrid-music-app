/// Een map die leegloopt hoort weg te gaan — ook als het eigen zijbestand van de app er nog in ligt.
///
/// **Waarom dit bestaat.** Saber, 04-09-2026: *"verwijderen van pc moet het ook weg zijn dan e, want
/// heb de indruk soms dat er paar blijven staan"*. Het bestand ging wél weg; de MAP bleef staan.
/// `pruneVacated` en `sweepEmptyFolders` vegen alleen een map op die niets bevat behalve rommel van
/// het besturingssysteem — en `.debridmusic-album.json` stond niet in die lijst, terwijl de app hem
/// er zelf neerzet. Gemeten over de echte bibliotheek: **93 mappen** hielden niets anders meer over
/// dan dat ene bestand.
///
/// Wat NIET mag veranderen staat er als tegenproef bij: een hoes die de gebruiker er zelf in zette
/// houdt de map overeind. "Ruim lege mappen op" mag nooit "gooi mijn hoezen weg" gaan betekenen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/album_facts.dart' show kSidecarName;
import 'package:debridmusic/organize.dart';

late Directory wortel;

Directory maak(String naam, {List<String> bestanden = const []}) {
  final d = Directory('${wortel.path}${Platform.pathSeparator}$naam')..createSync(recursive: true);
  for (final b in bestanden) {
    File('${d.path}${Platform.pathSeparator}$b').writeAsStringSync('x');
  }
  return d;
}

void main() {
  setUp(() => wortel = Directory.systemTemp.createTempSync('legemap'));
  tearDown(() {
    if (wortel.existsSync()) wortel.deleteSync(recursive: true);
  });

  group('pruneVacated — de map die je net leeggehaald hebt', () {
    test('DE KERN: alleen het zijbestand van de app is geen reden om te blijven staan', () async {
      final d = maak('Artiest/Plaat', bestanden: [kSidecarName]);
      await pruneVacated(d.path, wortel.path);
      expect(d.existsSync(), isFalse);
      // En de artiestenmap erboven loopt mee leeg.
      expect(Directory('${wortel.path}${Platform.pathSeparator}Artiest').existsSync(), isFalse);
    });

    test('een echt leeggelopen map ging altijd al weg', () async {
      final d = maak('Artiest/Plaat');
      await pruneVacated(d.path, wortel.path);
      expect(d.existsSync(), isFalse);
    });

    test('het zijbestand naast OS-rommel telt ook als leeg', () async {
      final d = maak('Artiest/Plaat', bestanden: [kSidecarName, 'Thumbs.db', 'desktop.ini']);
      await pruneVacated(d.path, wortel.path);
      expect(d.existsSync(), isFalse);
    });

    test('DE TEGENPROEF: een hoes houdt de map overeind', () async {
      // Een plaatje dat de gebruiker er zelf in zette is geen rommel, ook niet als de muziek weg is.
      final d = maak('Artiest/Plaat', bestanden: [kSidecarName, 'folder.jpg']);
      await pruneVacated(d.path, wortel.path);
      expect(d.existsSync(), isTrue);
      expect(File('${d.path}${Platform.pathSeparator}folder.jpg').existsSync(), isTrue);
    });

    test('en muziek natuurlijk ook', () async {
      final d = maak('Artiest/Plaat', bestanden: [kSidecarName, '01 - Nummer.flac']);
      await pruneVacated(d.path, wortel.path);
      expect(d.existsSync(), isTrue);
    });

    test('de wortel zelf blijft altijd staan', () async {
      File('${wortel.path}${Platform.pathSeparator}$kSidecarName').writeAsStringSync('x');
      await pruneVacated(wortel.path, wortel.path);
      expect(wortel.existsSync(), isTrue);
    });
  });

  group('sweepEmptyFolders — de ronde bij het opstarten', () {
    test('DE KERN: ruimt de mappen op die al blijven staan', () async {
      // Dit is wat de 93 bestaande gevallen bij de eerstvolgende start opruimt.
      final a = maak('Een/Plaat A', bestanden: [kSidecarName]);
      final b = maak('Twee/Plaat B', bestanden: [kSidecarName, '.DS_Store']);
      final c = maak('Drie/Plaat C', bestanden: [kSidecarName, 'cover.png']);
      final d = maak('Vier/Plaat D', bestanden: ['02 - Iets.flac']);

      await sweepEmptyFolders(wortel.path);

      expect(a.existsSync(), isFalse);
      expect(b.existsSync(), isFalse);
      expect(c.existsSync(), isTrue, reason: 'een hoes is van de gebruiker');
      expect(d.existsSync(), isTrue, reason: 'daar staat muziek');
      // De artiestenmappen erboven gaan in dezelfde ronde mee, diepste eerst.
      expect(Directory('${wortel.path}${Platform.pathSeparator}Een').existsSync(), isFalse);
      expect(Directory('${wortel.path}${Platform.pathSeparator}Drie').existsSync(), isTrue);
    });
  });
}
