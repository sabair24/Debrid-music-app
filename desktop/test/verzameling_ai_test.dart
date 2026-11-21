/// Claude deelt in (21-11-2026): de AI stelt verzamelingen en correcties voor, Saber keurt goed. Zijn woorden: "gebruik
/// ook ai om de genre te onderscheiden en zo met bestaande music ook te verzamelen", "Voorstel, ik keur goed", "AI
/// stelt voor, ik pas aan", en bij de gegevens "Ja, met een voorstel". En bij het nakijken: "wees kritisch en juist".
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/lan/server.dart' show weigerVanBuiten;
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show VerzamelingenView;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/verzamelingen.dart';
import 'package:debridmusic/verzamelvoorstellen.dart';
import 'package:debridmusic/verzamelvraag.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'place_file_test.dart' show buildFlac;

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

BibNummer _b(String id, String artiest, String titel, {String? genre, int? jaar}) =>
    (id: id, artiest: artiest, titel: titel, genre: genre, jaar: jaar);

/// Alle `properties` van een schema staan ook in `required` — anders weigert de API het hele schema.
void _volledig(Object? s, String waar) {
  if (s is! Map) return;
  if (s['properties'] is Map) {
    final props = (s['properties'] as Map).keys.toSet();
    final nodig = {...(s['required'] as List? ?? const [])};
    expect(nodig, props, reason: 'required bij $waar');
    expect(s['additionalProperties'], false, reason: waar);
    for (final e in (s['properties'] as Map).entries) {
      _volledig(e.value, '$waar.${e.key}');
    }
  }
  if (s['items'] != null) _volledig(s['items'], '$waar[]');
}

