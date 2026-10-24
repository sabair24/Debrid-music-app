/// Albums op een tv bouwt alleen de rijen die in beeld komen.
///
/// **Waarom dit bestaat.** Meetronde op de Shield, 24-10-2026 (Saber: "meet daar ook de performance"): Albums openen
/// kostte elke keer één beeld van ~360 ms. Per blok gemeten ([MeetBlok]) bleek waarom: elke rij stond als eigen
/// `SliverToBoxAdapter` in de lijst, en een viewport maakt elk los blok op — ook ver buiten beeld — om de lengte van
/// de pagina te kennen. Een rij opmaken bouwt zijn tegels: 28 rijen en 173 tegels, terwijl er 12 in beeld stonden.
/// Nu is het één `SliverList`, en die maakt alleen de rijen in beeld en de voorraad erachter.
library;

import 'dart:io';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/meetronde.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/tv.dart' show setTvModeForTest;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 26 letters met elk 10 platen: 26 rijen bij sorteren op artiest.
final _albums = [
  for (var l = 0; l < 26; l++)
    for (var i = 0; i < 10; i++)
      Album('Plaat $i', '${String.fromCharCode(65 + l)}rtiest $i', [
        Track(
            path: 'D:\m\$l-$i.flac',
            title: 'Nummer',
            artist: '${String.fromCharCode(65 + l)}rtiest $i',
            album: 'Plaat $i'),
      ]),
];

void main() {
  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('dm_tvrijen_').path));
  tearDown(() {
    setTvModeForTest(false);
    meetrondeLooptVoorToets = false;
  });

  Future<String> open(WidgetTester t) async {
    setTvModeForTest(true);
    t.view.physicalSize = const Size(960, 540);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    meetrondeLooptVoorToets = true;
    blokkenRegel();
    await t.pumpWidget(ChangeNotifierProvider<LibraryStore>(
      create: (_) => LibraryStore(),
      child: MaterialApp(home: Scaffold(body: AlbumsGrid(albums: _albums, sort: AlbumSort.artiest))),
    ));
    return blokkenRegel();
  }

  int keer(String regel, String naam) =>
      int.parse(RegExp('$naam (\d+)×').firstMatch(regel)?.group(1) ?? '0');

  testWidgets('DE KERN: op de Shield alleen de rijen in beeld en de voorraad — niet alle 26', (t) async {
    final regel = await open(t);
    expect(keer(regel, 'Albumrij'), lessThanOrEqualTo(4), reason: regel);
    expect(keer(regel, 'Albumtegel'), lessThanOrEqualTo(4 * 8), reason: regel);
    expect(find.byType(AlbumCard), findsWidgets, reason: 'wat in beeld staat, staat er wel');
  });

  testWidgets('DE GRENS: verder schuiven bouwt de volgende rijen, met hun kop', (t) async {
    await open(t);
    expect(find.text('Z', skipOffstage: false), findsNothing, reason: 'de laatste rij is nog niet gebouwd');
    await t.scrollUntilVisible(find.text('Z'), 600, scrollable: find.byType(Scrollable).first);
    expect(find.text('Z'), findsOneWidget);
  });
}
