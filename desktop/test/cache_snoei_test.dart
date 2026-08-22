/// De snoei mag nooit een half mapje achterlaten.
///
/// **Waarom deze toets bestaat.** `releaseart` bewaart per album een mapje met `front`, `back`,
/// `disc` en een merkteken `done`. Dat merkteken is 1 byte en wordt als LAATSTE geschreven, dus het
/// heeft altijd de nieuwste tijd van het hele mapje.
///
/// De snoei sorteerde nieuwste eerst en gooide **per bestand** weg tot de begroting gehaald was. Op
/// zo'n mapje betekent dat gegarandeerd: `done` blijft staan (nieuwste, 1 byte) en `disc.jpg` van
/// een paar honderd kilobyte gaat als eerste. Wat overblijft is een mapje dat zegt "hier is alles al
/// opgehaald", zonder cd erin.
///
/// En `releaseArt` kijkt naar precies dat merkteken en slaat dan de hele zoektocht over. Er is geen
/// vervaltijd en niets dat zo'n map ooit ongeldig verklaart, dus één snoeibeurt en de cd van dat
/// album is **voorgoed** weg. Dat is de klacht "de cd is er niet altijd terwijl ik die wel heb
/// aangeduid", en hij is van de schijf te lezen zonder toestel en zonder netwerk.
library;

import 'dart:io';

import 'package:debridmusic/cache_snoei.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory wortel;

  setUp(() => wortel = Directory.systemTemp.createTempSync('snoei'));
  tearDown(() {
    if (wortel.existsSync()) wortel.deleteSync(recursive: true);
  });

  /// Een albummapje zoals `releaseart` het schrijft: dikke scans, en het merkteken als laatste.
  Directory album(String naam, {required int hoesKb, int? cdKb, bool merk = true}) {
    final d = Directory('${wortel.path}${Platform.pathSeparator}$naam')..createSync(recursive: true);
    File('${d.path}${Platform.pathSeparator}front').writeAsBytesSync(List.filled(hoesKb * 1024, 7));
    if (cdKb != null) {
      File('${d.path}${Platform.pathSeparator}disc').writeAsBytesSync(List.filled(cdKb * 1024, 9));
    }
    // Het merkteken krijgt met opzet de NIEUWSTE tijd, want zo schrijft de app hem ook: als laatste.
    if (merk) {
      final f = File('${d.path}${Platform.pathSeparator}done')..writeAsStringSync('1');
      f.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 30)));
    }
    return d;
  }

  bool bestaat(Directory d, String naam) =>
      File('${d.path}${Platform.pathSeparator}$naam').existsSync();

  group('per map', () {
    test('een mapje gaat helemaal weg of helemaal niet — nooit half', () async {
      // Drie albums van elk ~300 kB, en een begroting waar er maar één in past.
      final oud = album('oud', hoesKb: 150, cdKb: 150);
      final midden = album('midden', hoesKb: 150, cdKb: 150);
      final nieuw = album('nieuw', hoesKb: 150, cdKb: 150);
      // Ouderdom uit elkaar trekken; de nieuwste hoort te blijven.
      for (final (d, dagen) in [(oud, 30), (midden, 10)]) {
        for (final f in d.listSync().whereType<File>()) {
          f.setLastModifiedSync(DateTime.now().subtract(Duration(days: dagen)));
        }
      }

      await snoeiMap(wortel, maxBytes: 400 * 1024, perMap: true);

      for (final d in [oud, midden, nieuw]) {
        if (!d.existsSync()) continue;
        // DIT is de bewering. Een mapje dat er nog is, is nog compleet: het merkteken staat er
        // alleen als de cd er ook nog staat.
        expect(bestaat(d, 'done') && !bestaat(d, 'disc'), isFalse,
            reason: '${d.path} beweert compleet te zijn maar heeft geen cd meer');
      }
      expect(nieuw.existsSync(), isTrue, reason: 'de nieuwste hoort te blijven');
      expect(oud.existsSync(), isFalse, reason: 'de oudste hoort te gaan');
    });

    test('past alles binnen de begroting, dan blijft alles staan', () async {
      final a = album('a', hoesKb: 10, cdKb: 10);
      await snoeiMap(wortel, maxBytes: 10 * 1024 * 1024, perMap: true);
      expect(a.existsSync(), isTrue);
      expect(bestaat(a, 'disc'), isTrue);
    });

    test('een lege wortel doet niets en klapt niet', () async {
      expect(await snoeiMap(Directory('${wortel.path}/bestaatniet'), maxBytes: 1, perMap: true), 0);
    });
  });

  group('per bestand — ongewijzigd voor caches zonder onderling verband', () {
    test('losse bestanden worden nog steeds los gesnoeid', () async {
      for (final (naam, dagen) in [('a', 30), ('b', 20), ('c', 0)]) {
        final f = File('${wortel.path}${Platform.pathSeparator}$naam')
          ..writeAsBytesSync(List.filled(150 * 1024, 1));
        f.setLastModifiedSync(DateTime.now().subtract(Duration(days: dagen)));
      }
      await snoeiMap(wortel, maxBytes: 200 * 1024);
      expect(File('${wortel.path}${Platform.pathSeparator}c').existsSync(), isTrue);
      expect(File('${wortel.path}${Platform.pathSeparator}a').existsSync(), isFalse);
    });
  });

  test('de lijst zegt welke caches per map horen te gaan', () {
    // Een nieuwe cache met een mapstructuur die hier niet in staat, krijgt stilletjes de oude
    // behandeling terug — en dat is precies hoe deze bug ontstond.
    expect(cachePerMap, contains('releaseart'));
    expect(cachePerMap, contains('booklets'));
    expect(cachePerMap, isNot(contains('cast_cache')));
    for (final naam in cachePerMap) {
      expect(cacheGrenzen.keys, contains(naam), reason: '$naam heeft geen grens en wordt dus nooit gesnoeid');
    }
  });
}
