/// De cachesleutels mogen niet verschuiven. Deze toets legt vast wat er vandaag op schijf staat.
///
/// **Waarom dit bestaat.** Eén FNV-1a bepaalt de bestandsnamen van élke cache in deze app:
/// `covers/<fnv>.jpg`, `bios/<fnv>.txt`, `artistart/<fnv>.json`, `albuminfo/<fnv>.json`,
/// `discography/<fnv>.json`, `wikipedia/<fnv>.json` en de merkbestanden in `hoescache`. Verschuift
/// de uitkomst, dan raakt niet één bestand zoek maar de héle bewaarde cache tegelijk: de app ziet
/// overal een gat en haalt honderden bestanden opnieuw op, over gelimiteerde banen. `hoesMerk` gaat
/// bovendien als ETag over de lijn, dus een afwijking daar laat élk toestel élke hoes opnieuw halen.
///
/// **En dat gebeurt zonder één rode toets.** Dat is de kern van het gevaar. Een verschoven hash is
/// geen uitzondering en geen foutmelding — de code doet precies wat er staat, de app start gewoon
/// op, en het enige wat je merkt is dat alles opeens traag is en de banen vollopen. Er is niets dat
/// zo'n wijziging tegenhoudt behalve vastgelegde uitkomsten, en die staan hier.
///
/// **Waar de getallen vandaan komen.** Ze zijn berekend met de zes losse lussen zoals die er stonden
/// vóór het samenvoegen — `album_facts.dart`, `discography_service.dart`, twee maal in
/// `enrichment.dart`, `library.dart` en `wikipedia.dart`. Ze beschrijven dus geen wens maar de
/// werkelijkheid op de schijf van de gebruiker.
///
/// Gaat er hier iets rood, dan is het antwoord bijna nooit "pas de verwachting aan". Het antwoord is
/// dat de wijziging elke bestaande cache weggooit.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/cachesleutel.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

Track _t(String pad) => Track(path: pad, title: 'x', artist: 'Portishead', album: 'Dummy');

/// Dezelfde reeks als in `hoesmerk_test.dart`, zodat de twee toetsen over hetzelfde beeld praten.
List<int> _plaatje(int zaad, {int lengte = 4000}) =>
    [for (var i = 0; i < lengte; i++) (zaad * 31 + i * 7) % 256];

