/// "Zoeken met TIDAL" in elk menu, naast "Zoeken met Soulseek" (Saber, 25-10-2026, met een schermafdruk van het menu
/// op een nummer van Tina Arena: "daarna wil ik ook in de menu overal, zoek met tidal optie hebben").
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

const _plaat = TidalAlbum('a1', 'Un Autre Univers', 'Tina Arena', '2005', '', 12, TidalKwaliteit.cd);

Future<void> _scherm(WidgetTester t, {String? tidalVraag}) async {
  t.view.physicalSize = const Size(1280, 900);
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
    child: MaterialApp(home: Scaffold(body: OnlineSearchScreen(tidalVraag: tidalVraag))),
  ));
  await t.pump();
}

void main() {
  final gevraagd = <String>[];
  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('dm_zoek_tidal_').path));
  setUp(() {
    // Zoals op de pc: tidaler staat er. Het zoeken zelf is een nep: echt zoeken start Python.
    Tidaler.zetVoorToets(pad: 'tidaler', python: 'python');
    gevraagd.clear();
    tidalCatalogusZoeker = (v) async {
      gevraagd.add(v);
      return const TidalZoekResultaat([_plaat], []);
    };
    ZoekGeheugen.wis();
    ZoekGeheugen.tab = ZoekTab.bladeren;
    ZoekGeheugen.vraag = 'iets van eerder';
  });
  tearDown(() {
    tidalCatalogusZoeker = zoekCatalogusOpTidal;
    Tidaler.zetVoorToets();
    ZoekGeheugen.wis();
  });

  testWidgets('DE KERN: vanuit het menu meteen op TIDAL, met de vraag ingevuld, en er is gezocht', (t) async {
    await _scherm(t, tidalVraag: 'Tina Arena Aller plus haut');
    await t.pump();
    await t.pump();
    expect(gevraagd, ['Tina Arena Aller plus haut'], reason: 'één keer gezocht, op wat het menu meegaf');
    expect(t.widget<TextField>(find.byType(TextField).first).controller!.text, 'Tina Arena Aller plus haut');
    expect(ZoekGeheugen.tab, ZoekTab.tidal);
    expect(find.text('Un Autre Univers'), findsOneWidget, reason: 'de uitslag van TIDAL staat er');
    expect(t.takeException(), isNull);
  });

  testWidgets('DE GRENS: zonder vraag begint het scherm waar je was, en zoekt het niet vanzelf', (t) async {
    await _scherm(t);
    await t.pump();
    expect(gevraagd, isEmpty);
    expect(ZoekGeheugen.tab, ZoekTab.bladeren);
    expect(t.widget<TextField>(find.byType(TextField).first).controller!.text, 'iets van eerder');
  });

  test('aangesloten: in de drie menu\'s (nummer, ontbrekend nummer, plaat), ook op de tv', () {
    final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final regels = RegExp(r"MenuRegel\(Icons\.waves_rounded, 'Zoeken met TIDAL', \(\) => openOp\(nav, \(_\) => _tidalPagina\(")
        .allMatches(m)
        .length;
    expect(regels, 3);
    expect(m, isNot(contains("if (!isTv) MenuRegel(Icons.waves_rounded, 'Zoeken met TIDAL'")),
        reason: 'de pc zoekt voor de Shield, dus ook daar');
    // Elk direct onder de Soulseek-regel van hetzelfde menu.
    for (final soulseek in [
      '_bronnenPagina(slot.title, vraag, tags: tags))),\n',
      '_bronnenPagina(t.title, vraag, tags: vervangTags))),\n',
      '_bronnenPagina(a.title, vraag))),\n',
    ]) {
      final i = m.indexOf(soulseek);
      expect(i, greaterThan(0), reason: soulseek);
      expect(m.substring(i + soulseek.length, i + soulseek.length + 80), contains("'Zoeken met TIDAL'"), reason: soulseek);
    }
    expect(m, contains('      body: OnlineSearchScreen(tidalVraag: vraag),'));
  });
}
