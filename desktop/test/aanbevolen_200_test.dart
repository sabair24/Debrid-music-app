/// "Aanbevolen voor jou": evenredig over wat je draait, 200 nummers (100 in de rij), en elke ververs nieuwe (21-11-2026).
///
/// Saber, met twee schermafdrukken van de rij: *"aanbevolen, zit vol met enkel rai of arabische muziek, wat mag maar dit
/// is veel te veel, en het is elke dag dezelfde, en er moeten er 100 in de rij staan. aanbevolen mag ook 200 liedjes
/// bevatten, en ik wil als ik ververs elke keer nieuwe liedjes"*. Gekozen: evenredig met wat hij draait, alleen nieuwe
/// artiesten, rij 100 en Alles 200. En voor Ontdek (daar zit de Anthropic-sleutel op): Claude tot tien keer per dag.
library;

import 'dart:io';

import 'package:debridmusic/aanbevolen.dart';
import 'package:debridmusic/nieuwe_releases.dart' show EigenArtiest;
import 'package:debridmusic/ontdekvraag.dart';
import 'package:debridmusic/organize.dart' show artistKey;
import 'package:debridmusic/recommend.dart' show RecTrack, RecommendService;
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Kandidaat _k(int id, String naam, double score, List<String> via) => (id: id, naam: naam, score: score, via: via);
RecTrack _t(String artiest, String titel) => RecTrack(artiest, titel, null);

