/// Een Discogs-nummer intypen, en alle pagina's van een master ophalen.
///
/// **Waarom dit bestaat.** Van Stromae's "Te Quiero" bestaat een promo-cd met een scan van het
/// schijfje zelf. Die uitgave was in de kiezer met geen mogelijkheid te bereiken: het zoeken op naam
/// komt uit bij een master, deze persing hing onder een ander, en van elk master werd alleen de
/// eerste pagina opgehaald. Twee muren, allebei onzichtbaar — de lijst hield gewoon op.
///
/// De uitweg is een nummer intypen. Dat nummer staat op zes verschillende manieren op het scherm,
/// en dit bestand houdt vast dat ze alle zes aankomen: één vorm die faalt betekent dat iemand die
/// een link plakt te horen krijgt dat zijn uitgave niet bestaat terwijl hij ernaar zit te kijken.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/discogs.dart';

void main() {
  group('waar een ingetypt nummer naar wijst', () {
    test('een kaal nummer is een uitgave', () {
      // Het nummer dat op de releasepagina staat, zonder meer. Dit is wat iemand overtypt.
      final v = DiscogsVerwijzing.ontleed('7738290');
      expect(v?.id, 7738290);
      expect(v?.isMaster, isFalse);
      // Met spaties eromheen, want dat is wat plakken oplevert.
      expect(DiscogsVerwijzing.ontleed('  7738290 ')?.id, 7738290);
    });

    test("Discogs' eigen schrijfwijze, met en zonder haken", () {
      expect(DiscogsVerwijzing.ontleed('[r7738290]')?.isMaster, isFalse);
      expect(DiscogsVerwijzing.ontleed('r7738290')?.id, 7738290);
      expect(DiscogsVerwijzing.ontleed('[m1938390]')?.isMaster, isTrue);
      expect(DiscogsVerwijzing.ontleed('m1938390')?.id, 1938390);
      // Hoofdletters komen mee uit een kopieerde regel.
      expect(DiscogsVerwijzing.ontleed('[R7738290]')?.id, 7738290);
    });

    test('een gedeelde link, in elke vorm waarin Discogs hem geeft', () {
      final r = DiscogsVerwijzing.ontleed(
          'https://www.discogs.com/release/7738290-Stromae-Te-Quiero');
      expect(r?.id, 7738290);
      expect(r?.isMaster, isFalse);

      final m = DiscogsVerwijzing.ontleed('https://www.discogs.com/master/1938390-Stromae-Te-Quiero');
      expect(m?.id, 1938390);
      expect(m?.isMaster, isTrue);

      // DE regel die het vaakst misgaat: blader je niet in het Engels, dan zet Discogs een taalcode
      // in het pad. Zonder deze zou een Franstalige of Nederlandstalige link nooit werken.
      expect(DiscogsVerwijzing.ontleed('https://www.discogs.com/fr/release/7738290-Stromae')?.id,
          7738290);
      expect(DiscogsVerwijzing.ontleed('https://www.discogs.com/nl/master/1938390')?.isMaster,
          isTrue);

      // De api-vorm staat in het meervoud, en die komt langs zodra iemand een adres uit deze app
      // of uit een browsertabblad kopieert.
      expect(DiscogsVerwijzing.ontleed('https://api.discogs.com/releases/7738290')?.id, 7738290);
      expect(DiscogsVerwijzing.ontleed('https://api.discogs.com/masters/1938390')?.isMaster, isTrue);

      // Zonder protocol ervoor, zoals een adresbalk hem laat zien.
      expect(DiscogsVerwijzing.ontleed('discogs.com/release/7738290')?.id, 7738290);
    });

    test('de staart van een link zonder de link erbij', () {
      // Wat je overhoudt als je alleen het laatste stuk van het adres pakt.
      final v = DiscogsVerwijzing.ontleed('7738290-Stromae-Te-Quiero');
      expect(v?.id, 7738290);
      expect(v?.isMaster, isFalse);
    });

    test('en wat er GEEN nummer is levert niets, en geen gok', () {
      // Een gok hier is erger dan een weigering: dan haalt de app een wildvreemde uitgave op en
      // zet die bovenaan de lijst als "degene die je vroeg".
      expect(DiscogsVerwijzing.ontleed(''), isNull);
      expect(DiscogsVerwijzing.ontleed('   '), isNull);
      expect(DiscogsVerwijzing.ontleed('Stromae'), isNull);
      expect(DiscogsVerwijzing.ontleed('https://www.discogs.com/artist/1795148-Stromae'), isNull);
      expect(DiscogsVerwijzing.ontleed('https://musicbrainz.org/release/abc'), isNull);
      // Nul is geen uitgave; het is wat een mislukte omzetting oplevert.
      expect(DiscogsVerwijzing.ontleed('0'), isNull);
      expect(DiscogsVerwijzing.ontleed('[r0]'), isNull);
      // Een getal dat niet in een int past mag niet als 'geldig' doorgaan.
      expect(DiscogsVerwijzing.ontleed('99999999999999999999999'), isNull);
    });

    test('de vorm die teruggelezen kan worden', () {
      expect(const DiscogsVerwijzing(DiscogsSoort.release, 7738290).toString(), 'r7738290');
      expect(const DiscogsVerwijzing(DiscogsSoort.master, 1938390).toString(), 'm1938390');
    });
  });

  group('hoeveel pagina\'s een master heeft', () {
    test('leest wat Discogs erover zegt', () {
      expect(
          DiscogsService.paginaAantal({
            'pagination': {'page': 1, 'pages': 4, 'items': 312},
            'versions': <dynamic>[],
          }),
          4);
      expect(
          DiscogsService.itemAantal({
            'pagination': {'pages': 4, 'items': 312}
          }),
          312);
    });

    test('zonder dat blok is het er één, en nooit nul', () {
      // Nul zou de lus laten stoppen alsof er niets was, terwijl er net een pagina binnenkwam —
      // en dan is de lijst leeg terwijl het antwoord er ligt.
      expect(DiscogsService.paginaAantal(null), 1);
      expect(DiscogsService.paginaAantal({'versions': <dynamic>[]}), 1);
      expect(
          DiscogsService.paginaAantal({
            'pagination': {'pages': 0}
          }),
          1);
      expect(DiscogsService.itemAantal(null), isNull);
    });
  });
}
