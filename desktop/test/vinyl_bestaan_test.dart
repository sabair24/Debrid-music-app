// De sectie "Vinyl & LP" en wat de app weet over vinyl per nummer (Saber, 12-11-2026: "ik wil bij de discographie van de
// artisten een volledige nieuwe sectie, Vinyl en Lp"). De persingen hieronder zijn ingekort uit de echte Discogs-uitslag
// van Spice Girls (artist_id 47109, format=Vinyl, type=release) van 12-11-2026.
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/vinyl_bestaan.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Map<String, dynamic> _p(int id, int master, String titel, List<String> formaat, {Object? jaar, String? hoes}) => {
      'id': id,
      'master_id': master,
      'title': 'Spice Girls - $titel',
      'format': formaat,
      'year': jaar ?? '',
      if (hoes != null) 'cover_image': hoes,
    };

final _spice = [
  _p(1, 10, 'Spice', ['Vinyl', 'LP', 'Album'], jaar: '1996', hoes: 'https://i.discogs.com/spice.jpg'),
  _p(2, 10, 'Spice', ['Vinyl', 'LP', 'Album', 'Reissue'], jaar: '2024'),
  _p(3, 10, 'Spice', ['Vinyl', 'LP', 'Album', 'Promo'], jaar: '1996'),
  _p(4, 20, 'Wannabe', ['Vinyl', '12"', '33 ⅓ RPM', 'Single'], jaar: '1996'),
  _p(5, 20, 'Wannabe', ['Vinyl', '7"', '45 RPM', 'Single'], jaar: '2026'),
  _p(6, 20, 'Wannabe', ['Vinyl', '12"', 'Unofficial Release'], jaar: '2015'),
  _p(7, 30, 'Wannabe 25', ['Vinyl', '12"', 'EP', 'Promo'], jaar: '2021'),
  _p(8, 0, 'Viva Forever', ['Vinyl', '12"', 'Single Sided', 'Unofficial Release'], jaar: '2015'),
  _p(9, 40, 'Spiceworld', ['Vinyl', 'LP', 'Album'], jaar: 1997),
];

/// Een tracklijst voor elke plaat in [_spice]: dan weet de app van elk nummer of het op vinyl staat.
const _alleNummers = {
  10: ['Wannabe', 'Love Thing'],
  20: ['Wannabe (Radio Edit)', 'Wannabe (Dave Way Alternative Mix)'],
  30: ['Wannabe (25 Mix)'],
  40: ['Spice Up Your Life'],
};

class _NepBron implements VinylBron {
  _NepBron({this.id = 47109, List<Map<String, dynamic>>? persingen, this.nummers = const {}})
      : _persingen = persingen ?? _spice;
  int? id;
  List<Map<String, dynamic>>? _persingen;
  final Map<int, List<String>> nummers;
  int persingVragen = 0;
  final List<int> plaatVragen = [];

  @override
  Future<int?> discogsId(String artiest) async => id;

  @override
  Future<List<Map<String, dynamic>>?> persingen(int discogsId) async {
    persingVragen++;
    return _persingen;
  }

  @override
  Future<Map<String, dynamic>?> plaat({int? master, int? release}) async {
    plaatVragen.add(master ?? release ?? 0);
    final n = nummers[master ?? release];
    return n == null ? null : {'tracklist': [for (final t in n) {'type_': 'track', 'title': t}]};
  }
}

