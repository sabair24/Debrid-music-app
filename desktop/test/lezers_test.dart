// Saber, 24-10-2026: "dit nummer die ik net downloadde … nu kan ik het niet spelen". De hoesveger schreef in
// "Mademoiselle chante le blues" terwijl de Mac het las (stroom.log 15:15:50, hoes_in_bestand.log 15:15:58.965).
// Nu telt de pc wat toestellen lezen, en laten de hoesveger, de Soulseek-jacht en de TIDAL-ronde dat met rust.
import 'dart:io';

import 'package:debridmusic/lan/lezers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wie leest, en tot tien minuten erna, houdt het bestand in gebruik', () {
    var nu = DateTime(2026, 10, 24, 15, 15, 50);
    final l = Lezers(klok: () => nu);
    const pad = r'D:\Flac music 2024\Patricia Kaas\01 - Mademoiselle chante le blues.flac';
    expect(l.leest(pad), isFalse);
    l.begin(pad);
    expect(l.leest(pad), isTrue);
    expect(l.leest('d:/flac music 2024/patricia kaas/01 - mademoiselle chante le blues.FLAC'), isTrue,
        reason: 'Windows kent geen verschil in hoofdletters of strepen');
    nu = nu.add(const Duration(seconds: 8));
    l.einde(pad);
    expect(l.leest(pad), isTrue, reason: 'de Mac speelt het nog uit zijn buffer');
    nu = nu.add(kNaLezen - const Duration(seconds: 1));
    expect(l.leest(pad), isTrue);
    nu = nu.add(const Duration(seconds: 2));
    expect(l.leest(pad), isFalse);
    expect(l.inGebruik, isEmpty);
  });

  test('twee lezers tegelijk: na de eerste blijft het in gebruik', () {
    var nu = DateTime(2026, 10, 24, 15);
    final l = Lezers(klok: () => nu);
    l
      ..begin('a.flac')
      ..begin('a.flac')
      ..einde('a.flac');
    nu = nu.add(const Duration(hours: 1));
    expect(l.leest('a.flac'), isTrue, reason: 'de tweede leest nog');
    l.einde('a.flac');
    expect(l.leest('a.flac'), isTrue);
    nu = nu.add(kNaLezen);
    expect(l.leest('a.flac'), isFalse);
  });

  test('de lijst voor de TIDAL-ronde en de huidige nummers van de zones', () {
    final l = Lezers()..begin(r'C:\M\A.flac');
    expect(l.inGebruik, ['c:/m/a.flac']);
    expect(Lezers.eenVan(r'C:\M\B.flac', [r'c:\m\b.FLAC']), isTrue);
    expect(Lezers.eenVan(r'C:\M\B.flac', [r'c:\m\a.flac']), isFalse);
  });

  test('bedrading: elke stream telt, en de drie die bestanden aanraken vragen het na', () {
    final server = File('lib/lan/server.dart').readAsStringSync();
    final stream = server.substring(server.indexOf('  Future<void> _stream(HttpRequest req)'));
    expect(stream.indexOf('lezers.begin(track.path)'), greaterThan(0));
    expect(stream.indexOf('lezers.einde(track.path)'), greaterThan(stream.indexOf('lezers.begin(track.path)')));
    expect(stream.indexOf('finally'), lessThan(stream.indexOf('lezers.einde(track.path)')));
    final main = File('lib/main.dart').readAsStringSync();
    // Sinds 25-10-2026: niet als de speler het bestand net losliet om het te vervangen (Deze houden).
    expect(main, contains('bool ergensInGebruik(String p) =>\n'
        '        (player.current?.path == p && !player.losgelaten) || (sharing.server?.inGebruikBijToestel(p) ?? false);'));
    expect(main, contains('downloads.speeltNu = ergensInGebruik;'), reason: 'de Soulseek-jacht');
    expect(main, contains('speeltNu: ergensInGebruik);'), reason: 'de hoesveger');
    expect(main, contains('..speeltNu = ergensInGebruik;'), reason: 'de TIDAL-ronde op jouw vraag');
    expect(main, contains('...?sharing.server?.padenInGebruikBijToestel(),'), reason: 'de TIDAL-ronde');
  });
}
