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

import 'dart:io';
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

  // Saber op 05-10-2026, met zijn S26 dwars (832×384 punten): de gestapelde indeling duwde de titel,
  // de spoelbalk en de knoppen onder de rand. Je zag de hoes en de albumnaam, verder niets.
  group('een telefoon dwars', () {
    /// Schermmaat en wat er overblijft zonder de systeembalken (status, navigatie, uitsparing).
    const dwars = <(String, Size, Size)>[
      ('S26 dwars', Size(832, 384), Size(795, 331)),
      ('Pixel 7 dwars', Size(915, 412), Size(867, 364)),
      ('kleine telefoon dwars', Size(740, 360), Size(704, 320)),
      ('S26, systeembalken verborgen', Size(832, 384), Size(832, 384)),
      // Hier is de BREEDTE de grens en niet de hoogte: dan moet de hoes krimpen voor de kolom.
      ('smal en laag venster', Size(700, 440), Size(680, 430)),
    ];

    test('DE KERN: dwars is liggend — niet naast elkaar, niet gestapeld', () {
      for (final (naam, scherm, _) in dwars) {
        expect(liggend(scherm: scherm, tv: false), isTrue, reason: naam);
        expect(naastElkaar(scherm: scherm, compact: false, tv: false), isFalse, reason: naam);
      }
    });

    test('DE GRENS: staand, een breed venster en een televisie zijn het niet', () {
      expect(liggend(scherm: const Size(384, 832), tv: false), isFalse, reason: 'de S26 staand');
      expect(liggend(scherm: const Size(1440, 900), tv: false), isFalse, reason: 'hoog genoeg voor naast elkaar');
      expect(liggend(scherm: const Size(960, 540), tv: true), isFalse,
          reason: 'de Shield heeft zijn eigen indeling, met de hoes als rustplek');
    });

    for (final (naam, _, bruikbaar) in dwars) {
      test('DE VAL ($naam): de cd schuift niet in de kolom, en alles past in de hoogte', () {
        final hoes = hoesLiggend(bruikbaar: bruikbaar);
        final kolom = kolomLiggend(bruikbaar: bruikbaar, hoes: hoes);
        final blok = blokBreedte(hoes: hoes, reisfactor: kLiggendReis);
        expect(kGoot * 2 + blok + kLiggendGat + kolom, lessThanOrEqualTo(bruikbaar.width + .5),
            reason: 'hoesblok + gat + kolom mogen samen niet breder zijn dan het scherm');
        expect(hoes + kLiggendLucht, lessThanOrEqualTo(bruikbaar.height + .5),
            reason: 'de hoes met de balk erboven en de albumnaam eronder past in de hoogte');
        expect(kolom, greaterThanOrEqualTo(kLiggendKolomMin), reason: 'zes knoppen op een rij');
        // De kolom (titel, artiest, spoelbalk, knoppen) is ~250 punten; onder de balk van 48 moet
        // daar plaats voor zijn — anders valt de knoppenrij weer onder de rand.
        expect(bruikbaar.height - 48, greaterThanOrEqualTo(250), reason: 'de kolom past ernaast');
        expect(hoes, greaterThanOrEqualTo(180), reason: 'een hoes die het waard is, geen postzegel');
      });
    }

    test('Now playing gebruikt de liggende indeling, met de kleinere uitschuifruimte', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains("final dwars = !naast && liggend(scherm: schermmaat, tv: isTv);"));
      expect(main, contains("key: const Key('np-dwars'),"));
      expect(main, contains('reisFactor: dwars ? kLiggendReis : null,'),
          reason: 'anders rekent de cd met de ruimte van een breed scherm en schuift hij in de kolom');
      expect(main, contains('if (!dwars && artiestVanPlaat.trim().isNotEmpty)'),
          reason: 'het logo boven de hoes past niet in 384 punten hoogte');
    });
  });
}
