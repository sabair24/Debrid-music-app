/// Een afgekapte FLAC telt niet als "die heb ik al".
///
/// **Waarom dit bestaat.** Gemeld op 30-08-2026 met Gorki — Anja: een bestand van 24 bit/44,1 kHz
/// dat op 17,4 kHz dichtklapt, dus opgeblazen uit iets lossy. Saber wil dan liever een echte
/// 16/44.1 dan een opgeblazen 24 — en dus moet de app ernaar op zoek.
///
/// De verlanglijst kan dat zoeken al. Maar hij laat een wens vervallen zodra de FLAC "in de
/// bibliotheek staat", en dat werd gemeten met [LibraryStore.hasLossless]. Telde een betrapte kopie
/// daarin mee, dan verviel de wens bij de eerstvolgende ronde — twintig minuten later — en zocht de
/// app er nooit meer naar. Eén regel verschil tussen een werkende functie en een knop die niets doet.
///
/// De andere kant telt net zo hard: alleen wat BEWEZEN nep is valt af. Zou een ongemeten bestand ook
/// afvallen, dan maakt de eerste meting ineens honderden wensen wakker.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/vaste_keuze.dart';

/// Precies het oordeel van Gorki — Anja: afgekapt op 17,4 kHz en opgeblazen naar 24 bit.
const _afgekapt = Echtheidsoordeel(
  bits: Bitdiepte.opgeblazen,
  boven: Bovenband.leeg,
  band: Bandbreedte.afgekapt,
  afkapHz: 17400,
  vensters: 40,
);

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_betrapt_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    vergeetOordeel('${scratch.path}${Platform.pathSeparator}anja.flac');
    scratch.deleteSync(recursive: true);
  });

  Track nummer(String pad, {String titel = 'Anja'}) => Track(
        path: pad,
        title: titel,
        artist: 'Gorki',
        album: 'Gorky',
        isFlac: true,
        sizeBytes: 30 * 1024 * 1024,
      );

  test('DE KERN: een betrapte FLAC vervult de wens niet', () async {
    final pad = '${scratch.path}${Platform.pathSeparator}anja.flac';
    final lib = LibraryStore()..tracks.add(nummer(pad));

    // Ongemeten telt hij gewoon mee — anders maakt de eerste meting alles wakker.
    expect(lib.hasLossless('Gorki', 'Anja'), isTrue);

    onthoudOordeelVanPc(pad, _afgekapt);

    expect(lib.hasLossless('Gorki', 'Anja'), isFalse,
        reason: 'anders vervalt de wens en gaat de app er nooit meer naar zoeken');
  });

  test('en een ECHTE kopie ernaast vervult hem wel', () async {
    final nep = '${scratch.path}${Platform.pathSeparator}anja.flac';
    final echt = '${scratch.path}${Platform.pathSeparator}anja-echt.flac';
    final lib = LibraryStore()
      ..tracks.add(nummer(nep))
      ..tracks.add(nummer(echt));
    onthoudOordeelVanPc(nep, _afgekapt);

    // De echte is niet gemeten, en dat hoeft ook niet: alleen bewezen nep valt af.
    expect(lib.hasLossless('Gorki', 'Anja'), isTrue);
    vergeetOordeel(nep);
  });

  test('MAAR: wat je zelf koos blijft de baas, ook als het betrapt is', () async {
    // Wie op de kwaliteitslijst met de hand een vervanger aanwijst heeft beslist. Misschien is dit
    // de enige uitgave die bestaat, of klinkt juist deze het best. Zou de app dan tóch blijven
    // zoeken, dan haalt hij eindeloos kopieën binnen die `firstIsBetter` meteen weer parkeert —
    // want daar wint een vaste keuze van alles, ook van een schone opname.
    final pad = '${scratch.path}${Platform.pathSeparator}anja.flac';
    final lib = LibraryStore()..tracks.add(nummer(pad));
    onthoudOordeelVanPc(pad, _afgekapt);
    expect(lib.hasLossless('Gorki', 'Anja'), isFalse);

    await onthoudVasteKeuze(pad);

    expect(lib.hasLossless('Gorki', 'Anja'), isTrue,
        reason: 'jouw keuze telt als "die heb ik", dus de app houdt op met zoeken');
    await vergeetVasteKeuze(pad);
    vergeetOordeel(pad);
  });

  test('een ander nummer van dezelfde plaat blijft ongemoeid', () async {
    final nep = '${scratch.path}${Platform.pathSeparator}anja.flac';
    final lib = LibraryStore()
      ..tracks.add(nummer(nep))
      ..tracks.add(nummer('${scratch.path}${Platform.pathSeparator}mia.flac', titel: 'Mia'));
    onthoudOordeelVanPc(nep, _afgekapt);

    expect(lib.hasLossless('Gorki', 'Anja'), isFalse);
    expect(lib.hasLossless('Gorki', 'Mia'), isTrue, reason: 'Mia mankeert niets');
    vergeetOordeel(nep);
  });
}
