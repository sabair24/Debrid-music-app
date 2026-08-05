/// Twee correctieregels voor één bestand, omdat de hoofdletters verschilden.
///
/// GEMETEN in Sabers corrections.json op 05-08-2026:
///
///     "…\09 - The Lady in My Life.flac" : {"artist":"Michael Jackson","album":"Thriller","_gone":"…"}
///     "…\09 - The Lady In My Life.flac" : {"artist":"Michael Jackson","album":"Thriller","release":"2911293"}
///
/// Op schijf staat er één bestand, met hoofdletter `In`. De andere regel is een wees van een
/// hernoeming — en [_sweepCorrections] vergeleek letterlijk (`live.contains(e.key)`), zag hem niet in
/// de scan en zette er een `_gone`-stempel op. Negentig dagen later was hij opgeruimd. Was de wees
/// toevallig degene met de vastgezette persing geweest, dan was díé stilletjes verdwenen.
///
/// Op Windows en macOS is `Foo.flac` hetzelfde bestand als `foo.flac`; in een tekstvergelijking niet.
/// Dat verschil is het hele geval.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/library.dart';

void main() {
  late Directory scratch;
  late Directory muziek;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_corr_');
    muziek = Directory('${scratch.path}${Platform.pathSeparator}muziek')..createSync();
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Een bibliotheek met een eigen configuratiemap, zodat de echte corrections.json ongemoeid blijft.
  LibraryStore maakStore() => LibraryStore()
    ..configDirOverride = scratch.path
    ..rootPath = muziek.path;

  File schrijfCorrecties(Map<String, Map<String, String>> inhoud) {
    final f = File('${scratch.path}${Platform.pathSeparator}corrections.json');
    f.writeAsStringSync(jsonEncode(inhoud));
    return f;
  }

  test('twee schrijfwijzen worden één regel, onder de naam die op schijf staat', () async {
    // Alleen zinvol waar het bestandssysteem zelf geen onderscheid maakt.
    if (!(Platform.isWindows || Platform.isMacOS)) return;

    final echt = File('${muziek.path}${Platform.pathSeparator}09 - The Lady In My Life.flac')
      ..writeAsBytesSync([0]);
    final wees = '${muziek.path}${Platform.pathSeparator}09 - The Lady in My Life.flac';

    schrijfCorrecties({
      wees: {'artist': 'Michael Jackson', 'album': 'Thriller', '_gone': '1785521565388'},
      echt.path: {'artist': 'Michael Jackson', 'album': 'Thriller', 'release': '2911293'},
    });

    final store = maakStore();
    await store.loadCorrections();

    // De schrijfwijze van de SCHIJF wint: alleen die komt in de scan terug.
    expect(store.correctionForTest(echt.path), isNotNull);
    expect(store.correctionForTest(wees), isNull, reason: 'de wees mag niet blijven staan');

    final c = store.correctionForTest(echt.path)!;
    expect(c['release'], '2911293', reason: 'de vastgezette persing is het hele punt');
    expect(c['artist'], 'Michael Jackson');
    expect(c['_gone'], isNull,
        reason: 'het stempel stond er omdát de andere schrijfwijze niet gevonden werd');
  });

  test('de pin overleeft ook als hij op de WEES-regel stond', () async {
    // De richting die het gevaarlijkst was: het waardevolle veld op de regel die de scan nooit ziet.
    if (!(Platform.isWindows || Platform.isMacOS)) return;

    final echt = File('${muziek.path}${Platform.pathSeparator}05 - Iets.flac')..writeAsBytesSync([0]);
    final wees = '${muziek.path}${Platform.pathSeparator}05 - iets.flac';

    schrijfCorrecties({
      wees: {'release': '999', '_gone': '1'},
      echt.path: {'artist': 'Iemand'},
    });

    final store = maakStore();
    await store.loadCorrections();

    final c = store.correctionForTest(echt.path)!;
    expect(c['release'], '999', reason: 'de pin van de wees hoort mee te verhuizen');
    expect(c['artist'], 'Iemand', reason: 'en wat er al stond blijft staan');
    expect(store.correctionForTest(wees), isNull);
  });

  test('regels die écht over verschillende bestanden gaan blijven apart', () async {
    final a = File('${muziek.path}${Platform.pathSeparator}01 - Een.flac')..writeAsBytesSync([0]);
    final b = File('${muziek.path}${Platform.pathSeparator}02 - Twee.flac')..writeAsBytesSync([0]);
    schrijfCorrecties({
      a.path: {'artist': 'A'},
      b.path: {'artist': 'B'},
    });

    final store = maakStore();
    await store.loadCorrections();
    expect(store.correctionForTest(a.path)?['artist'], 'A');
    expect(store.correctionForTest(b.path)?['artist'], 'B');
  });

  test('zonder dubbels verandert er niets', () async {
    final a = File('${muziek.path}${Platform.pathSeparator}01 - Een.flac')..writeAsBytesSync([0]);
    schrijfCorrecties({
      a.path: {'artist': 'A', 'release': '7'},
    });

    final store = maakStore();
    await store.loadCorrections();
    final c = store.correctionForTest(a.path)!;
    expect(c['artist'], 'A');
    expect(c['release'], '7');
  });
}
