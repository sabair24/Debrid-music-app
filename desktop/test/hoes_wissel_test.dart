/// De hoes en de cd springen niet meer bij een nummerwissel.
///
/// **Waarom.** Saber op 10-10-2026, op Nu speelt: *"bij het laden van de hoes en cd zie je een lichte
/// verspringing als je naar het volgende liedje gaat. de app moet altijd de hoezen herladen heb ik de
/// indruk."* Dat klopte. Elke vraag las de scans opnieuw van schijf (bij een wissel twee keer), en een
/// `Image.memory` herkent een beeld aan zijn bytes-OBJECT: elke lezing was voor Flutter een nieuw
/// beeld, opnieuw gedecodeerd terwijl er even niets stond. En bij een andere plaat ging de oude
/// eerst weg, zodat er een tel de hoes uit het bestand met een getekende schijf stond.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Een PNG van één pixel; elke aanroep een EIGEN bytes-object, zoals een lezing van schijf.
Uint8List _png() => Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

DiscogsService get _dienst => DiscogsService(AppSettings());

/// Een afgeronde scanmap op schijf, zoals de keten hem achterlaat.
void _scans(String artist, String album) {
  final dir = _dienst.artMap(artist, album, 0, null, null, const {})..createSync(recursive: true);
  for (final n in ['front', 'back', 'disc']) {
    File('${dir.path}${Platform.pathSeparator}$n').writeAsBytesSync(_png());
  }
  File('${dir.path}${Platform.pathSeparator}done').writeAsStringSync('1');
}

Widget _omhulsel(Widget kind) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: kind))),
    );

/// De bytes van elk getekend beeld in de boom.
List<Uint8List> _getekend(WidgetTester t) => [
      for (final i in t.widgetList<Image>(find.byType(Image)))
        if (i.image case ResizeImage(imageProvider: MemoryImage(:final bytes))) bytes
        else if (i.image case MemoryImage(:final bytes)) bytes,
    ];

