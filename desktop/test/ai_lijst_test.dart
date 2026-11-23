// AI-afspeellijsten (Saber, 23-11-2026): "ik wil dat AI ook afspeel lijsten kan maken, met op voorhand een lijst zonder
// iets te downloaden om te kijken wat hij voorstelt, eventueel liedjes eruit haalt of toevoegd". Zijn keuzes: vooral
// nieuw, hoogstens 2 per artiest, de opbouw van de AI, een reserve voor ↻ en de mix, bijsturen toont eerst het verschil.
import 'dart:io';

import 'package:debridmusic/ai_lijst.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _n(String a, String t, {String h = 'Klassiekers', int j = 1960}) =>
    {'artiest': a, 'titel': t, 'jaar': j, 'hoek': h};

LijstNummer _l(String a, String t, {String h = 'Klassiekers', LijstBron b = LijstBron.deezer}) =>
    LijstNummer(artiest: a, titel: t, hoek: h, bron: b);

AiLijstVoorstel _v(List<LijstNummer> nummers, {List<LijstNummer>? reserve, int? aantal}) => AiLijstVoorstel(
    naam: 'Kerst',
    zin: 'kerstliedjes',
    hoeken: const [(naam: 'Klassiekers', aandeel: 60), (naam: 'Modern', aandeel: 40)],
    nummers: nummers,
    reserve: reserve ?? [],
    aantal: aantal ?? nummers.length);

