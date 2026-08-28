/// De opdracht die naar ffmpeg gaat als de pc een nummer verkleint.
///
/// **Waarom dit een toets waard is.** Deze vlaggen bepalen wat er werkelijk over de lijn gaat, en
/// een fout erin valt niet om: je stuurt gewoon te veel bytes onder het juiste etiket, of je hoort
/// korrel in een stille passage. Alle drie de dingen die hier nagemeten worden zijn precies zo
/// misgegaan — het cast-pad ging nooit onder 24 bit, dus ze zijn nooit geraakt.
///
/// Zuiver: een lijst tekst in, een lijst tekst uit. Geen ffmpeg, geen schijf.
library;

import 'package:debridmusic/lan/transcode.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> args({required int rate, required int bits, Omzetrecept recept = receptCast}) =>
    omzetArgumenten(
        bronPad: '/muziek/a.flac',
        doelPad: '/cache/b.tmp',
        maxSampleRate: rate,
        maxBits: bits,
        recept: recept);

/// De waarde die achter [vlag] staat, of null als de vlag er niet is.
String? na(List<String> a, String vlag) {
  final i = a.indexOf(vlag);
  return i < 0 || i + 1 >= a.length ? null : a[i + 1];
}

void main() {
  group('DE KERN: het monsterformaat volgt de bitdiepte', () {
    test('naar 16 bit gaat het monsterformaat mee omlaag', () {
      // Hier stond altijd `s32`. De FLAC-codeerder leidt de opgeslagen diepte af uit het
      // monsterformaat, dus met s32 schrijf je een 24-bits stroom waar `-bits_per_raw_sample 16`
      // niets aan verandert: ruwweg anderhalf keer te veel bytes onder het etiket "16 bit".
      expect(na(args(rate: 44100, bits: 16), '-sample_fmt'), 's16');
      expect(na(args(rate: 44100, bits: 16), '-bits_per_raw_sample'), '16');
    });

    test('boven 16 bit blijft het s32', () {
      expect(na(args(rate: 48000, bits: 24), '-sample_fmt'), 's32');
      expect(na(args(rate: 48000, bits: 24), '-bits_per_raw_sample'), '24');
    });
  });

  group('DE KERN: dither, en alleen waar het nodig is', () {
    test('bij het zakken naar 16 bit wordt er geditherd', () {
      // 24 naar 16 zonder dither is afkappen, en dat hoor je in stille passages als korrel.
      expect(na(args(rate: 44100, bits: 16), '-af'), contains('dither_method=triangular_hp'));
    });

    test('bij 24 bit niet, want daar heeft het geen zin', () {
      expect(na(args(rate: 48000, bits: 24), '-af'), isNot(contains('dither')));
    });
  });

  group('het recept bepaalt de compressie', () {
    test('een speaker krijgt snelheid', () {
      // Weggooiwerk dat na het spelen verdwijnt; daar telt de wachttijd en niet de grootte.
      expect(na(args(rate: 48000, bits: 24, recept: receptCast), '-compression_level'), '0');
    });

    test('een gekoppeld toestel krijgt kleine bestanden', () {
      // Die bytes gaan over iemands databundel — dat is de hele reden dat deze weg bestaat.
      expect(na(args(rate: 44100, bits: 16, recept: receptStroom), '-compression_level'), '5');
    });

    test('de twee recepten hebben een verschillende naam', () {
      // De naam gaat in de cachesleutel. Zonder dat verschil zou een omzetting voor de speaker
      // doorgaan voor eentje voor de telefoon.
      expect(receptCast.naam, isNot(receptStroom.naam));
    });

    test('en een eigen bewaaraantal', () {
      // Vierentwintig is minder dan één album; voor een speaker is het één nummer.
      expect(receptStroom.bewaar, greaterThan(receptCast.bewaar));
    });
  });

  group('de vlaggen die er hoe dan ook op moeten', () {
    test('de doos wordt uitgesproken, want de extensie is .tmp', () {
      // ffmpeg kiest de container op de extensie van het uitvoerbestand. Zonder `-f flac` stopt hij
      // met "Unable to choose an output format" en schrijft hij niets. Gemeten: exitcode 127.
      expect(na(args(rate: 44100, bits: 16), '-f'), 'flac');
      expect(na(args(rate: 44100, bits: 16), '-c:a'), 'flac');
    });

    test('gewone aresample en nooit soxr', () {
      // Veel ffmpeg-bouwsels komen zonder soxr, en er dan om vragen laat de hele filterketen
      // mislukken: niets geschreven, en een lege stroom bij de speler.
      final a = na(args(rate: 44100, bits: 16), '-af')!;
      expect(a, startsWith('aresample=44100'));
      expect(a, isNot(contains('soxr')));
    });

    test('bron en doel staan erin, en het doel staat achteraan', () {
      final a = args(rate: 44100, bits: 16);
      expect(na(a, '-i'), '/muziek/a.flac');
      expect(a.last, '/cache/b.tmp');
    });

    test('de frequentie in de filterketen volgt het plafond', () {
      expect(na(args(rate: 48000, bits: 24), '-af'), startsWith('aresample=48000'));
    });
  });
}
