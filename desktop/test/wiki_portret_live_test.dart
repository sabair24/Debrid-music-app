@Tags(['live'])
library;

import 'dart:io';

import 'package:debridmusic/paths.dart';
import 'package:debridmusic/wikifotos.dart';
import 'package:flutter_test/flutter_test.dart';

/// METING: wat de Wikipedia-bron van "Foto kiezen" echt oplevert (Saber, 19-10-2026).
/// Draaien: `flutter test --run-skipped --tags live test/wiki_portret_live_test.dart`
void main() {
  setUpAll(() {
    HttpOverrides.global = null;
    setAppDirForTest(Directory.systemTemp.createTempSync('wikiportret').path);
  });

  test('METING: grote foto\'s per artiest', () async {
    for (final (naam, q) in [('Michael Jackson', 'Q2831'), ('Alabina', 'Q4734607'), ('Céline Dion', 'Q5105'), ('Kate Ryan', 'Q234608')]) {
      final uit = await WikiFotoService().portrettenVoor(q);
      // ignore: avoid_print
      print('$naam ($q): ${uit.length} foto\'s; ${uit.take(6).map((p) => '${p.breedte}×${p.hoogte} ${p.bestand}').join(' | ')}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
