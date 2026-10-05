/// Dezelfde hoes, opnieuw van schijf gelezen, is geen nieuwe hoes.
///
/// **Waarom dit bestaat.** `AlbumArt` geeft bij elke opening van een albumpagina of van Nu speelt de
/// gevonden voorkant door aan [LibraryStore.adoptAlbumCover]. Die hoes komt uit de cache op schijf
/// (`readAsBytes`), dus elke keer als een nieuw stuk geheugen — en `adoptAlbumCover` vergeleek met
/// `identical`. Gevolg, gevonden op 05-10-2026 bij het meten van "snel navigeren met muziek erbij":
/// elke opening meldde de hele bibliotheek als veranderd, en alles wat ernaar kijkt bouwde opnieuw
/// op; met een vastgezette persing werd de hoes er bovendien elke keer opnieuw voor naar schijf
/// geschreven. Voor een hoes die er al precies zo stond.
library;

import 'dart:typed_data';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ruim boven de ondergrens van 500 bytes; [merk] maakt hoezen onderscheidbaar.
Uint8List hoes(int merk) => Uint8List.fromList(List<int>.filled(800, merk));

LibraryStore metAlbum() {
  final t = Track(
    path: r'C:\Muziek\Oasis\Morning Glory\03 - Wonderwall.flac',
    title: 'Wonderwall',
    artist: 'Oasis',
    album: "(What's The Story) Morning Glory?",
  );
  return LibraryStore()..albums = [Album("(What's The Story) Morning Glory?", 'Oasis', [t])];
}

void main() {
  const artiest = 'Oasis', plaat = "(What's The Story) Morning Glory?";

  for (final (tak, from) in [('gok op naam', null), ('aangewezen persing', 'rel:368542')]) {
    group(tak, () {
      test('DE KERN: dezelfde hoes als nieuw stuk geheugen meldt niets', () {
        final s = metAlbum();
        expect(s.adoptAlbumCover(artiest, plaat, hoes(7), from: from), isTrue);
        var meldingen = 0;
        s.addListener(() => meldingen++);
        // Byte voor byte dezelfde, maar een ander object — zoals een tweede `readAsBytes`.
        expect(s.adoptAlbumCover(artiest, plaat, hoes(7), from: from), isFalse,
            reason: 'een hoes die er al precies zo stond, telde als veranderd');
        expect(meldingen, 0,
            reason: 'elke opening van een album of Nu speelt liet de hele bibliotheek opnieuw opbouwen');
      });

      test('DE VAL: een andere hoes van dezelfde grootte meldt wél', () {
        final s = metAlbum();
        s.adoptAlbumCover(artiest, plaat, hoes(7), from: from);
        var meldingen = 0;
        s.addListener(() => meldingen++);
        final anders = hoes(7)..[799] = 8;
        expect(s.adoptAlbumCover(artiest, plaat, anders, from: from), isTrue,
            reason: 'één afwijkende byte op het eind is een andere hoes');
        expect(meldingen, 1);
      });
    });
  }

  test('DE GRENS: dezelfde bytes van een andere persing is wél een verandering', () {
    final s = metAlbum();
    s.adoptAlbumCover(artiest, plaat, hoes(7), from: 'rel:368542');
    expect(s.adoptAlbumCover(artiest, plaat, hoes(7), from: 'rel:999'), isTrue,
        reason: 'de herkomst hoort bij de hoes; een andere persing moet genoteerd worden');
    expect(s.albums.single.resolvedFrom, 'rel:999');
  });
}
