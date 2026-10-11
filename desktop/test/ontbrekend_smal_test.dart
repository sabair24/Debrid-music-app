/// Op een gsm staat de titel van een ontbrekend nummer er helemaal, met het label eronder.
///
/// **Waarom.** Saber op 11-10-2026, met de gsm op de albumpagina van Lionel Richie: *"als je naar een
/// album gaat en je open verborgen tracks die niet in men bibliotheek staan zie ik de titels niet door
/// de melding"*. Op de schermafdruk: "Just…", "Run…", "Thre…", "Still …" — het label "niet in
/// bibliotheek" stond NAAST de titel en kreeg zijn volle breedte, de titel wat er overbleef. Gemeten
/// op 360 en 411 punten, de breedtes van een gewone en een grote telefoon.
library;

import 'dart:io';

import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _titel = 'Just Go (feat. Akon)';

Future<void> _rij(WidgetTester t, double breed) async {
  t.view.physicalSize = Size(breed, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final cfg = AppSettings();
  final d = DownloadManager(OnlineService(cfg), SoulseekService(cfg), Directory.systemTemp.path, () async {});
  await t.pumpWidget(ChangeNotifierProvider<DownloadManager>.value(
    value: d,
    child: MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          MissingTrackRow(
            slot: const AlbumSlot(index: 1, official: ChoiceTrack('2', _titel, 215)),
            jobKey: 'lionel-richie|just-go',
            onDownload: () {},
            artiest: 'Lionel Richie',
          ),
        ]),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('dm_ontbrekend_').path));

  for (final breed in [360.0, 411.0]) {
    testWidgets('DE KERN: op $breed punten staat de hele titel er', (t) async {
      await _rij(t, breed);
      // De maat is de BREEDTE die de titel krijgt, niet of hij in de toetsletter past: die letter
      // is in een widgettoets zo'n twee keer breder dan echt. Naast het label kreeg de titel wat er
      // overbleef ("Just…"); nu de hele kolom, en twee regels.
      final kop = t.getRect(find.text(_titel));
      final kolom = t.getRect(find
          .ancestor(of: find.text(_titel), matching: find.byType(Column))
          .first);
      expect(kop.width, closeTo(kolom.width, 1), reason: 'titel $kop, kolom $kolom');
      expect(t.widget<Text>(find.text(_titel)).maxLines, 2);
      // En het label staat eronder, niet ernaast.
      final label = t.getRect(find.text('niet in bibliotheek'));
      expect(label.top, greaterThanOrEqualTo(kop.bottom - 1), reason: 'label $label, titel $kop');
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('DE GRENS: op een breed scherm blijft het label naast de titel', (t) async {
    await _rij(t, 1200);
    final label = t.getRect(find.text('niet in bibliotheek'));
    final kop = t.getRect(find.text(_titel));
    expect(label.left, greaterThan(kop.right - 1), reason: 'daar is plek genoeg en hoort het in één regel');
    expect((label.center.dy - kop.center.dy).abs(), lessThan(4));
  });
}
