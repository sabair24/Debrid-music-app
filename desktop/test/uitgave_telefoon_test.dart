/// "Uitgave kiezen" en "Alle scans" op een telefoon: geen tekst die letter voor letter afbreekt, en
/// niets over de rand.
///
/// Saber op 05-10-2026: *"ook bij uitgave kiezen staat de tekst verticaal bij gsm als ik een hoes
/// ofzo selecteer"*. Zodra je een scan klaarzet verschijnt onderaan een balk: "Overnemen: hoes" met
/// "Ongedaan maken" en "Opslaan" ernaast, in één Row. In de dialoog op een telefoon (~250 punten
/// binnenin) namen de knoppen er ~240, en de uitleg brak per letter af. Een dag eerder was precies
/// dat bij "Nummers toewijzen" gerepareerd (`toewijzen_telefoon_test.dart`).
///
/// Bij het nalopen van de rest van deze twee vensters vielen er nog twee op: de knoppen onderaan
/// "Alle scans" ("Alles weer laten raden" + "Opslaan") zijn samen breder dan de dialoog op een
/// telefoon, en de drie knopjes onder elke scan (hoes / achter / cd) breder dan een tegel.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/audiodb.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/enrichment.dart' show CoverEnricher;
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// De breedte binnen de dialoog: scherm − 2×40 (`Dialog.insetPadding`) − 2×20 (de eigen `Padding`).
double _binnen(double scherm) => scherm - 80 - 40;

