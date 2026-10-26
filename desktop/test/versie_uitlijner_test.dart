// Uitlijnen (versies, 26-10-2026): waar in een vinylrip hetzelfde moment van de cd valt.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:debridmusic/fingerprint.dart';
import 'package:debridmusic/versie_uitlijner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Iets dat op muziek lijkt voor een kruiscorrelatie: een paar tonen die van toonhoogte veranderen, met een omhullende.
Float64List _muziek(int n, {int zaad = 1}) {
  final r = math.Random(zaad);
  final uit = Float64List(n);
  var f1 = 220.0, f2 = 331.0, fase1 = 0.0, fase2 = 0.0;
  for (var i = 0; i < n; i++) {
    if (i % 1200 == 0) {
      f1 = 150 + r.nextDouble() * 600;
      f2 = 300 + r.nextDouble() * 900;
    }
    fase1 += 2 * math.pi * f1 / kUitlijnHz;
    fase2 += 2 * math.pi * f2 / kUitlijnHz;
    final omhulling = 0.5 + 0.5 * math.sin(i / 900);
    uit[i] = 8000 * omhulling * (math.sin(fase1) + 0.6 * math.sin(fase2));
  }
  return uit;
}

void main() {
  test('DE KERN: de kruiscorrelatie vindt de verschuiving op het sample, ook met ruis erbij (vinyl)', () {
    final heel = _muziek(kUitlijnHz * 12);
    // Het anker: 8 s vanaf 1 s. De versie: 11 s vanaf 0,25 s, met ruis — hetzelfde moment staat daar 0,75 s + 37 ms later.
    final a = Float64List.sublistView(heel, kUitlijnHz, kUitlijnHz * 9);
    final r = math.Random(7);
    final b = Float64List.fromList([
      for (var i = kUitlijnHz ~/ 4; i < kUitlijnHz ~/ 4 + kUitlijnHz * 11 && i < heel.length; i++)
        heel[i] + (r.nextDouble() - .5) * 3000,
    ]);
    final k = kruiscorrelatie(a, b);
    expect(k.lag, kUitlijnHz - kUitlijnHz ~/ 4, reason: 'in b begint het anker 6000 samples later');
    expect(k.kwaliteit, greaterThan(0.8));
  });

  test('iets anders correleert niet: dan geen fijne meting', () {
    final a = _muziek(kUitlijnHz * 4, zaad: 1);
    final b = _muziek(kUitlijnHz * 6, zaad: 99);
    expect(kruiscorrelatie(a, b).kwaliteit, lessThan(kUitlijnDrempel + 0.15));
  });

  test('uit twee metingen: de verschuiving en de snelheid van de draaitafel', () {
    // Op 30 s ligt de versie 1,8 s later, op 200 s 2,14 s later: 0,2 % te traag.
    final u = uitTweeMetingen(30000, 1800, 200000, 2140);
    expect(u.snelheid, closeTo(1.002, 1e-6));
    expect(u.verschuivingMs, 1740);
    // Heen en terug: op 30 s in het anker is het 31,8 s in de versie.
    expect((u.verschuivingMs + 30000 * u.snelheid).round(), 31800);
    expect((u.verschuivingMs + 200000 * u.snelheid).round(), 202140);
    // Onzin (een snelheid van 10 %) is een meetfout: alleen de eerste meting.
    expect(uitTweeMetingen(30000, 1800, 60000, 4800), (verschuivingMs: 1800, snelheid: 1.0));
  });

  test('de vingerafdruk geeft de grove verschuiving erbij', () {
    final r = math.Random(3);
    final a = [for (var i = 0; i < 600; i++) r.nextInt(1 << 32)];
    final b = [for (var i = 0; i < 17; i++) r.nextInt(1 << 32), ...a];
    final p = bestePassing(a, b, maxOffset: 40);
    expect(p.verschuiving, 17, reason: 'b begint 17 items (≈2,1 s) later');
    expect(p.score, 1.0);
    expect(kVingerafdrukItemMs, closeTo(123.8, 0.1));
  });
}
