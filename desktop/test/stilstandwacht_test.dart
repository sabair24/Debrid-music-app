/// Wanneer "speelt" niet betekent dat er iets speelt.
///
/// Het geval dat dit veroorzaakte, gemeten op 12-08-2026: de pc stond uit, de telefoon streamt
/// daarvandaan, en de mediasessie meldde achttien seconden lang `state=PLAYING(3), position=0` —
/// zonder één audiostroom en zonder één foutmelding.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/player.dart';

final t0 = DateTime(2026, 8, 12, 18, 13);
Duration s(int n) => Duration(seconds: n);

void main() {
  test('een teller die loopt is nooit een klacht', () {
    final w = Stilstandwacht(geduld: s(10));
    for (var i = 0; i < 30; i++) {
      expect(w.voeden(speelt: true, positie: s(i), nu: t0.add(s(i))), isFalse);
    }
  });

  test('een teller die stilstaat wordt er na het geduld één', () {
    final w = Stilstandwacht(geduld: s(10));
    expect(w.voeden(speelt: true, positie: Duration.zero, nu: t0), isFalse);
    expect(w.voeden(speelt: true, positie: Duration.zero, nu: t0.add(s(9))), isFalse,
        reason: 'bufferen over het netwerk mag even duren');
    expect(w.voeden(speelt: true, positie: Duration.zero, nu: t0.add(s(10))), isTrue);
  });

  test('midden in een nummer telt net zo goed', () {
    // Niet alleen bij het openen: een pc die halverwege verdwijnt geeft precies hetzelfde beeld.
    final w = Stilstandwacht(geduld: s(10));
    expect(w.voeden(speelt: true, positie: s(94), nu: t0), isFalse);
    expect(w.voeden(speelt: true, positie: s(94), nu: t0.add(s(11))), isTrue);
  });

  test('pauze is geen stilstand', () {
    // Anders krijgt iedereen die zelf op pauze drukt tien seconden later een klacht te zien.
    final w = Stilstandwacht(geduld: s(10));
    for (var i = 0; i < 30; i++) {
      expect(w.voeden(speelt: false, positie: s(42), nu: t0.add(s(i))), isFalse);
    }
  });

  test('na pauze begint het geduld opnieuw', () {
    final w = Stilstandwacht(geduld: s(10));
    w.voeden(speelt: true, positie: s(5), nu: t0);
    w.voeden(speelt: false, positie: s(5), nu: t0.add(s(1)));
    // Zonder de reset in voeden() zou dit meteen waar zijn: dezelfde positie, en het beginmoment
    // van vóór de pauze.
    expect(w.voeden(speelt: true, positie: s(5), nu: t0.add(s(60))), isFalse);
    expect(w.voeden(speelt: true, positie: s(5), nu: t0.add(s(70))), isTrue);
  });

  test('zodra het weer loopt is de klacht voorbij', () {
    final w = Stilstandwacht(geduld: s(10));
    w.voeden(speelt: true, positie: Duration.zero, nu: t0);
    expect(w.voeden(speelt: true, positie: Duration.zero, nu: t0.add(s(12))), isTrue);
    expect(w.voeden(speelt: true, positie: s(1), nu: t0.add(s(13))), isFalse);
  });

  test('reset laat het geduld opnieuw beginnen', () {
    // Wordt aangeroepen als er een ander nummer geopend wordt.
    final w = Stilstandwacht(geduld: s(10));
    w.voeden(speelt: true, positie: Duration.zero, nu: t0);
    w.reset();
    expect(w.voeden(speelt: true, positie: Duration.zero, nu: t0.add(s(12))), isFalse);
    expect(w.voeden(speelt: true, positie: Duration.zero, nu: t0.add(s(23))), isTrue);
  });
}
