/// De motor van Ontdek (Saber, 04-11-2026: "meer variatie … nog meer afgestemd op men bibliotheek, plus ook geen
/// dingen die ik al heb"; zijn keuzes in memory `ontdek-keuzes-04-11`). Zie `lib/ontdek.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:debridmusic/nieuwe_releases.dart' show EigenArtiest;
import 'package:debridmusic/ontdek.dart';
import 'package:debridmusic/ontdekvraag.dart';
import 'package:debridmusic/ontdek_bronnen.dart' show deezerNummers, omDeBeurt;
import 'package:debridmusic/recommend.dart' show RecTrack, RecommendService;
import 'package:flutter_test/flutter_test.dart';

const _dag = 24 * 3600 * 1000;
final _nu = DateTime(2026, 11, 4, 12);
final _nuMs = _nu.millisecondsSinceEpoch;

OntdekNummer _n(
  String artiest,
  String titel, {
  Ontdekbron bron = Ontdekbron.deezer,
  bool verder = false,
  String via = '',
  int seconden = 210,
}) => OntdekNummer(
  RecTrack(artiest, titel, null, seconds: seconden),
  bron: bron,
  verder: verder,
  via: via,
);

bool _niets(String _, String __) => false;

void main() {
  group('zaden gespreid zoals de bibliotheek', () {
    test('naar aandeel, elke hoek boven 3 % minstens één, samen precies het aantal', () {
      final q = verdeelZaden({'popsoul': 1000, 'rock': 200, 'Frans': 100, 'Eurodance': 100, 'overig': 50}, 14);
      expect(q.values.fold<int>(0, (s, n) => s + n), 14);
      expect(q['popsoul'], 9);
      expect(q['rock'], 2);
      expect([q['Frans'], q['Eurodance'], q['overig']], [1, 1, 1]);
    });

    test('DE VAL: een hoek die met zijn eerste zaad al boven zijn aandeel zit, krijgt de rest niet', () {
      // Frans heeft 0,97 zaden "recht" en kreeg er al één: een negatieve rest (−0,03) mocht niet als 0,97 tellen.
      final q = verdeelZaden({'popsoul': 1000, 'rock': 200, 'Frans': 100, 'Eurodance': 100, 'overig': 50}, 14);
      expect(q['Frans'], 1);
    });

    test('een kleine hoek onder de drempel alleen als er plaats over is', () {
      final q = verdeelZaden({'popsoul': 980, 'Turks': 20}, 3);
      expect(q, {'popsoul': 3});
      expect(verdeelZaden({}, 5), isEmpty);
    });

    test('kiesOntdekZaden: per hoek zijn quotum, zwaarste vaker, en aangevuld als een hoek te weinig heeft', () {
      final alle = [
        for (var i = 0; i < 20; i++) OntdekArtiest(naam: 'Pop $i', gewicht: 20.0 - i, hoek: 'popsoul', nummers: 50),
        for (var i = 0; i < 2; i++) OntdekArtiest(naam: 'Frans $i', gewicht: 3, hoek: 'Frans', nummers: 40),
        const OntdekArtiest(naam: 'Rock 0', gewicht: 0, hoek: 'rock', nummers: 200),
      ];
      final z = kiesOntdekZaden(alle, aantal: 10, toeval: math.Random(1));
      expect(z, hasLength(10));
      expect(z.where((a) => a.hoek == 'Frans'), isNotEmpty, reason: 'de Franse hoek krijgt zijn eigen zaad');
      expect(z.map((a) => a.naam).toSet(), hasLength(10), reason: 'geen artiest twee keer');
      expect(z.any((a) => a.naam == 'Rock 0'), isFalse, reason: 'gewicht nul is geen zaad');
    });

    test('verversen geeft andere zaden (gewogen getrokken, niet altijd dezelfde)', () {
      final alle = [for (var i = 0; i < 30; i++) OntdekArtiest(naam: 'A$i', gewicht: 10, hoek: 'popsoul', nummers: 10)];
      final a = kiesOntdekZaden(alle, aantal: 6, toeval: math.Random(1)).map((x) => x.naam).toSet();
      final b = kiesOntdekZaden(alle, aantal: 6, toeval: math.Random(2)).map((x) => x.naam).toSet();
      expect(a, isNot(equals(b)));
    });
  });

  group('gewicht: gedraaid, de laatste weken, duimen, hartjes, en wat er weggetikt werd', () {
    const basis = EigenArtiest(naam: 'Sade', beurten: 10, nummers: 17);
    test('elke reden telt erbij', () {
      final g = ontdekGewicht(basis, nuMs: _nuMs);
      expect(ontdekGewicht(basis, nuMs: _nuMs, groen: true), g + kGroenBonusVoorToets);
      expect(ontdekGewicht(basis, nuMs: _nuMs, favoriet: true), g + kFavorietBonus);
      final kort = EigenArtiest(naam: 'Sade', beurten: 10, nummers: 17, laatstMs: _nuMs - 3 * _dag);
      final maand = EigenArtiest(naam: 'Sade', beurten: 10, nummers: 17, laatstMs: _nuMs - 20 * _dag);
      expect(
        ontdekGewicht(kort, nuMs: _nuMs) - ontdekGewicht(maand, nuMs: _nuMs),
        kKortGeledenBonus,
        reason: 'de laatste twee weken tellen bovenop de dertig dagen',
      );
    });
    test('wegtikken weegt het zaad minder, hoogstens drie, nooit onder nul', () {
      final g = ontdekGewicht(basis, nuMs: _nuMs);
      expect(ontdekGewicht(basis, nuMs: _nuMs, wegVia: 1), g - 1);
      expect(ontdekGewicht(basis, nuMs: _nuMs, wegVia: 9), g - 3);
      expect(ontdekGewicht(const EigenArtiest(naam: 'x'), nuMs: _nuMs, wegVia: 3), 0);
    });
  });

  group('de hoek van een artiest', () {
    test('een taal uit de Last.fm-tags gaat voor, ook als de bestanden "Pop" zeggen', () {
      expect(hoekVan(['nederlandstalig', 'pop'], ['Pop']), 'Nederlandstalig');
    });
    test('zonder groep: de familie die de eigen genres het vaakst noemen; zonder iets: overig', () {
      expect(hoekVan(const [], ['Rock', 'Pop Rock', 'Pop']), 'rock');
      expect(hoekVan(const [], [null, '']), 'overig');
    });
  });

  group('samenstellen', () {
    test('DE KERN: één per artiest — geen zes keer You Spin Me Round', () {
      final uit = stelOntdekSamen(
        {
          Ontdekbron.deezer: [
            for (final t in [
              'You Spin Me Round (Like a Record)',
              'You Spin Me Round',
              'Brand New Lover',
              'Lover Come Back',
            ])
              _n('Dead Or Alive', t),
            _n('Visage', 'Fade To Grey'),
            _n('Visage', 'Fade To Grey (Single Version)'),
          ],
        },
        heb: _niets,
        nuMs: _nuMs,
      );
      expect(uit.map((n) => n.nummer.artist), ['Dead Or Alive', 'Visage']);
    });

    test('wat je hebt valt weg, maar de artiest mag terugkomen met een ander nummer', () {
      final uit = stelOntdekSamen(
        {
          Ontdekbron.deezer: [_n('Sinéad O\'Connor', 'Nothing Compares 2 U'), _n('Sinéad O\'Connor', 'Mandinka')],
        },
        heb: (a, t) => t == 'Nothing Compares 2 U',
        nuMs: _nuMs,
      );
      expect(uit.single.nummer.title, 'Mandinka');
    });

    test('geen remix, live, edit, karaoke, intro of te kort; kerst pas vanaf half november', () {
      final uit = stelOntdekSamen(
        {
          Ontdekbron.deezer: [
            _n('A', 'Song (Remix)'),
            _n('B', 'Song - Live'),
            _n('C', 'Intro'),
            _n('D', 'Kort', seconden: 60),
            _n('E', 'Last Christmas'),
            _n('F', 'Goed'),
          ],
        },
        heb: _niets,
        nuMs: _nuMs,
        nu: DateTime(2026, 11, 4),
      );
      expect(uit.map((n) => n.nummer.artist), ['F']);
    });

    test('weggetikt: dat nummer nooit meer, en een artiest die twee keer weg ging ook niet', () {
      final uit = stelOntdekSamen(
        {
          Ontdekbron.deezer: [_n('A', 'Een'), _n('B', 'Twee'), _n('C', 'Drie')],
        },
        heb: _niets,
        weg: {ontdekSleutel('A', 'Een')},
        wegArtiesten: {ontdekArtiest('B')},
        nuMs: _nuMs,
      );
      expect(uit.map((n) => n.nummer.artist), ['C']);
    });

    test('vooral dichtbij, elke vijfde plek iets verder (Saber: "1 op 5 iets verder")', () {
      final uit = stelOntdekSamen(
        {
          Ontdekbron.deezer: [
            for (var i = 0; i < 20; i++) _n('Dicht $i', 'Nummer $i'),
            for (var i = 0; i < 10; i++) _n('Ver $i', 'Ander $i', verder: true),
          ],
        },
        heb: _niets,
        nuMs: _nuMs,
        max: 20,
      );
      for (var i = 0; i < uit.length; i++) {
        expect(uit[i].verder, (i + 1) % kVerderElke == 0, reason: 'plek ${i + 1}');
      }
    });

    test('de bronnen om de beurt: Claude, Last.fm, Deezer', () {
      final uit = stelOntdekSamen(
        {
          Ontdekbron.deezer: [for (var i = 0; i < 3; i++) _n('D$i', 'd')],
          Ontdekbron.lastfm: [for (var i = 0; i < 3; i++) _n('L$i', 'l', bron: Ontdekbron.lastfm)],
          Ontdekbron.claude: [for (var i = 0; i < 3; i++) _n('C$i', 'c', bron: Ontdekbron.claude)],
        },
        heb: _niets,
        nuMs: _nuMs,
        verderElke: 0,
      );
      expect(uit.take(6).map((n) => n.bron), [
        Ontdekbron.claude,
        Ontdekbron.lastfm,
        Ontdekbron.deezer,
        Ontdekbron.claude,
        Ontdekbron.lastfm,
        Ontdekbron.deezer,
      ]);
    });

    test('niet twee na elkaar uit hetzelfde zaad als er een ander klaarstaat', () {
      final uit = stelOntdekSamen(
        {
          Ontdekbron.deezer: [_n('A', 'a', via: 'Sade'), _n('B', 'b', via: 'Sade'), _n('C', 'c', via: 'Seal')],
        },
        heb: _niets,
        nuMs: _nuMs,
        verderElke: 0,
      );
      expect(uit.map((n) => n.via), ['Sade', 'Seal', 'Sade']);
    });

    test('wat de laatste twee weken al getoond werd, gaat achteraan', () {
      final uit = stelOntdekSamen(
        {
          Ontdekbron.deezer: [_n('A', 'a'), _n('B', 'b'), _n('C', 'c')],
        },
        heb: _niets,
        getoondOp: {ontdekSleutel('A', 'a'): _nuMs - 2 * _dag},
        nuMs: _nuMs,
        verderElke: 0,
      );
      expect(uit.map((n) => n.nummer.artist), ['B', 'C', 'A']);
      final oud = stelOntdekSamen(
        {
          Ontdekbron.deezer: [_n('A', 'a'), _n('B', 'b')],
        },
        heb: _niets,
        getoondOp: {ontdekSleutel('A', 'a'): _nuMs - 20 * _dag},
        nuMs: _nuMs,
        verderElke: 0,
      );
      expect(oud.first.nummer.artist, 'A', reason: 'na twee weken mag hij weer vooraan');
    });

    test('hoogstens het gevraagde aantal', () {
      final uit = stelOntdekSamen(
        {
          Ontdekbron.deezer: [for (var i = 0; i < 200; i++) _n('A$i', 'x')],
        },
        heb: _niets,
        nuMs: _nuMs,
      );
      expect(uit, hasLength(kOntdekLengte));
    });
  });

  group('in bezit', () {
    test('elke artiest uit een rij telt apart: "Circle Of Life" van Elton John staat al op de Lion King-plaat', () {
      final s = bezitSleutelsVan('Elton John, Tim Rice, Hans Zimmer', 'Circle Of Life').toSet();
      expect(s, contains(ontdekSleutel('Elton John', 'Circle Of Life')));
      expect(s, contains(ontdekSleutel('Elton John, Tim Rice, Hans Zimmer', 'Circle Of Life')));
      expect(bezitSleutelsVan('Sade', 'Smooth Operator'), [ontdekSleutel('Sade', 'Smooth Operator')]);
    });
    test('de sleutel kijkt niet naar versie of gast', () {
      expect(
        ontdekSleutel('Dead or Alive', 'You Spin Me Round (Like a Record)'),
        ontdekSleutel('Dead Or Alive', 'You Spin Me Round'),
      );
      expect(ontdekSleutel('Art of Noise feat. Duane Eddy', 'Peter Gunn'), ontdekSleutel('Art of Noise', 'Peter Gunn'));
    });
  });

  group('wegtikken onthouden', () {
    test('zet, terug, artiest na twee keer, het zaad telt, en het overleeft een bestand', () {
      final w = OntdekWeg()
        ..zet('Sinéad O\'Connor', 'Troy', via: 'Sade', nuMs: _nuMs)
        ..zet('Sinéad O\'Connor', 'Mandinka', via: 'Sade', nuMs: _nuMs);
      expect(w.artiesten(nuMs: _nuMs), {ontdekArtiest('Sinéad O\'Connor')});
      expect(w.via('Sade'), 2);
      expect(w.artiesten(nuMs: _nuMs + 91 * _dag), isEmpty, reason: 'na negentig dagen mag de artiest terug');
      final terug = OntdekWeg.fromJson(jsonDecode(jsonEncode(w.toJson())));
      expect(terug.nummers, w.nummers);
      expect(terug.namen(), contains('Sinéad O\'Connor — Troy'));
      expect(terug.terug('Sinéad O\'Connor', 'Troy'), isTrue);
      expect(terug.artiesten(nuMs: _nuMs), isEmpty, reason: 'één over: de artiest mag weer');
    });
  });

  group('je artiesten en je profiel', () {
    OntdekEigen e(
      String a,
      String t, {
      int beurten = 0,
      int laatst = 0,
      bool groen = false,
      bool fav = false,
      String? genre,
      int? jaar,
    }) => (
      artiest: a,
      album: '',
      titel: t,
      genre: genre,
      jaar: jaar,
      beurten: beurten,
      laatstMs: laatst,
      groen: groen,
      favoriet: fav,
    );

    test('zaadnummers: groen of hartje eerst, dan het meest gedraaid', () {
      final a = ontdekArtiesten(
        [e('Sade', 'Veel', beurten: 40), e('Sade', 'Groen', beurten: 1, groen: true), e('Sade', 'Weinig', beurten: 2)],
        tags: (_) => const [],
        nuMs: _nuMs,
      );
      expect(a.single.zaadNummers, ['Groen', 'Veel', 'Weinig']);
      expect(a.single.nummers, 3);
    });

    test('het profiel: wie zwaar weegt, wat recent is, wat groen is, en de verdeling in procenten', () {
      final ns = [
        e('Sade', 'A', beurten: 40, laatst: _nuMs - _dag, genre: 'Soul', jaar: 1985),
        e('Clouseau', 'B', groen: true, genre: 'Pop', jaar: 1995),
        e('Clouseau', 'C', jaar: 1996),
      ];
      final as = ontdekArtiesten(ns, tags: (a) => a == 'Clouseau' ? ['nederlandstalig'] : const [], nuMs: _nuMs);
      final p = ontdekProfiel(ns, as, nuMs: _nuMs, weggetikt: const ['X — Y']);
      expect(p.zwaarst.first, 'Sade');
      expect(p.recent, ['Sade — A']);
      expect(p.groen, ['Clouseau — B']);
      expect(p.hoeken, {'popsoul': 33, 'Nederlandstalig': 67});
      expect(p.decennia, {1980: 33, 1990: 67});
      expect(p.weggetikt, ['X — Y']);
    });
  });

  group('de vraag aan Claude', () {
    test('het schema: elk veld ook in required', () {
      final items = ((ontdekSchema()['properties'] as Map)['nummers'] as Map)['items'] as Map;
      expect((items['required'] as List).toSet(), (items['properties'] as Map).keys.toSet());
    });
    test('de vraag noemt de regels: bestaand, één per artiest, de verhouding, precies acht verder', () {
      final v = ontdekPrompt(const OntdekProfiel(zwaarst: ['Sade'], hoeken: {'popsoul': 60}, decennia: {1990: 40}));
      expect(v, contains('BESTAAN'));
      expect(v, contains('Elke artiest hoogstens één keer'));
      expect(v, contains('popsoul 60%'));
      expect(v, contains('1990s 40%'));
      expect(v, contains('Precies $kOntdekVragenVerder nummers'));
    });
    test('uitlezen: lege en dubbele artiesten weg, een te lange reden ingekort', () {
      final l = leesOntdekVoorstellen({
        'nummers': [
          {'artiest': 'Seal', 'titel': 'Crazy', 'reden': 'Voor wie Sade draait', 'verder': false},
          {'artiest': 'seal', 'titel': 'Kiss', 'reden': '', 'verder': false},
          {'artiest': '', 'titel': 'x', 'reden': '', 'verder': false},
          {
            'artiest': 'Sault',
            'titel': 'Wildfires',
            'reden': 'een twee drie vier vijf zes zeven acht negen tien',
            'verder': true,
          },
        ],
      });
      expect(l.map((v) => v.artiest), ['Seal', 'Sault']);
      expect(l.last.verder, isTrue);
      expect(l.last.reden, 'een twee drie vier vijf zes zeven acht…');
    });
  });

  group('de dienst op de pc', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_ontdek_'));
    tearDown(() {
      if (map.existsSync()) map.deleteSync(recursive: true);
    });

    OntdekVoorJou dienst({
      required DateTime Function() klok,
      required List<int> claudeVragen,
      List<OntdekNummer>? deezer,
    }) => OntdekVoorJou(
      artiesten: (_) => [
        for (var i = 0; i < 20; i++) OntdekArtiest(naam: 'Eigen $i', gewicht: 5, hoek: 'popsoul', nummers: 5),
      ],
      heb: (a, t) => a == 'Al' && t == 'Heb',
      bestand: File('${map.path}/ontdek.json'),
      wegBestand: File('${map.path}/ontdek_weg.json'),
      deezer: (_) async => deezer ?? [for (var i = 0; i < 60; i++) _n('Deezer $i', 'd$i'), _n('Al', 'Heb')],
      claude: (_) async {
        claudeVragen.add(1);
        return [for (var i = 0; i < 12; i++) _n('Claude $i', 'c$i', bron: Ontdekbron.claude)];
      },
      klok: klok,
      toeval: math.Random(3),
    );

    test('rekent, bewaart, en laadt terug', () async {
      final vragen = <int>[];
      final d = dienst(klok: () => _nu, claudeVragen: vragen);
      final l = await d.ververs();
      expect(l!.nummers, isNotEmpty);
      expect(l.nummers.any((n) => n.nummer.artist == 'Al'), isFalse, reason: 'wat je hebt komt er niet in');
      expect(l.nummers.where((n) => n.bron == Ontdekbron.claude), hasLength(12));
      final weer = dienst(klok: () => _nu, claudeVragen: vragen);
      await weer.laad();
      expect(weer.lijst!.nummers.map((n) => n.sleutel), l.nummers.map((n) => n.sleutel));
      expect(weer.verouderd, isFalse);
    });

    test(
      'Claude één keer per dag; verversen gebruikt zijn pool, en vraagt pas opnieuw als die op is (hoogstens twee)',
      () async {
        final vragen = <int>[];
        var klok = _nu;
        final d = dienst(klok: () => klok, claudeVragen: vragen);
        await d.ververs();
        expect(vragen, hasLength(1));
        await d.ververs();
        expect(vragen, hasLength(2), reason: 'de pool van 12 stond al helemaal in de eerste lijst');
        await d.ververs();
        expect(vragen, hasLength(2), reason: 'hoogstens twee per dag');
        klok = _nu.add(const Duration(days: 1));
        expect(d.verouderd, isTrue, reason: 'een nieuwe dag, een nieuwe lijst');
        await d.ververs();
        expect(vragen, hasLength(3));
      },
    );

    test('een grote pool die nog niet op is: verversen vraagt Claude niet opnieuw', () async {
      final vragen = <int>[];
      final d = OntdekVoorJou(
        artiesten: (_) => [for (var i = 0; i < 20; i++) OntdekArtiest(naam: 'E$i', gewicht: 5, hoek: 'popsoul')],
        heb: _niets,
        bestand: File('${map.path}/ontdek.json'),
        wegBestand: File('${map.path}/ontdek_weg.json'),
        deezer: (_) async => [for (var i = 0; i < 60; i++) _n('Deezer $i', 'd$i')],
        claude: (_) async {
          vragen.add(1);
          return [for (var i = 0; i < 40; i++) _n('Claude $i', 'c$i', bron: Ontdekbron.claude)];
        },
        klok: () => _nu,
        toeval: math.Random(5),
      );
      await d.ververs();
      expect(d.lijst!.nummers.take(kOntdekGetoond).where((n) => n.bron == Ontdekbron.claude).length, lessThan(30),
          reason: 'de helft van de eerste vijftig, de rest van de pool blijft voor straks');
      await d.ververs();
      expect(vragen, hasLength(1), reason: 'nog genoeg van Claude dat niet getoond is: geen tweede vraag');
    });

    test('wegtikken: meteen uit wat een scherm ziet, bewaard, en ongedaan te maken', () async {
      final d = dienst(klok: () => _nu, claudeVragen: []);
      await d.ververs();
      final eerste = d.zichtbaar.first;
      await d.zetWeg(eerste.nummer.artist, eerste.nummer.title, via: 'Sade');
      expect(d.zichtbaar.map((n) => n.sleutel), isNot(contains(eerste.sleutel)));
      final weer = dienst(klok: () => _nu, claudeVragen: []);
      await weer.laad();
      expect(weer.weg.nummers, contains(eerste.sleutel));
      await weer.zetWeg(eerste.nummer.artist, eerste.nummer.title, terug: true);
      expect(weer.zichtbaar.map((n) => n.sleutel), contains(eerste.sleutel));
    });

    test('niets gevonden (en geen pool van Claude): de vorige lijst blijft', () async {
      final d = OntdekVoorJou(
        artiesten: (_) => [const OntdekArtiest(naam: 'x', gewicht: 1, hoek: 'popsoul')],
        heb: _niets,
        bestand: File('${map.path}/ontdek.json'),
        wegBestand: File('${map.path}/ontdek_weg.json'),
        deezer: (_) async => [for (var i = 0; i < 5; i++) _n('D$i', 'd')],
        klok: () => _nu,
      );
      await d.ververs();
      final voor = d.lijst;
      final leeg = OntdekVoorJou(
        artiesten: (_) => [const OntdekArtiest(naam: 'x', gewicht: 1, hoek: 'popsoul')],
        heb: _niets,
        bestand: File('${map.path}/ontdek.json'),
        wegBestand: File('${map.path}/ontdek_weg.json'),
        deezer: (_) async => const [],
        klok: () => _nu,
      );
      await leeg.laad();
      final na = await leeg.ververs();
      expect(na!.nummers.map((n) => n.sleutel), voor!.nummers.map((n) => n.sleutel));
    });
  });

  // Wat de meting van 04-11-2026 op Sabers bibliotheek liet zien.
  group('na de meting', () {
    test('één per lied over artiesten heen: geen twee covers van "The Rhythm of the Night"', () {
      final uit = stelOntdekSamen({
        Ontdekbron.deezer: [
          _n('Neptunica', 'The Rhythm of the Night'),
          _n('Sean Finn', 'The Rhythm of the Night'),
          _n('R.E.M.', 'Drive'),
          _n('The Cars', 'Drive'),
        ],
      }, heb: _niets, nuMs: _nuMs, verderElke: 0);
      expect(uit.map((n) => n.nummer.artist), ['Neptunica', 'R.E.M.', 'The Cars'],
          reason: 'een korte titel ("Drive") zegt niets over het lied');
    });

    test('een cover van een lied dat je al hebt, heb je al', () {
      final bezit = {...bezitSleutelsVan('Corona', 'The Rhythm of the Night (Radio Edit)')};
      expect(inBezit(bezit, 'Sean Finn', 'The Rhythm of the Night'), isTrue);
      expect(inBezit(bezit, 'Corona', 'Baby Baby'), isFalse);
      expect(ontdekLied('Drive'), isNull);
      expect(ontdekLied('Love Is All Around (From "Four Weddings")'), ontdekLied('Love Is All Around'));
    });

    test('Deezer om de beurt per zaad, en alleen nummers van de kandidaat zelf', () {
      RecTrack t(String a, String titel) => RecTrack(a, titel, null, seconds: 200);
      final uit = deezerNummers((
        dichtbij: [
          (kandidaat: (id: 1, naam: 'Pop A', score: 9.0, via: ['Rihanna']), toppers: [t('Pop A', 'a')]),
          (kandidaat: (id: 2, naam: 'Pop B', score: 8.0, via: ['Rihanna']), toppers: [t('Pop B', 'b')]),
          (
            kandidaat: (id: 3, naam: 'Garou', score: 3.0, via: ['Céline Dion']),
            toppers: [t('Céline Dion', 'Sous le vent'), t('Garou', 'Belle')],
          ),
        ],
        verder: [
          (via: 'Pop A', naam: 'Ver', toppers: [t('Ver', 'v')]),
        ],
      ));
      expect(uit.map((n) => '${n.nummer.artist}|${n.via}'),
          ['Pop A|Rihanna', 'Garou|Céline Dion', 'Pop B|Rihanna', 'Ver|Pop A'],
          reason: 'Garou krijgt zijn beurt voor de tweede van Rihanna; "Sous le vent" is van Céline Dion, niet van hem');
      expect(uit.last.verder, isTrue);
      expect(uit.first.waarom, 'Lijkt op Rihanna');
    });

    test('"iets verder" uit elk zaad zijn beste kandidaat, niet de bovenste van één zaad', () {
      ({int id, String naam, double score, List<String> via}) k(int id, String zaad) =>
          (id: id, naam: 'K$id', score: 10.0 - id, via: [zaad]);
      final top = [k(1, 'Katy Perry'), k(2, 'Katy Perry'), k(3, 'Katy Perry'), k(4, 'Alizée'), k(5, 'Snap!')];
      expect(RecommendService.eenPerZaad(top, 3).map((x) => x.id), [1, 4, 5]);
      expect(RecommendService.eenPerZaad(top, 4).map((x) => x.id), [1, 4, 5, 2], reason: 'plaats over: op score');
    });

    test('omDeBeurt', () {
      expect(
          omDeBeurt([
            [1, 2, 3],
            [4],
            [5, 6],
          ]),
          [1, 4, 5, 2, 6, 3]);
    });
  });
}

/// [kGroenBonus] uit aanbevolen.dart, zonder die hele bibliotheek hier in te halen.
const double kGroenBonusVoorToets = 3;