void main() {
  group('het antwoord lezen', () {
    test('DE KERN: dubbels weg, hoogstens twee per artiest (de rest naar de reserve), het gevraagde aantal', () {
      final v = leesAiLijst({
        'naam': 'Kerst · klassiek en modern',
        'aantal': 3,
        'hoeken': [
          {'naam': 'Klassiekers', 'aandeel': 60},
          {'naam': 'Modern', 'aandeel': 40}
        ],
        'nummers': [
          _n('Bing Crosby', 'White Christmas'),
          _n('Bing Crosby', 'White Christmas (Remastered)'),
          _n('Bing Crosby', 'Silent Night'),
          _n('Bing Crosby', 'Jingle Bells'),
          _n('Mariah Carey', 'All I Want for Christmas Is You', h: 'Modern'),
          _n('Wham!', 'Last Christmas', h: 'Modern'),
        ],
        'reserve': [_n('Brenda Lee', "Rockin' Around the Christmas Tree")],
      }, zin: '3 kerstliedjes')!;
      expect([for (final n in v.nummers) n.titel], ['White Christmas', 'Silent Night', 'All I Want for Christmas Is You']);
      expect(v.aantal, 3);
      expect([for (final n in v.reserve) n.titel], ['Last Christmas', "Rockin' Around the Christmas Tree"],
          reason: 'meer dan gevraagd schuift naar de reserve; de derde Bing Crosby valt weg, de remaster is een dubbel');
      expect(v.hoeken.first, (naam: 'Klassiekers', aandeel: 60));
      expect(v.naam, 'Kerst · klassiek en modern');
    });

    test('DE GRENS: geen nummers is null; geen naam wordt de zin; het aantal blijft binnen 1 en $kAiLijstHoogstens', () {
      expect(leesAiLijst({'nummers': []}, zin: 'x'), isNull);
      expect(leesAiLijst('geen json', zin: 'x'), isNull);
      final v = leesAiLijst({'aantal': 9999, 'nummers': [_n('A', 'B')]}, zin: 'iets moois')!;
      expect(v.naam, 'iets moois');
      expect(v.aantal, kAiLijstHoogstens);
      expect(aiLijstReserve(200), 100);
      expect(aiLijstReserve(10), 15);
      expect(aiLijstReserve(60), 30);
    });

    test('een regel overleeft het bewaren', () {
      final n = LijstNummer(
          artiest: 'Mariah Carey',
          titel: 'All I Want for Christmas Is You',
          jaar: 1994,
          hoek: 'Modern',
          bron: LijstBron.deezer,
          hoes: 'https://x/c.jpg',
          seconden: 241,
          album: 'Merry Christmas',
          deezerId: 1234,
          fragment: 'https://x/p.mp3',
          eigenId: 'abc',
          aan: false);
      final m = LijstNummer.fromJson(n.toJson())!;
      expect((m.artiest, m.titel, m.jaar, m.hoek, m.bron, m.hoes, m.seconden, m.album, m.deezerId, m.fragment, m.eigenId, m.aan),
          (n.artiest, n.titel, 1994, 'Modern', LijstBron.deezer, n.hoes, 241, 'Merry Christmas', 1234, n.fragment, 'abc', false));
      final v = _v([n], reserve: [_l('A', 'B')]);
      final w = AiLijstVoorstel.fromJson(v.toJson())!;
      expect(w.nummers.single.titel, n.titel);
      expect(w.reserve.single.artiest, 'A');
      expect(w.hoeken, v.hoeken);
    });

    test('de vraag zegt de regels, en het schema heeft geen getalgrenzen (die weigert de API)', () {
      final p = aiLijstPrompt('200 kerstliedjes', eigen: ['Bing Crosby — White Christmas']);
      expect(p, contains('"200 kerstliedjes"'));
      expect(p, contains('Hoogstens $kAiLijstPerArtiest nummers per artiest'));
      expect(p, contains('Vooral nummers die hij nog niet heeft'));
      expect(p, contains('Bing Crosby — White Christmas'));
      expect(p, contains('een opbouw die loopt'));
      final s = '${aiLijstSchema()} ${bijsturenSchema()}';
      expect(s, isNot(contains('minimum')));
      expect(s, isNot(contains('maxItems')));
    });
  });

  group('de regels na het natrekken', () {
    test('DE KERN: wat niemand kent staat uit; van je eigen nummers hoogstens tien procent — de rest wordt nieuw', () {
      final nummers = [
        for (var i = 0; i < 20; i++) _l('Artiest $i', 'Nummer $i', b: i < 4 ? LijstBron.eigen : LijstBron.deezer),
      ]..[10].bron = LijstBron.nergens;
      final v = _v(nummers, reserve: [
        _l('Reserve A', 'R1', b: LijstBron.eigen),
        _l('Reserve B', 'R2'),
        _l('Reserve C', 'R3', b: LijstBron.nergens),
        _l('Reserve D', 'R4'),
      ]);
      expect(pasRegelsToe(v), 2, reason: 'vier eigen, twee mogen (10 % van 20)');
      expect([for (final n in v.nummers) if (n.bron == LijstBron.eigen && n.aan) n.titel], ['Nummer 0', 'Nummer 1']);
      expect(v.nummers[2].titel, 'R2', reason: 'de eerste nieuwe uit de reserve, niet de eigen R1');
      expect(v.nummers[3].titel, 'R4', reason: 'niet de niet-gevonden R3');
      expect(v.nummers[10].aan, isFalse, reason: 'niet gevonden: grijs, uit de lijst');
      expect(v.reserve.map((n) => n.titel), containsAll(['Nummer 2', 'Nummer 3']), reason: 'ze kunnen terugkomen');
    });

    test('↻ vervangt uit dezelfde hoek, het oude gaat naar de reserve; zonder reserve null', () {
      final v = _v([_l('A', '1'), _l('B', '2', h: 'Modern')], reserve: [_l('C', '3'), _l('D', '4', h: 'Modern')]);
      expect(vervang(v, 1)?.titel, '4', reason: 'dezelfde hoek gaat voor');
      expect(v.reserve.last.titel, '2');
      expect(vervang(v, 0)?.titel, '3');
      expect(vervang(v, 0)?.titel, '1', reason: 'het eerder weggehaalde komt terug als er niets anders is');
      final leeg = _v([_l('A', '1')]);
      expect(vervang(leeg, 0), isNull);
      expect(vervang(leeg, 5), isNull);
    });

    test('↻ houdt zich aan twee per artiest', () {
      final v = _v([_l('A', '1'), _l('A', '2'), _l('B', '3')], reserve: [_l('A', '4'), _l('C', '5')]);
      expect(vervang(v, 2)?.titel, '5', reason: 'een derde A mag niet');
    });
  });

  group('de mix', () {
    test('DE KERN: de verhouding volgt de schuiven, uit lijst en reserve, in de volgorde van de opbouw', () {
      final v = _v([
        for (var i = 0; i < 6; i++) _l('K$i', 'k$i'),
        for (var i = 0; i < 2; i++) _l('M$i', 'm$i', h: 'Modern'),
      ], reserve: [
        for (var i = 0; i < 4; i++) _l('R$i', 'r$i', h: 'Modern'),
      ]);
      final mix = kiesMix(v, {'Klassiekers': 50, 'Modern': 50}, 8);
      expect(mix.where((n) => n.hoek == 'Klassiekers'), hasLength(4));
      expect(mix.where((n) => n.hoek == 'Modern'), hasLength(4));
      expect(mix.map((n) => n.titel).take(4), ['k0', 'k1', 'k2', 'k3'], reason: 'de opbouw blijft');
      expect(mix.map((n) => n.titel), containsAll(['m0', 'm1', 'r0', 'r1']), reason: 'de reserve vult de hoek aan');
    });

    test('DE GRENS: een hoek op nul doet niet mee; tekort elders wordt aangevuld; niet gevonden en derde per artiest nooit', () {
      final v = _v([
        _l('A', '1'),
        _l('A', '2'),
        _l('A', '3'),
        _l('B', '4', b: LijstBron.nergens),
        _l('C', '5', h: 'Modern'),
      ], reserve: [_l('D', '6')]);
      final mix = kiesMix(v, {'Klassiekers': 100, 'Modern': 0}, 5);
      expect(mix.map((n) => n.titel), ['1', '2', '6'], reason: 'twee A, geen niet-gevonden, geen Modern');
    });
  });

  group('bijsturen', () {
    test('DE KERN: eerst het verschil — wat weg moet op plek, wat erbij komt zonder dubbels en binnen twee per artiest', () {
      final v = _v([_l('Frank Sinatra', 'Jingle Bells'), _l('Dean Martin', 'Let It Snow!'), _l('Wham!', 'Last Christmas')]);
      final b = leesBijsturing({
        'weg': [
          {'artiest': 'Frank Sinatra', 'titel': 'Jingle Bells'},
          {'artiest': 'Iemand', 'titel': 'Staat er niet in'},
        ],
        'erbij': [
          _n('Ariana Grande', 'Santa Tell Me', h: 'Modern'),
          _n('Wham!', 'Last Christmas', h: 'Modern'),
          _n('Wham!', 'Club Tropicana', h: 'Modern'),
          _n('Wham!', 'Everything She Wants', h: 'Modern'),
        ],
        'naam': '',
      }, v);
      expect(b.weg, [0]);
      expect([for (final n in b.erbij) n.titel], ['Santa Tell Me', 'Club Tropicana'],
          reason: 'Last Christmas staat er al; een derde Wham! mag niet');
      expect(b.naam, isNull);
      expect(b.leeg, isFalse);
    });

    test('overnemen: op de plek van wat wegging, de rest achteraan; het weggehaalde naar de reserve; een nieuwe hoek erbij', () {
      final v = _v([_l('A', '1'), _l('B', '2'), _l('C', '3')]);
      neemBijsturingOver(
          v,
          Bijsturing(weg: const [1], erbij: [
            LijstNummer(artiest: 'X', titel: 'x', hoek: 'Nederlandstalig'),
            LijstNummer(artiest: 'Y', titel: 'y', hoek: 'Modern'),
          ], naam: 'Kerst met Nederlands'));
      expect([for (final n in v.nummers) n.titel], ['1', 'x', '3', 'y']);
      expect(v.reserve.single.titel, '2');
      expect(v.hoeken.map((h) => h.naam), contains('Nederlandstalig'));
      expect(v.naam, 'Kerst met Nederlands');
      expect(v.aantal, 4);
    });

    test('de vraag om bij te sturen toont de lijst zoals hij nu is, zonder wat uit staat', () {
      final v = _v([_l('A', '1'), _l('B', '2')..aan = false]);
      final p = bijsturenPrompt(v, 'meer modern');
      expect(p, contains('"meer modern"'));
      expect(p, contains('- A — 1 [Klassiekers]'));
      expect(p, isNot(contains('- B — 2')));
    });
  });

  group('afspelen', () {
    test('DE KERN: wat landt, wordt de regel — op het liedje, ook een niet-gevonden; de lijst kent dan je nummer', () {
      final v = _v([
        _l('Bing Crosby', 'White Christmas'),
        _l('Plaza', 'Yo-Yo', b: LijstBron.nergens)..aan = false,
        _l('Wham!', 'Last Christmas'),
      ]);
      expect(regelGeland(v, 'Bing Crosby', 'White Christmas (Remastered 2019)', 'id1'), isTrue);
      expect(regelGeland(v, 'Plaza', 'Yo-Yo', 'id2'), isTrue);
      expect(regelGeland(v, 'Iemand', 'Anders', 'id3'), isFalse);
      expect(v.nummers[0].eigenId, 'id1');
      expect((v.nummers[1].aan, v.nummers[1].bron), (true, LijstBron.soulseek), reason: 'Soulseek had hem toch');
      expect(eigenIdsVan(v), ['id1', 'id2'], reason: 'in de volgorde van de lijst, alleen wat je hebt');
    });

    test('de verzameling gaat mee in het bewaren', () {
      final v = _v([_l('A', '1')])..verzameling = 'Kerst';
      expect(AiLijstVoorstel.fromJson(v.toJson())!.verzameling, 'Kerst');
      expect(AiLijstVoorstel.fromJson(_v([_l('A', '1')]).toJson())!.verzameling, isNull);
    });

    test('aangesloten: een radio uit de vaste lijst, zonder bijvullen; elke landing wordt de regel; in een lijst = gehouden', () {
      final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final s = m.substring(m.indexOf('Future<String?> speelAiLijst('));
      expect(s, contains('      aantal: plan.length,\n      verzameling: v.verzameling,'));
      expect(s.substring(0, s.indexOf('Widget _downloadControl')), isNot(contains('bijvul:')), reason: 'jij koos de nummers');
      expect(s, contains('if (id == null || nu == null || !regelGeland(nu, plek.artiest, plek.titel, id)) return;'));
      expect(m, contains('    return id != null && lijsten.lijsten.any((l) => l.trackIds.contains(id));\n  };\n'));
      final r = File('lib/radio.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(r, contains('      _doorRadio.add(t.path);\n      bijLanding?.call(p, t);\n'));
      expect(r, contains("    if (nieuw.isEmpty) return 'Er viel niets te vinden om een radio van te maken.';\n    bijLanding = null;\n"));
    });
  });

  group('de ingangen', () {
    test('DE KERN: zegt de zin "lijst", dan staat Afspeellijst aan in plaats van Radio', () {
      expect(zinVraagtLijst('maak me een lijst van 200 kerstliedjes, klasiekers, maar ook modernere liedjes'), isTrue);
      expect(zinVraagtLijst('een afspeellijst voor de zomer'), isTrue);
      expect(zinVraagtLijst('Playlist met eurodance'), isTrue);
      expect(zinVraagtLijst('een lijstje met slow songs'), isTrue);
      expect(zinVraagtLijst('maak me een radio met 300 liedjes van de jaren 90'), isFalse);
      expect(zinVraagtLijst('verlanglijstje'), isFalse, reason: 'een heel woord');
    });

    test('aangesloten: Radio of Afspeellijst in de zinradio, Met AI bij Afspeellijsten, bijsturen en afspelen op de lijst', () {
      final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(m, contains('  bool get _lijst => _lijstGekozen ?? zinVraagtLijst(widget.ctl.text);'));
      expect(m, contains("              FilledButton(onPressed: _bezig ? null : _maakLijst, child: const Text('Maak de lijst'))"));
      expect(m, contains('    unawaited(openAiLijst(nav.context, zin: zin));'));
      expect(m, contains("              onPressed: () => openAiLijst(context),\n              icon: const Icon(Icons.auto_awesome_rounded, size: 18),\n              label: const Text('Met AI'),"));
      expect(m, contains('                onPressed: () => openAiLijst(context, lijstId: id),'));
      expect(m, contains('                  final reden = await speelAiLijst(context, id);'));
      expect(m, contains('        await lijsten.zetAi(i, ai: v.toJson(), naam: v.naam, eigen: eigenIdsVan(v));'));
      expect(m, contains('          trekNa: (l, stap) => rec.trekNa(l, elders: _itunesVoorModel, voortgang: stap),'));
    });
  });
}
