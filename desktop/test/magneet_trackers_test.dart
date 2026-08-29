/// Een magneet die zijn zwerm ook echt kan vinden.
///
/// **Waarom dit bestaat.** Gemeld op 24-08-2026: "Knaben heeft soms heel veel peers maar wil niet
/// downloaden". De app bouwde uit een infohash een magneet met niets dan die hash erin. Zo'n magneet
/// heeft maar één manier om te ontdekken wíé die stukken heeft: DHT — traag om mee te beginnen, en
/// het eerste dat een provider dichtzet. De veertig peers op de site zijn dan echt, en toch komt er
/// niets binnen.
///
/// Trackers erbij is de reparatie, en dit is de toets die vastlegt dat de identiteit van de torrent
/// er niet door verandert: `xt` bepaalt wélke torrent het is, `tr` is niet meer dan een tip. Zou dat
/// verschuiven, dan herkent TorBox een cache-treffer niet meer.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/search.dart';

void main() {
  test('een kale magneet krijgt telefoonboeken mee', () {
    const kaal = 'magnet:?xt=urn:btih:73812ba4ac3bb331e8deff00689575cfe2193c73&dn=Iets';

    final uit = metTrackers(kaal);

    expect(uit, startsWith(kaal), reason: 'de identiteit blijft vooraan en ongewijzigd');
    for (final t in kOpenbareTrackers) {
      expect(uit, contains(Uri.encodeComponent(t)));
    }
  });

  test('wat de bron zelf al meegaf blijft staan, en de openbare komen ernaast', () {
    // Dit is de echte Knaben-magneet voor Robert Miles — Dreamland: één telefoonboek, dat van
    // RuTracker. Antwoordt die niet, dan is er niets meer over — dus mag "er staat al een tracker
    // in" nooit betekenen dat we er geen bij zetten.
    const eigen = 'magnet:?xt=urn:btih:09ddc131b738d254b9377eb8a905ba250e14e12e'
        '&tr=http%3A%2F%2Fbt4.t-ru.org%2Fann%3Fmagnet';

    final uit = metTrackers(eigen);

    expect(uit, startsWith(eigen), reason: 'de eigen tracker blijft ongemoeid vooraan');
    expect(uit, contains(Uri.encodeComponent(kOpenbareTrackers.first)));
  });

  test('en niets wordt dubbel toegevoegd', () {
    final eenmaal = metTrackers('magnet:?xt=urn:btih:abc');
    final tweemaal = metTrackers(eenmaal);

    expect(tweemaal, eenmaal);
  });

  test('een lege magneet blijft leeg', () {
    // Anders staat er "magnet:?tr=…" in een resultaat dat helemaal geen bron heeft.
    expect(metTrackers(''), '');
  });

  test('de infohash verandert niet', () {
    const hash = '73812ba4ac3bb331e8deff00689575cfe2193c73';
    final uit = metTrackers('magnet:?xt=urn:btih:$hash&dn=Iets');

    final gevonden = RegExp(r'btih:([0-9a-f]{40})').firstMatch(uit)?.group(1);
    expect(gevonden, hash, reason: 'TorBox herkent een torrent aan zijn hash, niet aan zijn hints');
  });
}
