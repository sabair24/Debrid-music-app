/// Hoezen, achterkanten en cd's staan er meteen (Saber, 17-10-2026: "direct tonen van alle covers,
/// backcover, cd hoes").
///
/// Drie dingen maakten ze laat: [AlbumArt] keek in zijn eerste beeld niet in het geheugen (dus eerst
/// de hoes uit het bestand en een getekende schijf, een beeld later de scans), de achterkant van een
/// tegel werd pas bij de eerste dubbeltik van schijf gelezen, en de binnenkomst liet tegels flitsen
/// (zie binnenkomst_test.dart).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/ui/tegel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hoofd = File('lib/main.dart').readAsStringSync();

  test('AlbumArt kijkt in zijn eerste beeld al in het geheugen', () {
    final begin = hoofd.indexOf('class _AlbumArtState extends State<AlbumArt>');
    final init = hoofd.indexOf('void initState() {', begin);
    final geheugen = hoofd.indexOf('.artInGeheugen(widget.artist, widget.album,', init);
    final laden = hoofd.indexOf('_load();', init);
    expect(geheugen, greaterThan(init));
    expect(geheugen, lessThan(laden), reason: 'vóór het laden, anders is het eerste beeld al getekend');
  });

  test('voorladen leest alleen van schijf en decodeert op de maat van de albumpagina', () {
    final begin = hoofd.indexOf('Future<Uint8List?> voorladenVan(BuildContext context, Album al)');
    expect(begin, greaterThan(-1));
    final eind = hoofd.indexOf('\n}\n', begin);
    final lijf = hoofd.substring(begin, eind);
    expect(lijf, contains('.cachedReleaseArt('));
    expect(lijf, isNot(contains('.releaseArt(')), reason: 'met de muis over een raster: geen Discogs-vragen');
    expect(lijf, contains('decodeWidth(kAlbumKopHoes)'));
    expect(lijf, contains('decodeWidth(kAlbumKopHoes * .92)'));
    expect(hoofd, contains(': kAlbumKopHoes;'), reason: 'de albumpagina tekent op dezelfde maat');
    expect(hoofd, contains('voorladen: () => voorladenVan(context, a),'));
  });

  test('tegel, Nu speelt en albumpagina zoeken de scans in dezelfde map', () {
    // De warmer en de albumpagina vullen de uitgave aan met `facts.mbid`; de tegel en Nu speelt
    // deden dat niet en zochten met het aantal bestanden in een andere map (17-10-2026, *NSYNC).
    final begin = hoofd.indexOf('AlbumArtVooruit albumArtVooruit(LibraryStore bib, Album al) => (');
    final lijf = hoofd.substring(begin, hoofd.indexOf(');', begin));
    expect(lijf, contains('bib.facts.get(bib.uidOf(al))?.mbid'));
    expect(hoofd, contains('pinnedMbid: al == null ? null : albumArtVooruit(bib, al).pinnedMbid,'),
        reason: 'Nu speelt met dezelfde regel');
    expect(hoofd, contains('_officialMbid,'), reason: 'de albumpagina vult zelf ook aan met de feiten');
  });

  test('de achtergrond van de albumpagina heeft één bron zodra de kop een voorkant meldt', () {
    // Twee bronnen sprongen heen en weer: build zette de hoes uit het bestand, de kop de scan.
    expect(hoofd, contains('if (!_kopGafHoes) _kleurUitHoes(album.correctedCover ?? album.cover);'));
    expect(hoofd, contains('onFront: _kleurUitKop,'));
    expect(hoofd, isNot(contains('onFront: _kleurUitHoes,')));
  });

  test('de credits schuiven open: de tracklijst eronder springt niet', () {
    final begin = hoofd.indexOf('class _CreditsPanelState extends State<CreditsPanel>');
    final bouw = hoofd.indexOf('Widget build(BuildContext context) =>', begin);
    expect(bouw, greaterThan(begin));
    expect(hoofd.substring(bouw, bouw + 120), contains('AnimatedSize('));
  });

  test('op een bureaublad is de beeldcache ruimer dan de standaard van 100 MB', () {
    final regel = RegExp(r'if \(_isDesktop\) \{\s*PaintingBinding\.instance\.imageCache\s*\.\.maximumSizeBytes = (\d+) << 20');
    final m = regel.firstMatch(hoofd);
    expect(m, isNotNull);
    expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(300));
  });

  testWidgets('de eerste keer aanwijzen laadt voor, en maar één keer', (t) async {
    var voor = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AlbumTegel(
            breedte: 180,
            hoes: (maat) => SizedBox.square(dimension: maat, child: const ColoredBox(color: Colors.teal)),
            titel: 'Plaat',
            onTap: () {},
            draaibaar: true,
            voorladen: () async {
              voor++;
              return null;
            },
          ),
        ),
      ),
    ));
    final muis = await t.createGesture(kind: PointerDeviceKind.mouse);
    await muis.addPointer(location: const Offset(1, 1));
    addTearDown(muis.removePointer);
    for (var i = 0; i < 3; i++) {
      await muis.moveTo(t.getCenter(find.byType(AlbumTegel)));
      await t.pump();
      await muis.moveTo(const Offset(1, 1));
      await t.pump();
    }
    expect(voor, 1);
    await t.pumpAndSettle();
  });

  testWidgets('de cd bestaat pas na het eerste aanwijzen, schuift dan uit, en tekent niets meer als hij terug is',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AlbumTegel(
            breedte: 180,
            hoes: (maat) => SizedBox.square(dimension: maat, child: const ColoredBox(color: Colors.teal)),
            titel: 'Plaat',
            onTap: () {},
            schijf: (maat) => SizedBox.square(key: const ValueKey('cd'), dimension: maat),
            onAfspelen: () {},
          ),
        ),
      ),
    ));
    bool zichtbaar() => t
        .widget<Visibility>(find.ancestor(of: find.byKey(const ValueKey('cd')), matching: find.byType(Visibility)))
        .visible;
    expect(find.byKey(const ValueKey('cd')), findsNothing, reason: 'een nieuwe rij bouwt geen cd mee');
    expect(find.byKey(const ValueKey('tegel-afspelen')), findsNothing);
    final muis = await t.createGesture(kind: PointerDeviceKind.mouse);
    await muis.addPointer(location: const Offset(1, 1));
    addTearDown(muis.removePointer);
    await muis.moveTo(t.getCenter(find.byType(AlbumTegel)));
    await t.pump();
    // Eerst opgebouwd in rust: zo heeft het uitschuiven een beginstand.
    expect(find.byKey(const ValueKey('cd')), findsOneWidget);
    expect(zichtbaar(), isFalse);
    final vak = t.getTopLeft(find.byKey(const ValueKey('cd')));
    await t.pump();
    expect(zichtbaar(), isTrue);
    await t.pump(const Duration(milliseconds: 160));
    expect(t.getTopLeft(find.byKey(const ValueKey('cd'))).dx, greaterThan(vak.dx), reason: 'hij schuift, hij springt niet');
    expect(find.byKey(const ValueKey('tegel-afspelen')), findsOneWidget);
    await muis.moveTo(const Offset(1, 1));
    await t.pump();
    expect(zichtbaar(), isTrue, reason: 'hij schuift nog terug');
    await t.pump(const Duration(milliseconds: 500));
    expect(zichtbaar(), isFalse);
    expect(find.byKey(const ValueKey('cd')), findsOneWidget, reason: 'eenmaal gebouwd blijft hij, voor de volgende keer');
    await t.pumpAndSettle();
  });

  test('het etiket van de cd deelt zijn decodering met de hoes', () {
    expect(hoofd, contains('TegelSchijf(etiket: widget.album.cover!, maat: m, decodeerBreedte: decodeWidth(m / .96))'));
  });

  test('de tegel laat de echte cd-scan zien, van schijf en met het gat van de albumpagina', () {
    // Saber, 18-10-2026: "in de album screen moeten de cd afbeeldingen ook zichtbaar zijn".
    expect(hoofd, contains('schijf: a.cover == null ? null : (maat) => _TegelCd(album: a, maat: maat),'));
    final begin = hoofd.indexOf('class _TegelCdState extends State<_TegelCd>');
    final lijf = hoofd.substring(begin, hoofd.indexOf('/// Een album in het raster op Albums.', begin));
    expect(lijf, contains('.artInGeheugen('));
    expect(lijf, contains('.cachedReleaseArt('));
    expect(lijf, isNot(contains('.releaseArt(')), reason: 'aanwijzen mag geen zoektocht op het net starten');
    expect(lijf, contains('clipper: const _DiscClipper()'));
  });

  test('een lege achterkant is geen fout', () {
    // De haak mag null teruggeven: dan haalt de dubbeltik hem zoals vroeger.
    Future<Uint8List?> leeg() async => null;
    expect(leeg(), completion(isNull));
  });
}
