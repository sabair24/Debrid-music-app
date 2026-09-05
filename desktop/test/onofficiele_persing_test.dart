/// Een bootleg moet op het scherm te zien zijn vóór je hem kiest.
///
/// **Gemeld op 05-09-2026, en het kostte twee ronden om te vinden.** Saber's *Gorillaz* stond op
/// Discogs-persing 10367136, en de app meldde onder "19-2000": *"deze uitgave heeft "19-2000 (Soul
/// Child Remix)" staan"*. Zijn antwoord: *"dat is niet waar ??? kijk maar eerst bronnen online
/// altijd controleren"*.
///
/// Bij de bron nagekeken klopte de zin wél — die rij staat er echt:
///
///     titel   : Gorillaz / G Sides
///     formaten: [{"name":"CD","descriptions":["Compilation","Unofficial Release"]}]
///     labels  : Parlophone (2) 7243 5 31138 0 3
///
/// Een bootleg die het catalogusnummer van de echte Parlophone-cd heeft overgenomen, met een
/// rommelige tracklijst zonder looptijden. De weigering was terecht; de UITGAVE deugde niet. En
/// niets op het scherm zei dat het er een was — terwijl Discogs het op elke weg gewoon meestuurt.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/editions.dart';

void main() {
  group('noemtOnofficieel', () {
    test('DE KERN: de zoekresultaten geven een LIJST', () {
      // Nagemeten bij Discogs op 05-09-2026, zoekend op artist=Gorillaz&release_title=Gorillaz.
      expect(noemtOnofficieel(['CD', 'Album', 'Enhanced', 'Unofficial Release']), isTrue);
      expect(noemtOnofficieel(['Cassette', 'Album', 'Unofficial Release', 'Stereo']), isTrue);
      expect(noemtOnofficieel(['CD', 'Album', 'Enhanced', 'Repress']), isFalse);
      expect(noemtOnofficieel(['CD', 'Album']), isFalse);
    });

    test('en de persingenlijst geeft één STRING', () {
      // Twee vormen, één oordeel — twee eigen zeven zouden vroeg of laat verschillen.
      expect(noemtOnofficieel('CD, Album, Unofficial Release'), isTrue);
      expect(noemtOnofficieel('CD, Album, Enhanced'), isFalse);
    });

    test('leeg of niets is niet onofficieel', () {
      expect(noemtOnofficieel(null), isFalse);
      expect(noemtOnofficieel(const <String>[]), isFalse);
      expect(noemtOnofficieel(''), isFalse);
    });
  });

  group('de vlag overleeft de weg naar het scherm', () {
    test('withArt houdt hem vast', () {
      // De scans komen ná de lijst binnen, en dán wordt de rij opnieuw gebouwd. Viel de vlag daar
      // weg, dan verdween de waarschuwing precies op het moment dat de rij compleet werd.
      const k = ReleaseChoice(
        source: EditionSource.discogs,
        releaseId: 10367136,
        format: 'CD',
        catno: '7243 5 31138 0 3',
        onofficieel: true,
      );
      expect(k.withArt(tracks: const [ChoiceTrack('1', 'x', 100)]).onofficieel, isTrue);
    });

    test('en standaard staat hij uit', () {
      const k = ReleaseChoice(source: EditionSource.discogs, releaseId: 1, format: 'CD');
      expect(k.onofficieel, isFalse);
      expect(k.withArt().onofficieel, isFalse);
    });
  });
}
