/// De buurt van een radio: wat het model mag voorstellen, en wat daarvan geloofd wordt.
///
/// **Waarom dit bestaat.** Saber op 12-09-2026, na een radio van twee uur: *"ik wil de maximum
/// variatie, dat ik ook nieuwe maar ook bekende liedjes kan ontdekken (...) het moet beter"* dan
/// Deezer en Tidal. Het getal waar dat op stukloopt is nagemeten: Deezers `related` geeft per
/// artiest precies TWINTIG namen en nooit meer, hoe je het ook vraagt (`limit=4`, `20`, `50`, `100`
/// → `total` is elke keer 20).
///
/// **Waarom er een toets op de LEZER staat en niet op het model.** De Messages-API weigert
/// `minItems`/`maxItems` in een schema. Er is dus geen enkele grens aan wat er terug kan komen
/// behalve [leesBuurt]. Zegt het model driehonderd namen, dan staat deze functie tussen die
/// vergissing en zeshonderd Deezer-verzoeken.
library;

import 'package:debridmusic/aanbevelingplan.dart';
import 'package:debridmusic/radiobuurt.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _buur(String naam, {bool bekend = false, String reden = 'omdat'}) =>
    {'artiest': naam, 'bekend': bekend, 'reden': reden};

void main() {
  test('DE KERN: namen komen eruit zoals ze erin gingen, met hun merk', () {
    final uit = leesBuurt({
      'buren': [
        _buur('Quincy Jones', bekend: true, reden: 'produceerde Thriller'),
        _buur('The SOS Band', reden: 'zelfde post-disco lijn'),
      ]
    });

    expect(uit, hasLength(2));
    expect(uit.first.artiest, 'Quincy Jones');
    expect(uit.first.bekend, isTrue);
    expect(uit.first.reden, 'produceerde Thriller');
    expect(uit.last.bekend, isFalse);
  });

  test('DE VAL: driehonderd namen worden er vierentwintig', () {
    // Dit is de storing waar deze functie voor bestaat: elke naam kost twee Deezer-verzoeken.
    final uit = leesBuurt({
      'buren': [for (var i = 0; i < 300; i++) _buur('artiest $i')]
    });

    expect(uit, hasLength(kMaxBuren));
  });

  test('DE VAL: de zaadartiest zelf valt weg', () {
    // De radio speelt hem toch al; hem als buur opvoeren kost een verzoek en levert meer van
    // hetzelfde - precies waar de klacht over ging.
    final uit = leesBuurt({
      'buren': [_buur('Michael Jackson'), _buur('michael jackson'), _buur('Rick James')]
    }, zaadArtiest: 'Michael Jackson');

    expect([for (final b in uit) b.artiest], ['Rick James']);
  });

  test('DE GRENS: dubbels, lege namen en onzin vallen weg', () {
    final uit = leesBuurt({
      'buren': [
        _buur('Rick James'),
        _buur('RICK JAMES'),
        _buur('   '),
        'geen object',
        {'bekend': true},
        _buur('x' * 200),
      ]
    });

    expect([for (final b in uit) b.artiest], ['Rick James']);
  });

  test('DE GRENS: een antwoord dat nergens op slaat geeft een lege lijst', () {
    expect(leesBuurt(null), isEmpty);
    expect(leesBuurt('een zin'), isEmpty);
    expect(leesBuurt({'buren': 'geen lijst'}), isEmpty);
  });

  test('DE KERN: de vraag noemt het nummer, zijn kast en wat Deezer al had', () {
    final vraag = buurtPrompt(
      artiest: 'Michael Jackson',
      titel: 'Billie Jean',
      profiel: const SmaakProfiel(
        topArtiesten: ['Michael Jackson (71)', 'Madonna (30)'],
        perDecennium: {1980: 300, 1990: 448},
        gespeeld: ['Scatman John'],
        genres: ['Funk / Soul'],
      ),
      deezerBuren: const ['Stevie Wonder', 'Diana Ross'],
    );

    expect(vraag, contains('Michael Jackson - Billie Jean'),
        reason: 'het nummer is de zaadwaarde, niet alleen de artiest');
    expect(vraag, contains('Madonna (30)'), reason: 'zonder zijn kast is het een algemene lijst');
    expect(vraag, contains('1990s (448)'));
    expect(vraag, contains('Stevie Wonder'), reason: 'wat Deezer al gaf hoeft niet herhaald');
    expect(vraag, contains('Noem ze niet opnieuw'));
    expect(vraag, contains('Geen liedjestitels'),
        reason: 'een model dat tracktitels verzint stuurt de radio een half uur naar niets');
  });
}
