/// De klok van een volger verspringt niet mee met zijn wandklok.
///
/// Live 28-11-2026 17:11:29, de Shield in een groep met de KEF: de tijdserver zette de wandklok van de Shield 6,1 s
/// vooruit (logcat: "Time changed by +6s125ms"). De volger rekende de pc-tijd uit met `DateTime.now()`, dacht 6,1 s achter
/// te lopen en sprong vooruit (−6099 ms) — 39 s later, bij de volgende ijking, weer terug: 6 s overgeslagen, 6 s dubbel.
library;

import 'dart:io';

import 'package:debridmusic/samen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // De pc loopt 5 s voor op de gestage klok van dit toestel; een rondgang kost niets.
  late int gestaag, wand, vragen;
  const pcVoor = 5000000;
  KlokIjk klok() => KlokIjk(
      vraag: () async {
        vragen++;
        return gestaag + pcVoor;
      },
      hierUs: () => gestaag,
      wandUs: () => wand);

  setUp(() {
    gestaag = 1000000000;
    wand = 1000000000 + 300000; // de wandklok staat er wat naast
    vragen = 0;
  });

  test('DE KERN: de wandklok springt 6,1 s vooruit — de pc-tijd loopt gewoon door', () async {
    final k = klok();
    await k.ijk();
    final voor = k.nuPcMs();
    expect(voor, (gestaag + pcVoor) ~/ 1000);
    // Een halve seconde later zet de tijdserver de wandklok 6125 ms vooruit.
    gestaag += 500000;
    wand += 500000 + 6125000;
    expect(k.nuPcMs() - voor, 500, reason: 'niet 6625: alleen de gestage klok telt');
  });

  test('een sprong laat meteen opnieuw meten, ook binnen de minuut — en zegt het één keer', () async {
    final k = klok();
    await k.ijk();
    expect(vragen, 7);
    gestaag += 1000000;
    wand += 1000000;
    await k.ijk();
    expect(vragen, 7, reason: 'binnen de minuut, geen sprong: niet opnieuw');
    expect(k.sprongGezien(), isNull);
    gestaag += 1000000;
    wand += 1000000 + 6125000;
    await k.ijk();
    expect(vragen, 14, reason: 'de wandklok versprong: opnieuw meten');
    expect(k.sprongGezien(), 6125000);
    expect(k.sprongGezien(), isNull, reason: 'één keer');
    // Daarna is dat de nieuwe stand: niet bij elke vraag opnieuw.
    gestaag += 1000000;
    wand += 1000000;
    await k.ijk();
    expect(vragen, 14);
  });

  test('na een slaap (de gestage klok stond stil, de pc liep door) klopt het na de volgende ijking', () async {
    var pcUs = gestaag + pcVoor;
    final k = KlokIjk(
        vraag: () async => pcUs,
        hierUs: () => gestaag,
        wandUs: () => wand);
    await k.ijk();
    // Twee uur slapen: de wandklok en de pc gaan door, de gestage klok niet.
    wand += 7200000000;
    pcUs += 7200000000;
    gestaag += 1000;
    await k.ijk();
    expect(k.nuPcMs(), pcUs ~/ 1000);
    expect(k.sprongGezien(), closeTo(7200000000, 2000));
  });

  test('kleine verschuivingen (bijsturen door de tijdserver) laten de minuut staan', () async {
    final k = klok();
    await k.ijk();
    gestaag += 30000000;
    wand += 30000000 + 150000; // 150 ms in 30 s: onder de grens
    await k.ijk();
    expect(vragen, 7);
    expect(kKlokSprongUs, 200000);
  });

  test('op de pc (zonder vraag) blijft de wandklok de maat: de ankers dragen die tijd', () {
    final k = KlokIjk(wandUs: () => wand);
    expect(k.nuPcMs(), wand ~/ 1000);
    final b = File('lib/samen.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(b, contains('        _hierUs = hierUs ?? (vraag == null ? (wandUs ?? _wandNu) : gestaagUs);'));
    // De volger zegt het in samen.log.
    expect(b, contains("de klok van dit toestel versprong"));
    // En de tijd van de volger zelf (rust, begin, wissel) loopt ook op de gestage klok.
    expect(b, contains('  }) : _nuMs = nuMs ?? (() => KlokIjk.gestaagUs() ~/ 1000);'));
  });
}
