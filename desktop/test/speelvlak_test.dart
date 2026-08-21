/// De cd mag nooit in de tekst schuiven.
///
/// **Waarom deze toets bestaat.** Op het speelscherm schuift de cd zijwaarts uit de hoes, naar
/// rechts. In de nieuwe indeling staat de tekstkolom precies daar. `AlbumArt` reserveert die
/// loopruimte in zijn eigen breedte — 1,62 maal de hoes op een breed scherm — maar dat helpt alleen
/// als de indeling ermee rekent.
///
/// Doet ze dat niet, dan gebeurt er niets zolang de muziek stilstaat: de cd zit dan grotendeels
/// achter de hoes. Pas als je op afspelen drukt komt hij eruit, en dan schuift hij onder de titel.
/// Dat is precies het soort fout dat een schermafbeelding van een stilstaand scherm niet laat zien.
library;

import 'dart:ui' show Size;

import 'package:debridmusic/ui/maten.dart';
import 'package:debridmusic/ui/speelvlak.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wat `discTravelFactor` teruggeeft: 0,62 breed, 0,30 op een telefoon.
const breed = .62;
const smal = .30;

/// De schermen waar de indeling naast elkaar op kan landen.
const _schermen = <(String, Size)>[
  ('krap 1100×600', Size(1100, 600)),
  ('venster 1440×900', Size(1440, 900)),
  ('de Mac van de gebruiker ~1600×867', Size(1600, 867)),
  ('groot 1920×1080', Size(1920, 1080)),
  ('heel groot 3000×1600', Size(3000, 1600)),
];

void main() {
  group('de uitgeschoven cd raakt de tekstkolom niet', () {
    for (final (naam, scherm) in _schermen) {
      test(naam, () {
        final hoes = hoesNaast(scherm: scherm, reisfactor: breed);
        final blok = blokBreedte(hoes: hoes, reisfactor: breed);
        final samen = kGoot + blok + kSpeelGat + kSpeelKolom + kGoot;
        expect(samen, lessThanOrEqualTo(scherm.width),
            reason: 'goot + blok($blok) + gat + kolom + goot = $samen past niet in ${scherm.width}');
        // En het gat is écht een gat: de cd houdt op vóór de kolom begint.
        expect(blok - hoes, closeTo(hoes * breed, 0.01),
            reason: 'de loopruimte hoort de volle reis te zijn');
      });
    }
  });

  group('wanneer de indeling omslaat', () {
    test('een breed venster krijgt hem', () {
      expect(naastElkaar(scherm: const Size(1600, 867), compact: false, tv: false), isTrue);
    });

    test('een telefoon niet', () {
      expect(naastElkaar(scherm: const Size(411, 915), compact: true, tv: false), isFalse);
    });

    test('een smal pc-venster niet — daar zou de hoes juist kleiner worden', () {
      expect(naastElkaar(scherm: const Size(1000, 800), compact: false, tv: false), isFalse);
    });

    test('een laag venster niet — dan loopt de kolom over de onderrand', () {
      expect(naastElkaar(scherm: const Size(1600, 400), compact: false, tv: false), isFalse);
    });

    test('een televisie NOOIT, hoe breed ook', () {
      // De hoes is daar de rustplek van de markering, en rechts is er "volgend nummer". Staat de
      // knoppenrij rechts van de hoes, dan is hij met de afstandsbediening onbereikbaar.
      expect(naastElkaar(scherm: const Size(960, 540), compact: false, tv: true), isFalse);
      expect(naastElkaar(scherm: const Size(1920, 1080), compact: false, tv: true), isFalse);
    });
  });

  group('de hoes wordt er groter van, niet kleiner', () {
    /// De gestapelde regel, zoals `_sleeve` in main.dart hem aanhoudt op een breed scherm.
    double gestapeld(Size s) {
      final opBreedte = (s.width - 40) / (1 + breed);
      final opHoogte = s.height * .46;
      final kleinste = opBreedte < opHoogte ? opBreedte : opHoogte;
      return kleinste.clamp(140.0, 520.0);
    }

    for (final (naam, scherm) in _schermen) {
      test(naam, () {
        expect(hoesNaast(scherm: scherm, reisfactor: breed), greaterThan(gestapeld(scherm)),
            reason: 'als de hoes er niet groter van wordt, is de verbouwing zinloos');
      });
    }
  });

  test('op een enorm scherm wordt de hoes geen behang', () {
    expect(hoesNaast(scherm: const Size(6000, 3000), reisfactor: breed), 720);
  });

  test('de smalle reisfactor van een telefoon geeft een smaller blok', () {
    // Niet in gebruik in deze indeling — een telefoon blijft gestapeld — maar de som hoort ook daar
    // te kloppen, want dit is dezelfde reservering die `_sleeve` op een telefoon gebruikt.
    expect(blokBreedte(hoes: 269, reisfactor: smal), closeTo(349.7, .1));
  });
}