void main() {
  group('evenredig over de zaden', () {
    test('DE KERN: één zaad met veel onbekende verwanten vult niet de hele rij', () {
      final rang = [
        // Khaled: veel onbekende raï-verwanten, hoog gescoord.
        for (var i = 0; i < 30; i++) _k(100 + i, 'Raï $i', 50 - i.toDouble(), ['Khaled']),
        // De pop-zaden: maar een paar die je nog niet hebt.
        for (var i = 0; i < 5; i++) _k(200 + i, 'Pop A $i', 10 - i.toDouble(), ['Michael Jackson']),
        for (var i = 0; i < 5; i++) _k(300 + i, 'Pop B $i', 10 - i.toDouble(), ['Adele']),
      ];
      final uit = verdeelOverZaden(rang, zaden: ['Khaled', 'Michael Jackson', 'Adele'], aantal: 15);
      expect(uit, hasLength(15));
      expect(uit.where((k) => k.naam.startsWith('Raï')).length, 5, reason: 'een derde, niet de hele rij');
      expect([for (final k in uit.take(3)) k.via.first], ['Khaled', 'Michael Jackson', 'Adele'],
          reason: 'om de beurt per zaad');
    });

    test('heeft een zaad te weinig, dan vult de rest aan — liever een volle lijst', () {
      final rang = [
        for (var i = 0; i < 30; i++) _k(100 + i, 'Raï $i', 50 - i.toDouble(), ['Khaled']),
        _k(200, 'Pop', 10, ['Adele']),
      ];
      final uit = verdeelOverZaden(rang, zaden: ['Khaled', 'Adele'], aantal: 10);
      expect(uit, hasLength(10));
      expect(uit.where((k) => k.naam == 'Pop'), hasLength(1));
    });

    test('een kandidaat die twee zaden noemen, telt bij het zaad dat nog het minst heeft', () {
      final rang = [
        _k(1, 'A1', 9, ['A']),
        _k(2, 'Gedeeld', 8, ['A', 'B']),
        _k(3, 'B1', 7, ['B']),
      ];
      final uit = verdeelOverZaden(rang, zaden: ['A', 'B'], aantal: 4);
      expect([for (final k in uit) k.naam], ['A1', 'Gedeeld', 'B1'],
          reason: 'Gedeeld hoort bij B (nog leeg), niet bij A (had er al één)');
    });
  });

  group('elke ververs nieuwe nummers', () {
    test('DE KERN: eerst wat je nog niet zag, in de volgorde van de voorraad', () {
      final voorraad = [for (var i = 0; i < 10; i++) _t('A$i', 'T$i')];
      const nu = 1000000000;
      final getoond = {for (var i = 0; i < 4; i++) aanbevolenSleutel(voorraad[i]): nu - 1000};
      final uit = trekUitVoorraad(voorraad, getoond, aantal: 4, nuMs: nu);
      expect([for (final t in uit) t.title], ['T4', 'T5', 'T6', 'T7']);
    });

    test('alles al gezien: dan wat het langst geleden was', () {
      final voorraad = [_t('A', 'X'), _t('B', 'Y'), _t('C', 'Z')];
      const nu = 1000000000;
      final getoond = {
        aanbevolenSleutel(voorraad[0]): nu - 300,
        aanbevolenSleutel(voorraad[1]): nu - 900,
        aanbevolenSleutel(voorraad[2]): nu - 600,
      };
      expect([for (final t in trekUitVoorraad(voorraad, getoond, aantal: 2, nuMs: nu)) t.title], ['Y', 'Z']);
    });

    test('na twee weken telt het weer als nieuw', () {
      final t = _t('A', 'X');
      final nu = DateTime(2026, 11, 21).millisecondsSinceEpoch;
      final oud = nu - const Duration(days: 15).inMilliseconds;
      expect(trekUitVoorraad([t], {aanbevolenSleutel(t): oud}, aantal: 1, nuMs: nu), [t]);
    });
  });

  group('de dienst', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_aanb200_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    AanbevolenVoorJou dienst(List<int> berekeningen, {int voorraad = 450}) => AanbevolenVoorJou(
          zoeker: (zaden, bezit) async {
            berekeningen.add(zaden.length);
            final ronde = berekeningen.length;
            return [for (var i = 0; i < voorraad; i++) _t('R$ronde-A$i', 'T$i')];
          },
          artiesten: () => [for (var i = 0; i < 50; i++) EigenArtiest(naam: 'E$i', beurten: 60 - i, nummers: 10)],
          groen: () => {},
          bezit: () => {},
          bestand: File('${map.path}${Platform.pathSeparator}aanbevolen.json'),
        );

    test('DE KERN: 240 nummers uit veertig zaden, en verversen geeft meteen 240 nieuwe', () async {
      final berekeningen = <int>[];
      final d = dienst(berekeningen, voorraad: 800);
      await d.ververs();
      expect(berekeningen, [kAanbevolenZaden], reason: 'veertig zaden (26-11-2026; eerst zes, toen twintig)');
      final eerst = {for (final t in d.lijst!.nummers) aanbevolenSleutel(t)};
      expect(eerst, hasLength(kAanbevolenNummers));
      await d.volgende();
      final tweede = {for (final t in d.lijst!.nummers) aanbevolenSleutel(t)};
      expect(tweede, hasLength(kAanbevolenNummers));
      expect(tweede.intersection(eerst), isEmpty, reason: 'elke ververs nieuwe nummers');
      expect(berekeningen, hasLength(1), reason: 'meteen uit de voorraad, zonder op Deezer te wachten');
    });

    test('raakt de voorraad op, dan rekent hij op de achtergrond een nieuwe', () async {
      final berekeningen = <int>[];
      final d = dienst(berekeningen);
      await d.ververs();
      expect(d.nogVers, 450 - kAanbevolenNummers);
      await d.volgende();
      for (var i = 0; i < 50 && berekeningen.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(berekeningen, hasLength(2), reason: 'minder dan een lijst nieuwe over: een nieuwe voorraad');
    });

    test('de voorraad en wat je zag blijven over een herstart', () async {
      final berekeningen = <int>[];
      final d = dienst(berekeningen, voorraad: 800);
      await d.ververs();
      final eerst = {for (final t in d.lijst!.nummers) aanbevolenSleutel(t)};
      final na = dienst(berekeningen, voorraad: 800);
      await na.laad();
      await na.volgende();
      expect(berekeningen, hasLength(1), reason: 'de voorraad kwam van schijf');
      expect({for (final t in na.lijst!.nummers) aanbevolenSleutel(t)}.intersection(eerst), isEmpty);
    });
  });

  group('tweede graad', () {
    test('DE KERN: een zaad waarvan je de verwanten al hebt, zoekt een stap verder — echt, via Deezer', () async {
      // Khaled (id 1): vijf onbekende raï-verwanten. Pop (id 2): drie verwanten die je allemaal al hebt, met elk
      // een eigen verwant die je nog niet kent. Zonder tweede graad kwam er van Pop niets: de rij werd raï.
      Map<String, dynamic> artiest(int id, String naam) => {'id': id, 'name': naam, 'nb_fan': 1000};
      final verwanten = <int, List<Map<String, dynamic>>>{
        1: [for (var i = 0; i < 5; i++) artiest(101 + i, 'Rai $i')],
        2: [artiest(201, 'Bezit Een'), artiest(202, 'Bezit Twee'), artiest(203, 'Bezit Drie')],
        201: [artiest(301, 'Verder Een')],
        202: [artiest(302, 'Verder Twee')],
        203: [artiest(303, 'Verder Drie')],
      };
      final namen = {for (final l in verwanten.values) for (final a in l) a['id'] as int: a['name'] as String};
      final vragen = <String>[];
      final dienst = RecommendService(
        adem: Duration.zero,
        haal: (url) async {
          vragen.add(url);
          final u = Uri.parse(url);
          if (u.path == '/search/artist') {
            final q = u.queryParameters['q'];
            return {
              'data': [if (q == 'Khaled') artiest(1, 'Khaled') else if (q == 'Pop') artiest(2, 'Pop')],
            };
          }
          final rel = RegExp(r'^/artist/(\d+)/related$').firstMatch(u.path);
          if (rel != null) return {'data': verwanten[int.parse(rel[1]!)] ?? const []};
          final top = RegExp(r'^/artist/(\d+)/top$').firstMatch(u.path);
          if (top != null) {
            final id = int.parse(top[1]!);
            return {
              'data': [
                {
                  'title': 'Lied $id',
                  'artist': {'name': namen[id] ?? '?', 'id': id},
                  'duration': 200,
                  'rank': 1000 - id,
                  'album': {'title': 'Plaat $id', 'id': id, 'cover_medium': null},
                },
              ],
            };
          }
          return {'data': const []};
        },
      );
      final uit = await dienst.ontdekVoorJou(
        [(naam: 'Khaled', gewicht: 10.0), (naam: 'Pop', gewicht: 10.0)],
        {for (final n in ['Bezit Een', 'Bezit Twee', 'Bezit Drie']) artistKey(n)},
        kandidaten: 10,
      );
      final artiesten = {for (final t in uit) t.artist};
      expect(artiesten, containsAll(['Verder Een', 'Verder Twee', 'Verder Drie']),
          reason: 'Pop had niets nieuws in de eerste graad: de verwanten van zijn verwanten');
      expect(artiesten.where((a) => a.startsWith('Rai')), hasLength(5));
      expect(artiesten, isNot(contains('Bezit Een')), reason: 'wat je al hebt, komt er niet in');
      expect(vragen.where((v) => v.contains('/artist/101/related')), isEmpty,
          reason: 'Khaled had genoeg: daar geen stap verder');
    });
  });

  group('aangesloten', () {
    test('de rij toont alles (26-11-2026: "zeker 200"), "Alles" als raster; verversen trekt meteen uit de voorraad', () {
      final m = _bron('lib/main.dart');
      expect(m, contains("_recRow(_forYou.take(kAanbevolenInRij).toList(), rij: 'voorjou')"));
      expect(m, contains('(_) => _AanbevolenAllesPagina('));
      expect(m, contains('      if (dwing) {\n        await pc.volgende();'));
      expect(_bron('lib/lan/server.dart'),
          contains('      l = await d.volgende().timeout(const Duration(seconds: 45), onTimeout: () => d.lijst);'));
      expect(kAanbevolenInRij, kAanbevolenNummers);
      expect(kAanbevolenNummers, greaterThanOrEqualTo(200));
    });

    test('een zaad met te weinig nieuws zoekt een stap verder, en de kandidaten gaan evenredig', () {
      final r = _bron('lib/recommend.dart');
      expect(r, contains('    final tekort = [for (final z in zaden) if (rang.where((k) => k.via.contains(z.naam)).length < quotum) z];'));
      expect(r, contains('    final top = verdeelOverZaden(rang, zaden: [for (final z in zaden) z.naam], aantal: kandidaten);'));
    });

    test('Ontdek: Claude krijgt mee wat er al in de lijst staat, en mag met de hand opnieuw', () {
      final vraag = ontdekPrompt(const OntdekProfiel(zwaarst: ['Sade'], alGetoond: ['Seal — Kiss From A Rose']));
      expect(vraag, contains('noem die NIET opnieuw'));
      expect(vraag, contains('Seal — Kiss From A Rose'));
      final m = _bron('lib/main.dart');
      expect(m, contains('weggetikt: ontdek.weg.namen(), alGetoond: ontdek.alGetoond());'));
      // Sinds 26-11-2026 trekt verversen meteen uit de voorraad; Claude mag bij het bijrekenen ([OntdekVoorJou.volgende]).
      expect(m, contains('          await pc.volgende();'));
      expect(_bron('lib/lan/server.dart'),
          contains('      l = await d.volgende().timeout(const Duration(seconds: 25), onTimeout: () => d.lijst);'));
      expect(_bron('lib/ontdek.dart'),
          contains('    if (vers < kOntdekTrekking && _bezig == null) unawaited(ververs(handmatig: true, bijvullen: true));'));
    });
  });
}
