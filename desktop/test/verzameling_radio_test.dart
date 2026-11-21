/// Verzamelingen en de radio (21-11-2026). Saber koos: een radio vanuit een verzameling blijft erin ("Binnen de
/// verzameling"), en wat je van een radio houdt kan apart — "Bij de start van de radio, Bij Houden per nummer, In het
/// afsluitoverzicht, Vanzelf op genre".
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show gehoudenPerDoel, kiesBestemming, radioEigen, radioVerzamelvoorstel;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiosessie.dart';
import 'package:debridmusic/verzamelingen.dart';
import 'package:debridmusic/verzamelvoorstel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

VoorstelNummer _n(String artiest, [String? genre]) => (artiest: artiest, genre: genre);

List<VoorstelNummer> _veel(int n, String genre) => [for (var i = 0; i < n; i++) _n('Artiest $genre $i', genre)];

/// Een bibliotheek met vaste id's (zoals een toestel ze uit het stroomadres haalt).
class _Lib extends LibraryStore {
  @override
  String? gedeeldId(String path) => 'id:${path.split(r'\').last}';
}

Verzamelingen _verz() => Verzamelingen()
  ..winkel = LanStateStore(File('${Directory.systemTemp.createTempSync('dm_vr_').path}${Platform.pathSeparator}s.json'));

/// Alleen wat de radio van de speler gebruikt.
class _Speler implements PlayerStore {
  final rij = <RadioItem>[];

  @override
  Future<List<RadioItem>> Function()? radioExtend;

  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;

  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;

  @override
  bool get playing => false;

  @override
  bool get radioDroog => false;

  @override
  bool get wilVerder => false;

  @override
  List<RadioItem> get radioQueue => rij;

  @override
  int get radioIndex => 0;

  @override
  Duration duration = Duration.zero;

  @override
  Duration get positieErgens => Duration.zero;

  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    rij
      ..clear()
      ..addAll(items);
  }

  @override
  void voegToeAanRadio(List<RadioItem> meer) => rij.addAll(meer);

  @override
  Future<bool> haalUitRadio(String pad) async {
    rij.removeWhere((r) => r.local?.path == pad);
    return true;
  }

  @override
  bool vervangInRadio(RadioItem oud, RadioItem? nieuw) => false;

  @override
  void addListener(void Function() listener) {}
  @override
  void removeListener(void Function() listener) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bron implements Radiobron {
  _Bron(this.nummers);
  final Map<String, Track> nummers;

  @override
  Future<String?> begin() async => null;

  @override
  void einde() {}

  @override
  void staak() {}

  @override
  Future<Track?> haal(Radioplek p) async => nummers[p.titel];

  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async => true;
}

Track _t(String titel, {String? artiest}) => Track(
    path: '${Directory.systemTemp.path}${Platform.pathSeparator}$titel.flac',
    title: titel,
    artist: artiest ?? titel,
    album: '');