void _telefoon(WidgetTester tester, double breedte, double hoogte) {
  tester.view.physicalSize = Size(breedte * 3, hoogte * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Ligt [wat] helemaal binnen [kader]? Een knop die erbuiten valt, is niet aan te tikken.
void _binnenIn(WidgetTester tester, Finder wat, Finder kader, String naam) {
  final k = tester.getRect(kader);
  for (var i = 0; i < tester.widgetList(wat).length; i++) {
    final r = tester.getRect(wat.at(i));
    expect(r.left >= k.left - .5 && r.right <= k.right + .5, isTrue,
        reason: '$naam #$i steekt buiten het venster: $r tegen $k');
  }
}

/// Laat de timers van het venster aflopen (de tijdslimiet van een TheAudioDB-vraag) voor de toets eindigt.
Future<void> _klaar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  group('de balk na het klaarzetten', () {
    Future<void> toon(WidgetTester tester, double breedte) => tester.pumpWidget(MaterialApp(
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: breedte,
                child: OvernemenBalk(
                  tekst: 'Overnemen: hoes, achter, cd',
                  bezig: false,
                  onOngedaan: () {},
                  onOpslaan: () {},
                ),
              ),
            ),
          ),
        ));

    for (final (toestel, scherm) in [('S26', 411.0), ('smalle telefoon', 360.0)]) {
      testWidgets('DE KERN: op een $toestel staat de uitleg leesbaar, de knoppen eronder', (tester) async {
        _telefoon(tester, scherm, 800);
        final breedte = _binnen(scherm);
        await toon(tester, breedte);
        expect(tester.takeException(), isNull, reason: 'geen overloop');
        final uitleg = find.text('Overnemen: hoes, achter, cd');
        expect(tester.renderObject<RenderBox>(uitleg).constraints.maxWidth, greaterThanOrEqualTo(breedte * .9),
            reason: '"Overnemen: hoes" brak letter voor letter af — de uitleg kreeg een paar punten');
        expect(tester.getTopLeft(find.text('Opslaan')).dy, greaterThan(tester.getBottomLeft(uitleg).dy - 1),
            reason: 'op een telefoon onder de uitleg, niet ernaast');
        expect(find.text('Ongedaan maken'), findsOneWidget);
      });
    }

    testWidgets('DE GRENS: op de pc blijft het één regel, zoals het was', (tester) async {
      await toon(tester, 900);
      final uitleg = find.text('Overnemen: hoes, achter, cd');
      expect((tester.getCenter(find.text('Opslaan')).dy - tester.getCenter(uitleg).dy).abs(), lessThan(12),
          reason: 'naast elkaar');
    });

    test('"Uitgave kiezen" gebruikt de balk, en de oude rij is weg', () {
      // Aan de bron, want de kiezer zelf haalt bij het openen MusicBrainz, Discogs en TheAudioDB op.
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('                OvernemenBalk(\n'));
      expect(
          main,
          isNot(contains('Row(children: [\n                  Expanded(\n                    child: Text(\n'
              '                      // Names what will change')),
          reason: 'de rij waarin "Overnemen: hoes" per letter afbrak');
    });
  });

  group('"Alle scans"', () {
    /// Een TheAudioDB-album met vijf scans, zoals *Play* die dag (HQ, gewoon, achter, cd, rug).
    MockClient audioDb() => MockClient((r) async => http.Response(
        jsonEncode({
          'album': [
            {
              'idAlbum': '2109660',
              'strAlbum': 'Play',
              'strArtist': 'Moby',
              'strAlbumThumb': 'https://r2.theaudiodb.com/images/media/album/thumb/play.jpg',
              'strAlbumThumbHQ': 'https://r2.theaudiodb.com/images/media/album/thumbhq/play.jpg',
              'strAlbumBack': 'https://r2.theaudiodb.com/images/media/album/back/play.jpg',
              'strAlbumCDart': 'https://r2.theaudiodb.com/images/media/album/cdart/play.png',
              'strAlbumSpine': 'https://r2.theaudiodb.com/images/media/album/spine/play.jpg',
            }
          ]
        }),
        200));

    Future<void> toon(WidgetTester tester) async {
      final lib = LibraryStore();
      lib.tracks.add(Track(
        path: '/muziek/Moby/Play/03 - Porcelain.flac',
        title: 'Porcelain',
        artist: 'Moby',
        album: 'Play',
        trackNo: 3,
        isFlac: true,
        sizeBytes: 4,
      ));
      lib.rebuildAlbums();
      await http.runWithClient(() async {
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<LibraryStore>.value(value: lib),
            ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
            Provider<MusicBrainzService>.value(value: MusicBrainzService()),
          ],
          child: MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: Scaffold(
              body: AssignScansDialog(
                album: lib.albums.single,
                choice: const ReleaseChoice(source: EditionSource.audiodb, audioDbId: '2109660'),
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }, audioDb);
    }

    for (final (toestel, scherm, hoogte) in [('S26', 411.0, 891.0), ('smalle telefoon', 360.0, 780.0)]) {
      testWidgets('DE KERN: op een $toestel passen de knopjes onder elke scan, ook na een keuze', (tester) async {
        _telefoon(tester, scherm, hoogte);
        await toon(tester);
        expect(find.text('hoes'), findsWidgets, reason: 'de scans van TheAudioDB staan erin');
        expect(tester.takeException(), isNull, reason: 'geen knopjes over de rand van een tegel');

        // Een rol kiezen: dan verschijnt "Alles weer laten raden" naast "Opslaan".
        await tester.tap(find.text('achter').at(1));
        await tester.pump();
        expect(find.text('Alles weer laten raden'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '"Alles weer laten raden" + "Opslaan" zijn samen breder dan de dialoog');
        final venster = find.byType(Dialog);
        _binnenIn(tester, find.text('Alles weer laten raden'), venster, 'Alles weer laten raden');
        _binnenIn(tester, find.text('Opslaan'), venster, 'Opslaan');

        // De zin naast de drie voorbeeldvakjes: die brak per letter af, elke keer dat je een scan aanwees.
        final zin = find.textContaining('Zo komt deze plaat eruit te zien');
        expect(tester.renderObject<RenderBox>(zin).constraints.maxWidth,
            greaterThanOrEqualTo(_binnen(scherm) * .9),
            reason: 'de uitleg kreeg naast de drie vakjes 14 tot 65 punten en stond letter voor letter onder elkaar');
        await _klaar(tester);
      });
    }

    testWidgets('DE GRENS: op de pc staan de knoppen onderaan naast elkaar, zoals het was', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await toon(tester);
      await tester.tap(find.text('achter').at(1));
      await tester.pump();
      expect(
          (tester.getCenter(find.text('Opslaan')).dy - tester.getCenter(find.text('Alles weer laten raden')).dy)
              .abs(),
          lessThan(12));
      final zin = find.textContaining('Zo komt deze plaat eruit te zien');
      expect(tester.getTopLeft(zin).dy, lessThan(tester.getBottomLeft(find.text('hoes').first).dy),
          reason: 'op de pc staat de uitleg naast de vakjes, zoals het was');
      await _klaar(tester);
    });
  });

  test('een vraag uit een venster meldt zich bij de achtergrondrij van TheAudioDB', () {
    // Zonder deze koppeling vroeg een venster en vroeg de achtergrond vlak erna nog eens — samen te
    // snel voor de gratis grens van TheAudioDB.
    expect(AudioDbService.vraagGedaan, same(CoverEnricher.meldAudioDbVraag));
  });
}
