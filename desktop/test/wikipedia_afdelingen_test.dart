/// Een Wikipedia-artikel in stukken knippen, zonder dat er een kopje overblijft dat niets toont.
///
/// **Waarom dit bestaat.** De biografie op de artiestpagina wordt een uitklapbaar venster waarin je
/// per SECTIE openklapt. Daarvoor moet de tekst betrouwbaar in koppen en lichamen uiteenvallen, en
/// daar zitten twee vallen in die allebei gemeten zijn op 10-09-2026.
///
/// **De eerste: `exsectionformat=raw` is onbruikbaar.** Die levert zijn scheidingstekens als
/// U+FFFD — het vervangingsteken, oftewel precies het teken dat al "deze tekst is stuk" betekent.
/// Op de echte respons voor Stromae kwam er `\n \n 357 277 275 357 277 275 2 …` uit, en `357 277
/// 275` is `EF BF BD`. In een repo die `mojibake.dart` heeft omdát dat teken ook om andere redenen
/// opduikt, is dat het slechtst denkbare scheidingsteken. `wiki` geeft schoon `== Kop ==`.
///
/// **De tweede: `explaintext` rendert tabellen als niets.** "Discografie", "Prijzen" en "Externe
/// links" komen dus terug als een kop boven een leegte. Een kopje dat je openklapt en waar niets
/// onder staat is erger dan geen kopje — het lijkt op een storing.
///
/// De ontleder is puur, dus deze toets heeft geen netwerk nodig. En juist omdat hij puur is kan een
/// verkeerde uitdrukking er stil in blijven zitten: niets wordt rood, je ziet alleen een venster
/// met lege kopjes of met één brok tekst.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/wikipedia.dart';

/// Zoals `action=query&prop=extracts&explaintext=1&exsectionformat=wiki` het echt aanlevert.
const _uittreksel = '''
Paul Van Haver, beter bekend onder zijn artiestennaam Stromae, is een Belgisch zanger, rapper en
producer. Hij brak internationaal door met Alors on danse.


== Biografie ==

Van Haver werd geboren in Etterbeek als zoon van een Rwandese vader en een Vlaamse moeder.


=== Beginjaren ===

Op zijn elfde ging hij naar de muziekacademie.


=== Doorbraak ===

In 2009 verscheen Alors on danse, dat in verschillende landen op nummer één belandde.


== Discografie ==


== Prijzen ==


== Externe links ==

''';