void main() {
  group('de kale hash', () {
    test('DE KERN: elke sleutelvorm in de app houdt zijn uitkomst', () {
      // Eén regel per cachemap, met de vorm die de aanroeper er echt in stopt. Staat een regel
      // hieronder op rood, dan is het díe map die leegloopt.
      const vast = <String, String>{
        'the doors|l.a. woman': 'f4097460', //      covers/  ·  CoverEnricher.keyFor
        'radiohead': '46be2a6', //                  bios/ en artistart/  ·  naam kleingemaakt
        'v2|radiohead|ok computer': '2e5c3c1b', //  albuminfo/
        'disco|v7|doors': 'cde2c641', //            discography/  ·  schema | artistKey
        'a1|stromae': '8a4aa236', //                wikipedia/  ·  naam naar artikel
        't1|nl|Michael Jackson': 'a0db5548', //     wikipedia/  ·  het artikel zelf
        'Sigur Rós|Ágætis byrjun': 'fd684019', //   een naam met accenten
      };
      vast.forEach((invoer, verwacht) {
        expect(fnv1a(invoer), verwacht,
            reason: 'de bewaarde bestanden van "$invoer" zijn onvindbaar geworden');
      });
    });

    test('DE VAL: codeUnits en niet runes', () {
      // Voor gewone tekst — accenten inbegrepen — geven ze hetzelfde antwoord, dus een verwisseling
      // overleeft zowel een vluchtige blik als de helft van de toetsen hierboven. Pas bij een teken
      // buiten de BMP lopen ze uiteen. Met `runes` zou hier 15c1eadd staan.
      expect(fnv1a('x🎵y'), 'b856b61f',
          reason: 'de hash telt code points in plaats van code units, en dan schuift élke sleutel '
              'met een emoji of een zeldzaam teken erin');
    });

    test('DE VAL: geen nullen ervoor', () {
      // `toRadixString` levert géén vaste breedte. Wie dat "netter" maakt met padLeft(8) hernoemt in
      // één klap elk bestand waarvan de hash toevallig onder 0x10000000 uitkwam.
      expect(fnv1a('radiohead'), hasLength(7));
      expect(fnv1a('radiohead'), isNot(startsWith('0')));
    });

    test('DE GRENS: leeg is het startgetal zelf', () {
      expect(fnv1a(''), '811c9dc5');
      expect(fnvBegin.toRadixString(16), '811c9dc5');
    });

    test('DE GRENS: de uitkomst blijft binnen 32 bits', () {
      // Zonder het masker groeit `h` bij elke stap door tot het getal alle betekenis verliest, en
      // dan is de naam op schijf opeens zestien tekens lang.
      for (final s in ['', 'a', 'x' * 10000, 'Ágætis byrjun', 'x🎵y']) {
        expect(fnv1aVan(s), inInclusiveRange(0, 0xFFFFFFFF));
        expect(fnv1a(s).length, lessThanOrEqualTo(8),
            reason: 'de hash is over 32 bits heen gelopen');
      }
    });

    test('DE GRENS: doorhashen op een meegegeven h is hetzelfde als in één keer', () {
      // Hier leunen `trackSetHashOf` en `hoesMerk` op: die hashen twee stukken achter elkaar.
      expect(fnv1aVan('def', fnv1aVan('abc')), fnv1aVan('abcdef'));
      expect(fnv1aBytes([0x64, 0x65, 0x66], fnv1aVan('abc')), fnv1aVan('abcdef'));
    });
  });

  group('trackSetHashOf', () {
    test('DE KERN: een vaste plaat houdt zijn uitkomst', () {
      final t = [_t(r'D:\m\01 - Mysterons.flac'), _t(r'D:\m\02 - Sour Times.flac')];
      expect(trackSetHashOf(t), '2-bc0e1899',
          reason: 'elke plaat vraagt zijn zes MusicBrainz-verzoeken opnieuw');
    });

    test('DE VAL: de scheider tussen de namen blijft staan', () {
      // Zonder scheider hashen ["ab","c"] en ["a","bc"] dezelfde reeks letters, en dan deelt de ene
      // plaat de feiten van de andere. Beide waarden staan hier, zodat een "opgeruimde" join met
      // een scheider ALLEEN ertussen — dus niet achter de laatste — er ook over valt.
      expect(trackSetHashOf([_t('/m/ab'), _t('/m/c')]), '2-b2c0bfe1');
      expect(trackSetHashOf([_t('/m/a'), _t('/m/bc')]), '2-2c1aa8b');
    });

    test('DE GRENS: een plaat zonder nummers', () {
      expect(trackSetHashOf(const <Track>[]), '0-811c9dc5');
    });
  });

  group('hoesSleutel', () {
    test('DE KERN: pad, grootte en mtime houden hun vorm', () {
      // De grootte en de mtime gaan er ONGEHASHT in, in radix 36. Dat is geen detail: wie ze alsnog
      // door de hash haalt of naar radix 16 verhuist hernoemt elk merkbestand in `hoescache`.
      expect(hoesSleutel(r'C:\Muziek\Portishead\Dummy\01.flac', 1730000000000, 41234567),
          'fa17f02d_ojssn_m2r1bz7k',
          reason:
              'de app leest bij élke start alle ingebedde hoezen opnieuw van de draaiende schijf');
    });
  });

  group('hoesMerk', () {
    test('DE KERN: dezelfde hoes houdt hetzelfde merk', () {
      expect(CoverEnricher.hoesMerk(_plaatje(1)), 'd3524f1',
          reason: 'elk toestel houdt zijn hoescache voor achterhaald en haalt alles opnieuw op');
    });

    test('DE VAL: de lengte hashet mee', () {
      // Eén byte langer, verder dezelfde reeks. De lengte gaat als TEKST vooraan de hash in; laat je
      // dat weg, dan is dit verschil veel minder scherp dan het lijkt.
      expect(CoverEnricher.hoesMerk(_plaatje(1, lengte: 4001)), 'e7b6173');
    });

    test('DE GRENS: te klein om een hoes te zijn', () {
      expect(CoverEnricher.hoesMerk(List<int>.filled(99, 7)), '');
      expect(CoverEnricher.hoesMerk(null), '');
    });
  });
}
