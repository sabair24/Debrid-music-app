/// Drie opruimers, en vooral: waar ze moeten STOPPEN.
///
/// Alle drie gooien iets weg dat de gebruiker niet zelf terugzet, dus de toetsen hier gaan minder over
/// "ruimt hij op" dan over "houdt hij zijn handen thuis als hij het niet zeker weet". Dat is dezelfde
/// val als bij `corrections.json`, dat ooit leeggelopen is omdat een niet-aangekoppelde schijf gelezen
/// werd als "die bestanden zijn weg".
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/cache_snoei.dart';

void main() {
  late Directory krab;

  setUp(() => krab = Directory.systemTemp.createTempSync('dm_opruim_'));
  tearDown(() {
    try {
      krab.deleteSync(recursive: true);
    } catch (_) {}
  });

  File maak(String naam, int bytes, {DateTime? tijd}) {
    final f = File('${krab.path}${Platform.pathSeparator}$naam')
      ..writeAsBytesSync(List<int>.filled(bytes, 0));
    if (tijd != null) f.setLastModifiedSync(tijd);
    return f;
  }

  group('de feiten van albums die er niet meer zijn', () {
    AlbumFactsStore winkel() => AlbumFactsStore(dir: () => krab.path);

    test('een lege verzameling gooit NIETS weg', () {
      // De belangrijkste van alle drie. Leeg betekent "ik weet het niet" — de schijf hing er niet, de
      // scan mislukte — en dan is alles weggooien het ergst denkbare antwoord.
      final w = winkel();
      w.put(const AlbumFacts(uid: 'uid-a', trackSetHash: 'h'));
      expect(w.prune({}), 0);
      expect(w.get('uid-a'), isNotNull);
    });

    test('wat nergens meer bij hoort gaat weg, de rest blijft staan', () {
      final w = winkel();
      w.put(const AlbumFacts(uid: 'blijft', trackSetHash: 'h'));
      w.put(const AlbumFacts(uid: 'wees', trackSetHash: 'h'));
      expect(w.prune({'blijft'}), 1);
      expect(w.get('blijft'), isNotNull);
      expect(w.get('wees'), isNull);
    });

    test('twee keer opruimen doet de tweede keer niets', () {
      final w = winkel();
      w.put(const AlbumFacts(uid: 'blijft', trackSetHash: 'h'));
      w.put(const AlbumFacts(uid: 'wees', trackSetHash: 'h'));
      expect(w.prune({'blijft'}), 1);
      expect(w.prune({'blijft'}), 0, reason: 'anders schrijft elke scan het bestand voor niets');
    });
  });

  group('een cachemap binnen zijn grens houden', () {
    test('onder de grens blijft alles staan', () async {
      maak('a', 1000);
      maak('b', 1000);
      expect(await snoeiMap(krab, maxBytes: 10000), 0);
      expect(krab.listSync().length, 2);
    });

    test('boven de grens gaat de OUDSTE eruit, niet de grootste', () async {
      // Nieuwste blijft: wat je vandaag bekijkt is wat morgen weer gevraagd wordt. Op grootte
      // opruimen zou juist de hoes van je meest bekeken album pakken.
      final nu = DateTime.now();
      maak('oud', 1000, tijd: nu.subtract(const Duration(days: 30)));
      maak('midden', 1000, tijd: nu.subtract(const Duration(days: 10)));
      maak('nieuw', 1000, tijd: nu);

      final bevrijd = await snoeiMap(krab, maxBytes: 2000);
      expect(bevrijd, 1000);
      final over = [for (final f in krab.listSync()) f.path.split(Platform.pathSeparator).last]..sort();
      expect(over, ['midden', 'nieuw']);
    });

    test('een map die niet bestaat is geen fout', () async {
      final weg = Directory('${krab.path}${Platform.pathSeparator}bestaat-niet');
      expect(await snoeiMap(weg, maxBytes: 100), 0);
    });

    test('de grenzen zijn echte getallen en geen nul', () {
      // Een grens van 0 zou de map elke start leegvegen.
      expect(cacheGrenzen, isNotEmpty);
      for (final e in cacheGrenzen.entries) {
        expect(e.value, greaterThan(10 * 1024 * 1024), reason: '${e.key} staat te krap');
      }
      expect(cacheGrenzen.containsKey('discogs'), isFalse,
          reason: 'API-antwoorden weggooien ruilt schijf in voor een verzoekenlimiet');
      expect(cacheGrenzen.containsKey('musicbrainz'), isFalse, reason: 'idem');
      expect(cacheGrenzen.containsKey('hoescache'), isFalse,
          reason: 'die ruimt zichzelf al op tot precies de bibliotheek');
    });
  });
}
