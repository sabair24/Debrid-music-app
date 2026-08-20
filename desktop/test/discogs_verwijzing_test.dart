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
import 'package:debridmusic/editions.dart';

ReleaseChoice rij({
  int id = 1,
  String? catno,
  String? country,
  String? barcode,
  bool detailed = false,
  ChoiceImage? front,
  ChoiceImage? back,
  ChoiceImage? disc,
}) =>
    ReleaseChoice(
      source: EditionSource.discogs,
      releaseId: id,
      format: 'CD',
      catno: catno,
      country: country,
      barcode: barcode,
      detailed: detailed,
      front: front,
      back: back,
      disc: disc,
    );

const _plaatje = ChoiceImage('https://x/a.jpg', 'https://x/a-thumb.jpg');

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

    test('een slug zonder link is dubbelzinnig en wordt geweigerd', () {
      // "7738290-Stromae-Te-Quiero" komt uit een uitgave-link en "1938390-Stromae-Racine-Carree"
      // uit een master-link, en ze zien er identiek uit. Master- en uitgavenummers lopen bovendien
      // door hetzelfde bereik, dus een gok haalt geen "verkeerde soort" op maar een WILDVREEMDE
      // uitgave — en zet die bovenaan als degene die je vroeg. Weigeren is hier het goede antwoord;
      // de hele link plakken werkt wel, want daar staat in wat het is.
      expect(DiscogsVerwijzing.ontleed('7738290-Stromae-Te-Quiero'), isNull);
      expect(DiscogsVerwijzing.ontleed('1938390-Stromae-Racine-Carree'), isNull);
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

    test('een getal als tekst gooit niet, maar wordt gelezen', () {
      // `as num?` gooit op een tekst in plaats van null te geven, en die fout viel tot in de
      // dialoog — die er dan "Discogs was niet bereikbaar" van maakte terwijl er net een pagina
      // vol uitgaves was binnengekomen.
      expect(
          DiscogsService.paginaAantal({
            'pagination': {'pages': '4'}
          }),
          4);
      expect(
          DiscogsService.paginaAantal({
            'pagination': {'pages': 'weet ik veel'}
          }),
          1);
    });
  });

  group('twee keer dezelfde uitgave in de lijst', () {
    test('een rij mag nooit voor een armere geruild worden', () {
      final kaal = rij();
      final metHoes = rij(front: _plaatje);
      final opgezocht = rij(detailed: true, front: _plaatje, back: _plaatje, disc: _plaatje);
      final opgezochtEnLeeg = rij(detailed: true);

      // De MusicBrainz-kant: eerst kaal, daarna opnieuw met alles erin. Zonder deze volgorde bleef
      // elke uitgave voor eeuwig op "scans ophalen…" staan.
      expect(rijkdom(opgezocht), greaterThan(rijkdom(kaal)));
      expect(rijkdom(metHoes), greaterThan(rijkdom(kaal)));

      // De nummerveld-kant: wat het veld ophaalt is per definitie nog niet opgezocht. Dat over een
      // rij heen zetten die al scans had is de andere helft van hetzelfde molentje.
      expect(rijkdom(kaal), lessThan(rijkdom(opgezocht)));

      // En de regel die die twee verenigt: opgezocht-en-niets-gevonden is nog altijd een ANTWOORD,
      // en telt zwaarder dan een rij waar nog nooit iemand naar gekeken heeft.
      expect(rijkdom(opgezochtEnLeeg), greaterThan(rijkdom(metHoes)));
    });
  });

  group('wanneer twee rijen dezelfde persing zijn', () {
    test('"none" is geen catalogusnummer', () {
      // DE reden dat een promo onvindbaar was. Discogs schrijft letterlijk "none" waar een uitgave
      // geen catalogusnummer heeft — precies wat promo's, testpersingen en witlabels gemeen hebben.
      // Als nummer behandeld werden ze allemaal één rij, en die ene rij was er dan één van.
      final a = rij(id: 1, catno: 'none', country: 'Europe');
      final b = rij(id: 2, catno: 'none', country: 'Europe');
      expect(a.dedupeKey, isNot(b.dedupeKey));
      // Hoofdletters en spaties eromheen zijn hetzelfde woord.
      expect(rij(id: 3, catno: ' None ', country: 'Europe').dedupeKey,
          isNot(rij(id: 4, catno: 'NONE', country: 'Europe').dedupeKey));
    });

    test('een echt catalogusnummer ontdubbelt nog steeds wel', () {
      // Anders zou dezelfde persing twee keer in de lijst staan: één keer van MusicBrainz en één
      // keer van Discogs. Dat is waar deze sleutel voor gemaakt is en dat moet blijven werken.
      expect(rij(id: 1, catno: '88725453152', country: 'FR').dedupeKey,
          rij(id: 2, catno: '887-254 531 52', country: 'fr').dedupeKey);
      // En een streepjescode wint van allebei.
      expect(rij(id: 1, barcode: '0888751234561', catno: 'A').dedupeKey,
          rij(id: 2, barcode: '088875 123456 1', catno: 'B').dedupeKey);
    });
  });
}
