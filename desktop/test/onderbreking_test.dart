/// Wat er met de muziek gebeurt als iets anders geluid wil maken.
///
/// **Waarom dit een toets verdient.** Wat hiervoor in de app stond was één regel: bij élke
/// onderbreking pauzeren, en nooit meer hervatten. In een auto is dat de ergernis die je elke rit
/// hebt — de navigatiestem zegt "sla rechtsaf", de muziek valt stil en komt niet terug. Het systeem
/// stuurt het onderscheid gewoon mee; er keek alleen niemand naar.
///
/// De randgevallen hieronder zijn geen bedenksels: het zijn precies de gevallen waarin muziek uit
/// zichzelf begint te spelen in een stille auto, of juist stil blijft terwijl je hem terug verwacht.
library;

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/now_playing.dart';

void main() {
  group('er komt iets doorheen', () {
    test('een korte stem zet de muziek zachter, niet uit', () {
      // Pauzeren voor twee seconden navigatie is te veel: je hoort een gat in plaats van een stem
      // over de muziek heen.
      expect(
        bijOnderbreking(
            begint: true,
            soort: AudioInterruptionType.duck,
            speelt: true,
            zelfGepauzeerd: false),
        Onderbreking.dempen,
      );
    });

    test('en daarna weer terug op je eigen stand', () {
      expect(
        bijOnderbreking(
            begint: false,
            soort: AudioInterruptionType.duck,
            speelt: true,
            zelfGepauzeerd: false),
        Onderbreking.ontdempen,
      );
    });

    test('een gesprek pauzeert', () {
      expect(
        bijOnderbreking(
            begint: true,
            soort: AudioInterruptionType.pause,
            speelt: true,
            zelfGepauzeerd: false),
        Onderbreking.pauzeren,
      );
    });

    test('en na het gesprek loopt hij verder', () {
      expect(
        bijOnderbreking(
            begint: false,
            soort: AudioInterruptionType.pause,
            speelt: false,
            zelfGepauzeerd: true),
        Onderbreking.hervatten,
      );
    });
  });

  group('wanneer er juist NIETS mag gebeuren', () {
    test('wie zelf op pauze drukte krijgt zijn muziek niet terug', () {
      // Anders begint de muziek na een gesprek alsnog te spelen terwijl jij hem zelf had stilgezet.
      expect(
        bijOnderbreking(
            begint: false,
            soort: AudioInterruptionType.pause,
            speelt: false,
            zelfGepauzeerd: false),
        Onderbreking.niets,
      );
    });

    test('bij "onbekend" blijft het stil', () {
      // We weten niet waarom het stopte. Uit zichzelf weer beginnen is erger dan stil blijven: dat
      // is muziek die opeens aangaat in een stille auto.
      expect(
        bijOnderbreking(
            begint: false,
            soort: AudioInterruptionType.unknown,
            speelt: false,
            zelfGepauzeerd: true),
        Onderbreking.niets,
      );
    });

    test('wat al stil was wordt niet nog eens gepauzeerd', () {
      for (final s in AudioInterruptionType.values) {
        expect(
          bijOnderbreking(begint: true, soort: s, speelt: false, zelfGepauzeerd: false),
          Onderbreking.niets,
          reason: 'bij $s',
        );
      }
    });
  });

  test('onbekend pauzeert wél, want het is geen kort geluid', () {
    // Alleen `duck` is kort. Al het andere hoort de muziek stil te zetten; het verschil zit in wat
    // er daarna gebeurt.
    expect(
      bijOnderbreking(
          begint: true,
          soort: AudioInterruptionType.unknown,
          speelt: true,
          zelfGepauzeerd: false),
      Onderbreking.pauzeren,
    );
  });
}
