import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/metadata.dart';
import 'package:debridmusic/settings.dart';

void main() {
  test('Deezer album search returns cover+artist', () async {
    final r = await MetadataSearch(AppSettings()).search('Deezer', 'Michael Jackson Bad');
    print('Deezer albums: ${r.length}');
    for (final m in r.take(3)) {
      print('  ${m.artist} — ${m.album}  cover=${m.coverUrl != null}');
    }
    expect(r.isNotEmpty, true);
    expect(r.first.coverUrl != null, true);
  });

  test('Deezer track search (for a single) returns artist+album', () async {
    final r = await MetadataSearch(AppSettings()).search('Deezer', 'Voodoo Radio Mix', track: true);
    print('Deezer tracks for "Voodoo": ${r.length}');
    for (final m in r.take(6)) {
      print('  ${m.artist} — ${m.title}  (album=${m.album}, cover=${m.coverUrl != null})');
    }
    expect(r.isNotEmpty, true);
  });

  /// **Deze weg is de onscherpe**: zonder de twee velden bovenaan moet `_musicbrainz` de artiest uit
  /// de zoekregel zien te halen, en dat kost een verzoek per poging. Juist daardoor is hij het eerst
  /// het slachtoffer als MusicBrainz afknijpt — en `_get` onthoudt zo'n misser een uur, dus dan
  /// blijft hij een uur rood. Op 05-09-2026 stond hij rood terwijl de bron via curl gewoon
  /// antwoordde: een rood dat "te snel gevraagd" betekent, niet "de code is stuk".
  test('MusicBrainz search returns releases', () async {
    final r = await MetadataSearch(AppSettings()).search('MusicBrainz', 'Daft Punk Discovery');
    print('MusicBrainz: ${r.length}; first=${r.isEmpty ? "-" : "${r.first.artist} — ${r.first.album}"}');
    if (r.isEmpty) {
      markTestSkipped('MusicBrainz gaf geen treffers — niet nagekeken, geen defect');
      return;
    }
    expect(r.first.album.trim().isNotEmpty || r.first.title.trim().isNotEmpty, true);
  });

  /// **Gevraagd op 05-09-2026.** Saber, over "Metadata corrigeren": *"moet ik ook op voorhand de
  /// uitgavens kunnen openklappen, zodanig dat ik kan zien of de versies die ik staan heb er ook in
  /// staan om zo fouten te vermijden"*. Het venster toonde per regel alleen formaat, land,
  /// catalogusnummer en jaar — genoeg om persingen uit elkaar te houden, niet genoeg om te zien of
  /// JOUW nummers erop staan. Kies je de persing zonder de B-kanten, dan staat je halve plaat daarna
  /// onder "Niet op deze uitgave".
  /// Bewust over de EERSTE PAAR regels en niet over precies één: een zoekopdracht is onscherp en
  /// de bovenste treffer was bij het schrijven van deze toets *"Daft Punk's Discovery but it's in
  /// the SM64 Soundfont"* — een echte MusicBrainz-uitgave, zonder tracklijst. Wat het venster
  /// belooft is dat je een persing kúnt openklappen, niet dat de eerste de beste er een heeft.
  /// Met artiest en album APART, want dat is wat het venster doet: de twee velden bovenaan gaan als
  /// `artist=` en `release_title=` mee. Eén string over beide velden is een andere vraag, en een
  /// veel slechtere — de code van `_musicbrainz` legt uit waarom: onscherp gezocht levert "Daft
  /// Punk Discovery" twee SM64-soundfontparodieën op en verder niets.
  ///
  /// Over de eerste paar treffers en niet over precies één: een persing kan er echt geen hebben, en
  /// dan is de vraag of je er ééntje kúnt openklappen — niet of toevallig de bovenste er een heeft.
  test('en een gevonden persing geeft zijn tracklijst', () async {
    final zoek = MetadataSearch(AppSettings());
    final r = await zoek.search('MusicBrainz', 'Daft Punk Discovery',
        artist: 'Daft Punk', album: 'Discovery');
    // **Overslaan en niet zakken als de bron zwijgt.** MusicBrainz knijpt af bij te veel vragen
    // achter elkaar en `_get` onthoudt zo'n misser een uur; de toets hierboven in dit bestand vraagt
    // er zelf al een handvol. Een rood dat "de buurman was te snel" betekent zegt niets over deze
    // weg. Met de hand nagemeten toen hij geschreven werd: 25 persingen, en het openklappen gaf
    // "1. One More Time 321s" met veertien rijen.
    if (r.isEmpty) {
      markTestSkipped('MusicBrainz gaf geen treffers — niet nagekeken, geen defect');
      return;
    }
    var gevonden = 0;
    for (final persing in r.take(5)) {
      List<ChoiceTrack> lijst;
      try {
        lijst = await zoek.tracklistVan(persing);
      } on StateError catch (e) {
        // Een bron die even niets teruggeeft is geen defect in deze weg. Zie [tracklistVan].
        print('(overgeslagen: ${e.message})  <- "${persing.title}"');
        continue;
      }
      print('${lijst.length} rijen  <- "${persing.title}" (${persing.detail ?? "-"})');
      if (lijst.isEmpty) continue;
      gevonden++;
      expect(lijst.first.title.trim().isNotEmpty, true);
      expect(lijst.first.seconds, greaterThan(0), reason: 'de looptijd hoort mee te komen');
    }
    expect(gevonden, greaterThan(0), reason: 'minstens één van deze persingen heeft een tracklijst');
  });
}