void main() {
  group('de vraag', () {
    test('DE KERN: per artiest op zijn naam zoals hij in de bestanden staat — Billie Holiday & Her Orchestra apart', () {
      final a = vraagArtiesten([
        _b('1', 'Billie Holiday', 'My Man', genre: 'Jazz', jaar: 1953),
        _b('2', 'billie holiday', 'Lover Man', genre: 'Jazz', jaar: 1945),
        _b('3', 'Billie Holiday', 'Strange Fruit', genre: 'Vocal Jazz', jaar: 1939),
        _b('4', 'Billie Holiday & Her Orchestra', 'Lover Come Back', genre: 'Toccara0217', jaar: 1944),
        _b('5', 'Sade', 'Smooth Operator', genre: 'Soul', jaar: 1984),
      ], (artiest) => artiest == 'Billie Holiday' ? ['jazz', 'vocal jazz', 'blues', 'female vocalists', 'swing', 'soul'] : const []);
      expect([for (final x in a) (x.artiest, x.aantal)],
          [('Billie Holiday', 3), ('Billie Holiday & Her Orchestra', 1), ('Sade', 1)],
          reason: 'de meeste nummers eerst; de schrijfwijze die het vaakst voorkomt');
      expect(a.first.genres, ['Jazz', 'Vocal Jazz']);
      expect(a.first.tags, hasLength(5));
      expect((a.first.vanJaar, a.first.totJaar), (1939, 1953));
      expect(vraagRegel(a[1]),
          'Billie Holiday & Her Orchestra · 1 nummer · genre: Toccara0217 · 1944 · Lover Come Back');
    });

    test('hoogstens zes titels per artiest, met een beletselteken als er meer zijn', () {
      final a = vraagArtiesten([for (var i = 0; i < 9; i++) _b('$i', 'Ella Fitzgerald', 'Nummer $i')], (_) => const []);
      expect(a.single.titels, hasLength(kTitelsPerArtiest));
      expect(vraagRegel(a.single), endsWith('Nummer 5; …'));
    });

    test('DE KERN: de vraag draagt het onderscheid dat Saber goedkeurde, met de redenen', () {
      final p = verzamelPrompt(
        [(artiest: 'Nancy Wilson', aantal: 6, genres: ['Jazz'], tags: ['vocal jazz'], vanJaar: 1960, totJaar: 1964, titels: ['Guess Who I Saw Today'])],
        [(naam: 'Vocal jazz', artiesten: ['Ella Fitzgerald'])],
        afgewezen: ['Kerst'],
      );
      for (final zin in [
        'vocal jazz (Ella Fitzgerald, Sarah Vaughan, Nancy Wilson, Madeleine Peyroux) is iets anders dan',
        'crooners en standards uit de traditional pop',
        'soulklassiekers (Sam Cooke, Ben E. King, Etta James)',
        'Bigband en swing (Glenn Miller, Benny Goodman) staan apart',
        'Een popzanger of -zangeres die een standard zingt (Annie Lennox, Eva Cassidy) hoort in geen van alle',
        'stel nooit een verzameling voor\n   van wat hij het meest heeft',
        'gebruik dan precies haar naam',
        'Liever geen correctie dan een gok.',
        '- Vocal jazz: Ella Fitzgerald',
        'Voorstellen die hij eerder afwees (stel ze niet opnieuw voor): Kerst',
        'Nancy Wilson · 6 nummers · genre: Jazz · tags: vocal jazz · 1960–1964 · Guess Who I Saw Today',
      ]) {
        expect(p, contains(zin));
      }
    });

    test('het schema: elk veld verplicht en niets erbij, anders weigert de API het', () {
      _volledig(verzamelSchema(), 'schema');
    });
  });

  group('het antwoord', () {
    final bekend = {
      for (final a in ['Nancy Wilson', 'Sarah Vaughan', 'Frank Sinatra', 'Etta James', 'Billie Holiday & Her Orchestra'])
        vraagSleutel(a): a
    };
    int aantal(String a) => a == 'Nancy Wilson' ? 6 : 3;

    test('DE KERN: alleen artiesten uit de vraag, elk in één voorstel, en een te kleine valt weg', () {
      final r = leesVerzamelvoorstel({
        'verzamelingen': [
          {
            'naam': 'Vocal jazz',
            'waarom': 'Zangers uit de jazz.',
            'artiesten': [
              {'artiest': 'nancy wilson', 'twijfel': false, 'opmerking': '', 'nietDeze': []},
              {'artiest': 'Sarah Vaughan', 'twijfel': false, 'opmerking': '', 'nietDeze': []},
              {'artiest': 'Verzonnen Zanger', 'twijfel': false, 'opmerking': '', 'nietDeze': []},
            ],
          },
          {
            'naam': 'Crooners & standards',
            'waarom': '',
            'artiesten': [
              {'artiest': 'Nancy Wilson', 'twijfel': false, 'opmerking': '', 'nietDeze': []},
              {'artiest': 'Frank Sinatra', 'twijfel': true, 'opmerking': 'ook swing', 'nietDeze': ['Bad, Bad Leroy Brown']},
            ],
          },
        ],
        'correcties': [],
      }, bekend: bekend, aantalVan: aantal);
      expect(r.verzamelingen.map((v) => v.naam), ['Vocal jazz'],
          reason: 'Crooners houdt alleen Sinatra over (3 nummers): te klein');
      expect(r.verzamelingen.first.artiesten.map((a) => a.artiest), ['Nancy Wilson', 'Sarah Vaughan'],
          reason: 'de schrijfwijze uit de vraag; een verzonnen artiest valt weg');
    });

    test('twijfel, opmerking en nietDeze komen mee', () {
      final r = leesVerzamelvoorstel({
        'verzamelingen': [
          {
            'naam': 'Crooners & standards',
            'waarom': 'w',
            'artiesten': [
              {'artiest': 'Frank Sinatra', 'twijfel': true, 'opmerking': 'ook swing', 'nietDeze': ['Bad, Bad Leroy Brown', ' ']},
            ],
          },
        ],
        'correcties': [],
      }, bekend: bekend);
      final a = r.verzamelingen.single.artiesten.single;
      expect((a.twijfel, a.opmerking, a.nietDeze.join('|')), (true, 'ook swing', 'Bad, Bad Leroy Brown'));
    });

    test('DE KERN: correcties alleen als ze kloppen — een jaar met een titel, een bekend veld, een echte wijziging', () {
      Map<String, Object> c(String artiest, String titel, String veld, String naar) =>
          {'artiest': artiest, 'titel': titel, 'veld': veld, 'naar': naar, 'waarom': 'w'};
      final r = leesVerzamelvoorstel({
        'verzamelingen': [],
        'correcties': [
          c('Etta James', 'At Last', 'jaar', '1960'),
          c('Etta James', '', 'jaar', '1960'),
          c('Etta James', 'At Last', 'jaar', '1850'),
          c('Etta James', 'At Last', 'jaar', 'zestig'),
          c('Etta James', 'At Last', 'hoes', 'x'),
          c('Billie Holiday & Her Orchestra', '', 'artiest', 'Billie Holiday'),
          c('Billie Holiday & Her Orchestra', '', 'artiest', 'billie holiday & her orchestra'),
          c('Billie Holiday & Her Orchestra', '', 'genre', 'Vocal Jazz'),
          c('Niemand', '', 'genre', 'Jazz'),
        ],
      }, bekend: bekend, vandaagJaar: 2026);
      expect([for (final x in r.correcties) '${x.artiest}|${x.titel}|${x.veld}|${x.naar}'], [
        'Etta James|At Last|jaar|1960',
        'Billie Holiday & Her Orchestra||artiest|Billie Holiday',
        'Billie Holiday & Her Orchestra||genre|Vocal Jazz',
      ]);
    });

    test('DE GRENS: hoogstens veertig correcties', () {
      final r = leesVerzamelvoorstel({
        'verzamelingen': [],
        'correcties': [
          for (var i = 0; i < 50; i++) {'artiest': 'Etta James', 'titel': '', 'veld': 'genre', 'naar': 'Soul $i', 'waarom': ''}
        ],
      }, bekend: bekend);
      expect(r.correcties, hasLength(kCorrectiesHoogstens));
    });

    test('geen kaart, of iets anders dan een kaart: niets', () {
      expect(leesVerzamelvoorstel(null, bekend: bekend).verzamelingen, isEmpty);
      expect(leesVerzamelvoorstel(const ['x'], bekend: bekend).correcties, isEmpty);
    });

    test('DE KERN: terug naar je nummers — zonder wat niet hoort, met twijfel, en een correctie zegt wat er nu staat', () {
      final nummers = [
        _b('s1', 'Frank Sinatra', 'Fly Me to the Moon', genre: 'Jazz', jaar: 1964),
        _b('s2', 'Frank Sinatra', 'Bad, Bad Leroy Brown', genre: 'Pop', jaar: 1974),
        _b('e1', 'Etta James', 'At Last', genre: 'Soul', jaar: 1990),
        _b('e2', 'Etta James', 'Trust in Me', genre: 'Soul', jaar: 1960),
        _b('b1', 'Billie Holiday & Her Orchestra', 'Lover Come Back', genre: 'Toccara0217'),
      ];
      final r = voorstellenUit((
        verzamelingen: [
          (
            naam: 'Crooners & standards',
            waarom: 'w',
            artiesten: [(artiest: 'Frank Sinatra', twijfel: true, opmerking: 'ook swing', nietDeze: ['bad, bad leroy brown'])],
          ),
        ],
        correcties: [
          (artiest: 'Etta James', titel: 'at last', veld: 'jaar', naar: '1960', waarom: 'heruitgave'),
          (artiest: 'Etta James', titel: '', veld: 'genre', naar: 'soul', waarom: 'al goed'),
          (artiest: 'Billie Holiday & Her Orchestra', titel: '', veld: 'genre', naar: 'Vocal Jazz', waarom: 'uploadernaam'),
        ],
      ), nummers, nuMs: 7);
      final v = r.voorstellen.single;
      expect((v.id, v.naam), ('v7-0', 'Crooners & standards'));
      expect([for (final n in v.nummers) (n.id, n.twijfel, n.opmerking)], [('s1', true, 'ook swing')],
          reason: '"Bad, Bad Leroy Brown" hoort er niet in');
      expect([for (final c in r.correcties) (c.id, c.ids.join(','), c.van, c.regel)], [
        ('c7-0', 'e1', '1990', 'Jaar: 1990 → 1960'),
        ('c7-2', 'b1', 'Toccara0217', 'Genre: Toccara0217 → Vocal Jazz'),
      ], reason: 'een correctie die niets verandert valt weg');
    });
  });

  group('de voorstellen bewaren', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_verzai_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    VerzamelAiVoorstel vs(String id, String naam) => VerzamelAiVoorstel(
        id: id, naam: naam, waarom: 'w', nummers: [const VoorgesteldNummer(id: 'n', artiest: 'A', titel: 'T')]);

    test('DE KERN: nieuwe voorstellen vervangen wat nog open stond; wat je deed of afwees blijft, en op schijf', () async {
      final f = File('${wortel.path}${Platform.pathSeparator}verzamelvoorstellen.json');
      final v = Verzamelvoorstellen(bestand: f);
      await v.vraagOpPc(() async => (voorstellen: [vs('a', 'Vocal jazz'), vs('b', 'Kerst'), vs('c', 'Raï')], correcties: <AiCorrectieVoorstel>[]));
      await v.zet('a', VoorstelStand.gedaan);
      await v.zet('b', VoorstelStand.weg);
      expect(v.afgewezen, ['Kerst']);
      await v.vraagOpPc(() async => (voorstellen: [vs('d', 'Soul classics')], correcties: <AiCorrectieVoorstel>[]));
      expect([for (final x in v.voorstellen) (x.id, x.stand)],
          [('a', VoorstelStand.gedaan), ('b', VoorstelStand.weg), ('d', VoorstelStand.open)]);
      expect(v.open.map((x) => x.naam), ['Soul classics']);
      expect(v.bezig, isNull);

      final terug = Verzamelvoorstellen(bestand: f);
      await terug.laad();
      expect([for (final x in terug.voorstellen) (x.id, x.stand, x.nummers.single.titel)], [
        ('a', VoorstelStand.gedaan, 'T'),
        ('b', VoorstelStand.weg, 'T'),
        ('d', VoorstelStand.open, 'T'),
      ]);
      expect(terug.gevraagdMs, greaterThan(0));
    });

    test('een fout van het model komt in beeld, en "bezig" overleeft geen herstart', () async {
      final f = File('${wortel.path}${Platform.pathSeparator}v.json');
      final v = Verzamelvoorstellen(bestand: f);
      final klaar = Completer<({List<VerzamelAiVoorstel> voorstellen, List<AiCorrectieVoorstel> correcties})>();
      final loopt = v.vraagOpPc(() => klaar.future);
      expect(v.bezig, isNotNull);
      var tweede = false;
      unawaited(v.vraagOpPc(() async {
        tweede = true;
        throw StateError('tweede');
      }));
      expect(tweede, isFalse, reason: 'één vraag aan Claude tegelijk');
      klaar.completeError('Het taalmodel heeft het even te druk.');
      await loopt;
      expect(v.fout, 'Het taalmodel heeft het even te druk.', reason: 'en de tweede vraag liep niet: één tegelijk');
      expect(v.bezig, isNull);
      final terug = Verzamelvoorstellen(bestand: f);
      await terug.laad();
      expect(terug.bezig, isNull);
      expect(terug.fout, 'Het taalmodel heeft het even te druk.');
    });

    test('DE KERN: een toestel vraagt het de pc, en kijkt tot de pc klaar is', () async {
      final pc = Verzamelvoorstellen(bestand: File('${wortel.path}${Platform.pathSeparator}pc.json'));
      final klaar = Completer<void>();
      Future<void> opPc() => pc.vraagOpPc(() async {
            await klaar.future;
            return (voorstellen: [vs('a', 'Vocal jazz')], correcties: <AiCorrectieVoorstel>[]);
          });
      final gsm = Verzamelvoorstellen()..viaPc = () => (body) => pc.beantwoord(body, opPc: opPc);
      final vraag = gsm.vraag(elke: const Duration(milliseconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(gsm.bezig, isNotNull);
      klaar.complete();
      await vraag;
      expect(gsm.bezig, isNull);
      expect(gsm.open.single.naam, 'Vocal jazz');
      await gsm.zet('a', VoorstelStand.gedaan);
      expect(pc.voorstellen.single.stand, VoorstelStand.gedaan, reason: 'de pc weet wat je deed');
    });

    test('zonder sleutel op de pc: het toestel hoort waarom', () async {
      final pc = Verzamelvoorstellen();
      final gsm = Verzamelvoorstellen()..viaPc = () => (body) => pc.beantwoord(body);
      await gsm.vraag();
      expect(gsm.fout, 'Op de pc staat geen AI-sleutel.');
    });
  });

  group('gegevens rechtzetten', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_verzai_tags_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: in het bestand en in de app, en de weg terug ligt klaar', () async {
      File maak(String naam, List<String> tags) =>
          File('${wortel.path}${Platform.pathSeparator}$naam')..writeAsBytesSync(Uint8List.fromList(buildFlac(tags)));
      final a = maak('a.flac', ['TITLE=Lover Come Back', 'ARTIST=Billie Holiday & Her Orchestra', 'GENRE=Toccara0217', 'DATE=1990']);
      final b = maak('b.flac', ['TITLE=At Last', 'ARTIST=Etta James', 'DATE=1990']);
      final lib = LibraryStore()
        ..tracks.addAll([
          Track(path: a.path, title: 'Lover Come Back', artist: 'Billie Holiday & Her Orchestra', album: '', genre: 'Toccara0217', year: 1990),
          Track(path: b.path, title: 'At Last', artist: 'Etta James', album: '', year: 1990),
        ])
        ..rebuildAlbums();
      expect(await lib.zetGegevens([a.path], 'genre', 'Vocal Jazz'), (geschreven: 1, mislukt: 0));
      expect(await lib.zetGegevens([a.path], 'artiest', 'Billie Holiday'), (geschreven: 1, mislukt: 0));
      expect(await lib.zetGegevens([b.path], 'jaar', '1960'), (geschreven: 1, mislukt: 0));
      expect(readFlacRawFields(a)['genre'], 'Vocal Jazz');
      expect(readFlacRawFields(a)['artist'], 'Billie Holiday');
      expect(readFlacRawFields(b)['date'], '1960');
      expect([for (final t in lib.tracks) (t.artist, t.genre, t.year)],
          [('Billie Holiday', 'Vocal Jazz', 1990), ('Etta James', null, 1960)]);
      final undo = File('${wortel.path}${Platform.pathSeparator}tag_undo.json');
      expect(undo.existsSync() ? undo.readAsStringSync() : _alleUndo(wortel), contains('Toccara0217'),
          reason: '"Tags terugzetten" kent de oude waarde');
    });

    test('een jaar dat geen jaar is, of een bestand dat geen FLAC of MP3 is: niets geschreven', () async {
      final wav = File('${wortel.path}${Platform.pathSeparator}x.wav')..writeAsBytesSync([1, 2, 3]);
      final lib = LibraryStore()..tracks.add(Track(path: wav.path, title: 'X', artist: 'Y', album: ''));
      expect(await lib.zetGegevens([wav.path], 'jaar', 'zestig'), (geschreven: 0, mislukt: 1));
      expect(await lib.zetGegevens([wav.path], 'genre', 'Jazz'), (geschreven: 0, mislukt: 1));
    });
  });

  testWidgets('DE KERN: het voorstel nakijken — twijfel staat uit, de naam is aan te passen, en het telt als gedaan',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = LibraryStore();
    final verz = Verzamelingen()
      ..winkel = LanStateStore(File('${Directory.systemTemp.createTempSync('dm_verzai_w_').path}${Platform.pathSeparator}s.json'));
    final v = Verzamelvoorstellen()
      ..voorstellen = [
        VerzamelAiVoorstel(id: 'v1', naam: 'Vocal jazz', waarom: 'Zangers uit de jazz.', nummers: const [
          VoorgesteldNummer(id: 'n1', artiest: 'Nancy Wilson', titel: 'Guess Who I Saw Today'),
          VoorgesteldNummer(id: 'n2', artiest: 'Nancy Wilson', titel: 'Save Your Love for Me'),
          VoorgesteldNummer(id: 'n3', artiest: 'Glenn Miller', titel: 'In the Mood', twijfel: true, opmerking: 'bigband'),
        ]),
      ];
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>.value(value: lib),
        ChangeNotifierProvider<Verzamelingen>.value(value: verz),
        ChangeNotifierProvider<Verzamelvoorstellen>.value(value: v),
        ChangeNotifierProvider<AppSettings>.value(value: AppSettings()..anthropicKey = 'sleutel'),
      ],
      child: const MaterialApp(home: Scaffold(body: VerzamelingenView())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Claude deelt in'), findsOneWidget);
    expect(find.text('Opnieuw laten indelen'), findsOneWidget);
    expect(find.text('“Vocal jazz” · nieuw'), findsOneWidget);
    expect(find.text('3 nummers van 2 artiesten · 1 twijfel'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-voorstel-bekijk-v1')));
    await tester.pumpAndSettle();
    expect(find.text('Twijfel: bigband'), findsOneWidget);
    expect(find.text('2 naar “Vocal jazz”'), findsOneWidget, reason: 'de twijfel staat uit');
    await tester.enterText(find.byKey(const ValueKey('ai-voorstel-naam')), 'Jazz-zangers');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-nummer-n2')));
    await tester.pump();
    expect(find.text('1 naar “Jazz-zangers”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-voorstel-doen')));
    await tester.pumpAndSettle();
    expect(v.voorstellen.single.stand, VoorstelStand.gedaan);
    expect(find.text('“Vocal jazz” · nieuw'), findsNothing, reason: 'gedaan: de kaart is weg');
    expect(verz.namen, contains('Jazz-zangers'), reason: 'de naam die hij koos');
    // De melding ("0 nummers naar …") laten verlopen.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  test('aangesloten: de pc beantwoordt toestellen, ook van buitenshuis, en zet gegevens recht', () {
    expect(weigerVanBuiten('/api/verzamelvoorstel', 'POST'), isNull);
    final s = _bron('lib/lan/server.dart');
    expect(s, contains("      case '/api/verzamelvoorstel':\n        return _verzamelvoorstel(req);"));
    expect(s, contains('    return _json(req.response, await v.beantwoord(body, opPc: vraagVerzamelvoorstellen));'));
    expect(s, contains("          final r = await library.zetGegevens(paden, veld, '\${body['naar'] ?? ''}');"));
    final m = _bron('lib/main.dart');
    expect(m, contains('      s.verzamelvoorstellen = verzamelvoorstellen;'));
    expect(m, contains("      return r == null ? null : (body) => r.ask('/api/verzamelvoorstel', body);"));
    expect(m, contains('        ChangeNotifierProvider<Verzamelvoorstellen>.value(value: verzamelvoorstellen),'));
    expect(m, contains('        const SliverToBoxAdapter(child: _AiVoorstelKaarten()),'));
    expect(m, contains('    for (final t in lib.mixTracks)\n      if (lib.gedeeldId(t.path) case final id?)'),
        reason: 'alleen je gewone bibliotheek: wat al in een verzameling staat, staat er niet in');
    final a = _bron('lib/ai.dart');
    expect(a, contains("          'effort': 'medium',\n          'format': {'type': 'json_schema', 'schema': verzamelSchema()},"));
  });
}

/// Waar de weg terug ook staat: alle json-bestanden in de map van de app, achter elkaar.
String _alleUndo(Directory d) => [
      for (final f in d.listSync().whereType<File>())
        if (f.path.endsWith('.json')) f.readAsStringSync()
    ].join('\n');
