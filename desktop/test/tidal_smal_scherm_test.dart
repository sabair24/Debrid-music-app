/// TIDAL in "Online zoeken" op elk scherm: een gsm (ook liggend), en een groot scherm.
///
/// **Waarom.** Saber, 23-10-2026, met twee schermafdrukken van de gsm: de nummers van "Natural Born Killer EP" stonden
/// er als "Natural Born Ki…", vier keer — het verschil (Original Mix, Extended Mix) staat juist achteraan. En draaide
/// hij de gsm, dan sprong het tabblad terug naar Bladeren en kon hij niet scrollen. *"bij deze app altijd moet
/// rekening houden met kleine schermen, gsm, maar ook grote schermen pc 24 inch, en ook mac en ipad."*
library;

import 'dart:io';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/tidal.dart';
import 'package:debridmusic/tidaler.dart';
import 'package:debridmusic/zoek_geheugen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _plaat = TidalAlbum('a1', 'Natural Born Killer EP', 'Dominion', '2009', '', 4, TidalKwaliteit.cd);
const _titels = [
  'Natural Born Killer (Original Mix)',
  'Natural Born Killer (Extended Mix)',
  'Natural Born Killer (Dub Mix)',
  'Natural Born Killer (Radio Edit)',
];

Future<void> _scherm(WidgetTester t, Size maat, {Key? sleutel}) async {
  t.view.physicalSize = maat;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final cfg = AppSettings();
  final d = DownloadManager(OnlineService(cfg), SoulseekService(cfg), Directory.systemTemp.path, () async {});
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppSettings>.value(value: cfg),
      ChangeNotifierProvider<DownloadManager>.value(value: d),
      ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
      Provider<MusicBrainzService>(create: (_) => MusicBrainzService()),
      Provider<OnlineService>(create: (_) => OnlineService(cfg)),
      Provider<SoulseekService>(create: (_) => SoulseekService(cfg)),
      Provider<TidalService>(create: (_) => TidalService(cfg)),
    ],
    child: MaterialApp(home: Scaffold(body: OnlineSearchScreen(key: sleutel))),
  ));
  await t.pump();
}

void _geheugen() {
  ZoekGeheugen.wis();
  ZoekGeheugen.tab = ZoekTab.tidal;
  ZoekGeheugen.vraag = 'dominion killer';
  ZoekGeheugen.tidalAlbums = const [_plaat];
  ZoekGeheugen.tidalAlbumOpen = 0;
  ZoekGeheugen.tidalAlbumNummers['a1'] = [
    for (var i = 0; i < _titels.length; i++)
      TidalTrack('t$i', _titels[i], 'Dominion', seconden: 245 + i, nummer: i + 1, kwaliteit: TidalKwaliteit.cd),
  ];
}

void main() {
  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('dm_tidal_smal_').path));
  setUp(() {
    // Zoals op de pc: tidaler staat er, dus een plaat klapt open op haar nummers.
    Tidaler.zetVoorToets(pad: 'tidaler', python: 'python');
    _geheugen();
  });
  tearDown(() {
    Tidaler.zetVoorToets();
    ZoekGeheugen.wis();
  });

  for (final breed in [360.0, 411.0]) {
    testWidgets('DE KERN: op $breed punten krijgt de titel de hele breedte, en staat Ophalen eronder', (t) async {
      await _scherm(t, Size(breed, 800));
      final titel = find.text(_titels.first);
      expect(titel, findsOneWidget);
      final kop = t.getRect(titel);
      final kolom = t.getRect(find.ancestor(of: titel, matching: find.byType(Column)).first);
      expect(kop.width, closeTo(kolom.width, 1), reason: 'titel $kop, kolom $kolom');
      expect(t.widget<Text>(titel).maxLines, 3);
      // De duur van dit nummer staat ónder de titel, niet ernaast.
      final duur = t.getRect(find.text('4:05'));
      expect(duur.top, greaterThanOrEqualTo(kop.bottom - 1), reason: 'duur $duur, titel $kop');
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('DE GRENS: op een groot scherm blijft het één rij', (t) async {
    await _scherm(t, const Size(1920, 1080));
    final kop = t.getRect(find.text(_titels.first));
    final duur = t.getRect(find.text('4:05'));
    expect(duur.left, greaterThan(kop.right - 1));
    expect((duur.center.dy - kop.center.dy).abs(), lessThan(6));
    expect(t.takeException(), isNull);
  });

  testWidgets('DE KERN: een draai (het scherm begint opnieuw) houdt TIDAL en de open plaat', (t) async {
    ZoekGeheugen.tab = ZoekTab.bladeren;
    ZoekGeheugen.tidalAlbumOpen = null;
    await _scherm(t, const Size(411, 800), sleutel: const ValueKey('staand'));
    // Alles wat je zelf doet vóór de draai: het tabblad, de plaat openklappen, iets anders intikken.
    await t.tap(find.text('TIDAL'));
    await t.pump();
    await t.tap(find.text('Natural Born Killer EP'));
    await t.pump();
    expect(find.text(_titels.first), findsOneWidget);
    await t.enterText(find.byType(TextField), 'dominion natural');
    await t.pump();
    // Een andere indeling = een nieuw scherm, en het oude is nog niet weg als het nieuwe zijn stand leest.
    await _scherm(t, const Size(800, 411), sleutel: const ValueKey('liggend'));
    expect(find.text('Zoek in TIDAL…'), findsOneWidget, reason: 'het sprong terug naar Bladeren');
    expect(find.text(_titels.first), findsOneWidget, reason: 'de open plaat met haar nummers blijft');
    expect(find.text('dominion natural'), findsOneWidget, reason: 'en wat je net intikte');
  });

  testWidgets('DE KERN: liggend schuift de kop mee weg en scrol je tot het laatste nummer', (t) async {
    await _scherm(t, const Size(800, 360));
    expect(find.byType(NestedScrollView), findsOneWidget);
    final laatste = find.text(_titels.last);
    // Met de vinger over de nummers omhoog, zoals op de gsm: eerst schuift de kop weg, dan de lijst.
    final kopVoor = t.getRect(find.text('Online zoeken')).top;
    await t.drag(find.text(_titels.first), const Offset(0, -600));
    await t.pumpAndSettle();
    expect(t.getRect(laatste).bottom, lessThanOrEqualTo(360), reason: 'het laatste nummer is te bereiken');
    expect(find.text('Online zoeken').evaluate().isEmpty || t.getRect(find.text('Online zoeken')).top < kopVoor, isTrue,
        reason: 'de kop schoof mee weg');
    expect(t.takeException(), isNull);
  });

  testWidgets('staand en op een groot scherm blijft de kop staan', (t) async {
    for (final maat in [const Size(411, 800), const Size(1920, 1080)]) {
      await _scherm(t, maat);
      expect(find.byType(NestedScrollView), findsNothing, reason: '$maat');
    }
  });
}
