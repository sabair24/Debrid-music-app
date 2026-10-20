/// De jaren op een artiestpagina: het jaar van de PLAAT, niet van zijn digitale heruitgave.
///
/// **Waarom.** Saber, 11-10-2026, bij Serge Gainsbourg: *"kloppen die jaren wel ?? da lijkt me nie
/// correct"*. Aux armes et caetera stond op 2003 (MusicBrainz: 1979), Love On The Beat op 2015 (1984),
/// L'homme à tête de chou op 2023 (1976). Drie oorzaken, gemeten:
/// 1. MusicBrainz ontbrak helemaal: om 17:54 gaf het opzoeken van de artiest één 503 ("busy"), dat
///    werd een uur lang "niets gevonden", en de pagina meldde niets.
/// 2. Discogs las twee pagina's nieuwste-eerst van 59; er kwam niets van vóór 2001 binnen.
/// 3. Deezer-titels met een staart ("-Version Internationale", "(Bande originale du film)") vielen
///    niet samen met de plaat zelf, en stonden met hun heruitgavejaar tussen de albums.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/discography.dart';
import 'package:debridmusic/discography_service.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

DiscoRelease _dz(String t, String d, {RecordKind k = RecordKind.album, int id = 1}) => DiscoRelease(
    title: t, kind: k, firstDate: d, sources: const {DiscoSource.deezer}, refs: {DiscoSource.deezer: CatalogRef.deezer(id)});
DiscoRelease _mb(String t, String d, {RecordKind k = RecordKind.album}) => DiscoRelease(
    title: t, kind: k, firstDate: d, sources: const {DiscoSource.musicbrainz});

