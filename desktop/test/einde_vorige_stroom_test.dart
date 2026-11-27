/// Een decodeerfout vlak na het einde van een nummer hoort bij de stroom die net afliep.
///
/// 27-11-2026, speler.log van de Shield: `OPENEN MISLUKT — Red Alert — Error decoding audio.` 3 ms na het einde van
/// Sing Hallelujah (`WACHT OP DE STROOM … buffer nog 0`), en 210 ms vóór Red Alert zelf geopend werd. Zo ook IDGAF,
/// Sign Of The Times, Cheap Thrills en Sing Hallelujah. De app gaf het nieuwe nummer de schuld, toonde "Kan dit nummer
/// niet openen" en liet de pc het gave bestand nakijken.
library;

import 'dart:io';

import 'package:debridmusic/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('foutVanVorigeStroom', () {
    test('een decodeerfout binnen 1,5 s na het einde: van de vorige stroom', () {
      expect(foutVanVorigeStroom(fout: 'Error decoding audio.', msSindsEinde: 3), isTrue);
      expect(foutVanVorigeStroom(fout: 'Error decoding audio.', msSindsEinde: 0), isTrue);
      expect(foutVanVorigeStroom(fout: 'Error decoding audio.', msSindsEinde: 1500), isTrue);
    });

    test('later, of zonder einde: van het nummer dat nu speelt', () {
      expect(foutVanVorigeStroom(fout: 'Error decoding audio.', msSindsEinde: 1501), isFalse);
      expect(foutVanVorigeStroom(fout: 'Error decoding audio.', msSindsEinde: 60000), isFalse);
      expect(foutVanVorigeStroom(fout: 'Error decoding audio.', msSindsEinde: null), isFalse);
      expect(foutVanVorigeStroom(fout: 'Error decoding audio.', msSindsEinde: -5), isFalse,
          reason: 'een klok die terugspringt is geen einde');
    });

    test('een fout bij het openen is altijd van nu, ook vlak na een einde', () {
      expect(foutVanVorigeStroom(fout: 'Failed to open http://pc/stream/abc.flac?token=…', msSindsEinde: 3), isFalse);
      expect(foutVanVorigeStroom(fout: 'tcp: Connection timed out', msSindsEinde: 3), isFalse);
      expect(foutVanVorigeStroom(fout: 'Failed to recognize file format.', msSindsEinde: 3), isFalse);
    });
  });

  test('de speler kijkt het na vóór hij een fout afhandelt, en onthoudt elk einde', () {
    final p = File('lib/player.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final luister = p.indexOf('_player.stream.error.listen((e) {');
    expect(luister, greaterThan(0));
    final staart = p.indexOf('if (_staartVanVorige(e)) return;', luister);
    final breuk = p.indexOf('if (_breukInGroeistroom(e)) return;', luister);
    final verwerk = p.indexOf('_verwerkFout(e);', luister);
    expect(staart, greaterThan(luister));
    expect(staart, lessThan(breuk), reason: 'eerst de vorige stroom, dan de rest');
    expect(staart, lessThan(verwerk));
    final f = p.indexOf('bool _staartVanVorige(String e) {');
    final lijf = p.substring(f, p.indexOf('\n  }\n', f));
    expect(lijf, contains('foutVanVorigeStroom(fout: e, msSindsEinde: DateTime.now().difference(einde.op).inMilliseconds)'));
    expect(lijf, contains("_log?.line('EINDE VAN DE VORIGE STROOM"));
    expect(lijf, contains('return true;'), reason: 'opgeschreven en dan niets meer mee doen');
    expect(lijf, contains('return false;'));
    final einde = p.indexOf('void _onCompleted() {');
    expect(p.substring(einde, einde + 200), contains('_eindeVorige = (op: DateTime.now()'));
  });
}
