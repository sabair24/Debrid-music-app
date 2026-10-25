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

  // Saber, 25-10-2026, Rockin': "studio behouden lukt niet opdat liedje nog speelt, maar dat is niet zo". Het toestel
  // dat vroeg, las het nummer zelf (stroom.log 21:12:50, 21:13:01, 21:13:34) en telde zo als lezer mee.
  test('DE KERN: wie vraagt, telt zelf niet mee; een ander toestel wel', () {
    var nu = DateTime(2026, 10, 25, 21, 13);
    final l = Lezers(klok: () => nu);
    const pad = r"D:\Flac music 2024\DebridMusic Downloads\Albums\The Weeknd\Starboy\05 - Rockin'.flac";
    l
      ..begin(pad, wie: '192.168.0.132')
      ..einde(pad, wie: '192.168.0.132');
    nu = nu.add(const Duration(seconds: 5));
    expect(l.leest(pad), isTrue, reason: 'voor de vegers en de TIDAL-ronde: in gebruik');
    expect(l.leest(pad, behalve: '192.168.0.132'), isFalse, reason: 'voor het toestel dat zelf om houden vraagt niet');
    l.begin(pad, wie: '192.168.0.216');
    expect(l.leest(pad, behalve: '192.168.0.132'), isTrue, reason: 'leest de Mac het intussen, dan wel');
    l.einde(pad, wie: '192.168.0.216');
    expect(l.leest(pad, behalve: '192.168.0.132'), isTrue, reason: 'en tot tien minuten erna');
    nu = nu.add(kNaLezen);
    expect(l.leest(pad, behalve: '192.168.0.132'), isFalse);
  });

  test('aangesloten: het adres van de lezer, en Deze houden laat het vragende toestel weg', () {
    final server = File('lib/lan/server.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(server, contains('    lezers.begin(track.path, wie: wie);\n'));
    expect(server, contains('      lezers.einde(track.path, wie: wie);\n'));
    expect(server, contains("          behalveLezer: req.connectionInfo?.remoteAddress.address, behalveZone: body['toestel'] as String?),"));
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains("final res = await c.ask('/api/twijfel', {'trackId': id, 'actie': actie, 'toestel': ik.id});"));
    expect(main, contains('    downloads.inGebruikVoorHouden = (p, {behalveLezer, behalveZone}) =>\n'));
    final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(online, contains('        inGebruikVoorHouden?.call(pad, behalveLezer: behalveLezer, behalveZone: behalveZone) ??\n'));
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
    expect(stream.indexOf('lezers.begin(track.path, wie: wie)'), greaterThan(0));
    expect(stream.indexOf('lezers.einde(track.path, wie: wie)'), greaterThan(stream.indexOf('lezers.begin(track.path, wie: wie)')));
    expect(stream.indexOf('finally'), lessThan(stream.indexOf('lezers.einde(track.path, wie: wie)')));
    final main = File('lib/main.dart').readAsStringSync();
    // Sinds 25-10-2026: niet als de speler het bestand net losliet om het te vervangen (Deze houden).
    expect(main, contains('bool ergensInGebruik(String p) =>\n'
        '        (player.current?.path == p && !player.losgelaten) || (sharing.server?.inGebruikBijToestel(p) ?? false);'));
    expect(main, contains('downloads.speeltNu = ergensInGebruik;'), reason: 'de Soulseek-jacht');
    expect(main, contains('speeltNu: ergensInGebruik);'), reason: 'de hoesveger');
    expect(main, contains('..speeltNu = ergensInGebruik;'), reason: 'de TIDAL-ronde op jouw vraag');
    expect(main, contains('...?sharing.server?.padenInGebruikBijToestel(),'), reason: 'de TIDAL-ronde');
  });

  // Saber, 25-10-2026, Rockin': "ik wil hier de studio houden maar lukt niet ???". De pc stond zelf in de zones, met het
  // nummer dat hij speelde: losgelaten of niet, het bleef "in gebruik bij een toestel".
  test('de zones zonder de pc zelf: die kent zijn eigen speler, en die laat los voor Deze houden', () {
    final server = File('lib/lan/server.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(server,
        contains("          if (z.id != 'dev:\${zones.pcId}' && (behalve == null || z.id != 'dev:\$behalve') && z.trackId.isNotEmpty)\n"));
    final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(online, contains('houden gaat nu niet — het bestand is in gebruik'), reason: 'en anders staat het in het logboek');
  });
}