void main() {
  group('de persingen per plaat', () {
    test('DE KERN: per master samen, LP of single, promo apart, bootleg weg', () {
      final platen = {for (final p in vinylPlatenUit(_spice)) p.titel: p};
      expect(platen.keys, unorderedEquals(['Spice', 'Wannabe', 'Wannabe 25', 'Spiceworld']),
          reason: 'Viva Forever bestaat alleen als bootleg');
      final spice = platen['Spice']!;
      expect(spice.vorm, VinylVorm.lp);
      expect(spice.persingen, 2, reason: 'de promo telt niet als gewone persing');
      expect(spice.promos, 1);
      expect((spice.jaarVan, spice.jaarTot), (1996, 2024));
      expect(spice.master, 10);
      expect(spice.hoes, 'https://i.discogs.com/spice.jpg');
      final wannabe = platen['Wannabe']!;
      expect(wannabe.vorm, VinylVorm.single);
      expect(wannabe.persingen, 2, reason: 'de bootleg van 2015 telt niet mee');
      expect(wannabe.formaten, {'12"', '7"'});
      expect((wannabe.jaarVan, wannabe.jaarTot), (1996, 2026));
      expect(platen['Wannabe 25']!.getoond, isFalse, reason: 'alleen als promo: niet in de sectie, wel om te zoeken');
      expect(platen['Spiceworld']!.jaarVan, 1997, reason: 'een jaartal als getal mag ook');
    });

    test('in de sectie: LP\'s en singles apart, oudste eerst, zonder wat alleen promo is', () {
      // Omgekeerd aangeleverd: de volgorde komt van het jaar, niet van Discogs.
      final k = VinylKennis(discogsId: 47109, gemetenMs: 0, platen: vinylPlatenUit(_spice.reversed.toList()));
      expect(k.lps.map((p) => p.titel), ['Spice', 'Spiceworld']);
      expect(k.singles.map((p) => p.titel), ['Wannabe']);
    });

    test('de regel onder de tegel', () {
      final platen = {for (final p in vinylPlatenUit(_spice)) p.titel: p};
      expect(vinylOnderregel(platen['Spice']!), 'LP · 2 persingen · 1996–2024');
      expect(vinylOnderregel(platen['Wannabe']!), '12" · 7" · 2 persingen · 1996–2026');
      expect(vinylOnderregel(platen['Spiceworld']!), 'LP · 1 persing · 1997');
    });

    test('de tracklijst: nummers, ook onder een index; kopjes niet', () {
      expect(
          tracklijstUit({
            'tracklist': [
              {'type_': 'heading', 'title': 'Side A'},
              {'type_': 'track', 'title': 'Wannabe'},
              {
                'type_': 'index',
                'title': 'Medley',
                'sub_tracks': [
                  {'title': 'Say You\'ll Be There'},
                  {'title': '2 Become 1'}
                ]
              },
            ]
          }),
          ['Wannabe', 'Say You\'ll Be There', '2 Become 1']);
    });
  });

  group('bestaat dit nummer op vinyl?', () {
    test('DE KERN: dezelfde versie telt, een remix alleen voor zichzelf', () {
      expect(vinylNummerSleutel('Wannabe (Radio Edit)'), vinylNummerSleutel('Wannabe'));
      expect(vinylNummerSleutel('Wannabe - Radio Edit'), vinylNummerSleutel('Wannabe'));
      expect(vinylNummerSleutel('Wannabe (Single Version)'), vinylNummerSleutel('Wannabe'));
      expect(vinylNummerSleutel('Wannabe (Remastered 2011)'), vinylNummerSleutel('Wannabe'));
      expect(vinylNummerSleutel('Wannabe - 2011 Remaster'), vinylNummerSleutel('Wannabe'));
      expect(vinylNummerSleutel('Wannabe (feat. Jason Mraz)'), vinylNummerSleutel('Wannabe'));
      expect(vinylNummerSleutel('Wannabe feat. Jason Mraz'), vinylNummerSleutel('Wannabe'));
      expect(vinylNummerSleutel('Wannabe (Dave Way Alternative Mix)'), isNot(vinylNummerSleutel('Wannabe')));
      expect(vinylNummerSleutel('Wannabe (Live)'), isNot(vinylNummerSleutel('Wannabe')));
      expect(vinylNummerSleutel('Wannabe - Acoustic'), isNot(vinylNummerSleutel('Wannabe')));
    });

    test('op de LP, op de single (ook een dubbele A-kant), en niet', () {
      final k = VinylKennis(discogsId: 1, gemetenMs: 0, platen: [
        const VinylPlaat(master: 10, titel: 'Spice', vorm: VinylVorm.lp, persingen: 2, nummers: ['Wannabe', 'Love Thing']),
        const VinylPlaat(master: 20, titel: 'Wannabe / 2 Become 1', vorm: VinylVorm.single, persingen: 1, nummers: [
          'Wannabe (Radio Edit)',
          'Wannabe (Dave Way Alternative Mix)',
        ]),
      ]);
      expect(k.bestaat('Love Thing'), isTrue);
      expect(k.bestaat('2 Become 1 - Single Version'), isTrue, reason: 'de A-kant in de titel van de single');
      expect(k.bestaat('Wannabe (Dave Way Alternative Mix)'), isTrue);
      expect(k.bestaat('Wannabe (Vocalpella)'), isFalse, reason: 'die remix staat op geen enkele plaat');
      expect(k.bestaat('Viva Forever'), isFalse);
    });

    test('een plaat zonder tracklijst: geen nee, want de app weet het niet', () {
      final k = VinylKennis(discogsId: 1, gemetenMs: 0, platen: const [
        VinylPlaat(master: 10, titel: 'Spice', vorm: VinylVorm.lp, persingen: 2),
        VinylPlaat(master: 20, titel: 'Wannabe', vorm: VinylVorm.single, persingen: 1, nummers: []),
      ]);
      expect(k.bestaat('Wannabe'), isTrue, reason: 'de single zegt het al');
      expect(k.bestaat('Viva Forever'), isNull);
    });

    test('een artiest zonder vinyl: nee, voor elk nummer', () {
      const k = VinylKennis(discogsId: 1, gemetenMs: 0, platen: []);
      expect(k.bestaat('Anything'), isFalse);
      expect(k.lps, isEmpty);
    });
  });

  group('de dienst', () {
    test('DE KERN: eerst de platen, dan de tracklijsten; een week uit het geheugen', () async {
      final d = VinylBestaan();
      final bron = _NepBron(nummers: {10: ['Wannabe', 'Love Thing'], 40: ['Spice Up Your Life']});
      VinylKennis? voorlopig;
      final k = await d.voor('Spice Girls', bron, opPlaten: (v) => voorlopig = v);
      expect(voorlopig!.platen.every((p) => p.nummers == null), isTrue, reason: 'de sectie hoeft niet te wachten');
      expect(k!.platen, hasLength(4));
      expect(d.bestaatOpVinyl('Spice Girls', 'Love Thing'), isTrue);
      expect(d.bestaatOpVinyl('spice girls', 'Spice Up Your Life (Radio Edit)'), isTrue, reason: 'naam zonder hoofdletters');
      await d.voor('Spice Girls', bron);
      expect(bron.persingVragen, 1, reason: 'binnen de week niet opnieuw');
      await d.voor('Spice Girls', bron, vers: true);
      expect(bron.persingVragen, 2);
      expect(bron.plaatVragen.where((m) => m == 10), hasLength(1),
          reason: 'een tracklijst die er al is, wordt niet opnieuw gevraagd');
    });

    test('ouder dan een week: opnieuw bij Discogs', () async {
      final d = VinylBestaan();
      final bron = _NepBron();
      await d.voor('Spice Girls', bron);
      // Zelf de tijd terugzetten via een bewaard bestand van acht dagen oud.
      final map = await Directory.systemTemp.createTemp('vinyl_oud');
      addTearDown(() => map.delete(recursive: true));
      final f = File('${map.path}/vinyl_bestaan.json');
      final oud = VinylKennis(
          discogsId: 47109,
          gemetenMs: DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch,
          platen: vinylPlatenUit(_spice));
      await f.writeAsString(jsonEncode({'spice girls': oud.toJson()}));
      final terug = VinylBestaan(bestand: f);
      final bron2 = _NepBron();
      await terug.voor('Spice Girls', bron2);
      expect(bron2.persingVragen, 1);
      expect(oud.isVers, isFalse);
    });

    test('Discogs weet het niet: wat er was blijft, en zonder iets is het antwoord null', () async {
      final d = VinylBestaan();
      final weg = _NepBron(id: null);
      expect(await d.voor('Celeste', weg), isNull);
      expect(d.bestaatOpVinyl('Celeste', 'Strange'), isNull, reason: 'geen antwoord is geen nee');
      final bron = _NepBron();
      await d.voor('Spice Girls', bron);
      bron._persingen = null;
      final k = await d.voor('Spice Girls', bron, vers: true);
      expect(k!.platen, hasLength(4), reason: 'een mislukte vraag gooit niets weg');
    });

    test('bewaren en inlezen', () async {
      final map = await Directory.systemTemp.createTemp('vinyl_bewaar');
      addTearDown(() => map.delete(recursive: true));
      final f = File('${map.path}/vinyl_bestaan.json');
      final d = VinylBestaan(bestand: f);
      await d.voor('Spice Girls', _NepBron(nummers: {10: ['Love Thing']}));
      await d.bewaarNu();
      final terug = VinylBestaan(bestand: f);
      await terug.laad();
      expect(terug.bekend('Spice Girls')!.platen, hasLength(4));
      expect(terug.bestaatOpVinyl('Spice Girls', 'Love Thing'), isTrue);
    });
  });

  group('zoeken', () {
    Future<VinylBestaan> metSpice() async {
      final d = VinylBestaan();
      await d.voor('Spice Girls', _NepBron(nummers: _alleNummers));
      return d;
    }

    test('DE KERN: een vinylrip van een nummer dat nooit op vinyl verscheen, valt weg; de rest blijft', () async {
      final d = await metSpice();
      const paden = [
        'Muziek/Spice Girls - Spice (1996) [Vinyl 24-96]/05 - Viva Forever.flac',
        'Muziek/Spice Girls - Spice (1996) [FLAC]/05 - Viva Forever.flac',
      ];
      // 'Viva Forever' staat op geen van de platen (alleen als bootleg, en die tellen niet).
      expect(d.bekend('Spice Girls')!.platen.where((p) => p.nummers == null), isEmpty,
          reason: 'van elke plaat is de tracklijst bekend, anders zegt de app geen nee');
      expect(zonderNepVinyl(paden, 'Spice Girls', 'Viva Forever', (p) => p, dienst: d), [paden[1]]);
      expect(zonderNepVinyl(paden, 'Spice Girls', 'Love Thing', (p) => p, dienst: d), paden,
          reason: 'Love Thing staat op de LP: vinyl mag');
      expect(zonderNepVinyl(paden, 'Celeste', 'Strange', (p) => p, dienst: d), paden,
          reason: 'niets bekend over Celeste: geen antwoord is geen nee');
      expect(zonderNepVinyl(paden, '', 'Viva Forever', (p) => p, dienst: d), paden);
    });

    test('vóór een vinylzoektocht vraagt de app Discogs eerst', () async {
      final d = VinylBestaan();
      final bron = _NepBron(nummers: {..._alleNummers, 40: ['Stop']});
      vinylBronVoorZoeken = () => bron;
      addTearDown(() => vinylBronVoorZoeken = null);
      expect(await vinylVoorNummer('Spice Girls', 'Stop', dienst: d), isTrue);
      expect(await vinylVoorNummer('Spice Girls', 'Viva Forever', dienst: d), isFalse);
      expect(bron.persingVragen, 1, reason: 'binnen de week één keer');
      vinylBronVoorZoeken = null;
      expect(await vinylVoorNummer('Milow', 'Ayo Technology', dienst: d), isNull, reason: 'zonder bron vraagt hij niets');
    });

    test('het menu grijs: alleen als GEEN van de nummers op vinyl bestaat', () async {
      final d = await metSpice();
      expect(geenVinylBekend([(artiest: 'Spice Girls', titel: 'Viva Forever')], dienst: d), isTrue);
      expect(
          geenVinylBekend(
              [(artiest: 'Spice Girls', titel: 'Viva Forever'), (artiest: 'Spice Girls', titel: 'Wannabe')],
              dienst: d),
          isFalse);
      expect(geenVinylBekend([(artiest: 'Celeste', titel: 'Strange')], dienst: d), isFalse, reason: 'onbekend');
      expect(geenVinylBekend(const [], dienst: d), isFalse);
    });

    test('aangesloten: elke automatische keuze, de vinylvragen en het menu', () {
      final o = _bron('lib/online.dart');
      expect(RegExp(r'zonderNepVinyl\(').allMatches(o).length, 4,
          reason: 'de gewone keuze, opwaarderen, de radio en de wensen/soorten/jacht');
      expect(o, contains("          zonderNepVinyl(candidates, authority?.artist ?? '', authority?.title ?? '', (f) => f.filename),"));
      expect(o, contains('        if (await vinylVoorNummer(v.artiest, v.titel) == false) geen.add(v);'));
      expect(o, contains('          vragen.verwijder(v.pad);'));
      final m = _bron('lib/main.dart');
      expect(m, contains('  vinylBronVoorZoeken = () => DiscographyService(CatalogService(), musicbrainz, DiscogsService(settings)).vinylBron();'));
      expect(m, contains('            uit: s == Kopiesoort.vinyl && geenVinyl),'));
    });
  });

  test('aangesloten: Discogs op het artiestnummer en vers, de artiestpagina toont de sectie na de discografie', () {
    final dg = _bron('lib/discogs.dart');
    expect(dg, contains("'https://api.discogs.com/database/search?artist_id=\$artistId&format=Vinyl&type=release&per_page=100&page=\$p',\n          vers: true);"));
    expect(dg, contains('    final cached = vers ? null : await _readCache(url);'));
    final ds = _bron('lib/discography_service.dart');
    expect(ds, contains('      _svc.discogs.available ? _svc.discogsIdVoor(artiest, bekendeMbid: _mbid) : null;'));
    final m = _bron('lib/main.dart');
    expect(m, contains('    unawaited(_laadVinyl(svc, ref.isMb ? ref.id : null));\n'));
    expect(m, contains('          ..._vinylSectie(_eigenVinyl(lib, mine)),\n'));
    final na = m.indexOf('          ..._vinylSectie(_eigenVinyl(lib, mine)),');
    expect(na, greaterThan(m.indexOf('            for (final blok in blokken) ...[')), reason: 'ná de discografie');
    expect(na, lessThan(m.indexOf("child: _sectionTitle('Over \${widget.artist.name}',")), reason: 'vóór de biografie');
  });
}

