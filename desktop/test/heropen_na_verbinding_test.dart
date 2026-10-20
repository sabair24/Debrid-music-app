// Shield, 19-10-2026: na het slapen startte de app opnieuw terwijl de wifi er nog niet was (twintig
// minuten "geen winnaar" in verbinding.log). Het herstelde nummer ging niet open, en "Kan dit nummer
// niet openen — tcp://127.0.0.1:33851 … timed out" bleef staan, ook toen de pc allang weer antwoordde.
// Oorzaak: restore() zette de positie op 0:35 ook als het openen mislukte, en _naOpenfout doet bewust
// niets met een nummer dat een positie heeft.
import 'dart:io';

import 'package:debridmusic/vooruithalen.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('DE KERN: een nummer dat nooit openging en niet speelt, gaat opnieuw open als de pc terug is', () {
    expect(heropenNaVerbinding(radio: false, nietGeopend: true, speelt: false), isTrue);
  });

  test('niet als het al open is, als het speelt, of in de radio (die heeft een eigen wachtstand)', () {
    expect(heropenNaVerbinding(radio: false, nietGeopend: false, speelt: false), isFalse);
    expect(heropenNaVerbinding(radio: false, nietGeopend: true, speelt: true), isFalse);
    expect(heropenNaVerbinding(radio: true, nietGeopend: true, speelt: false), isFalse);
  });

  group('aangesloten', () {
    final speler = _bron('lib/player.dart');

    test('een fout zonder duur onthoudt het nummer; een duur wist het weer', () {
      final fout = speler.indexOf('void _verwerkFout(String e) {');
      expect(fout, greaterThan(0));
      expect(speler.substring(fout, fout + 800), contains('if (duration <= Duration.zero) _nietGeopend = current?.path;'));
      expect(speler, contains('      if (d > Duration.zero) _nietGeopend = null;\n'));
    });

    test('pcWeerBereikbaar opent hem opnieuw, gepauzeerd en op dezelfde plek', () {
      final p = speler.indexOf('  void pcWeerBereikbaar() {');
      expect(speler.substring(p, p + 400),
          contains('if (heropenNaVerbinding(radio: radioMode, nietGeopend: _nietGeopend == t.path, speelt: playing)) {\n'
              '      unawaited(_heropenGepauzeerd());'));
      final h = speler.indexOf('Future<void> _heropenGepauzeerd() async {');
      expect(h, greaterThan(0));
      final lijf = speler.substring(h, speler.indexOf('\n  }\n', h));
      expect(lijf, contains('await _player.open(Media(bron), play: false);'),
          reason: 'een tv die na het wakker worden uit zichzelf begint te spelen is erger dan de melding');
      expect(lijf, contains('_meldStilstand(null);'));
      expect(lijf, contains('await _player.seek(plek);'));
    });

    test('en main.dart roept hem aan bij elke session.ready', () {
      expect(_bron('lib/main.dart'), contains('          player.pcWeerBereikbaar();\n'));
    });
  });
}