void main() {
  group('koppen en niveaus', () {
    test('DE KERN: elke kop komt terug met zijn niveau', () {
      final r = ontleedAfdelingen(_uittreksel);
      expect(r.afdelingen.map((a) => a.kop).toList(), ['Biografie', 'Beginjaren', 'Doorbraak'],
          reason: 'een sectie die niet herkend wordt is een stuk biografie dat je niet kunt openen');
      expect(r.afdelingen.map((a) => a.niveau).toList(), [2, 3, 3],
          reason: 'zonder het niveau staat een onderdeel even zwaar als het hoofdstuk erboven');
    });

    test('DE KERN: de inleiding is wat er VOOR de eerste kop staat', () {
      final r = ontleedAfdelingen(_uittreksel);
      expect(r.intro, startsWith('Paul Van Haver'));
      expect(r.intro, contains('Alors on danse'));
      expect(r.intro, isNot(contains('==')),
          reason: 'een kopje in de ingeklapte inleiding is opmaak die naar het scherm lekt');
    });

    test('DE KERN: de tekst van een sectie hoort bij die sectie', () {
      final r = ontleedAfdelingen(_uittreksel);
      final beginjaren = r.afdelingen.firstWhere((a) => a.kop == 'Beginjaren');
      expect(beginjaren.tekst, 'Op zijn elfde ging hij naar de muziekacademie.');
      final biografie = r.afdelingen.firstWhere((a) => a.kop == 'Biografie');
      expect(biografie.tekst, isNot(contains('muziekacademie')),
          reason: 'een hoofdstuk slokt de tekst van zijn onderdelen op');
    });
  });

  group('wat er NIET doorheen mag', () {
    test('DE VAL: een sectie zonder tekst valt weg', () {
      final r = ontleedAfdelingen(_uittreksel);
      expect(r.afdelingen.map((a) => a.kop), isNot(contains('Discografie')),
          reason: 'anders staat er een kopje dat opengeklapt niets toont');
      expect(r.afdelingen.map((a) => a.kop), isNot(contains('Prijzen')));
    });

    test('DE VAL: de staart gaat eruit, ook als er wél tekst onder staat', () {
      const met = '''
Inleiding.


== Zie ook ==

Lijst van Belgische zangers


== Externe links ==

Officiële website


== Referenties ==

Deze pagina heeft bronnen.
''';
      final r = ontleedAfdelingen(met);
      expect(r.afdelingen, isEmpty,
          reason: 'een lezer klapt geen "Referenties" open om over de artiest te lezen');
      expect(r.intro, 'Inleiding.');
    });

    test('DE VAL: ongelijke tekens links en rechts zijn geen kop', () {
      // `== a ===` is geen kopje maar tekst. De terugverwijzing \\1 in de uitdrukking is precies
      // wat dat afvangt; zonder die verwijzing wordt het niveau een gok.
      final r = ontleedAfdelingen('Begin.\n\n== Scheef ===\n\nInhoud.\n');
      expect(r.afdelingen, isEmpty);
      expect(r.intro, contains('Scheef'),
          reason: 'wat geen kop is hoort gewoon tekst te blijven, niet te verdwijnen');
    });
  });

  group('grensgevallen', () {
    test('DE GRENS: een artikel zonder koppen is één inleiding', () {
      final r = ontleedAfdelingen('Een korte biografie zonder secties.');
      expect(r.afdelingen, isEmpty);
      expect(r.intro, 'Een korte biografie zonder secties.');
    });

    test('DE GRENS: een leeg uittreksel valt niet om', () {
      final r = ontleedAfdelingen('');
      expect(r.intro, isEmpty);
      expect(r.afdelingen, isEmpty);
    });

    test('DE GRENS: een kop op de eerste regel laat de inleiding leeg', () {
      final r = ontleedAfdelingen('== Meteen ==\n\nTekst.\n');
      expect(r.intro, isEmpty);
      expect(r.afdelingen.single.kop, 'Meteen');
    });

    test('DE GRENS: niveau 4 tot 6 tellen ook mee', () {
      final r = ontleedAfdelingen('Intro.\n\n==== Diep ====\n\nTekst.\n');
      expect(r.afdelingen.single.niveau, 4);
    });
  });

  group('de bronvermelding', () {
    test('DE KERN: de url wijst naar de pagina waar de tekst vandaan komt', () {
      // CC BY-SA vraagt om vermelding. Klopt deze url niet, dan verwijst de app naar niets.
      // Spaties worden liggende streepjes, zoals Wikipedia zijn eigen links schrijft — NIET %20.
      const a = WikiArtikel(taal: 'nl', titel: 'Michael Jackson', intro: 'x');
      expect(a.url, 'https://nl.wikipedia.org/wiki/Michael_Jackson');
    });

    test('DE VAL: een titel met bijzondere tekens blijft een werkende link', () {
      const a = WikiArtikel(taal: 'nl', titel: 'Beyoncé', intro: 'x');
      expect(a.url, contains('wikipedia.org/wiki/'));
      expect(a.url, isNot(contains(' ')), reason: 'een spatie in een url maakt hem onklikbaar');
    });
  });

  group('de cache', () {
    test('DE VAL: een ander schema geeft null in plaats van halve gegevens', () {
      // Zonder dit antwoordt elke regel die een oudere bouw bewaarde voor altijd met de velden die
      // toen bestonden -- de les die `AlbumInfo` en `ArtistArt` allebei al dragen.
      expect(WikiArtikel.fromJson({'v': 0, 'taal': 'nl', 'titel': 'X'}), isNull);
    });

    test('DE KERN: de rondreis door JSON houdt de secties vast', () {
      const a = WikiArtikel(
        taal: 'nl',
        titel: 'Stromae',
        intro: 'Paul Van Haver',
        afdelingen: [WikiAfdeling(niveau: 3, kop: 'Beginjaren', tekst: 'Muziekacademie.')],
        beeldUrl: 'https://upload.wikimedia.org/x.jpg',
        beeldBreedte: 470,
        beeldHoogte: 574,
        haaldMs: 1757000000000,
      );
      final terug = WikiArtikel.fromJson(a.toJson())!;
      expect(terug.titel, 'Stromae');
      expect(terug.afdelingen.single.kop, 'Beginjaren');
      expect(terug.afdelingen.single.niveau, 3);
      expect(terug.beeldBreedte, 470);
      expect(terug.haaldMs, 1757000000000);
    });
  });
}
