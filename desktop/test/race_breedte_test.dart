// Hoe breed de race van het gewone downloaden (⬇) begint — online.dart, `raceBreedte`.
//
// Gemeten op de pc (20-10-2026): "Tell Him" met ⬇ — zes kanalen, elk wachtend tot zijn uploader
// antwoordde of opgaf: 56 s. Met ▶ (dertig meteen samen) werden populaire nummers 4 à 8 s. Saber: "dat zou
// het gewone downloaden drastisch versnellen".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/online.dart';

void main() {
  test('één nummer: alle kandidaten meteen, tot de grens van twintig', () {
    expect(DownloadManager.raceBreedte(actief: 1, cap: 20), 20);
    expect(DownloadManager.raceBreedte(actief: 0, cap: 20), 20, reason: 'nog niet geteld telt als één');
    expect(DownloadManager.raceBreedte(actief: 1, cap: 8), 8, reason: 'lossy: acht in totaal');
  });

  test('meer nummers tegelijk: het budget van dertig verdeeld, nooit minder dan zes', () {
    expect(DownloadManager.raceBreedte(actief: 2, cap: 20), 15);
    expect(DownloadManager.raceBreedte(actief: 3, cap: 20), 10);
    expect(DownloadManager.raceBreedte(actief: 5, cap: 20), 6);
    expect(DownloadManager.raceBreedte(actief: 12, cap: 20), 6,
        reason: 'een album van twaalf: zoals voorheen, geen honderden verbindingen in één tel');
  });

  test('aangesloten: de race begint met die breedte', () {
    final online = File('lib/online.dart').readAsStringSync();
    expect(online, contains('static const kRaceBudget = 30;'));
    expect(online, contains('final feeders = List.generate(raceBreedte(actief: _slskActive, cap: n), (_) => feeder());'));
    expect(online, isNot(contains('List.generate(_probeWidth, (_) => feeder())')));
  });
}
