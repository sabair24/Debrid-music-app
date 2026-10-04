/// "Nummers toewijzen" op een telefoon: de titels lezen als titels, niet als een zuil letters.
///
/// Saber op 04-10-2026, met een schermafdruk van P!nk — *The Truth About Love* op zijn S26: *"op
/// mobile gsm staat de text verticaal bij nummers toewijzen, dit is niet werkbaar, alles moet perfect
/// leesbaar zijn"*. "Are We All We Are" stond letter voor letter onder elkaar.
///
/// De rij was nummer (30) + titel + bestand (vast 250 breed). Binnen een dialoog op 411 punten blijft
/// er in de rij zo'n 270 over, en 30 + 8 + 250 = 288: de titel kreeg nul punten. Flutter meldt dat op
/// een toestel niet; het breekt gewoon af waar het kan, en dat is na elke letter.
library;

import 'package:debridmusic/editions.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _uitgave = [
  ChoiceTrack('1-1', 'Are We All We Are', 268),
  ChoiceTrack('1-2', 'Blow Me (One Last Kiss)', 256),
  ChoiceTrack('1-3', 'Try', 248),
  ChoiceTrack('1-4', 'Just Give Me a Reason (feat. Nate Ruess)', 242),
];

LibraryStore _bibliotheek() {
  final lib = LibraryStore();
  lib.tracks.add(Track(
    path: '/muziek/P!nk/The Truth About Love/04 - Just Give Me a Reason (feat. Nate Ruess).flac',
    title: 'Just Give Me a Reason (feat. Nate Ruess)',
    artist: 'P!nk',
    album: 'The Truth About Love',
    trackNo: 4,
    isFlac: true,
    sizeBytes: 4,
    duration: const Duration(seconds: 242),
  ));
  lib.tracks.add(Track(
    path: '/muziek/P!nk/The Truth About Love/02 - Blow Me (One Last Kiss).flac',
    title: 'Blow Me (One Last Kiss)',
    artist: 'P!nk',
    album: 'The Truth About Love',
    trackNo: 2,
    isFlac: true,
    sizeBytes: 4,
    duration: const Duration(seconds: 256),
  ));
  lib.rebuildAlbums();
  return lib;
}

Future<void> _toon(WidgetTester tester, {required double breedte, required double hoogte}) async {
  tester.view.physicalSize = Size(breedte * 3, hoogte * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final lib = _bibliotheek();
  await tester.pumpWidget(ChangeNotifierProvider<LibraryStore>.value(
    value: lib,
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: RijToewijzenDialog(official: _uitgave, album: lib.albums.single)),
    ),
  ));
  await tester.pump();
}

/// De bibliotheek zet een timer bij het opbouwen; laat die aflopen voor de toets eindigt.
Future<void> _klaar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

void main() {
  for (final (toestel, breedte, hoogte) in [('S26', 411.0, 891.0), ('smalle telefoon', 360.0, 780.0)]) {
    testWidgets('DE KERN: op een $toestel ($breedte punten) krijgt elke titel de breedte van de rij',
        (tester) async {
      await _toon(tester, breedte: breedte, hoogte: hoogte);
      expect(tester.takeException(), isNull, reason: 'geen overloop');
      final rij = tester.getSize(find.byType(ListView)).width;
      // Eén regel, gemeten aan de kortste titel.
      final regel = tester.getSize(find.text('Try')).height;
      for (final o in _uitgave) {
        final titel = find.text(o.title);
        expect(titel, findsOneWidget, reason: o.title);
        // Wat de titel KRIJGT, niet hoe breed hij uitvalt: "Try" is van zichzelf smal.
        expect(tester.renderObject<RenderBox>(titel).constraints.maxWidth, greaterThanOrEqualTo(rij * .6),
            reason: '"${o.title}" stond letter voor letter onder elkaar — de titel kreeg 0 punten');
        // De toetsletter is ~2× zo breed als de echte: vier regels hier is twee op het toestel. Met de
        // storing was het één regel per letter — veertig voor "Just Give Me a Reason (feat. Nate Ruess)".
        expect(tester.getSize(titel).height, lessThanOrEqualTo(regel * 4.5),
            reason: '"${o.title}" hoort een titel te zijn, geen zuil van ${o.title.length} regels');
      }
      await _klaar(tester);
    });
  }

  testWidgets('DE VAL: het bestand dat al op een rij ligt is ook leesbaar, onder de titel', (tester) async {
    await _toon(tester, breedte: 411, hoogte: 891);
    final kaart = find.textContaining('Just Give Me a Reason (feat. Nate Ruess)  4:02');
    expect(kaart, findsOneWidget);
    final titel = find.text('Just Give Me a Reason (feat. Nate Ruess)');
    expect(tester.getTopLeft(kaart).dy, greaterThan(tester.getBottomLeft(titel).dy - 1),
        reason: 'op een telefoon onder de titel, niet in een strook ernaast');
    expect(tester.getSize(kaart).width, greaterThanOrEqualTo(150), reason: 'geen zuil');
    // Een middellange bestandsnaam past op een telefoon niet op één regel; met één regel stond er
    // "Blow Me (One La…". Hoeveel regels het op het toestel worden kan deze toets niet tellen — de
    // toetsletter is twee keer zo breed als de echte — dus hij houdt vast wat de kaart MAG: twee.
    final blow = find.textContaining('Blow Me (One Last Kiss)  4:16');
    expect(blow, findsOneWidget);
    expect(tester.widget<Text>(blow).maxLines, greaterThanOrEqualTo(2),
        reason: 'de bestandsnaam afgekapt: dan weet je niet welk bestand je legt');
    expect(tester.getSize(blow).width, greaterThanOrEqualTo(150), reason: 'geen zuil');
    expect(find.text('leeg'), findsNWidgets(2));
    for (final e in tester.widgetList<Text>(find.text('leeg'))) {
      expect(e.data, 'leeg');
    }
    await _klaar(tester);
  });

  testWidgets('DE GRENS: op de pc blijft het bestand naast de titel staan, zoals het was', (tester) async {
    await _toon(tester, breedte: 1280, hoogte: 800);
    expect(tester.takeException(), isNull);
    final titel = find.text('Are We All We Are');
    final leeg = find.text('leeg').first;
    expect(tester.getTopLeft(leeg).dx, greaterThan(tester.getTopRight(titel).dx),
        reason: 'naast elkaar: op een breed scherm is daar plaats voor');
    expect((tester.getCenter(leeg).dy - tester.getCenter(titel).dy).abs(), lessThan(20),
        reason: 'op dezelfde hoogte als de titel');
    await _klaar(tester);
  });
}
