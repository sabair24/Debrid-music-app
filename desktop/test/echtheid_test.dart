/// Is dit bestand écht wat het beweert? — de logica, met verzonnen signalen.
///
/// Saber's vraag: "hoe weet ik dat een FLAC echt een FLAC is en niet een mp3 die naar FLAC is omgezet?"
///
/// Alles hier draait op bedachte spectra en bedachte samples. Geen bestand, geen ffmpeg. Dat is met opzet:
/// de drempels zijn het hart van deze functie, en die moeten te toetsen zijn zonder dat er een
/// hulpprogramma of een muziekcollectie in de buurt hoeft te zijn.
///
/// De zwaarste test staat onderaan: een opname uit 1962 mag NOOIT "transcode" heten.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/fft.dart';

const int _bins = 2048; // een venster van 4096 geeft 2048 bruikbare bins
const int _cd = 44100;

/// Een spectrum waarin het vermogen tot [tot] Hz op [niveauDb] ligt en daarboven op [vloerDb].
/// [helling] laat het vóór de grens al geleidelijk aflopen, in dB per kHz.
Float64List spectrum({
  required double totHz,
  int sampleRate = _cd,
  double niveauDb = -20,
  double vloerDb = -140,
  double helling = 0,
}) {
  final s = Float64List(_bins);
  final perBin = sampleRate / 2 / _bins;
  for (var i = 0; i < _bins; i++) {
    final hz = i * perBin;
    final db = hz <= totHz ? niveauDb - helling * (hz / 1000) : vloerDb;
    s[i] = math.pow(10, db / 10).toDouble();
  }
  return s;
}

Echtheidsoordeel beoordeel(
  Float64List s, {
  int sampleRate = _cd,
  int kopSampleRate = _cd,
  int kopBits = 16,
  int gebruikteBits = 16,
  int vensters = 20,
  int nietNul = 500000,
}) =>
    oordeel(
      spectrum: s,
      sampleRate: sampleRate,
      kopSampleRate: kopSampleRate,
      kopBits: kopBits,
      gebruikteBits: gebruikteBits,
      vensters: vensters,
      nietNulSamples: nietNul,
    );