Future<void> _totGeland(RadioBesturing r, int n) async {
  for (var i = 0; i < 400; i++) {
    if (_gehaald(r) >= n) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

int _gehaald(RadioBesturing r) => r.plan.where((p) => p.doorRadio).length;

void main() {
  group('vanzelf op genre', () {
    test('DE KERN: een radio vanaf een artiest die je apart houdt, stelt die verzameling voor', () {
      final v = verzamelingVoorRadio(
        zaadArtiest: 'Madeleine Peyroux',
        zaadGenre: 'Jazz',
        verzamelingen: {
          'Vocal jazz': [_n('Madeleine Peyroux', 'Vocal Jazz'), _n('Nancy Wilson', 'Vocal Jazz')],
          'Crooners & standards': [_n('Dean Martin', 'Easy Listening')],
        },
        bibliotheek: [_n('Sade', 'Soul'), _n('Khaled', 'Raï')],
      );
      expect(v?.naam, 'Vocal jazz');
      expect(v?.nieuw, isFalse);
      expect(v?.waarom, 'Madeleine Peyroux staat al in “Vocal jazz”');
    });

    test('de artiest telt alleen als hij meer in de verzameling staat dan in je bibliotheek', () {
      final v = verzamelingVoorRadio(
        zaadArtiest: 'Sade',
        verzamelingen: {
          'Vocal jazz': [_n('Sade', 'Soul')],
        },
        bibliotheek: [_n('Sade', 'Soul'), _n('Sade', 'Soul')],
      );
      expect(v, isNull, reason: 'Sade hoort bij je gewone muziek; "Soul" staat niet vooral in Vocal jazz');
    });

    test('DE KERN: een genre dat vooral in een verzameling staat, stelt die voor', () {
      final v = verzamelingVoorRadio(
        zaadArtiest: 'Diana Krall',
        zaadGenre: 'Vocal Jazz',
        verzamelingen: {
          'Vocal jazz': [..._veel(4, 'Vocal Jazz'), ..._veel(2, 'Jazz')],
        },
        bibliotheek: [..._veel(1, 'Vocal Jazz'), ..._veel(50, 'Pop')],
      );
      expect(v?.naam, 'Vocal jazz');
      expect(v?.waarom, '“Vocal Jazz” staat vooral in “Vocal jazz”');
    });

    test('DE GRENS: minstens drie nummers, en minstens 30 % van de verzameling', () {
      Verzamelvoorstel? met(List<VoorstelNummer> verz) => verzamelingVoorRadio(
          zaadArtiest: 'X', zaadGenre: 'Swing', verzamelingen: {'Bigband': verz}, bibliotheek: _veel(10, 'Pop'));
      expect(met(_veel(3, 'Swing'))?.naam, 'Bigband');
      expect(met(_veel(2, 'Swing')), isNull, reason: 'twee is toeval');
      expect(met([..._veel(3, 'Swing'), ..._veel(7, 'Jazz')])?.naam, 'Bigband', reason: '30 % precies');
      expect(met([..._veel(3, 'Swing'), ..._veel(8, 'Jazz')]), isNull, reason: 'minder dan 30 %');
    });

    test('op het genre zoals het in je bestanden staat, niet op de familie: Swing is geen Vocal jazz', () {
      final v = verzamelingVoorRadio(
        zaadArtiest: 'Glenn Miller',
        zaadGenre: 'Swing',
        verzamelingen: {'Vocal jazz': _veel(10, 'Vocal Jazz')},
        bibliotheek: _veel(50, 'Pop'),
      );
      expect(v, isNull, reason: 'Saber wees de bigband op 21-11-2026 niet bij Vocal jazz in');
    });

    test('DE KERN: een zeldzaam genre stelt een nieuwe verzameling voor', () {
      final v = verzamelingVoorRadio(
        zaadArtiest: 'João Gilberto',
        zaadGenre: 'Bossa Nova',
        verzamelingen: const {},
        bibliotheek: [..._veel(4, 'Bossa Nova'), ..._veel(296, 'Pop')],
      );
      expect(v?.naam, 'Bossa Nova');
      expect(v?.nieuw, isTrue);
      expect(v?.waarom, '“Bossa Nova” komt bijna niet voor in je bibliotheek (4 van 300)');
    });

    test('DE GRENS: zeldzaam is hoogstens 2 % van minstens 200 nummers, en nooit een verzamelbak', () {
      Verzamelvoorstel? met(String genre, int zelf, int rest) => verzamelingVoorRadio(
          zaadArtiest: 'X',
          zaadGenre: genre,
          verzamelingen: const {},
          bibliotheek: [..._veel(zelf, genre), ..._veel(rest, 'Pop')]);
      expect(met('Fado', 6, 294)?.naam, 'Fado', reason: '2 % precies');
      expect(met('Fado', 7, 293), isNull, reason: 'meer dan 2 %: dat is gewoon je muziek');
      expect(met('Fado', 1, 150), isNull, reason: 'een kleine bibliotheek: alles is zeldzaam');
      expect(met('Various', 1, 300), isNull);
      expect(met('Easy Listening', 1, 300), isNull);
      expect(met('Soundtrack', 0, 300), isNull);
    });

    test('zonder genre van het zaad: het genre dat het meest voorkomt bij de artiest', () {
      final v = verzamelingVoorRadio(
        zaadArtiest: 'Stacey Kent',
        verzamelingen: {'Vocal jazz': _veel(5, 'Vocal Jazz')},
        bibliotheek: [_n('Stacey Kent', 'Vocal Jazz'), _n('Stacey Kent', 'vocal jazz'), _n('Stacey Kent', 'Pop'), ..._veel(20, 'Pop')],
      );
      expect(v?.naam, 'Vocal jazz');
      expect(meesteGenre([_n('a', 'Vocal Jazz'), _n('a', 'vocal jazz'), _n('a', 'Pop'), _n('a', 'Vocal Jazz')]), 'Vocal Jazz');
    });

    test('genres vergelijken: hoofdletters, & en leestekens tellen niet', () {
      expect(genreSleutel('R&B'), genreSleutel('r and b'));
      expect(genreSleutel('Vocal-Jazz'), 'vocal jazz');
      expect(genreSleutel('  Raï  '), 'raï');
      expect(genreSleutel(' / '), isNull);
      expect(genreSleutel(null), isNull);
    });

    test('wat je deze sessie afwees, komt niet terug', () async {
      final lib = _Lib()
        ..tracks.addAll([
          Track(path: r'D:\m\DebridMusic Downloads\Verzamelingen\Vocal jazz\Singles\a.flac', title: 'A', artist: 'Nancy Wilson', album: ''),
          Track(path: r'D:\m\DebridMusic Downloads\Singles\b.flac', title: 'B', artist: 'Sade', album: ''),
        ])
        ..rebuildAlbums();
      final verz = _verz();
      expect(radioVerzamelvoorstel(lib, verz, 'Nancy Wilson', null)?.naam, 'Vocal jazz');
      expect(radioVerzamelvoorstel(lib, verz, 'Nancy Wilson', null, afgewezen: {'vocal jazz'}), isNull);
      expect(radioVerzamelvoorstel(lib, verz, 'Sade', null), isNull);
    });
  });

  group('de sessie', () {
    test('DE KERN: elk nummer gaat naar zijn eigen keuze, anders naar die van de radio', () {
      final s = RadioSessie(naam: 'Nancy Wilson', begonnenMs: 1, verzameling: 'Vocal jazz', doelen: {
        'b': '',
        'c': 'Crooners & standards',
      });
      Gehaald g(String pad) => Gehaald(pad: pad, artiest: 'X', titel: pad);
      expect(s.doelVan(g('a')), 'Vocal jazz');
      expect(s.doelVan(g('b')), isNull, reason: 'bij Houden gekozen: je bibliotheek');
      expect(s.doelVan(g('c')), 'Crooners & standards');
      s.verzameling = null;
      expect(s.doelVan(g('a')), isNull);
      expect(s.doelVan(g('c')), 'Crooners & standards');
    });

    test('bewaard en teruggelezen, en een oude notitie zonder bestemming blijft je bibliotheek', () {
      final s = RadioSessie(naam: 'r', begonnenMs: 1, verzameling: 'Vocal jazz', doelen: {'b': '', 'c': 'Soul classics'});
      final terug = RadioSessie.fromJson(s.toJson())!;
      expect(terug.verzameling, 'Vocal jazz');
      expect(terug.doelen, {'b': '', 'c': 'Soul classics'});
      final oud = RadioSessie.fromJson(RadioSessie(naam: 'r', begonnenMs: 1).toJson())!;
      expect(oud.verzameling, isNull);
      expect(oud.doelen, isEmpty);
      expect(RadioSessie(naam: 'r', begonnenMs: 1).toJson().containsKey('verzameling'), isFalse);
    });

    test('DE KERN: per verzameling de bestanden; wat naar je bibliotheek gaat of al weg is, niet', () {
      final s = RadioSessie(naam: 'r', begonnenMs: 1, verzameling: 'Vocal jazz', doelen: {'b': '', 'c': 'Soul classics'});
      final blijft = [
        for (final p in ['a', 'b', 'c', 'd', 'weg']) Gehaald(pad: p, artiest: 'X', titel: p),
      ];
      expect(gehoudenPerDoel(s, blijft, (g) => g.pad == 'weg' ? null : 'D:/${g.pad}'),
          {
            'Vocal jazz': ['D:/a', 'D:/d'],
            'Soul classics': ['D:/c'],
          });
      expect(gehoudenPerDoel(RadioSessie(naam: 'r', begonnenMs: 1), blijft, (g) => g.pad), isEmpty,
          reason: 'een gewone radio verhuist niets');
    });
  });

  group('de radio', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_verzradio_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: gestart vanuit een verzameling; Houden kiest per nummer; de radio wisselt de rest', () async {
      final zaad = _t('Zaad', artiest: 'Nancy Wilson'), b = _t('B', artiest: 'Sarah Vaughan'), c = _t('C', artiest: 'Ella');
      final radio = RadioBesturing(speler: _Speler(), bron: _Bron({'B': b, 'C': c}));
      addTearDown(radio.stop);
      await radio.start([
        Radioplek(artiest: 'Nancy Wilson', titel: 'Zaad', eigen: zaad, zaad: true),
        Radioplek(artiest: 'Sarah Vaughan', titel: 'B'),
        Radioplek(artiest: 'Ella', titel: 'C'),
      ], verzameling: 'Vocal jazz');
      await _totGeland(radio, 2);
      expect(radio.verzameling, 'Vocal jazz');
      expect(radio.doelVoor(b.path), 'Vocal jazz');

      radio.houdIn(b.path, null);
      expect(radio.doelVoor(b.path), isNull, reason: 'bij Houden: je bibliotheek');
      radio.zetVerzameling('Crooners & standards');
      expect(radio.doelVoor(c.path), 'Crooners & standards', reason: 'wat geen eigen keuze heeft, volgt de radio');
      expect(radio.doelVoor(b.path), isNull, reason: 'de eigen keuze blijft');
      radio.houdIn(c.path, 'Vocal jazz', id: null);
      expect(radio.doelVoor(c.path), 'Vocal jazz');
    });

    test('een voorstel verdwijnt bij aannemen, bij nee, en bij een nieuwe start', () async {
      final radio = RadioBesturing(speler: _Speler(), bron: _Bron(const {}));
      addTearDown(radio.stop);
      final zaad = _t('Zaad', artiest: 'Nancy Wilson');
      Future<void> start() => radio.start([Radioplek(artiest: 'Nancy Wilson', titel: 'Zaad', eigen: zaad, zaad: true)]);
      await start();
      const v = (naam: 'Vocal jazz', waarom: 'w', nieuw: false);
      radio.verzamelvoorstel = v;
      expect(radio.verzamelvoorstel, v);
      radio.zetVerzameling('Vocal jazz');
      expect(radio.verzamelvoorstel, isNull);
      expect(radio.verzameling, 'Vocal jazz');

      radio.verzamelvoorstel = (naam: 'Bossa nova', waarom: 'w', nieuw: true);
      radio.wijsVoorstelAf();
      expect(radio.verzamelvoorstel, isNull);
      expect(radio.afgewezenVoorstellen, {'bossa nova'});
      expect(radio.verzameling, 'Vocal jazz', reason: 'nee zeggen verandert de bestemming niet');

      radio.verzamelvoorstel = v;
      await start();
      expect(radio.verzamelvoorstel, isNull, reason: 'elke start begint zonder');
      expect(radio.verzameling, isNull, reason: 'en voor je bibliotheek, tenzij gekozen');
    });

    test('DE KERN: een vorige radio die meegaat, houdt zijn eigen bestemming', () async {
      final zaad = _t('Zaad', artiest: 'Nancy Wilson'), b = _t('B', artiest: 'Sarah Vaughan'), d = _t('D', artiest: 'Sade');
      final radio = RadioBesturing(speler: _Speler(), bron: _Bron({'B': b, 'D': d}));
      addTearDown(radio.stop);
      await radio.start([
        Radioplek(artiest: 'Nancy Wilson', titel: 'Zaad', eigen: zaad, zaad: true),
        Radioplek(artiest: 'Sarah Vaughan', titel: 'B'),
      ], verzameling: 'Vocal jazz');
      await _totGeland(radio, 1);
      radio.stop();
      expect(radio.openstaand?.verzameling, 'Vocal jazz');
      radio.zetVerzameling('Soul classics', sessie: radio.openstaand);
      expect(radio.openstaand?.verzameling, 'Soul classics', reason: 'gewijzigd in het afsluitoverzicht');

      await radio.start([
        Radioplek(artiest: 'Sade', titel: 'Zaad2', eigen: _t('Zaad2', artiest: 'Sade'), zaad: true),
        Radioplek(artiest: 'Sade', titel: 'D'),
      ]);
      await _totGeland(radio, 1);
      expect(radio.verzameling, isNull);
      expect(radio.doelVoor(b.path), 'Soul classics', reason: 'die van de vorige radio');
      expect(radio.doelVoor(d.path), isNull);
    });
  });

  test('een radio vanuit een verzameling vult ook met wat er als verwijzing in staat', () async {
    final lib = _Lib()
      ..tracks.addAll([
        Track(path: r'D:\m\DebridMusic Downloads\Verzamelingen\Vocal jazz\Singles\a.flac', title: 'A', artist: 'X', album: ''),
        Track(path: r'D:\m\DebridMusic Downloads\Singles\b.flac', title: 'B', artist: 'Y', album: ''),
        Track(path: r'D:\m\DebridMusic Downloads\Singles\c.flac', title: 'C', artist: 'Z', album: ''),
      ])
      ..rebuildAlbums();
    final verz = _verz();
    await verz.koppel('Vocal jazz', ['id:b.flac']);
    expect([for (final t in radioEigen(lib, 'Vocal jazz', verz)) t.title], ['A', 'B']);
    expect([for (final t in radioEigen(lib, 'Vocal jazz')) t.title], ['A']);
    expect([for (final t in radioEigen(lib, null, verz)) t.title], ['B', 'C'], reason: 'je bibliotheek: zonder de map');
  });

  testWidgets('DE KERN: de keuze — je bibliotheek, een verzameling, of niets', (tester) async {
    final lib = _Lib()
      ..tracks.add(Track(
          path: r'D:\m\DebridMusic Downloads\Verzamelingen\Vocal jazz\Singles\a.flac', title: 'A', artist: 'X', album: ''))
      ..rebuildAlbums();
    final verz = _verz();
    await tester.runAsync(() => verz.maak('Soul classics'));
    ({String? naam})? uit;
    var klaar = false;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>.value(value: lib),
        ChangeNotifierProvider<Verzamelingen>.value(value: verz),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                uit = await kiesBestemming(context, titel: 'Dit nummer houden in…', huidig: 'Vocal jazz');
                klaar = true;
              },
              child: const Text('kies'),
            ),
          ),
        ),
      ),
    ));
    Future<void> kies(String tekst) async {
      klaar = false;
      await tester.tap(find.text('kies'));
      await tester.pumpAndSettle();
      expect(find.text('Dit nummer houden in…'), findsOneWidget);
      expect(find.text('Je bibliotheek'), findsOneWidget);
      expect(find.text('Soul classics'), findsOneWidget);
      expect(find.text('Nieuwe verzameling…'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('bestemming-Vocal jazz')), matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget,
          reason: 'de huidige staat aangevinkt');
      await tester.tap(find.text(tekst));
      await tester.pumpAndSettle();
      expect(klaar, isTrue);
    }

    await kies('Soul classics');
    expect(uit?.naam, 'Soul classics');
    await kies('Je bibliotheek');
    expect(uit, isNotNull);
    expect(uit?.naam, isNull);
    await kies('Annuleren');
    expect(uit, isNull);
  });

  test('aangesloten: de start, het paneel, Houden en het afsluitoverzicht', () {
    final m = _bron('lib/main.dart');
    expect(m, contains('  final verz = verzameling ?? zaad?.verzameling;'));
    expect(m, contains('      verzameling: verz,\n      bijStart: (s) {'));
    expect(m, contains('    reserveKandidaten: (artiesten) => _reserveUit(lib, artiesten, verzameling: verz, koppel: verzStore),'));
    expect(m, contains('          for (final t in radioEigen(lib, verz, verzStore))\n'
        '            if (artiestSleutel(t.artist) == zelf && !nooitOpRadio(t.title)) t'));
    expect(m, contains('          radioVerzamelvoorstel(lib, verzStore, artist, zaad?.genre, afgewezen: radio.afgewezenVoorstellen);'));
    expect(m, contains('          const _RadioOpruimregel(),\n          const _RadioBestemming(),'));
    expect(m, contains("        final keuze = await kiesBestemming(context, titel: 'Dit nummer houden in…', huidig: doel);"));
    expect(m, contains('        r.houdIn(t.path, keuze.naam, id: id);'));
    expect(m, contains('    kortGemeld(vooraf.blijft.length, await verhuisGehouden(vooraf.blijft));'),
        reason: 'ook als er niets weg moet');
    expect(m, contains('  final verhuisd = await verhuisGehouden(plan.blijft);'));
    expect(m, contains("    unawaited(startRadio(context, zaad.artist, zaad: zaad, verzameling: _naam));"));
    expect(m, contains("                  key: const ValueKey('verzameling-radio'),"));
  });
}
