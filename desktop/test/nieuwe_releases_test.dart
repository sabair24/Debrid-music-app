// De balk "Nieuwe release": wie, wat, en of het echt nieuw is.
//
// De titels hieronder zijn letterlijk wat Deezer op 15-10-2026 voor deze artiesten teruggaf.
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/nieuwe_releases.dart';
import 'package:debridmusic/startrijen.dart' show bezitssleutel;
import 'package:flutter_test/flutter_test.dart';

final _nu = DateTime(2026, 10, 15);
int _id = 1;
CatalogAlbum _al(String titel, String datum, [String soort = 'single']) =>
    CatalogAlbum(_id++, titel, null, datum, 1, soort);

Aanbod _van(String artiest, List<CatalogAlbum> albums, {double r = 10, String? lijktOp}) =>
    Aanbod(artiest: artiest, relevantie: r, albums: albums, lijktOp: lijktOp);

List<String> _titels(List<NieuweUitgave> u) => [for (final x in u) x.album.title];

void main() {
  test('een plaat die nog moet verschijnen: de hoes uit md5_image (Sting, Seven Tears, 18-10-2026)', () {
    final al = deezerAlbumUit({'id': 1, 'title': 'Seven Tears', 'cover_big': null, 'md5_image': '9846572093021a90c5c23ed30c125c31', 'release_date': '2026-11-27'})!;
    expect(al.cover, 'https://cdn-images.dzcdn.net/images/cover/9846572093021a90c5c23ed30c125c31/500x500-000000-80-0-0.jpg');
    // Een gewone plaat houdt zijn eigen adres, en zonder iets blijft het leeg.
    expect(deezerAlbumUit({'id': 2, 'title': 'X', 'cover_big': 'https://a/b.jpg', 'md5_image': 'abc'})!.cover, 'https://a/b.jpg');
    expect(deezerAlbumUit({'id': 3, 'title': 'Y'})!.cover, isNull);
  });

  group('wat geen nieuwe muziek is', () {
    String? r(String t, [String soort = 'album', int jaar = 2026]) =>
        geenNieuweMuziek(t, recordType: soort, jaar: jaar);

    test('heruitgaven', () {
      expect(r('WH1TNEY (Expanded Edition)'), 'heruitgave');
      expect(r("B'DAY (20th ANNIVERSARY DELUXE EDITION)"), 'heruitgave');
      expect(r('This Is Acting (10th Anniversary Edition)'), 'heruitgave');
    });
    test('verzamelaars', () {
      expect(r('ReVivo: Los Hits'), 'verzamelaar');
      expect(r('The Very Best Of Celine Dion'), 'verzamelaar');
      expect(r('Wat dan ook', 'compile'), 'verzamelaar');
      expect(r('The Early Dancehall Years'), 'verzamelaar');
      expect(r('Singles 1990-2003'), 'verzamelaar');
    });
    test('soundtracks', () {
      expect(r('The Devil Wears Prada 2 (Music From The Motion Picture)'), 'soundtrack');
    });
    test('archief: outtakes en live met een oud jaartal', () {
      expect(r('Tomorrow Never Knows (Outtake)', 'single'), 'archief');
      expect(r('Careless Whisper (Live in Paris, 1988)', 'single'), 'archief');
      expect(r("The Roof Is Leaking (Live at the Secret Policeman's Other Ball, London, 1981)", 'single'),
          'archief');
      expect(r('Roots, Rock, Reggae (Live At The Hammersmith Odeon, London, UK - June 1976)'), 'archief');
    });
    test('maar een nieuwe live-plaat en een nieuwe single blijven', () {
      expect(r('The Night Watch (Live at the Rijksmuseum)'), isNull);
      expect(r("Hymne à l'amour (Live aux Jeux Olympiques de Paris 2024)", 'single', 2024), isNull);
      expect(r('Caught Up', 'single'), isNull);
      expect(r('Hits Different', 'single'), isNull, reason: 'een titel met "hits" erin is geen verzamelaar');
      expect(r('DNA (More Than A Game) [FIFA World Cup 2026™]', 'single'), isNull);
    });
  });

  group('remixen vallen onder hun single', () {
    test('de basis', () {
      expect(uitgaveBasis('MORNING DEW (DONK) REMIX PACK'), uitgaveBasis('MORNING DEW (DONK)'));
      expect(uitgaveBasis('Sad Girls (Extended Mix)'), uitgaveBasis('Sad Girls'));
      expect(uitgaveBasis('Sad Girls (DJs from Mars Remix)'), uitgaveBasis('Sad Girls'));
      expect(uitgaveBasis('Caught Up'), isNot(uitgaveBasis('Mariô')));
      expect(uitgaveBasis('Songs In The Key Of Life - The EP'), uitgaveBasis('Songs In The Key Of Life'));
      expect(uitgaveBasis('We Found Love (feat. Calvin Harris)'), uitgaveBasis('We Found Love (Extended Version)'));
    });

    test('één tegel, met het aantal remixen erbij', () {
      final u = kiesUitgaven([
        _van('Beyoncé', [
          _al('MORNING DEW (DONK) REMIX PACK', '2026-08-04'),
          _al('MORNING DEW (DONK)', '2026-07-24'),
        ]),
      ], nu: _nu);
      expect(_titels(u), ['MORNING DEW (DONK)']);
      expect(u.single.remixen, 1);
      expect(releaseOnderschrift(u.single), '24 juli 2026 · + 1 remix');
    });
  });

  group('kiezen', () {
    test('alleen de laatste 90 dagen, plus wat binnen 45 dagen verschijnt', () {
      final u = kiesUitgaven([
        _van('Sting', [
          _al('Seven Tears', '2026-11-27', 'album'), // over 43 dagen
          _al('Ver weg', '2027-02-01', 'album'), // te ver
          _al('The Night Watch (Live at the Rijksmuseum)', '2026-06-26', 'album'), // 111 dagen
        ]),
        _van('Britney Spears', [_al("She'll Never Be Me", '2026-10-09')]),
      ], nu: _nu);
      expect(_titels(u)..sort(), ['Seven Tears', "She'll Never Be Me"]);
    });

    test('hoogstens twee per artiest, de single vóór zijn remixen van anderen', () {
      final u = kiesUitgaven([
        _van('David Guetta', [
          _al('Caught Up', '2026-10-09'),
          _al('Mariô', '2026-10-02'),
          _al('RoTATe wiTh aMeRiCa FOsTeR (David Guetta Remix)', '2026-09-18'),
          _al('You And I, Me And You', '2026-09-11'),
        ]),
      ], nu: _nu);
      expect(_titels(u), ['Caught Up', 'Mariô']);
    });

    test('een oud nummer in een nieuw jasje is geen nieuwe muziek — een nieuwe remix van een nieuw nummer wel', () {
      // De eerste echte ronde, 15-10-2026: deze twee stonden bovenaan.
      final weg = <String, int>{};
      final u = kiesUitgaven([
        _van('Rihanna', [
          _al('We Found Love (Extended Version)', '2026-09-22'),
          _al('We Found Love (feat. Calvin Harris)', '2011-09-22'),
        ]),
        // Dit keer niet uit Deezer maar uit de eigen bibliotheek: het nummer staat er met jaartal.
        Aanbod(artiest: 'Britney Spears', relevantie: 10, albums: [_al("I'm A Slave 4 U (Remixes)", '2026-09-25')],
            eerder: {vergelijkTitel("I'm a Slave 4 U"): 2001}),
        _van('Céline Dion', [
          _al('Bonjour, Pardon, Merci (Bon Entendeur Remix)', '2026-09-25'),
          _al('Bonjour, Pardon, Merci', '2026-07-03'),
        ]),
      ], nu: _nu, weg: weg);
      expect(_titels(u), ['Bonjour, Pardon, Merci (Bon Entendeur Remix)']);
      expect(weg['oud nummer'], 2);
    });

    test('wat je al hebt valt weg', () {
      final u = kiesUitgaven([
        _van('Dua Lipa', [_al("Training Season's Over", '2026-08-28')]),
      ], nu: _nu, alInBezit: {bezitssleutel('Dua Lipa', "Training Season's Over")});
      expect(u, isEmpty);
    });

    test('de zwaarste artiest en de verste plaat bovenaan', () {
      final u = kiesUitgaven([
        _van('Weinig gedraaid', [_al('Een', '2026-10-10')], r: 2),
        _van('Veel gedraaid', [_al('Twee', '2026-08-20')], r: 14),
      ], nu: _nu);
      expect(_titels(u), ['Twee', 'Een']);
    });

    test('aanvullers om de beurt per artiest waarop ze lijken', () {
      expect(omDeBeurt(['c1', 'c2', 'c3', 'g1', 'b1'], (s) => s[0], 3), ['c1', 'g1', 'b1']);
      expect(omDeBeurt(['c1', 'c2', 'g1'], (s) => s[0], 5), ['c1', 'g1', 'c2']);
      expect(omDeBeurt(<String>[], (s) => s, 3), isEmpty);
    });

    test('hoogstens vijftien', () {
      final u = kiesUitgaven([
        for (var i = 0; i < 20; i++) _van('Artiest $i', [_al('Single $i', '2026-10-0${1 + i % 9}')]),
      ], nu: _nu);
      expect(u.length, 15);
    });

    test('wat afvalt wordt per reden geteld', () {
      final weg = <String, int>{};
      kiesUitgaven([
        _van('Phil Collins', [
          _al("The Roof Is Leaking (Live at the Secret Policeman's Other Ball, London, 1981)", '2026-09-10'),
          _al('Tomorrow Never Knows (Outtake)', '2026-08-14'),
        ]),
        _van('Whitney Houston', [_al('WH1TNEY (Expanded Edition)', '2026-08-10', 'album')]),
      ], nu: _nu, weg: weg);
      expect(weg, {'archief': 2, 'heruitgave': 1});
    });
  });

  group('wie', () {
    final nuMs = _nu.millisecondsSinceEpoch;
    final dag = const Duration(days: 1).inMilliseconds;

    test('beurten wegen zwaarder dan bezit, en wie je net draaide krijgt er wat bij', () {
      final veel = EigenArtiest(naam: 'Britney Spears', beurten: 60, nummers: 20, laatstMs: nuMs - 2 * dag);
      final bezit = EigenArtiest(naam: 'Kaoma', beurten: 2, nummers: 30, laatstMs: nuMs - 200 * dag);
      final vergeten = EigenArtiest(naam: 'Europe', beurten: 2, nummers: 1, laatstMs: nuMs - 300 * dag);
      expect(relevanteArtiesten([vergeten, bezit, veel], nuMs: nuMs).map((a) => a.naam),
          ['Britney Spears', 'Kaoma', 'Europe']);
      // Ook zonder recente beurt: wie je veel draaide gaat voor wie je veel hebt.
      final gedraaid = EigenArtiest(naam: 'Dua Lipa', beurten: 60, nummers: 10, laatstMs: nuMs - 100 * dag);
      expect(relevanteArtiesten([bezit, gedraaid], nuMs: nuMs).first.naam, 'Dua Lipa');
    });

    test('de bibliotheek per artiest, gasten niet als aparte artiest', () {
      final a = eigenArtiesten([
        EigenNummer(artiest: "Lil' Kim feat. Phil Collins", album: 'In The Air Tonite', titel: 'In The Air Tonite', beurten: 3, laatstMs: 5),
        EigenNummer(artiest: "Lil' Kim", album: 'Hard Core', titel: 'Crush On You', beurten: 1, laatstMs: 9),
        EigenNummer(artiest: 'Various Artists', album: 'Hits', titel: 'X', beurten: 50, laatstMs: 9),
      ], overslaan: (n) => n.toLowerCase().startsWith('various'));
      expect(a.map((x) => x.naam), ["Lil' Kim"]);
      expect(a.single.beurten, 4);
      expect(a.single.nummers, 2);
      expect(a.single.laatstMs, 9);
      expect(a.single.albums, containsAll(['in the air tonite', 'hard core']));
    });

    test('een naamgenoot deelt niets met wat jij hebt', () {
      // Sabers Predator is één gabbernummer op een Thunderdome-verzamelaar.
      final eigen = eigenArtiesten([
        EigenNummer(artiest: 'Predator', album: 'Thunderdome VIII', titel: 'Head Bangers', beurten: 1, laatstMs: 0),
      ]).single;
      expect(zelfdeArtiest(eigen, albums: ['26"27"', 'Guillotine Chapter One']), isFalse);
      expect(zelfdeArtiest(eigen, titels: ['Head Bangers (Original Mix)']), isTrue);
      final sia = eigenArtiesten([
        EigenNummer(artiest: 'Sia', album: 'This Is Acting', titel: 'Cheap Thrills', beurten: 9, laatstMs: 0),
      ]).single;
      expect(zelfdeArtiest(sia, albums: ['This Is Acting (Deluxe Version)']), isTrue);
    });
  });

  group('de kop boven een tegel', () {
    NieuweUitgave u(String soort, String datum, {String? lijktOp}) => NieuweUitgave(
        album: CatalogAlbum(1, 'X', null, datum, 1, soort), artiest: 'A', lijktOp: lijktOp);
    test('soort, en wat nog moet verschijnen', () {
      expect(releaseKop(u('single', '2026-10-09'), nu: _nu), 'NIEUWE SINGLE');
      expect(releaseKop(u('ep', '2026-09-10'), nu: _nu), 'NIEUWE EP');
      expect(releaseKop(u('album', '2026-11-06'), nu: _nu), 'NIEUW ALBUM · VERSCHIJNT 6 NOV');
      expect(releaseKop(u('single', '2026-10-01', lijktOp: 'Dua Lipa'), nu: _nu),
          'LIJKT OP DUA LIPA · NIEUWE SINGLE');
    });
    test('vandaag is geen "verschijnt"', () {
      expect(releaseKop(u('single', '2026-10-15'), nu: _nu), 'NIEUWE SINGLE');
    });
  });

  group('bij Deezer', () {
    /// Een nep-Deezer: pad → antwoord, en wat er gevraagd werd.
    ({NieuweReleasesZoeker z, List<String> gevraagd}) nep(Map<String, Object> antwoorden) {
      final gevraagd = <String>[];
      final z = NieuweReleasesZoeker((url) async {
        final pad = url.replaceFirst('https://api.deezer.com', '');
        gevraagd.add(pad);
        for (final e in antwoorden.entries) {
          if (pad.startsWith(e.key)) return jsonDecode(jsonEncode(e.value)) as Map<String, dynamic>;
        }
        return {'data': []};
      });
      return (z: z, gevraagd: gevraagd);
    }

    Map<String, Object> albums(List<(String, String, String)> l, {int? total}) => {
          'data': [
            for (final (i, x) in l.indexed)
              {'id': 900 + i, 'title': x.$1, 'release_date': x.$2, 'record_type': x.$3, 'nb_tracks': 1}
          ],
          'total': total ?? l.length,
        };

    final predator = eigenArtiesten([
      EigenNummer(artiest: 'Predator', album: 'Thunderdome VIII', titel: 'Head Bangers', beurten: 1, laatstMs: 0),
    ]).single;

    test('de bekendste naamgenoot zonder bewijs wordt overgeslagen, de juiste niet', () async {
      final d = nep({
        '/search/artist': {
          'data': [
            {'id': 1, 'name': 'Predator', 'nb_fan': 50000},
            {'id': 2, 'name': 'Predator', 'nb_fan': 300},
          ]
        },
        '/artist/1/albums': albums([('Guillotine Chapter One', '2026-09-01', 'album')]),
        '/artist/1/top': {'data': [{'title': 'Bloodbath'}]},
        '/artist/2/albums': albums([('Hardcore Will Never Die', '2026-10-01', 'single')]),
        '/artist/2/top': {'data': [{'title': 'Head Bangers'}]},
      });
      final v = ReleasesVerslag();
      final u = await d.z.zoek([predator], nu: _nu, verslag: v);
      expect(_titels(u), ['Hardcore Will Never Die']);
      expect(d.z.ids.values.single.id, 2);
      expect(v.herkend, 1);
    });

    test('zonder bewijs bij geen enkele: niets, en dat wordt een week onthouden', () async {
      final d = nep({
        '/search/artist': {'data': [{'id': 1, 'name': 'Predator', 'nb_fan': 50000}]},
        '/artist/1/albums': albums([('Guillotine Chapter One', '2026-09-01', 'album')]),
        '/artist/1/top': {'data': [{'title': 'Bloodbath'}]},
      });
      final v = ReleasesVerslag();
      expect(await d.z.zoek([predator], nu: _nu, verslag: v), isEmpty);
      expect(v.naamgenoot, 1);
      expect(v.overgeslagen, ['Predator']);
      final eerst = d.gevraagd.length;
      await d.z.zoek([predator], nu: _nu.add(const Duration(days: 3)));
      expect(d.gevraagd.length, eerst, reason: 'binnen de week niet opnieuw zoeken');
      await d.z.zoek([predator], nu: _nu.add(const Duration(days: 8)));
      expect(d.gevraagd.length, greaterThan(eerst));
    });

    test('meer dan honderd uitgaven: een tweede bladzijde, en zelf op datum sorteren', () async {
      final d = nep({
        '/artist/5/albums?limit=100&index=100': albums([('Caught Up', '2026-10-09', 'single')]),
        '/artist/5/albums?limit=100': albums([('Oud album', '2011-01-01', 'album')], total: 398),
      });
      final l = await d.z.uitgavenVan(5);
      expect(l.map((a) => a.title), ['Caught Up', 'Oud album']);
      expect(d.gevraagd, contains('/artist/5/albums?limit=100&index=100'));
    });

    test('te weinig? verwante artiesten, met erbij op wie ze lijken — en nooit een eigen artiest dubbel', () async {
      final dua = eigenArtiesten([
        EigenNummer(artiest: 'Dua Lipa', album: 'Future Nostalgia', titel: 'Levitating', beurten: 30, laatstMs: 0),
        EigenNummer(artiest: 'Kylie Minogue', album: 'Fever', titel: 'Fever', beurten: 1, laatstMs: 0),
      ]);
      final d = nep({
        '/search/artist?q=Dua': {'data': [{'id': 10, 'name': 'Dua Lipa', 'nb_fan': 9}]},
        '/search/artist?q=Kylie': {'data': [{'id': 11, 'name': 'Kylie Minogue', 'nb_fan': 9}]},
        '/artist/10/albums': albums([('Future Nostalgia', '2020-03-27', 'album')]),
        '/artist/11/albums': albums([('Fever', '2001-10-01', 'album')]),
        '/artist/10/related': {
          'data': [
            {'id': 11, 'name': 'Kylie Minogue'},
            {'id': 20, 'name': 'Raye'},
          ]
        },
        '/artist/20/albums': albums([('Nieuw van Raye', '2026-10-01', 'single')]),
      });
      final u = await d.z.zoek(relevanteArtiesten(dua, nuMs: _nu.millisecondsSinceEpoch), nu: _nu);
      expect(_titels(u), ['Nieuw van Raye']);
      expect(u.single.lijktOp, 'Dua Lipa');
      expect(d.gevraagd.where((p) => p.startsWith('/chart')), isEmpty, reason: 'nooit een hitlijst');
    });
  });

  group('aangesloten', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final server = File('lib/lan/server.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('de startpagina wacht voor de balk niet meer op de andere rijen', () {
      final s = main.indexOf('Future<void> _loadSeeds(');
      final e = main.indexOf('String? get _genreBijschrift', s);
      expect(main.substring(s, e), isNot(contains('latestFromArtists')));
      expect(main, contains('unawaited(_laadNieuw())'));
    });

    test('de balk toont de kop en de datum, en valt niet terug op de hitlijst', () {
      expect(main, contains('koppen: {for (final u in hero) u.album.id: releaseKop(u, nu: nu)},'));
      expect(main, contains('final hero = _nieuw.take(7).toList();'));
      expect(main, isNot(contains('uitJaar(_charts')));
    });

    test('de pc rekent het uit en een toestel vraagt het hem', () {
      expect(main, contains('NieuweReleases.pc = releases;'));
      expect(server, contains("case '/api/releases':"));
      expect(server, contains("'/api/cast/status', '/api/releases',"), reason: 'ook van buiten');
    });
  });

  test('buren alleen van wie zelf iets nieuws uitbracht, ook als je dat al hebt', () async {
    // Op de pc, 15-10-2026: Céline Dions remix was gedownload, en toen leverde Michael Jackson de buren.
    final eigen = eigenArtiesten([
      EigenNummer(artiest: 'Michael Jackson', album: 'Thriller', titel: 'Billie Jean', beurten: 119),
      EigenNummer(artiest: 'Céline Dion', album: "Let's Talk About Love", titel: 'My Heart Will Go On', beurten: 39),
    ]);
    final gevraagd = <String>[];
    final z = NieuweReleasesZoeker((url) async {
      final pad = url.replaceFirst('https://api.deezer.com', '');
      gevraagd.add(pad);
      Map<String, dynamic> albums(List<(String, String)> l) => {
            'data': [
              for (final (i, x) in l.indexed)
                {'id': pad.hashCode.abs() % 1000 + i, 'title': x.$1, 'release_date': x.$2, 'record_type': 'single'}
            ],
            'total': l.length,
          };
      if (pad.startsWith('/search/artist?q=Michael')) return {'data': [{'id': 1, 'name': 'Michael Jackson'}]};
      if (pad.startsWith('/search/artist?q=C')) return {'data': [{'id': 2, 'name': 'Céline Dion'}]};
      if (pad.startsWith('/artist/1/albums')) return albums([('Thriller', '1982-11-30')]);
      if (pad.startsWith('/artist/2/albums')) {
        return albums([("Let's Talk About Love", '1997-11-14'), ('Bonjour, Pardon, Merci (Bon Entendeur Remix)', '2026-09-25')]);
      }
      if (pad.startsWith('/artist/2/related')) return {'data': [{'id': 30, 'name': 'Natasha St-Pier'}]};
      if (pad.startsWith('/artist/30/albums')) return albums([('Thérèse, ma petite voie', '2026-10-02')]);
      return {'data': []};
    });
    final u = await z.zoek(relevanteArtiesten(eigen, nuMs: _nu.millisecondsSinceEpoch),
        nu: _nu, alInBezit: {bezitssleutel('Céline Dion', 'Bonjour, Pardon, Merci (Bon Entendeur Remix)')});
    expect(_titels(u), ['Thérèse, ma petite voie']);
    expect(gevraagd, isNot(contains(startsWith('/artist/1/related'))));
  });

  group('bewaren', () {
    test('de lijst gaat heen en terug door JSON', () {
      final l = ReleasesLijst(123, [
        NieuweUitgave(
            album: const CatalogAlbum(7, 'Seven Tears', 'https://x/h.jpg', '2026-11-27', 10, 'album'),
            artiest: 'Sting',
            remixen: 2,
            score: 9.25),
        NieuweUitgave(
            album: const CatalogAlbum(8, 'Raye', null, '2026-10-01', 1, 'single'),
            artiest: 'Raye',
            lijktOp: 'Dua Lipa'),
      ]);
      final terug = ReleasesLijst.fromJson(jsonDecode(jsonEncode(l.toJson())))!;
      expect(terug.berekendMs, 123);
      expect(terug.uitgaven.map((u) => (u.album.id, u.album.title, u.album.recordType, u.artiest, u.lijktOp, u.remixen)),
          [(7, 'Seven Tears', 'album', 'Sting', null, 2), (8, 'Raye', 'single', 'Raye', 'Dua Lipa', 0)]);
      expect(ReleasesLijst.fromJson({'versie': 99, 'berekendMs': 1}), isNull);
    });

    test('de dienst rekent één keer tegelijk, bewaart, en leest het weer in', () async {
      final map = await Directory.systemTemp.createTemp('dm_releases');
      addTearDown(() => map.delete(recursive: true));
      var keren = 0;
      NieuweReleases maak() => NieuweReleases(
            zoeker: NieuweReleasesZoeker((url) async {
              keren++;
              if (url.contains('/search/artist')) {
                return {'data': [{'id': 3, 'name': 'Sting', 'nb_fan': 1}]};
              }
              if (url.contains('/artist/3/albums')) {
                return {
                  'data': [
                    {'id': 30, 'title': 'Seven Tears', 'release_date': '2026-11-27', 'record_type': 'album'},
                    {'id': 31, 'title': 'Ten Summoner\'s Tales', 'release_date': '1993-03-09', 'record_type': 'album'},
                  ],
                  'total': 2,
                };
              }
              return {'data': []};
            }),
            nummers: () => eigenArtiesten([
              EigenNummer(artiest: 'Sting', album: "Ten Summoner's Tales", titel: 'Fields of Gold', beurten: 5, laatstMs: 0),
            ]),
            bezit: () => const {},
            bestand: File('${map.path}/nieuwe_releases.json'),
            idsBestand: File('${map.path}/ids.json'),
            klok: () => _nu,
          );
      final d = maak();
      final twee = await Future.wait([d.ververs(), d.ververs()]);
      expect(identical(twee[0], twee[1]), isTrue);
      expect(_titels(d.lijst!.uitgaven), ['Seven Tears']);
      final vragen = keren;
      final opnieuw = maak();
      await opnieuw.laad();
      expect(_titels(opnieuw.lijst!.uitgaven), ['Seven Tears']);
      expect(opnieuw.verouderd, isFalse);
      expect(opnieuw.zoeker.ids.values.single.id, 3);
      expect(keren, vragen, reason: 'inlezen kost geen enkele vraag');
    });
  });
}