void main() {
  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('dm_hoeswissel_').path));
  setUp(DiscogsArtwork.vergeetGelezenVoorToets);

  group('het geheugen van de scans', () {
    test('DE KERN: twee keer lezen geeft HETZELFDE object', () async {
      _scans('Bazart', 'Echo');
      final een = await _dienst.cachedReleaseArt('Bazart', 'Echo');
      final twee = await _dienst.cachedReleaseArt('Bazart', 'Echo');
      expect(een, isNotNull);
      expect(identical(een, twee), isTrue, reason: 'anders decodeert Flutter het beeld opnieuw');
      expect(identical(een!.front, twee!.front), isTrue);
    });

    test('releaseArt geeft voor een afgeronde map ook dat object', () async {
      _scans('Bazart', 'Onderweg');
      final eerst = await _dienst.cachedReleaseArt('Bazart', 'Onderweg');
      final dan = await _dienst.releaseArt('Bazart', 'Onderweg');
      expect(identical(eerst, dan), isTrue, reason: 'de tweede wisseling bij elk nummer');
    });

    test('meteen beschikbaar, zonder schijf, zodra hij eens gelezen is', () async {
      _scans('Clouseau', 'Hoezo?');
      expect(_dienst.artInGeheugen('Clouseau', 'Hoezo?'), isNull);
      final gelezen = await _dienst.cachedReleaseArt('Clouseau', 'Hoezo?');
      expect(identical(_dienst.artInGeheugen('Clouseau', 'Hoezo?'), gelezen), isTrue);
    });

    test('hoogstens zestien albums, het langst niet gebruikte gaat eruit', () async {
      for (var i = 0; i <= DiscogsArtwork.kGelezenMax; i++) {
        _scans('Artiest $i', 'Plaat $i');
        await _dienst.cachedReleaseArt('Artiest $i', 'Plaat $i');
      }
      expect(_dienst.artInGeheugen('Artiest 0', 'Plaat 0'), isNull);
      expect(_dienst.artInGeheugen('Artiest ${DiscogsArtwork.kGelezenMax}', 'Plaat ${DiscogsArtwork.kGelezenMax}'),
          isNotNull);
    });

    test('nieuwe scans maken het geheugen van die map leeg', () {
      // `_writeArt` is privé; dit legt vast dat hij de map vergeet, vóór en ná het schrijven.
      final bron = File('lib/discogs.dart').readAsStringSync();
      final begin = bron.indexOf('Future<void> _writeArt(');
      final eind = bron.indexOf('\n  }\n', begin);
      final romp = bron.substring(begin, eind);
      expect('_gelezen.remove(dir.path);'.allMatches(romp).length, 2, reason: romp);
      expect(romp.contains('} finally {\n      _gelezen.remove(dir.path);'), isTrue);
    });
  });

  group('DE KERN: AlbumArt bij een wissel', () {
    testWidgets('ligt de volgende plaat in het geheugen, dan staat hij er in hetzelfde beeld',
        (tester) async {
      _scans('Niels Destadsbader', 'Vuur en vlam');
      _scans('Bart Peeters', 'Slimmer dan de zanger');
      final volgende = (await tester.runAsync(
          () => _dienst.cachedReleaseArt('Bart Peeters', 'Slimmer dan de zanger')))!;

      await tester.pumpWidget(_omhulsel(const AlbumArt(
          artist: 'Niels Destadsbader', album: 'Vuur en vlam', identity: 'niels', size: 200)));
      await tester.pump();
      await tester.pumpWidget(_omhulsel(const AlbumArt(
          artist: 'Bart Peeters', album: 'Slimmer dan de zanger', identity: 'bart', size: 200)));
      // Eén beeld, geen wachten op schijf: de hoes en de cd van de volgende plaat staan er al.
      final getekend = _getekend(tester);
      expect(getekend.any((b) => identical(b, volgende.front)), isTrue,
          reason: 'de hoes moet de scan uit het geheugen zijn, niet een lege plek');
      expect(getekend.any((b) => identical(b, volgende.disc)), isTrue, reason: 'en de cd ook');
    });

    testWidgets('de hoes en de cd houden het vorige beeld vast tot het volgende klaar is',
        (tester) async {
      _scans('Bazart', 'Goud');
      await tester.runAsync(() => _dienst.cachedReleaseArt('Bazart', 'Goud'));
      await tester.pumpWidget(_omhulsel(const AlbumArt(artist: 'Bazart', album: 'Goud', size: 200)));
      await tester.pump();
      final beelden = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(beelden.length, greaterThanOrEqualTo(2), reason: 'hoes en cd');
      expect(beelden.every((i) => i.gaplessPlayback), isTrue,
          reason: 'zonder gaplessPlayback staat er bij elk nieuw beeld een tel niets');
    });

    testWidgets('de plaat van het volgende nummer wordt alvast klaargezet', (tester) async {
      _scans('Pauline', 'Allo le monde');
      _scans('Lara Fabian', 'Tout');
      expect(_dienst.artInGeheugen('Lara Fabian', 'Tout'), isNull);
      await tester.pumpWidget(_omhulsel(const AlbumArt(
        artist: 'Pauline',
        album: 'Allo le monde',
        size: 200,
        volgende: (
          artist: 'Lara Fabian',
          album: 'Tout',
          trackCount: 0,
          pinned: null,
          pinnedMbid: null,
          roles: <String, String>{},
        ),
      )));
      // Het lezen begon binnen de nepklok van de toets: elke stap ervan wil echte tijd én een pump.
      for (var i = 0; i < 20 && _dienst.artInGeheugen('Lara Fabian', 'Tout') == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(_dienst.artInGeheugen('Lara Fabian', 'Tout'), isNotNull,
          reason: 'bij de wissel moet hij er al liggen');
    });
  });

  test('Nu speelt geeft het volgende nummer door, met dezelfde regels als het huidige', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('final n = p.volgendNummer;'), isTrue);
    expect(main.contains('return na == null ? null : albumArtVooruit(bib, na);'), isTrue);
  });
}
