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

    test('anderVooraan: niet twee keer dezelfde plaat op de grote kaarten', () {
      expect(anderVooraan([1, 1, 2, 3], (x) => x == 1), [2, 1, 1, 3]);
      expect(anderVooraan([2, 1], (x) => x == 1), [2, 1]);
      expect(anderVooraan([1, 1], (x) => x == 1), [1, 1], reason: 'alleen die plaat: dan zo laten');
      expect(anderVooraan(<int>[], (x) => true), isEmpty);
    });

    test('releaseKop boven een nummer zegt waar het uit komt', () {
      final ep = _u('Whitney Houston', 'One Wish', '2026-10-16', soort: 'ep');
      expect(releaseKop(ep, nu: _nu, alsNummer: true), 'UIT DE NIEUWE EP');
      expect(releaseKop(_u('A', 'B', '2026-10-16', soort: 'album'), nu: _nu, alsNummer: true), 'UIT HET NIEUWE ALBUM');
      expect(releaseKop(_u('A', 'B', '2026-10-16'), nu: _nu, alsNummer: true), 'NIEUWE SINGLE');
      expect(releaseKop(ep, nu: _nu), 'NIEUWE EP');
    });

    test('Start telt elke lijst opnieuw, tegen wat je de vorige keer zag', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('await (_gezienVorige ??= leesNieuwGezien())'));
      expect(main, isNot(contains('if (_teller == null) unawaited(_telNieuw(l));')));
      expect(main, contains('final nummers = anderVooraan('));
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
        'tracks': {
          'data': [
            {'id': 1, 'title': 'Training Season', 'rank': 900, 'track_position': 1},
            {'id': 2, 'title': 'Houdini', 'rank': 800, 'track_position': 2},
          ]
        }
      },
    };

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
