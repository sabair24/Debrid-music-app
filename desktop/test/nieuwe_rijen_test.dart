// De twee rijen "Nieuwe nummers" en "Nieuwe albums & EP's" (Saber, 19-10-2026): uit al je artiesten,
// zes maanden terug, twee per artiest per lijst, per week op de meer-pagina, en de nummers van nieuwe
// albums erbij.
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/nieuwe_releases.dart';
import 'package:debridmusic/startrijen.dart' show bezitssleutel;
import 'package:flutter_test/flutter_test.dart';

// Een maandag, zodat "deze week" vandaag begint.
final _nu = DateTime(2026, 10, 19);
int _id = 1;
CatalogAlbum _al(String titel, String datum, [String soort = 'single']) =>
    CatalogAlbum(_id++, titel, null, datum, 10, soort);
NieuweUitgave _u(String artiest, String titel, String datum,
        {String soort = 'single', double score = 5, String? lijktOp, int remixen = 0}) =>
    NieuweUitgave(album: _al(titel, datum, soort), artiest: artiest, score: score, lijktOp: lijktOp, remixen: remixen);

void main() {
  group('kopjes en lintjes', () {
    test('weekKop', () {
      String k(String d) => weekKop(DateTime.parse(d), _nu);
      expect(k('2026-10-25'), 'Binnenkort');
      expect(k('2026-10-19'), 'Deze week');
      expect(k('2026-10-14'), 'Vorige week');
      expect(k('2026-10-12'), 'Vorige week');
      expect(k('2026-10-05'), 'Eerder in oktober');
      expect(k('2026-09-10'), 'September');
      expect(k('2025-12-20'), 'December 2025');
      expect(weekKop(null, _nu), 'Eerder');
    });

    test('datumLint', () {
      String? l(String d) => datumLint(DateTime.parse(d), _nu);
      expect(l('2026-10-19'), 'Vandaag');
      expect(l('2026-10-18'), 'Gisteren');
      expect(l('2026-10-16'), '3 dagen');
      expect(l('2026-09-12'), '12 sep');
      expect(l('2026-11-06'), '6 nov', reason: 'wat nog komt: de dag waarop het verschijnt');
      expect(datumLint(null, _nu), isNull);
    });

    test('perWeek: Binnenkort bovenaan (wat eerst komt eerst), daarna eigen artiesten voor verwant', () {
      final l = [
        _u('Sting', 'Seven Tears', '2026-11-27'),
        _u('Dua Lipa', 'Later', '2026-10-30'),
        _u('Verwant', 'Buur', '2026-10-19', lijktOp: 'Dua Lipa', score: 99),
        _u('Rihanna', 'Nu', '2026-10-19', score: 1),
        _u('Adele', 'Oud', '2026-09-01'),
      ];
      final w = perWeek(l, datum: (u) => u.datum, eigen: (u) => u.lijktOp == null, score: (u) => u.score, nu: _nu);
      expect([for (final g in w) g.kop], ['Binnenkort', 'Deze week', 'September']);
      expect([for (final u in w[0].items) u.album.title], ['Later', 'Seven Tears']);
      expect([for (final u in w[1].items) u.album.title], ['Nu', 'Buur'],
          reason: 'eigen artiest eerst, ook met een lagere score');
    });

    test('rijVolgorde: vooraan het beste wat al uit is, dan Binnenkort, dan de rest', () {
      final l = [
        _u('A', 'Komt', '2026-11-01'),
        _u('B', 'Vers', '2026-10-19', score: 9),
        _u('C', 'Ouder', '2026-09-01'),
      ];
      final r = rijVolgorde(l, datum: (u) => u.datum, eigen: (u) => true, score: (u) => u.score, nu: _nu);
      expect([for (final u in r) u.album.title], ['Vers', 'Komt', 'Ouder']);
      final alleenKomend = rijVolgorde([l.first], datum: (u) => u.datum, eigen: (u) => true, score: (u) => 0, nu: _nu);
      expect(alleenKomend, hasLength(1));
    });

    test('nieuwSindsVorige: de eerste keer niets (alles zou "nieuw" zijn), daarna wat er bij kwam', () {
      expect(nieuwSindsVorige(['a', 'b'], {}), 0);
      expect(nieuwSindsVorige(['a', 'b', 'c'], {'a', 'b'}), 1);
    });
  });

  group('oude opnamen (ISRC)', () {
    test('isrcJaar', () {
      expect(isrcJaar('USWB19600603'), 1996);
      expect(isrcJaar('USWB12604176'), 2026);
      expect(isrcJaar('gbaht2000041'), 2020);
      expect(isrcJaar('FR-Z03-14-00212'.replaceAll('-', '')), 2014);
      expect(isrcJaar(''), isNull);
      expect(isrcJaar(null), isNull);
      expect(isrcJaar('kapot'), isNull);
    });

    List<AlbumNummer> plaat(List<String?> isrcs) => [
          for (final (i, x) in isrcs.indexed) AlbumNummer(id: i, titel: 'N$i', jaar: isrcJaar(x) ?? 0),
        ];

    test('Madonna "You Must Love Me" (Deezer: single van 12-10-2026) is een heruitgave', () {
      // De echte ISRC's van die uitgave (Deezer-album 1119390132).
      expect(oudeOpnamen(plaat(['USWB12604176', 'USWB19600603', 'USWB19600769']), DateTime(2026, 10, 12)), isTrue);
    });

    test('half oud blijft, zonder ISRC of zonder datum ook', () {
      final d = DateTime(2026, 10, 16);
      expect(oudeOpnamen(plaat(['USA0303', 'USRC10300001', 'USRC12600001', 'USRC12600002', 'USRC12600003']), d),
          isFalse, reason: 'Whitney Houston: 1 van 4 oud (de kapotte telt niet)');
      expect(oudeOpnamen(plaat(['USRC10300001', 'USRC12600001']), d), isFalse, reason: 'de helft is geen meerderheid');
      expect(oudeOpnamen(plaat(['USRC12400001']), d), isFalse, reason: 'twee jaar: nog nieuw genoeg');
      expect(oudeOpnamen(plaat(['USRC12300001']), d), isTrue, reason: 'drie jaar: oud');
      expect(oudeOpnamen(plaat([null, null]), d), isFalse);
      expect(oudeOpnamen(plaat(['USRC19600001']), null), isFalse);
    });

    test('bewaarde nummers van vóór de ISRC-jaren worden één keer opnieuw gevraagd', () async {
      final map = await Directory.systemTemp.createTemp('dm_isrc');
      addTearDown(() => map.delete(recursive: true));
      final f = File('${map.path}/albumnummers.json');
      await f.writeAsString(jsonEncode({
        '7': [
          {'id': 1, 't': 'Oud bewaard', 's': 200, 'r': 5, 'p': 1},
        ],
        '8': [const AlbumNummer(id: 2, titel: 'Met jaar', jaar: 2026).toJson()],
      }));
      final d = NieuweReleases(
        zoeker: NieuweReleasesZoeker((_) async => {'data': []}, slaap: (_) async {}),
        nummers: () => const [],
        bezit: () => const {},
        bestand: File('${map.path}/lijst.json'),
        idsBestand: File('${map.path}/ids.json'),
        nummersBestand: f,
      );
      await d.laad();
      expect(d.zoeker.nummers.containsKey(7), isFalse, reason: 'zonder jaar: opnieuw vragen');
      expect(d.zoeker.nummers[8]!.single.jaar, 2026);
    });
  });

  group('kiesNieuweNummers', () {
    test('singles en de populairste nummers van een nieuw album; twee per artiest; de single wint', () {
      final album = _u('Dua Lipa', 'Radical Optimism', '2026-10-10', soort: 'album', score: 8);
      final single = _u('Dua Lipa', 'Houdini', '2026-09-20', score: 6);
      final uit = kiesNieuweNummers(
        singles: [single],
        albums: [album],
        nummersPerAlbum: {
          album.album.id: const [
            AlbumNummer(id: 1, titel: 'Houdini', rank: 900000, positie: 3),
            AlbumNummer(id: 2, titel: 'Training Season', rank: 800000, positie: 2),
            AlbumNummer(id: 3, titel: 'End Of An Era', rank: 100, positie: 1),
          ]
        },
      );
      expect([for (final n in uit) n.titel], unorderedEquals(['Training Season', 'Houdini']));
      final houdini = uit.firstWhere((n) => n.titel == 'Houdini');
      expect(houdini.album.id, single.album.id, reason: 'de single, niet het albumnummer met dezelfde naam');
      expect(houdini.vanAlbum, isFalse);
      expect(uit.firstWhere((n) => n.titel == 'Training Season').vanAlbum, isTrue);
    });

    test('versies van één liedje op hetzelfde album: één nummer, de rest als remix eronder', () {
      final ep = _u('Whitney Houston', 'One Wish (For Christmas) - The Voice of Whitney Symphonic', '2026-10-16',
          soort: 'ep', score: 9);
      final album = _u('Rolling Stones', 'Out of Our Heads', '2026-10-10', soort: 'album', score: 8);
      final uit = kiesNieuweNummers(
        albums: [ep, album],
        singles: const [],
        nummersPerAlbum: {
          ep.album.id: const [
            AlbumNummer(id: 1, titel: 'One Wish (For Christmas) (The Voice of Whitney Symphonic)', rank: 900),
            AlbumNummer(id: 2, titel: 'One Wish (For Christmas) (The Voice - A cappella Mix)', rank: 800),
          ],
          album.album.id: const [
            AlbumNummer(id: 3, titel: "(I Can't Get No) Satisfaction", rank: 900),
            AlbumNummer(id: 4, titel: '(Walkin\' Thru The) Sleepy City', rank: 800),
          ],
        },
        perArtiest: 5,
      );
      final whitney = [for (final n in uit) if (n.artiest == 'Whitney Houston') n];
      expect(whitney, hasLength(1), reason: 'twee versies van hetzelfde liedje');
      expect(whitney.single.titel, contains('Symphonic'), reason: 'de populairste versie');
      expect(whitney.single.remixen, 1);
      expect([for (final n in uit) if (n.artiest == 'Rolling Stones') n.titel], hasLength(2),
          reason: 'een titel die met een haakje begint zegt niets over het liedje');
    });

    test('rijVolgorde met nietVooraan: de grote kaart is het volgende dat al uit is, nooit Binnenkort', () {
      final l = [
        _u('Whitney Houston', 'One Wish', '2026-10-16', score: 9),
        _u('Pascal Obispo', 'À Forthlin Road', '2026-10-23', score: 8),
        _u('Nelly Furtado', 'FADED', '2026-10-16', score: 7),
      ];
      List<String> r(bool Function(NieuweUitgave)? weg) => [
            for (final u in rijVolgorde(l,
                datum: (u) => u.datum, eigen: (u) => true, score: (u) => u.score, nu: _nu, nietVooraan: weg))
              u.album.title
          ];
      expect(r(null), ['One Wish', 'À Forthlin Road', 'FADED']);
      expect(r((u) => u.artiest == 'Whitney Houston'), ['FADED', 'À Forthlin Road', 'One Wish'],
          reason: 'Pascal Obispo verschijnt pas op 23 oktober');
      expect(r((u) => true), ['One Wish', 'À Forthlin Road', 'FADED'], reason: 'niets anders: dan zo laten');
    });

    test('releaseKop boven een nummer zegt waar het uit komt', () {
      final ep = _u('Whitney Houston', 'One Wish', '2026-10-16', soort: 'ep');
      expect(releaseKop(ep, nu: _nu, alsNummer: true), 'UIT DE NIEUWE EP');
      expect(releaseKop(_u('A', 'B', '2026-10-16', soort: 'album'), nu: _nu, alsNummer: true), 'UIT HET NIEUWE ALBUM');
      expect(releaseKop(_u('A', 'B', '2026-10-16'), nu: _nu, alsNummer: true), 'NIEUWE SINGLE');
      expect(releaseKop(ep, nu: _nu), 'NIEUWE EP');
    });

    test('een tik op de pc: eerst wat TorBox klaar heeft, anders halen zoals de radio', () {
      final main = File('lib/main.dart').readAsStringSync();
      final speel = main.substring(main.indexOf('class NieuwSpeler'), main.indexOf('File get _nieuwOpToestel'));
      expect(speel, contains('EigenRadiobron('));
      expect(speel, contains('await online.resolveRadio(n.artiest, n.titel);'),
          reason: 'alleen klaarstaande torrents: een niet-klaarstaande kan minuten duren');
      expect(speel, isNot(contains('instantOnly: false')));
      expect(speel, contains('for (var ronde = 0; ronde < kNieuwHaalRondes && t == null; ronde++)'),
          reason: 'je vroeg dít nummer: meer dan de drie uploaders van de radio');
      expect(main, contains('const kNieuwHaalRondes = 3;'));
    });

    test('Start telt elke lijst opnieuw, tegen wat je de vorige keer zag', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('await (_gezienVorige ??= leesNieuwGezien())'));
      expect(main, isNot(contains('if (_teller == null) unawaited(_telNieuw(l));')));
      expect(main, contains('nietVooraan: (n) => albums.isNotEmpty && n.album.id == albums.first.album.id'));
    });

    test('wat je al hebt valt weg', () {
      final uit = kiesNieuweNummers(
        singles: [_u('Sean Paul', 'DIP', '2026-09-30'), _u('Sean Paul', 'Nieuw', '2026-10-01')],
        inBezit: {bezitssleutel('Sean Paul', 'DIP')},
      );
      expect([for (final n in uit) n.titel], ['Nieuw']);
    });
  });

  test('kiesUitgaven met soorten: alleen albums en EP\'s', () {
    final a = Aanbod(artiest: 'X', relevantie: 1, albums: [
      _al('Single', '2026-10-01'),
      _al('Album', '2026-10-01', 'album'),
      _al('EP', '2026-10-02', 'ep'),
    ]);
    final uit = kiesUitgaven([a], nu: _nu, soorten: const {UitgaveSoort.album, UitgaveSoort.ep}, perArtiest: 5);
    expect([for (final u in uit) u.album.title], unorderedEquals(['Album', 'EP']));
  });

  group('ReleasesLijst', () {
    test('versie 2 heen en terug, en versie 1 voor oudere apps', () {
      final l = ReleasesLijst(5, [_u('A', 'Oud', '2026-10-01')],
          nummers: [
            NieuwNummer(titel: 'Nummer', artiest: 'B', album: _al('Plaat', '2026-10-02', 'album'), trackId: 7, seconden: 200),
          ],
          albums: [_u('C', 'Album', '2026-10-03', soort: 'album')]);
      final terug = ReleasesLijst.fromJson(jsonDecode(jsonEncode(l.toJson())))!;
      expect(terug.nummers.single.titel, 'Nummer');
      expect(terug.nummers.single.trackId, 7);
      expect(terug.nummers.single.album.title, 'Plaat');
      expect(terug.albums.single.album.title, 'Album');
      expect(terug.uitgaven.single.album.title, 'Oud');
      expect(l.toJsonV1()['versie'], 1);
      expect(l.toJsonV1().containsKey('nummers'), isFalse);
    });

    test('een oudere pc (versie 1): de twee rijen uit de oude lijst', () {
      final v1 = ReleasesLijst(5, [
        _u('A', 'Single', '2026-10-01'),
        _u('B', 'Album', '2026-10-01', soort: 'album'),
      ]).toJsonV1();
      final l = ReleasesLijst.fromJson(jsonDecode(jsonEncode(v1)))!;
      expect([for (final n in l.nummers) n.titel], ['Single']);
      expect([for (final a in l.albums) a.album.title], ['Album']);
    });
  });

  group('een ronde bij Deezer', () {
    ({NieuweReleasesZoeker z, List<String> gevraagd}) nep(Map<String, Object> antwoorden) {
      final gevraagd = <String>[];
      final z = NieuweReleasesZoeker((url) async {
        final pad = url.replaceFirst('https://api.deezer.com', '');
        gevraagd.add(pad);
        for (final e in antwoorden.entries) {
          if (pad.startsWith(e.key)) return jsonDecode(jsonEncode(e.value)) as Map<String, dynamic>;
        }
        return {'data': []};
      }, slaap: (_) async {});
      return (z: z, gevraagd: gevraagd);
    }

    final dua = eigenArtiesten([
      const EigenNummer(artiest: 'Dua Lipa', album: 'Future Nostalgia', titel: 'Levitating', beurten: 20),
    ]).single;

    final antwoorden = <String, Object>{
      '/search/artist': {
        'data': [
          {'id': 8, 'name': 'Dua Lipa', 'nb_fan': 1000}
        ]
      },
      '/artist/8/albums': {
        'data': [
          {'id': 100, 'title': 'Future Nostalgia', 'release_date': '2020-03-27', 'record_type': 'album'},
          {'id': 101, 'title': 'Radical Optimism', 'release_date': '2026-10-10', 'record_type': 'album'},
          {'id': 102, 'title': 'Houdini', 'release_date': '2026-09-20', 'record_type': 'single'},
          {'id': 103, 'title': 'Dance The Night', 'release_date': '2026-05-01', 'record_type': 'single'},
        ],
        'total': 4,
      },
      '/artist/8/related': {
        'data': [
          {'id': 9, 'name': 'Raye'}
        ]
      },
      '/artist/9/albums': {
        'data': [
          {'id': 200, 'title': 'Genesis', 'release_date': '2026-10-15', 'record_type': 'single'},
        ],
        'total': 1,
      },
      '/album/101': {
        'data': [
          {'id': 1, 'title': 'Training Season', 'rank': 900, 'track_position': 1, 'isrc': 'GBAHT2600001'},
          {'id': 2, 'title': 'Houdini', 'rank': 800, 'track_position': 2, 'isrc': 'GBAHT2600002'},
        ]
      },
      '/album/102': {
        'data': [
          {'id': 3, 'title': 'Houdini', 'rank': 950, 'track_position': 1, 'isrc': 'GBAHT2600002'},
        ]
      },
      '/album/103': {
        'data': [
          {'id': 4, 'title': 'Dance The Night', 'rank': 700, 'track_position': 1, 'isrc': 'GBAHT2600003'},
        ]
      },
      '/album/200': {
        'data': [
          {'id': 5, 'title': 'Genesis', 'rank': 600, 'track_position': 1, 'isrc': 'GBAHT2600004'},
        ]
      },
    };

    test('een heruitgave (oude ISRC\'s) valt weg, en de volgende van die artiest schuift op', () async {
      final metOud = {
        ...antwoorden,
        '/artist/8/albums': {
          'data': [
            // Het bewijs dat dit jouw Dua Lipa is: een album dat je hebt.
            {'id': 100, 'title': 'Future Nostalgia', 'release_date': '2020-03-27', 'record_type': 'album'},
            {'id': 101, 'title': 'Radical Optimism', 'release_date': '2026-10-10', 'record_type': 'album'},
            {'id': 104, 'title': 'Club Future Nostalgia', 'release_date': '2026-10-01', 'record_type': 'album'},
            {'id': 105, 'title': 'Live In Mexico', 'release_date': '2026-08-01', 'record_type': 'album'},
            {'id': 106, 'title': 'One Kiss', 'release_date': '2026-10-05', 'record_type': 'single'},
          ],
          'total': 5,
        },
        '/album/104': {
          'data': [
            {'id': 41, 'title': 'Levitating (Remix)', 'rank': 900, 'isrc': 'GBAHT2000041'},
            {'id': 42, 'title': 'Physical (Remix)', 'rank': 800, 'isrc': 'GBAHT2000042'},
          ]
        },
        '/album/105': {
          'data': [
            {'id': 51, 'title': 'Houdini (Live)', 'rank': 500, 'isrc': 'GBAHT2600051'},
          ]
        },
        '/album/106': {
          'data': [
            {'id': 61, 'title': 'One Kiss', 'rank': 990, 'isrc': 'GBAHT1800061'},
          ]
        },
      };
      final d = nep(metOud);
      final v = ReleasesVerslag();
      final uit = await d.z.zoekAlles([dua], nu: _nu, verslag: v);
      expect([for (final a in uit.albums) a.album.title], ['Radical Optimism', 'Live In Mexico'],
          reason: 'Club Future Nostalgia is uit 2020; Live In Mexico schuift op');
      expect([for (final n in uit.nummers) n.titel], isNot(contains('One Kiss')), reason: 'een single uit 2018');
      expect(v.weg['oude opnamen'], 2);
      expect(d.gevraagd, contains('/album/106/tracks?limit=100'), reason: 'alleen /tracks draagt de ISRC');
    });

    test('een intro, interlude of skit van een album is geen nieuw nummer', () {
      final album = _u('Angèle', 'Instinct', '2026-10-16', soort: 'album', score: 8);
      final uit = kiesNieuweNummers(
        singles: const [],
        albums: [album],
        nummersPerAlbum: {
          album.album.id: const [
            AlbumNummer(id: 1, titel: 'Instinct (intro)', rank: 999),
            AlbumNummer(id: 2, titel: 'Intro (Instrumental)', rank: 998),
            AlbumNummer(id: 3, titel: 'Skit', rank: 997),
            AlbumNummer(id: 4, titel: 'Introspection', rank: 500),
            AlbumNummer(id: 5, titel: 'Au revoir', rank: 400),
          ]
        },
        perArtiest: 5,
      );
      expect([for (final n in uit) n.titel], unorderedEquals(['Introspection', 'Au revoir']),
          reason: '"Introspection" begint wel met intro, maar is een liedje');
    });

    test('een remix-EP van een bewezen oude single (verse ISRC\'s) is dezelfde heruitgave', () async {
      final metRemixen = {
        ...antwoorden,
        '/artist/8/albums': {
          'data': [
            {'id': 100, 'title': 'Future Nostalgia', 'release_date': '2020-03-27', 'record_type': 'album'},
            {'id': 108, 'title': 'Witch Doktor', 'release_date': '2026-10-09', 'record_type': 'single'},
            {'id': 109, 'title': 'Witch Doktor (Basic Beat / ffrr Mixes)', 'release_date': '2026-10-16', 'record_type': 'album'},
            {'id': 110, 'title': 'Training Season (Remixes)', 'release_date': '2026-10-16', 'record_type': 'single'},
          ],
          'total': 4,
        },
        '/album/108': {
          'data': [
            {'id': 81, 'title': 'Witch Doktor', 'rank': 900, 'isrc': 'GBAHT9400081'},
          ]
        },
        '/album/109': {
          'data': [
            {'id': 91, 'title': 'Witch Doktor (Radio Edit)', 'rank': 900, 'isrc': 'QMRSZ2603520'},
            {'id': 92, 'title': 'Witch Doktor (Orientalist Mix)', 'rank': 800, 'isrc': 'QMRSZ2603521'},
          ]
        },
        '/album/110': {
          'data': [
            {'id': 101, 'title': 'Training Season (Remix)', 'rank': 700, 'isrc': 'GBAHT2600101'},
          ]
        },
      };
      final v = ReleasesVerslag();
      final uit = await nep(metRemixen).z.zoekAlles([dua], nu: _nu, verslag: v);
      expect([for (final a in uit.albums) a.album.title], isNot(contains('Witch Doktor (Basic Beat / ffrr Mixes)')));
      expect([for (final n in uit.nummers) n.titel], isNot(contains('Witch Doktor')));
      expect(v.weg['oude opnamen'], 2, reason: 'de single en het remixalbum');
    });

    test('de nummers van een album dat nog moet verschijnen staan niet bij Nieuwe nummers', () async {
      final metKomend = {
        ...antwoorden,
        '/artist/8/albums': {
          'data': [
            {'id': 100, 'title': 'Future Nostalgia', 'release_date': '2020-03-27', 'record_type': 'album'},
            {'id': 107, 'title': 'Later', 'release_date': '2026-11-27', 'record_type': 'album'},
          ],
          'total': 2,
        },
        '/album/107': {
          'data': [
            {'id': 71, 'title': 'Nog Niet Uit', 'rank': 999, 'isrc': 'GBAHT2600071'},
          ]
        },
      };
      final uit = await nep(metKomend).z.zoekAlles([dua], nu: _nu);
      expect([for (final a in uit.albums) a.album.title], ['Later'], reason: 'het album zelf: bij Binnenkort');
      expect([for (final n in uit.nummers) n.titel], isNot(contains('Nog Niet Uit')));
    });

    test('een oude opname op een verder nieuw album is geen nieuw nummer', () async {
      final metBonus = {
        ...antwoorden,
        '/album/101': {
          'data': [
            {'id': 7, 'title': "Don't Start Now", 'rank': 99999, 'isrc': 'GBAHT1900007'},
            {'id': 1, 'title': 'Training Season', 'rank': 900, 'isrc': 'GBAHT2600001'},
            {'id': 2, 'title': 'Houdini', 'rank': 800, 'isrc': 'GBAHT2600002'},
          ]
        },
      };
      final uit = await nep(metBonus).z.zoekAlles([dua], nu: _nu);
      expect([for (final a in uit.albums) a.album.title], ['Radical Optimism'], reason: 'het album zelf is nieuw');
      expect([for (final n in uit.nummers) n.titel], isNot(contains("Don't Start Now")));
      expect([for (final n in uit.nummers) n.titel], contains('Training Season'));
    });

    test('albums, nummers (met albumnummers) en verwant, in één ronde', () async {
      final d = nep(antwoorden);
      final uit = await d.z.zoekAlles([dua], nu: _nu);
      expect([for (final a in uit.albums) a.album.title], ['Radical Optimism']);
      final titels = [for (final n in uit.nummers) '${n.artiest}: ${n.titel}'];
      expect(titels, containsAll(['Dua Lipa: Houdini', 'Raye: Genesis']));
      expect(titels.where((t) => t.startsWith('Dua Lipa')).length, 2, reason: 'twee per artiest');
      expect(uit.nummers.firstWhere((n) => n.artiest == 'Raye').lijktOp, 'Dua Lipa');
      expect(d.z.nummers[101], isNotNull, reason: 'de albumnummers zijn onthouden');
    });

    test('"Quota limit exceeded": wachten en opnieuw, en een artiest die niet lukt kost niet de hele ronde',
        () async {
      final gevraagd = <String>[];
      var weigeringen = 1;
      final gewacht = <Duration>[];
      final z = NieuweReleasesZoeker((url) async {
        final pad = url.replaceFirst('https://api.deezer.com', '');
        gevraagd.add(pad);
        if (pad.startsWith('/search/artist?q=Kapot')) throw Exception('altijd stuk');
        if (pad.startsWith('/artist/8/albums') && weigeringen-- > 0) throw Exception('Quota limit exceeded');
        for (final e in antwoorden.entries) {
          if (pad.startsWith(e.key)) return jsonDecode(jsonEncode(e.value)) as Map<String, dynamic>;
        }
        return {'data': []};
      }, slaap: (d) async => gewacht.add(d));
      final kapot = eigenArtiesten([const EigenNummer(artiest: 'Kapot', titel: 'X', beurten: 50)]).single;
      final v = ReleasesVerslag();
      final uit = await z.zoekAlles([kapot, dua], nu: _nu, verslag: v);
      expect([for (final a in uit.albums) a.album.title], ['Radical Optimism'], reason: 'Dua Lipa ging gewoon door');
      expect(v.mislukt, 1, reason: 'alleen de kapotte artiest');
      expect(gewacht, contains(const Duration(seconds: 6)), reason: 'na een quotaweigering eerst wachten');
      expect(gewacht.where((d) => d == NieuweReleasesZoeker.rondeRust), isNotEmpty, reason: 'rust tussen de vragen');
    });

    test('elke vijftig artiesten een tussenstand, zodat een lange eerste ronde te volgen is', () async {
      final d = nep(const {});
      final veel = [
        for (var i = 0; i < 51; i++) EigenArtiest(naam: 'Artiest $i', beurten: 51 - i),
      ];
      final regels = <String>[];
      await d.z.zoekAlles(veel, nu: _nu, tussendoor: (r) async => regels.add(r));
      expect(regels, hasLength(1));
      expect(regels.single, startsWith('50 van 51 artiesten'));
    });

    test('een tweede ronde binnen drie uur vraagt de topartiest en de albumnummers niet opnieuw', () async {
      final d = nep(antwoorden);
      await d.z.zoekAlles([dua], nu: _nu);
      d.gevraagd.clear();
      await d.z.zoekAlles([dua], nu: _nu.add(const Duration(hours: 2)));
      expect(d.gevraagd.where((p) => p.startsWith('/artist/8/albums')), isEmpty);
      expect(d.gevraagd.where((p) => p.startsWith('/album/')), isEmpty);
      d.gevraagd.clear();
      await d.z.zoekAlles([dua], nu: _nu.add(const Duration(hours: 4)));
      expect(d.gevraagd.where((p) => p.startsWith('/artist/8/albums')), isNotEmpty, reason: 'na drie uur wel');
    });
  });
}
