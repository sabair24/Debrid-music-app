// De schijf zonder scan: vinyl alleen als de uitgave vinyl is, anders een zilveren cd, met een glans
// die stilstaat terwijl de schijf draait (Saber, 18-10-2026).
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/ui/getekende_schijf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  test('vinyl is vinyl, al het andere en onbekend is een cd', () {
    for (final f in ['Vinyl', '12" Vinyl', '7" Vinyl', 'LP', 'Shellac']) {
      expect(isVinylFormaat(f), isTrue, reason: f);
    }
    for (final f in ['CD', 'File', 'Digital Media', 'Enhanced CD', 'Cassette', '', null]) {
      expect(isVinylFormaat(f), isFalse, reason: '$f');
    }
  });

  test('het formaat van de persing blijft bij de scans, ook na een herstart', () async {
    final d = Directory.systemTemp.createTempSync('dm_schijf_');
    setAppDirForTest(d.path);
    addTearDown(() {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    });
    final dienst = DiscogsService(AppSettings());
    final map = dienst.artMap('Prince', 'Purple Rain', 9, null, null, const {})..createSync(recursive: true);
    File('${map.path}${Platform.pathSeparator}front').writeAsBytesSync(_png);
    File('${map.path}${Platform.pathSeparator}formaat').writeAsStringSync('Vinyl');
    final art = await dienst.cachedReleaseArt('Prince', 'Purple Rain', expectedTracks: 9);
    expect(art?.formaat, 'Vinyl');
    // En een map van vóór deze versie: geen formaat, dus een cd.
    final oud = dienst.artMap('Prince', '1999', 11, null, null, const {})..createSync(recursive: true);
    File('${oud.path}${Platform.pathSeparator}front').writeAsBytesSync(_png);
    final art2 = await dienst.cachedReleaseArt('Prince', '1999', expectedTracks: 11);
    expect(art2?.formaat, isNull);
  });

  test('het formaat wordt ook weggeschreven, naast de herkomst', () {
    final bron = File('lib/discogs.dart').readAsStringSync();
    final begin = bron.indexOf('Future<void> _writeArt(');
    final romp = bron.substring(begin, bron.indexOf('\n  }\n', begin));
    expect(romp, contains("Platform.pathSeparator}formaat').writeAsString(art.formaat!)"));
  });

  testWidgets('cd en vinyl tekenen, met de hoes als etiket', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Row(children: [
        GetekendeCd(label: _png, maat: 200),
        GetekendVinyl(label: _png, maat: 200),
        const CdGlans(maat: 200),
      ]),
    ));
    expect(find.byType(GetekendeCd), findsOneWidget);
    expect(find.byType(GetekendVinyl), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('cd-glans'))), const Size(200, 200));
  });

  test('aangesloten: het licht ligt boven de draaiende schijf en draait niet mee; een scan alleen schaduw', () {
    final bron = File('lib/main.dart').readAsStringSync();
    // Sinds 19-10-2026 via ui/schijf_licht.dart (zie schijf_licht_test.dart): het licht is een broer van
    // spinningDisc, niet zijn kind, en een echte scan krijgt SchijfSoort.scan (alleen de schaduwen).
    final i = bron.indexOf('                spinningDisc,\n                SchijfLichtLaag(');
    expect(i, greaterThan(0));
    final stuk = bron.substring(i, i + 400);
    expect(stuk, contains('soort: disc != null\n                        ? SchijfSoort.scan'));
    expect(stuk, contains('isVinylFormaat(_art?.formaat)\n                            ? SchijfSoort.vinyl'));
    expect(bron, contains('_GetekendeSchijf(label: front, maat: s * .92, vinyl: isVinylFormaat(_art?.formaat))'));
  });
}
