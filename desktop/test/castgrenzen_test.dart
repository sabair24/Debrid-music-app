/// Past deze plaat op deze speaker?
///
/// **Waarom dit een toets waard is.** Casten faalt bij uitstek zónder klap. Een speaker die een
/// bestand niet aankan meldt geen fout — hij speelt gewoon niets. Van buitenaf is dat niet te
/// onderscheiden van een netwerkprobleem, een verkeerd token of een lege wachtrij, en er zijn hier al
/// twee reparaties op een vermoeden gemikt.
///
/// **Wat er misging.** Er staan twee assen en er werd er één bekeken. Gemeld op een KEF LS50
/// Wireless II: een bestand van 32 bit / 384 kHz bleef stil, terwijl die speaker over het netwerk
/// tot 24 bit / 384 kHz gaat — KEF geeft dat zelf op. De frequentie was dus geen enkel probleem en
/// de bitdiepte wel, en de app keek alleen naar de frequentie. Dezelfde soort mislukking als de
/// Sonos die alles boven 48 kHz overslaat, alleen op de andere as.
library;

import 'package:debridmusic/lan/upnp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een speaker met een opgegeven fabrikant, om [Renderer.isSonos] te laten werken.
Renderer speaker(String fabrikant) => Renderer(
      id: 'x',
      name: fabrikant,
      host: '192.168.1.2',
      avTransportUrl: 'http://192.168.1.2/av',
      manufacturer: fabrikant,
    );

void main() {
  group('de plafonds van een speaker', () {
    test('elke netwerkspeler houdt op bij 24 bit', () {
      // Geen merkkwestie zoals de 48 kHz van Sonos: er bestaat geen DLNA-profiel voor 32-bits PCM.
      // 32 bit komt uit de studio en uit software; wat er aan een kabel hangt, gaat tot 24.
      expect(speaker('KEF').maxBitDepth, 24);
      expect(speaker('Sonos, Inc.').maxBitDepth, 24);
    });

    test('alleen Sonos heeft een bekend frequentieplafond', () {
      expect(speaker('Sonos, Inc.').maxSampleRate, 48000);
      expect(speaker('KEF').maxSampleRate, 0, reason: '0 = geen bekend plafond');
    });
  });

  group('wat er omgezet moet worden', () {
    test('de KEF en een bestand van 32/384: alleen de DIEPTE omlaag', () {
      // Precies het gemelde geval. 384 kHz blijft staan — die speaker kan het aan, en onnodig
      // herbemonsteren is werk doen om iets slechter te maken.
      final g = castGrenzen(
          sampleRate: 384000, bits: 32, maxSampleRate: 0, maxBitDepth: 24);
      expect(g.omzetten, isTrue);
      expect(g.bits, 24);
      expect(g.rate, 384000, reason: 'wat past, blijft');
    });

    test('een gewone hi-res plaat op de KEF gaat ongemoeid', () {
      final g = castGrenzen(
          sampleRate: 192000, bits: 24, maxSampleRate: 0, maxBitDepth: 24);
      expect(g.omzetten, isFalse);
    });

    test('een cd-rip gaat overal ongemoeid', () {
      final g = castGrenzen(
          sampleRate: 44100, bits: 16, maxSampleRate: 48000, maxBitDepth: 24);
      expect(g.omzetten, isFalse);
      expect(g.rate, 44100);
      expect(g.bits, 16);
    });

    test('Sonos en 24/96: alleen de FREQUENTIE omlaag', () {
      final g = castGrenzen(
          sampleRate: 96000, bits: 24, maxSampleRate: 48000, maxBitDepth: 24);
      expect(g.omzetten, isTrue);
      expect(g.rate, 48000);
      expect(g.bits, 24, reason: 'de diepte paste al');
    });

    test('Sonos en 32/384: allebei omlaag', () {
      final g = castGrenzen(
          sampleRate: 384000, bits: 32, maxSampleRate: 48000, maxBitDepth: 24);
      expect(g.omzetten, isTrue);
      expect(g.rate, 48000);
      expect(g.bits, 24);
    });

    test('een onbekende diepte is geen te grote diepte', () {
      // Een catalogus van vóór deze versie geeft 0. Dan hoort er niets omgezet te worden op grond
      // van niets — dat zou elke plaat van elke oudere pc door ffmpeg jagen.
      final g = castGrenzen(sampleRate: 44100, bits: 0, maxSampleRate: 0, maxBitDepth: 24);
      expect(g.omzetten, isFalse);
      expect(g.bits, 0);
    });

    test('geen enkel plafond laat alles staan', () {
      // De eigen televisie loopt niet langs deze weg, maar als er ooit een speaker zonder grenzen
      // bij komt, hoort hij het bestand ongemoeid te krijgen — dat is het hele punt van casten.
      final g = castGrenzen(sampleRate: 384000, bits: 32, maxSampleRate: 0, maxBitDepth: 0);
      expect(g.omzetten, isFalse);
    });
  });
}