http.Response _utf8(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('een uitgave-staart, ook in het Frans en na een streepje', () {
    test('de heruitgaven van Gainsbourg', () {
      expect(heeftEditieStaart('Aux Armes Et Caetera-Version Internationale'), isTrue);
      expect(heeftEditieStaart('Mauvaises Nouvelles Des Etoiles-Version Internationale'), isTrue);
      expect(heeftEditieStaart('Histoire De Melody Nelson - 40ème Anniversaire'), isTrue);
      expect(heeftEditieStaart("L'homme à tête de chou (Mix 2023)"), isTrue);
    });

    test('DE GRENS: geen valse staart', () {
      expect(heeftEditieStaart('Love On The Beat'), isFalse);
      expect(heeftEditieStaart('Jean-Pierre'), isFalse, reason: 'een streepje in een naam');
      expect(heeftEditieStaart('Greatest Hits - 2'), isFalse, reason: 'een kaal getal beslist de jubileumregel');
      expect(heeftEditieStaart('Something - Live'), isFalse, reason: 'live is een aanduiding, geen uitgave');
    });
  });

  group('een aanduiding van wat de plaat IS valt samen met die plaat', () {
    test('DE KERN: soundtrack, BOF en tweede naam krijgen het jaar van de plaat', () {
      final uit = mergeDiscography([
        [
          _dz('Madame Claude (Bande originale du film)', '2021-02-19'),
          _dz('BOF Anna', '2006-02-20', id: 2),
          _dz("L'étonnant Serge Gainsbourg (N°3)", '2016-02-26', id: 3),
        ],
        [_mb('Madame Claude', '1977'), _mb('Anna', '1967'), _mb('L’Étonnant Serge Gainsbourg', '1961-04-05')],
      ]);
      String? jaar(String t) => uit.firstWhere((r) => r.title == t).firstDate;
      expect(uit, hasLength(3), reason: 'elk één regel, niet twee');
      expect(jaar('Madame Claude'), '1977');
      expect(jaar('Anna'), '1967');
      expect(jaar('L’Étonnant Serge Gainsbourg'), '1961-04-05');
      expect(uit.firstWhere((r) => r.title == 'Madame Claude').refs[DiscoSource.deezer]?.intId, 1,
          reason: 'openen gaat nog steeds via Deezer, met zijn tracklijst');
    });

    test('ook "Bande originale de la comédie musicale" en "… du film de Claude Berri"', () {
      final uit = mergeDiscography([
        [
          _dz('Anna (Bande Originale De La Comédie Musicale)', '2006'),
          _dz('Je Vous Aime (Bande Originale Du Film De Claude Berri)', '2010', id: 2),
        ],
        [_mb('Anna', '1967'), _mb('Je vous aime', '1980-04')],
      ]);
      expect({for (final r in uit) r.title: r.firstDate}, {'Anna': '1967', 'Je vous aime': '1980-04'});
    });

    test('live alleen bij een liveplaat', () {
      final uit = mergeDiscography([
        [_dz('Le Zénith de Gainsbourg (Live / 1989)', '2021-06-11'), _dz('Thriller (Live)', '2020', id: 2)],
        [_mb('Le Zénith de Gainsbourg', '1989', k: RecordKind.live), _mb('Thriller', '1982')],
      ]);
      expect(uit.where((r) => r.key == discoKey('Le Zénith de Gainsbourg')).single.firstDate, '1989');
      expect(uit, hasLength(3), reason: '"Thriller (Live)" naast de studioplaat "Thriller" zijn twee platen');
    });

    test('DE KERN: twee keer dezelfde soundtrack zonder kaal album wordt één regel', () {
      // Madonna, 20-10-2026: twee keer tussen de albums; "Who's That Girl" zelf is een single.
      final uit = mergeDiscography([
        [_dz("Who's That Girl Soundtrack", '1987-07-21'), _dz("Who's That Girl", '1987', k: RecordKind.single, id: 2)],
        [_mb('Who’s That Girl: Original Motion Picture Soundtrack', '1987-07-21'),
         _mb('Who’s That Girl', '1987-06-30', k: RecordKind.single)],
      ]);
      expect(uit.where((r) => r.kind == RecordKind.album).map((r) => r.title),
          ['Who’s That Girl: Original Motion Picture Soundtrack']);
      expect(uit.where((r) => r.kind == RecordKind.single), hasLength(1), reason: 'de single blijft de single');
      expect(uit.firstWhere((r) => r.kind == RecordKind.album).refs[DiscoSource.deezer]?.intId, 1,
          reason: 'openen gaat via Deezer, met zijn tracklijst');
    });

    test('DE GRENS: een live- en een soundtrackregel met dezelfde kale titel blijven twee', () {
      final uit = mergeDiscography([
        [_dz('Evita (Live)', '1998', k: RecordKind.live), _dz('Evita: Original Motion Picture Soundtrack', '1996', id: 2)],
      ]);
      expect(uit, hasLength(2));
    });

    test('DE GRENS: zonder de kale titel blijft hij staan zoals hij is', () {
      final uit = mergeDiscography([
        [_dz('Madame Claude (Bande originale du film)', '2021-02-19')]
      ]);
      expect(uit.single.title, 'Madame Claude (Bande originale du film)');
    });

    test('de volgorde van de bronnen maakt niet uit', () {
      final a = [_dz('Madame Claude (Bande originale du film)', '2021-02-19')];
      final b = [_mb('Madame Claude', '1977')];
      String vorm(List<DiscoRelease> l) => (l.map((r) => '${r.title}|${r.firstDate}').toList()..sort()).join(';');
      expect(vorm(mergeDiscography([a, b])), vorm(mergeDiscography([b, a])));
    });
  });

  test('DE KERN: Gainsbourg — Deezer met zijn heruitgavedata en MusicBrainz met de plaat', () {
    // De echte titels en data van 11-10-2026: links Deezer, rechts MusicBrainz.
    const paren = {
      'Aux armes et caetera': ['2003', 'Aux armes et cætera', '1979-03-13'],
      'Love On The Beat': ['2015-10-30', 'Love on the Beat', '1984-10-02'],
      "You're Under Arrest": ['2001-01-01', 'You’re Under Arrest', '1987'],
      "Vu de l'extérieur": ['2016-02-26', 'Vu de l’extérieur', '1973'],
      'Rock Around The Bunker': ['2015-10-30', 'Rock Around the Bunker', '1975'],
      'N°2': ['2018-06-22', 'Nº2', '1959-07'],
      'Gainsbourg percussions': ['2019-02-14', 'Gainsbourg Percussions', '1964-10-26'],
      'Mauvaises nouvelles des étoiles': ['2015-10-30', 'Mauvaises nouvelles des étoiles', '1981'],
    };
    var i = 0;
    final uit = mergeDiscography([
      [for (final e in paren.entries) _dz(e.key, e.value[0], id: ++i)],
      [for (final e in paren.entries) _mb(e.value[1], e.value[2])],
    ]);
    expect(uit, hasLength(paren.length));
    for (final e in paren.entries) {
      expect(uit.firstWhere((r) => r.key == discoKey(e.key)).firstDate, e.value[2], reason: e.key);
    }
  });

  group('Discogs: de masters uit de sweep, met hun eerste jaar', () {
    setUp(() => setAppDirForTest(Directory.systemTemp.createTempSync('dm_dgjaren_').path));

    test('DE KERN: wat buiten de twee pagina\'s viel komt erbij, en alleen op zijn naam', () async {
      const sweep = DiscogsSweep({4955: 'Vinyl, LP, Album', 9737: 'LP, Album', 77: 'LP, Comp'}, {}, {}, {
        4955: (titel: 'Aux Armes Et Cætera', jaar: 1979, artiest: 'Serge Gainsbourg'),
        9737: (titel: 'Love On The Beat', jaar: 1984, artiest: 'Serge Gainsbourg*'),
        88: (titel: 'Jane Birkin & Serge Gainsbourg', jaar: 1969, artiest: 'Jane Birkin & Serge Gainsbourg'),
        77: (titel: 'Les Années Yé-Yé', jaar: 1990, artiest: 'Various'),
        66: (titel: 'Initials B.B.', jaar: 1968, artiest: 'Brigitte Bardot'),
      });
      late List<DiscoRelease> rijen;
      await http.runWithClient(() async {
        rijen = await DiscogsService(AppSettings()..discogsToken = 'nep').artistReleases(5951,
            sweep_: sweep, naam: 'Serge Gainsbourg');
      }, () => MockClient((r) async => _utf8(jsonEncode({'releases': [], 'pagination': {'pages': 1}}), 200)));
      final jaren = {for (final r in rijen) r.title: r.firstDate};
      expect(jaren['Aux Armes Et Cætera'], '1979');
      expect(jaren['Love On The Beat'], '1984', reason: 'het sterretje van een andere schrijfwijze telt niet');
      expect(jaren['Jane Birkin & Serge Gainsbourg'], '1969', reason: 'een duo telt voor allebei');
      expect(jaren.containsKey('Les Années Yé-Yé'), isFalse, reason: 'Various is niet van hem');
      expect(jaren.containsKey('Initials B.B.'), isFalse, reason: 'een plaat van iemand anders');
    });

    test('een master die de pagina\'s al hadden komt er geen tweede keer bij', () async {
      const sweep = DiscogsSweep({}, {}, {}, {
        4955: (titel: 'Aux Armes Et Cætera', jaar: 1979, artiest: 'Serge Gainsbourg'),
      });
      late List<DiscoRelease> rijen;
      await http.runWithClient(() async {
        rijen = await DiscogsService(AppSettings()..discogsToken = 'nep').artistReleases(5951,
            sweep_: sweep, naam: 'Serge Gainsbourg');
      }, () => MockClient((r) async => _utf8(jsonEncode({
            'releases': [
              {'id': 4955, 'type': 'master', 'role': 'Main', 'title': 'Aux Armes Et Cætera', 'year': 1979, 'artist': 'Serge Gainsbourg'},
            ],
            'pagination': {'pages': 1}
          }), 200)));
      expect(rijen.where((r) => r.key == discoKey('Aux Armes Et Cætera')), hasLength(1));
    });

    test('de sweep onthoudt titel, jaar en artiest van elke master', () async {
      late DiscogsSweep sweep;
      await http.runWithClient(() async {
        sweep = await DiscogsService(AppSettings()..discogsToken = 'nep').artistSweep(5951);
      }, () => MockClient((r) async => _utf8(jsonEncode({
            'results': [
              {'id': 4955, 'type': 'master', 'title': 'Serge Gainsbourg - Aux Armes Et Cætera', 'year': '1979', 'format': ['Vinyl', 'LP', 'Album']},
            ],
            'pagination': {'pages': 1}
          }), 200)));
      expect(sweep.meesters[4955], (titel: 'Aux Armes Et Cætera', jaar: 1979, artiest: 'Serge Gainsbourg'));
    });
  });

  group('MusicBrainz: een "busy" is een verzoek om het straks opnieuw te proberen', () {
    setUp(() {
      setAppDirForTest(Directory.systemTemp.createTempSync('dm_mbbusy_').path);
      MusicBrainzService.resetLanes();
      MusicBrainzService.busyWacht = (_) async {};
    });
    tearDown(() => MusicBrainzService.busyWacht = Future<void>.delayed);

    const gevonden = {
      'artists': [
        {'id': 'b21ef19b-c6aa-4775-90d3-3cc3e067ce6d', 'name': 'Serge Gainsbourg', 'score': 100}
      ]
    };

    test('DE KERN: na één 503 de tweede poging, en dan gewoon het antwoord', () async {
      var vragen = 0;
      late List<MbArtist> uit;
      await http.runWithClient(() async {
        uit = await MusicBrainzService().searchArtists('Serge Gainsbourg', max: 5);
      }, () => MockClient((r) async {
            vragen++;
            return vragen == 1
                ? http.Response('{"error": "The MusicBrainz web server is currently busy."}', 503)
                : _utf8(jsonEncode(gevonden), 200);
          }));
      expect(vragen, 2);
      expect(uit.single.name, 'Serge Gainsbourg');
    });

    test('DE GRENS: niet eindeloos — na drie keer busy geeft hij het op', () async {
      var vragen = 0;
      await http.runWithClient(() async {
        await MusicBrainzService().searchArtists('Serge Gainsbourg', max: 5);
      }, () => MockClient((r) async {
            vragen++;
            return http.Response('busy', 503);
          }));
      expect(vragen, MusicBrainzService.kBusyPogingen);
    });

    test('een discografie die MusicBrainz niet kon geven heet "niet bereikbaar", niet "niets"', () async {
      late BronUitkomst u;
      await http.runWithClient(() async {
        u = await DiscographyService(CatalogService(), MusicBrainzService(), DiscogsService(AppSettings()))
            .vanMusicBrainz('Serge Gainsbourg');
      }, () => MockClient((r) async => http.Response('busy', 503)));
      expect(u.status, BronStatus.onbereikbaar);
    });

    test('kent MusicBrainz hem echt niet, dan is het gewoon "klaar"', () async {
      late BronUitkomst u;
      await http.runWithClient(() async {
        u = await DiscographyService(CatalogService(), MusicBrainzService(), DiscogsService(AppSettings()))
            .vanMusicBrainz('Niemand Bestaat Zo');
      }, () => MockClient((r) async => _utf8(jsonEncode({'artists': []}), 200)));
      expect(u.status, BronStatus.klaar);
    });
  });
}
