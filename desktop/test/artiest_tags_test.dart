// Taal en stijl in de bibliotheek, uit de Last.fm-tags per artiest (Saber, 22-10-2026, bij de Last.fm-ideeën: "9").
// Gemeten die dag op 498 artiesten (470 met tags): Frans 68, R&B en soul 73, Eurodance 54, Rock 53. Twee valkuilen:
// naamgenoten (K3 draagt "progressive metal") en nationaliteit in plaats van taal ("dutch" bij Alice Deejay, "german"
// bij Masterboy).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/artiest_tags.dart';
import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/radiostijl.dart' show Stijlfamilie;

void main() {
  group('de groepen van één artiest', () {
    test('DE KERN: een taal uit de tags, een stijl als je eigen genres het niet tegenspreken', () {
      expect(groepenVan(const ['nederlandstalig', 'belgian', 'pop'], const ['Pop']), ['Nederlandstalig']);
      expect(groepenVan(const ['chanson francaise', 'french', 'pop'], const []), ['Frans']);
      expect(groepenVan(const ['eurodance', 'dance', '90s'], const ['Dance']), ['Eurodance']);
      expect(groepenVan(const ['rnb', 'soul', 'female vocalists'], const ['R&B']), ['R&B en soul']);
    });

    test('DE VAL: naamgenoten — K3 met "Pop" in je bestanden wordt geen Metal, wel Nederlandstalig', () {
      expect(groepenVan(const ['progressive metal', 'belgian', 'pop', 'nederlandstalig'], const ['Pop']), [
        'Nederlandstalig',
      ]);
      expect(groepenVan(const ['progressive metal'], const []), [
        'Metal',
      ], reason: 'zonder eigen genre: geen bewijs ertegen');
    });

    test(
      'DE VAL: een nationaliteit is geen taal bij een danceact — "dutch" bij Alice Deejay, "german" bij Masterboy',
      () {
        expect(groepenVan(const ['dutch', 'trance', 'dance'], const ['Dance']), ['Trance']);
        expect(groepenVan(const ['german', 'eurodance', '90s'], const []), ['Eurodance']);
        expect(groepenVan(const ['dutch', 'nederlandstalig', 'pop'], const []), [
          'Nederlandstalig',
        ], reason: 'een echte taaltag telt altijd');
        expect(groepenVan(const ['french', 'chanson francaise', 'pop'], const []), ['Frans']);
        expect(groepenVan(const ['dutch', 'rock'], const ['Rock']), [
          'Nederlandstalig',
          'Rock',
        ], reason: 'geen danceact: dan telt ook de nationaliteit (een gok, maar meestal raak)');
      },
    );

    test('pop en dance lopen in elkaar over: Kate Ryan met "Pop" in haar bestanden is eurodance', () {
      expect(stijlPast(Stijlfamilie.dans, {Stijlfamilie.popsoul}), isTrue);
      expect(stijlPast(Stijlfamilie.rock, {Stijlfamilie.popsoul}), isFalse);
      expect(stijlPast(Stijlfamilie.jazz, const {}), isTrue);
      expect(groepenVan(const ['dance', 'pop', 'eurodance', 'belgian'], const ['Pop']), ['Eurodance']);
    });
  });

  group('de groepen van een bibliotheek', () {
    test('DE KERN: talen eerst, daarna de grootste; alleen vanaf vijf artiesten; de artiesten op naam', () {
      final g = bibliotheekGroepen({
        for (var i = 0; i < 6; i++) 'Frans $i': const ['chanson francaise'],
        for (var i = 0; i < 8; i++) 'Dance $i': const ['eurodance'],
        for (var i = 0; i < 5; i++) 'Soul $i': const ['soul'],
        'Zanger': const ['nederlandstalig'],
      }, const {});
      expect([for (final x in g) '${x.naam} ${x.artiesten.length}'], ['Frans 6', 'Eurodance 8', 'R&B en soul 5']);
      expect(g.first.artiesten.first, 'Frans 0');
      expect(g.first.soort, Groepsoort.taal);
    });
  });

  group('naar de toestellen', () {
    test('de tags reizen mee in de catalogus, en leeg schrijft niets', () {
      const a = ArtistDto(id: '1', name: 'Clouseau', tags: ['nederlandstalig', 'pop']);
      final terug = ArtistDto.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(terug.tags, ['nederlandstalig', 'pop']);
      expect(const ArtistDto(id: '2', name: 'X').toJson().containsKey('tags'), isFalse);
      expect(ArtistDto.fromJson(const {'id': '3', 'name': 'Y'}).tags, isEmpty);
    });

    test('aangesloten: de pc vult ze, de catalogus draagt ze en telt ze mee, het raster toont ze als chips', () {
      String lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
      final catalog = lees('lib/lan/catalog.dart');
      expect(catalog, contains('tags: library.tagsOf(a.name),'));
      expect(catalog, contains("..add(a.tags.join(','));"), reason: 'anders krijgt een toestel een 304');
      final library = lees('lib/library.dart');
      expect(library, contains('if (a.tags.isNotEmpty) MapEntry(artistKey(a.name), a.tags),'));
      expect(library, contains("artist_tags.json"));
      final main = lees('lib/main.dart');
      expect(main, contains('    await library.loadArtistTags();'));
      expect(main, contains('    unawaited(_vulArtiestTags(library, settings));\n'));
      expect(
        main,
        contains('if (++n % 25 == 0) await lib.bewaarArtistTags(melden: false);'),
        reason: 'tussentijds bewaren duwt de catalogus niet naar elk toestel',
      );
      expect(main, contains('return bibliotheekGroepen(tags, genres);'));
      expect(main, contains("label: Text(g == null ? 'Alles' : '\${g.naam} \${g.artiesten.length}',"));
    });
  });
}
