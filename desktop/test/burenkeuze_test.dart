/// Twee keer dezelfde radio mag niet twee keer dezelfde buren geven.
///
/// **De meting.** Saber op 12-09-2026: *"laat op variatie in music relevantie"*, bij een radio vanaf
/// Michael Jackson - Billie Jean die twee uur mocht lopen. Van de eerste zes nummers die klonken
/// waren er vier van Michael Jackson zelf. Dat komt niet door de volgorde maar door de oogst:
/// [RecommendService.mixRadio] bouwt zijn plan uit de vijftien eigen toppers, de "similar"-stroom
/// van Deezer, en de toppers van precies VIER buren — en dat waren altijd dezelfde vier, want het
/// verzoek vroeg er letterlijk vier op.
///
/// Diezelfde vondst staat al uitgeschreven bij [RecommendService.discover]: *"`related?limit=20`
/// kost exact hetzelfde ene verzoek"*. Twintig ophalen en er vier uit trekken kost dus niets, en
/// maakt een tweede radio rond dezelfde artiest pas werkelijk anders.
library;

import 'dart:math';

import 'package:debridmusic/recommend.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _buren(int n) => [for (var i = 0; i < n; i++) 'buur$i'];

void main() {
  test('DE KERN: uit twintig buren komen er vier', () {
    final gekozen = kiesBuren(_buren(20), 4, Random(1));

    expect(gekozen, hasLength(4));
    expect(gekozen.toSet(), hasLength(4), reason: 'dezelfde buur twee keer is een buur minder');
    expect(_buren(20), containsAll(gekozen));
  });

  test('DE VAL: een tweede radio rond dezelfde artiest krijgt andere buren', () {
    // Dit is de hele storing: wie twee keer radio zet op Michael Jackson kreeg twee keer dezelfde
    // vier namen, en dus twee keer dezelfde muziek naast de vijftien van hemzelf.
    final eerste = kiesBuren(_buren(20), 4, Random(1));
    final tweede = kiesBuren(_buren(20), 4, Random(2));

    expect(tweede, isNot(equals(eerste)));
  });

  test('DE GRENS: minder buren dan gevraagd geeft ze alle, zonder fout', () {
    final drie = _buren(3);

    expect(kiesBuren(drie, 4, Random(1)), equals(drie),
        reason: 'een artiest met weinig buren mag geen lege radio opleveren');
  });

  test('DE GRENS: de lijst van de aanroeper blijft zoals hij was', () {
    // De aanroeper leest `rel` hierna niet meer, maar een schudbeurt in zijn lijst is precies het
    // soort stille schade dat pas bij de volgende gebruiker opduikt.
    final bron = _buren(20);
    final voor = List<String>.from(bron);

    kiesBuren(bron, 4, Random(1));

    expect(bron, equals(voor));
  });
}
