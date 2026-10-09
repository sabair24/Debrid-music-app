/// Een weggevallen verbinding met de Soulseek-server laat een spoor na (09-10-2026).
///
/// Om 06:50:41 viel de verbinding weg, anderhalve minuut na een geslaagde login en midden in acht
/// radiodownloads. Daarna gaf de server 22 minuten lang geen antwoord op precies hetzelfde loginbericht.
/// Wáárom de verbinding wegviel stond nergens: een verlies na de eerste minuut werd stil opgeruimd.
/// Daardoor viel niet te zeggen of het Soulseek zelf was, of Soulseek dat op onze zoekopdrachten
/// reageerde. En de melding waarmee Soulseek zelf zegt dat je account elders ingelogd werd (code 41,
/// "Relogged"), werd genegeerd.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_slskweg_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('de regel in het logboek', () {
    test('DE KERN: hoe lang, wie, wat de server als laatste zei, en hoeveel wij zochten', () {
      final r = verbindingWegRegel(
        open: const Duration(seconds: 92),
        hoe: 'door de server gesloten',
        codes: const [(Duration(seconds: 3), 18), (Duration(milliseconds: 200), 3)],
        zoekMinuut: 12,
        zoekVijf: 19,
      );
      expect(r, 'verbinding met de server weg na 1m32s (door de server gesloten)'
          ' — laatste servercodes: 18@-3s, 3@-0s'
          ' — zoekopdrachten: 12 in de laatste minuut, 19 in 5 min');
    });

    test('Relogged staat er met zoveel woorden bij', () {
      final r = verbindingWegRegel(
        open: const Duration(minutes: 5),
        hoe: 'door de server gesloten',
        codes: const [(Duration(milliseconds: 5), 41)],
        zoekMinuut: 0,
        zoekVijf: 2,
        relogged: true,
      );
      expect(r, contains('na 5m0s'));
      expect(r, contains('elders ingelogd (Relogged)'));
      expect(r, contains('41@-0s'));
    });

    test('zonder bekende inlogtijd en zonder codes: geen gat in de zin', () {
      final r = verbindingWegRegel(hoe: 'fout: SocketException', codes: const [], zoekMinuut: 0, zoekVijf: 0);
      expect(r, 'verbinding met de server weg (fout: SocketException) — laatste servercodes: geen'
          ' — zoekopdrachten: 0 in de laatste minuut, 0 in 5 min');
    });
  });

  group('Relogged is een kick, ook na de eerste minuut', () {
    test('DE KERN: zegt de server het zelf, dan wacht de app in plaats van terug te vechten', () {
      final c = SoulseekClient();
      // Geen login van net: zonder de melding van de server is dit geen kick (zie login_budget_test).
      c.noteConnectionLost();
      expect(c.blocked, isFalse);
      c.noteConnectionLost(relogged: true);
      expect(c.blocked, isTrue);
      expect(c.pause, SlskPause.kicked);
      final wacht = c.blockedFor;
      expect(wacht, isNotNull);
      expect(wacht!.inMinutes, greaterThanOrEqualTo(4));
    });
  });

  group('de bedrading', () {
    final bron = File('lib/soulseek.dart').readAsStringSync();

    test('code 41 wordt herkend en elke code onthouden', () {
      // Met de regel erna: `if (code == 41)` staat ook bij de peer-berichten (TransferResponse), en dat
      // is een ander protocol met toevallig hetzelfde nummer.
      expect(bron.contains('        if (code == 41) {\n          // Relogged'), isTrue, reason: 'Relogged herkennen');
      expect(bron.contains('          _relogged = true;'), isTrue);
      expect(bron.contains('        _servercodes.add((DateTime.now(), code));'), isTrue);
    });

    test('een weggevallen verbinding gaat via _lost met wie hem sloot, en telt Relogged mee', () {
      expect(
          bron.contains("onError: (Object e) => _lost('fout: \$e'), onDone: () => _lost('door de server gesloten'));"),
          isTrue);
      expect(bron.contains('      client.noteConnectionLost(relogged: _relogged);'), isTrue);
      expect(bron.contains('      client.logboek(verbindingWegRegel('), isTrue);
    });

    test('elke zoekopdracht telt, en de inlogtijd wordt gezet', () {
      expect(bron.contains('        _zoektijden\n          ..add(nu)'), isTrue);
      expect(bron.contains('      _ingelogdOp = DateTime.now();\n      _conn = c;'), isTrue);
    });
  });
}