void main() {
  group('de FFT zelf', () {
    test('een sinus op bin 100 geeft een piek op bin 100', () {
      const n = 1024;
      final re = Float64List(n), im = Float64List(n);
      for (var i = 0; i < n; i++) {
        re[i] = math.sin(2 * math.pi * 100 * i / n);
      }
      fft(re, im);
      var piek = 0, besteVermogen = 0.0;
      for (var k = 1; k < n ~/ 2; k++) {
        final v = re[k] * re[k] + im[k] * im[k];
        if (v > besteVermogen) {
          besteVermogen = v;
          piek = k;
        }
      }
      expect(piek, 100);
    });

    test('een venster van Blackman-Harris loopt naar nul aan de randen', () {
      final w = blackmanHarris(512);
      expect(w.first, lessThan(0.001));
      expect(w.last, lessThan(0.001));
      expect(w[256], greaterThan(0.9));
    });

    test('dB heeft een bodem in plaats van min oneindig', () {
      expect(dB(0), lessThan(-200));
      expect(dB(1), closeTo(0, 0.0001));
      expect(dB(100), closeTo(20, 0.0001));
    });
  });

  group('proef A: de bitdiepte', () {
    test('16-bit dat als 24-bit is verpakt wordt betrapt', () {
      // ffmpeg levert links uitgelijnd: een 16-bit sample zit in de bovenste 16 bits.
      final s = Int32List.fromList([0x1234 << 16, 0x5678 << 16, -0x0ABC << 16]);
      expect(gebruikteBitsVan(s), lessThanOrEqualTo(16));

      final o = beoordeel(spectrum(totHz: 22000), kopBits: 24, gebruikteBits: 16);
      expect(o.bits, Bitdiepte.opgeblazen);
      expect(o.isNep, isTrue);
      expect(waarom(o), contains('opgeblazen'));
    });

    test('echte 24 bits spreekt zichzelf niet tegen — maar heet nooit "echt"', () {
      final s = Int32List.fromList([0x123456 << 8, 0x789ABD << 8]);
      expect(gebruikteBitsVan(s), greaterThan(16));

      final o = beoordeel(spectrum(totHz: 22000), kopBits: 24, gebruikteBits: 24);
      expect(o.bits, Bitdiepte.spreektNietTegen);
      expect(o.isNep, isFalse);
    });

    test('digitale stilte vervuilt de meting niet', () {
      expect(gebruikteBitsVan(Int32List.fromList([0, 0, 0x123456 << 8, 0])), greaterThan(16));
      expect(gebruikteBitsVan(Int32List.fromList([0, 0, 0])), 0);
    });

    test('te weinig samples: geen oordeel over de bits', () {
      final o = beoordeel(spectrum(totHz: 22000), kopBits: 24, gebruikteBits: 16, nietNul: 1000);
      expect(o.bits, Bitdiepte.onbekend);
      expect(o.gebruikteBits, isNull);
    });

    test('een bestand dat zelf 16 bits zegt wordt niet op bits beoordeeld', () {
      final o = beoordeel(spectrum(totHz: 22000), kopBits: 16, gebruikteBits: 16);
      expect(o.bits, Bitdiepte.onbekend, reason: 'er valt niets tegen te spreken');
    });
  });

  group('proef B: de bovenband', () {
    test('96 kHz zonder iets boven 22 kHz is opgeschaald', () {
      final s = spectrum(totHz: 21000, sampleRate: 96000);
      final o = beoordeel(s, sampleRate: 96000, kopSampleRate: 96000, kopBits: 24, gebruikteBits: 24);
      expect(o.boven, Bovenband.leeg);
      expect(o.isNep, isTrue);
      expect(waarom(o), contains('22 kHz'));
    });

    test('96 kHz mét ruis boven 22 kHz is echt', () {
      // Een echte opname heeft daar altijd íets: microfoon- en omzetterruis. En hij heeft rond 45 kHz
      // het anti-aliasfilter van de omzetter — een steile, volkomen normale val. Die mag GEEN transcode
      // heten; daarvoor bestaat [hoogsteAfkapHz].
      final s = spectrum(totHz: 45000, sampleRate: 96000, niveauDb: -20, helling: 1.2);
      final o = beoordeel(s, sampleRate: 96000, kopSampleRate: 96000, kopBits: 24, gebruikteBits: 24);
      expect(o.boven, Bovenband.vol);
      expect(o.band, isNot(Bandbreedte.afgekapt),
          reason: 'het filter van de omzetter is geen mp3-afkap');
      expect(o.isNep, isFalse);
    });

    test('een 96 kHz-bestand dat tóch uit een mp3 komt wordt wél betrapt', () {
      // De muur ligt dan nog steeds rond 20 kHz en valt dus binnen het zoekgebied — het optrekken naar
      // 96 kHz verstopt hem niet.
      final s = spectrum(totHz: 19800, sampleRate: 96000);
      final o = beoordeel(s, sampleRate: 96000, kopSampleRate: 96000, kopBits: 24, gebruikteBits: 24);
      expect(o.band, Bandbreedte.afgekapt);
      expect(o.isNep, isTrue);
    });

    test('bij 44,1 kHz wordt de bovenband niet beoordeeld', () {
      final o = beoordeel(spectrum(totHz: 22000));
      expect(o.boven, Bovenband.onbekend, reason: 'daar bestaat geen band boven 22 kHz');
    });
  });

  group('proef C: de afkap — de enige die vals alarm kan geven', () {
    test('een mp3 van 320 kbps: muur rond 20 kHz', () {
      final s = spectrum(totHz: 19800);
      final o = beoordeel(s);
      expect(o.band, Bandbreedte.afgekapt);
      expect(o.afkapHz, closeTo(19800, 400));
      expect(o.isNep, isTrue);
      expect(waarom(o), contains('mp3'));
    });

    test('een mp3 van 128 kbps: muur rond 16 kHz', () {
      final o = beoordeel(spectrum(totHz: 16000));
      expect(o.band, Bandbreedte.afgekapt);
      expect(o.afkapHz, closeTo(16000, 400));
    });

    test('een echte cd-rip loopt door tot Nyquist', () {
      final o = beoordeel(spectrum(totHz: 22000));
      expect(o.band, Bandbreedte.doorlopend);
      expect(o.isNep, isFalse);
    });

    // ── DE ZWAARSTE TEST ──────────────────────────────────────────────────
    test('een opname uit 1962 met tape-hiss is GEEN transcode', () {
      // De muziek stopt bij 12 kHz, maar de hiss loopt door tot Nyquist — de omzetter heeft hem
      // meegenomen. Precies dat verschil maakt zo'n plaat beoordeelbaar in plaats van verdacht.
      final s = Float64List(_bins);
      final perBin = _cd / 2 / _bins;
      for (var i = 0; i < _bins; i++) {
        final hz = i * perBin;
        final muziek = hz < 12000 ? -20.0 - hz / 1000 : -300.0;
        const hiss = -95.0;
        s[i] = math.pow(10, muziek / 10).toDouble() + math.pow(10, hiss / 10).toDouble();
      }
      final o = beoordeel(s);
      expect(o.band, isNot(Bandbreedte.afgekapt),
          reason: 'de hiss boven 12 kHz bewijst dat er niets is afgekapt');
      expect(o.isNep, isFalse);
    });

    test('een dof opgenomen stuk zonder hoog krijgt GEEN oordeel', () {
      // Alles boven 9 kHz ligt al onder de vloer: er is daar niets af te kappen.
      final o = beoordeel(spectrum(totHz: 9000));
      expect(o.band, Bandbreedte.doorlopend, reason: 'geen muur binnen het beoordeelbare gebied');
      expect(o.isNep, isFalse);
    });

    test('een natuurlijke roll-off is geen muur', () {
      // Geleidelijk aflopend over het hele bereik: analoog filter, tapeband. Nooit steil genoeg.
      final o = beoordeel(spectrum(totHz: 22050, niveauDb: -20, helling: 3.5));
      expect(o.band, Bandbreedte.doorlopend);
      expect(o.isNep, isFalse);
    });

    test('een afkap onder 14 kHz valt buiten de uitspraak', () {
      final o = beoordeel(spectrum(totHz: 11000));
      expect(o.band, isNot(Bandbreedte.afgekapt),
          reason: '78-toeren en cassettetransfers wonen daar');
    });

    test('te weinig luide vensters: geen oordeel over de band', () {
      final o = beoordeel(spectrum(totHz: 16000), vensters: 3);
      expect(o.band, Bandbreedte.onbekend);
    });
  });

  group('wanneer er niets te zeggen valt', () {
    test('onder 44,1 kHz doen we geen enkele uitspraak', () {
      final o = beoordeel(spectrum(totHz: 15000, sampleRate: 32000), sampleRate: 32000);
      expect(o.isOnbekend, isTrue);
      expect(o.isNep, isFalse);
      expect(waarom(o), 'niet te beoordelen');
    });

    test('een leeg spectrum levert geen oordeel', () {
      final o = beoordeel(Float64List(0));
      expect(o.isOnbekend, isTrue);
    });

    test('onbekend is nadrukkelijk GEEN nep', () {
      const o = Echtheidsoordeel(
          bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.onbekend);
      expect(o.isNep, isFalse);
      expect(o.isOnbekend, isTrue);
    });
  });

  group('het oordeel overleeft een herstart', () {
    test('heen en terug door JSON', () {
      const o = Echtheidsoordeel(
        bits: Bitdiepte.opgeblazen,
        gebruikteBits: 16,
        boven: Bovenband.leeg,
        band: Bandbreedte.afgekapt,
        afkapHz: 19800,
        wandDb: 62,
        vensters: 24,
      );
      final terug = Echtheidsoordeel.fromJson(o.toJson())!;
      expect(terug.bits, o.bits);
      expect(terug.boven, o.boven);
      expect(terug.band, o.band);
      expect(terug.afkapHz, o.afkapHz);
      expect(terug.gebruikteBits, 16);
      expect(terug.isNep, isTrue);
    });

    test('rommel levert null, niet een half oordeel', () {
      expect(Echtheidsoordeel.fromJson({'bits': 'onzin'}), isNull);
      expect(Echtheidsoordeel.fromJson({}), isNull);
    });
  });

  group('de afkap van een mp3 van 320 — het gat dat er zat', () {
    // **Waarom deze groep bestaat.** Spek liet een nep-FLAC zien terwijl de app hem goedkeurde. De
    // oorzaak stond als bewuste keuze in de code: de muurzoeker eiste 2000 Hz ruimte boven de muur,
    // dus op een 44,1 kHz-bestand liep het zoekgebied maar tot 20,05 kHz. Een mp3 van 320 kbit/s
    // kapt rond 20,5 — verreweg de meest gebruikte bron voor een nep-FLAC, en hij viel er net
    // buiten.
    //
    // De toets hierboven heette "een mp3 van 320 kbps" maar gebruikte 19,8 kHz, en dat is waar 256
    // kapt. Hij paste dus binnen het oude bereik en verborg het gat in plaats van het te vinden.

    test('een muur op 20,5 kHz wordt nu gezien', () {
      final o = beoordeel(spectrum(totHz: 20500));
      expect(o.band, Bandbreedte.afgekapt, reason: 'dit is precies waar een mp3 van 320 kapt');
      expect(o.afkapHz, closeTo(20500, 400));
      expect(o.isNep, isTrue);
    });

    test('en de melding noemt de meting eerst, de verklaring erachter', () {
      final o = beoordeel(spectrum(totHz: 20500));
      final zin = waarom(o);
      // De muur wordt op de eerste plek gevonden waar hij het steilst is, dus ergens tussen 20,3 en
      // 20,7 — vandaar het begin van het getal en niet één exacte waarde.
      expect(zin, startsWith('afgekapt op 20.'), reason: 'de gemeten hoogte staat vooraan');
      expect(zin, contains('mp3 320'));
    });

    test('een echte cd-rip die tot Nyquist doorloopt blijft schoon', () {
      // De keerzijde, en de reden dat er nog steeds een marge is: een cd heeft zijn eigen
      // antialiasmuur pal op 22,05 kHz. Zonder marge was élke cd-rip ineens een transcode.
      final o = beoordeel(spectrum(totHz: 22000));
      expect(o.band, Bandbreedte.doorlopend);
      expect(o.isNep, isFalse);
    });

    test('een echte 96 kHz-opname wordt nog steeds niet beschuldigd', () {
      // Het anti-aliasfilter van de omzetter zit daar rond 46 kHz. Dat is een volkomen normale
      // steile val, en hij hoort buiten het zoekgebied te blijven vallen.
      final o = beoordeel(
        spectrum(totHz: 46000, sampleRate: 96000),
        sampleRate: 96000,
        kopSampleRate: 96000,
        kopBits: 24,
        gebruikteBits: 24,
      );
      expect(o.band, Bandbreedte.doorlopend);
      expect(o.isNep, isFalse);
    });
  });

  group('waar een afkap vandaan komt', () {
    test('de bekende encoders worden bij naam genoemd', () {
      expect(vermoedelijkeBron(16000), contains('128'));
      expect(vermoedelijkeBron(19500), contains('V0'));
      expect(vermoedelijkeBron(20500), contains('320'));
    });

    test('met een marge, want encoders schuiven hun filter een beetje', () {
      expect(vermoedelijkeBron(20300), contains('320'));
      expect(vermoedelijkeBron(20700), contains('320'));
    });

    test('en wat nergens naar wijst krijgt geen verzonnen naam', () {
      // Sinds de zoeker tot 21 kHz kijkt zit daar ook de bovengrens van een oude, smal gemasterde
      // cd. Die is smal — dat is een meting — maar hem "mp3" noemen zou een gok zijn.
      expect(vermoedelijkeBron(14500), isNull);
      expect(vermoedelijkeBron(21000), isNull);
    });

    test('een afkap zonder bekende bron zegt nog steeds wat er gemeten is', () {
      expect(afkapZin(14500), contains('14.5'));
      expect(afkapZin(14500), isNot(contains('mp3')));
      expect(afkapZin(14500), contains('smaller'));
    });
  });

  group('wat het dan WEL is', () {
    // Het bolletje naast `FLAC · 24/192` zei dat die getallen niet klopten, zonder te zeggen wat het
    // dan wél was. Dit is dat getal.

    test('een muur in het spectrum bindt sterker dan welke bemonstering ook', () {
      const o = Echtheidsoordeel(
        bits: Bitdiepte.opgeblazen,
        gebruikteBits: 16,
        boven: Bovenband.leeg,
        band: Bandbreedte.afgekapt,
        afkapHz: 17200,
      );
      // Niet "16/44,1": een bestand dat op 17,2 kHz ophoudt draagt geen 44,1 kHz aan inhoud.
      expect(echteResolutie(o, kopSampleRate: 192000, kopBits: 24), 'tot 17.2 kHz');
    });

    test('opgeblazen bits worden het gemeten getal', () {
      const o = Echtheidsoordeel(
        bits: Bitdiepte.opgeblazen,
        gebruikteBits: 16,
        boven: Bovenband.vol,
        band: Bandbreedte.doorlopend,
      );
      expect(echteResolutie(o, kopSampleRate: 192000, kopBits: 24), '16/192');
    });

    test('niets boven 22 kHz betekent dat er niet meer dan 44,1 in zit', () {
      const o = Echtheidsoordeel(
        bits: Bitdiepte.opgeblazen,
        gebruikteBits: 16,
        boven: Bovenband.leeg,
        band: Bandbreedte.doorlopend,
      );
      expect(echteResolutie(o, kopSampleRate: 96000, kopBits: 24), '16/44.1');
    });

    test('klopt de kop, dan valt er niets te vervangen', () {
      const o = Echtheidsoordeel(
        bits: Bitdiepte.spreektNietTegen,
        gebruikteBits: 24,
        boven: Bovenband.vol,
        band: Bandbreedte.doorlopend,
      );
      expect(echteResolutie(o, kopSampleRate: 96000, kopBits: 24), isNull,
          reason: 'dan hoort er ook geen merkteken te staan');
    });
  });
}
