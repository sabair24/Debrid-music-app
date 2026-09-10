/// [imageSize] moet ook WebP en GIF kunnen lezen, want de app haalt die binnen.
///
/// **Waarom dit bestaat.** `CoverEnricher._isImage` keurt vier formaten goed — JPEG, PNG, GIF en
/// WebP — en [imageSize] las er tot 10-09-2026 maar twee: PNG en JPEG. Zolang die functie alleen
/// boekjes bediende viel dat niemand op, want de Cover Art Archive levert JPEG.
///
/// Met de beeldkiezer voor artiestfoto's wordt het wél een storing, en een stille. Die rangschikt
/// kandidaten op vorm én resolutie, en een kandidaat waarvan de afmetingen onbekend zijn kan de
/// grootste-van-de-juiste-vorm nooit winnen. Een WebP-foto van 2000×3000 zou dus stil verliezen van
/// een JPEG van 1280×720 — en het gevolg dat je ziet is niet "verkeerde foto gekozen" maar
/// "artiestpagina blijft leeg", wat je nergens aan kunt aflezen.
///
/// De koppen hieronder zijn met de hand gebouwd in plaats van uit een bestand gelezen: het gaat om
/// de indeling van de eerste dertig bytes, en die drie WebP-brokken hebben elk hun eigen. Zo staat
/// er ook geen beeldmateriaal in de repo dat niet van ons is.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/booklet.dart';

/// `GIF87a`, dan de logische schermmaat als twee little-endian shorts.
Uint8List gif(int w, int h) => Uint8List.fromList([
      0x47, 0x49, 0x46, 0x38, 0x37, 0x61, //
      w & 0xFF, (w >> 8) & 0xFF,
      h & 0xFF, (h >> 8) & 0xFF,
      0x00, 0x00,
    ]);

/// Het gemeenschappelijke begin van elk WebP-bestand: `RIFF`, een lengte, `WEBP`, en dan de naam
/// van de brok die de indeling bepaalt.
List<int> _riff(String brok) => [
      0x52, 0x49, 0x46, 0x46, // RIFF
      0x00, 0x00, 0x00, 0x00, // lengte, doet er hier niet toe
      0x57, 0x45, 0x42, 0x50, // WEBP
      ...brok.codeUnits,
      0x00, 0x00, 0x00, 0x00, // broklengte
    ];

/// Verliesgevend: framekop, synccode `9D 01 2A`, dan breedte en hoogte in de onderste 14 bits.
Uint8List webpVerliesgevend(int w, int h) => Uint8List.fromList([
      ..._riff('VP8 '),
      0x00, 0x00, 0x00, // framekop
      0x9D, 0x01, 0x2A, // synccode
      w & 0xFF, (w >> 8) & 0x3F,
      h & 0xFF, (h >> 8) & 0x3F,
      0x00,
    ]);

/// Verliesloos: één signatuurbyte, dan breedte−1 in 14 bits en hoogte−1 in de 14 daarna.
Uint8List webpVerliesloos(int w, int h) {
  final gepakt = ((w - 1) & 0x3FFF) | (((h - 1) & 0x3FFF) << 14);
  return Uint8List.fromList([
    ..._riff('VP8L'),
    0x2F, // signatuur
    gepakt & 0xFF,
    (gepakt >> 8) & 0xFF,
    (gepakt >> 16) & 0xFF,
    (gepakt >> 24) & 0xFF,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]);
}

/// Uitgebreid (doorzichtigheid, animatie): canvasbreedte−1 en canvashoogte−1, elk 24 bits.
Uint8List webpUitgebreid(int w, int h) => Uint8List.fromList([
      ..._riff('VP8X'),
      0x10, // vlaggen
      0x00, 0x00, 0x00, // gereserveerd
      (w - 1) & 0xFF, ((w - 1) >> 8) & 0xFF, ((w - 1) >> 16) & 0xFF,
      (h - 1) & 0xFF, ((h - 1) >> 8) & 0xFF, ((h - 1) >> 16) & 0xFF,
      0x00,
    ]);

/// PNG met alleen een IHDR-kop: breedte en hoogte als big-endian woorden op 16 en 20.
Uint8List png(int w, int h) => Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52,
      (w >> 24) & 0xFF, (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF,
      (h >> 24) & 0xFF, (h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF,
      0x08, 0x02, 0x00,
    ]);

void main() {
  test('DE KERN: alle drie de WebP-brokken geven hun maat', () {
    expect(imageSize(webpVerliesgevend(2000, 3000)), (w: 2000, h: 3000),
        reason: 'een verliesgevende WebP-foto telt niet mee bij het kiezen van een achtergrond');
    expect(imageSize(webpVerliesloos(2291, 3046)), (w: 2291, h: 3046),
        reason: 'een verliesloze WebP telt niet mee bij het kiezen van een achtergrond');
    expect(imageSize(webpUitgebreid(1920, 1080)), (w: 1920, h: 1080),
        reason: 'een WebP met doorzichtigheid telt niet mee bij het kiezen van een achtergrond');
  });

  test('DE KERN: een GIF geeft zijn maat', () {
    expect(imageSize(gif(1280, 720)), (w: 1280, h: 720),
        reason: 'een GIF komt door `_isImage` en zou daarna zonder afmetingen verder gaan');
  });

  test('DE VAL: PNG en JPEG blijven werken', () {
    // De nieuwe takken staan ACHTER de bestaande, en dit is de toets daarop: `booklet_test.dart`
    // draait niet in CI, dus zonder deze regel merkt niemand het als de volgorde omvalt.
    expect(imageSize(png(600, 601)), (w: 600, h: 601),
        reason: 'de boekjes meten hun bladen hiermee — dat mag hier niet sneuvelen');
  });

  test('DE GRENS: een afgekapte kop valt niet om maar geeft niets', () {
    // Een half binnengehaald bestand is echt: `_download` weigert onder 1500 bytes, maar een
    // beschadigde cache is niet uitgesloten. Nul teruggeven is goed; een uitzondering niet.
    expect(imageSize(Uint8List.fromList(_riff('VP8 '))), isNull,
        reason: 'een half bestand hoort geen uitzondering te gooien maar niets te weten');
    expect(imageSize(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])), isNull,
        reason: 'vier bytes GIF zijn nog geen maat');
    expect(imageSize(Uint8List(0)), isNull, reason: 'leeg is leeg');
  });

  test('DE GRENS: een RIFF die geen WEBP is telt niet', () {
    // WAV begint ook met RIFF. Dat is geen theoretisch geval in een muziekapp.
    final wav = Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, //
      0x57, 0x41, 0x56, 0x45, // WAVE
      ...List<int>.filled(20, 0),
    ]);
    expect(imageSize(wav), isNull,
        reason: 'een WAV-bestand zou hier een verzonnen breedte en hoogte krijgen');
  });
}
